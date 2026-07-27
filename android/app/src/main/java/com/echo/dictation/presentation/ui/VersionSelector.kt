package com.echo.dictation.presentation.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.ai.VersionType
import com.echo.dictation.presentation.theme.CardColor
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.OutlineColor
import com.echo.dictation.presentation.theme.Primary
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun VersionSelector(
    versions: List<TranscriptVersion>,
    activeIndex: Int,
    onSelectIndex: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (versions.isEmpty()) return

    // Single version fallback — display "Original Transcript" header
    if (versions.size <= 1) {
        Row(
            modifier = modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.Mic,
                contentDescription = null,
                tint = Primary,
                modifier = Modifier.size(16.dp)
            )
            Text(
                text = "Original Transcript",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
        return
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        versions.forEachIndexed { index, version ->
            VersionChip(
                version = version,
                selected = index == activeIndex,
                onClick = { onSelectIndex(index) },
            )
        }
    }
}

@Composable
private fun VersionChip(
    version: TranscriptVersion,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val containerModifier = Modifier
        .clip(RoundedCornerShape(20.dp))
        .then(
            if (selected) {
                Modifier.background(Brush.linearGradient(listOf(PrimaryColor, PrimaryVariant)))
            } else {
                Modifier
                    .background(CardColor)
                    .border(1.dp, OutlineColor, RoundedCornerShape(20.dp))
            }
        )
        .clickable(onClick = onClick)
        .padding(horizontal = 14.dp, vertical = 8.dp)

    val timeFormatted = remember(version.createdAt) {
        SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(version.createdAt))
    }

    Box(
        modifier = containerModifier,
        contentAlignment = Alignment.Center,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = if (version.versionType == VersionType.Original)
                    Icons.Outlined.Mic
                else
                    Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = if (selected) Color.White else Primary,
                modifier = Modifier.size(14.dp),
            )
            Column {
                Text(
                    text = version.versionType.displayName,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (selected) Color.White else OnSurfaceVariant,
                )
            }
            Text(
                text = "• $timeFormatted",
                style = MaterialTheme.typography.bodySmall,
                color = if (selected) Color.White.copy(alpha = 0.8f) else OnSurfaceVariant.copy(alpha = 0.6f),
            )
        }
    }
}

