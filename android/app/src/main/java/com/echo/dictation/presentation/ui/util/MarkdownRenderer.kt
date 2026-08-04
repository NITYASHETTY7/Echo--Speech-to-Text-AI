package com.echo.dictation.presentation.ui.util

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight

/**
 * Parses markdown formatted text into an [AnnotatedString] for display in Jetpack Compose UI.
 *
 * Supported features:
 *  - Bold text (`**text**` or `__text__`) rendered as [FontWeight.Bold]
 *  - Italic text (`*text*` or `_text_`) rendered as [FontStyle.Italic]
 *  - Bold Italic text (`***text***` or `___text___`)
 *  - Headings (`# Heading`, `## Heading`, etc.) rendered bold without `#` symbols
 *  - Bullet lists (`* item`, `- item`, `+ item`) converted to `• item`
 *  - Numbered lists (`1. item`, `2. item`) preserved
 *  - Line breaks and spacing preserved
 *  - Strips literal markdown formatting characters (`**`, `*`, `__`, `_`, `#`)
 *  - Graceful fallback to plain text if parsing fails
 */
fun parseMarkdownToAnnotatedString(markdown: String): AnnotatedString {
    if (markdown.isBlank()) return AnnotatedString(markdown)

    return try {
        buildAnnotatedString {
            val lines = markdown.split("\n")
            lines.forEachIndexed { lineIndex, line ->
                var processedLine = line
                var isHeading = false

                // 1. Process Headings (# Heading, ## Heading, etc.)
                val headingRegex = Regex("""^(#{1,6})\s+(.*)$""")
                val headingMatch = headingRegex.matchEntire(processedLine.trimEnd())
                if (headingMatch != null) {
                    isHeading = true
                    processedLine = headingMatch.groupValues[2]
                }

                // 2. Process Bullet items (* item, - item, + item)
                val bulletRegex = Regex("""^(\s*)([*+-])\s+(.*)$""")
                val bulletMatch = bulletRegex.matchEntire(processedLine)
                var isBullet = false
                var bulletIndent = ""
                var bulletContent = ""
                if (bulletMatch != null && !processedLine.trimStart().startsWith("**")) {
                    isBullet = true
                    bulletIndent = bulletMatch.groupValues[1]
                    bulletContent = bulletMatch.groupValues[3]
                }

                val lineToParse = if (isBullet) bulletContent else processedLine

                if (isBullet) {
                    append(bulletIndent)
                    append("• ")
                }

                // 3. Process Inline Markdown (bold, italic, bold-italic)
                appendInlineMarkdown(lineToParse, forceBold = isHeading)

                if (lineIndex < lines.size - 1) {
                    append("\n")
                }
            }
        }
    } catch (e: Exception) {
        AnnotatedString(markdown)
    }
}

private fun AnnotatedString.Builder.appendInlineMarkdown(text: String, forceBold: Boolean = false) {
    if (text.isEmpty()) return

    val regex = Regex(
        """(?:\*\*\*(.*?)\*\*\*)|(?:___(.*?)___)|(?:\*\*(.*?)\*\*)|(?:__(.*?)__)|(?:\*(.*?)\*)|(?:_(.*?)_)|([^*_]+|[*_])""",
        RegexOption.DOT_MATCHES_ALL
    )

    val matches = regex.findAll(text)
    var matchedAny = false

    for (match in matches) {
        matchedAny = true
        val g1BoldItalicStar = match.groups[1]?.value
        val g2BoldItalicUnder = match.groups[2]?.value
        val g3BoldStar = match.groups[3]?.value
        val g4BoldUnder = match.groups[4]?.value
        val g5ItalicStar = match.groups[5]?.value
        val g6ItalicUnder = match.groups[6]?.value
        val g7Plain = match.groups[7]?.value

        when {
            g1BoldItalicStar != null || g2BoldItalicUnder != null -> {
                val content = g1BoldItalicStar ?: g2BoldItalicUnder ?: ""
                val start = length
                append(content)
                addStyle(
                    SpanStyle(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic),
                    start,
                    length
                )
            }
            g3BoldStar != null || g4BoldUnder != null -> {
                val content = g3BoldStar ?: g4BoldUnder ?: ""
                val start = length
                append(content)
                addStyle(
                    SpanStyle(fontWeight = FontWeight.Bold),
                    start,
                    length
                )
            }
            g5ItalicStar != null || g6ItalicUnder != null -> {
                val content = g5ItalicStar ?: g6ItalicUnder ?: ""
                val start = length
                append(content)
                if (forceBold) {
                    addStyle(
                        SpanStyle(fontWeight = FontWeight.Bold, fontStyle = FontStyle.Italic),
                        start,
                        length
                    )
                } else {
                    addStyle(
                        SpanStyle(fontStyle = FontStyle.Italic),
                        start,
                        length
                    )
                }
            }
            g7Plain != null -> {
                val start = length
                append(g7Plain)
                if (forceBold) {
                    addStyle(
                        SpanStyle(fontWeight = FontWeight.Bold),
                        start,
                        length
                    )
                }
            }
            else -> {
                val start = length
                append(match.value)
                if (forceBold) {
                    addStyle(
                        SpanStyle(fontWeight = FontWeight.Bold),
                        start,
                        length
                    )
                }
            }
        }
    }

    if (!matchedAny) {
        val start = length
        append(text)
        if (forceBold) {
            addStyle(SpanStyle(fontWeight = FontWeight.Bold), start, length)
        }
    }
}
