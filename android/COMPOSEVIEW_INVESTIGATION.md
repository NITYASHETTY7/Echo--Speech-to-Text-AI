# ComposeView Crash Investigation

## Project Details
- **Path:** `C:\Users\Abhishek\Downloads\WhisperFlow\android`
- **Package:** `com.echo.dictation`
- **APK:** `app\build\intermediates\apk\debug\app-debug.apk`

## Crash Details
```
java.lang.IllegalStateException:
ViewTreeLifecycleOwner not found from androidx.compose.ui.platform.ComposeView
```

## Investigation Summary

### 1. Source Code Analysis ✅

**Searched entire codebase for:**
- `ComposeView`, `AbstractComposeView`, `AndroidComposeView` - **NOT FOUND**
- `setContent {}` - Found only in `MainActivity:19` (Activity, not overlay)
- `WindowManager.addView()` - Found only in `PillWindowManager:160`
- `ViewCompositionStrategy`, `rememberCompositionContext`, `WindowRecomposer` - **NOT FOUND**

**Confirmed single implementations:**
- `PillWindowManager` at line 29-247
- `PillOverlayService` at line 20-124
- `PillController` at line 25-102
- `AudioLevelView` at line 252-315

**Overlay view hierarchy created in code:**
```
FrameLayout (pill)
└── LinearLayout (container)
    ├── ImageView (micIcon)
    ├── TextView (statusText)
    └── AudioLevelView (custom View)
```

### 2. Dependencies Analysis ✅

**build.gradle.kts dependencies:**
- Standard Compose BOM (2024.10.01)
- `androidx.compose.ui:ui`
- `androidx.compose.ui:ui-tooling-preview`
- `debugImplementation("androidx.compose.ui:ui-tooling")` ⚠️
- No third-party overlay/floating/bubble libraries

**Merged manifest findings:**
```xml
<activity
    android:name="androidx.compose.ui.tooling.PreviewActivity"
    android:exported="true" />
```
This activity is injected by `ui-tooling` debug dependency but no code in the project launches it.

### 3. Instrumentation Added ✅

**Modified:** `app/src/main/java/com/echo/dictation/service/overlay/PillWindowManager.kt`

**Added imports:**
```kotlin
import android.util.Log
import android.view.ViewGroup
```

**Added before `windowManager.addView(pill, params)` at line 161:**
```kotlin
Log.e("OVERLAY_ADD", "=== ABOUT TO ADD VIEW TO WINDOWMANAGER ===")
Log.e("OVERLAY_ADD", "View class: ${pill.javaClass.name}")
Log.e("OVERLAY_ADD", "View ID: ${pill.id}")
Log.e("OVERLAY_ADD", "RootView: ${pill.rootView.javaClass.name}")
Log.e("OVERLAY_ADD", "View hierarchy dump:")
dump(pill)
Log.e("OVERLAY_ADD", "=== END VIEW DUMP ===")
```

**Added diagnostic function:**
```kotlin
private fun dump(view: View, indent: String = "") {
    val className = view.javaClass.name
    Log.e("VIEWTREE", indent + className)
    
    // Check if this is a ComposeView
    if (className.contains("Compose")) {
        Log.e("COMPOSE_FOUND", "=== COMPOSEVIEW DETECTED ===")
        Log.e("COMPOSE_FOUND", "Class: $className")
        Log.e("COMPOSE_FOUND", "RootView: ${view.rootView.javaClass.name}")
        Log.e("COMPOSE_FOUND", "Stack trace:")
        Log.e("COMPOSE_FOUND", Log.getStackTraceString(Throwable()))
        
        // Try to get lifecycle owner
        try {
            val lifecycleOwnerClass = Class.forName("androidx.lifecycle.ViewTreeLifecycleOwner")
            val getMethod = lifecycleOwnerClass.getMethod("get", View::class.java)
            val owner = getMethod.invoke(null, view)
            Log.e("COMPOSE_FOUND", "ViewTreeLifecycleOwner: $owner")
        } catch (e: Exception) {
            Log.e("COMPOSE_FOUND", "Failed to get ViewTreeLifecycleOwner: ${e.message}")
        }
    }
    
    if (view is ViewGroup) {
        for (i in 0 until view.childCount) {
            dump(view.getChildAt(i), indent + "  ")
        }
    }
}
```

## Next Steps - REQUIRES DEVICE CONNECTION

### Build and Install
```powershell
# Find Java if needed
$javaHome = "C:\Program Files\Android\Android Studio\jbr"
$env:JAVA_HOME = $javaHome

# Build
.\gradlew.bat assembleDebug

# Install
& 'C:\Users\Abhishek\AppData\Local\Android\Sdk\platform-tools\adb.exe' install -r app\build\intermediates\apk\debug\app-debug.apk
```

### Capture Logs
```powershell
# Start logcat monitoring (in separate terminal)
& 'C:\Users\Abhishek\AppData\Local\Android\Sdk\platform-tools\adb.exe' logcat -s OVERLAY_ADD:E VIEWTREE:E COMPOSE_FOUND:E

# Or capture all logs
& 'C:\Users\Abhishek\AppData\Local\Android\Sdk\platform-tools\adb.exe' logcat > crash_log.txt
```

### Reproduce
1. Launch app
2. Tap "Enable floating pill"
3. Observe logs

### Expected Output

**If NO ComposeView exists (expected based on code):**
```
OVERLAY_ADD: === ABOUT TO ADD VIEW TO WINDOWMANAGER ===
OVERLAY_ADD: View class: android.widget.FrameLayout
VIEWTREE: android.widget.FrameLayout
VIEWTREE:   android.widget.LinearLayout
VIEWTREE:     android.widget.ImageView
VIEWTREE:     android.widget.TextView
VIEWTREE:     com.echo.dictation.service.overlay.AudioLevelView
OVERLAY_ADD: === END VIEW DUMP ===
```

**If ComposeView IS somehow present:**
```
COMPOSE_FOUND: === COMPOSEVIEW DETECTED ===
COMPOSE_FOUND: Class: androidx.compose.ui.platform.ComposeView
COMPOSE_FOUND: RootView: ...
COMPOSE_FOUND: Stack trace:
... (full stack trace showing where ComposeView was created)
```

## Theories to Test

1. **Different APK installed** - The installed APK may be from a different version of the code
2. **Runtime injection** - Some library or Android framework creates ComposeView at runtime
3. **Hilt/Dagger injection** - Dependency injection might be creating a view
4. **Android System behavior** - On certain Android versions, the system might wrap overlays

## Files Modified
- `app/src/main/java/com/echo/dictation/service/overlay/PillWindowManager.kt`
