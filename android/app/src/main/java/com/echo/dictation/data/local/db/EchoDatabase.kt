package com.echo.dictation.data.local.db

import androidx.room.Database
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Dao
import androidx.room.Query
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.RoomDatabase
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "transcriptions")
data class TranscriptionEntity(@PrimaryKey val id: String, val text: String, val timestamp: Long, val model: String, val audioPath: String?, val userId: String, val synced: Boolean)
@Dao interface TranscriptionDao { @Query("SELECT * FROM transcriptions ORDER BY timestamp DESC LIMIT :limit") fun observe(limit: Int): Flow<List<TranscriptionEntity>>; @Query("SELECT * FROM transcriptions") suspend fun all(): List<TranscriptionEntity>; @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insertAll(items: List<TranscriptionEntity>); @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insert(item: TranscriptionEntity); @Query("DELETE FROM transcriptions WHERE id = :id") suspend fun delete(id: String) }
@Database(entities = [TranscriptionEntity::class], version = 1, exportSchema = true)
abstract class EchoDatabase : RoomDatabase() { abstract fun transcriptions(): TranscriptionDao }
