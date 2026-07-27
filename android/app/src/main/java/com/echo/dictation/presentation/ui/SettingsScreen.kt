package com.echo.dictation.presentation.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.echo.dictation.presentation.ui.auth.AuthUiState
import com.echo.dictation.presentation.ui.auth.AuthViewModel
import com.echo.dictation.speech.provider.ProviderId
import com.echo.dictation.speech.provider.ProviderRegistry
import com.echo.dictation.presentation.ai.AIViewModel
import com.echo.dictation.presentation.theme.CardColor
import com.echo.dictation.presentation.theme.OnSurfaceVariant
import com.echo.dictation.presentation.theme.OutlineColor
import com.echo.dictation.presentation.theme.Primary
import com.echo.dictation.presentation.theme.PrimaryColor
import com.echo.dictation.presentation.theme.PrimaryVariant

@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
    aiViewModel: AIViewModel = hiltViewModel(),
    authViewModel: AuthViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current

    // Auth state — used for the Account section
    val currentUser by authViewModel.currentUser.collectAsState()
    val isAuthenticated by authViewModel.isAuthenticated.collectAsState()
    val authUiState by authViewModel.uiState.collectAsState()

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            // ── Header ────────────────────────────────────────────────────────
            SettingsHeader(onBack = onBack)

            // ── Scrollable content ────────────────────────────────────────────
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // ── Account section ─────────────────────────────────────────
                SectionHeader("Account")

                if (isAuthenticated && currentUser != null) {
                    AccountSignedInCard(
                        user = currentUser!!,
                        authUiState = authUiState,
                        onSignOut = { authViewModel.signOut(context) },
                    )
                } else {
                    AccountSignedOutCard(
                        authUiState = authUiState,
                        onSignIn = { authViewModel.signInWithGoogle(context) },
                    )
                }

                Spacer(Modifier.height(8.dp))
                // ── AI Enhancements section ─────────────────────────────────
                SectionHeader("AI Enhancements")

                val aiState by aiViewModel.state.collectAsState()
                GrammarCorrectionCard(
                    enabled  = aiState.grammarCorrectionEnabled,
                    onToggle = { aiViewModel.setGrammarCorrectionEnabled(it) },
                )

                // Auto Enhance after transcription
                SettingsCard {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Auto Enhance", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text("Automatically enhance transcriptions after they are generated.", style = MaterialTheme.typography.bodySmall, color = OnSurfaceVariant)
                        }
                        Switch(
                            checked = aiState.autoEnhanceEnabled,
                            onCheckedChange = { aiViewModel.setAutoEnhanceEnabled(it) }
                        )
                    }
                }

                // Save Original Guaranteed
                SettingsCard {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Save Original Transcript", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text("Original audio & text are always preserved immutably", style = MaterialTheme.typography.bodySmall, color = OnSurfaceVariant)
                        }
                        Text("Always ON", style = MaterialTheme.typography.labelSmall, color = Primary, fontWeight = FontWeight.Bold)
                    }
                }

                Spacer(Modifier.height(8.dp))

                // ── Speech AI section ─────────────────────────────────────────
                SectionHeader("Speech AI")

                // Provider
                SettingsCard {
                    SettingsLabel("Provider")
                    Spacer(Modifier.height(8.dp))
                    ProviderDropdown(
                        selected = state.selectedProvider,
                        onSelect = { viewModel.onProviderSelected(it) },
                    )
                }

                // API Key
                SettingsCard {
                    SettingsLabel("API Key")
                    Spacer(Modifier.height(8.dp))
                    ApiKeyField(
                        value         = state.apiKeyInput,
                        hasStoredKey  = state.hasStoredKey,
                        keyVisible    = state.keyVisible,
                        providerName  = state.providerConfig.displayName,
                        onValueChange = { viewModel.onApiKeyChanged(it) },
                        onToggleVisibility = { viewModel.onToggleKeyVisibility() },
                        onPaste = {
                            val text = clipboard.getText()?.text ?: ""
                            if (text.isNotBlank()) viewModel.onApiKeyChanged(text)
                        },
                        onClear = { viewModel.onClearKey() },
                        onSave  = { viewModel.onSaveKey() },
                    )
                    // Provider API key link
                    ApiKeyLink(providerId = state.selectedProvider)
                }

                // Model
                SettingsCard {
                    SettingsLabel("Model")
                    Spacer(Modifier.height(8.dp))
                    val models = state.providerConfig.models
                    if (models.isEmpty() || state.providerConfig.requiresCustomModel) {
                        // Free-text model entry for Azure / Custom
                        OutlinedTextField(
                            value         = state.selectedModel,
                            onValueChange = { viewModel.onModelSelected(it) },
                            modifier      = Modifier.fillMaxWidth(),
                            label         = { Text("Model name") },
                            singleLine    = true,
                            colors        = echoTextFieldColors(),
                        )
                    } else {
                        ModelDropdown(
                            selected  = state.selectedModel,
                            models    = models,
                            onSelect  = { viewModel.onModelSelected(it) },
                        )
                    }
                }

                // Test connection
                SettingsCard {
                    TestConnectionSection(
                        testState = state.testState,
                        onTest    = { viewModel.onTestConnection() },
                    )
                }

                Spacer(Modifier.height(16.dp))

                // ── General section ───────────────────────────────────────────
                SectionHeader("General")

                // Language
                SettingsCard {
                    SettingsLabel("Language")
                    Spacer(Modifier.height(8.dp))
                    val languages = listOf(
                        "auto" to "Auto-detect",
                        "en" to "English",
                        "hi" to "Hindi",
                        "es" to "Spanish",
                        "fr" to "French",
                        "de" to "German",
                        "it" to "Italian",
                        "pt" to "Portuguese",
                        "zh" to "Chinese",
                        "ja" to "Japanese",
                        "ko" to "Korean",
                        "ar" to "Arabic",
                        "ru" to "Russian",
                    )
                    SimpleDropdown(
                        selected     = state.language,
                        options      = languages.map { it.first },
                        displayName  = { code -> languages.firstOrNull { it.first == code }?.second ?: code },
                        onSelect     = { viewModel.onLanguageChanged(it) },
                    )
                }

                // Retention
                SettingsCard {
                    SettingsLabel("History Retention")
                    Spacer(Modifier.height(8.dp))
                    // 0 = Forever (no date filter applied)
                    val retentionOptions = listOf(7, 14, 30, 60, 90, 365, 0)
                    SimpleDropdown(
                        selected     = state.retentionDays,
                        options      = retentionOptions,
                        displayName  = { days -> if (days <= 0) "Forever" else "$days days" },
                        onSelect     = { viewModel.onRetentionChanged(it) },
                    )
                }

                // Theme
                SettingsCard {
                    SettingsLabel("Theme")
                    Spacer(Modifier.height(8.dp))
                    val themes = listOf("system" to "System default", "dark" to "Dark", "light" to "Light")
                    SimpleDropdown(
                        selected     = state.theme,
                        options      = themes.map { it.first },
                        displayName  = { t -> themes.firstOrNull { it.first == t }?.second ?: t },
                        onSelect     = { viewModel.onThemeChanged(it) },
                    )
                }

                Spacer(Modifier.height(32.dp))
            }
        }
    }
}

// ─── Grammar Correction card ──────────────────────────────────────────────────

@Composable
private fun GrammarCorrectionCard(enabled: Boolean, onToggle: (Boolean) -> Unit) {
    Card(
        modifier  = Modifier.fillMaxWidth(),
        shape     = RoundedCornerShape(16.dp),
        colors    = CardDefaults.cardColors(containerColor = CardColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier              = Modifier.fillMaxWidth(),
                verticalAlignment     = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text  = "Enable Grammar Correction",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text  = "AI corrects grammar, punctuation, capitalization, spelling, and formatting after transcription.",
                        style = MaterialTheme.typography.bodySmall,
                        color = OnSurfaceVariant,
                        modifier = Modifier.alpha(0.7f),
                    )
                }
                Spacer(Modifier.width(12.dp))
                Switch(
                    checked        = enabled,
                    onCheckedChange = onToggle,
                    colors = SwitchDefaults.colors(checkedThumbColor = MaterialTheme.colorScheme.onPrimary, checkedTrackColor = Primary),
                )
            }

        }
    }
}

// ─── Header ───────────────────────────────────────────────────────────────────

@Composable
private fun SettingsHeader(onBack: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onBack) {
            Icon(
                imageVector        = Icons.Outlined.ArrowBack,
                contentDescription = "Back",
                tint               = MaterialTheme.colorScheme.onBackground,
            )
        }
        Spacer(Modifier.width(4.dp))
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(Brush.linearGradient(listOf(PrimaryColor, PrimaryVariant))),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.Settings, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(
                text  = "Settings",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                text  = "Configure your speech provider",
                style = MaterialTheme.typography.bodySmall,
                color = OnSurfaceVariant,
                modifier = Modifier.alpha(0.7f),
            )
        }
    }
}

// ─── Section header ───────────────────────────────────────────────────────────

@Composable
private fun SectionHeader(title: String) {
    Text(
        text     = title.uppercase(),
        style    = MaterialTheme.typography.labelMedium,
        color    = Primary,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(start = 4.dp, top = 8.dp, bottom = 4.dp),
    )
}

// ─── Card wrapper ─────────────────────────────────────────────────────────────

@Composable
private fun SettingsCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape    = RoundedCornerShape(16.dp),
        colors   = CardDefaults.cardColors(containerColor = CardColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) { content() }
    }
}

@Composable
private fun SettingsLabel(text: String) {
    Text(
        text  = text,
        style = MaterialTheme.typography.labelLarge,
        color = OnSurfaceVariant,
    )
}

// ─── Provider dropdown ────────────────────────────────────────────────────────

@Composable
private fun ProviderDropdown(selected: ProviderId, onSelect: (ProviderId) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .border(1.dp, OutlineColor, RoundedCornerShape(10.dp))
                .clickable { expanded = true }
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text  = selected.displayName,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Icon(Icons.Default.ArrowDropDown, null, tint = OnSurfaceVariant)
        }
        DropdownMenu(
            expanded         = expanded,
            onDismissRequest = { expanded = false },
            modifier         = Modifier.background(CardColor),
        ) {
            ProviderRegistry.allConfigs.forEach { config ->
                DropdownMenuItem(
                    text    = { Text(config.displayName, color = MaterialTheme.colorScheme.onSurface) },
                    onClick = { onSelect(config.id); expanded = false },
                    leadingIcon = if (config.id == selected) ({
                        Icon(Icons.Default.Check, null, tint = Primary, modifier = Modifier.size(18.dp))
                    }) else null,
                )
            }
        }
    }
}

// ─── API key field ────────────────────────────────────────────────────────────

@Composable
private fun ApiKeyField(
    value: String,
    hasStoredKey: Boolean,
    keyVisible: Boolean,
    providerName: String,
    onValueChange: (String) -> Unit,
    onToggleVisibility: () -> Unit,
    onPaste: () -> Unit,
    onClear: () -> Unit,
    onSave: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value         = value,
            onValueChange = onValueChange,
            modifier      = Modifier.fillMaxWidth(),
            placeholder   = {
                Text(
                    if (hasStoredKey) "Key saved — enter new key to replace"
                    else "Enter your $providerName API key",
                    color = OnSurfaceVariant.copy(alpha = 0.6f),
                )
            },
            visualTransformation = if (keyVisible) VisualTransformation.None
                                   else PasswordVisualTransformation(),
            singleLine    = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            trailingIcon  = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // Paste
                    IconButton(onClick = onPaste, modifier = Modifier.size(36.dp)) {
                        Icon(Icons.Default.ContentPaste, "Paste", tint = OnSurfaceVariant, modifier = Modifier.size(18.dp))
                    }
                    // Clear
                    if (value.isNotEmpty() || hasStoredKey) {
                        IconButton(onClick = onClear, modifier = Modifier.size(36.dp)) {
                            Icon(Icons.Default.Clear, "Clear", tint = OnSurfaceVariant, modifier = Modifier.size(18.dp))
                        }
                    }
                    // Show/hide
                    IconButton(onClick = onToggleVisibility, modifier = Modifier.size(36.dp)) {
                        Icon(
                            imageVector = if (keyVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (keyVisible) "Hide key" else "Show key",
                            tint = OnSurfaceVariant,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            },
            colors = echoTextFieldColors(),
        )
        // Save button — only enabled when there's text to save
        AnimatedVisibility(visible = value.isNotBlank()) {
            Button(
                onClick  = onSave,
                modifier = Modifier.fillMaxWidth(),
                colors   = ButtonDefaults.buttonColors(containerColor = Primary),
                shape    = RoundedCornerShape(10.dp),
            ) {
                Text("Save Key", color = MaterialTheme.colorScheme.onPrimary)
            }
        }
        if (hasStoredKey && value.isBlank()) {
            Text(
                "✓ API key saved",
                style = MaterialTheme.typography.labelSmall,
                color = Color(0xFF66BB6A),
            )
        }
    }
}

// ─── Model dropdown ───────────────────────────────────────────────────────────

@Composable
private fun ModelDropdown(selected: String, models: List<String>, onSelect: (String) -> Unit) {
    SimpleDropdown(
        selected     = selected,
        options      = models,
        displayName  = { it },
        onSelect     = onSelect,
    )
}

// ─── Generic dropdown ─────────────────────────────────────────────────────────

@Composable
private fun <T> SimpleDropdown(
    selected: T,
    options: List<T>,
    displayName: (T) -> String,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .border(1.dp, OutlineColor, RoundedCornerShape(10.dp))
                .clickable { expanded = true }
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text  = displayName(selected),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Icon(Icons.Default.ArrowDropDown, null, tint = OnSurfaceVariant)
        }
        DropdownMenu(
            expanded         = expanded,
            onDismissRequest = { expanded = false },
            modifier         = Modifier.background(CardColor),
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text    = { Text(displayName(option), color = MaterialTheme.colorScheme.onSurface) },
                    onClick = { onSelect(option); expanded = false },
                    leadingIcon = if (option == selected) ({
                        Icon(Icons.Default.Check, null, tint = Primary, modifier = Modifier.size(18.dp))
                    }) else null,
                )
            }
        }
    }
}

// ─── Test connection ──────────────────────────────────────────────────────────

@Composable
private fun TestConnectionSection(testState: TestState, onTest: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Button(
            onClick  = onTest,
            modifier = Modifier.fillMaxWidth(),
            enabled  = testState !is TestState.Testing,
            colors   = ButtonDefaults.buttonColors(
                containerColor = Primary.copy(alpha = 0.15f),
                contentColor   = Primary,
            ),
            shape = RoundedCornerShape(10.dp),
        ) {
            if (testState is TestState.Testing) {
                CircularProgressIndicator(
                    modifier  = Modifier.size(18.dp),
                    color     = Primary,
                    strokeWidth = 2.dp,
                )
                Spacer(Modifier.width(8.dp))
                Text("Testing…")
            } else {
                Text("Test Provider")
            }
        }

        AnimatedVisibility(
            visible = testState !is TestState.Idle && testState !is TestState.Testing,
            enter   = fadeIn(),
            exit    = fadeOut(),
        ) {
            when (testState) {
                is TestState.Success -> Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.Default.Check, null, tint = Color(0xFF66BB6A), modifier = Modifier.size(16.dp))
                    Text(
                        "Connected (${testState.latencyMs} ms)",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(0xFF66BB6A),
                    )
                }
                is TestState.Error -> Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.Outlined.Circle, null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(16.dp))
                    Text(
                        testState.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                else -> {}
            }
        }
    }
}

// ─── Account — signed in ──────────────────────────────────────────────────────

@Composable
private fun AccountSignedInCard(
    user: com.echo.dictation.domain.model.User,
    authUiState: AuthUiState,
    onSignOut: () -> Unit,
) {
    val isBusy = authUiState is AuthUiState.Loading
    val errorMessage = (authUiState as? AuthUiState.Error)?.message

    SettingsCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            UserAvatar(
                photoUrl    = user.photoUrl,
                displayName = user.displayName,
                size        = 52,
            )
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                if (!user.displayName.isNullOrBlank()) {
                    Text(
                        text  = user.displayName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                    )
                }
                if (!user.email.isNullOrBlank()) {
                    Text(
                        text  = user.email,
                        style = MaterialTheme.typography.bodySmall,
                        color = OnSurfaceVariant,
                        maxLines = 1,
                    )
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.padding(top = 4.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF66BB6A))
                    )
                    Text(
                        text  = "Syncing enabled",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFF66BB6A),
                    )
                }
            }
        }

        if (errorMessage != null) {
            Spacer(Modifier.height(10.dp))
            Text(
                text     = errorMessage,
                style    = MaterialTheme.typography.bodySmall,
                color    = MaterialTheme.colorScheme.error,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Spacer(Modifier.height(14.dp))

        Button(
            onClick  = onSignOut,
            enabled  = !isBusy,
            modifier = Modifier.fillMaxWidth(),
            shape    = RoundedCornerShape(12.dp),
            colors   = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
                contentColor   = MaterialTheme.colorScheme.onErrorContainer,
            ),
        ) {
            Text("Sign Out", style = MaterialTheme.typography.labelMedium)
        }
    }
}

// ─── Account — signed out ─────────────────────────────────────────────────────

@Composable
private fun AccountSignedOutCard(
    authUiState: AuthUiState,
    onSignIn: () -> Unit,
) {
    val isLoading    = authUiState is AuthUiState.Loading
    val errorMessage = (authUiState as? AuthUiState.Error)?.message

    SettingsCard {
        Row(
            modifier          = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector        = Icons.Default.Person,
                    contentDescription = null,
                    tint               = OnSurfaceVariant,
                    modifier           = Modifier.size(26.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text  = "Not signed in",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text  = "Sign in to keep your transcriptions synced across your devices.",
                    style = MaterialTheme.typography.bodySmall,
                    color = OnSurfaceVariant,
                )
            }
        }

        if (errorMessage != null) {
            Spacer(Modifier.height(10.dp))
            Text(
                text     = errorMessage,
                style    = MaterialTheme.typography.bodySmall,
                color    = MaterialTheme.colorScheme.error,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        Spacer(Modifier.height(14.dp))

        Button(
            onClick  = onSignIn,
            enabled  = !isLoading,
            modifier = Modifier.fillMaxWidth(),
            shape    = RoundedCornerShape(12.dp),
            colors   = ButtonDefaults.buttonColors(containerColor = Primary),
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier    = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color       = Color.White,
                )
                Spacer(Modifier.width(8.dp))
                Text("Signing in…", style = MaterialTheme.typography.labelMedium)
            } else {
                Text("Sign in with Google", style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

// ─── User avatar ──────────────────────────────────────────────────────────────

@Composable
private fun UserAvatar(photoUrl: String?, displayName: String?, size: Int) {
    val context = LocalContext.current
    val sizeDp  = size.dp

    Box(
        modifier         = Modifier
            .size(sizeDp)
            .clip(CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (!photoUrl.isNullOrBlank()) {
            AsyncImage(
                model             = ImageRequest.Builder(context).data(photoUrl).crossfade(true).build(),
                contentDescription = displayName,
                contentScale      = ContentScale.Crop,
                modifier          = Modifier.fillMaxSize(),
            )
        } else {
            // Fallback: initials on gradient background
            Box(
                modifier         = Modifier
                    .fillMaxSize()
                    .background(Brush.linearGradient(listOf(PrimaryColor, PrimaryVariant))),
                contentAlignment = Alignment.Center,
            ) {
                val initials = displayName
                    ?.split(" ")
                    ?.take(2)
                    ?.mapNotNull { it.firstOrNull()?.uppercaseChar() }
                    ?.joinToString("")
                    ?: "?"
                Text(
                    text  = initials,
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}

// ─── Provider API key link ────────────────────────────────────────────────────

@Composable
private fun ApiKeyLink(providerId: com.echo.dictation.speech.provider.ProviderId) {
    val context = LocalContext.current

    data class LinkInfo(val domain: String, val url: String?)

    val info = when (providerId) {
        com.echo.dictation.speech.provider.ProviderId.GROQ ->
            LinkInfo("console.groq.com", "https://console.groq.com/keys")
        com.echo.dictation.speech.provider.ProviderId.OPENAI ->
            LinkInfo("platform.openai.com", "https://platform.openai.com/api-keys")
        com.echo.dictation.speech.provider.ProviderId.OPENROUTER ->
            LinkInfo("openrouter.ai", "https://openrouter.ai/keys")
        com.echo.dictation.speech.provider.ProviderId.DEEPGRAM ->
            LinkInfo("console.deepgram.com", "https://console.deepgram.com/signup")
        com.echo.dictation.speech.provider.ProviderId.ASSEMBLYAI ->
            LinkInfo("assemblyai.com", "https://www.assemblyai.com/dashboard/signup")
        com.echo.dictation.speech.provider.ProviderId.GEMINI ->
            LinkInfo("aistudio.google.com", "https://aistudio.google.com/app/apikey")
        com.echo.dictation.speech.provider.ProviderId.AZURE ->
            LinkInfo("", null)   // plain note, no link
        com.echo.dictation.speech.provider.ProviderId.BEDROCK ->
            LinkInfo("aws.amazon.com", "https://console.aws.amazon.com/bedrock/")
        com.echo.dictation.speech.provider.ProviderId.CUSTOM ->
            return  // no link for custom providers
    }

    Spacer(Modifier.height(8.dp))

    if (info.url != null) {
        // "Get your API key from " — plain  |  "domain" — primary + underline
        val primary       = Primary
        val subtle        = OnSurfaceVariant
        val annotated: AnnotatedString = buildAnnotatedString {
            withStyle(SpanStyle(color = subtle)) { append("Get your API key from ") }
            withStyle(
                SpanStyle(
                    color          = primary,
                    textDecoration = TextDecoration.Underline,
                )
            ) { append(info.domain) }
        }
        Text(
            text     = annotated,
            style    = MaterialTheme.typography.bodySmall,
            modifier = Modifier.clickable {
                context.startActivity(
                    android.content.Intent(
                        android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse(info.url),
                    )
                )
            },
        )
    } else if (providerId == com.echo.dictation.speech.provider.ProviderId.AZURE) {
        Text(
            text  = "Create an API key from your Azure Portal.",
            style = MaterialTheme.typography.bodySmall,
            color = OnSurfaceVariant,
        )
    }
}

// ─── Shared text field colours ────────────────────────────────────────────────

@Composable
private fun echoTextFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor   = Primary,
    unfocusedBorderColor = OutlineColor,
    focusedLabelColor    = Primary,
    unfocusedLabelColor  = OnSurfaceVariant,
    cursorColor          = Primary,
    focusedTextColor     = MaterialTheme.colorScheme.onSurface,
    unfocusedTextColor   = MaterialTheme.colorScheme.onSurface,
)

