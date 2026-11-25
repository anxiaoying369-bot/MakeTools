import AppKit
import Foundation

private func selectedPlainText(from textView: NSTextView) -> String {
    let ns = textView.string as NSString
    let parts: [String] = textView.selectedRanges.compactMap { value in
        let range = value.rangeValue
        guard range.length > 0, NSMaxRange(range) <= ns.length else {
            return nil
        }
        return ns.substring(with: range)
    }
    return parts.joined(separator: "\n")
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class DynamicColorView: NSView {
    private let fillColor: NSColor

    init(fillColor: NSColor) {
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
        }
    }
}

private final class CardContainerView: NSView {
    private let fillColor: NSColor
    private let borderColor: NSColor
    private let cornerRadius: CGFloat

    init(fillColor: NSColor, borderColor: NSColor = .separatorColor, cornerRadius: CGFloat = 12) {
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
        layer?.borderWidth = 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.cgColor
            layer?.borderColor = borderColor.cgColor
        }
    }
}

private final class CodeBlockScrollView: NSScrollView {
    private let minimumContentWidth: CGFloat
    private let fixedContentHeight: CGFloat

    init(minimumContentWidth: CGFloat, fixedContentHeight: CGFloat) {
        self.minimumContentWidth = minimumContentWidth
        self.fixedContentHeight = fixedContentHeight
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let width = max(contentSize.width, minimumContentWidth)
        let targetFrame = NSRect(x: 0, y: 0, width: width, height: fixedContentHeight)
        if let docView = documentView, docView.frame != targetFrame {
            docView.frame = targetFrame
        }
    }
}

private class SelectableTextView: NSTextView {
    var onNonEmptySelection: ((NSTextView) -> Void)?

    override func copy(_ sender: Any?) {
        let text = selectedPlainText(from: self)
        if !text.isEmpty {
            ClipboardHelper.copyText(text)
            return
        }
        super.copy(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        if flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                let text = selectedPlainText(from: self)
                if !text.isEmpty {
                    ClipboardHelper.copyText(text)
                    return true
                }
                return false
            case "a":
                selectAll(nil)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        if ranges.contains(where: { $0.rangeValue.length > 0 }) {
            onNonEmptySelection?(self)
        }
    }
}

private final class AutoSizingTextView: SelectableTextView, NSTextViewDelegate {
    var onLinkClicked: ((URL) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isEditable = false
        isSelectable = true
        drawsBackground = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.heightTracksTextView = false
        delegate = self
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(bounds.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            invalidateIntrinsicContentSize()
        }
    }

    override func layout() {
        super.layout()
        if bounds.width > 0,
           let tc = textContainer,
           abs(tc.containerSize.width - bounds.width) > 0.5 {
            tc.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return super.intrinsicContentSize
        }
        if bounds.width > 0 {
            textContainer.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(18, ceil(rect.height) + 4))
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL {
            onLinkClicked?(url)
            return true
        }
        if let str = link as? String, let url = URL(string: str) {
            onLinkClicked?(url)
            return true
        }
        return false
    }
}

private final class CodeCopyButton: NSButton {
    let rawCode: String

    init(code: String, target: AnyObject?, action: Selector?) {
        self.rawCode = code
        super.init(frame: .zero)
        self.title = "复制"
        self.controlSize = .small
        ToolAppearance.configureCopy(self, symbol: "doc.on.doc")
        self.target = target
        self.action = action
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Pure-AppKit Markdown renderer view — zero WebKit/WebContent processes, 100% Quick Look sandbox safe.
public final class NativeMarkdownView: NSView, NSUserInterfaceValidations {
    public var onOpenLink: ((URL) -> Void)?

    private let scrollView = NSScrollView()
    private let documentContainer = FlippedView()
    private let stackView = NSStackView()
    private var selectableTextViews: [NSTextView] = []

    // MARK: - Dynamic Theme Palette

    private static let cardBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.09, green: 0.12, blue: 0.17, alpha: 1.0)
            : NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1.0)
    }

    private static let inlineCodeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.12)
            : NSColor(white: 0.0, alpha: 0.07)
    }

    private static let tableStripeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1.0, alpha: 0.03)
            : NSColor(white: 0.0, alpha: 0.025)
    }

    private static let keywordColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.48, blue: 0.45, alpha: 1.0)
            : NSColor(srgbRed: 0.81, green: 0.13, blue: 0.18, alpha: 1.0)
    }

    private static let stringColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.65, green: 0.84, blue: 1.0, alpha: 1.0)
            : NSColor(srgbRed: 0.04, green: 0.19, blue: 0.41, alpha: 1.0)
    }

    private static let commentColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 1.0)
            : NSColor(srgbRed: 0.43, green: 0.47, blue: 0.51, alpha: 1.0)
    }

    private static let numberColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.47, green: 0.75, blue: 1.0, alpha: 1.0)
            : NSColor(srgbRed: 0.02, green: 0.31, blue: 0.68, alpha: 1.0)
    }

    private static let typeColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.65, blue: 0.34, alpha: 1.0)
            : NSColor(srgbRed: 0.58, green: 0.22, blue: 0.0, alpha: 1.0)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayout() {
        wantsLayer = true

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        documentContainer.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 18
        stackView.edgeInsets = NSEdgeInsets(top: 34, left: 34, bottom: 42, right: 34)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentContainer.addSubview(stackView)
        scrollView.documentView = documentContainer
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            documentContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentContainer.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: documentContainer.topAnchor),
            stackView.centerXAnchor.constraint(equalTo: documentContainer.centerXAnchor),
            stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 850),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: documentContainer.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: documentContainer.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentContainer.bottomAnchor)
        ])

        let fullWidth = stackView.widthAnchor.constraint(equalTo: documentContainer.widthAnchor)
        fullWidth.priority = .defaultHigh
        fullWidth.isActive = true
    }

    public func render(markdown: String) {
        selectableTextViews.removeAll()
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let blocks = MarkdownRenderer.parseBlocks(markdown)
        var proseBuffer: [MarkdownBlock] = []

        func flushProse() {
            guard !proseBuffer.isEmpty else { return }
            let textView = makeProseTextView(for: proseBuffer)
            addFullWidthView(textView)
            proseBuffer.removeAll()
        }

        for block in blocks {
            switch block {
            case .heading, .paragraph, .list, .blockquote, .horizontalRule:
                proseBuffer.append(block)
            case .frontmatter(let pairs):
                flushProse()
                addFullWidthView(makeFrontmatterView(pairs))
            case .codeBlock(let language, let code, let tokens):
                flushProse()
                addFullWidthView(makeCodeBlockView(language: language, code: code, tokens: tokens))
            case .callout(let kind, let title, let lines):
                flushProse()
                addFullWidthView(makeCalloutView(kind: kind, title: title, lines: lines))
            case .table(let headers, let alignments, let rows):
                flushProse()
                addFullWidthView(makeTableView(headers: headers, alignments: alignments, rows: rows))
            }
        }

        flushProse()
        needsLayout = true
        layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func addFullWidthView(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -56).isActive = true
    }

    private func clearOtherSelections(except active: NSTextView) {
        for tv in selectableTextViews where tv !== active && tv.selectedRange().length > 0 {
            tv.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    public func currentSelectedText() -> String {
        if let activeTV = window?.firstResponder as? NSTextView {
            let text = selectedPlainText(from: activeTV)
            if !text.isEmpty {
                return text
            }
        }
        for tv in selectableTextViews {
            let text = selectedPlainText(from: tv)
            if !text.isEmpty {
                return text
            }
        }
        return ""
    }

    public var hasSelection: Bool { !currentSelectedText().isEmpty }

    @discardableResult
    public func copyCurrentSelection() -> Bool {
        let text = currentSelectedText()
        guard !text.isEmpty else {
            return false
        }
        ClipboardHelper.copyText(text)
        return true
    }

    @discardableResult
    public func selectAllInActiveBlock() -> Bool {
        if let activeTV = window?.firstResponder as? NSTextView {
            activeTV.selectAll(nil)
            return true
        }
        if let firstTV = selectableTextViews.first {
            window?.makeFirstResponder(firstTV)
            firstTV.selectAll(nil)
            return true
        }
        return false
    }

    public func handleShortcutEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        guard flags == .command else {
            return false
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            return copyCurrentSelection()
        case "a":
            return selectAllInActiveBlock()
        default:
            return false
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleShortcutEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc public func copy(_ sender: Any?) {
        _ = copyCurrentSelection()
    }

    public override func selectAll(_ sender: Any?) {
        _ = selectAllInActiveBlock()
    }

    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(NSText.copy(_:)):
            return hasSelection
        case #selector(NSText.selectAll(_:)):
            return !selectableTextViews.isEmpty || (window?.firstResponder is NSTextView)
        default:
            return false
        }
    }

    // MARK: - Prose Rendering (Headings, Paragraphs, Lists, Blockquotes, HR)

    private func makeProseTextView(for blocks: [MarkdownBlock]) -> AutoSizingTextView {
        let textView = AutoSizingTextView()
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.onLinkClicked = { [weak self] url in
            self?.onOpenLink?(url)
        }
        textView.onNonEmptySelection = { [weak self] active in
            self?.clearOtherSelections(except: active)
        }
        selectableTextViews.append(textView)

        let attributed = NSMutableAttributedString()
        for (idx, block) in blocks.enumerated() {
            let isLast = idx == blocks.count - 1
            switch block {
            case .heading(let level, let inlines):
                attributed.append(attributedHeading(level: level, inlines: inlines, addTrailingSpacing: !isLast))
            case .paragraph(let inlines):
                attributed.append(attributedParagraph(inlines: inlines, addTrailingSpacing: !isLast))
            case .list(let items):
                attributed.append(attributedList(items: items, addTrailingSpacing: !isLast))
            case .blockquote(let lines):
                let innerText = lines.joined(separator: " ")
                attributed.append(attributedBlockquote(text: innerText, addTrailingSpacing: !isLast))
            case .horizontalRule:
                let rulePara = NSMutableParagraphStyle()
                rulePara.paragraphSpacing = isLast ? 0 : 12
                let rule = NSAttributedString(
                    string: "────────────────────────────────────────",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: NSColor.separatorColor,
                        .paragraphStyle: rulePara
                    ]
                )
                attributed.append(rule)
                if !isLast {
                    attributed.append(NSAttributedString(string: "\n"))
                }
            default:
                break
            }
        }

        textView.textStorage?.setAttributedString(attributed)
        return textView
    }

    private func attributedHeading(level: Int, inlines: [InlineNode], addTrailingSpacing: Bool) -> NSAttributedString {
        let sizes: [Int: CGFloat] = [1: 32, 2: 23, 3: 18, 4: 15.5, 5: 14, 6: 13]
        let fontSize = sizes[level] ?? 15
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: level == 1 ? .bold : .semibold)
        let color: NSColor = level == 6 ? .secondaryLabelColor : .labelColor

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        para.paragraphSpacingBefore = level <= 2 ? 10 : 6
        para.paragraphSpacing = addTrailingSpacing ? 10 : 0

        let result = NSMutableAttributedString()
        result.append(renderAttributedInlines(inlines, baseFont: baseFont, color: color))
        result.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: result.length))
        if addTrailingSpacing {
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    private func attributedParagraph(inlines: [InlineNode], addTrailingSpacing: Bool) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 15)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 5
        para.paragraphSpacing = addTrailingSpacing ? 10 : 0

        let result = NSMutableAttributedString()
        result.append(renderAttributedInlines(inlines, baseFont: baseFont, color: .labelColor))
        result.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: result.length))
        if addTrailingSpacing {
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    private func attributedBlockquote(text: String, addTrailingSpacing: Bool) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 14)
        let para = NSMutableParagraphStyle()
        para.firstLineHeadIndent = 14
        para.headIndent = 14
        para.lineSpacing = 4
        para.paragraphSpacing = addTrailingSpacing ? 10 : 0

        let result = NSMutableAttributedString(string: "│ ", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.separatorColor
        ])
        let inlines = MarkdownRenderer.parseInline(text)
        result.append(renderAttributedInlines(inlines, baseFont: baseFont, color: .secondaryLabelColor))
        result.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: result.length))
        if addTrailingSpacing {
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    private func attributedList(items: [NativeListItem], addTrailingSpacing: Bool) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: 14.5)
        let result = NSMutableAttributedString()

        for (idx, item) in items.enumerated() {
            let isLastItem = idx == items.count - 1
            let level = min(6, max(0, item.indent / 2))
            let indentPts = CGFloat(level) * 18 + 6

            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = indentPts
            para.headIndent = indentPts + 18
            para.lineSpacing = 4
            para.paragraphSpacing = (isLastItem && addTrailingSpacing) ? 10 : 4

            let markerText: String
            let markerColor: NSColor
            if let checked = item.taskState {
                markerText = checked ? "☑ " : "☐ "
                markerColor = checked ? .controlAccentColor : .secondaryLabelColor
            } else if item.ordered {
                markerText = "\(item.number). "
                markerColor = .secondaryLabelColor
            } else {
                markerText = level % 2 == 0 ? "• " : "◦ "
                markerColor = .secondaryLabelColor
            }

            let line = NSMutableAttributedString(
                string: markerText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14.5, weight: .medium),
                    .foregroundColor: markerColor
                ]
            )
            line.append(renderAttributedInlines(item.inlines, baseFont: baseFont, color: .labelColor))
            line.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: line.length))

            result.append(line)
            if !isLastItem || addTrailingSpacing {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private func renderAttributedInlines(_ nodes: [InlineNode], baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()

        func appendNodes(_ items: [InlineNode], font: NSFont, textColor: NSColor, strike: Bool, linkURL: String?) {
            for node in items {
                switch node {
                case .text(let s):
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: textColor
                    ]
                    if strike {
                        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    }
                    if let linkURL, let url = URL(string: linkURL) {
                        attrs[.link] = url
                        attrs[.foregroundColor] = NSColor.linkColor
                    }
                    result.append(NSAttributedString(string: s, attributes: attrs))
                case .code(let s):
                    let monoFont = NSFont.monospacedSystemFont(ofSize: max(12, font.pointSize - 1.5), weight: .regular)
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: monoFont,
                        .foregroundColor: textColor,
                        .backgroundColor: Self.inlineCodeBackground
                    ]
                    if let linkURL, let url = URL(string: linkURL) {
                        attrs[.link] = url
                    }
                    result.append(NSAttributedString(string: "\u{00A0}\(s)\u{00A0}", attributes: attrs))
                case .strong(let inner):
                    let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    appendNodes(inner, font: boldFont, textColor: textColor, strike: strike, linkURL: linkURL)
                case .emphasis(let inner):
                    let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    appendNodes(inner, font: italicFont, textColor: textColor, strike: strike, linkURL: linkURL)
                case .strongEmphasis(let inner):
                    var boldItalic = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    boldItalic = NSFontManager.shared.convert(boldItalic, toHaveTrait: .italicFontMask)
                    appendNodes(inner, font: boldItalic, textColor: textColor, strike: strike, linkURL: linkURL)
                case .strikethrough(let inner):
                    appendNodes(inner, font: font, textColor: .secondaryLabelColor, strike: true, linkURL: linkURL)
                case .link(let label, let url):
                    appendNodes(label, font: font, textColor: .linkColor, strike: strike, linkURL: url)
                case .image(let alt, let url):
                    let display = alt.isEmpty ? url : "[\(alt)]"
                    var attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor.linkColor
                    ]
                    if let parsed = URL(string: url) {
                        attrs[.link] = parsed
                    }
                    result.append(NSAttributedString(string: display, attributes: attrs))
                case .softBreak:
                    result.append(NSAttributedString(string: " ", attributes: [.font: font, .foregroundColor: textColor]))
                case .hardBreak:
                    result.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: textColor]))
                }
            }
        }

        appendNodes(nodes, font: baseFont, textColor: color, strike: false, linkURL: nil)
        return result
    }

    // MARK: - Cards (Code Block, Table, Callout, Frontmatter)

    private func makeCodeBlockView(language: String, code: String, tokens: [CodeToken]) -> NSView {
        let card = CardContainerView(fillColor: Self.cardBackground)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 12)
        header.translatesAutoresizingMaskIntoConstraints = false

        let langText = language.isEmpty ? "CODE" : language.uppercased()
        let langLabel = NSTextField(labelWithString: langText)
        langLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        langLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let copyButton = CodeCopyButton(code: code, target: self, action: #selector(handleCopyCodeButton(_:)))

        header.addArrangedSubview(langLabel)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(copyButton)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let codeAttr = NSMutableAttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3.5

        for token in tokens {
            let color: NSColor
            switch token.kind {
            case .plain: color = .labelColor
            case .keyword: color = Self.keywordColor
            case .string: color = Self.stringColor
            case .comment: color = Self.commentColor
            case .number: color = Self.numberColor
            case .type: color = Self.typeColor
            }
            codeAttr.append(NSAttributedString(
                string: token.text,
                attributes: [
                    .font: monoFont,
                    .foregroundColor: color,
                    .paragraphStyle: para
                ]
            ))
        }

        let codeTextView = SelectableTextView()
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.drawsBackground = false
        codeTextView.isHorizontallyResizable = true
        codeTextView.isVerticallyResizable = false
        codeTextView.textContainerInset = NSSize(width: 14, height: 12)
        codeTextView.textContainer?.lineFragmentPadding = 0
        codeTextView.textContainer?.widthTracksTextView = false
        codeTextView.textContainer?.heightTracksTextView = false
        codeTextView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        codeTextView.onNonEmptySelection = { [weak self] active in
            self?.clearOtherSelections(except: active)
        }
        selectableTextViews.append(codeTextView)
        codeTextView.textStorage?.setAttributedString(codeAttr)

        var measuredWidth: CGFloat = 200
        var measuredHeight: CGFloat = 24
        if let layoutManager = codeTextView.layoutManager, let textContainer = codeTextView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            measuredWidth = max(200, ceil(usedRect.width) + 28)
            measuredHeight = max(20, ceil(usedRect.height))
        }
        let totalCodeHeight = measuredHeight + 22
        codeTextView.frame = NSRect(x: 0, y: 0, width: measuredWidth, height: totalCodeHeight)
        codeTextView.minSize = NSSize(width: 0, height: totalCodeHeight)
        codeTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: totalCodeHeight)

        let codeScroll = CodeBlockScrollView(minimumContentWidth: measuredWidth, fixedContentHeight: totalCodeHeight)
        codeScroll.hasHorizontalScroller = true
        codeScroll.hasVerticalScroller = false
        codeScroll.autohidesScrollers = true
        codeScroll.drawsBackground = false
        codeScroll.documentView = codeTextView
        codeScroll.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(header)
        card.addSubview(divider)
        card.addSubview(codeScroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor),

            codeScroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            codeScroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            codeScroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            codeScroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            codeScroll.heightAnchor.constraint(equalToConstant: totalCodeHeight)
        ])

        return card
    }

    @objc private func handleCopyCodeButton(_ sender: CodeCopyButton) {
        ClipboardHelper.copyText(sender.rawCode)
        ClipboardHelper.flashButton(sender, restoreTitle: "复制")
    }

    private func makeCalloutView(kind: CalloutKind, title: String, lines: [String]) -> NSView {
        let accent: NSColor
        switch kind {
        case .note: accent = .systemBlue
        case .tip: accent = .systemGreen
        case .important: accent = .systemPurple
        case .warning: accent = .systemOrange
        case .caution: accent = .systemRed
        }

        let card = CardContainerView(fillColor: Self.cardBackground)

        let accentBar = DynamicColorView(fillColor: accent)
        accentBar.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = accent
        titleLabel.isSelectable = true
        stack.addArrangedSubview(titleLabel)
        titleLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -28).isActive = true

        let bodyBlocks = MarkdownRenderer.parseBlocks(lines.joined(separator: "\n"))
        if !bodyBlocks.isEmpty {
            let bodyView = makeProseTextView(for: bodyBlocks)
            bodyView.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(bodyView)
            bodyView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
        }

        card.addSubview(accentBar)
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            accentBar.topAnchor.constraint(equalTo: card.topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            accentBar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 4),

            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        return card
    }

    private func makeFrontmatterView(_ pairs: [(String, String)]) -> NSView {
        let card = CardContainerView(fillColor: Self.cardBackground)

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6
        outer.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "METADATA")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor
        outer.addArrangedSubview(header)

        let gridRows: [[NSView]] = pairs.map { key, value in
            let k = NSTextField(labelWithString: key)
            k.font = .systemFont(ofSize: 12.5, weight: .semibold)
            k.textColor = .secondaryLabelColor
            k.isSelectable = true
            k.setContentHuggingPriority(.required, for: .horizontal)

            let v = NSTextField(wrappingLabelWithString: value)
            v.font = .systemFont(ofSize: 12.5)
            v.isSelectable = true
            v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return [k, v]
        }

        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 4
        grid.columnSpacing = 14
        grid.yPlacement = .top
        grid.translatesAutoresizingMaskIntoConstraints = false
        outer.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true

        card.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            outer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            outer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            outer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10)
        ])

        return card
    }

    private func makeTableView(
        headers: [[InlineNode]],
        alignments: [MarkdownAlignment],
        rows: [[[InlineNode]]]
    ) -> NSView {
        let card = CardContainerView(fillColor: .separatorColor)

        let colCount = headers.count
        var gridRows: [[NSView]] = []

        func makeCell(inlines: [InlineNode], alignment: MarkdownAlignment, isHeader: Bool, isStriped: Bool) -> NSView {
            let cellBackground: NSColor = isHeader
                ? Self.cardBackground
                : (isStriped ? Self.tableStripeBackground : .textBackgroundColor)
            let wrapper = DynamicColorView(fillColor: cellBackground)

            let font = isHeader ? NSFont.systemFont(ofSize: 13.5, weight: .semibold) : NSFont.systemFont(ofSize: 13.5)
            let attr = NSMutableAttributedString(attributedString: renderAttributedInlines(inlines, baseFont: font, color: .labelColor))
            let para = NSMutableParagraphStyle()
            switch alignment {
            case .left, .none: para.alignment = .left
            case .center: para.alignment = .center
            case .right: para.alignment = .right
            }
            attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))

            let field = NSTextField(wrappingLabelWithString: "")
            field.attributedStringValue = attr
            field.isSelectable = true
            field.allowsEditingTextAttributes = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.translatesAutoresizingMaskIntoConstraints = false

            wrapper.addSubview(field)
            NSLayoutConstraint.activate([
                field.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8),
                field.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -8),
                field.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 12),
                field.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -12)
            ])
            return wrapper
        }

        let headerCells = (0..<colCount).map { idx in
            let align = idx < alignments.count ? alignments[idx] : .none
            return makeCell(inlines: headers[idx], alignment: align, isHeader: true, isStriped: false)
        }
        gridRows.append(headerCells)

        for (rIdx, row) in rows.enumerated() {
            let cells = (0..<colCount).map { cIdx in
                let align = cIdx < alignments.count ? alignments[cIdx] : .none
                let cellInlines = cIdx < row.count ? row[cIdx] : []
                return makeCell(inlines: cellInlines, alignment: align, isHeader: false, isStriped: rIdx % 2 == 1)
            }
            gridRows.append(cells)
        }

        let grid = NSGridView(views: gridRows)
        grid.xPlacement = .fill
        grid.yPlacement = .fill
        grid.rowSpacing = 1
        grid.columnSpacing = 1
        grid.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: card.topAnchor),
            grid.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        return card
    }
}
