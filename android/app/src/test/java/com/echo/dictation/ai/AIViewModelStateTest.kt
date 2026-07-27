package com.echo.dictation.ai

import com.echo.dictation.presentation.ai.AiUiState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AIViewModelStateTest {

    @Test
    fun testCustomPromptValidationEmptyFails() {
        val state = AiUiState(customPromptText = "   ")
        assertFalse("Blank prompt should be invalid", state.isCustomPromptValid)
    }

    @Test
    fun testCustomPromptValidationValidPasses() {
        val state = AiUiState(customPromptText = "Rewrite as legal summary")
        assertTrue("Valid prompt under 500 chars should be valid", state.isCustomPromptValid)
    }

    @Test
    fun testCustomPromptValidationExceedingLimitFails() {
        val longText = "a".repeat(501)
        val state = AiUiState(customPromptText = longText)
        assertFalse("Prompt exceeding 500 chars should be invalid", state.isCustomPromptValid)
    }
}
