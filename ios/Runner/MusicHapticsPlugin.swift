import Flutter
import Foundation
import MediaAccessibility
import MediaPlayer

/// Publishes the playing recording's ISRC into the Now Playing entry so iOS
/// renders its authored Music Haptics track.
///
/// The Dart layer announces every track change over the method channel. The
/// ISRC itself is not in the metadata Spotube has, so it is recovered from
/// MusicBrainz and confirmed against the system's own availability check — a
/// candidate the system has no haptic track for is never published, and a
/// recording that matches nothing stays unpublished rather than risking a
/// wrong recording's haptics.
///
/// Music Haptics shipped in iOS 18 while the app targets older systems, so the
/// class is availability-gated; on earlier iOS the channel simply has no
/// handler and the Dart calls no-op.
@available(iOS 18.0, *)
public class MusicHapticsPlugin: NSObject, FlutterPlugin {
    private static let channelName = "oss.krtirtho.spotube.music_haptics"
    private static let userAgent = "SpotubeMusicHaptics/1.0 (personal build; MusicBrainz compliant)"

    /// Written on the main thread from channel events; read from the lookup
    /// task after hopping back to main, so it stays single-threaded.
    private var generation = 0
    private var currentKey: String?
    private var reassertTimer: Timer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: MusicHapticsPlugin.channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(MusicHapticsPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "trackChanged":
            let arguments = call.arguments as? [String: Any]
            let title = arguments?["title"] as? String ?? ""
            let artist = arguments?["artist"] as? String ?? ""
            let durationMs = (arguments?["durationMs"] as? NSNumber)?.doubleValue ?? 0
            result(nil)

            generation += 1
            let currentGeneration = generation
            let key = "\(artist)|\(title)".lowercased()
            guard key != currentKey else { return }
            currentKey = key

            // Drop the previous recording's code at once so a skip cannot
            // leave the last track's haptics dangling on the new one.
            stopReasserting()
            publish(isrc: nil)

            Task { [weak self] in
                await self?.resolveAndPublish(
                    title: title,
                    artist: artist,
                    durationMs: durationMs,
                    generation: currentGeneration
                )
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Lookup

    private struct SearchResponse: Decodable {
        struct Recording: Decodable {
            let id: String
            let score: Int?
            let length: Int?   // milliseconds
        }
        let recordings: [Recording]?
    }

    private struct RecordingResponse: Decodable {
        let isrcs: [String]?
    }

    private func resolveAndPublish(title: String, artist: String, durationMs: Double, generation: Int) async {
        // The system feature is the person's switch; with it off there is
        // nothing to match and no reason to ask MusicBrainz.
        guard MAMusicHapticsManager.shared.isActive else { return }

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(title)\" AND artist:\"\(artist)\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components?.url,
              let data = await get(url),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return }

        // Length-matched recordings first, then only MusicBrainz's own strong
        // scores — the same correctness gate as a hand-typed code.
        let sorted = (decoded.recordings ?? []).sorted { lhs, rhs in
            let lhsClose = lhs.length.map { abs(Double($0) - durationMs) < 5_000 } ?? false
            let rhsClose = rhs.length.map { abs(Double($0) - durationMs) < 5_000 } ?? false
            if lhsClose != rhsClose { return lhsClose }
            return (lhs.score ?? 0) > (rhs.score ?? 0)
        }
        let candidates = sorted.filter { recording in
            recording.length.map { abs(Double($0) - durationMs) < 5_000 } ?? false
        }
        let strong = sorted.filter { ($0.score ?? 0) >= 85 }
        let chosen = candidates.isEmpty ? strong : candidates

        for recording in chosen.prefix(2) {
            try? await Task.sleep(nanoseconds: 1_100_000_000)   // MusicBrainz: ~1 req/s
            guard let isrcs = await isrcs(forRecording: recording.id) else { continue }
            for isrc in isrcs {
                let available = (try? await MAMusicHapticsManager.shared
                    .isHapticTrackAvailable(forMediaMatching: isrc)) ?? false
                if available {
                    await MainActor.run { [weak self] in
                        self?.finishPublish(isrc: isrc, generation: generation)
                    }
                    return
                }
            }
        }
    }

    private func isrcs(forRecording mbid: String) async -> [String]? {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/\(mbid)")
        components?.queryItems = [
            URLQueryItem(name: "inc", value: "isrcs"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        guard let url = components?.url,
              let data = await get(url),
              let decoded = try? JSONDecoder().decode(RecordingResponse.self, from: data)
        else { return nil }

        return (decoded.isrcs ?? []).compactMap { Self.canonicalize($0) }
    }

    private func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return data
    }

    /// 12 characters: two-letter country, three-character registrant, two-digit
    /// year, seven-digit designation. Anything else can never match.
    static func canonicalize(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 12,
              cleaned.wholeMatch(of: /[A-Z]{2}[A-Z0-9]{3}[0-9]{7}/) != nil
        else { return nil }
        return cleaned
    }

    // MARK: - Publishing

    /// Runs on the main thread. Stale lookups are recognised by generation and
    /// discarded, so a skip during a lookup publishes nothing.
    private func finishPublish(isrc: String, generation: Int) {
        guard self.generation == generation else { return }
        publish(isrc: isrc)
        startReasserting(isrc: isrc)
    }

    private func publish(isrc: String?) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        if let isrc {
            info[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] = isrc
        } else {
            info.removeValue(forKey: MPNowPlayingInfoPropertyInternationalStandardRecordingCode)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// audio_service rewrites parts of the Now Playing entry as playback
    /// progresses; a light heartbeat re-adds the code if a rewrite dropped it.
    private func startReasserting(isrc: String) {
        stopReasserting()
        reassertTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
            if info[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] == nil {
                var updated = info
                updated[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] = isrc
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
    }

    private func stopReasserting() {
        reassertTimer?.invalidate()
        reassertTimer = nil
    }
}
