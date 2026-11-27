import Foundation

public enum MarkdownAlignment: String {
    case none = ""
    case left = "left"
    case center = "center"
    case right = "right"
}

public enum CalloutKind: String {
    case note
    case tip
    case important
    case warning
    case caution

    public var displayTitle: String {
        switch self {
        case .note: return L10n.text("markdown.alert.note", "Note")
        case .tip: return L10n.text("markdown.alert.tip", "Tip")
        case .important: return L10n.text("markdown.alert.important", "Important")
        case .warning: return L10n.text("markdown.alert.warning", "Warning")
        case .caution: return L10n.text("markdown.alert.caution", "Caution")
        }
    }

    public var cssClass: String {
        "callout-\(rawValue)"
    }
}

public enum CodeTokenKind {
    case plain
    case keyword
    case string
    case comment
    case number
    case type
}

public struct CodeToken {
    public let kind: CodeTokenKind
    public let text: String

    public init(kind: CodeTokenKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

public indirect enum InlineNode {
    case text(String)
    case code(String)
    case strong([InlineNode])
    case emphasis([InlineNode])
    case strongEmphasis([InlineNode])
    case strikethrough([InlineNode])
    case link(label: [InlineNode], url: String)
    case image(alt: String, url: String)
    case softBreak
    case hardBreak
}

public struct NativeListItem {
    public let indent: Int
    public let ordered: Bool
    public let number: Int
    public let taskState: Bool?
    public let inlines: [InlineNode]

    public init(indent: Int, ordered: Bool, number: Int, taskState: Bool?, inlines: [InlineNode]) {
        self.indent = indent
        self.ordered = ordered
        self.number = number
        self.taskState = taskState
        self.inlines = inlines
    }
}

public enum MarkdownBlock {
    case frontmatter([(String, String)])
    case heading(level: Int, inlines: [InlineNode])
    case paragraph([InlineNode])
    case codeBlock(language: String, code: String, tokens: [CodeToken])
    case blockquote(lines: [String])
    case callout(kind: CalloutKind, title: String, lines: [String])
    case table(headers: [[InlineNode]], alignments: [MarkdownAlignment], rows: [[[InlineNode]]])
    case list([NativeListItem])
    case horizontalRule
}

/// Pure-Swift offline Markdown parser and renderer (supports HTML, native AppKit AST, and plain text).
public enum MarkdownRenderer {
    private static let maxBlockRecursionDepth = 16

    // MARK: - Public API

    /// Renders a Markdown string into a complete, self-contained HTML5 document.
    public static func renderDocument(
        _ markdown: String,
        title: String = "Markdown Preview",
        interactive: Bool = true
    ) -> String {
        let body = renderBody(markdown, interactive: interactive)
        let safeTitle = escapeHTML(title)
        let previewClass = interactive ? "markdown-body is-interactive" : "markdown-body"
        let scriptBlock = interactive ? "\n\(interactiveScript)" : ""
        return """
        <!DOCTYPE html>
        <html lang="\(escapeHTML(L10n.locale.identifier.replacingOccurrences(of: "_", with: "-")))">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(safeTitle)</title>
            <style>
        \(ThemeCSS.stylesheet)
            </style>
        </head>
        <body>
            <article class="\(previewClass)">
        \(body)
            </article>\(scriptBlock)
        </body>
        </html>
        """
    }

    /// Renders a Markdown string into HTML fragment markup (without outer `<html>` wrapper).
    public static func renderBody(_ markdown: String, interactive: Bool = true) -> String {
        let blocks = parseBlocks(markdown)
        return renderBlocksHTML(blocks, depth: 0, interactive: interactive)
    }

    /// Parses a Markdown string into structured block AST nodes for native or HTML rendering.
    public static func parseBlocks(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []

        if let (pairs, consumed) = parseFrontmatterPairs(lines) {
            blocks.append(.frontmatter(pairs))
            lines.removeFirst(consumed)
        }

        blocks.append(contentsOf: parseBlockLines(lines, depth: 0))
        return blocks
    }

    /// Parses inline Markdown syntax into structured inline AST nodes.
    public static func parseInline(_ text: String) -> [InlineNode] {
        parseInlineNodes(text, depth: 0)
    }

    /// Tokenizes a code snippet for lightweight syntax highlighting.
    public static func tokenizeCode(_ code: String, language: String) -> [CodeToken] {
        let lowerLang = language.lowercased()
        let supported: Set<String> = [
            "swift", "python", "py", "js", "javascript", "ts", "typescript",
            "json", "bash", "sh", "zsh", "shell", "c", "cpp", "java", "go", "rust", "rs"
        ]
        guard supported.contains(lowerLang) else {
            return code.isEmpty ? [] : [CodeToken(kind: .plain, text: code)]
        }

        let keywords = keywordsForLanguage(lowerLang)
        let hashCommentLangs: Set<String> = ["python", "py", "bash", "sh", "zsh", "shell"]
        let slashCommentLangs: Set<String> = [
            "swift", "js", "javascript", "ts", "typescript", "c", "cpp", "java", "go", "rust", "rs"
        ]

        var tokens: [CodeToken] = []
        var plainBuffer = ""
        var i = code.startIndex

        func flushPlain() {
            if !plainBuffer.isEmpty {
                tokens.append(CodeToken(kind: .plain, text: plainBuffer))
                plainBuffer = ""
            }
        }

        while i < code.endIndex {
            let ch = code[i]

            if hashCommentLangs.contains(lowerLang) && ch == "#" {
                flushPlain()
                let end = code[i...].firstIndex(of: "\n") ?? code.endIndex
                tokens.append(CodeToken(kind: .comment, text: String(code[i..<end])))
                i = end
                continue
            }

            if slashCommentLangs.contains(lowerLang) && ch == "/" {
                let next = code.index(after: i)
                if next < code.endIndex && code[next] == "/" {
                    flushPlain()
                    let end = code[i...].firstIndex(of: "\n") ?? code.endIndex
                    tokens.append(CodeToken(kind: .comment, text: String(code[i..<end])))
                    i = end
                    continue
                }
                if next < code.endIndex && code[next] == "*" {
                    flushPlain()
                    let searchStart = code.index(after: next)
                    let end = code[searchStart...].range(of: "*/")?.upperBound ?? code.endIndex
                    tokens.append(CodeToken(kind: .comment, text: String(code[i..<end])))
                    i = end
                    continue
                }
            }

            if ch == "\"" || ch == "'" {
                flushPlain()
                let quote = ch
                var j = code.index(after: i)
                var escaped = false
                while j < code.endIndex {
                    let c = code[j]
                    j = code.index(after: j)
                    if escaped {
                        escaped = false
                    } else if c == "\\" {
                        escaped = true
                    } else if c == quote || c == "\n" {
                        break
                    }
                }
                tokens.append(CodeToken(kind: .string, text: String(code[i..<j])))
                i = j
                continue
            }

            if ch.isNumber {
                flushPlain()
                var j = code.index(after: i)
                while j < code.endIndex && (code[j].isNumber || code[j] == "." || code[j] == "_" || code[j] == "x" || code[j].isHexDigit) {
                    j = code.index(after: j)
                }
                tokens.append(CodeToken(kind: .number, text: String(code[i..<j])))
                i = j
                continue
            }

            if ch.isLetter || ch == "_" || ch == "@" {
                var j = code.index(after: i)
                while j < code.endIndex && (code[j].isLetter || code[j].isNumber || code[j] == "_") {
                    j = code.index(after: j)
                }
                let word = String(code[i..<j])
                if keywords.contains(word) {
                    flushPlain()
                    tokens.append(CodeToken(kind: .keyword, text: word))
                } else if let first = word.first, first.isUppercase, word.count > 1 {
                    flushPlain()
                    tokens.append(CodeToken(kind: .type, text: word))
                } else {
                    plainBuffer.append(contentsOf: word)
                }
                i = j
                continue
            }

            plainBuffer.append(ch)
            i = code.index(after: i)
        }

        flushPlain()
        return tokens
    }

    /// Extracts clean, readable plain text from Markdown (stripping markup syntax).
    public static func renderPlainText(_ markdown: String) -> String {
        let blocks = parseBlocks(markdown)
        return renderBlocksPlainText(blocks, depth: 0)
    }

    /// Escapes HTML special characters to prevent markup injection.
    public static func escapeHTML(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            case "'": result.append("&#39;")
            default: result.append(ch)
            }
        }
        return result
    }

    // MARK: - Block AST Parsing

    private static func parseFrontmatterPairs(_ lines: [String]) -> (pairs: [(String, String)], consumedLines: Int)? {
        guard lines.count >= 3, lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        var closingIndex: Int?
        for idx in 1..<min(lines.count, 60) {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                closingIndex = idx
                break
            }
        }

        guard let end = closingIndex, end > 1 else {
            return nil
        }

        var pairs: [(String, String)] = []
        for idx in 1..<end {
            let line = lines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    pairs.append((key, val))
                }
            } else {
                return nil
            }
        }

        guard !pairs.isEmpty else {
            return nil
        }

        return (pairs, end + 1)
    }

    private static func parseBlockLines(_ lines: [String], depth: Int) -> [MarkdownBlock] {
        guard depth < maxBlockRecursionDepth else {
            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? [] : [.paragraph([.text(joined)])]
        }

        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if let fence = parseFenceStart(line) {
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if isFenceEnd(lines[i], marker: fence.marker, minLength: fence.length) {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                let tokens = tokenizeCode(code, language: fence.language)
                blocks.append(.codeBlock(language: fence.language, code: code, tokens: tokens))
                continue
            }

            if let heading = parseATXHeading(line) {
                blocks.append(.heading(level: heading.level, inlines: parseInlineNodes(heading.text, depth: 0)))
                i += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            if isBlockquoteLine(line) {
                var quoteLines: [String] = []
                while i < lines.count && isBlockquoteLine(lines[i]) {
                    quoteLines.append(stripBlockquotePrefix(lines[i]))
                    i += 1
                }
                blocks.append(parseBlockquoteOrCallout(quoteLines))
                continue
            }

            if i + 1 < lines.count,
               line.contains("|"),
               let alignments = parseTableSeparator(lines[i + 1]) {
                let headerCells = splitTableRow(line)
                if headerCells.count == alignments.count {
                    var bodyRows: [[String]] = []
                    i += 2
                    while i < lines.count {
                        let rowLine = lines[i]
                        let rowTrimmed = rowLine.trimmingCharacters(in: .whitespaces)
                        if rowTrimmed.isEmpty || !rowLine.contains("|") || parseFenceStart(rowLine) != nil || parseATXHeading(rowLine) != nil {
                            break
                        }
                        bodyRows.append(splitTableRow(rowLine))
                        i += 1
                    }
                    let parsedHeaders = headerCells.map { parseInlineNodes($0, depth: 0) }
                    let parsedRows = bodyRows.map { row in
                        (0..<headerCells.count).map { idx in
                            parseInlineNodes(idx < row.count ? row[idx] : "", depth: 0)
                        }
                    }
                    blocks.append(.table(headers: parsedHeaders, alignments: alignments, rows: parsedRows))
                    continue
                }
            }

            if parseListItemStart(line) != nil {
                var listItems: [NativeListItem] = []
                while i < lines.count {
                    let current = lines[i]
                    if current.trimmingCharacters(in: .whitespaces).isEmpty {
                        if i + 1 < lines.count, parseListItemStart(lines[i + 1]) != nil {
                            i += 1
                            continue
                        }
                        break
                    }
                    if let parsed = parseListItemStart(current) {
                        listItems.append(parsed)
                        i += 1
                    } else if !listItems.isEmpty,
                              parseFenceStart(current) == nil,
                              parseATXHeading(current) == nil,
                              !isHorizontalRule(current.trimmingCharacters(in: .whitespaces)),
                              !isBlockquoteLine(current) {
                        let trimmedCont = current.trimmingCharacters(in: .whitespaces)
                        let last = listItems[listItems.count - 1]
                        let combined = last.inlines + [.text(" ")] + parseInlineNodes(trimmedCont, depth: 0)
                        listItems[listItems.count - 1] = NativeListItem(
                            indent: last.indent,
                            ordered: last.ordered,
                            number: last.number,
                            taskState: last.taskState,
                            inlines: combined
                        )
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.list(listItems))
                continue
            }

            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty ||
                    parseFenceStart(next) != nil ||
                    parseATXHeading(next) != nil ||
                    isHorizontalRule(nextTrimmed) ||
                    isBlockquoteLine(next) ||
                    parseListItemStart(next) != nil {
                    break
                }
                if i + 1 < lines.count,
                   next.contains("|"),
                   parseTableSeparator(lines[i + 1]) != nil {
                    break
                }
                paragraphLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(parseParagraphInlines(paragraphLines)))
        }

        return blocks
    }

    private static func parseParagraphInlines(_ lines: [String]) -> [InlineNode] {
        var nodes: [InlineNode] = []
        for (idx, line) in lines.enumerated() {
            let trimmedLeading = line.drop(while: { $0 == " " || $0 == "\t" })
            let hasHardBreak = line.hasSuffix("  ") || (line.hasSuffix("\\") && idx < lines.count - 1)
            let cleaned: String
            if idx < lines.count - 1 && line.hasSuffix("\\") {
                cleaned = String(trimmedLeading.dropLast())
            } else {
                cleaned = String(trimmedLeading).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            }
            nodes.append(contentsOf: parseInlineNodes(cleaned, depth: 0))
            if idx < lines.count - 1 {
                nodes.append(hasHardBreak ? .hardBreak : .softBreak)
            }
        }
        return nodes
    }

    private static func parseBlockquoteOrCallout(_ quoteLines: [String]) -> MarkdownBlock {
        if let first = quoteLines.first?.trimmingCharacters(in: .whitespaces) {
            let callouts: [(tag: String, kind: CalloutKind)] = [
                ("[!NOTE]", .note),
                ("[!TIP]", .tip),
                ("[!IMPORTANT]", .important),
                ("[!WARNING]", .warning),
                ("[!CAUTION]", .caution)
            ]
            for callout in callouts where first.uppercased().hasPrefix(callout.tag) {
                var inner = quoteLines
                let remainder = String(first.dropFirst(callout.tag.count)).trimmingCharacters(in: .whitespaces)
                if remainder.isEmpty {
                    inner.removeFirst()
                } else {
                    inner[0] = remainder
                }
                return .callout(kind: callout.kind, title: callout.kind.displayTitle, lines: inner)
            }
        }
        return .blockquote(lines: quoteLines)
    }

    // MARK: - HTML Rendering from AST

    private static func renderBlocksHTML(_ blocks: [MarkdownBlock], depth: Int, interactive: Bool) -> String {
        var htmlBlocks: [String] = []
        for block in blocks {
            switch block {
            case .frontmatter(let pairs):
                var rows = ""
                for (key, val) in pairs {
                    rows += "<div class=\"frontmatter-key\">\(escapeHTML(key))</div>"
                    rows += "<div>\(escapeHTML(val))</div>"
                }
                htmlBlocks.append("""
                <div class="frontmatter">
                    <div class="frontmatter-title">\(escapeHTML(L10n.text("markdown.metadata", "Metadata")))</div>
                    <div class="frontmatter-grid">\(rows)</div>
                </div>
                """)
            case .heading(let level, let inlines):
                htmlBlocks.append("<h\(level)>\(renderInlinesHTML(inlines))</h\(level)>")
            case .paragraph(let inlines):
                htmlBlocks.append("<p>\(renderInlinesHTML(inlines))</p>")
            case .codeBlock(let language, _, let tokens):
                htmlBlocks.append(renderCodeBlockHTML(tokens: tokens, language: language, interactive: interactive))
            case .blockquote(let lines):
                let innerBlocks = parseBlockLines(lines, depth: depth + 1)
                let innerHTML = renderBlocksHTML(innerBlocks, depth: depth + 1, interactive: interactive)
                htmlBlocks.append("<blockquote>\n\(innerHTML)\n</blockquote>")
            case .callout(let kind, let title, let lines):
                let innerBlocks = parseBlockLines(lines, depth: depth + 1)
                let body = renderBlocksHTML(innerBlocks, depth: depth + 1, interactive: interactive)
                htmlBlocks.append("""
                <div class="callout \(kind.cssClass)">
                    <div class="callout-title">\(escapeHTML(title))</div>
                    \(body)
                </div>
                """)
            case .table(let headers, let alignments, let rows):
                htmlBlocks.append(renderTableHTML(headers: headers, alignments: alignments, rows: rows))
            case .list(let items):
                htmlBlocks.append(renderListTreeHTML(items))
            case .horizontalRule:
                htmlBlocks.append("<hr>")
            }
        }
        return htmlBlocks
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func renderInlinesHTML(_ nodes: [InlineNode]) -> String {
        var out = ""
        for node in nodes {
            switch node {
            case .text(let s):
                out += escapeHTML(s)
            case .code(let s):
                out += "<code>\(escapeHTML(s))</code>"
            case .strong(let inner):
                out += "<strong>\(renderInlinesHTML(inner))</strong>"
            case .emphasis(let inner):
                out += "<em>\(renderInlinesHTML(inner))</em>"
            case .strongEmphasis(let inner):
                out += "<strong><em>\(renderInlinesHTML(inner))</em></strong>"
            case .strikethrough(let inner):
                out += "<del>\(renderInlinesHTML(inner))</del>"
            case .link(let label, let url):
                let labelHTML = renderInlinesHTML(label)
                let safeURL = sanitizeURL(url)
                if safeURL.isEmpty {
                    out += labelHTML
                } else {
                    out += "<a href=\"\(escapeHTML(safeURL))\">\(labelHTML)</a>"
                }
            case .image(let alt, let url):
                let safeURL = sanitizeURL(url)
                if safeURL.isEmpty {
                    out += escapeHTML(alt)
                } else {
                    out += "<img src=\"\(escapeHTML(safeURL))\" alt=\"\(escapeHTML(alt))\">"
                }
            case .softBreak:
                out += " "
            case .hardBreak:
                out += "<br>\n"
            }
        }
        return out
    }

    private static func renderCodeBlockHTML(tokens: [CodeToken], language: String, interactive: Bool) -> String {
        var highlighted = ""
        for token in tokens {
            let escaped = escapeHTML(token.text)
            switch token.kind {
            case .plain: highlighted += escaped
            case .keyword: highlighted += "<span class=\"tok-kw\">\(escaped)</span>"
            case .string: highlighted += "<span class=\"tok-str\">\(escaped)</span>"
            case .comment: highlighted += "<span class=\"tok-cmt\">\(escaped)</span>"
            case .number: highlighted += "<span class=\"tok-num\">\(escaped)</span>"
            case .type: highlighted += "<span class=\"tok-type\">\(escaped)</span>"
            }
        }

        let headerHTML: String
        if interactive {
            let langLabel = language.isEmpty ? "code" : escapeHTML(language)
            headerHTML = "<div class=\"code-header\"><span class=\"code-lang\">\(langLabel)</span><button type=\"button\" class=\"copy-code-btn\" data-copy-code>\(escapeHTML(L10n.text("island.copy", "复制")))</button></div>"
        } else {
            headerHTML = language.isEmpty ? "" : "<span class=\"code-lang\">\(escapeHTML(language))</span>"
        }
        return "<div class=\"code-block\">\(headerHTML)<pre><code>\(highlighted)</code></pre></div>"
    }

    private static func renderTableHTML(headers: [[InlineNode]], alignments: [MarkdownAlignment], rows: [[[InlineNode]]]) -> String {
        func styleAttr(_ align: MarkdownAlignment) -> String {
            align == .none ? "" : " style=\"text-align: \(align.rawValue);\""
        }

        var html = "<table>\n<thead>\n<tr>\n"
        for (idx, header) in headers.enumerated() {
            let align = idx < alignments.count ? alignments[idx] : .none
            html += "<th\(styleAttr(align))>\(renderInlinesHTML(header))</th>\n"
        }
        html += "</tr>\n</thead>\n"

        if !rows.isEmpty {
            html += "<tbody>\n"
            for row in rows {
                html += "<tr>\n"
                for idx in 0..<headers.count {
                    let cell = idx < row.count ? row[idx] : []
                    let align = idx < alignments.count ? alignments[idx] : .none
                    html += "<td\(styleAttr(align))>\(renderInlinesHTML(cell))</td>\n"
                }
                html += "</tr>\n"
            }
            html += "</tbody>\n"
        }

        html += "</table>"
        return html
    }

    private static func renderListTreeHTML(_ items: [NativeListItem]) -> String {
        var index = 0

        func buildList(minIndent: Int) -> String {
            guard index < items.count else { return "" }
            let first = items[index]
            let isOrdered = first.ordered
            let tag = isOrdered ? "ol" : "ul"
            let startAttr = (isOrdered && first.number != 1) ? " start=\"\(first.number)\"" : ""
            var html = "<\(tag)\(startAttr)>\n"

            while index < items.count {
                let item = items[index]
                if item.indent < minIndent || item.indent > minIndent || item.ordered != isOrdered {
                    break
                }

                index += 1
                let inlineText = renderInlinesHTML(item.inlines)
                var liBody: String
                var liAttr = ""
                if let checked = item.taskState {
                    liAttr = " class=\"task-list-item\""
                    let checkedAttr = checked ? " checked" : ""
                    liBody = "<input type=\"checkbox\" disabled\(checkedAttr)> \(inlineText)"
                } else {
                    liBody = inlineText
                }

                if index < items.count && items[index].indent > item.indent {
                    liBody += "\n" + buildList(minIndent: items[index].indent)
                }

                html += "<li\(liAttr)>\(liBody)</li>\n"
            }

            html += "</\(tag)>"
            return html
        }

        var blocks: [String] = []
        while index < items.count {
            blocks.append(buildList(minIndent: items[index].indent))
        }
        return blocks.joined(separator: "\n")
    }

    // MARK: - Plain Text Extraction

    private static func renderBlocksPlainText(_ blocks: [MarkdownBlock], depth: Int) -> String {
        guard depth < maxBlockRecursionDepth else { return "" }
        var sections: [String] = []

        for block in blocks {
            switch block {
            case .frontmatter(let pairs):
                let lines = pairs.map { "\($0.0): \($0.1)" }
                if !lines.isEmpty {
                    sections.append(lines.joined(separator: "\n"))
                }
            case .heading(_, let inlines), .paragraph(let inlines):
                sections.append(renderInlinesPlainText(inlines))
            case .codeBlock(_, let code, _):
                sections.append(code)
            case .blockquote(let lines):
                let inner = renderBlocksPlainText(parseBlockLines(lines, depth: depth + 1), depth: depth + 1)
                if !inner.isEmpty {
                    sections.append(inner)
                }
            case .callout(_, let title, let lines):
                let inner = renderBlocksPlainText(parseBlockLines(lines, depth: depth + 1), depth: depth + 1)
                sections.append(inner.isEmpty ? title : "\(title)\n\(inner)")
            case .table(let headers, _, let rows):
                var tableLines: [String] = []
                tableLines.append(headers.map { renderInlinesPlainText($0) }.joined(separator: "\t"))
                for row in rows {
                    tableLines.append(row.map { renderInlinesPlainText($0) }.joined(separator: "\t"))
                }
                sections.append(tableLines.joined(separator: "\n"))
            case .list(let items):
                let itemLines = items.map { item -> String in
                    let prefix: String
                    if let checked = item.taskState {
                        prefix = checked ? "[x] " : "[ ] "
                    } else if item.ordered {
                        prefix = "\(item.number). "
                    } else {
                        prefix = "• "
                    }
                    let indentStr = String(repeating: "  ", count: max(0, item.indent / 2))
                    return "\(indentStr)\(prefix)\(renderInlinesPlainText(item.inlines))"
                }
                sections.append(itemLines.joined(separator: "\n"))
            case .horizontalRule:
                sections.append("---")
            }
        }

        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public static func renderInlinesPlainText(_ nodes: [InlineNode]) -> String {
        var out = ""
        for node in nodes {
            switch node {
            case .text(let s), .code(let s):
                out += s
            case .strong(let inner), .emphasis(let inner), .strongEmphasis(let inner), .strikethrough(let inner):
                out += renderInlinesPlainText(inner)
            case .link(let label, _):
                out += renderInlinesPlainText(label)
            case .image(let alt, _):
                out += alt
            case .softBreak:
                out += " "
            case .hardBreak:
                out += "\n"
            }
        }
        return out
    }

    private static var interactiveScript: String { """
        <script>
        (function () {
            function getSelectedText() {
                var sel = window.getSelection ? window.getSelection() : null;
                return sel ? (sel.toString() || '') : '';
            }

            function postBridge(payload) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.clipboard) {
                    window.webkit.messageHandlers.clipboard.postMessage(payload);
                    return true;
                }
                return false;
            }

            function postCopy(text) {
                if (!text) return;
                if (!postBridge({ type: 'copy', text: text })) {
                    if (navigator.clipboard && navigator.clipboard.writeText) {
                        navigator.clipboard.writeText(text).catch(function () {});
                    }
                }
            }

            var selectionTimer = null;
            function syncSelection(immediate) {
                var emit = function () {
                    selectionTimer = null;
                    postBridge({ type: 'selection', text: getSelectedText() });
                };
                if (immediate) {
                    if (selectionTimer) {
                        clearTimeout(selectionTimer);
                        selectionTimer = null;
                    }
                    emit();
                    return;
                }
                if (selectionTimer) {
                    clearTimeout(selectionTimer);
                }
                selectionTimer = setTimeout(emit, 25);
            }

            window.__makeToolsSelectAll = function () {
                var target = document.querySelector('.markdown-body') || document.body;
                if (!target || !window.getSelection) return '';
                var range = document.createRange();
                range.selectNodeContents(target);
                var sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
                syncSelection(true);
                return sel.toString() || '';
            };

            document.addEventListener('click', function (event) {
                var btn = event.target.closest('[data-copy-code]');
                if (!btn) return;
                var block = btn.closest('.code-block');
                if (!block) return;
                var codeEl = block.querySelector('pre code');
                if (!codeEl) return;
                var text = codeEl.textContent || '';
                postCopy(text);
                if (btn._copyTimer) {
                    clearTimeout(btn._copyTimer);
                }
                btn.textContent = \(L10n.scriptString(L10n.text("common.copied", "已复制 ✓")));
                btn.classList.add('copied');
                btn._copyTimer = setTimeout(function () {
                    btn.textContent = \(L10n.scriptString(L10n.text("island.copy", "复制")));
                    btn.classList.remove('copied');
                    btn._copyTimer = null;
                }, 1500);
            });

            document.addEventListener('selectionchange', function () {
                syncSelection(false);
            });

            document.addEventListener('mouseup', function () {
                syncSelection(true);
            });

            document.addEventListener('keyup', function () {
                syncSelection(true);
            });

            document.addEventListener('keydown', function (event) {
                if (!event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
                var key = (event.key || '').toLowerCase();
                if (key === 'c' || event.code === 'KeyC') {
                    var text = getSelectedText();
                    if (text.length > 0) {
                        event.preventDefault();
                        postCopy(text);
                    }
                } else if (key === 'a' || event.code === 'KeyA') {
                    event.preventDefault();
                    window.__makeToolsSelectAll();
                }
            }, true);

            document.addEventListener('copy', function () {
                var text = getSelectedText();
                if (text.length > 0) {
                    postCopy(text);
                }
            });
        })();
        </script>
    """ }

    // MARK: - Block Line Helpers

    private static func parseFenceStart(_ line: String) -> (marker: Character, length: Int, language: String)? {
        let stripped = dropLeadingSpaces(line, maxSpaces: 3)
        guard let first = stripped.first, first == "`" || first == "~" else {
            return nil
        }
        var count = 0
        var idx = stripped.startIndex
        while idx < stripped.endIndex && stripped[idx] == first {
            count += 1
            idx = stripped.index(after: idx)
        }
        guard count >= 3 else {
            return nil
        }
        let rest = String(stripped[idx...]).trimmingCharacters(in: .whitespaces)
        if first == "`" && rest.contains("`") {
            return nil
        }
        let language = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        return (first, count, language)
    }

    private static func isFenceEnd(_ line: String, marker: Character, minLength: Int) -> Bool {
        let stripped = dropLeadingSpaces(line, maxSpaces: 3)
        var count = 0
        var idx = stripped.startIndex
        while idx < stripped.endIndex && stripped[idx] == marker {
            count += 1
            idx = stripped.index(after: idx)
        }
        guard count >= minLength else {
            return false
        }
        return stripped[idx...].trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func parseATXHeading(_ line: String) -> (level: Int, text: String)? {
        let stripped = dropLeadingSpaces(line, maxSpaces: 3)
        var level = 0
        var idx = stripped.startIndex
        while idx < stripped.endIndex && stripped[idx] == "#" {
            level += 1
            idx = stripped.index(after: idx)
        }
        guard (1...6).contains(level) else {
            return nil
        }
        if idx < stripped.endIndex && stripped[idx] != " " && stripped[idx] != "\t" {
            return nil
        }
        var content = String(stripped[idx...]).trimmingCharacters(in: .whitespaces)
        var hashStart = content.endIndex
        while hashStart > content.startIndex {
            let prev = content.index(before: hashStart)
            if content[prev] == "#" {
                hashStart = prev
            } else {
                break
            }
        }
        if hashStart < content.endIndex {
            if hashStart == content.startIndex ||
                content[content.index(before: hashStart)] == " " ||
                content[content.index(before: hashStart)] == "\t" {
                content = String(content[..<hashStart]).trimmingCharacters(in: .whitespaces)
            }
        }
        return (level, content)
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let compact = trimmed.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let first = compact.first else {
            return false
        }
        guard first == "-" || first == "*" || first == "_" else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func isBlockquoteLine(_ line: String) -> Bool {
        let stripped = dropLeadingSpaces(line, maxSpaces: 3)
        return stripped.first == ">"
    }

    private static func stripBlockquotePrefix(_ line: String) -> String {
        let stripped = dropLeadingSpaces(line, maxSpaces: 3)
        guard stripped.first == ">" else {
            return line
        }
        let after = stripped.dropFirst()
        if after.first == " " {
            return String(after.dropFirst())
        }
        return String(after)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") {
            trimmed.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in trimmed {
            if escaped {
                current.append(ch == "|" ? "|" : "\\\(ch)")
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if escaped {
            current.append("\\")
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func parseTableSeparator(_ line: String) -> [MarkdownAlignment]? {
        guard line.contains("|") else {
            return nil
        }
        let cells = splitTableRow(line)
        guard !cells.isEmpty else {
            return nil
        }
        var alignments: [MarkdownAlignment] = []
        for cell in cells {
            guard !cell.isEmpty else {
                return nil
            }
            let startsColon = cell.hasPrefix(":")
            let endsColon = cell.hasSuffix(":")
            var core = cell
            if startsColon { core.removeFirst() }
            if endsColon && !core.isEmpty { core.removeLast() }
            guard core.count >= 1, core.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            if startsColon && endsColon {
                alignments.append(.center)
            } else if startsColon {
                alignments.append(.left)
            } else if endsColon {
                alignments.append(.right)
            } else {
                alignments.append(.none)
            }
        }
        return alignments
    }

    private static func parseListItemStart(_ line: String) -> NativeListItem? {
        var indent = 0
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == " " {
                indent += 1
            } else if ch == "\t" {
                indent += 4
            } else {
                break
            }
            idx = line.index(after: idx)
        }

        let rest = line[idx...]
        guard let first = rest.first else {
            return nil
        }

        var ordered = false
        var startNum = 1
        var afterMarker: Substring

        if first == "-" || first == "*" || first == "+" {
            let nextIdx = rest.index(after: rest.startIndex)
            guard nextIdx < rest.endIndex, rest[nextIdx] == " " || rest[nextIdx] == "\t" else {
                return nil
            }
            afterMarker = rest[rest.index(after: nextIdx)...]
        } else if first.isNumber {
            var numEnd = rest.startIndex
            while numEnd < rest.endIndex && rest[numEnd].isNumber {
                numEnd = rest.index(after: numEnd)
            }
            guard numEnd < rest.endIndex, rest[numEnd] == "." || rest[numEnd] == ")" else {
                return nil
            }
            let afterDelim = rest.index(after: numEnd)
            guard afterDelim < rest.endIndex, rest[afterDelim] == " " || rest[afterDelim] == "\t" else {
                return nil
            }
            ordered = true
            startNum = Int(rest[..<numEnd]) ?? 1
            afterMarker = rest[rest.index(after: afterDelim)...]
        } else {
            return nil
        }

        var content = String(afterMarker).trimmingCharacters(in: .whitespaces)
        var taskState: Bool?
        if content.hasPrefix("[ ] ") || content == "[ ]" {
            taskState = false
            content = String(content.dropFirst(content.count >= 4 ? 4 : 3)).trimmingCharacters(in: .whitespaces)
        } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") || content == "[x]" || content == "[X]" {
            taskState = true
            content = String(content.dropFirst(content.count >= 4 ? 4 : 3)).trimmingCharacters(in: .whitespaces)
        }

        return NativeListItem(
            indent: indent,
            ordered: ordered,
            number: startNum,
            taskState: taskState,
            inlines: parseInlineNodes(content, depth: 0)
        )
    }

    private static func keywordsForLanguage(_ language: String) -> Set<String> {
        switch language {
        case "swift":
            return ["import", "struct", "class", "enum", "protocol", "extension", "func", "let", "var",
                    "if", "else", "guard", "switch", "case", "default", "for", "while", "in", "return",
                    "throw", "throws", "try", "catch", "async", "await", "public", "private", "internal",
                    "final", "static", "true", "false", "nil", "self", "Self", "override", "@objc", "@MainActor"]
        case "python", "py":
            return ["import", "from", "as", "def", "class", "if", "elif", "else", "for", "while",
                    "in", "return", "yield", "try", "except", "finally", "with", "async", "await",
                    "True", "False", "None", "and", "or", "not", "pass", "break", "continue", "lambda"]
        case "js", "javascript", "ts", "typescript":
            return ["import", "export", "from", "default", "const", "let", "var", "function", "class",
                    "interface", "type", "if", "else", "for", "while", "switch", "case", "return",
                    "try", "catch", "finally", "async", "await", "new", "true", "false", "null", "undefined"]
        case "bash", "sh", "zsh", "shell":
            return ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while",
                    "case", "esac", "function", "export", "local", "return", "exit", "echo", "set"]
        case "json":
            return ["true", "false", "null"]
        default:
            return ["if", "else", "for", "while", "switch", "case", "return", "struct", "enum",
                    "func", "fn", "pub", "package", "import", "const", "var", "let", "true", "false", "nil", "null"]
        }
    }

    // MARK: - Inline AST Parsing

    private static func parseInlineNodes(_ text: String, depth: Int) -> [InlineNode] {
        guard depth < 8 else {
            return text.isEmpty ? [] : [.text(text)]
        }

        var nodes: [InlineNode] = []
        var plainBuffer = ""
        var i = text.startIndex

        func flushPlain() {
            if !plainBuffer.isEmpty {
                nodes.append(.text(plainBuffer))
                plainBuffer = ""
            }
        }

        while i < text.endIndex {
            let ch = text[i]

            if ch == "\\" {
                let next = text.index(after: i)
                if next < text.endIndex && isASCIIPunctuation(text[next]) {
                    plainBuffer.append(text[next])
                    i = text.index(after: next)
                    continue
                }
            }

            if ch == "`" {
                var tickCount = 0
                var scan = i
                while scan < text.endIndex && text[scan] == "`" {
                    tickCount += 1
                    scan = text.index(after: scan)
                }
                if let closeRange = findClosingBackticks(in: text, from: scan, count: tickCount) {
                    flushPlain()
                    var codeContent = String(text[scan..<closeRange.lowerBound])
                    if codeContent.count >= 2 && codeContent.hasPrefix(" ") && codeContent.hasSuffix(" ") && !codeContent.allSatisfy({ $0 == " " }) {
                        codeContent = String(codeContent.dropFirst().dropLast())
                    }
                    nodes.append(.code(codeContent))
                    i = closeRange.upperBound
                    continue
                } else {
                    plainBuffer.append(contentsOf: String(repeating: "`", count: tickCount))
                    i = scan
                    continue
                }
            }

            if ch == "<", let (url, endIdx) = parseAutolink(in: text, from: i) {
                flushPlain()
                let safeURL = sanitizeURL(url)
                if !safeURL.isEmpty {
                    nodes.append(.link(label: [.text(url)], url: safeURL))
                } else {
                    plainBuffer.append(contentsOf: text[i..<endIdx])
                }
                i = endIdx
                continue
            }

            if ch == "!",
               text.index(after: i) < text.endIndex,
               text[text.index(after: i)] == "[",
               let parsed = parseLink(in: text, fromBracket: text.index(after: i)) {
                flushPlain()
                let safeURL = sanitizeURL(parsed.url)
                if !safeURL.isEmpty {
                    nodes.append(.image(alt: parsed.label, url: safeURL))
                } else {
                    plainBuffer.append(contentsOf: parsed.label)
                }
                i = parsed.endIndex
                continue
            }

            if ch == "[", let parsed = parseLink(in: text, fromBracket: i) {
                flushPlain()
                let safeURL = sanitizeURL(parsed.url)
                let labelNodes = parseInlineNodes(parsed.label, depth: depth + 1)
                if !safeURL.isEmpty {
                    nodes.append(.link(label: labelNodes, url: safeURL))
                } else {
                    nodes.append(contentsOf: labelNodes)
                }
                i = parsed.endIndex
                continue
            }

            if (ch == "*" || ch == "_"),
               let (delim, content, endIdx) = parseEmphasis(in: text, from: i) {
                flushPlain()
                let inner = parseInlineNodes(content, depth: depth + 1)
                switch delim {
                case "***", "___":
                    nodes.append(.strongEmphasis(inner))
                case "**", "__":
                    nodes.append(.strong(inner))
                default:
                    nodes.append(.emphasis(inner))
                }
                i = endIdx
                continue
            }

            if ch == "~",
               text.index(after: i) < text.endIndex,
               text[text.index(after: i)] == "~",
               let close = text[text.index(i, offsetBy: 2)...].range(of: "~~") {
                let content = String(text[text.index(i, offsetBy: 2)..<close.lowerBound])
                if !content.isEmpty {
                    flushPlain()
                    nodes.append(.strikethrough(parseInlineNodes(content, depth: depth + 1)))
                    i = close.upperBound
                    continue
                }
            }

            plainBuffer.append(ch)
            i = text.index(after: i)
        }

        flushPlain()
        return nodes
    }

    private static func findClosingBackticks(in text: String, from start: String.Index, count: Int) -> Range<String.Index>? {
        var idx = start
        while idx < text.endIndex {
            if text[idx] == "`" {
                var run = 0
                var end = idx
                while end < text.endIndex && text[end] == "`" {
                    run += 1
                    end = text.index(after: end)
                }
                if run == count {
                    return idx..<end
                }
                idx = end
            } else {
                idx = text.index(after: idx)
            }
        }
        return nil
    }

    private static func parseAutolink(in text: String, from start: String.Index) -> (url: String, endIndex: String.Index)? {
        let afterOpen = text.index(after: start)
        guard let close = text[afterOpen...].firstIndex(of: ">") else {
            return nil
        }
        let candidate = String(text[afterOpen..<close])
        guard (candidate.hasPrefix("https://") || candidate.hasPrefix("http://")),
              !candidate.contains(where: { $0.isWhitespace }) else {
            return nil
        }
        return (candidate, text.index(after: close))
    }

    private static func parseLink(in text: String, fromBracket openBracket: String.Index) -> (label: String, url: String, endIndex: String.Index)? {
        var idx = text.index(after: openBracket)
        var bracketDepth = 1
        var labelEnd: String.Index?

        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "\\" {
                let next = text.index(after: idx)
                idx = next < text.endIndex ? text.index(after: next) : next
                continue
            }
            if ch == "[" {
                bracketDepth += 1
            } else if ch == "]" {
                bracketDepth -= 1
                if bracketDepth == 0 {
                    labelEnd = idx
                    break
                }
            }
            idx = text.index(after: idx)
        }

        guard let closeBracket = labelEnd else {
            return nil
        }
        let afterBracket = text.index(after: closeBracket)
        guard afterBracket < text.endIndex && text[afterBracket] == "(" else {
            return nil
        }

        var urlIdx = text.index(after: afterBracket)
        var parenDepth = 1
        var urlEnd: String.Index?

        while urlIdx < text.endIndex {
            let ch = text[urlIdx]
            if ch == "\\" {
                let next = text.index(after: urlIdx)
                urlIdx = next < text.endIndex ? text.index(after: next) : next
                continue
            }
            if ch == "(" {
                parenDepth += 1
            } else if ch == ")" {
                parenDepth -= 1
                if parenDepth == 0 {
                    urlEnd = urlIdx
                    break
                }
            }
            urlIdx = text.index(after: urlIdx)
        }

        guard let closeParen = urlEnd else {
            return nil
        }

        let label = String(text[text.index(after: openBracket)..<closeBracket])
        var rawURL = String(text[text.index(after: afterBracket)..<closeParen]).trimmingCharacters(in: .whitespaces)
        if rawURL.hasPrefix("<") && rawURL.hasSuffix(">") && rawURL.count >= 2 {
            rawURL = String(rawURL.dropFirst().dropLast())
        } else if let spaceIdx = rawURL.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            rawURL = String(rawURL[..<spaceIdx])
        }

        return (label, rawURL, text.index(after: closeParen))
    }

    private static func parseEmphasis(in text: String, from start: String.Index) -> (delim: String, content: String, endIndex: String.Index)? {
        let marker = text[start]
        var count = 0
        var idx = start
        while idx < text.endIndex && text[idx] == marker && count < 3 {
            count += 1
            idx = text.index(after: idx)
        }

        if marker == "_" && start > text.startIndex {
            let prev = text[text.index(before: start)]
            if prev.isLetter || prev.isNumber {
                return nil
            }
        }

        guard idx < text.endIndex && !text[idx].isWhitespace else {
            return nil
        }

        let delim = String(repeating: marker, count: count)
        var search = idx
        while search < text.endIndex {
            if let range = text[search...].range(of: delim) {
                let beforeClose = text[text.index(before: range.lowerBound)]
                if !beforeClose.isWhitespace {
                    if marker == "_" && range.upperBound < text.endIndex {
                        let afterClose = text[range.upperBound]
                        if afterClose.isLetter || afterClose.isNumber {
                            search = range.upperBound
                            continue
                        }
                    }
                    let content = String(text[idx..<range.lowerBound])
                    if !content.isEmpty {
                        return (delim, content, range.upperBound)
                    }
                }
                search = range.upperBound
            } else {
                break
            }
        }

        return nil
    }

    private static func sanitizeURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("javascript:") || lower.hasPrefix("vbscript:") || lower.hasPrefix("data:text/html") {
            return ""
        }
        return trimmed
    }

    private static func isASCIIPunctuation(_ ch: Character) -> Bool {
        let punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
        return punctuation.contains(ch)
    }

    private static func dropLeadingSpaces(_ line: String, maxSpaces: Int) -> Substring {
        var count = 0
        var idx = line.startIndex
        while idx < line.endIndex && count < maxSpaces && line[idx] == " " {
            count += 1
            idx = line.index(after: idx)
        }
        return line[idx...]
    }
}
