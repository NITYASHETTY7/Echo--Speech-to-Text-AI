package com.echo.dictation.ai

import com.echo.dictation.domain.ai.PromptCategory
import com.echo.dictation.domain.ai.PromptTemplate
import com.echo.dictation.domain.ai.PromptTemplateRepository
import com.echo.dictation.domain.ai.VersionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class PromptTemplateRepositoryTest {

    private lateinit var repository: PromptTemplateRepository

    @Before
    fun setUp() {
        repository = PromptTemplateRepository()
    }

    @Test
    fun testDefaultTemplatesAreLoaded() {
        val templates = repository.getAllTemplates()
        assertTrue("Should load at least 7 default templates", templates.size >= 7)
    }

    @Test
    fun testFindTemplateById() {
        val summaryTemplate = repository.getTemplate("summary")
        assertNotNull(summaryTemplate)
        assertEquals("Summary", summaryTemplate?.title)
        assertEquals(VersionType.Summary, summaryTemplate?.targetVersionType)
    }

    @Test
    fun testFilterByCategory() {
        val productivityTemplates = repository.getTemplatesByCategory(PromptCategory.PRODUCTIVITY)
        assertTrue(productivityTemplates.any { it.id == "meeting_notes" })
        assertTrue(productivityTemplates.any { it.id == "action_items" })
    }

    @Test
    fun testDynamicTemplateRegistration() {
        val customTemplate = PromptTemplate(
            id = "custom_test",
            title = "Test Template",
            description = "Test description",
            category = PromptCategory.GENERAL,
            systemPrompt = "System prompt test",
            targetVersionType = VersionType.Custom
        )
        repository.registerTemplate(customTemplate)

        val retrieved = repository.getTemplate("custom_test")
        assertNotNull(retrieved)
        assertEquals("Test Template", retrieved?.title)
    }
}
