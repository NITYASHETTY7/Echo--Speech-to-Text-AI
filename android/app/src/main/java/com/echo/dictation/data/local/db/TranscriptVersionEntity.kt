package com.echo.dictation.data.local.db

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.echo.dictation.domain.ai.TranscriptVersion
import com.echo.dictation.domain.ai.VersionType
import org.json.JSONObject

@Entity(tableName = "transcript_versions")
data class TranscriptVersionEntity(
    @PrimaryKey val id: String,
    val transcriptId: String,
    val versionType: String,
    val createdAt: Long,
    val provider: String,
    val model: String,
    val content: String,
    val metadataJson: String = "{}",
    val syncStatus: String = "PENDING",
    val lastSyncedAt: Long? = null,
    val remoteId: String? = null,
    val syncVersion: Int = 1,
    val updatedAt: Long = System.currentTimeMillis(),
    val deleted: Boolean = false
)

fun TranscriptVersionEntity.toDomain(): TranscriptVersion {
    val meta = runCatching {
        val json = JSONObject(metadataJson)
        val map = mutableMapOf<String, String>()
        json.keys().forEach { key -> map[key] = json.getString(key) }
        map.toMap()
    }.getOrDefault(emptyMap())

    val type = runCatching { VersionType.valueOf(versionType) }.getOrDefault(VersionType.Custom)

    return TranscriptVersion(
        id = id,
        transcriptId = transcriptId,
        versionType = type,
        createdAt = createdAt,
        provider = provider,
        model = model,
        content = content,
        metadata = meta
    )
}

fun TranscriptVersion.toEntity(): TranscriptVersionEntity {
    val json = JSONObject()
    metadata.forEach { (k, v) -> json.put(k, v) }
    return TranscriptVersionEntity(
        id = id,
        transcriptId = transcriptId,
        versionType = versionType.name,
        createdAt = createdAt,
        provider = provider,
        model = model,
        content = content,
        metadataJson = json.toString()
    )
}
