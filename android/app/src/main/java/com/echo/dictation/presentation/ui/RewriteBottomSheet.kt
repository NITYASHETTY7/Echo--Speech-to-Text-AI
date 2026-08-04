package com.echo.dictation.presentation.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.automirrored.outlined.FormatListBulleted
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Summarize
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.echo.dictation.domain.ai.PromptTemplate
import com.echo.dictation.domain.ai.PromptTemplateRepository
import com.echo.dictation.presentation.theme.CardColor
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.OutlineColor
import com.echo.dictation.presentation.theme.Primary
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RewriteBottomSheet(
    customPromptText: String,
    onCustomPromptChanged: (String) -> Unit,
    onPresetSelected: (String) -> Unit,
    onCustomPromptSubmit: () -> Unit,
    onDismiss: () -> Unit,
    outputLanguage: String = "English",
    onOutputLanguageChanged: (String) -> Unit = {},
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    var selectedTab by remember { mutableIntStateOf(0) }
    var showOutputLanguagePicker by remember { mutableStateOf(false) }

    if (showOutputLanguagePicker) {
        TranslationLanguagePickerDialog(
            onLanguageSelected = { language ->
                showOutputLanguagePicker = false
                onOutputLanguageChanged(language)
            },
            onDismiss = { showOutputLanguagePicker = false }
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
                .padding(horizontal = 20.dp)
        ) {
            // ── Header: title + global language selector ───────────────────
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(
                        imageVector = Icons.Default.AutoAwesome,
                        contentDescription = null,
                        tint = Primary,
                        modifier = Modifier.size(22.dp)
                    )
                    Text(
                        text = "AI Rewrite Engine",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }

                // Compact output-language chip: 🌐 English ▼
                androidx.compose.foundation.layout.Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(Primary.copy(alpha = 0.10f))
                        .clickable { showOutputLanguagePicker = true }
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Language,
                        contentDescription = "Output language",
                        tint = Primary,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = outputLanguage,
                        style = MaterialTheme.typography.labelMedium,
                        color = Primary,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Icon(
                        imageVector = Icons.Default.ArrowDropDown,
                        contentDescription = null,
                        tint = Primary,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }

            Spacer(Modifier.height(12.dp))

            TabRow(
                selectedTabIndex = selectedTab,
                containerColor = Color.Transparent,
                contentColor = Primary,
            ) {
                Tab(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    text = { Text("Presets", fontWeight = FontWeight.SemiBold) }
                )
                Tab(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    text = { Text("Custom Prompt", fontWeight = FontWeight.SemiBold) }
                )
            }

            Spacer(Modifier.height(16.dp))

            if (selectedTab == 0) {
                PresetsTab(
                    onPresetSelected = { id -> onPresetSelected(id) }
                )
            } else {
                CustomPromptTab(
                    customPromptText = customPromptText,
                    onCustomPromptChanged = onCustomPromptChanged,
                    onSubmit = onCustomPromptSubmit
                )
            }

            Spacer(Modifier.height(20.dp))
        }
    }
}

@Composable
private fun PresetsTab(onPresetSelected: (String) -> Unit) {
    val repository = remember { PromptTemplateRepository() }
    val templates = repository.getAllTemplates()
    LazyColumn(
        contentPadding = PaddingValues(bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(items = templates, key = { it.id }) { template ->
            PresetCard(template = template, onClick = { onPresetSelected(template.id) })
        }
    }
}

@Composable
private fun PresetCard(template: PromptTemplate, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = CardColor),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(Primary.copy(alpha = 0.1f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = iconForTemplate(template.id),
                    contentDescription = null,
                    tint = Primary,
                    modifier = Modifier.size(20.dp),
                )
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = template.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = template.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = OnSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun CustomPromptTab(
    customPromptText: String,
    onCustomPromptChanged: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val maxChars = 500
    val isValid = customPromptText.trim().isNotBlank() && customPromptText.length <= maxChars

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = customPromptText,
            onValueChange = onCustomPromptChanged,
            modifier = Modifier
                .fillMaxWidth()
                .height(130.dp),
            placeholder = { Text("e.g. Rewrite as a formal customer email or legal summary...") },
            shape = RoundedCornerShape(16.dp),
            maxLines = 4,
            supportingText = {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    if (customPromptText.length > maxChars) {
                        Text("Maximum 500 characters", color = MaterialTheme.colorScheme.error)
                    } else {
                        Spacer(Modifier.width(1.dp))
                    }
                    Text("${customPromptText.length} / $maxChars", style = MaterialTheme.typography.bodySmall)
                }
            }
        )

        AnimatedVisibility(visible = customPromptText.trim().isNotBlank()) {
            Card(
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = Primary.copy(alpha = 0.05f))
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text("Prompt Preview", style = MaterialTheme.typography.labelSmall, color = Primary, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    Text("\"${customPromptText.trim()}\"", style = MaterialTheme.typography.bodySmall, color = OnSurfaceVariant)
                }
            }
        }

        Button(
            onClick = onSubmit,
            enabled = isValid,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Primary,
                disabledContainerColor = Primary.copy(alpha = 0.3f),
            ),
            contentPadding = PaddingValues(vertical = 14.dp),
        ) {
            Icon(imageVector = Icons.AutoMirrored.Filled.Send, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Generate Rewrite", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
        }
    }
}

private fun iconForTemplate(id: String): ImageVector = when (id) {
    "professional"   -> Icons.AutoMirrored.Outlined.Article
    "summary"        -> Icons.Outlined.Summarize
    "meeting_notes"  -> Icons.AutoMirrored.Outlined.Notes
    "bullet_points"  -> Icons.AutoMirrored.Outlined.FormatListBulleted
    "email"          -> Icons.Outlined.Email
    "action_items"   -> Icons.Outlined.Checklist
    "translate"      -> Icons.Outlined.Language
    else             -> Icons.Outlined.Edit
}

@Composable
private fun TranslationLanguagePickerDialog(
    onLanguageSelected: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val languages = listOf(
        "English", "Spanish", "French", "German", "Italian", "Portuguese",
        "Hindi", "Kannada", "Tamil", "Telugu", "Malayalam",
        "Japanese", "Korean", "Chinese (Simplified)", "Arabic", "Russian",
    )

    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        shape = RoundedCornerShape(24.dp),
        title = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Outlined.Language, contentDescription = null, tint = Primary, modifier = Modifier.size(20.dp))
                Text("Select Language", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            }
        },
        text = {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(4.dp),
                contentPadding = PaddingValues(vertical = 4.dp),
            ) {
                items(items = languages) { language ->
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .clickable { onLanguageSelected(language) }
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                    ) {
                        Text(
                            text = language,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}

