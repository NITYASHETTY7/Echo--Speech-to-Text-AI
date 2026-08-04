package com.echo.dictation.presentation.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.TextSnippet
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.dictation.domain.ai.JobStatus
import com.echo.dictation.domain.model.Transcription
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.presentation.ai.AIViewModel
import com.echo.dictation.presentation.theme.CardColor
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.Primary
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class TranscriptionDetailViewModel @Inject constructor(
    private val repository: TranscriptionRepository
) : ViewModel() {
    fun deleteTranscription(id: String, onComplete: () -> Unit) {
        viewModelScope.launch {
            repository.delete(id)
            onComplete()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TranscriptionDetailBottomSheet(
    transcription: Transcription,
    onDismiss: () -> Unit,
    onCopied: (() -> Unit)? = null,
    viewModel: TranscriptionDetailViewModel = hiltViewModel(),
    aiViewModel: AIViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    var showDeleteDialog by remember { mutableStateOf(false) }

    val aiState by aiViewModel.state.collectAsState()
    val snackbarState = remember { SnackbarHostState() }

    LaunchedEffect(transcription.id) {
        aiViewModel.loadTranscript(transcription.id)
    }

    LaunchedEffect(aiState.successMessage) {
        aiState.successMessage?.let { msg ->
            snackbarState.showSnackbar(msg, duration = SnackbarDuration.Short)
            aiViewModel.dismissSuccess()
        }
    }
    LaunchedEffect(aiState.errorMessage) {
        aiState.errorMessage?.let { msg ->
            snackbarState.showSnackbar("Error: $msg", duration = SnackbarDuration.Long)
            aiViewModel.dismissError()
        }
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
            SheetHeader(
                transcription = transcription,
                context = context,
                onCopy = {
                    // For Original version, copy the immutable spoken-language text;
                    // for AI versions, copy the processed content.
                    val activeType = aiState.activeVersion?.versionType
                    val textToCopy = if (activeType == null || activeType == com.echo.dictation.domain.ai.VersionType.Original) {
                        transcription.rawTranscript ?: transcription.text
                    } else {
                        aiState.activeVersion?.content ?: transcription.text
                    }
                    copyToClipboard(context, textToCopy)
                    onCopied?.invoke()
                },
                onShare = {
                    val activeType = aiState.activeVersion?.versionType
                    val textToShare = if (activeType == null || activeType == com.echo.dictation.domain.ai.VersionType.Original) {
                        transcription.rawTranscript ?: transcription.text
                    } else {
                        aiState.activeVersion?.content ?: transcription.text
                    }
                    shareText(context, textToShare)
                },
                onDelete = { showDeleteDialog = true }
            )

            Spacer(Modifier.height(4.dp))
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant,
                thickness = 0.5.dp
            )

            // Version selector bar
            VersionSelector(
                versions = aiState.versions,
                activeIndex = aiState.activeIndex,
                onSelectIndex = { aiViewModel.selectVersion(it) },
            )

            // AIJob Status Banner
            val latestJob = aiState.latestJob
            if (latestJob != null && latestJob.status != JobStatus.COMPLETED) {
                JobStatusBanner(
                    job = latestJob,
                    onRetry = {
                        val retrySource = aiState.activeVersion?.content ?: transcription.text
                        aiViewModel.retryFailedJob(transcription.id, retrySource)
                    }
                )
                Spacer(Modifier.height(8.dp))
            }

            Spacer(Modifier.height(8.dp))

            // Active transcript card.
            // For the Original version, always display rawTranscript (the immutable
            // STT output in the spoken language). Fall back to transcription.text for
            // rows created before rawTranscript was introduced (backward compat).
            // For every AI-generated version, use the version's processed content.
            val activeVersionType = aiState.activeVersion?.versionType
            val displayText = when {
                activeVersionType == null || activeVersionType == com.echo.dictation.domain.ai.VersionType.Original ->
                    transcription.rawTranscript ?: transcription.text
                else ->
                    aiState.activeVersion?.content ?: transcription.text
            }
            TranscriptCard(text = displayText, isAiVersion = activeVersionType != null && activeVersionType != com.echo.dictation.domain.ai.VersionType.Original)

            Spacer(Modifier.height(12.dp))

            // AI loading indicator
            AnimatedVisibility(
                visible = aiState.isLoading,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    modifier = Modifier.padding(vertical = 4.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = Primary,
                        strokeWidth = 2.dp,
                    )
                    Text(
                        "Processing AI rewrite...",
                        style = MaterialTheme.typography.bodySmall,
                        color = OnSurfaceVariant,
                    )
                }
            }

            // Rewrite button
            Button(
                onClick = { aiViewModel.showRewriteSheet() },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Primary.copy(alpha = 0.12f),
                    contentColor = Primary,
                ),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 14.dp),
                enabled = !aiState.isLoading,
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = "Rewrite",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(8.dp))
            ModelChip(model = transcription.model)
            Spacer(Modifier.height(20.dp))
        }
    }

    if (aiState.isRewriteSheetVisible) {
        // The source text for rewrites: use the currently active AI version content
        // if one is selected, otherwise fall back to rawTranscript (spoken language)
        // or transcription.text for backward compat.
        val activeType = aiState.activeVersion?.versionType
        val rewriteSourceText = if (activeType != null && activeType != com.echo.dictation.domain.ai.VersionType.Original) {
            aiState.activeVersion?.content ?: transcription.text
        } else {
            transcription.rawTranscript ?: transcription.text
        }
        RewriteBottomSheet(
            customPromptText = aiState.customPromptText,
            onCustomPromptChanged = { aiViewModel.onCustomPromptChanged(it) },
            onPresetSelected = { templateId -> aiViewModel.applyPreset(transcription.id, rewriteSourceText, templateId) },
            onCustomPromptSubmit = { aiViewModel.applyCustomPrompt(transcription.id, rewriteSourceText) },
            onDismiss = { aiViewModel.hideRewriteSheet() },
            outputLanguage = aiState.outputLanguage,
            onOutputLanguageChanged = { aiViewModel.setOutputLanguage(it) },
        )
    }

    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            shape = RoundedCornerShape(24.dp),
            title = { Text("Delete transcription?") },
            text = { Text("This will permanently delete this transcription and all its AI versions.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteDialog = false
                        viewModel.deleteTranscription(transcription.id) { onDismiss() }
                    }
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) { Text("Cancel") }
            }
        )
    }
}

@Composable
private fun JobStatusBanner(
    job: com.echo.dictation.domain.ai.AIJob,
    onRetry: () -> Unit
) {
    val isFailed = job.status == JobStatus.FAILED
    val containerColor = if (isFailed) MaterialTheme.colorScheme.errorContainer else Primary.copy(alpha = 0.1f)
    val contentColor = if (isFailed) MaterialTheme.colorScheme.onErrorContainer else Primary

    Card(
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = containerColor),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(
                imageVector = if (isFailed) Icons.Outlined.ErrorOutline else Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = contentColor,
                modifier = Modifier.size(20.dp)
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "AI Job: ${job.status.displayName}",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                    color = contentColor
                )
                if (job.errorMessage != null) {
                    Text(
                        text = job.errorMessage,
                        style = MaterialTheme.typography.bodySmall,
                        color = contentColor.copy(alpha = 0.8f)
                    )
                }
            }
            if (isFailed) {
                OutlinedButton(
                    onClick = onRetry,
                    shape = RoundedCornerShape(8.dp),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                ) {
                    Icon(imageVector = Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Retry", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }
}

@Composable
private fun SheetHeader(
    transcription: Transcription,
    context: Context,
    onCopy: () -> Unit,
    onShare: () -> Unit,
    onDelete: () -> Unit,
) {
    val formattedTime = remember(transcription.timestamp) {
        SimpleDateFormat("EEE, d MMM yyyy • HH:mm", Locale.getDefault()).format(Date(transcription.timestamp))
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = formattedTime,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "${transcription.text.split("\\s+".toRegex()).filter { it.isNotBlank() }.size} words",
                style = MaterialTheme.typography.bodySmall,
                color = OnSurfaceVariant,
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            IconButton(onClick = onCopy) {
                Icon(imageVector = Icons.Default.ContentCopy, contentDescription = "Copy text", tint = Primary)
            }
            IconButton(onClick = onShare) {
                Icon(imageVector = Icons.Default.Share, contentDescription = "Share text", tint = Primary)
            }
            IconButton(onClick = onDelete) {
                Icon(imageVector = Icons.Default.Delete, contentDescription = "Delete transcription", tint = MaterialTheme.colorScheme.error)
            }
        }
    }
}

@Composable
private fun TranscriptCard(text: String, isAiVersion: Boolean = false) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(200.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = CardColor),
    ) {
        Box(
            modifier = Modifier
                .padding(16.dp)
                .verticalScroll(rememberScrollState())
        ) {
            if (isAiVersion) {
                // AI-generated versions may contain markdown — render it as rich text.
                val annotatedText = remember(text) {
                    com.echo.dictation.presentation.ui.util.parseMarkdownToAnnotatedString(
                        text.ifEmpty { "(Empty transcript)" }
                    )
                }
                Text(
                    text = annotatedText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    lineHeight = MaterialTheme.typography.bodyMedium.lineHeight * 1.3f,
                )
            } else {
                // Original transcript: always display as plain text so raw spoken
                // language (e.g. Hindi, Tamil) is never altered by markdown parsing.
                Text(
                    text = text.ifEmpty { "(Empty transcript)" },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    lineHeight = MaterialTheme.typography.bodyMedium.lineHeight * 1.3f,
                )
            }
        }
    }
}

@Composable
private fun ModelChip(model: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = Icons.Outlined.TextSnippet,
            contentDescription = null,
            tint = OnSurfaceVariant,
            modifier = Modifier.size(14.dp),
        )
        Text(
            text = "Model: $model",
            style = MaterialTheme.typography.labelSmall,
            color = OnSurfaceVariant,
        )
    }
}

private fun copyToClipboard(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = ClipData.newPlainText("Transcription", text)
    clipboard.setPrimaryClip(clip)
    Toast.makeText(context, "Copied to clipboard", Toast.LENGTH_SHORT).show()
}

private fun shareText(context: Context, text: String) {
    val sendIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_TEXT, text)
        type = "text/plain"
    }
    context.startActivity(Intent.createChooser(sendIntent, "Share transcript"))
}
