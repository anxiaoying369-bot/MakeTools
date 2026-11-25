import Foundation

private var totalAssertions = 0
private var failedAssertions = 0

private func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    totalAssertions += 1
    if !condition {
        failedAssertions += 1
        fputs("FAIL [\(file):\(line)] \(message)\n", stderr)
    }
}

private func checkContains(_ haystack: String, _ needle: String, _ message: String, file: String = #fileID, line: Int = #line) {
    check(haystack.contains(needle), "\(message) — expected to find: \(needle)\nActual:\n\(haystack)", file: file, line: line)
}

private func checkNotContains(_ haystack: String, _ needle: String, _ message: String, file: String = #fileID, line: Int = #line) {
    check(!haystack.contains(needle), "\(message) — did NOT expect to find: \(needle)\nActual:\n\(haystack)", file: file, line: line)
}

@main
struct MarkdownRendererTests {
    static func main() {
        testHeadings()
        testInlineFormattingAndCodeProtection()
        testLinksImagesAndXSSSanitization()
        testFencedCodeBlocksAndHighlighting()
        testTablesAndAlignment()
        testListsAndTasks()
        testBlockquotesAndCallouts()
        testFrontmatter()
        testFullDocumentWrapper()
        testInteractiveCopyControls()
        testASTAndPlainText()
        testSelectionAndCommandCCopySupport()

        print("MarkdownRendererTests: \(totalAssertions - failedAssertions)/\(totalAssertions) assertions passed.")
        if failedAssertions > 0 {
            exit(1)
        }
    }

    private static func testHeadings() {
        let md = """
        # Heading 1
        ## Heading 2 ##
        ### Heading 3
        ###### Heading 6
        """
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "<h1>Heading 1</h1>", "Should render H1")
        checkContains(html, "<h2>Heading 2</h2>", "Should render H2 and strip trailing #")
        checkContains(html, "<h3>Heading 3</h3>", "Should render H3")
        checkContains(html, "<h6>Heading 6</h6>", "Should render H6")
    }

    private static func testInlineFormattingAndCodeProtection() {
        let md = "Text **bold** *italic* ***both*** ~~gone~~ `**not_bold**` and snake_case_var"
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "<strong>bold</strong>", "Should render bold")
        checkContains(html, "<em>italic</em>", "Should render italic")
        checkContains(html, "<strong><em>both</em></strong>", "Should render bold+italic")
        checkContains(html, "<del>gone</del>", "Should render strikethrough")
        checkContains(html, "<code>**not_bold**</code>", "Should preserve markdown inside inline code")
        checkContains(html, "snake_case_var", "Should not italicize underscores inside identifiers")
        checkNotContains(html, "<em>case</em>", "Should not split snake_case_var into <em>")
    }

    private static func testLinksImagesAndXSSSanitization() {
        let md = """
        [Swift](https://swift.org)
        ![Logo](https://example.com/logo.png)
        [Bad](javascript:alert(1))
        <script>alert('xss')</script>
        <https://apple.com>
        """
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "<a href=\"https://swift.org\">Swift</a>", "Should render safe link")
        checkContains(html, "<img src=\"https://example.com/logo.png\" alt=\"Logo\">", "Should render safe image")
        checkNotContains(html, "javascript:", "Should strip javascript: links")
        checkNotContains(html, "<script>", "Should escape raw <script> tags")
        checkContains(html, "&lt;script&gt;", "Should HTML-escape <script>")
        checkContains(html, "<a href=\"https://apple.com\">https://apple.com</a>", "Should render autolink")
    }

    private static func testFencedCodeBlocksAndHighlighting() {
        let md = """
        ```swift
        // comment
        let count = 42
        let msg = "hello"
        ```
        """
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "<span class=\"code-lang\">swift</span>", "Should include language badge")
        checkContains(html, "<span class=\"tok-cmt\">// comment</span>", "Should highlight comments")
        checkContains(html, "<span class=\"tok-kw\">let</span>", "Should highlight keywords")
        checkContains(html, "<span class=\"tok-num\">42</span>", "Should highlight numbers")
        checkContains(html, "<span class=\"tok-str\">&quot;hello&quot;</span>", "Should highlight strings")
    }

    private static func testTablesAndAlignment() {
        let md = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        """
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "<th style=\"text-align: left;\">Left</th>", "Should align left")
        checkContains(html, "<th style=\"text-align: center;\">Center</th>", "Should align center")
        checkContains(html, "<th style=\"text-align: right;\">Right</th>", "Should align right")
        checkContains(html, "<td style=\"text-align: center;\">b</td>", "Should align body cells")
    }

    private static func testListsAndTasks() {
        let md = """
        - Item 1
          - Nested 1a
        - [x] Done task
        - [ ] Open task

        1. First
        2. Second
        """
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "<ul>", "Should render unordered list")
        checkContains(html, "<li>Nested 1a</li>", "Should render nested list item")
        checkContains(html, "<input type=\"checkbox\" disabled checked> Done task", "Should render checked task")
        checkContains(html, "<input type=\"checkbox\" disabled> Open task", "Should render unchecked task")
        checkContains(html, "<ol>", "Should render ordered list")
        checkContains(html, "<li>Second</li>", "Should render second ordered item")
    }

    private static func testBlockquotesAndCallouts() {
        let md = """
        > Normal quote

        > [!NOTE]
        > Important note here

        > [!WARNING]
        > Be careful
        """
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "<blockquote>", "Should render standard blockquote")
        checkContains(html, "callout-note", "Should render note callout")
        checkContains(html, "callout-warning", "Should render warning callout")
    }

    private static func testFrontmatter() {
        let md = """
        ---
        title: Test Doc
        author: Alice
        ---

        # Body
        """
        let html = MarkdownRenderer.renderBody(md)
        checkContains(html, "class=\"frontmatter\"", "Should render frontmatter card")
        checkContains(html, "Test Doc", "Should include frontmatter value")
        checkContains(html, "<h1>Body</h1>", "Should render heading after frontmatter")
    }

    private static func testFullDocumentWrapper() {
        let doc = MarkdownRenderer.renderDocument("# 中文标题", title: "测试.md")
        checkContains(doc, "<!DOCTYPE html>", "Should emit HTML5 doctype")
        checkContains(doc, "<meta charset=\"utf-8\">", "Should specify UTF-8 charset")
        checkContains(doc, "<title>测试.md</title>", "Should include document title")
        checkContains(doc, "@media (prefers-color-scheme: dark)", "Should embed dark mode CSS")
        checkContains(doc, "<h1>中文标题</h1>", "Should render Chinese heading")
    }

    private static func testInteractiveCopyControls() {
        let md = """
        ```swift
        let x = 1
        ```
        """
        let interactiveDoc = MarkdownRenderer.renderDocument(md, title: "Interactive", interactive: true)
        checkContains(
            interactiveDoc,
            "<button type=\"button\" class=\"copy-code-btn\" data-copy-code>复制</button>",
            "Interactive mode should render copy code button"
        )
        checkContains(
            interactiveDoc,
            "window.webkit.messageHandlers.clipboard",
            "Interactive mode should embed clipboard bridge script"
        )

        let staticDoc = MarkdownRenderer.renderDocument(md, title: "Static", interactive: false)
        checkNotContains(staticDoc, "data-copy-code", "Non-interactive mode should omit copy button")
        checkNotContains(staticDoc, "<script>", "Non-interactive mode should omit script tag")
    }

    private static func testASTAndPlainText() {
        let md = """
        # Title

        Hello **world** with `code` and [link](https://example.com).

        ```swift
        let a = 1
        ```
        """
        let blocks = MarkdownRenderer.parseBlocks(md)
        check(blocks.count == 3, "Expected 3 top-level AST blocks, got \(blocks.count)")

        let tokens = MarkdownRenderer.tokenizeCode("let a = 1", language: "swift")
        check(tokens.contains(where: { $0.kind == .keyword && $0.text == "let" }), "Should tokenize Swift keyword")
        check(tokens.contains(where: { $0.kind == .number && $0.text == "1" }), "Should tokenize number")

        let plain = MarkdownRenderer.renderPlainText(md)
        checkContains(plain, "Title", "Plain text should preserve heading text")
        checkContains(plain, "Hello world with code and link.", "Plain text should strip inline markdown markers")
        checkContains(plain, "let a = 1", "Plain text should preserve code block contents")
    }

    private static func testSelectionAndCommandCCopySupport() {
        checkContains(ThemeCSS.stylesheet, "user-select: text", "Stylesheet should explicitly allow text selection")
        checkContains(ThemeCSS.stylesheet, "-webkit-user-select: text", "Stylesheet should include webkit text selection")
        checkContains(ThemeCSS.stylesheet, ".code-header {\n", "Stylesheet should define .code-header")
        checkContains(ThemeCSS.stylesheet, "user-select: none", "Stylesheet should exclude code header controls from selection")

        let interactiveDoc = MarkdownRenderer.renderDocument("# Title\n\nSelectable text", title: "Selection", interactive: true)
        checkContains(interactiveDoc, "selectionchange", "Interactive mode should sync selection changes")
        checkContains(interactiveDoc, "keydown", "Interactive mode should handle Cmd+C / Cmd+A keydown")
        checkContains(interactiveDoc, "document.addEventListener('copy'", "Interactive mode should bridge copy events")
        checkContains(interactiveDoc, "__makeToolsSelectAll", "Interactive mode should expose select-all helper")

        let staticDoc = MarkdownRenderer.renderDocument("# Title\n\nSelectable text", title: "Static", interactive: false)
        checkNotContains(staticDoc, "<script>", "Non-interactive mode should omit script tag")
    }
}
