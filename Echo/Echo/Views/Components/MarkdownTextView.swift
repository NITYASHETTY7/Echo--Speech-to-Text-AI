//
//  MarkdownTextView.swift
//  Echo
//
//  Renders AI-generated Markdown text correctly in SwiftUI.
//
//  Problem
//  -------
//  LLMs produce inconsistent Markdown. Common artefacts that cause visible
//  syntax characters in the UI:
//
//    Symmetric (clean but not handled by .inlineOnlyPreservingWhitespace):
//      **Heading**       * Heading:      ## Heading
//
//    Asymmetric / malformed (emphasis marker left dangling):
//      **Heading**:      Topic**:        **Topic:
//      *Topic*:          Heading*:       *Topic:
//      **Heading :       *Action Items** **Decisions Made**
//
//  AttributedString(.inlineOnlyPreservingWhitespace) handles inline bold
//  correctly ONLY when the markers are perfectly balanced inside a line.
//  A trailing "**" after ":" breaks the parser and the markers appear
//  literally (e.g. "Topic**:").
//
//  Solution
//  --------
//  1. Split the raw text into lines.
//  2. Classify each line as heading | body | blank.
//  3. For headings, strip ALL emphasis markers and render with .bold.
//  4. For body lines that contain stray markers, run a normalization pass
//     so AttributedString never receives broken Markdown.
//  5. Genuine list items (-, +, •, 1.) are always treated as body.
//

import SwiftUI

// MARK: - MarkdownTextView

struct MarkdownTextView: View {

    let text: String
    /// true  = AI-generated content (full Markdown processing).
    /// false = Original transcript (shown verbatim, no processing).
    var isMarkdown: Bool = true

    var body: some View {
        if isMarkdown {
            markdownContent
        } else {
            plainContent
        }
    }

    // MARK: - Plain (Original tab)

    private var plainContent: some View {
        Text(text.isEmpty ? "No text transcribed." : text)
            .font(.body)
            .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Markdown (AI versions)

    private var markdownContent: some View {
        if text.isEmpty {
            return AnyView(
                Text("No text transcribed.")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        }

        let blocks = MarkdownParser.parse(text)

        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(blocks.indices, id: \.self) { i in
                    blockView(for: blocks[i])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    @ViewBuilder
    private func blockView(for block: MarkdownParser.Block) -> some View {
        switch block {
        case .heading(let headingText):
            Text(headingText)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

        case .body(let raw):
            // Body lines have already been normalized by MarkdownParser —
            // stray markers are stripped. Pass through AttributedString for
            // legitimate inline bold/italic rendering.
            if let attributed = try? AttributedString(
                markdown: raw,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            ) {
                Text(attributed)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(raw)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .blank:
            Spacer().frame(height: 6)
        }
    }
}

// MARK: - MarkdownParser

enum MarkdownParser {

    enum Block {
        case heading(String)   // stripped plain text, rendered bold
        case body(String)      // normalized line, rendered with inline Markdown
        case blank             // empty line, rendered as spacing
    }

    // MARK: - Public parse entry point

    static func parse(_ raw: String) -> [Block] {
        let lines = raw.components(separatedBy: "\n")
        var blocks: [Block] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                blocks.append(.blank)
                continue
            }

            if let heading = extractHeading(from: trimmed) {
                blocks.append(.heading(heading))
            } else {
                // Normalize body lines: remove stray/dangling markers so
                // AttributedString never receives broken inline Markdown.
                let normalized = normalizeBodyLine(line)
                blocks.append(.body(normalized))
            }
        }

        return collapseConsecutiveBlanks(blocks)
    }

    // MARK: - Heading extraction

    /// Returns the plain heading text (all markers stripped) for any line that
    /// matches a heading pattern, or nil when the line is a body/list line.
    ///
    /// Recognized heading patterns (in priority order):
    ///
    ///   ATX:           # Title       ## Title
    ///   Full bold:     **Title**     **Title:**     **Title** :
    ///   Full italic:   *Title*       *Title:*
    ///   Mixed:         **Title*      *Title**       **Title:     Title**:
    ///   Bullet+bold:   * **Title**   * **Title:**   * Title:
    ///   Double-star:   ** Title:     ** Key Points
    ///
    /// NOT promoted (inline bold inside a sentence):
    ///   "See **this** for details."  — markers are mid-line, not at edges
    static func extractHeading(from line: String) -> String? {
        // Never re-classify genuine list items.
        if isListItem(line) { return nil }

        // 1. ATX headings: # / ## / ### …
        if line.hasPrefix("#") {
            let rest = line.drop(while: { $0 == "#" })
            if rest.hasPrefix(" ") {
                return stripAllEmphasis(String(rest.dropFirst()))
            }
        }

        // 2. Only proceed when the emphasis markers are structural, i.e. they
        //    appear at the START or END of the trimmed line (not only in the
        //    middle). Mid-line-only markers are inline bold in a sentence.
        guard lineContainsEmphasisMarkers(line) else { return nil }
        guard emphasisIsAtEdge(line) else { return nil }

        // Strip ALL leading emphasis tokens to get the bare candidate text.
        let deLeaded = stripLeadingEmphasisTokens(line)
        let candidate = stripAllEmphasis(deLeaded)

        // The candidate must be non-empty and look like a heading label
        // (short, no mid-sentence punctuation).
        guard !candidate.isEmpty, looksLikeHeading(candidate) else { return nil }

        return candidate
    }

    /// Returns true when emphasis markers (`**`, `*`) appear at the very start
    /// or very end of the trimmed line (possibly separated by whitespace from
    /// content).  This distinguishes structural heading wrappers from inline
    /// bold spans that appear only in the middle of a sentence.
    private static func emphasisIsAtEdge(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        // Starts with an emphasis token
        let startsWithEmphasis = t.hasPrefix("**") || t.hasPrefix("__") ||
                                 t.hasPrefix("* ") || t.hasPrefix("* *") ||
                                 (t.hasPrefix("*") && !t.hasPrefix("* "))
        // Ends with an emphasis token (possibly followed by ":" or whitespace)
        let stripped = t.hasSuffix(":") ? String(t.dropLast()) : t
        let endsWithEmphasis  = stripped.hasSuffix("**") || stripped.hasSuffix("__") ||
                                stripped.hasSuffix("*")  || stripped.hasSuffix("_")
        return startsWithEmphasis || endsWithEmphasis
    }

    // MARK: - Body line normalization

    /// Removes stray/dangling emphasis markers from a body line so that
    /// AttributedString never receives broken inline Markdown.
    ///
    /// Only touches lines that contain "*" or "_" — clean lines are returned
    /// as-is to preserve formatting.
    private static func normalizeBodyLine(_ line: String) -> String {
        guard lineContainsEmphasisMarkers(line) else { return line }

        // Preserve leading whitespace (indentation / list continuation).
        let leadingWS = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Strategy:
        // - If the trimmed line has dangling/unbalanced markers at the edges,
        //   strip everything and return clean plain text.
        // - Otherwise leave the line for AttributedString to handle
        //   (e.g. "See **this** example" — balanced inline bold is fine).
        let cleaned = removeDanglingEdgeMarkers(trimmed)
        return leadingWS + cleaned
    }

    /// Removes emphasis markers that are only at the start or end of the string
    /// without a matching close/open (i.e. "dangling" markers that would confuse
    /// the inline Markdown parser).
    private static func removeDanglingEdgeMarkers(_ s: String) -> String {
        var result = s

        // Count occurrences — if odd count, there is at least one unmatched marker.
        let doubleCount = result.components(separatedBy: "**").count - 1
        let singleCount = result.components(separatedBy: "*").count - 1 - (doubleCount * 2)

        // Unmatched "**": strip all occurrences from the string.
        if doubleCount % 2 != 0 {
            result = result.replacingOccurrences(of: "**", with: "")
        }
        // Unmatched "*": strip all remaining single-star occurrences.
        if singleCount % 2 != 0 {
            result = result.replacingOccurrences(of: "*", with: "")
        }

        // Same for "__" / "_"
        let dunderCount = result.components(separatedBy: "__").count - 1
        let underCount  = result.components(separatedBy: "_").count - 1 - (dunderCount * 2)
        if dunderCount % 2 != 0 {
            result = result.replacingOccurrences(of: "__", with: "")
        }
        if underCount % 2 != 0 {
            result = result.replacingOccurrences(of: "_", with: "")
        }

        return result
    }

    // MARK: - Core strip helpers

    /// Strips ALL leading emphasis tokens from the start of a string,
    /// including combinations like "* **", "** ", "* ", "__ ".
    private static func stripLeadingEmphasisTokens(_ s: String) -> String {
        var result = s[s.startIndex...]
        var progress = true
        while progress {
            progress = false
            // Skip whitespace
            let before = result
            result = result.drop(while: { $0 == " " || $0 == "\t" })
            // Try to consume an emphasis token
            for token in ["**", "__", "*", "_"] {
                if result.hasPrefix(token) {
                    result = result.dropFirst(token.count)
                    progress = true
                    break
                }
            }
            if result == before { break }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Removes ALL emphasis marker characters from a string, leaving plain text.
    /// Called only on lines that have been identified as headings.
    static func stripAllEmphasis(_ s: String) -> String {
        var r = s
        // Order matters: longest token first to avoid partial matches.
        for token in ["**", "__", "*", "_"] {
            r = r.replacingOccurrences(of: token, with: "")
        }
        return r.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Predicates

    /// True when the line contains any emphasis marker characters.
    private static func lineContainsEmphasisMarkers(_ line: String) -> Bool {
        line.contains("*") || line.contains("__")
    }

    /// True when the line is a genuine list item that must not be promoted to
    /// a heading, regardless of any emphasis markers it may contain.
    private static func isListItem(_ line: String) -> Bool {
        // Dash variants
        if line.hasPrefix("- ") || line.hasPrefix("– ") || line.hasPrefix("— ") { return true }
        // Plus
        if line.hasPrefix("+ ") { return true }
        // Unicode bullets
        if line.hasPrefix("• ") || line.hasPrefix("· ") || line.hasPrefix("◦ ") { return true }
        // Numbered list: "1. " / "2) " / "10. " etc.
        let digits = line.prefix(while: { $0.isNumber })
        if !digits.isEmpty {
            let after = line.dropFirst(digits.count)
            if after.hasPrefix(". ") || after.hasPrefix(") ") { return true }
        }
        // Indented content (2+ spaces at start = continuation / sub-list)
        if line.hasPrefix("  ") { return true }
        return false
    }

    /// A line is heading-shaped when it is short and has no mid-sentence
    /// punctuation that would make it clearly a sentence rather than a title.
    private static func looksLikeHeading(_ content: String) -> Bool {
        let t = content.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count < 100 else { return false }
        // Drop trailing period before checking for mid-sentence patterns.
        let body = t.hasSuffix(".") ? String(t.dropLast()) : t
        if body.contains(". ") || body.contains("? ") || body.contains("! ") { return false }
        return true
    }

    // MARK: - Blank collapse

    private static func collapseConsecutiveBlanks(_ blocks: [Block]) -> [Block] {
        var result: [Block] = []
        var lastWasBlank = false
        for block in blocks {
            if case .blank = block {
                if !lastWasBlank { result.append(block) }
                lastWasBlank = true
            } else {
                result.append(block)
                lastWasBlank = false
            }
        }
        return result
    }
}
