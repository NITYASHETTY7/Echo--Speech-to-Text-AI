package com.echo.dictation.ui

import com.echo.dictation.presentation.ui.util.parseMarkdownToAnnotatedString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownRendererTest {

    @Test
    fun testParseMarkdownBoldStripsAsterisksAndPreservesText() {
        val markdown = "**Meeting Summary**\nDiscussed the launch timeline."
        val result = parseMarkdownToAnnotatedString(markdown)

        val plainText = result.text
        assertEquals("Meeting Summary\nDiscussed the launch timeline.", plainText)
        assertTrue(!plainText.contains("**"))
    }

    @Test
    fun testParseMarkdownBoldAndBulletsStripsSymbols() {
        val markdown = "**Project Timeline**\n* Important point\n**Action Items**\n1. Task 1"
        val result = parseMarkdownToAnnotatedString(markdown)

        val plainText = result.text
        val expected = "Project Timeline\n• Important point\nAction Items\n1. Task 1"
        assertEquals(expected, plainText)
        assertTrue(!plainText.contains("**"))
        assertTrue(!plainText.startsWith("* "))
    }

    @Test
    fun testParseMarkdownHeadings() {
        val markdown = "# Meeting Notes\n## Overview\nContent line"
        val result = parseMarkdownToAnnotatedString(markdown)

        val plainText = result.text
        val expected = "Meeting Notes\nOverview\nContent line"
        assertEquals(expected, plainText)
        assertTrue(!plainText.contains("#"))
    }

    @Test
    fun testParseMarkdownUnderscoreBoldAndItalic() {
        val markdown = "__Bold Title__\n*Italic note*"
        val result = parseMarkdownToAnnotatedString(markdown)

        val plainText = result.text
        val expected = "Bold Title\nItalic note"
        assertEquals(expected, plainText)
        assertTrue(!plainText.contains("__"))
        assertTrue(!plainText.contains("*"))
    }

    @Test
    fun testEmptyOrBlankStringFallback() {
        val result = parseMarkdownToAnnotatedString("")
        assertEquals("", result.text)
    }
}
