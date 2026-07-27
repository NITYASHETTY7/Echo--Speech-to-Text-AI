package com.echo.dictation.domain.ai

enum class JobStatus {
    PENDING,
    PROCESSING,
    COMPLETED,
    FAILED,
    RETRYING;

    val displayName: String get() = when (this) {
        PENDING    -> "Pending"
        PROCESSING -> "Processing"
        COMPLETED  -> "Completed"
        FAILED     -> "Failed"
        RETRYING   -> "Retrying"
    }
}
