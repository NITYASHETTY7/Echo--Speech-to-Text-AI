# =============================================================================
# Echo – ProGuard / R8 rules for release builds
# =============================================================================

# ── Kotlin ────────────────────────────────────────────────────────────────────
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations
-keepattributes AnnotationDefault
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }
-keep class kotlin.Metadata { *; }

# ── Hilt / Dagger ─────────────────────────────────────────────────────────────
-keep class dagger.hilt.** { *; }
-keep @dagger.hilt.android.HiltAndroidApp class * { *; }
-keep @dagger.hilt.android.AndroidEntryPoint class * { *; }
-keep @dagger.hilt.InstallIn class * { *; }
-keep @javax.inject.Singleton class * { *; }
-keepclassmembers class * {
    @javax.inject.Inject <init>(...);
    @javax.inject.Inject <fields>;
}
-dontwarn dagger.**
-dontwarn javax.annotation.**

# ── Room ──────────────────────────────────────────────────────────────────────
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }
-keepclassmembers @androidx.room.Entity class * { <fields>; }

# ── Retrofit + OkHttp ─────────────────────────────────────────────────────────
-dontwarn retrofit2.**
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class retrofit2.** { *; }
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# ── Gson ──────────────────────────────────────────────────────────────────────
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory { *; }
-keep class * implements com.google.gson.JsonSerializer { *; }
-keep class * implements com.google.gson.JsonDeserializer { *; }

# Keep all Groq API response models so Gson can deserialize them
-keep class com.echo.dictation.speech.GroqTranscriptionResponse { *; }
-keep class com.echo.dictation.speech.GroqSegment { *; }

# ── Domain / data models (Room entities + domain models used by Gson) ─────────
-keep class com.echo.dictation.domain.model.** { *; }
-keep class com.echo.dictation.data.local.db.** { *; }

# ── Accessibility service ─────────────────────────────────────────────────────
# System binds AccessibilityService by name — never rename or remove it.
-keep class com.echo.dictation.core.accessibility.TextInsertionAccessibilityService { *; }
# TextInsertionHelper is Hilt-injected and accesses the service via companion object.
-keep class com.echo.dictation.core.accessibility.TextInsertionHelper { *; }

# ── Hilt entry points ─────────────────────────────────────────────────────────
-keep @dagger.hilt.EntryPoint interface * { *; }
-keep class com.echo.dictation.EchoApplication$AppEntryPoint { *; }

# ── Android components ────────────────────────────────────────────────────────
-keep class com.echo.dictation.service.BootReceiver { *; }
-keep class com.echo.dictation.service.overlay.PillOverlayService { *; }
-keep class com.echo.dictation.MainActivity { *; }
-keep class com.echo.dictation.EchoApplication { *; }

# ── Security Crypto ───────────────────────────────────────────────────────────
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**
# errorprone annotations are compile-only and not present at runtime;
# they are pulled in transitively by tink (used by security-crypto).
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi

# ── Coroutines ────────────────────────────────────────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory { *; }
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler { *; }
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.**

# ── Timber ────────────────────────────────────────────────────────────────────
-dontwarn org.jetbrains.annotations.**
