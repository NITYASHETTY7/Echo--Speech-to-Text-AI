package com.echo.dictation.presentation.ui.auth

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.security.MessageDigest

/**
 * Logs the SHA-1 (and SHA-256) certificate fingerprint of the installed APK so
 * developers can immediately compare what the device reports vs what is registered
 * in Firebase Console / Google Cloud Console without reaching for the terminal.
 *
 * Called once per sign-in attempt from [AuthViewModel.signInWithGoogle].
 * Output is visible in Logcat under the tag "ShaFingerprintLogger".
 *
 * Registered SHA-1 values in google-services.json:
 *   26:D4:7B:81:D3:EE:99:67:54:34:9A:CB:89:EC:CA:FC:03:69:AE:B3  (Abhishek / active dev machine)
 *   3C:F9:1D:E1:87:01:CE:A1:9F:B5:14:A5:A1:81:AB:53:AB:08:6D:7F  (Narendra / secondary machine)
 *
 * Signing configuration:
 *   - build.gradle.kts reads debug.keystore.path from local.properties.
 *   - local.properties pins C:\Users\Abhishek\.android\debug.keystore.
 *   - Both SHA-1 values above are registered in google-services.json AND Firebase Console.
 *   - gradlew signingReport confirms SHA-1: 26:D4:7B:81... for all debug/release variants.
 *
 * To register a NEW machine:
 *   1. Run: gradlew signingReport   (or use this log output)
 *   2. Copy the SHA-1 shown here.
 *   3. Firebase Console → Project Settings → Android App → SHA certificate fingerprints → Add.
 *   4. Download the updated google-services.json and replace android/app/google-services.json.
 *   5. Rebuild.
 */
object ShaFingerprintLogger {

    private const val TAG = "ShaFingerprintLogger"

    /**
     * Logs the SHA-1 and SHA-256 fingerprints of the certificate(s) used to
     * sign the installed APK.  Safe to call on any thread.  Never throws.
     */
    fun logSigningCertificate(context: Context) {
        try {
            @Suppress("DEPRECATION")
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                context.packageManager
                    .getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                    .signingInfo
                    ?.apkContentsSigners
            } else {
                context.packageManager
                    .getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
                    .signatures
            }

            if (signatures.isNullOrEmpty()) {
                Log.w(TAG, "No signing certificates found for ${context.packageName}")
                return
            }

            Log.d(TAG, "╔══ APK SIGNING CERTIFICATES ═══════════════════════════════════")
            signatures.forEachIndexed { idx, sig ->
                val certBytes = sig.toByteArray()
                val sha1   = fingerprintOf(certBytes, "SHA-1")
                val sha256 = fingerprintOf(certBytes, "SHA-256")
                Log.d(TAG, "║ Certificate [$idx]")
                Log.d(TAG, "║   SHA-1  : $sha1")
                Log.d(TAG, "║   SHA-256: $sha256")
            }
            Log.d(TAG, "╠══ EXPECTED (in google-services.json) ═════════════════════════")
            Log.d(TAG, "║   SHA-1 #1: 26:D4:7B:81:D3:EE:99:67:54:34:9A:CB:89:EC:CA:FC:03:69:AE:B3")
            Log.d(TAG, "║   SHA-1 #2: 3C:F9:1D:E1:87:01:CE:A1:9F:B5:14:A5:A1:81:AB:53:AB:08:6D:7F")
            Log.d(TAG, "║")
            Log.d(TAG, "║  If the SHA-1 above is NOT in the expected list:")
            Log.d(TAG, "║   → Register it in Firebase Console → Project Settings → Android App")
            Log.d(TAG, "║   → Re-download google-services.json and rebuild")
            Log.d(TAG, "╚═══════════════════════════════════════════════════════════════")
        } catch (e: Exception) {
            Log.w(TAG, "Could not read signing certificates: ${e.message}")
        }
    }

    private fun fingerprintOf(bytes: ByteArray, algorithm: String): String {
        val digest = MessageDigest.getInstance(algorithm).digest(bytes)
        return digest.joinToString(":") { "%02X".format(it) }
    }
}
