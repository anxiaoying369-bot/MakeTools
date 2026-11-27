import AppKit

public final class ExtensionsOverviewTool: ToolModule {
    public let id = "extensions-overview"
    public let title = L10n.text("extensions.systemExtensions", "系统扩展")
    public let subtitle = L10n.text("extensions.quickLookAndExtensionGuide", "Quick Look 与扩展指南")
    public let symbolName = "puzzlepiece.extension"

    public init() {}

    public func makeViewController() -> NSViewController {
        ExtensionsOverviewViewController()
    }
}

private final class FlippedOverviewContainer: NSView {
    override var isFlipped: Bool { true }
}

public final class ExtensionsOverviewViewController: NSViewController {

    public override var nibName: NSNib.Name? { nil }

    public override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let container = FlippedOverviewContainer()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 32, bottom: 36, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = ToolAppearance.header(
            title: L10n.text("extensions.systemExtensions", "系统扩展"),
            subtitle: L10n.text("extensions.previewMarkdownInFinderOrLearnTo", "在访达中预览 Markdown，或了解如何为 MakeTools 添加新工具。"),
            symbol: "puzzlepiece.extension"
        )

        let extCard = makeCard(
            title: L10n.text("extensions.markdownQuickLook", "Markdown 快速预览"),
            symbol: "doc.richtext",
            badge: "com.make.MakeTools.MarkdownQuickLook",
            body: L10n.text("extensions.fileTypesMdMarkdownMdownMkdMdx", "• 支持类型：.md / .markdown / .mdown / .mkd / .mdx（net.daringfireball.markdown）\n• 预览模式：AppKit 原生渲染，随系统切换浅色与深色外观\n• 复制能力：代码块右上角一键复制、工具栏「复制 Markdown / 纯文本」、划词 Cmd+C\n• 使用方式：在访达（Finder）中选中任意 Markdown 文件并按下空格键"),
            buttonTitle: L10n.text("extensions.openExtensionSettings", "打开系统扩展设置"),
            buttonAction: #selector(openSystemExtensions(_:))
        )

        let guideCard = makeCard(
            title: L10n.text("extensions.addAToolModule", "添加工具模块"),
            symbol: "hammer",
            badge: "Sources/Tools/<YourTool>/",
            body: L10n.text("extensions.1AddAModuleUnderSourcesTools", "1. 在 Sources/Tools/ 下新建模块目录并实现 ToolModule 协议\n2. 在 Sources/Core/ToolModule.swift 的 ToolRegistry.defaultTools() 中注册新工具\n3. 如需新的系统扩展（Quick Look、Finder 同步、分享菜单等），在 Sources/Extensions/ 下添加对应 .appex 并在 scripts/build.sh 中打包签名"),
            buttonTitle: nil,
            buttonAction: nil
        )

        stack.addArrangedSubview(header)
        stack.setCustomSpacing(18, after: header)
        stack.addArrangedSubview(extCard)
        stack.addArrangedSubview(guideCard)

        header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64).isActive = true
        extCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64).isActive = true
        guideCard.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64).isActive = true

        container.addSubview(stack)
        scrollView.documentView = container

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            container.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor)
        ])

        self.view = scrollView
    }

    private func makeCard(
        title: String,
        symbol: String,
        badge: String,
        body: String,
        buttonTitle: String?,
        buttonAction: Selector?
    ) -> NSView {
        let card = ToolSurfaceView(fill: buttonAction == nil ? ToolAppearance.surface : ToolAppearance.tint)
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false

        let header = ToolAppearance.sectionTitle(title, symbol: symbol)

        let badgeLabel = NSTextField(wrappingLabelWithString: badge)
        badgeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.isSelectable = true
        badgeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        bodyLabel.attributedStringValue = NSAttributedString(
            string: body,
            attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        )
        bodyLabel.isSelectable = true
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        inner.addArrangedSubview(header)
        inner.addArrangedSubview(badgeLabel)
        inner.addArrangedSubview(bodyLabel)

        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        badgeLabel.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        bodyLabel.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        if let buttonTitle, let buttonAction {
            let btn = NSButton(title: buttonTitle, target: self, action: buttonAction)
            ToolAppearance.configure(btn, symbol: "gearshape")
            inner.addArrangedSubview(btn)
        }

        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        return card
    }

    @objc private func openSystemExtensions(_ sender: Any?) {
        InstallationService.shared.openExtensionsSettings()
    }
}
