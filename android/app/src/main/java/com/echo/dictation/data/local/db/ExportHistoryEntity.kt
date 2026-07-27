package com.echo.dictation.data.local.db

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import com.echo.dictation.domain.export.ExportFormat
import com.echo.dictation.domain.export.ExportHistory
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "export_history")
data class ExportHistoryEntity(
    @PrimaryKey val id: String,
    val transcriptId: String,
    val versionId: String?,
    val exportType: String,
    val timestamp: Long,
    val destination: String,
    val success: Boolean,
    val filePath: String?
)

fun ExportHistoryEntity.toDomain(): ExportHistory = ExportHistory(
    id = id,
    transcriptId = transcriptId,
    versionId = versionId,
    exportType = runCatching { ExportFormat.valueOf(exportType) }.getOrDefault(ExportFormat.TXT),
    timestamp = timestamp,
    destination = destination,
    success = success,
    filePath = filePath
)

fun ExportHistory.toEntity(): ExportHistoryEntity = ExportHistoryEntity(
    id = id,
    transcriptId = transcriptId,
    versionId = versionId,
    exportType = exportType.name,
    timestamp = timestamp,
    destination = destination,
    success = success,
    filePath = filePath
)

@Dao
interface ExportHistoryDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertExport(history: ExportHistoryEntity)

    @Query("SELECT * FROM export_history ORDER BY timestamp DESC")
    fun observeHistory(): Flow<List<ExportHistoryEntity>>
}
