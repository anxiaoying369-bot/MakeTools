import AppKit
import QuartzCore

enum ToolAppearance {
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
        let tile = ToolSurfaceView(
            fill: NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return .controlAccentColor.withAlphaComponent(dark ? 0.20 : 0.12)
            },
            radius: side * 0.26,
            border: nil
        )
        let iconView = icon(name, size: size)
        tile.translatesAutoresizingMaskIntoConstraints = false
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
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        button.imagePosition = .imageLeading
    }

    static func header(title: String, subtitle: String, symbol: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
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

        let header = NSStackView(views: [tile(symbol, side: 46, size: 21), labels])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        return header
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

        let iconTile = tile("doc.richtext", side: 32, size: 15)
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        for subview in [iconTile, filename, context] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(subview)
        }
        var trailingAnchor = toolbar.trailingAnchor
        var spacing = insets.right
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            toolbar.addSubview(button)
        }
        for button in buttons.reversed() {
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -spacing),
                button.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor)
            ])
            trailingAnchor = button.leadingAnchor
            spacing = 9
        }

        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: insets.left),
            iconTile.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: insets.top),
            iconTile.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -insets.bottom),

            filename.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 9),
            filename.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            filename.bottomAnchor.constraint(equalTo: iconTile.centerYAnchor, constant: 1),

            context.leadingAnchor.constraint(equalTo: filename.leadingAnchor),
            context.trailingAnchor.constraint(equalTo: filename.trailingAnchor),
            context.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 2)
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
        let image = icon(symbol, size: 14)
        image.widthAnchor.constraint(equalToConstant: 19).isActive = true
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

    init(fill: NSColor = .controlBackgroundColor, radius: CGFloat = 14, border: NSColor? = .separatorColor) {
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
