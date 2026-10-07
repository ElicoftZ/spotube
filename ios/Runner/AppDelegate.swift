import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Add this to get Documents directory path
    if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
        UserDefaults.standard.set(documentsPath, forKey: "download_path")
    }
    
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 18.0, *) {
      if let registrar = self.registrar(forPlugin: "MusicHapticsPlugin") {
        MusicHapticsPlugin.register(with: registrar)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
