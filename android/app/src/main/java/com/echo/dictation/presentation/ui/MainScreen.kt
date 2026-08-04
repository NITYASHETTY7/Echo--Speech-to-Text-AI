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
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.outlined.History
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.material.icons.outlined.Settings
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
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
import com.echo.dictation.presentation.theme.CormorantGaramondSemiBold
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.Primary
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant
import com.echo.dictation.speech.provider.ProviderKeyStore
import com.echo.dictation.speech.provider.ProviderSettings
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.inject.Inject

import com.echo.dictation.data.local.db.TranscriptVersionDao
import com.echo.dictation.domain.ai.VersionType
import com.echo.dictation.domain.recording.RecordingEventBus
import com.echo.dictation.domain.sync.SyncManager
import com.echo.dictation.domain.sync.SyncState

// ─── ViewModel ───────────────────────────────────────────────────────────────

@HiltViewModel
class MainViewModel @Inject constructor(
    private val repository: TranscriptionRepository,
    val permissions: PermissionManager,
    private val providerKeyStore: ProviderKeyStore,
    private val providerSettings: ProviderSettings,
    private val versionDao: TranscriptVersionDao,
    val syncManager: SyncManager,
    private val recordingEventBus: RecordingEventBus,
) : ViewModel() {
    val history: StateFlow<List<Transcription>> = repository.history().stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = emptyList()
    )

    /** True when device has network connectivity. */
    val isOnline: StateFlow<Boolean> = syncManager.isOnline

    /** Cloud sync state — drives subtle indicators in the UI. */
    val syncState: StateFlow<SyncState> = syncManager.syncState

    /**
     * Maps transcriptId → Pair(latestVersionType, latestVersionContent).
     * Both values come from the SAME version row so the card preview text and
     * badge always represent the identical transcript version — never mismatched.
     *
     * When no version exists (original only) → VersionType.Original + empty string
     * (card falls back to transcription.text which is the persisted display text).
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    val latestVersionInfo: StateFlow<Map<String, Pair<VersionType, String>>> =
        history.flatMapLatest { list ->
            flow {
                val map = list.associate { t ->
                    val latest = versionDao.getLatestVersion(t.id)
                    val type = latest?.versionType?.let {
                        runCatching { VersionType.valueOf(it) }.getOrNull()
                    } ?: VersionType.Original
                    val content = latest?.content ?: ""
                    t.id to (type to content)
                }
                emit(map)
            }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    /**
     * Emits every transcription that was saved to Room (from [PillController] via
     * [RecordingEventBus]). Collected by [MainScreen] to auto-copy to clipboard and
     * show a confirmation snackbar — regardless of whether text was pasted or
     * fell back to clipboard.
     */
    val completedTranscriptions: SharedFlow<Transcription> =
        recordingEventBus.completedTranscriptions

    /** True when the currently selected provider has an API key configured. */
    val providerConfigured: Boolean
        get() = providerKeyStore.isConfigured(providerSettings.selectedProvider)

    init {
        viewModelScope.launch { repository.sync() }
    }

    companion object {
        private const val DEFAULT_MODEL = "whisper-large-v3-turbo"
    }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

@Composable
fun MainScreen(
    onNavigateToSettings: () -> Unit = {},
    viewModel: MainViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val history: List<Transcription> by viewModel.history.collectAsState()
    val latestVersionInfo by viewModel.latestVersionInfo.collectAsState()
    val isOnline by viewModel.isOnline.collectAsState()
    val syncState by viewModel.syncState.collectAsState()
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

    // Track accessibility service state.
    // Use isAccessibilityServiceEnabled() for the initial value so we correctly
    // reflect the current system setting on every cold launch and after device
    // reboots — instance is always null at this point even when the service is
    // registered in Android Settings.
    var accessibilityConnected by remember { mutableStateOf(isAccessibilityServiceEnabled(context)) }
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

    // Show confirmation snackbar for every completed transcription.
    // PillController emits via RecordingEventBus whether the text was
    // pasted into a field (text insertion succeeded) or copied to clipboard
    // (clipboard fallback). The transcription is already persisted in Room
    // by the time this fires — History is guaranteed to show it.
    LaunchedEffect(viewModel) {
        viewModel.completedTranscriptions.collect { transcription ->
            if (transcription.text.isNotBlank()) {
                snackbarHostState.showSnackbar(
                    message  = "✓ Transcription saved",
                    duration = SnackbarDuration.Short,
                )
            }
        }
    }

    // Re-check provider configured state on resume
    var providerConfigured by remember { mutableStateOf(viewModel.providerConfigured) }
    DisposableEffect(lifecycleOwner) {
        val obs = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
                providerConfigured = viewModel.providerConfigured
            }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
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
                .navigationBarsPadding()
        ) {
            // ── Header ────────────────────────────────────────────────────────
            ScreenHeader(onNavigateToSettings = onNavigateToSettings)

            // ── Provider not configured banner ────────────────────────────────
            AnimatedVisibility(
                visible = !providerConfigured,
                enter = fadeIn() + slideInVertically(),
                exit = fadeOut()
            ) {
                ProviderNotConfiguredBanner(onSetUp = onNavigateToSettings)
            }

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

            // ── History list / empty state / no-internet ──────────────────
            Box(modifier = Modifier.weight(1f)) {
                when {
                    !isOnline -> NoInternetScreen(onRetry = { /* auto-retries via SyncManager network callback */ })
                    history.isEmpty() -> EmptyState()
                    else -> HistoryList(
                        items = history,
                        latestVersionInfo = latestVersionInfo,
                        onCardClick = { selectedTranscription = it }
                    )
                }
            }
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
private fun ScreenHeader(onNavigateToSettings: () -> Unit = {}) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 24.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(PrimaryColor, PrimaryVariant)
                        )
                    )
                    .semantics { disabled() },
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
            Column(modifier = Modifier.weight(1f)) {
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
            androidx.compose.material3.IconButton(onClick = onNavigateToSettings) {
                Icon(
                    imageVector = Icons.Outlined.Settings,
                    contentDescription = "Settings",
                    tint = OnSurfaceVariant,
                    modifier = Modifier.size(22.dp),
                )
            }
        }
    }
}

// ─── Provider not configured banner ──────────────────────────────────────────

@Composable
private fun ProviderNotConfiguredBanner(onSetUp: () -> Unit) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.primaryContainer,
        tonalElevation = 2.dp,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = "Configure your AI speech provider to start transcribing",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = onSetUp) {
                Text(
                    text = "Set Up",
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    style = MaterialTheme.typography.labelLarge,
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

// ─── No internet screen ───────────────────────────────────────────────────────

@Composable
private fun NoInternetScreen(onRetry: () -> Unit) {
    Box(
        modifier         = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier            = Modifier.padding(horizontal = 40.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(80.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.errorContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector        = Icons.Outlined.Mic,
                    contentDescription = null,
                    tint               = MaterialTheme.colorScheme.onErrorContainer,
                    modifier           = Modifier.size(36.dp),
                )
            }

            Text(
                text       = "No Internet Connection",
                style      = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color      = MaterialTheme.colorScheme.onBackground,
                textAlign  = androidx.compose.ui.text.style.TextAlign.Center,
            )
            Text(
                text      = "Echo requires an internet connection to transcribe speech and use AI features.\n\nPlease connect to the internet and try again.",
                style     = MaterialTheme.typography.bodyMedium,
                color     = OnSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )

            Button(
                onClick        = onRetry,
                shape          = RoundedCornerShape(14.dp),
                colors         = ButtonDefaults.buttonColors(containerColor = Primary),
                contentPadding = PaddingValues(horizontal = 32.dp, vertical = 12.dp),
            ) {
                Text("Retry", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

@Composable
private fun EmptyState() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.radialGradient(
                            listOf(
                                Primary.copy(alpha = 0.20f),
                                PrimaryVariant.copy(alpha = 0.08f),
                            )
                        )
                    )
                    .border(
                        width = 1.dp,
                        brush = Brush.linearGradient(
                            listOf(
                                Primary.copy(alpha = 0.4f),
                                PrimaryVariant.copy(alpha = 0.2f),
                            )
                        ),
                        shape = CircleShape,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector        = Icons.Outlined.Mic,
                    contentDescription = null,
                    tint               = Primary,
                    modifier           = Modifier.size(44.dp),
                )
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text       = "No recordings yet",
                    style      = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color      = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text     = "Your saved recordings will appear here.",
                    style    = MaterialTheme.typography.bodyMedium,
                    color    = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.alpha(0.7f),
                )
            }
        }
    }
}

// ─── History list ─────────────────────────────────────────────────────────────

@Composable
private fun HistoryList(
    items: List<Transcription>,
    latestVersionInfo: Map<String, Pair<VersionType, String>>,
    onCardClick: (Transcription) -> Unit,
) {
    // Group by calendar date (epoch-day), preserving newest-first order
    val grouped: List<Pair<Long, List<Transcription>>> = remember(items) {
        items
            .groupBy { epochDayOf(it.timestamp) }
            .entries
            .sortedByDescending { it.key }
            .map { it.key to it.value.sortedByDescending { t -> t.timestamp } }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        grouped.forEachIndexed { groupIndex, (epochDay, transcriptions) ->
            // ── Date header ──────────────────────────────────────────────
            item(key = "header_$epochDay") {
                DateHeader(
                    epochDay = epochDay,
                    modifier = if (groupIndex == 0) Modifier else Modifier.padding(top = 8.dp),
                )
            }

            // ── Cards for this day ────────────────────────────────────────
            itemsIndexed(
                items = transcriptions,
                key   = { _, t -> t.id },
            ) { cardIndex, transcription ->
                val info  = latestVersionInfo[transcription.id]
                // Stagger animation offset: reset per group so every first card animates in
                val globalIndex = grouped.take(groupIndex).sumOf { it.second.size } + cardIndex
                AnimatedTranscriptionCard(
                    transcription     = transcription,
                    index             = globalIndex,
                    latestVersionType = info?.first,
                    latestVersionText = info?.second,
                    onClick           = { onCardClick(transcription) },
                )
            }
        }
    }
}

// ─── Date header ──────────────────────────────────────────────────────────────

@Composable
private fun DateHeader(epochDay: Long, modifier: Modifier = Modifier) {
    val label = remember(epochDay) {
        val todayEpoch     = epochDayOf(System.currentTimeMillis())
        val yesterdayEpoch = todayEpoch - 1
        when (epochDay) {
            todayEpoch     -> "Today"
            yesterdayEpoch -> "Yesterday"
            else           -> {
                val ms = epochDay * 24 * 60 * 60 * 1000L
                SimpleDateFormat("MMM d, yyyy", Locale.ENGLISH).format(Date(ms))
            }
        }
    }
    Text(
        text  = label,
        style = MaterialTheme.typography.labelMedium.copy(
            fontFamily    = CormorantGaramondSemiBold,
            fontSize      = 20.sp,
            fontWeight    = FontWeight.SemiBold,
            letterSpacing = 0.sp,
        ),
        color    = MaterialTheme.colorScheme.onBackground,
        modifier = modifier.padding(start = 4.dp, top = 4.dp, bottom = 2.dp),
    )
}

/** Returns the epoch-day (UTC midnight / 86400 s) for a timestamp. */
private fun epochDayOf(timestamp: Long): Long =
    java.util.concurrent.TimeUnit.MILLISECONDS.toDays(timestamp)

// ─── Animated card ────────────────────────────────────────────────────────────

@Composable
private fun AnimatedTranscriptionCard(
    transcription: Transcription,
    index: Int,
    latestVersionType: VersionType?,
    latestVersionText: String?,
    onClick: () -> Unit,
) {
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
            transcription     = transcription,
            latestVersionType = latestVersionType,
            latestVersionText = latestVersionText,
            onClick           = onClick,
        )
    }
}

// ─── Card ─────────────────────────────────────────────────────────────────────

@Composable
private fun TranscriptionCard(
    transcription: Transcription,
    latestVersionType: VersionType?,
    latestVersionText: String?,
    onClick: () -> Unit,
) {
    // Single source of truth: if a non-Original version exists use its content,
    // otherwise fall back to transcription.text (the persisted display text).
    val showBadge = latestVersionType != null && latestVersionType != VersionType.Original
    val previewText = if (showBadge && !latestVersionText.isNullOrBlank()) {
        latestVersionText
    } else {
        transcription.text
    }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = ripple(color = Primary.copy(alpha = 0.12f)),
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
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(Primary.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Outlined.RecordVoiceOver,
                    contentDescription = null,
                    tint = Primary,
                    modifier = Modifier.size(20.dp)
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                val annotatedPreview = remember(previewText, showBadge) {
                    if (showBadge) {
                        // AI-generated version — parse markdown so bold/bullets render correctly
                        com.echo.dictation.presentation.ui.util.parseMarkdownToAnnotatedString(previewText)
                    } else {
                        // Original transcript — show as plain text (preserves spoken language)
                        androidx.compose.ui.text.AnnotatedString(previewText)
                    }
                }
                Text(
                    text = annotatedPreview,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = formatTimeOnly(transcription.timestamp),
                        style = MaterialTheme.typography.labelSmall,
                        color = OnSurfaceVariant,
                        modifier = Modifier.alpha(0.8f)
                    )

                    // Badge shown only when a non-Original AI version exists;
                    // type and preview text are from the same version row.
                    if (showBadge) {
                        AiBadge(versionType = latestVersionType!!)
                    }
                }
            }
        }
    }
}

@Composable
private fun AiBadge(versionType: VersionType) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = Primary.copy(alpha = 0.12f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = Primary,
                modifier = Modifier.size(10.dp)
            )
            Text(
                text = versionType.displayName,
                style = MaterialTheme.typography.labelSmall,
                color = Primary,
                fontWeight = FontWeight.SemiBold
            )
        }
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

/** Returns only the time component, e.g. "3:08 pm" — used on history cards. */
private fun formatTimeOnly(timestamp: Long): String =
    SimpleDateFormat("h:mm a", Locale.ENGLISH)
        .format(Date(timestamp))
        .replace("AM", "am")
        .replace("PM", "pm")



