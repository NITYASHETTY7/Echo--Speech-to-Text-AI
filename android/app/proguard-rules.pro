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

# ── Kotlin Coroutines ─────────────────────────────────────────────────────────
-keep class kotlin.coroutines.Continuation { *; }
-keepclassmembers class * implements kotlin.coroutines.Continuation {
    public <init>(...);
    public java.lang.Object invokeSuspend(java.lang.Object);
    public kotlin.coroutines.CoroutineContext getContext();
}
-keep class kotlin.coroutines.intrinsics.** { *; }
-keepclassmembers class kotlinx.coroutines.** { *; }
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory { *; }
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler { *; }
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

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

# ── Retrofit ──────────────────────────────────────────────────────────────────
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepclassmembers,allowshrinking,allowobfuscation interface * {
    @retrofit2.http.* <methods>;
}
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}
-keep class retrofit2.KotlinExtensions { *; }
-keep class retrofit2.KotlinExtensions$* { *; }

# ── OkHttp ────────────────────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-keep class okhttp3.internal.** { *; }
-keep class okhttp3.internal.platform.** { *; }
-dontwarn okhttp3.internal.**

# ── Gson ──────────────────────────────────────────────────────────────────────
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory { *; }
-keep class * implements com.google.gson.JsonSerializer { *; }
-keep class * implements com.google.gson.JsonDeserializer { *; }

# ── Speech provider package ───────────────────────────────────────────────────
# All provider classes, configs, and result models must survive R8 intact.
-keep class com.echo.dictation.speech.provider.** { *; }

# ── Domain / data models ──────────────────────────────────────────────────────
-keep class com.echo.dictation.domain.model.** { *; }
-keep class com.echo.dictation.data.local.db.** { *; }

# ── Accessibility service ─────────────────────────────────────────────────────
-keep class com.echo.dictation.core.accessibility.TextInsertionAccessibilityService { *; }
-keep class com.echo.dictation.core.accessibility.TextInsertionHelper { *; }

# ── Hilt entry points ─────────────────────────────────────────────────────────
-keep @dagger.hilt.EntryPoint interface * { *; }

# ── Android components ────────────────────────────────────────────────────────
-keep class com.echo.dictation.service.BootReceiver { *; }
-keep class com.echo.dictation.service.overlay.PillOverlayService { *; }
-keep class com.echo.dictation.MainActivity { *; }
-keep class com.echo.dictation.EchoApplication { *; }

# ── Security Crypto ───────────────────────────────────────────────────────────
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi

# ── Timber ────────────────────────────────────────────────────────────────────
-dontwarn org.jetbrains.annotations.**
