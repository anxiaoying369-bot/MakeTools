import AppKit
import QuartzCore

enum ToolAppearance {
    static let canvas = adaptive(light: 0xf0f3f9, dark: 0x141b2a)
    static let rail = adaptive(light: 0xe7edf8, dark: 0x101829)
    static let surface = adaptive(light: 0xffffff, dark: 0x1b263b)
    static let line = adaptive(light: 0xd9e2f1, dark: 0x31425c)
    static let accent = adaptive(light: 0x2653c7, dark: 0xa1b7ff)
    static let tint = adaptive(light: 0xe1eaff, dark: 0x263a66)

    private static func adaptive(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let color = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((color >> 16) & 255) / 255,
                           green: CGFloat((color >> 8) & 255) / 255,
                           blue: CGFloat(color & 255) / 255, alpha: 1)
        }
    }

    static func section(_ content: NSView, fill: NSColor = surface, inset: CGFloat = 16) -> NSView {
        let card = ToolSurfaceView(fill: fill)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset)
        ])
        return card
    }

    static var allowsMotion: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static let timing = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)

    static func reveal(_ view: NSView, from opacity: Float = 0.45, duration: CFTimeInterval = 0.22) {
        guard allowsMotion else { return }
        view.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = opacity
        animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = timing
        view.layer?.add(animation, forKey: "reveal")
    }

    static func icon(_ name: String, size: CGFloat, tint: NSColor = .controlAccentColor) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        view.symbolConfiguration = .init(pointSize: size, weight: .semibold)
        view.contentTintColor = tint
        view.setAccessibilityElement(false)
        return view
    }

    static func tile(_ name: String, side: CGFloat, size: CGFloat) -> NSView {
        let tile = ToolSurfaceView(fill: tint, radius: side * 0.28, border: nil)
        let iconView = icon(name, size: size, tint: accent)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(iconView)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: side),
            tile.heightAnchor.constraint(equalToConstant: side),
            iconView.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: tile.centerYAnchor)
        ])
        return tile
    }

    static func configure(_ button: NSButton, symbol: String) {
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        button.imagePosition = .imageLeading
    }

    static func header(title: String, subtitle: String, symbol: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 29, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.isSelectable = true

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.isSelectable = true
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        subtitleLabel.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true

        let marker = ToolSurfaceView(fill: accent, radius: 2, border: nil)
        marker.widthAnchor.constraint(equalToConstant: 3).isActive = true
        marker.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let glyph = tile(symbol, side: 51, size: 23)
        let header = NSStackView(views: [marker, labels, glyph])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        labels.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        glyph.setContentCompressionResistancePriority(.required, for: .horizontal)
        return section(header, inset: 18)
    }

    static func documentToolbar(
        filename: NSTextField,
        context: NSTextField,
        buttons: [NSButton],
        insets: NSEdgeInsets
    ) -> NSView {
        filename.font = .systemFont(ofSize: 14, weight: .semibold)
        context.font = .systemFont(ofSize: 11)
        context.textColor = .secondaryLabelColor

        for label in [filename, context] {
            label.lineBreakMode = .byTruncatingMiddle
            label.isSelectable = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let titles = NSStackView(views: [filename, context])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        titles.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        for label in [filename, context] {
            label.widthAnchor.constraint(equalTo: titles.widthAnchor).isActive = true
        }
        let heading = NSStackView(views: [tile("doc.richtext", side: 34, size: 16), titles])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 11

        let actions = NSStackView(views: buttons)
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 7

        let stack = NSStackView(views: [heading, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let toolbar = ToolSurfaceView(fill: surface, radius: 0, border: nil)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: insets.left),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -insets.right),
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: insets.top),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -insets.bottom),
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actions.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor)
        ])
        return toolbar
    }

    static func configureCopy(_ button: NSButton, symbol: String) {
        configure(button, symbol: symbol)
        let title = button.title
        let originalWidth = button.intrinsicContentSize.width
        button.title = ClipboardHelper.copiedTitle
        let copiedWidth = button.intrinsicContentSize.width
        button.title = title
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: max(originalWidth, copiedWidth)).isActive = true
    }

    static func sectionTitle(_ title: String, symbol: String) -> NSView {
        let image = tile(symbol, side: 26, size: 12)
        let label = NSTextField(wrappingLabelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}

final class ToolSurfaceView: NSView {
    private let fill: NSColor
    private let radius: CGFloat
    private let border: NSColor?

    init(fill: NSColor = ToolAppearance.surface, radius: CGFloat = 16, border: NSColor? = ToolAppearance.line) {
        self.fill = fill
        self.radius = radius
        self.border = border
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = radius
        layer?.borderWidth = border == nil ? 0 : 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor
            layer?.borderColor = border?.cgColor
        }
    }
}
