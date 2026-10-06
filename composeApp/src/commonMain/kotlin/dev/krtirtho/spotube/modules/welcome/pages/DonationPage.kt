package dev.krtirtho.spotube.modules.welcome.pages

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dev.krtirtho.spotube.core.ui.base.OutlineButton
import dev.krtirtho.spotube.modules.welcome.DonationOption
import org.jetbrains.compose.resources.stringResource
import spotube.composeapp.generated.resources.*

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DonationPage(
    donations: List<DonationOption>,
    onDonate: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            stringResource(Res.string.welcome_donate_quiet_title),
            style = MaterialTheme.typography.displaySmall.copy(fontFamily = FontFamily.Serif),
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(20.dp))
        Text(
            stringResource(Res.string.welcome_donate_letter),
            modifier = Modifier.widthIn(max = 540.dp),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(32.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            donations.forEach { option ->
                OutlineButton(onClick = { onDonate(option.url) }) {
                    Icon(
                        option.icon, null, Modifier.size(24.dp),
                        tint = if (option.id == "patreon") MaterialTheme.colorScheme.onSurface else Color.Unspecified,
                    )
                    Text(stringResource(option.title))
                }
            }
        }
        Spacer(Modifier.height(24.dp))
        Text(
            stringResource(Res.string.welcome_donate_optional),
            modifier = Modifier.widthIn(max = 500.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}
