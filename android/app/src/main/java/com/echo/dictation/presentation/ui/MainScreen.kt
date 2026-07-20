package com.echo.dictation.presentation.ui

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.material3.ripple
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.echo.dictation.R
import com.echo.dictation.core.accessibility.TextInsertionAccessibilityService
import com.echo.dictation.core.permission.PermissionManager
import com.echo.dictation.domain.model.Transcription
import com.echo.dictation.domain.repository.TranscriptionRepository
import com.echo.dictation.presentation.theme.CardColor
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant
import com.echo.dictation.service.overlay.PillOverlayService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class MainViewModel @Inject constructor(
    private val repository: TranscriptionRepository,
    val permissions: PermissionManager
) : ViewModel() {
    val history: StateFlow<List<Transcription>> = repository.history().stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = emptyList()
    )

    private val _uploadedTranscriptions = MutableSharedFlow<Transcription>(replay = 1)
    val uploadedTranscriptions: SharedFlow<Transcription> = _uploadedTranscriptions

    init {
        viewModelScope.launch { repository.sync() }
    }

    fun uploadRecordedAudio(file: File, model: String = DEFAULT_MODEL) {
        viewModelScope.launch {
            repository.transcribe(file, model).onSuccess { _uploadedTranscriptions.emit(it) }
        }
    }

    companion object {
        private const val DEFAULT_MODEL = "whisper-large-v3-turbo"
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@Composable
fun MainScreen(
    viewModel: MainViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val history: List<Transcription> by viewModel.history.collectAsState()
    val overlayRunning by PillOverlayService.isRunning.collectAsState()
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    var selectedTranscription by remember { mutableStateOf<Transcription?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // ── Mic permission ────────────────────────────────────────────────────
    var micPermissionGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED
        )
    }
    val requestMicPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> micPermissionGranted = granted }

    // Track accessibility service state
    var accessibilityConnected by remember { mutableStateOf(TextInsertionAccessibilityService.instance != null) }
    val lifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val obs = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                accessibilityConnected = isAccessibilityServiceEnabled(context)
                micPermissionGranted = ContextCompat.checkSelfPermission(
                    context, Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    val accessibilitySettingsLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) {
        accessibilityConnected = isAccessibilityServiceEnabled(context)
    }

    // Auto-copy on upload and show snackbar
    LaunchedEffect(viewModel) {
        viewModel.uploadedTranscriptions.collect { transcription ->
            clipboard.setPrimaryClip(ClipData.newPlainText("Transcription", transcription.text))
            snackbarHostState.showSnackbar(
                message = "✓ Copied to clipboard",
                duration = SnackbarDuration.Short
            )
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
        ) {
            // ── Header ────────────────────────────────────────────────────────
            ScreenHeader()

            // ── Accessibility banner ──────────────────────────────────────────
            AnimatedVisibility(
                visible = !accessibilityConnected,
                enter = fadeIn() + slideInVertically(),
                exit = fadeOut()
            ) {
                AccessibilityBanner(
                    onEnable = {
                        accessibilitySettingsLauncher.launch(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        )
                    }
                )
            }

            // ── Mic permission banner ─────────────────────────────────────────
            AnimatedVisibility(
                visible = !micPermissionGranted,
                enter = fadeIn() + slideInVertically(),
                exit = fadeOut()
            ) {
                MicPermissionBanner(
                    onGrant = { requestMicPermission.launch(Manifest.permission.RECORD_AUDIO) }
                )
            }

            // ── History list / empty state ─────────────────────────────────
            Box(modifier = Modifier.weight(1f)) {
                if (history.isEmpty()) {
                    EmptyState()
                } else {
                    HistoryList(
                        items = history,
                        onCardClick = { selectedTranscription = it }
                    )
                }
            }

            // ── Bottom action bar ─────────────────────────────────────────
            BottomActionBar(
                overlayRunning = overlayRunning,
                onToggleOverlay = {
                    if (overlayRunning) {
                        PillOverlayService.stop(context.applicationContext)
                        scope.launch {
                            snackbarHostState.showSnackbar(
                                message = "✓ Floating mic disabled",
                                duration = SnackbarDuration.Short
                            )
                        }
                    } else {
                        PillOverlayService.start(context.applicationContext)
                        scope.launch {
                            snackbarHostState.showSnackbar(
                                message = "✓ Floating mic enabled",
                                duration = SnackbarDuration.Short
                            )
                        }
                    }
                },
                modifier = Modifier.navigationBarsPadding()
            )
        }

        // ── Snackbar ──────────────────────────────────────────────────────
        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 100.dp)
        )
    }

    // ── Detail sheet ──────────────────────────────────────────────────────
    selectedTranscription?.let { transcription ->
        TranscriptionDetailBottomSheet(
            transcription = transcription,
            onDismiss = { selectedTranscription = null },
            onCopied = {
                scope.launch {
                    snackbarHostState.showSnackbar(
                        message = "✓ Copied to clipboard",
                        duration = SnackbarDuration.Short
                    )
                }
            }
        )
    }
}

// ─── Header ──────────────────────────────────────────────────────────────────

@Composable
private fun ScreenHeader() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 24.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(PrimaryColor, PrimaryVariant)
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Outlined.History,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(22.dp)
                )
            }
            Spacer(Modifier.width(14.dp))
            Column {
                Text(
                    text = "History",
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.onBackground
                )
                Text(
                    text = "Recent transcriptions",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.alpha(0.7f)
                )
            }
        }
    }
}

// ─── Accessibility banner ─────────────────────────────────────────────────────

@Composable
private fun AccessibilityBanner(onEnable: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.errorContainer,
        tonalElevation = 2.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Enable accessibility for text injection",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = onEnable) {
                Text(
                    text = "Enable",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
    }
}

// ─── Mic permission banner ────────────────────────────────────────────────────

@Composable
private fun MicPermissionBanner(onGrant: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.errorContainer,
        tonalElevation = 2.dp
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = "Microphone permission required for recording",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = onGrant) {
                Text(
                    text = "Allow",
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
    }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

@Composable
private fun EmptyState() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(40.dp)
        ) {
            // Large mic illustration
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.radialGradient(
                            listOf(
                                PrimaryColor.copy(alpha = 0.20f),
                                PrimaryVariant.copy(alpha = 0.08f)
                            )
                        )
                    )
                    .border(
                        width = 1.dp,
                        brush = Brush.linearGradient(
                            listOf(PrimaryColor.copy(alpha = 0.4f), PrimaryVariant.copy(alpha = 0.2f))
                        ),
                        shape = CircleShape
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Outlined.Mic,
                    contentDescription = null,
                    tint = PrimaryColor,
                    modifier = Modifier.size(44.dp)
                )
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = "No transcriptions yet",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
            Text(
                text = "Start dictating to see your history.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.alpha(0.7f)
            )
        }
    }
}

// ─── History list ─────────────────────────────────────────────────────────────

@Composable
private fun HistoryList(
    items: List<Transcription>,
    onCardClick: (Transcription) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        itemsIndexed(items = items, key = { _, t -> t.id }) { index, transcription ->
            AnimatedTranscriptionCard(
                transcription = transcription,
                index = index,
                onClick = { onCardClick(transcription) }
            )
        }
    }
}

// ─── Animated card ────────────────────────────────────────────────────────────

@Composable
private fun AnimatedTranscriptionCard(
    transcription: Transcription,
    index: Int,
    onClick: () -> Unit
) {
    // Entrance: fade + slight upward slide, staggered by index
    var visible by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { visible = true }

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(animationSpec = tween(durationMillis = 200, delayMillis = (index * 40).coerceAtMost(300), easing = FastOutSlowInEasing)) +
                slideInVertically(
                    animationSpec = tween(durationMillis = 200, delayMillis = (index * 40).coerceAtMost(300), easing = FastOutSlowInEasing),
                    initialOffsetY = { it / 5 }
                )
    ) {
        TranscriptionCard(
            transcription = transcription,
            onClick = onClick
        )
    }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

@Composable
private fun TranscriptionCard(
    transcription: Transcription,
    onClick: () -> Unit
) {
    val context = LocalContext.current

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = ripple(color = PrimaryColor.copy(alpha = 0.12f)),
                onClick = onClick
            ),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = CardColor),
        elevation = CardDefaults.cardElevation(
            defaultElevation = 4.dp,
            pressedElevation  = 8.dp,
            hoveredElevation  = 6.dp
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            // Transcript icon badge
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(PrimaryColor.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Outlined.RecordVoiceOver,
                    contentDescription = null,
                    tint = PrimaryColor,
                    modifier = Modifier.size(20.dp)
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = transcription.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = formatTimestamp(context, transcription.timestamp),
                    style = MaterialTheme.typography.labelSmall,
                    color = OnSurfaceVariant,
                    modifier = Modifier.alpha(0.8f)
                )
            }
        }
    }
}

// ─── Bottom action bar ────────────────────────────────────────────────────────

@Composable
private fun BottomActionBar(
    overlayRunning: Boolean,
    onToggleOverlay: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        shape = RoundedCornerShape(24.dp),
        color = CardColor,
        tonalElevation = 6.dp,
        shadowElevation = 8.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Left: mic status
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                MicStatusIndicator(active = overlayRunning)
                Column {
                    Text(
                        text = "Floating Mic",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = if (overlayRunning) "ON" else "OFF",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (overlayRunning) PrimaryColor else OnSurfaceVariant,
                        modifier = Modifier.alpha(if (overlayRunning) 1f else 0.7f)
                    )
                }
            }

            // Right: toggle button
            if (overlayRunning) {
                Button(
                    onClick = onToggleOverlay,
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor   = MaterialTheme.colorScheme.onErrorContainer
                    ),
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)
                ) {
                    Icon(Icons.Filled.MicOff, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Disable", style = MaterialTheme.typography.labelLarge)
                }
            } else {
                Button(
                    onClick = onToggleOverlay,
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = PrimaryColor,
                        contentColor   = MaterialTheme.colorScheme.onPrimary
                    ),
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp)
                ) {
                    Icon(Icons.Outlined.Mic, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Enable", style = MaterialTheme.typography.labelLarge)
                }
            }
        }
    }
}

// ─── Mic status indicator ─────────────────────────────────────────────────────

@Composable
private fun MicStatusIndicator(active: Boolean) {
    val infiniteTransition = rememberInfiniteTransition(label = "mic_pulse")
    val pulseScale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue  = 1.4f,
        animationSpec = infiniteRepeatable(
            animation  = tween(900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse_scale"
    )
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.5f,
        targetValue  = 0.0f,
        animationSpec = infiniteRepeatable(
            animation  = tween(900, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse_alpha"
    )

    Box(
        modifier = Modifier.size(36.dp),
        contentAlignment = Alignment.Center
    ) {
        // Pulse ring (only when active)
        if (active) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .scale(pulseScale)
                    .alpha(pulseAlpha)
                    .clip(CircleShape)
                    .background(PrimaryColor)
            )
        }
        // Solid dot
        Box(
            modifier = Modifier
                .size(14.dp)
                .clip(CircleShape)
                .background(if (active) PrimaryColor else OnSurfaceVariant.copy(alpha = 0.4f))
        )
    }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

private fun isAccessibilityServiceEnabled(context: Context): Boolean {
    val manager = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
        ?: return false
    val expected = ComponentName(context, TextInsertionAccessibilityService::class.java)
    return manager.getEnabledAccessibilityServiceList(
        android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK
    ).any { info ->
        val si = info.resolveInfo?.serviceInfo ?: return@any false
        ComponentName(si.packageName, si.name) == expected
    }
}

internal fun formatTimestamp(context: Context, timestamp: Long): String {
    val date = SimpleDateFormat("MMM d, yyyy", Locale.ENGLISH).format(Date(timestamp))
    val time = SimpleDateFormat("h:mm a", Locale.ENGLISH)
        .format(Date(timestamp))
        .replace("AM", "am")
        .replace("PM", "pm")
    return context.getString(R.string.history_timestamp_format, date, time)
}


