# Audio Recording Permission Fix

## Root Cause

**MediaRecorder.setAudioSource() failed because RECORD_AUDIO permission was never requested at runtime.**

### Issue Details

1. ✅ **AndroidManifest.xml** - RECORD_AUDIO permission declared (line 5)
2. ❌ **Runtime Request** - PermissionManager.requestRecordAudio() method exists but was NEVER called
3. ❌ **Permission Check** - PillController.startRecording() called AudioRecorder.start() without checking permission
4. ✅ **MediaRecorder API** - Initialization order was correct

On Android 6.0+ (API 23+), dangerous permissions like RECORD_AUDIO must be requested at runtime. The app declared the permission in the manifest but never requested it from the user.

## Solution

### 1. PillController.kt - Added Permission Check

**Added:**
- Import `PermissionManager`
- Inject `PermissionManager` into constructor
- Check `permissions.hasRecordAudio()` before attempting to start recording
- Log error and return early if permission not granted

**Changes:**
```kotlin
@Singleton
class PillController @Inject constructor(
    private val audioRecorder: AudioRecorder,
    private val audioFileManager: AudioFileManager,
    private val transcriptionRepository: TranscriptionRepository,
    private val preferences: AppPreferences,
    private val permissions: PermissionManager  // ADDED
) {
    private fun startRecording() {
        if (!permissions.hasRecordAudio()) {  // ADDED CHECK
            Log.e(TAG, "RECORD_AUDIO permission not granted")
            state.value = PillState.Idle
            return
        }
        
        try {
            val outputFile = audioFileManager.newFile()
            currentFile = outputFile
            audioRecorder.start(outputFile)
            state.value = PillState.Recording
            Log.d(TAG, "Recording started: ${outputFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start recording", e)
            state.value = PillState.Idle
            currentFile = null
        }
    }
}
```

### 2. MainScreen.kt - Added Permission Request Flow

**Added:**
- Import `rememberLauncherForActivityResult` and `ActivityResultContracts`
- Import `PermissionManager`
- Inject `PermissionManager` into `MainViewModel`
- Created permission launcher using `ActivityResultContracts.RequestPermission()`
- Check permission before starting overlay service
- Request permission if not granted

**Changes:**
```kotlin
@HiltViewModel
class MainViewModel @Inject constructor(
    private val repository: TranscriptionRepository,
    val permissions: PermissionManager  // ADDED
) : ViewModel() {
    // ... rest of implementation
}

@Composable
fun MainScreen(
    onLogout: () -> Unit = {},
    viewModel: MainViewModel = hiltViewModel()
) {
    // ... existing code ...
    
    val permissionLauncher = rememberLauncherForActivityResult(  // ADDED
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            PillOverlayService.start(applicationContext)
        }
    }
    
    // ... existing UI code ...
    
    Button(onClick = {
        if (viewModel.permissions.hasRecordAudio()) {  // ADDED CHECK
            PillOverlayService.start(applicationContext)
        } else {
            permissionLauncher.launch(android.Manifest.permission.RECORD_AUDIO)  // REQUEST
        }
    }) {
        Text("Enable floating pill")
    }
}
```

## Files Modified

1. `app/src/main/java/com/echo/dictation/service/overlay/PillController.kt`
   - Added PermissionManager injection
   - Added permission check before recording

2. `app/src/main/java/com/echo/dictation/presentation/ui/MainScreen.kt`
   - Added PermissionManager to MainViewModel
   - Added permission request launcher
   - Check/request permission before starting overlay service

## Verification

### Before Fix
```
Error: java.lang.RuntimeException: setAudioSource failed.
Reason: RECORD_AUDIO permission not granted
```

### After Fix
1. User taps "Enable floating pill"
2. If permission not granted → System permission dialog appears
3. User grants permission → Overlay service starts
4. User taps pill → Recording starts successfully
5. MediaRecorder.setAudioSource(MIC) succeeds

## Flow Diagram

```
User taps "Enable floating pill"
         ↓
Check hasRecordAudio()
         ↓
    ┌────┴────┐
    NO       YES
    ↓         ↓
Request    Start
Permission Overlay
    ↓         ↓
User      User taps
Grants    pill
    ↓         ↓
Start     Check permission
Overlay   in PillController
    ↓         ↓
User      ┌───┴────┐
taps     NO       YES
pill     ↓         ↓
         Log      Start
         Error    Recording
                  ↓
              SUCCESS
```

## Testing

1. **First launch (no permission):**
   - Tap "Enable floating pill"
   - Permission dialog appears
   - Grant permission
   - Overlay starts
   - Tap pill → recording starts

2. **Permission already granted:**
   - Tap "Enable floating pill"
   - Overlay starts immediately
   - Tap pill → recording starts

3. **Permission denied:**
   - Tap "Enable floating pill"
   - Permission dialog appears
   - Deny permission
   - Overlay doesn't start
   - User can try again (dialog reappears)
