package com.echo.dictation.presentation.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.Primary

/**
 * Snooze duration options presented to the user. [SnoozeDuration.Indefinite] persists
 * `Long.MAX_VALUE` in [com.echo.dictation.core.input.SnoozeManager] and is only cleared
 * by "Resume Now" / "Resume Floating Pill".
 */
sealed interface SnoozeDuration {
    data object FifteenMinutes : SnoozeDuration
    data object ThirtyMinutes : SnoozeDuration
    data object OneHour : SnoozeDuration
    data object TwoHours : SnoozeDuration
    /** User-entered custom duration, in minutes (> 0). */
    data class Custom(val minutes: Int) : SnoozeDuration
    data object Indefinite : SnoozeDuration

    companion object {
        const val FIFTEEN_MIN_MS = 15 * 60 * 1000L
        const val THIRTY_MIN_MS  = 30 * 60 * 1000L
        const val ONE_HOUR_MS    = 60 * 60 * 1000L
        const val TWO_HOURS_MS   = 2 * 60 * 60 * 1000L
    }
}

/**
 * Bottom sheet offering Floating Pill snooze durations. Shared between the Settings
 * screen entry point and the pill's own long-press action.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SnoozeOptionsBottomSheet(
    onDurationSelected: (SnoozeDuration) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var showCustomDialog by remember { mutableStateOf(false) }

    if (showCustomDialog) {
        CustomSnoozeDurationDialog(
            onConfirm = { minutes ->
                showCustomDialog = false
                onDurationSelected(SnoozeDuration.Custom(minutes))
            },
            onDismiss = { showCustomDialog = false },
        )
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        containerColor = MaterialTheme.colorScheme.surface,
        tonalElevation = 6.dp,
        dragHandle = {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp, bottom = 4.dp),
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .width(40.dp)
                        .height(4.dp)
                        .clip(CircleShape)
                        .background(OnSurfaceVariant.copy(alpha = 0.4f))
                )
            }
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Bedtime,
                    contentDescription = null,
                    tint = Primary,
                    modifier = Modifier.height(22.dp),
                )
                Text(
                    text = "Snooze Floating Pill",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                )
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = "The pill will stay hidden even if a text field or the keyboard becomes active. Permissions stay untouched.",
                style = MaterialTheme.typography.bodySmall,
                color = OnSurfaceVariant,
            )
            Spacer(Modifier.height(16.dp))

            SnoozeOptionRow("15 Minutes") { onDurationSelected(SnoozeDuration.FifteenMinutes) }
            SnoozeOptionRow("30 Minutes") { onDurationSelected(SnoozeDuration.ThirtyMinutes) }
            SnoozeOptionRow("1 Hour") { onDurationSelected(SnoozeDuration.OneHour) }
            SnoozeOptionRow("2 Hours") { onDurationSelected(SnoozeDuration.TwoHours) }
            SnoozeOptionRow("Custom…") { showCustomDialog = true }
            SnoozeOptionRow("Until Manually Enabled") { onDurationSelected(SnoozeDuration.Indefinite) }

            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun SnoozeOptionRow(label: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
        )
        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = OnSurfaceVariant,
        )
    }
}

/**
 * Simple numeric-input dialog for a custom snooze duration in minutes.
 * Shared by the pill's Snooze sheet and the Settings "Default Snooze Duration" picker.
 */
@Composable
fun CustomSnoozeDurationDialog(
    onConfirm: (minutes: Int) -> Unit,
    onDismiss: () -> Unit,
    initialMinutes: Int = 45,
) {
    var text by remember { mutableStateOf(initialMinutes.toString()) }
    val minutes = text.toIntOrNull()
    val isValid = minutes != null && minutes > 0 && minutes <= MAX_CUSTOM_MINUTES

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Custom Snooze Duration") },
        text = {
            Column {
                Text(
                    text = "Enter a duration in minutes (1–$MAX_CUSTOM_MINUTES).",
                    style = MaterialTheme.typography.bodySmall,
                    color = OnSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { input -> text = input.filter { it.isDigit() }.take(4) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    label = { Text("Minutes") },
                    isError = text.isNotEmpty() && !isValid,
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = isValid,
                onClick = { if (minutes != null) onConfirm(minutes) },
            ) { Text("Snooze") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

private const val MAX_CUSTOM_MINUTES = 24 * 60 // cap at 24 hours

/** Maps a [SnoozeDuration] selection to a millisecond duration, or null for indefinite. */
fun SnoozeDuration.toDurationMsOrNull(): Long? = when (this) {
    SnoozeDuration.FifteenMinutes -> SnoozeDuration.FIFTEEN_MIN_MS
    SnoozeDuration.ThirtyMinutes  -> SnoozeDuration.THIRTY_MIN_MS
    SnoozeDuration.OneHour        -> SnoozeDuration.ONE_HOUR_MS
    SnoozeDuration.TwoHours       -> SnoozeDuration.TWO_HOURS_MS
    is SnoozeDuration.Custom      -> this.minutes * 60 * 1000L
    SnoozeDuration.Indefinite     -> null
}

/** Human-readable label for a [SnoozeDuration], used in dropdowns/settings. */
fun SnoozeDuration.label(): String = when (this) {
    SnoozeDuration.FifteenMinutes -> "15 minutes"
    SnoozeDuration.ThirtyMinutes  -> "30 minutes"
    SnoozeDuration.OneHour        -> "1 hour"
    SnoozeDuration.TwoHours       -> "2 hours"
    is SnoozeDuration.Custom      -> "Custom (${this.minutes} min)"
    SnoozeDuration.Indefinite     -> "Until Manually Enabled"
}

/** Reconstructs a [SnoozeDuration] from a persisted millisecond value (best-effort match). */
fun snoozeDurationFromMs(ms: Long): SnoozeDuration = when (ms) {
    SnoozeDuration.FIFTEEN_MIN_MS -> SnoozeDuration.FifteenMinutes
    SnoozeDuration.THIRTY_MIN_MS  -> SnoozeDuration.ThirtyMinutes
    SnoozeDuration.ONE_HOUR_MS    -> SnoozeDuration.OneHour
    SnoozeDuration.TWO_HOURS_MS   -> SnoozeDuration.TwoHours
    Long.MAX_VALUE                -> SnoozeDuration.Indefinite
    else                           -> SnoozeDuration.Custom((ms / 60_000L).toInt().coerceAtLeast(1))
}
