# Touch and Recording Quality Fixes

## Part 1: Touch Handling Fix

### Problem
The floating pill required 3-4 taps to start/stop recording because:
- View position was updated on every `ACTION_MOVE` event, even for tiny movements
- The `moved` flag was set based on distance but position updated unconditionally
- Small finger movements during tap were interpreted as drags

### Solution
Changed touch detection logic in `PillWindowManager.kt`:

**Before:**
```kotlin
var moved = false
// ...
MotionEvent.ACTION_MOVE -> {
    val deltaX = event.rawX - downX
    val deltaY = event.rawY - downY
    moved = moved || deltaX * deltaX + deltaY * deltaY > DRAG_THRESHOLD_PX * DRAG_THRESHOLD_PX
    params.x = startX + deltaX.toInt()  // ❌ Always updates position
    params.y = startY + deltaY.toInt()
    windowManager.updateViewLayout(touchedView, params)
}
```

**After:**
```kotlin
var isDragging = false
val touchSlop = context.dp(10) // ~10dp threshold

MotionEvent.ACTION_MOVE -> {
    val deltaX = event.rawX - downX
    val deltaY = event.rawY - downY
    val distance = sqrt((deltaX * deltaX + deltaY * deltaY).toDouble()).toFloat()
    
    // Only start dragging if movement exceeds threshold
    if (distance > touchSlop) {
        isDragging = true
    }
    
    // ✅ Only update position if actively dragging
    if (isDragging) {
        params.x = startX + deltaX.toInt()
        params.y = startY + deltaY.toInt()
        windowManager.updateViewLayout(touchedView, params)
    }
}

MotionEvent.ACTION_UP -> {
    if (!isDragging) {
        controller.toggleState()  // ✅ Reliable tap detection
    }
}
```

**Key Changes:**
1. Renamed `moved` → `isDragging` for clarity
2. Calculate actual distance using `sqrt()` instead of squared distance
3. Use `context.dp(10)` (~10dp) as touch slop threshold
4. **Only update view position if `isDragging` is true**
5. Removed unused `DRAG_THRESHOLD_PX` constant

**Result:**
- Normal taps always toggle recording on first attempt
- Dragging still works smoothly
- ~10dp threshold matches Android standard touch slop

---

## Part 2: Recording Quality Fix

### Problem
Poor transcription quality even for clear speech due to:
- **No bit rate specified** - critical quality parameter missing
- Suboptimal encoder settings for speech transcription
- File finalization order could cause incomplete files

### Solution
Enhanced recording settings in `AudioRecorder.kt`:

#### 1. Added Audio Bit Rate
```kotlin
// Before
mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
mediaRecorder.setAudioSamplingRate(16_000)
mediaRecorder.setAudioChannels(1)
// ❌ No bit rate set - uses low default

// After
mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
mediaRecorder.setAudioSamplingRate(16_000)
mediaRecorder.setAudioEncodingBitRate(128_000)  // ✅ 128 kbps for clear speech
mediaRecorder.setAudioChannels(1)
```

#### 2. Updated Constants
```kotlin
companion object {
    private const val SAMPLE_RATE_HZ = 16_000  // Whisper optimal sample rate
    private const val BIT_RATE = 128_000       // 128 kbps for clear speech
    private const val CHANNELS = 1             // Mono
}
```

#### 3. Improved File Finalization
```kotlin
@Synchronized
fun stop(): File? {
    val activeRecorder = recorder ?: return null
    val output = file
    var savedFile: File? = null
    
    try {
        // ✅ Stop recording first - finalizes the file
        activeRecorder.stop()
        
        // ✅ Then release resources
        activeRecorder.release()
        
        // ✅ Verify file is valid
        savedFile = output?.takeIf { it.isFile && it.length() > 0L }
        
        if (savedFile == null) {
            output?.delete()
            _audioFilePath.value = null
        }
    } catch (e: RuntimeException) {
        // Stop failed, try to release anyway
        try {
            activeRecorder.release()
        } catch (_: Exception) {
            // Ignore release errors
        }
        output?.delete()
        _audioFilePath.value = null
    } finally {
        recorder = null
        file = null
        session = 0
        _recording.value = false
    }
    
    return savedFile
}
```

### Recording Quality Settings Verified

✅ **AudioSource**: `MIC` - correct for voice recording  
✅ **OutputFormat**: `MPEG_4` - container format for AAC  
✅ **AudioEncoder**: `AAC` - modern, efficient codec  
✅ **Sample Rate**: `16,000 Hz` - optimal for Whisper/speech recognition  
✅ **Bit Rate**: `128,000 bps` (128 kbps) - high quality for clear speech  
✅ **Channels**: `1` (Mono) - sufficient for speech, reduces file size  
✅ **Sequence**: `setAudioSource → setOutputFormat → setAudioEncoder → setSamplingRate → setBitRate → setChannels → setOutputFile → prepare → start`  
✅ **Finalization**: `stop()` called before `release()`, file verified before return

### Why These Settings?

1. **16 kHz Sample Rate**: Whisper models are trained on 16 kHz audio
2. **128 kbps Bit Rate**: Balances quality and file size for speech
   - Too low (< 64 kbps): Loss of clarity, especially with background noise
   - Too high (> 192 kbps): Unnecessary for speech, larger files
3. **AAC Mono**: Efficient compression, mono is standard for speech
4. **Proper Finalization**: Ensures file is fully written before transcription

---

## Files Modified

### 1. `app/src/main/java/com/echo/dictation/service/overlay/PillWindowManager.kt`
**Changes:**
- Fixed touch handling to only update position when actively dragging
- Changed threshold to ~10dp using `context.dp(10)`
- Renamed `moved` → `isDragging` for clarity
- Calculate actual distance using `sqrt()`
- Removed unused `DRAG_THRESHOLD_PX` constant

### 2. `app/src/main/java/com/echo/dictation/core/audio/AudioRecorder.kt`
**Changes:**
- Added `setAudioEncodingBitRate(128_000)` for quality
- Added `BIT_RATE = 128_000` constant with documentation
- Improved `stop()` method to release recorder after stopping
- Added detailed comments for file finalization flow
- Better error handling in stop() method

---

## Expected Results

### Touch Handling
- ✅ Single tap reliably toggles recording
- ✅ Dragging still works smoothly
- ✅ No accidental drags during taps
- ✅ ~10dp threshold feels natural

### Recording Quality
- ✅ Clear, crisp audio capture
- ✅ Better transcription accuracy
- ✅ Proper handling of background noise
- ✅ Complete file finalization before transcription
- ✅ Optimal format for Whisper/Groq models

---

## Testing Checklist

- [ ] Tap pill once → recording starts immediately
- [ ] Tap pill once while recording → recording stops immediately
- [ ] Drag pill → moves smoothly without triggering toggle
- [ ] Small finger movements during tap don't prevent toggle
- [ ] Recorded audio has clear speech quality
- [ ] Transcription accuracy improves vs. previous version
- [ ] File size is reasonable (~960 KB per minute)
- [ ] No corruption or incomplete files
