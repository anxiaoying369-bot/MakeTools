import AppKit
import ImageIO
import QuartzCore
import QuickLookThumbnailing

/// Non-activating borderless floating panel used for the Dynamic Island overlay.
private final class DynamicIslandPanel: NSPanel, NSDraggingDestination {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // The window is a fallback destination even when a native control owns the hit view.
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (contentView as? DynamicIslandContentView)?.draggingEntered(sender) ?? []
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (contentView as? DynamicIslandContentView)?.draggingUpdated(sender) ?? []
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        (contentView as? DynamicIslandContentView)?.draggingExited(sender)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (contentView as? DynamicIslandContentView)?.performDragOperation(sender) ?? false
    }
}

private enum IslandColors {
    static let shell = NSColor(srgbRed: 0.037, green: 0.063, blue: 0.125, alpha: 1)
    static let expanded = NSColor(srgbRed: 0.055, green: 0.09, blue: 0.169, alpha: 1)
    static let card = NSColor(srgbRed: 0.087, green: 0.139, blue: 0.235, alpha: 1)
    static let stroke = NSColor(srgbRed: 0.64, green: 0.75, blue: 1, alpha: 0.24)
    static let accent = NSColor(srgbRed: 0.59, green: 0.73, blue: 1, alpha: 1)
    static let text = NSColor(srgbRed: 0.85, green: 0.9, blue: 1, alpha: 1)
    static let control = NSColor(srgbRed: 0.45, green: 0.61, blue: 1, alpha: 0.14)
}

private final class IslandGlassBackdrop: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct IslandMaterialPalette {
    let shell: NSColor
    let expanded: NSColor
    let card: NSColor
    let stroke: NSColor

    init(material: DynamicIslandMaterial, translucent: Bool) {
        func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: alpha)
        }

        switch material {
        case .midnight:
            (shell, expanded, card, stroke) = (IslandColors.shell, IslandColors.expanded, IslandColors.card, IslandColors.stroke)
        case .frostedGlass:
            (shell, expanded, card, stroke) = translucent
                ? (color(0x15223c, alpha: 0.47), color(0x15223c, alpha: 0.52),
                   color(0x192a47, alpha: 0.49), color(0xdbe9ff, alpha: 0.40))
                : (color(0x1b2638), color(0x233147), color(0x2c3d57), color(0xdbe9ff, alpha: 0.32))
        case .graphite:
            (shell, expanded, card, stroke) = (color(0x101114), color(0x1b1d22), color(0x2b2e36), color(0xe3e6ed, alpha: 0.28))
        case .warmAmber:
            (shell, expanded, card, stroke) = (color(0x291a16), color(0x34231d), color(0x4c3227), color(0xffbe85, alpha: 0.36))
        }
    }
}

/// Dark rounded Bento tile inside the expanded Dynamic Island (direct Auto Layout, no NSBox.contentView).
private final class IslandCardView: NSView {
    var palette = IslandMaterialPalette(material: .midnight, translucent: false) {
        didSet { needsDisplay = true }
    }
    var isDropHighlighted: Bool = false {
        didSet { needsDisplay = true; layer?.setNeedsDisplay() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        layer?.cornerRadius = 12
        layer?.borderWidth = isDropHighlighted ? 1.4 : 0.75
        layer?.backgroundColor = palette.card.cgColor
        layer?.borderColor = isDropHighlighted
            ? IslandColors.accent.cgColor
            : palette.stroke.cgColor
    }
}

/// Thin 4pt capsule progress meter for CPU and memory utilization.
private final class IslandProgressBar: NSView {
    var progress: Double = 0 {
        didSet {
            let clamped = Self.normalized(progress)
            guard clamped != Self.normalized(oldValue) else { return }
            fillWidthConstraint?.isActive = false
            fillWidthConstraint = clamped == 0
                ? fillView.widthAnchor.constraint(equalToConstant: 0)
                : fillView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: clamped)
            fillWidthConstraint?.isActive = true
            needsLayout = true
        }
    }

    var fillColor: NSColor = .systemTeal {
        didSet {
            fillView.layer?.backgroundColor = fillColor.cgColor
        }
    }

    private let fillView = NSView()
    private var fillWidthConstraint: NSLayoutConstraint?

    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        fillView.wantsLayer = true
        fillView.layer?.cornerRadius = 2
        fillView.layer?.backgroundColor = fillColor.cgColor
        fillView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fillView)

        let widthC = fillView.widthAnchor.constraint(equalToConstant: 0)
        fillWidthConstraint = widthC
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 4),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            widthC
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Shared pointer and press feedback for the overlay's borderless controls.
private class IslandButton: NSButton {
    var normalBackground = IslandColors.control {
        didSet {
            if oldValue != normalBackground { updateBackground() }
        }
    }

    private var pointerTracking: NSTrackingArea?
    private var isHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        pointerTracking = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isHovered = false
        updateBackground()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateBackground(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateBackground(animated: true)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateBackground(animated: true)
    }

    private func updateBackground(animated: Bool = false) {
        guard let layer else { return }
        let color: NSColor
        if isHighlighted {
            color = normalBackground.blended(withFraction: 0.22, of: .white) ?? normalBackground
        } else if isHovered {
            color = normalBackground.blended(withFraction: 0.10, of: .white) ?? normalBackground
        } else {
            color = normalBackground
        }

        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color.cgColor
        CATransaction.commit()

        if animated && ToolAppearance.allowsMotion {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = previous
            animation.toValue = color.cgColor
            animation.duration = 0.14
            layer.add(animation, forKey: "pointerFeedback")
        }
    }
}

/// Strictly circular SF Symbol icon button for the Dynamic Island.
private final class IslandIconButton: IslandButton {
    private let diameter: CGFloat

    init(
        symbolName: String,
        accessibilityLabel: String,
        diameter: CGFloat = 22,
        pointSize: CGFloat = 10.5,
        target: AnyObject?,
        action: Selector?
    ) {
        self.diameter = diameter
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.refusesFirstResponder = true
        self.imagePosition = .imageOnly
        self.toolTip = accessibilityLabel
        self.setAccessibilityLabel(accessibilityLabel)
        self.contentTintColor = .white
        self.wantsLayer = true
        self.layer?.cornerRadius = diameter * 0.34
        self.layer?.backgroundColor = normalBackground.cgColor
        self.translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter)
        ])
        setSymbol(symbolName, pointSize: pointSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSymbol(_ symbolName: String, pointSize: CGFloat = 10.5) {
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        self.image = img?.withSymbolConfiguration(config)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: diameter, height: diameter)
    }
}

/// Compact dark pill chip button used for timer presets, keep-awake toggle, and footer actions.
private final class IslandChipButton: IslandButton {
    var textColor: NSColor = NSColor(white: 0.92, alpha: 1.0) {
        didSet { updateAttributedTitle(fontSize: font?.pointSize ?? 10.5) }
    }

    private let horizontalPadding: CGFloat
    private let fixedHeight: CGFloat

    init(
        title: String,
        fontSize: CGFloat = 10.5,
        horizontalPadding: CGFloat = 10,
        height: CGFloat = 20,
        target: AnyObject?,
        action: Selector?
    ) {
        self.horizontalPadding = horizontalPadding
        self.fixedHeight = height
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.refusesFirstResponder = true
        self.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        self.wantsLayer = true
        self.layer?.cornerRadius = max(5, height * 0.36)
        self.layer?.backgroundColor = normalBackground.cgColor
        updateAttributedTitle(fontSize: fontSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAttributedTitle(fontSize: CGFloat) {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: textColor
            ]
        )
    }

    override var title: String {
        didSet {
            updateAttributedTitle(fontSize: font?.pointSize ?? 10.5)
        }
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + horizontalPadding, height: fixedHeight)
    }
}

/// Cached preview payload for staged shelf files.
private enum ShelfPreviewContent {
    case image(NSImage)
    case textSnippet(String)
    case icon(NSImage)
}

/// Generates and caches thumbnails (ImageIO / QuickLookThumbnailing) and text snippets for the 3x3 File Shelf.
private final class ShelfPreviewProvider {
    static let shared = ShelfPreviewProvider()

    private var cache: [URL: ShelfPreviewContent] = [:]
    private var order: [URL] = []
    private var inFlight: Set<URL> = []

    func cachedContent(for url: URL) -> ShelfPreviewContent? {
        cache[url]
    }

    func preloadSynchronously(for url: URL) {
        if cache[url] != nil { return }
        switch ShelfPreviewHelper.classify(url: url) {
        case .text:
            if let snippet = ShelfPreviewHelper.readTextSnippet(from: url) {
                store(.textSnippet(snippet), for: url)
            } else {
                store(.icon(NSWorkspace.shared.icon(forFile: url.path)), for: url)
            }
        case .image:
            if let img = Self.decodeImageThumbnail(at: url, maxPixelSize: 160) {
                store(.image(img), for: url)
            } else {
                store(.icon(NSWorkspace.shared.icon(forFile: url.path)), for: url)
            }
        case .other:
            store(.icon(NSWorkspace.shared.icon(forFile: url.path)), for: url)
        }
    }

    func loadPreview(for url: URL, completion: @escaping (URL, ShelfPreviewContent) -> Void) {
        if let existing = cache[url] {
            completion(url, existing)
            return
        }

        let kind = ShelfPreviewHelper.classify(url: url)
        if kind == .text {
            let content: ShelfPreviewContent
            if let snippet = ShelfPreviewHelper.readTextSnippet(from: url) {
                content = .textSnippet(snippet)
            } else {
                content = .icon(NSWorkspace.shared.icon(forFile: url.path))
            }
            store(content, for: url)
            completion(url, content)
            return
        }

        guard !inFlight.contains(url) else { return }
        inFlight.insert(url)

        if kind == .image {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let thumb = Self.decodeImageThumbnail(at: url, maxPixelSize: 160)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.inFlight.remove(url)
                    let content: ShelfPreviewContent = thumb.map(ShelfPreviewContent.image)
                        ?? .icon(NSWorkspace.shared.icon(forFile: url.path))
                    self.store(content, for: url)
                    completion(url, content)
                }
            }
            return
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 120, height: 96),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(url)
                let content: ShelfPreviewContent
                if let rep {
                    content = .image(rep.nsImage)
                } else {
                    content = .icon(NSWorkspace.shared.icon(forFile: url.path))
                }
                self.store(content, for: url)
                completion(url, content)
            }
        }
    }

    private func store(_ content: ShelfPreviewContent, for url: URL) {
        cache[url] = content
        order.removeAll { $0 == url }
        order.append(url)
        if order.count > 32, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    private static func decodeImageThumbnail(at url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Image view whose intrinsic size never distorts fixed or equally-distributed grid cells.
private final class FlexiblePreviewImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Shared drag source for full-size shelf cells and the collapsed shelf.
private class ShelfFileDragView: NSView, NSDraggingSource {
    var fileURL: URL?
    var onSelect: (() -> Void)?
    var onOpen: (() -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var mouseDownPoint: NSPoint?
    private var didStartDrag = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
        guard fileURL != nil else { return }
        onSelect?()
        if event.clickCount >= 2 {
            onOpen?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url = fileURL, !didStartDrag, let start = mouseDownPoint else {
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        let dist = hypot(current.x - start.x, current.y - start.y)
        guard dist >= 4 else { return }

        didStartDrag = true
        onDragStarted?()

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let previewImage = NSWorkspace.shared.icon(forFile: url.path)
        previewImage.size = NSSize(width: 32, height: 32)
        draggingItem.setDraggingFrame(NSRect(x: current.x - 16, y: current.y - 16, width: 32, height: 32), contents: previewImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        didStartDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.copy, .move]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?()
    }
}

private final class CollapsedShelfTile: ShelfFileDragView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyDown
        title.font = .systemFont(ofSize: 9, weight: .medium)
        title.textColor = IslandColors.text
        title.alignment = .center
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [icon, title] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 1),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ url: URL) {
        fileURL = url
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 17, height: 17)
        icon.image = image
        title.stringValue = url.lastPathComponent
        toolTip = url.lastPathComponent
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(url.lastPathComponent)
    }
}

/// Interactive single tile inside the 3x3 File Shelf grid.
private final class ShelfGridCellView: ShelfFileDragView {
    var isSelectedSlot: Bool = false

    private let previewContainer = NSView()
    private let emptyIcon = ToolAppearance.icon("plus", size: 10, tint: IslandColors.text.withAlphaComponent(0.32))
    private let previewImageView = FlexiblePreviewImageView()
    private let textPreviewBox = NSView()
    private let textSnippetLabel = NSTextField(wrappingLabelWithString: "")
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        previewImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        previewImageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 5
        previewImageView.layer?.masksToBounds = true
        previewImageView.layer?.backgroundColor = IslandColors.shell.cgColor
        previewImageView.translatesAutoresizingMaskIntoConstraints = false

        textPreviewBox.wantsLayer = true
        textPreviewBox.layer?.cornerRadius = 5
        textPreviewBox.layer?.masksToBounds = true
        textPreviewBox.layer?.borderWidth = 0.5
        textPreviewBox.layer?.backgroundColor = IslandColors.expanded.cgColor
        textPreviewBox.layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        textPreviewBox.translatesAutoresizingMaskIntoConstraints = false

        textSnippetLabel.font = .monospacedSystemFont(ofSize: 6.5, weight: .regular)
        textSnippetLabel.textColor = NSColor(white: 0.84, alpha: 1.0)
        textSnippetLabel.maximumNumberOfLines = 4
        textSnippetLabel.lineBreakMode = .byWordWrapping
        textSnippetLabel.preferredMaxLayoutWidth = 60
        textSnippetLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textSnippetLabel.setContentHuggingPriority(.defaultLow, for: .vertical)
        textSnippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textSnippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textSnippetLabel.translatesAutoresizingMaskIntoConstraints = false
        textPreviewBox.addSubview(textSnippetLabel)

        iconView.translatesAutoresizingMaskIntoConstraints = false

        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(textPreviewBox)
        previewContainer.addSubview(iconView)

        nameLabel.font = .systemFont(ofSize: 9, weight: .medium)
        nameLabel.textColor = NSColor(white: 0.90, alpha: 1.0)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(previewContainer)
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyIcon)
        NSLayoutConstraint.activate([
            emptyIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyIcon.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        previewContainer.isHidden = true
        nameLabel.isHidden = true
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            previewContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            previewContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            previewContainer.bottomAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -2),

            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),

            textPreviewBox.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            textPreviewBox.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            textPreviewBox.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            textPreviewBox.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),

            textSnippetLabel.topAnchor.constraint(equalTo: textPreviewBox.topAnchor, constant: 2),
            textSnippetLabel.leadingAnchor.constraint(equalTo: textPreviewBox.leadingAnchor, constant: 4),
            textSnippetLabel.trailingAnchor.constraint(equalTo: textPreviewBox.trailingAnchor, constant: -4),
            textSnippetLabel.bottomAnchor.constraint(lessThanOrEqualTo: textPreviewBox.bottomAnchor, constant: -2),

            iconView.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: previewContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            nameLabel.heightAnchor.constraint(equalToConstant: 12)
        ])

        configure(with: nil, isSelected: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.masksToBounds = true
        layer?.cornerRadius = 9
        if fileURL == nil {
            layer?.backgroundColor = IslandColors.control.cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        } else if isSelectedSlot {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            layer?.borderWidth = 1.4
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.backgroundColor = IslandColors.shell.cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        }
    }

    func configure(with url: URL?, isSelected: Bool) {
        let urlChanged = (self.fileURL != url)
        self.fileURL = url
        self.isSelectedSlot = url != nil && isSelected
        emptyIcon.isHidden = url != nil

        if urlChanged {
            if let url {
                previewContainer.isHidden = false
                nameLabel.isHidden = false
                nameLabel.stringValue = url.lastPathComponent
                toolTip = url.path

                if let cached = ShelfPreviewProvider.shared.cachedContent(for: url) {
                    applyPreviewContent(cached)
                } else {
                    let fallback = NSWorkspace.shared.icon(forFile: url.path)
                    fallback.size = NSSize(width: 24, height: 24)
                    applyPreviewContent(.icon(fallback))

                    ShelfPreviewProvider.shared.loadPreview(for: url) { [weak self] loadedURL, content in
                        guard let self, self.fileURL == loadedURL else { return }
                        self.applyPreviewContent(content)
                    }
                }
            } else {
                previewContainer.isHidden = true
                nameLabel.isHidden = true
                previewImageView.image = nil
                textSnippetLabel.stringValue = ""
                iconView.image = nil
                nameLabel.stringValue = ""
                toolTip = nil
            }
        }

        needsDisplay = true
        layer?.setNeedsDisplay()
    }

    private func applyPreviewContent(_ content: ShelfPreviewContent) {
        previewImageView.isHidden = true
        textPreviewBox.isHidden = true
        iconView.isHidden = true

        switch content {
        case .image(let image):
            previewImageView.image = image
            previewImageView.isHidden = false
        case .textSnippet(let snippet):
            textSnippetLabel.stringValue = snippet
            textPreviewBox.isHidden = false
        case .icon(let icon):
            icon.size = NSSize(width: 24, height: 24)
            iconView.image = icon
            iconView.isHidden = false
        }
    }


}

/// Main visual view rendered inside `DynamicIslandPanel` with authentic Apple Notch silhouette & 3x3 File Shelf.
public final class DynamicIslandContentView: NSView {
    private weak var manager: DynamicIslandManager?

    private var trackingArea: NSTrackingArea?
    private var hoverInWorkItem: DispatchWorkItem?
    private var hoverOutWorkItem: DispatchWorkItem?
    private var clipboardMenu: NSMenu?
    private lazy var passwordBook = PasswordBookWindowController()
    private var calendarCountdown: CalendarCountdownWindowController?
    private weak var presentedPasswordBook: NSWindow?
    private weak var presentedBookmarks: NSWindow?

    var hasOpenEditor: Bool {
        calendarCountdown?.window?.isVisible == true ||
            presentedPasswordBook?.isVisible == true || presentedBookmarks?.isVisible == true
    }
    private let webBookmarkStore = WebBookmarkStore()
    private var webBookmarks: [WebBookmark] = []
    private lazy var webBookmarksWindow: WebBookmarksWindowController = {
        let controller = WebBookmarksWindowController(store: webBookmarkStore)
        controller.onChange = { [weak self] bookmarks in
            self?.webBookmarks = bookmarks
            self?.refreshBookmarkCard()
        }
        return controller
    }()
    private let editLayoutButton = IslandIconButton(
        symbolName: "pencil", accessibilityLabel: L10n.text("island.layout.edit", "编辑布局…"), target: nil, action: nil
    )
    private var isDragHighlighted = false

    private static let outline = IslandColors.stroke.cgColor
    private let pillShapeLayer = CAShapeLayer()
    private let glass = IslandGlassBackdrop()
    private struct GlassShape: Equatable {
        let size: NSSize
        let cornerRadius: CGFloat
        let earRadius: CGFloat
        let isTopAttached: Bool
    }

    private var glassShape: GlassShape?
    private var appearanceObserver: NSObjectProtocol?
    private var usesGlass = false
    private var palette = IslandMaterialPalette(material: .midnight, translucent: false)
    public let contentContainer = NSView()
    public private(set) var currentGeometry: IslandGeometry = IslandGeometry.compute(
        screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0,
        notchWidth: nil,
        style: .auto,
        state: .collapsed
    )

    // Mutually exclusive state views (only the active one is mounted in contentContainer)
    private let collapsedBar = NSStackView()
    private let collapsedShelf = NSStackView()
    private var collapsedShelfFiles: [URL] = []
    private let hudContainer = NSView()
    private let hudBar = NSStackView()
    private var hudTopConstraint: NSLayoutConstraint?
    private let expandedContainer = NSStackView()
    private let bentoHost = NSStackView()
    private let footerRow = NSStackView()

    // Collapsed subviews
    private let collapsedDot = NSView()
    private let collapsedTitleLabel = NSTextField(labelWithString: "MakeTools")
    private let collapsedLeftSpacer = NSView()
    private let leftWingContainer = NSStackView()
    private let collapsedNotchGapView = NSView()
    private var collapsedNotchGapWidthConstraint: NSLayoutConstraint?
    private let rightWingContainer = NSStackView()
    private let collapsedRightSpacer = NSView()
    private let collapsedMetricLabel = NSTextField(labelWithString: "CPU 0%")
    private var displayedCollapsedMetric: CollapsedMetricItem?
    private var collapsedEqualWingsConstraint: NSLayoutConstraint?

    // HUD subviews
    private let hudIconBadge = NSView()
    private let hudIconView = NSImageView()
    private let hudTitleLabel = NSTextField(labelWithString: "")
    private let hudDetailLabel = NSTextField(labelWithString: "")

    // Expanded header
    private let expandedClockLabel = NSTextField(labelWithString: "00:00:00")
    private let expandedBatteryIcon = NSImageView()
    private let expandedBatteryLabel = NSTextField(labelWithString: "")
    private let pinButton = IslandIconButton(
        symbolName: "pin",
        accessibilityLabel: L10n.text("island.pinDynamicIsland", "固定灵动岛"),
        target: nil,
        action: nil
    )

    // Bento Card A: Performance & Network (compact 72pt height)
    private var systemCard = IslandCardView()
    private let cpuGroup = NSStackView()
    private let cpuValueLabel = NSTextField(labelWithString: "0%")
    private let cpuBar = IslandProgressBar()
    private let memGroup = NSStackView()
    private let memValueLabel = NSTextField(labelWithString: "0%")
    private let memBar = IslandProgressBar()
    private let downloadSpeedLabel = NSTextField(labelWithString: "↓ 0 B/s")
    private let uploadSpeedLabel = NSTextField(labelWithString: "↑ 0 B/s")

    // Bento Card B: Audio & Keep-Awake (compact 72pt height)
    private var audioCard = IslandCardView()
    private let audioSection = NSStackView()
    private let muteButton = IslandIconButton(
        symbolName: "speaker.wave.2.fill",
        accessibilityLabel: L10n.text("island.muteOrUnmute", "静音/取消静音"),
        diameter: 18,
        pointSize: 9,
        target: nil,
        action: nil
    )
    private let volumeSlider = NSSlider(value: 0.5, minValue: 0.0, maxValue: 1.0, target: nil, action: nil)
    private let volumeValueLabel = NSTextField(labelWithString: "50%")
    private let keepAwakeButton = IslandChipButton(
        title: L10n.text("island.keepAwakeOff.263", "☕ 防休眠: 关"),
        fontSize: 10,
        horizontalPadding: 12,
        height: 20,
        target: nil,
        action: nil
    )

    // Bento Card C: Focus Timer (compact 72pt height)
    private var timerCard = IslandCardView()
    private let timerCountdownLabel = NSTextField(labelWithString: "25:00")
    private let timerToggleButton = IslandIconButton(
        symbolName: "play.fill",
        accessibilityLabel: L10n.text("island.startOrPauseFocus", "开始/暂停专注"),
        diameter: 22,
        pointSize: 9.5,
        target: nil,
        action: nil
    )

    private var bookmarkCard = IslandCardView()
    private let bookmarkEmptyLabel = NSTextField(labelWithString: L10n.text("island.addWebsitesThenClickANameTo", "添加常用网页，点击名称即可打开"))
    private var bookmarkLinks: [IslandChipButton] = []
    private weak var bookmarkManageButton: IslandChipButton?

    private var lanTransferCard = IslandCardView()
    private let lanTransfer = LANTransferController.shared
    private var lanTransferObserver: NSObjectProtocol?
    private var lanTransferLinkWindow: LANTransferLinkWindowController?
    private var revealLANTransferLinkWhenReady = false
    private let lanTransferToggle = IslandChipButton(title: L10n.text("island.enable", "开启"), fontSize: 10, horizontalPadding: 9, height: 17,
                                                    target: nil, action: nil)
    private let lanTransferQR = IslandChipButton(title: L10n.text("island.qrCode", "二维码"), fontSize: 10, horizontalPadding: 9, height: 17,
                                                target: nil, action: nil)
    private let lanTransferCopy = IslandChipButton(title: L10n.text("lanTransfer.copyLink", "复制链接"), fontSize: 10, horizontalPadding: 9, height: 17,
                                                  target: nil, action: nil)
    private let lanTransferStatus = NSTextField(labelWithString: "")

    private var calendarCard = IslandCardView()
    private let calendarDateLabel = NSTextField(labelWithString: "")
    private let calendarEventLabel = NSTextField(labelWithString: "")
    private let calendarHolidayLabel = NSTextField(labelWithString: "")
    private var calendarHolidayRevision = -1
    private var calendarDisplayDay: CountdownDay?
    private var displayedCalendarEvents: [CalendarCountdownEvent] = []

    // Bento Card D: 3x3 File Shelf (230pt height)
    private var shelfCard = IslandCardView()
    private let shelfHeaderLabel = NSTextField(labelWithString: L10n.text("island.shelf09", "暂存架 (0/9)"))
    private let shelfActionsGroup = NSStackView()
    private var shelfActionButtons: [NSButton] = []
    private let shelfHintLabel = NSTextField(labelWithString: L10n.text("island.dragUpToNineFilesToDynamic", "拖入文件到顶部灵动岛（支持多文件九宫格）"))
    private var shelfCells: [ShelfGridCellView] = []

    // Expanded footer: Clipboard History
    private let clipboardIndexLabel = NSTextField(labelWithString: "0/0")
    private let clipboardLabel = NSTextField(labelWithString: L10n.text("island.clipboardNoText", "剪贴板: 暂无文本"))

    private var lastExpandedLayout: IslandExpandedLayout?
    private var lastExpandedCards: [IslandExpandedCard] = []
    private var bentoStacks: [NSStackView] = []
    private var bentoConstraints: [NSLayoutConstraint] = []
    private var displayedState: DynamicIslandState?

    private static let clockFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    private let fullTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.locale = L10n.locale
        fmt.dateFormat = L10n.text("island.dateTimeFormat", "M月d日 HH:mm:ss")
        return fmt
    }()

    public init(manager: DynamicIslandManager) {
        self.manager = manager
        super.init(frame: .zero)
        setupView()
        lanTransferObserver = NotificationCenter.default.addObserver(
            forName: LANTransferController.didChange, object: lanTransfer, queue: .main
        ) { [weak self] _ in self?.refreshLANTransferCard() }
        refreshLANTransferCard()
        appearanceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applyMaterial(self.manager?.material ?? .midnight)
        }
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let lanTransferObserver { NotificationCenter.default.removeObserver(lanTransferObserver) }
        if let appearanceObserver { NSWorkspace.shared.notificationCenter.removeObserver(appearanceObserver) }
        lanTransferLinkWindow?.close()
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        pillShapeLayer.fillColor = IslandColors.shell.cgColor
        pillShapeLayer.strokeColor = Self.outline
        pillShapeLayer.lineWidth = 0.75
        pillShapeLayer.shadowColor = NSColor.black.cgColor
        pillShapeLayer.shadowOffset = CGSize(width: 0, height: -4)
        pillShapeLayer.shadowRadius = 4
        pillShapeLayer.shadowOpacity = 0.22
        glass.material = .hudWindow
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.isHidden = true
        glass.wantsLayer = true
        addSubview(glass)
        glass.layer?.zPosition = -1
        layer?.addSublayer(pillShapeLayer)

        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(contentContainer)

        collapsedShelf.orientation = .horizontal
        collapsedShelf.alignment = .centerY
        collapsedShelf.distribution = .fillEqually
        collapsedShelf.spacing = 3
        collapsedShelf.setAccessibilityLabel(L10n.text("island.shelf", "暂存架"))
        collapsedShelf.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        collapsedShelf.wantsLayer = true
        collapsedShelf.layer?.cornerCurve = .continuous
        collapsedShelf.layer?.cornerRadius = 12
        collapsedShelf.layer?.borderWidth = 0.75
        collapsedShelf.isHidden = true
        addSubview(collapsedShelf)

        setupCollapsedBar()
        setupHUDBar()
        setupExpandedContainer()
        applyMaterial(manager?.material ?? .midnight)

        applyState(.collapsed)
        applyGeometry(currentGeometry, animated: false)
    }

    private func setupCollapsedBar() {
        collapsedBar.orientation = .horizontal
        collapsedBar.alignment = .centerY
        collapsedBar.spacing = 6
        collapsedBar.edgeInsets = NSEdgeInsets(top: 0, left: 13, bottom: 0, right: 13)
        collapsedBar.translatesAutoresizingMaskIntoConstraints = false

        collapsedDot.wantsLayer = true
        collapsedDot.layer?.cornerRadius = 3
        collapsedDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        collapsedDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collapsedDot.widthAnchor.constraint(equalToConstant: 6),
            collapsedDot.heightAnchor.constraint(equalToConstant: 6)
        ])

        collapsedTitleLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        collapsedTitleLabel.textColor = NSColor(white: 0.90, alpha: 1.0)
        collapsedTitleLabel.lineBreakMode = .byTruncatingTail
        collapsedTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        collapsedLeftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        collapsedLeftSpacer.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)

        leftWingContainer.orientation = .horizontal
        leftWingContainer.alignment = .centerY
        leftWingContainer.spacing = 6
        leftWingContainer.translatesAutoresizingMaskIntoConstraints = false
        leftWingContainer.addArrangedSubview(collapsedDot)
        leftWingContainer.addArrangedSubview(collapsedTitleLabel)
        leftWingContainer.addArrangedSubview(collapsedLeftSpacer)

        collapsedNotchGapView.wantsLayer = false
        collapsedNotchGapView.translatesAutoresizingMaskIntoConstraints = false
        let gapWidthConstraint = collapsedNotchGapView.widthAnchor.constraint(equalToConstant: 0)
        gapWidthConstraint.isActive = true
        collapsedNotchGapWidthConstraint = gapWidthConstraint
        collapsedNotchGapView.isHidden = true

        collapsedRightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        collapsedRightSpacer.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)

        collapsedMetricLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        collapsedMetricLabel.textColor = NSColor(white: 0.78, alpha: 1.0)
        collapsedMetricLabel.alignment = .right
        collapsedMetricLabel.lineBreakMode = .byTruncatingTail
        collapsedMetricLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rightWingContainer.orientation = .horizontal
        rightWingContainer.alignment = .centerY
        rightWingContainer.spacing = 6
        rightWingContainer.translatesAutoresizingMaskIntoConstraints = false
        rightWingContainer.addArrangedSubview(collapsedRightSpacer)
        rightWingContainer.addArrangedSubview(collapsedMetricLabel)

        collapsedBar.addArrangedSubview(leftWingContainer)
        collapsedBar.addArrangedSubview(collapsedNotchGapView)
        collapsedBar.addArrangedSubview(rightWingContainer)

        let equalWings = leftWingContainer.widthAnchor.constraint(equalTo: rightWingContainer.widthAnchor)
        equalWings.priority = .required
        equalWings.isActive = false
        collapsedEqualWingsConstraint = equalWings
    }

    public func preferredCollapsedPillWidth(notchReservedWidth: CGFloat = 0) -> CGFloat {
        guard let manager else { return 196 }
        let leftText = manager.collapsedStatusText
        let metrics = manager.orderedEnabledCollapsedMetrics
        let now = Date()
        let leftFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let rightFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

        let leftTextWidth: CGFloat = leftText.map {
            ceil(NSAttributedString(string: $0, attributes: [.font: leftFont]).size().width)
        } ?? 0
        // Reserve room for the widest selected metric so the panel does not resize as it rotates.
        let rightTextWidth = metrics.map { metric in
            let text = manager.latestSnapshot.formatCollapsedMetric(metric, now: now)
            return ceil(NSAttributedString(string: text, attributes: [.font: rightFont]).size().width)
        }.max() ?? 0

        if notchReservedWidth > 0 {
            let leftWingNeeded = 6 + (leftTextWidth > 0 ? (6 + leftTextWidth) : 0)
            let rightWingNeeded = rightTextWidth
            let wingWidth = max(leftWingNeeded, rightWingNeeded, 36)
            return ceil(notchReservedWidth + wingWidth * 2 + 26 + 12)
        }

        var width: CGFloat = 26 + 6 + 6 // edgeInsets (13*2) + dot (6) + dot spacing (6)
        width += leftTextWidth + rightTextWidth
        if leftText != nil && !metrics.isEmpty {
            width += 16
        } else if leftText != nil || !metrics.isEmpty {
            width += 4
        }
        return max(136, ceil(width))
    }

    public static func preloadShelfPreviewsSynchronouslyForTesting(_ urls: [URL]) {
        for url in urls {
            ShelfPreviewProvider.shared.preloadSynchronously(for: url)
        }
    }

    private func setupHUDBar() {
        hudContainer.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.wantsLayer = true
        hudContainer.layer?.masksToBounds = true

        hudBar.orientation = .horizontal
        hudBar.alignment = .centerY
        hudBar.spacing = 8
        hudBar.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        hudBar.translatesAutoresizingMaskIntoConstraints = false
        hudContainer.addSubview(hudBar)

        // Keep the row below the notch and clip it while the panel grows into place.
        let top = hudBar.topAnchor.constraint(equalTo: hudContainer.topAnchor)
        hudTopConstraint = top
        NSLayoutConstraint.activate([
            top,
            hudBar.leadingAnchor.constraint(equalTo: hudContainer.leadingAnchor),
            hudBar.trailingAnchor.constraint(equalTo: hudContainer.trailingAnchor),
            hudBar.heightAnchor.constraint(equalToConstant: IslandGeometry.hudRowHeight)
        ])

        hudIconBadge.wantsLayer = true
        hudIconBadge.layer?.cornerRadius = 11
        hudIconBadge.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.18).cgColor
        hudIconBadge.translatesAutoresizingMaskIntoConstraints = false

        hudIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        hudIconView.contentTintColor = .systemTeal
        hudIconView.translatesAutoresizingMaskIntoConstraints = false
        hudIconBadge.addSubview(hudIconView)

        NSLayoutConstraint.activate([
            hudIconBadge.widthAnchor.constraint(equalToConstant: 22),
            hudIconBadge.heightAnchor.constraint(equalToConstant: 22),
            hudIconView.centerXAnchor.constraint(equalTo: hudIconBadge.centerXAnchor),
            hudIconView.centerYAnchor.constraint(equalTo: hudIconBadge.centerYAnchor)
        ])

        hudTitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        hudTitleLabel.textColor = .white
        hudTitleLabel.setContentHuggingPriority(.required, for: .horizontal)

        hudDetailLabel.font = .systemFont(ofSize: 11.5)
        hudDetailLabel.textColor = NSColor(white: 0.72, alpha: 1.0)
        hudDetailLabel.lineBreakMode = .byTruncatingTail
        hudDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        hudBar.addArrangedSubview(hudIconBadge)
        hudBar.addArrangedSubview(hudTitleLabel)
        hudBar.addArrangedSubview(hudDetailLabel)
    }

    private func setupExpandedContainer() {
        expandedContainer.orientation = .vertical
        expandedContainer.alignment = .leading
        expandedContainer.spacing = 8
        expandedContainer.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        expandedContainer.translatesAutoresizingMaskIntoConstraints = false

        // Header row (24pt)
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 7
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        expandedClockLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        expandedClockLabel.textColor = .white
        expandedClockLabel.lineBreakMode = .byTruncatingTail
        expandedClockLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        expandedBatteryIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        expandedBatteryIcon.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
        expandedBatteryIcon.translatesAutoresizingMaskIntoConstraints = false

        expandedBatteryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        expandedBatteryLabel.textColor = NSColor(white: 0.70, alpha: 1.0)

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        pinButton.target = self
        pinButton.action = #selector(handlePinTapped(_:))

        let openAppBtn = IslandIconButton(
            symbolName: "slider.horizontal.3",
            accessibilityLabel: L10n.text("menu.openMaketools", "打开 MakeTools 主窗口"),
            target: self,
            action: #selector(handleOpenMainWindow(_:))
        )
        let passwordBookButton = IslandIconButton(
            symbolName: "key.fill",
            accessibilityLabel: L10n.text("island.passwordBook", "密码本"),
            target: self,
            action: #selector(handleOpenPasswordBook(_:))
        )
        let collapseBtn = IslandIconButton(
            symbolName: "chevron.up",
            accessibilityLabel: L10n.text("island.collapseDynamicIsland", "收起灵动岛"),
            target: self,
            action: #selector(handleCollapseTapped(_:))
        )

        headerRow.addArrangedSubview(expandedClockLabel)
        headerRow.addArrangedSubview(expandedBatteryIcon)
        headerRow.addArrangedSubview(expandedBatteryLabel)
        headerRow.addArrangedSubview(headerSpacer)
        headerRow.addArrangedSubview(pinButton)
        headerRow.addArrangedSubview(passwordBookButton)
        editLayoutButton.target = self
        editLayoutButton.action = #selector(openLayoutEditor(_:))
        headerRow.addArrangedSubview(editLayoutButton)
        headerRow.addArrangedSubview(openAppBtn)
        headerRow.addArrangedSubview(collapseBtn)

        // Adaptive Bento host
        bentoHost.orientation = .horizontal
        bentoHost.alignment = .top
        bentoHost.distribution = .fillEqually
        bentoHost.spacing = IslandExpandedLayout.spacing
        bentoHost.translatesAutoresizingMaskIntoConstraints = false

        systemCard = buildSystemCard()
        audioCard = buildAudioAndKeepAwakeCard()
        timerCard = buildTimerCard()
        calendarCard = buildCalendarCard()
        lanTransferCard = buildLANTransferCard()
        bookmarkCard = buildBookmarkCard()
        webBookmarks = (try? webBookmarkStore.load()) ?? []
        refreshBookmarkCard()
        shelfCard = buildShelfCard()
        // Footer row (22pt): Clipboard history
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 5
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        let historyButton = IslandChipButton(
            title: L10n.text("island.clipboard", "剪贴板 ▾"), horizontalPadding: 12, height: 20,
            target: self, action: #selector(handleShowClipboardHistory(_:))
        )
        historyButton.toolTip = L10n.text("island.showClipboardHistory", "显示剪贴板历史")
        historyButton.setAccessibilityLabel(L10n.text("island.showClipboardHistory", "显示剪贴板历史"))
        historyButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        clipboardIndexLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        clipboardIndexLabel.textColor = NSColor(white: 0.56, alpha: 1.0)
        clipboardIndexLabel.setContentHuggingPriority(.required, for: .horizontal)

        clipboardLabel.font = .systemFont(ofSize: 11)
        clipboardLabel.textColor = NSColor(white: 0.78, alpha: 1.0)
        clipboardLabel.lineBreakMode = .byTruncatingTail
        clipboardLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let prevClipBtn = IslandChipButton(title: "‹", fontSize: 11, horizontalPadding: 8, height: 19, target: self, action: #selector(handlePrevClipboard(_:)))
        let nextClipBtn = IslandChipButton(title: "›", fontSize: 11, horizontalPadding: 8, height: 19, target: self, action: #selector(handleNextClipboard(_:)))
        let copyClipBtn = IslandChipButton(title: L10n.text("island.copy", "复制"), fontSize: 10, horizontalPadding: 9, height: 19, target: self, action: #selector(handleCopyClipboard(_:)))
        let demoHudBtn = IslandChipButton(title: L10n.text("island.demo", "演示"), fontSize: 10, horizontalPadding: 9, height: 19, target: self, action: #selector(handleDemoHUD(_:)))

        footerRow.addArrangedSubview(historyButton)
        footerRow.addArrangedSubview(clipboardIndexLabel)
        footerRow.addArrangedSubview(clipboardLabel)
        footerRow.addArrangedSubview(footerSpacer)
        footerRow.addArrangedSubview(prevClipBtn)
        footerRow.addArrangedSubview(nextClipBtn)
        footerRow.addArrangedSubview(copyClipBtn)
        footerRow.addArrangedSubview(demoHudBtn)

        expandedContainer.addArrangedSubview(headerRow)
        expandedContainer.addArrangedSubview(bentoHost)
        expandedContainer.addArrangedSubview(footerRow)

        NSLayoutConstraint.activate([
            headerRow.widthAnchor.constraint(equalTo: expandedContainer.widthAnchor, constant: -32),
            headerRow.heightAnchor.constraint(equalToConstant: 24),
            bentoHost.widthAnchor.constraint(equalTo: expandedContainer.widthAnchor, constant: -32),
            footerRow.widthAnchor.constraint(equalTo: expandedContainer.widthAnchor, constant: -32),
            footerRow.heightAnchor.constraint(equalToConstant: 22)
        ])

        rebuildExpandedLayoutIfNeeded()
    }

    private func makeCardHeader(symbolName: String, title: String) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        icon.contentTintColor = IslandColors.accent
        icon.setAccessibilityElement(false)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = IslandColors.text
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        return row
    }

    private func buildSystemCard() -> IslandCardView {
        let card = IslandCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let headerTitle = makeCardHeader(symbolName: "cpu", title: L10n.text("island.performance", "性能"))
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        for (label, color, title) in [
            (downloadSpeedLabel, NSColor.systemTeal, L10n.text("island.downloadSpeed", "下行网速")),
            (uploadSpeedLabel, NSColor.systemBlue, L10n.text("island.uploadSpeed", "上行网速"))
        ] {
            label.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
            label.textColor = color
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.toolTip = title
            label.setAccessibilityLabel(title)
        }

        let headerRow = NSStackView(views: [headerTitle, headerSpacer, downloadSpeedLabel, uploadSpeedLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 4

        // CPU
        let cpuRow = NSStackView()
        cpuRow.orientation = .horizontal
        cpuRow.alignment = .centerY
        let cpuName = NSTextField(labelWithString: "CPU")
        cpuName.font = .systemFont(ofSize: 9.5)
        cpuName.textColor = NSColor(white: 0.78, alpha: 1.0)
        let cpuSpacer = NSView()
        cpuSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cpuValueLabel.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        cpuValueLabel.textColor = .white
        cpuRow.addArrangedSubview(cpuName)
        cpuRow.addArrangedSubview(cpuSpacer)
        cpuRow.addArrangedSubview(cpuValueLabel)
        cpuBar.fillColor = .systemTeal

        cpuGroup.orientation = .vertical
        cpuGroup.alignment = .leading
        cpuGroup.spacing = 2
        cpuGroup.addArrangedSubview(cpuRow)
        cpuGroup.addArrangedSubview(cpuBar)

        // Memory
        let memRow = NSStackView()
        memRow.orientation = .horizontal
        memRow.alignment = .centerY
        let memName = NSTextField(labelWithString: L10n.text("island.memory", "内存"))
        memName.font = .systemFont(ofSize: 9.5)
        memName.textColor = NSColor(white: 0.78, alpha: 1.0)
        let memSpacer = NSView()
        memSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        memValueLabel.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        memValueLabel.textColor = .white
        memRow.addArrangedSubview(memName)
        memRow.addArrangedSubview(memSpacer)
        memRow.addArrangedSubview(memValueLabel)
        memBar.fillColor = .systemBlue

        memGroup.orientation = .vertical
        memGroup.alignment = .leading
        memGroup.spacing = 2
        memGroup.addArrangedSubview(memRow)
        memGroup.addArrangedSubview(memBar)

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(cpuGroup)
        stack.addArrangedSubview(memGroup)

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),
            headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cpuGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cpuRow.widthAnchor.constraint(equalTo: cpuGroup.widthAnchor),
            cpuBar.widthAnchor.constraint(equalTo: cpuGroup.widthAnchor),
            memGroup.widthAnchor.constraint(equalTo: stack.widthAnchor),
            memRow.widthAnchor.constraint(equalTo: memGroup.widthAnchor),
            memBar.widthAnchor.constraint(equalTo: memGroup.widthAnchor)
        ])
        return card
    }

    private func buildAudioAndKeepAwakeCard() -> IslandCardView {
        let card = IslandCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = makeCardHeader(symbolName: "speaker.wave.2", title: L10n.text("island.audioAndKeepAwake", "音频与防休眠"))

        muteButton.target = self
        muteButton.action = #selector(handleMuteToggle(_:))

        volumeSlider.controlSize = .mini
        volumeSlider.isContinuous = true
        volumeSlider.target = self
        volumeSlider.action = #selector(handleVolumeSliderChanged(_:))
        volumeSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        volumeValueLabel.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        volumeValueLabel.textColor = .white
        volumeValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        audioSection.orientation = .horizontal
        audioSection.alignment = .centerY
        audioSection.spacing = 5
        audioSection.addArrangedSubview(muteButton)
        audioSection.addArrangedSubview(volumeSlider)
        audioSection.addArrangedSubview(volumeValueLabel)

        keepAwakeButton.target = self
        keepAwakeButton.action = #selector(handleKeepAwakeToggle(_:))

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(audioSection)
        stack.addArrangedSubview(keepAwakeButton)

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),
            audioSection.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return card
    }

    private func buildTimerCard() -> IslandCardView {
        let card = IslandCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let headerTitle = makeCardHeader(symbolName: "timer", title: L10n.text("island.focus.186", "专注"))
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let p5 = IslandChipButton(title: "5m", fontSize: 9, horizontalPadding: 6, height: 16, target: self, action: #selector(handlePreset5(_:)))
        let p15 = IslandChipButton(title: "15m", fontSize: 9, horizontalPadding: 6, height: 16, target: self, action: #selector(handlePreset15(_:)))
        let p25 = IslandChipButton(title: "25m", fontSize: 9, horizontalPadding: 6, height: 16, target: self, action: #selector(handlePreset25(_:)))

        let headerRow = NSStackView(views: [headerTitle, headerSpacer, p5, p15, p25])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 3

        timerCountdownLabel.font = .monospacedDigitSystemFont(ofSize: 19, weight: .bold)
        timerCountdownLabel.textColor = .white

        let timerSpacer = NSView()
        timerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        timerToggleButton.target = self
        timerToggleButton.action = #selector(handleTimerToggle(_:))
        timerToggleButton.normalBackground = NSColor.systemOrange.withAlphaComponent(0.88)

        let resetBtn = IslandIconButton(
            symbolName: "arrow.counterclockwise",
            accessibilityLabel: L10n.text("island.resetTimer", "重置计时器"),
            diameter: 22,
            pointSize: 9.5,
            target: self,
            action: #selector(handleTimerReset(_:))
        )

        let mainRow = NSStackView(views: [timerCountdownLabel, timerSpacer, timerToggleButton, resetBtn])
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 6

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(mainRow)

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),
            headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            mainRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return card
    }

    private func buildCalendarCard() -> IslandCardView {
        let card = IslandCardView()
        let spacer = NSView()
        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        let button = IslandChipButton(
            title: L10n.text("island.view", "查看"), fontSize: 10, horizontalPadding: 9, height: 16,
            target: self, action: #selector(handleOpenCalendar(_:))
        )
        button.toolTip = L10n.text("island.openCalendarAndCountdowns", "打开日历与日期倒计时")
        button.setAccessibilityLabel(L10n.text("island.openCalendarAndCountdowns", "打开日历与日期倒计时"))
        let header = NSStackView(views: [makeCardHeader(symbolName: "calendar", title: L10n.text("calendar.calendar", "日历")), calendarDateLabel, spacer, button])
        header.spacing = 5
        header.orientation = .horizontal
        header.alignment = .centerY

        calendarDateLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        calendarDateLabel.textColor = .white
        calendarEventLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        calendarEventLabel.textColor = .systemTeal
        calendarHolidayLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        calendarHolidayLabel.textColor = .systemYellow
        for label in [calendarDateLabel, calendarEventLabel, calendarHolidayLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let stack = NSStackView(views: [header, calendarEventLabel, calendarHolidayLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            calendarEventLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            calendarHolidayLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return card
    }

    private func buildLANTransferCard() -> IslandCardView {
        let card = IslandCardView()
        lanTransferToggle.target = self
        lanTransferToggle.action = #selector(handleToggleLANTransfer)
        lanTransferToggle.setAccessibilityLabel(L10n.text("island.toggleLocalNetworkFileReception", "开启或关闭局域网文件接收"))
        lanTransferQR.target = self
        lanTransferQR.action = #selector(showLANTransferQRCode)
        lanTransferCopy.target = self
        lanTransferCopy.action = #selector(copyLANTransferLink)
        for button in [lanTransferToggle, lanTransferQR, lanTransferCopy] {
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        let space = NSView()
        space.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        let header = NSStackView(views: [
            makeCardHeader(symbolName: "wifi", title: L10n.text("lanTransfer.title", "局域网传输")), space, lanTransferToggle
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 5

        lanTransferStatus.font = .systemFont(ofSize: 10.5, weight: .medium)
        lanTransferStatus.lineBreakMode = .byTruncatingTail
        lanTransferStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [lanTransferQR, lanTransferCopy])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 5

        let stack = NSStackView(views: [header, lanTransferStatus, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            lanTransferStatus.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return card
    }

    private func refreshLANTransferCard() {
        let state = lanTransfer.state
        lanTransferToggle.normalBackground = state.isEnabled ? IslandColors.accent.withAlphaComponent(0.26) : IslandColors.control
        lanTransferToggle.title = state.isEnabled ? L10n.text("island.off", "关闭") : L10n.text("island.enable", "开启")
        lanTransferQR.isEnabled = state.url != nil
        lanTransferCopy.isEnabled = state.url != nil
        lanTransferStatus.textColor = .lightGray
        switch state {
        case .off:
            lanTransferStatus.stringValue = L10n.text("island.off.296", "已关闭")
        case .starting:
            lanTransferStatus.stringValue = L10n.text("island.starting", "正在启动…")
        case .listening(let url):
            lanTransferStatus.stringValue = lanTransfer.lastReceivedName.map { L10n.text("island.received", "已收到  {arg1}", ["arg1": String(describing: $0)]) } ?? L10n.text("island.waitingForUploadsFromTheLocalNetwork", "等待同一网络中的设备上传")
            lanTransferStatus.textColor = .systemTeal
            if revealLANTransferLinkWhenReady {
                revealLANTransferLinkWhenReady = false
                showLANTransferLink(url)
            }
        case .failed(let message):
            lanTransferStatus.stringValue = message
            lanTransferStatus.textColor = .systemOrange
        }
        lanTransferStatus.toolTip = lanTransferStatus.stringValue
        if !state.isEnabled {
            revealLANTransferLinkWhenReady = false
            if lanTransferLinkWindow?.window?.isVisible == true { lanTransferLinkWindow?.close() }
        }
    }

    @objc private func handleToggleLANTransfer() {
        let enabled = !lanTransfer.state.isEnabled
        revealLANTransferLinkWhenReady = enabled
        lanTransfer.setEnabled(enabled)
    }

    @objc private func showLANTransferQRCode() {
        if let url = lanTransfer.state.url { showLANTransferLink(url) }
    }

    private func showLANTransferLink(_ url: URL) {
        if lanTransferLinkWindow == nil { lanTransferLinkWindow = LANTransferLinkWindowController() }
        lanTransferLinkWindow?.show(url: url, from: lanTransferQR)
    }

    @objc private func copyLANTransferLink() {
        if lanTransfer.copyLink() {
            ClipboardHelper.flashButton(lanTransferCopy, restoreTitle: L10n.text("lanTransfer.copyLink", "复制链接"))
        }
    }

    private func buildBookmarkCard() -> IslandCardView {
        let card = IslandCardView()
        let spacer = NSView()
        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        let manage = IslandChipButton(
            title: L10n.text("island.all", "全部"), fontSize: 10, horizontalPadding: 9, height: 16,
            target: self, action: #selector(handleManageBookmarks(_:))
        )
        bookmarkManageButton = manage
        let header = NSStackView(views: [makeCardHeader(symbolName: "bookmark", title: L10n.text("island.webBookmarks", "网络书签")), spacer, manage])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 5

        bookmarkEmptyLabel.font = .systemFont(ofSize: 10.5)
        bookmarkEmptyLabel.textColor = NSColor(white: 0.68, alpha: 1)
        bookmarkEmptyLabel.lineBreakMode = .byTruncatingTail
        bookmarkEmptyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bookmarkLinks = (0..<2).map { index in
            let link = IslandChipButton(
                title: "", fontSize: 10, horizontalPadding: 10, height: 16,
                target: self, action: #selector(handleOpenBookmark(_:))
            )
            link.tag = index
            link.alignment = .left
            link.cell?.lineBreakMode = .byTruncatingTail
            link.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return link
        }

        let stack = NSStackView(views: [header, bookmarkEmptyLabel] + bookmarkLinks)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bookmarkEmptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        for link in bookmarkLinks {
            link.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        return card
    }

    private func refreshBookmarkCard() {
        bookmarkEmptyLabel.isHidden = !webBookmarks.isEmpty
        for (index, link) in bookmarkLinks.enumerated() {
            let bookmark = webBookmarks.indices.contains(index) ? webBookmarks[index] : nil
            link.isHidden = bookmark == nil
            link.title = bookmark?.title ?? ""
            link.toolTip = bookmark?.url.absoluteString
            link.setAccessibilityLabel(bookmark.map { L10n.text("island.openBookmark", "打开书签 {arg1}", ["arg1": String(describing: $0.title)]) })
        }
        let manage = bookmarkManageButton
        manage?.title = webBookmarks.isEmpty ? L10n.text("island.add", "添加") : L10n.text("island.all", "全部")
        manage?.setAccessibilityLabel(webBookmarks.isEmpty ? L10n.text("island.addWebBookmark", "添加网络书签") : L10n.text("island.showAllWebBookmarks", "查看全部网络书签"))
    }

    private func buildShelfCard() -> IslandCardView {
        let card = IslandCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Header row
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: L10n.text("island.shelf", "暂存架"))
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        icon.contentTintColor = NSColor(white: 0.60, alpha: 1.0)

        shelfHeaderLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        shelfHeaderLabel.textColor = NSColor(white: 0.68, alpha: 1.0)

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let openBtn = IslandIconButton(symbolName: "arrow.up.right.square", accessibilityLabel: L10n.text("island.open", "打开"),
                                       diameter: 18, target: self, action: #selector(handleOpenShelfFile(_:)))
        let shareBtn = IslandIconButton(symbolName: "square.and.arrow.up", accessibilityLabel: L10n.text("island.share", "分享"),
                                        diameter: 18, target: self, action: #selector(handleShareShelfFiles(_:)))
        let removeBtn = IslandIconButton(symbolName: "minus", accessibilityLabel: L10n.text("island.remove.311", "移除"),
                                         diameter: 18, target: self, action: #selector(handleRemoveSelectedShelfFile(_:)))
        let clearBtn = IslandIconButton(symbolName: "trash", accessibilityLabel: L10n.text("island.clear", "清空"),
                                        diameter: 18, target: self, action: #selector(handleClearShelf(_:)))
        shelfActionButtons = [openBtn, shareBtn, removeBtn, clearBtn]
        shelfHeaderLabel.lineBreakMode = .byTruncatingTail
        shelfHeaderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shelfActionsGroup.orientation = .horizontal
        shelfActionsGroup.alignment = .centerY
        shelfActionsGroup.spacing = 3
        shelfActionsGroup.addArrangedSubview(openBtn)
        shelfActionsGroup.addArrangedSubview(shareBtn)
        shelfActionsGroup.addArrangedSubview(removeBtn)
        shelfActionsGroup.addArrangedSubview(clearBtn)

        let headerRow = NSStackView(views: [icon, shelfHeaderLabel, headerSpacer, shelfActionsGroup])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 4

        // 3x3 Grid
        shelfCells.removeAll()
        let gridColumn = NSStackView()
        gridColumn.orientation = .vertical
        gridColumn.alignment = .leading
        gridColumn.distribution = .fillEqually
        gridColumn.spacing = 5
        gridColumn.translatesAutoresizingMaskIntoConstraints = false

        var rowStacks: [NSStackView] = []
        for r in 0..<3 {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .top
            rowStack.distribution = .fillEqually
            rowStack.spacing = 5
            rowStack.translatesAutoresizingMaskIntoConstraints = false

            for c in 0..<3 {
                let idx = r * 3 + c
                let cell = ShelfGridCellView()
                cell.translatesAutoresizingMaskIntoConstraints = false
                cell.onSelect = { [weak self] in
                    self?.manager?.selectDroppedFile(at: idx)
                }
                cell.onOpen = { [weak self] in
                    self?.manager?.openDroppedFile(at: idx)
                }
                cell.onDragStarted = { [weak self] in
                    self?.manager?.isInternalDragInProgress = true
                }
                cell.onDragEnded = { [weak self] in
                    self?.manager?.isInternalDragInProgress = false
                }
                shelfCells.append(cell)
                rowStack.addArrangedSubview(cell)
                cell.heightAnchor.constraint(equalTo: rowStack.heightAnchor).isActive = true
            }

            gridColumn.addArrangedSubview(rowStack)
            rowStacks.append(rowStack)
        }

        shelfHintLabel.font = .systemFont(ofSize: 10)
        shelfHintLabel.textColor = NSColor(white: 0.54, alpha: 1.0)
        shelfHintLabel.alignment = .center
        shelfHintLabel.lineBreakMode = .byTruncatingTail
        shelfHintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        shelfHintLabel.heightAnchor.constraint(equalToConstant: 13).isActive = true

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(gridColumn)
        stack.addArrangedSubview(shelfHintLabel)

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            headerRow.heightAnchor.constraint(equalToConstant: 18),
            gridColumn.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shelfHintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        for rowStack in rowStacks {
            rowStack.widthAnchor.constraint(equalTo: gridColumn.widthAnchor).isActive = true
            rowStack.heightAnchor.constraint(equalTo: rowStacks[0].heightAnchor).isActive = true
        }
        return card
    }

    // MARK: - Dynamic Asymmetric Bento Adaptation

    private func rebuildExpandedLayoutIfNeeded() {
        guard let manager else { return }
        let layout = manager.expandedLayout
        let cards = manager.activeExpandedCards
        let hideFooter = !manager.isFeatureEnabled(.clipboardHistory)
        if footerRow.isHidden != hideFooter {
            footerRow.isHidden = hideFooter
            if hideFooter { dismissClipboardMenu() }
        }
        guard lastExpandedLayout != layout || lastExpandedCards != cards else { return }
        lastExpandedLayout = layout
        lastExpandedCards = cards

        NSLayoutConstraint.deactivate(bentoConstraints)
        bentoConstraints.removeAll()
        for stack in [bentoHost] + bentoStacks {
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }
        bentoStacks.removeAll()

        bentoHost.isHidden = cards.isEmpty
        guard !cards.isEmpty else { return }

        let hasShelf = cards.contains(.shelf)
        let compactCards = cards.filter { $0 != .shelf }
        let metrics = IslandExpandedLayout.self
        bentoHost.distribution = .fillEqually

        if layout.usesGrid(cardCount: cards.count, hasShelf: hasShelf) {
            bentoHost.orientation = .vertical
            bentoHost.alignment = .leading
            bentoHost.distribution = .fill
            for rowCards in layout.gridRows(for: cards) {
                let row = makeBentoStack(orientation: .horizontal, alignment: .top, spacing: metrics.spacing)
                bentoHost.addArrangedSubview(row)
                bentoConstraints.append(row.widthAnchor.constraint(equalTo: bentoHost.widthAnchor))
                for card in rowCards {
                    addCard(card, to: row, height: card == .shelf ? metrics.shelfHeight : metrics.cardHeight)
                }
                let height = rowCards.contains(.shelf) ? metrics.shelfHeight : metrics.cardHeight
                bentoConstraints.append(row.heightAnchor.constraint(equalToConstant: height))
            }
        } else {
            bentoHost.orientation = .horizontal
            bentoHost.alignment = .top
            if hasShelf && !compactCards.isEmpty {
                let column = makeBentoStack(orientation: .vertical, alignment: .leading, spacing: metrics.compactSpacing)
                let height = layout.bodySize(cardCount: cards.count, hasShelf: true).height
                for card in compactCards {
                    addCard(card, to: column)
                }
                bentoConstraints.append(column.heightAnchor.constraint(equalToConstant: height))
                if layout == .shelfRight { bentoHost.addArrangedSubview(column) }
                addCard(.shelf, to: bentoHost, height: height)
                if layout == .shelfLeft { bentoHost.addArrangedSubview(column) }
            } else {
                for card in cards {
                    addCard(card, to: bentoHost, height: card == .shelf ? metrics.shelfHeight : metrics.cardHeight)
                }
            }
        }
        NSLayoutConstraint.activate(bentoConstraints)
    }

    private func makeBentoStack(
        orientation: NSUserInterfaceLayoutOrientation, alignment: NSLayoutConstraint.Attribute, spacing: CGFloat
    ) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = orientation
        stack.alignment = alignment
        stack.distribution = .fillEqually
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        bentoStacks.append(stack)
        return stack
    }

    private func cardView(for card: IslandExpandedCard) -> IslandCardView {
        switch card {
        case .performance: return systemCard
        case .audio: return audioCard
        case .focus: return timerCard
        case .shelf: return shelfCard
        case .calendar: return calendarCard
        case .bookmarks: return bookmarkCard
        case .lanTransfer: return lanTransferCard
        }
    }

    private func addCard(_ card: IslandExpandedCard, to stack: NSStackView, height: CGFloat? = nil) {
        let view = cardView(for: card)
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        if stack.orientation == .vertical {
            bentoConstraints.append(view.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        if let height {
            bentoConstraints.append(view.heightAnchor.constraint(equalToConstant: height))
        }
    }

    // MARK: - Layout & Geometry

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let activePillRect = effectivePillRect()
        contentContainer.frame = activePillRect
        updateShelfFrame()
        updateTrackingAreas()
        updateShapeLayer(for: activePillRect, geometry: currentGeometry, animated: false)
        CATransaction.commit()
    }

    func applyMaterial(_ value: DynamicIslandMaterial) {
        usesGlass = value.usesBackdrop && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        palette = IslandMaterialPalette(material: value, translucent: usesGlass)
        glass.isHidden = !usesGlass
        for card in IslandExpandedCard.allCases { cardView(for: card).palette = palette }
        collapsedShelf.layer?.backgroundColor = (usesGlass ? palette.expanded.blended(withFraction: 0.62, of: IslandColors.shell) ?? IslandColors.shell : palette.expanded).cgColor
        collapsedShelf.layer?.borderColor = palette.stroke.cgColor
        updateShapeLayer(for: effectivePillRect(), geometry: currentGeometry, animated: false)
    }

    private func effectivePillRect() -> NSRect { centeredRect(currentGeometry.pillRect) }

    private func centeredRect(_ target: NSRect) -> NSRect {
        guard bounds.width > 1, bounds.height > 1 else { return target }
        let geometryWidth = max(currentGeometry.pillRect.width, currentGeometry.collapsedShelfRect?.width ?? 0)
        let inset = (currentGeometry.panelFrame.width - geometryWidth) / 2
        let width = min(target.width, max(1, bounds.width - 2 * inset))
        let topInset = currentGeometry.panelFrame.height - target.maxY
        let top = max(bounds.minY, bounds.maxY - topInset)
        let height = min(target.height, top - bounds.minY)
        return NSRect(x: bounds.midX - width / 2, y: top - height, width: width, height: height)
    }

    private func updateShelfFrame() {
        if let rect = currentGeometry.collapsedShelfRect, !collapsedShelfFiles.isEmpty, displayedState == .collapsed {
            let frame = centeredRect(rect)
            collapsedShelf.frame = frame
            collapsedShelf.isHidden = frame.height < rect.height - 1
        } else {
            collapsedShelf.isHidden = true
        }
    }

    private func updateCollapsedShelf(_ files: [URL]) {
        if collapsedShelfFiles != files {
            collapsedShelfFiles = files
            for tile in collapsedShelf.arrangedSubviews {
                collapsedShelf.removeArrangedSubview(tile)
                tile.removeFromSuperview()
            }
            for (index, file) in files.enumerated() {
                let tile = CollapsedShelfTile(frame: .zero)
                tile.configure(file)
                tile.onSelect = { [weak self] in self?.manager?.selectDroppedFile(at: index) }
                tile.onOpen = { [weak self] in self?.manager?.openDroppedFile(at: index) }
                tile.onDragStarted = { [weak self] in self?.manager?.isInternalDragInProgress = true }
                tile.onDragEnded = { [weak self] in self?.manager?.isInternalDragInProgress = false }
                collapsedShelf.addArrangedSubview(tile)
                tile.heightAnchor.constraint(equalToConstant: 28).isActive = true
            }
        }
        updateShelfFrame()
    }

    public func applyGeometry(_ geometry: IslandGeometry, animated: Bool) {
        currentGeometry = geometry
        hudTopConstraint?.constant = geometry.hudContentTopInset
        let hasNotchGap = geometry.notchReservedWidth > 0
        collapsedNotchGapWidthConstraint?.constant = geometry.notchReservedWidth
        collapsedNotchGapView.isHidden = !hasNotchGap
        collapsedEqualWingsConstraint?.isActive = hasNotchGap
        collapsedBar.spacing = hasNotchGap ? 0 : 6
        updateCollapsedBarContent()
        needsLayout = true
        updateTrackingAreas()

        if animated {
            updateShapeLayer(for: geometry.pillRect, geometry: geometry, animated: true)
        } else {
            pillShapeLayer.removeAnimation(forKey: "geometry")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentContainer.frame = geometry.pillRect
            updateShelfFrame()
            updateShapeLayer(for: geometry.pillRect, geometry: geometry, animated: false)
            CATransaction.commit()
        }
    }

    private func updateGlass(in rect: NSRect, geometry: IslandGeometry) {
        glass.frame = rect
        guard rect.width > 0, rect.height > 0 else { return }
        let shape = GlassShape(size: rect.size, cornerRadius: geometry.cornerRadius,
                               earRadius: geometry.earRadius, isTopAttached: geometry.isTopAttached)
        guard shape != glassShape else { return }
        glassShape = shape
        let path = Self.makeIslandPath(pillRect: NSRect(origin: .zero, size: shape.size),
                                       cornerRadius: shape.cornerRadius, earRadius: shape.earRadius,
                                       isTopAttached: shape.isTopAttached)
        glass.maskImage = NSImage(size: shape.size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(path)
            context.fillPath()
            return true
        }
    }

    private func updateShapeLayer(for rect: NSRect, geometry: IslandGeometry, animated: Bool) {
        let path = Self.makeIslandPath(
            pillRect: rect,
            cornerRadius: geometry.cornerRadius,
            earRadius: geometry.earRadius,
            isTopAttached: geometry.isTopAttached
        )
        let isExpanded = (manager?.state == .expanded)
        let shellColor = (isExpanded ? palette.expanded : palette.shell).cgColor
        if usesGlass { updateGlass(in: rect, geometry: geometry) }
        if !isDragHighlighted { pillShapeLayer.strokeColor = palette.stroke.cgColor }
        let targetShadowRadius: CGFloat = isExpanded ? 18 : 5
        let targetShadowOpacity: Float = isExpanded ? 0.43 : 0.27

        if animated {
            let presentation = pillShapeLayer.presentation() ?? pillShapeLayer
            let transitions: [(String, Any?, Any)] = [
                ("path", presentation.path, path),
                ("fillColor", presentation.fillColor, shellColor),
                ("shadowPath", presentation.shadowPath, path),
                ("shadowRadius", presentation.shadowRadius, targetShadowRadius),
                ("shadowOpacity", presentation.shadowOpacity, targetShadowOpacity)
            ]
            let group = CAAnimationGroup()
            group.animations = transitions.map { property, start, end in
                let animation = CABasicAnimation(keyPath: property)
                animation.fromValue = start
                animation.toValue = end
                animation.duration = 0.26
                return animation
            }
            group.duration = 0.26
            group.timingFunction = ToolAppearance.timing
            pillShapeLayer.add(group, forKey: "geometry")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillShapeLayer.path = path
        pillShapeLayer.fillColor = shellColor
        pillShapeLayer.shadowPath = path
        pillShapeLayer.shadowRadius = targetShadowRadius
        pillShapeLayer.shadowOpacity = targetShadowOpacity
        CATransaction.commit()
    }

    private static func makeIslandPath(
        pillRect: NSRect,
        cornerRadius: CGFloat,
        earRadius: CGFloat,
        isTopAttached: Bool
    ) -> CGPath {
        guard pillRect.width > 4, pillRect.height > 4 else {
            return CGPath(rect: pillRect, transform: nil)
        }

        let r = min(cornerRadius, min(pillRect.width / 2.0, pillRect.height / 2.0))
        let x0 = pillRect.minX
        let x1 = pillRect.maxX
        let y0 = pillRect.minY
        let y1 = pillRect.maxY
        let ear = min(earRadius, max(0, pillRect.height - r))
        let topInset = isTopAttached ? -ear : r
        let sideInset = isTopAttached ? ear : r

        // Keep the same segments in each display style so Core Animation can interpolate the paths.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0 + topInset, y: y1))
        path.addQuadCurve(to: CGPoint(x: x0, y: y1 - sideInset), control: CGPoint(x: x0, y: y1))
        path.addLine(to: CGPoint(x: x0, y: y0 + r))
        path.addQuadCurve(to: CGPoint(x: x0 + r, y: y0), control: CGPoint(x: x0, y: y0))
        path.addLine(to: CGPoint(x: x1 - r, y: y0))
        path.addQuadCurve(to: CGPoint(x: x1, y: y0 + r), control: CGPoint(x: x1, y: y0))
        path.addLine(to: CGPoint(x: x1, y: y1 - sideInset))
        path.addQuadCurve(to: CGPoint(x: x1 - topInset, y: y1), control: CGPoint(x: x1, y: y1))
        path.closeSubpath()
        return path
    }

    public func applyState(_ state: DynamicIslandState, animated: Bool = false) {
        rebuildExpandedLayoutIfNeeded()
        if state != .expanded {
            dismissClipboardMenu()
        }

        let activeView: NSView
        let previousState = displayedState
        displayedState = state
        switch state {
        case .collapsed:
            activeView = collapsedBar
        case .hud(let title, let detail, let symbolName):
            activeView = hudContainer
            hudIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            hudTitleLabel.stringValue = title
            hudDetailLabel.stringValue = detail
        case .expanded:
            activeView = expandedContainer
        }

        if contentContainer.subviews.count != 1 || contentContainer.subviews.first !== activeView {
            for sub in contentContainer.subviews {
                sub.removeFromSuperview()
            }
            contentContainer.addSubview(activeView)
            NSLayoutConstraint.activate([
                activeView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                activeView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                activeView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                activeView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor)
            ])
        }
        if animated && previousState != state {
            ToolAppearance.reveal(activeView, from: 0.30, duration: 0.24)
        } else if !animated {
            activeView.layer?.removeAnimation(forKey: "reveal")
        }
        refreshTelemetry()
    }

    public func setExternalDropHighlight(_ active: Bool) {
        isDragHighlighted = active
        shelfCard.isDropHighlighted = active
        pillShapeLayer.lineWidth = active ? 1.5 : 0.75
        pillShapeLayer.strokeColor = active ? IslandColors.accent.cgColor : palette.stroke.cgColor
    }

    private func updateCollapsedBarContent(now: Date = Date()) {
        guard let manager else { return }

        if manager.isFeatureEnabled(.focusTimer), manager.focusTimer.isRunning {
            collapsedDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        } else if manager.isFeatureEnabled(.keepAwake), manager.isKeepAwakeActive {
            collapsedDot.layer?.backgroundColor = NSColor.systemYellow.cgColor
        } else if manager.isFeatureEnabled(.fileShelf), !manager.droppedFiles.isEmpty {
            collapsedDot.layer?.backgroundColor = NSColor.systemTeal.cgColor
        } else {
            collapsedDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        }

        let hasNotchGap = currentGeometry.notchReservedWidth > 0
        let leftText = manager.collapsedStatusText
        let metric = manager.currentCollapsedMetric
        let rightText = metric.map { manager.latestSnapshot.formatCollapsedMetric($0, now: now) }
        if metric != displayedCollapsedMetric {
            if displayedCollapsedMetric != nil, metric != nil, manager.state == .collapsed,
               collapsedMetricLabel.window?.isVisible == true {
                ToolAppearance.reveal(collapsedMetricLabel, from: 0.35, duration: 0.18)
            }
            displayedCollapsedMetric = metric
        }

        if let leftText {
            collapsedTitleLabel.stringValue = leftText
            collapsedTitleLabel.isHidden = false
        } else {
            collapsedTitleLabel.stringValue = ""
            collapsedTitleLabel.isHidden = true
        }

        if let rightText {
            collapsedMetricLabel.stringValue = rightText
            collapsedMetricLabel.isHidden = false
        } else {
            collapsedMetricLabel.stringValue = ""
            collapsedMetricLabel.isHidden = true
        }

        if hasNotchGap {
            rightWingContainer.isHidden = false
            collapsedLeftSpacer.isHidden = false
            collapsedRightSpacer.isHidden = false
        } else {
            rightWingContainer.isHidden = (rightText == nil)
            collapsedLeftSpacer.isHidden = true
            collapsedRightSpacer.isHidden = (leftText == nil || rightText == nil)
        }
    }

    public func refreshTelemetry() {
        guard let manager else { return }
        rebuildExpandedLayoutIfNeeded()

        let snap = manager.latestSnapshot
        let now = Date()
        updateCollapsedBarContent(now: now)
        updateCalendarCard(events: manager.calendarEvents, now: now)

        // Expanded header
        expandedClockLabel.stringValue = manager.expandedNotice?.title ?? fullTimeFormatter.string(from: now)
        expandedClockLabel.toolTip = manager.expandedNotice?.detail
        if let battery = snap.batteryPercent {
            let symbol = snap.isCharging ? "battery.100.bolt" : (battery > 60 ? "battery.75" : (battery > 25 ? "battery.50" : "battery.25"))
            expandedBatteryIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.text("island.battery", "电量"))
            expandedBatteryIcon.contentTintColor = snap.isCharging ? .systemGreen : NSColor(white: 0.70, alpha: 1.0)
            expandedBatteryLabel.stringValue = "\(battery)%"
        } else {
            expandedBatteryIcon.image = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: L10n.text("island.externalPower", "外接电源"))
            expandedBatteryIcon.contentTintColor = NSColor(white: 0.70, alpha: 1.0)
            expandedBatteryLabel.stringValue = "AC"
        }

        pinButton.setSymbol(manager.isPinned ? "pin.fill" : "pin")
        pinButton.normalBackground = manager.isPinned
            ? NSColor.controlAccentColor.withAlphaComponent(0.85)
            : NSColor(white: 1.0, alpha: 0.11)

        // System & Network card
        let showSys = manager.isFeatureEnabled(.systemMonitor)
        cpuGroup.isHidden = !showSys
        memGroup.isHidden = !showSys
        downloadSpeedLabel.isHidden = !manager.isFeatureEnabled(.downloadSpeed)
        uploadSpeedLabel.isHidden = !manager.isFeatureEnabled(.uploadSpeed)

        cpuValueLabel.stringValue = "\(snap.cpuPercentInt)%"
        cpuBar.progress = snap.cpuUsage
        if snap.cpuUsage >= 0.80 {
            cpuBar.fillColor = .systemRed
        } else if snap.cpuUsage >= 0.50 {
            cpuBar.fillColor = .systemOrange
        } else {
            cpuBar.fillColor = .systemTeal
        }

        memValueLabel.stringValue = "\(snap.memoryPercentInt)%"
        memBar.progress = snap.memoryUsage
        downloadSpeedLabel.stringValue = "↓ \(SystemSnapshot.formatSpeed(snap.downloadBytesPerSec))"
        uploadSpeedLabel.stringValue = "↑ \(SystemSnapshot.formatSpeed(snap.uploadBytesPerSec))"

        // Audio & Keep-Awake card
        let showAudio = manager.isFeatureEnabled(.audioControl)
        let showAwake = manager.isFeatureEnabled(.keepAwake)
        audioSection.isHidden = !showAudio
        keepAwakeButton.isHidden = !showAwake

        if let vol = snap.volume {
            volumeSlider.isEnabled = true
            volumeSlider.doubleValue = Double(vol)
            let pct = Int((vol * 100).rounded())
            volumeValueLabel.stringValue = snap.isMuted ? L10n.text("island.muted.198", "静音") : "\(pct)%"
            muteButton.setSymbol(snap.isMuted ? "speaker.slash.fill" : (pct < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"), pointSize: 9)
        } else {
            volumeSlider.isEnabled = false
            volumeSlider.doubleValue = 0
            volumeValueLabel.stringValue = "N/A"
            muteButton.setSymbol("speaker.slash", pointSize: 9)
        }

        keepAwakeButton.title = manager.isKeepAwakeActive ? L10n.text("island.keepAwakeOn.316", "☕ 防休眠: 开") : L10n.text("island.keepAwakeOff.263", "☕ 防休眠: 关")
        keepAwakeButton.normalBackground = manager.isKeepAwakeActive
            ? NSColor.systemOrange.withAlphaComponent(0.85)
            : NSColor(white: 1.0, alpha: 0.10)

        // Focus timer
        timerCountdownLabel.stringValue = manager.focusTimer.formattedRemaining
        timerToggleButton.setSymbol(manager.focusTimer.isRunning ? "pause.fill" : "play.fill", pointSize: 9.5)

        // 3x3 File shelf
        let files = manager.droppedFiles
        updateCollapsedShelf(manager.isFeatureEnabled(.fileShelf) ? files : [])
        shelfHeaderLabel.stringValue = L10n.text("island.shelf.318", "暂存架 ({arg1}/{arg2})", ["arg1": String(describing: files.count), "arg2": String(describing: DynamicIslandManager.maxShelfFiles)])
        for button in shelfActionButtons { button.isEnabled = !files.isEmpty }
        shelfCard.isDropHighlighted = isDragHighlighted || manager.isExternalFileDragActive

        for idx in 0..<shelfCells.count {
            let url = idx < files.count ? files[idx] : nil
            let isSelected = (url != nil) && (idx == manager.selectedFileIndex)
            shelfCells[idx].configure(with: url, isSelected: isSelected)
        }

        // Clipboard history footer
        if manager.clipboardEntries.isEmpty {
            clipboardIndexLabel.stringValue = "0/0"
            clipboardLabel.stringValue = L10n.text("island.noHistory", "暂无历史")
        } else {
            clipboardIndexLabel.stringValue = "\(manager.clipboardHistoryIndex + 1)/\(manager.clipboardEntries.count)"
            clipboardLabel.stringValue = manager.currentClipboardItem
        }
    }

    // MARK: - Mouse Hover & Click

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        let rect = currentGeometry.interactionRect(for: effectivePillRect())
        if let trackingArea {
            guard trackingArea.rect != rect else { return }
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    fileprivate var blocksAutomaticCollapse: Bool {
        clipboardMenu != nil || containsPointer
    }

    fileprivate var containsPointer: Bool {
        guard let window, window.isVisible else { return false }
        let mouseInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = convert(mouseInWindow, from: nil)
        let pill = effectivePillRect()
        if displayedState == .collapsed, !currentGeometry.isTopAttached {
            return makeCapsule(in: pill).contains(point)
        }
        return currentGeometry.interactionRect(for: pill).contains(point)
    }

    private func makeCapsule(in rect: NSRect) -> CGPath {
        let radius = min(rect.width, rect.height) / 2
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    public override func mouseEntered(with event: NSEvent) { updateHoverExpansion() }
    public override func mouseMoved(with event: NSEvent) { updateHoverExpansion() }

    private func updateHoverExpansion() {
        guard containsPointer else { cancelPendingHoverExpansion(); return }
        hoverOutWorkItem?.cancel()
        hoverOutWorkItem = nil
        guard hoverInWorkItem == nil, let manager, manager.isEnabled, manager.hoverToExpand,
              manager.state != .expanded, NSEvent.pressedMouseButtons == 0 else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hoverInWorkItem = nil
            guard let manager = self.manager, manager.isEnabled, manager.hoverToExpand,
                  manager.state != .expanded, NSEvent.pressedMouseButtons == 0,
                  containsPointer else { return }
            manager.expand()
        }
        hoverInWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + manager.hoverDelay, execute: item)
    }

    fileprivate func cancelPendingHoverExpansion() {
        hoverInWorkItem?.cancel()
        hoverInWorkItem = nil
    }

    public override func mouseExited(with event: NSEvent) {
        cancelPendingHoverExpansion()
        scheduleHoverCollapse()
    }

    private func scheduleHoverCollapse() {
        guard clipboardMenu == nil,
              let manager, manager.state == .expanded, !manager.isPinned,
              !manager.isExternalFileDragActive, !manager.isInternalDragInProgress else {
            return
        }
        hoverOutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hoverOutWorkItem = nil
            self.manager?.collapse(force: false)
        }
        hoverOutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard currentGeometry.interactionRect(for: effectivePillRect()).contains(point) else {
            return
        }
        if let manager, manager.state != .expanded {
            manager.expand()
            return
        }
        super.mouseDown(with: event)
    }

    @objc private func openLayoutEditor(_ sender: NSButton) {
        manager?.openLayoutEditor(from: sender)
    }

    // MARK: - Drag & Drop

    private func canReceiveFiles(from sender: NSDraggingInfo) -> Bool {
        guard manager?.isFeatureEnabled(.fileShelf) == true,
              !(sender.draggingSource is ShelfFileDragView),
              sender.draggingSourceOperationMask.contains(.copy) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        return currentGeometry.interactionRect(for: effectivePillRect()).contains(point)
            || (!collapsedShelf.isHidden && collapsedShelf.frame.contains(point))
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = canReceiveFiles(from: sender) && sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        )
        if isDragHighlighted != accepted { setExternalDropHighlight(accepted) }
        return accepted ? .copy : []
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) {
        setExternalDropHighlight(false)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setExternalDropHighlight(false) }
        guard canReceiveFiles(from: sender), let manager else { return false }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return false }
        manager.addDroppedFiles(urls)
        return true
    }

    private func updateCalendarCard(events: [CalendarCountdownEvent], now: Date) {
        let calendar = CalendarCountdown.localCalendar
        calendarCountdown?.refresh(now: now, calendar: calendar)
        guard manager?.activeExpandedCards.contains(.calendar) == true else { return }
        let today = CountdownDay(date: now, calendar: calendar)
        let holidays = HolidayCalendar.shared
        holidays.refresh(around: today.year, now: now)
        let revision = holidays.revision
        guard calendarDisplayDay != today || displayedCalendarEvents != events || calendarHolidayRevision != revision else { return }
        calendarDisplayDay = today
        displayedCalendarEvents = events
        calendarHolidayRevision = revision
        calendarDateLabel.stringValue = now.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)
                .month().day().weekday(.abbreviated).locale(L10n.locale)
        )
        if let nextHoliday = HolidayCountdown.upcoming(in: Array(holidays.daysByDate.values), now: now, calendar: calendar).first {
            calendarHolidayLabel.stringValue = "\(nextHoliday.holiday.name) · \(CalendarCountdown.status(for: nextHoliday.days))"
            calendarHolidayLabel.toolTip = calendarHolidayLabel.stringValue
        } else {
            calendarHolidayLabel.stringValue = L10n.text("calendar.noUpcomingHolidaysSynced", "暂无已同步的近期节假日")
            calendarHolidayLabel.toolTip = nil
        }

        if let next = CalendarCountdown.orderedEvents(events, now: now, calendar: calendar).first {
            calendarEventLabel.stringValue = "\(next.event.title) · \(CalendarCountdown.status(for: next.days))"
            calendarEventLabel.toolTip = calendarEventLabel.stringValue
        } else {
            calendarEventLabel.stringValue = L10n.text("island.selectADateOrAddAnEvent", "选择日期或添加事件")
            calendarEventLabel.toolTip = nil
        }
    }

    // MARK: - Button Actions

    @objc private func handleManageBookmarks(_ sender: NSButton) {
        webBookmarksWindow.show(from: sender)
        presentedBookmarks = webBookmarksWindow.window
    }

    @objc private func handleOpenBookmark(_ sender: NSButton) {
        guard webBookmarks.indices.contains(sender.tag) else { return }
        if !webBookmarksWindow.openBookmark(webBookmarks[sender.tag]) {
            manager?.showHUD(title: L10n.text("island.cannotOpenBookmark", "无法打开书签"), detail: webBookmarks[sender.tag].title, symbolName: "bookmark")
        }
    }

    @objc private func handleOpenCalendar(_ sender: NSButton) {
        guard let manager else { return }
        if calendarCountdown == nil {
            calendarCountdown = CalendarCountdownWindowController(manager: manager)
        }
        calendarCountdown?.show(from: sender)
    }

    @objc private func handleOpenPasswordBook(_ sender: NSButton) {
        passwordBook.show(from: sender)
        presentedPasswordBook = passwordBook.window
    }
    @objc private func handlePinTapped(_ sender: Any?) { manager?.togglePin() }
    @objc private func handleOpenMainWindow(_ sender: Any?) { manager?.openMainWindow() }
    @objc private func handleCollapseTapped(_ sender: Any?) { manager?.collapse(force: true) }
    @objc private func handleMuteToggle(_ sender: Any?) { manager?.toggleMute() }
    @objc private func handleVolumeSliderChanged(_ sender: NSSlider) { manager?.setVolume(Float(sender.doubleValue)) }
    @objc private func handleKeepAwakeToggle(_ sender: Any?) { manager?.toggleKeepAwake() }
    @objc private func handleTimerToggle(_ sender: Any?) { manager?.toggleFocusTimer() }
    @objc private func handleTimerReset(_ sender: Any?) { manager?.resetFocusTimer() }
    @objc private func handlePreset5(_ sender: Any?) { manager?.setFocusDuration(minutes: 5) }
    @objc private func handlePreset15(_ sender: Any?) { manager?.setFocusDuration(minutes: 15) }
    @objc private func handlePreset25(_ sender: Any?) { manager?.setFocusDuration(minutes: 25) }
    @objc private func handleOpenShelfFile(_ sender: Any?) { manager?.openSelectedDroppedFile() }
    @objc private func handleShareShelfFiles(_ sender: NSView) { manager?.shareDroppedFiles(from: sender) }
    @objc private func handleRemoveSelectedShelfFile(_ sender: Any?) { manager?.removeSelectedDroppedFile() }
    @objc private func handleClearShelf(_ sender: Any?) { manager?.clearDroppedFiles() }
    fileprivate func dismissClipboardMenu() {
        clipboardMenu?.cancelTracking()
    }

    @objc private func handleShowClipboardHistory(_ sender: NSButton) {
        guard let manager, sender.window != nil,
              manager.isFeatureEnabled(.clipboardHistory), clipboardMenu == nil else { return }

        let menu = NSMenu(title: L10n.text("island.clipboardHistory", "剪贴板历史"))
        menu.autoenablesItems = false
        menu.minimumWidth = 220

        if manager.clipboardEntries.isEmpty {
            let item = NSMenuItem(title: L10n.text("island.noClipboardHistory", "暂无剪贴板历史"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for (index, entry) in manager.clipboardEntries.enumerated() {
                let item = NSMenuItem(
                    title: entry.preview,
                    action: #selector(handleCopyHistoryEntry(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.id
                item.state = index == manager.clipboardHistoryIndex ? .on : .off
                menu.addItem(item)
            }
        }

        hoverOutWorkItem?.cancel()
        hoverOutWorkItem = nil
        clipboardMenu = menu
        let lowerEdge = sender.isFlipped ? sender.bounds.maxY : sender.bounds.minY
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: lowerEdge), in: sender)
        clipboardMenu = nil

        if !containsPointer { scheduleHoverCollapse() }
    }

    @objc private func handleCopyHistoryEntry(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        manager?.copyClipboardItem(id: id)
    }

    @objc private func handlePrevClipboard(_ sender: Any?) { manager?.selectPreviousClipboard() }
    @objc private func handleNextClipboard(_ sender: Any?) { manager?.selectNextClipboard() }
    @objc private func handleCopyClipboard(_ sender: Any?) {
        guard let manager, !manager.clipboardEntries.isEmpty else { return }
        manager.copyCurrentClipboardItem()
        manager.showHUD(title: L10n.text("island.copiedFromHistory", "已复制历史记录"), detail: manager.currentClipboardItem, symbolName: "doc.on.clipboard.fill", duration: 1.8)
    }
    @objc private func handleDemoHUD(_ sender: Any?) {
        manager?.showHUD(title: L10n.text("island.islandAlert", "灵动提示"), detail: L10n.text("island.maketoolsLiveStatusIsReady", "MakeTools 实时状态已就绪"), symbolName: "sparkles", duration: 2.2)
    }
}

/// Manages the floating `DynamicIslandPanel` window and animates state/geometry transitions.
public final class DynamicIslandWindowController {
    private weak var manager: DynamicIslandManager?
    private let panel: DynamicIslandPanel
    private let contentView: DynamicIslandContentView

    public var currentPanelFrame: NSRect { panel.frame }

    var hasOpenEditor: Bool { contentView.hasOpenEditor }

    var blocksAutomaticCollapse: Bool { contentView.blocksAutomaticCollapse }
    var isPointerOverPill: Bool { contentView.containsPointer }

    public var currentCollapsedPillWidth: CGFloat {
        contentView.currentGeometry.pillSize.width
    }

    public init(manager: DynamicIslandManager) {
        self.manager = manager
        self.contentView = DynamicIslandContentView(manager: manager)

        let initialFrame = Self.computeCurrentGeometry(for: manager, contentView: contentView)?.panelFrame
            ?? NSRect(x: 400, y: 800, width: 256, height: 36)

        let panel = DynamicIslandPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 120, height: 24)
        panel.contentMinSize = NSSize(width: 120, height: 24)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = contentView
        panel.registerForDraggedTypes([.fileURL])
        self.panel = panel
    }

    public func showIsland() {
        syncState(animated: false)
        panel.orderFrontRegardless()
    }

    public func ensureVisible() {
        panel.orderFrontRegardless()
    }

    public func hideIsland() {
        cancelPendingHoverExpansion()
        contentView.dismissClipboardMenu()
        panel.orderOut(nil)
    }

    func cancelPendingHoverExpansion() {
        contentView.cancelPendingHoverExpansion()
    }

    public func refreshContents() {
        contentView.refreshTelemetry()
        if let manager, manager.state == .collapsed,
           let newGeom = Self.computeCurrentGeometry(for: manager, contentView: contentView),
           (abs(contentView.currentGeometry.pillSize.width - newGeom.pillSize.width) >= 6
            || contentView.currentGeometry.collapsedShelfRect?.size != newGeom.collapsedShelfRect?.size) {
            syncState(animated: true)
        }
    }

    public func setExternalDropHighlight(_ active: Bool) {
        contentView.setExternalDropHighlight(active)
    }

    func applyMaterial(_ material: DynamicIslandMaterial) {
        contentView.applyMaterial(material)
    }

    public func syncState(animated: Bool) {
        guard let manager else { return }
        let shouldAnimate = animated && ToolAppearance.allowsMotion && panel.isVisible
        contentView.applyState(manager.state, animated: shouldAnimate)

        guard let geometry = Self.computeCurrentGeometry(for: manager, contentView: contentView) else {
            return
        }
        let geometryChanged = contentView.currentGeometry != geometry || panel.frame != geometry.panelFrame
        guard geometryChanged || !shouldAnimate else { return }
        contentView.applyGeometry(geometry, animated: shouldAnimate)

        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = ToolAppearance.timing
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(geometry.panelFrame, display: true)
            }
        } else {
            panel.setFrame(geometry.panelFrame, display: true)
        }
    }

    private static func computeCurrentGeometry(
        for manager: DynamicIslandManager,
        contentView: DynamicIslandContentView
    ) -> IslandGeometry? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }
        let detectedNotch = IslandGeometry.detectNotchWidth(for: screen)
        let rawNotch = (manager.style != .floatingPill)
            ? IslandGeometry.effectiveNotchWidth(safeAreaTop: screen.safeAreaInsets.top, detectedNotchWidth: detectedNotch)
            : 0
        let notchReserved: CGFloat = (manager.state == .collapsed && rawNotch > 0) ? (rawNotch + 12) : 0
        let desiredCollapsedWidth: CGFloat = manager.collapsedCustomWidth > 0
            ? manager.collapsedCustomWidth
            : contentView.preferredCollapsedPillWidth(notchReservedWidth: notchReserved)
        return IslandGeometry.compute(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            notchWidth: detectedNotch,
            style: manager.style,
            state: manager.state,
            expandedCardCount: manager.activeExpandedCardCount,
            hasFileShelf: manager.isFileShelfVisible,
            showFooter: manager.isFeatureEnabled(.clipboardHistory),
            collapsedDesiredWidth: desiredCollapsedWidth,
            expandedLayout: manager.expandedLayout,
            floatingTopInset: screen.frame.maxY - screen.visibleFrame.maxY,
            collapsedFileCount: manager.isFeatureEnabled(.fileShelf) ? manager.droppedFiles.count : 0
        )
    }
}
