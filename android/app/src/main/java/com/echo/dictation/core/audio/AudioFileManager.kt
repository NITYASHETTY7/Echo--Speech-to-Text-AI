package com.echo.dictation.core.audio

import android.content.Context
import android.os.Environment
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AudioFileManager @Inject constructor(@ApplicationContext context: Context) {
    private val directory = (context.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: context.filesDir)
        .resolve("recordings")
        .also { check(it.exists() || it.mkdirs()) { "Unable to create recordings directory" } }

    fun newFile(): File {
        var candidate: File
        do {
            candidate = directory.resolve("recording_${System.currentTimeMillis()}.m4a")
        } while (candidate.exists())
        return candidate
    }

    fun lastFile(): File? = directory.listFiles()
        ?.filter { it.isFile && it.extension.equals("m4a", ignoreCase = true) }
        ?.maxByOrNull { it.lastModified() }
}
