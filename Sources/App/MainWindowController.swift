import AppKit

private final class ToolNavigationRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        let selection = bounds.insetBy(dx: 8, dy: 2)
        ToolAppearance.tint.setFill()
        NSBezierPath(roundedRect: selection, xRadius: 10, yRadius: 10).fill()
        ToolAppearance.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: selection.minX, y: selection.midY - 12, width: 3, height: 24),
                     xRadius: 1.5, yRadius: 1.5).fill()
    }
}

public final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let tools: [ToolModule]
    private var cachedControllers: [String: NSViewController] = [:]
    private var activeController: NSViewController?

    private let tableView = NSTableView()
    private let detailContainer = ToolSurfaceView(fill: ToolAppearance.canvas, radius: 0, border: nil)

    var onOpenLanguageSettings: (() -> Void)?

    public var onWindowShouldClose: ((NSWindow) -> Bool)?

    public init(tools: [ToolModule], initialToolID: String? = nil) {
        self.tools = tools
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let root = NSViewController()
        root.view = NSView(frame: NSRect(x: 0, y: 0, width: 1060, height: 720))
        window.contentViewController = root
        window.backgroundColor = ToolAppearance.canvas
        window.title = "MakeTools"
        window.minSize = NSSize(width: 780, height: 500)
        window.center()
        super.init(window: window)
        window.delegate = self
        setupUI()
        if let initialToolID, tools.contains(where: { $0.id == initialToolID }) {
            selectTool(withID: initialToolID)
        } else {
            selectTool(at: 0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        onWindowShouldClose?(sender) ?? true
    }

    // MARK: - Public Routing

    var selectedToolID: String? {
        tools.indices.contains(tableView.selectedRow) ? tools[tableView.selectedRow].id : nil
    }

    var markdownPreview: MarkdownToolViewController.Preview? {
        (cachedControllers["markdown-preview"] as? MarkdownToolViewController)?.preview
    }

    func restoreMarkdownPreview(_ preview: MarkdownToolViewController.Preview) {
        let controller = cachedControllers["markdown-preview"] as? MarkdownToolViewController ?? MarkdownToolViewController()
        cachedControllers["markdown-preview"] = controller
        controller.restorePreview(preview)
    }

    public func openMarkdownPicker() {
        selectTool(withID: "markdown-preview")
        if let vc = cachedControllers["markdown-preview"] as? MarkdownToolViewController {
            vc.openFilePicker()
        }
    }

    public func openMarkdownFile(at url: URL) {
        selectTool(withID: "markdown-preview")
        if let vc = cachedControllers["markdown-preview"] as? MarkdownToolViewController {
            vc.loadMarkdownFile(at: url)
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let sidebar = ToolSurfaceView(fill: ToolAppearance.rail, radius: 0, border: nil)
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2
        headerStack.edgeInsets = NSEdgeInsets(top: 27, left: 20, bottom: 23, right: 20)
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let brandLabel = NSTextField(labelWithString: "MakeTools")
        brandLabel.font = .systemFont(ofSize: 19, weight: .semibold)

        let taglineLabel = NSTextField(labelWithString: L10n.text("window.productivityTools", "个人效率工具集"))
        taglineLabel.font = .systemFont(ofSize: 11)
        taglineLabel.textColor = .secondaryLabelColor

        let brandText = NSStackView(views: [brandLabel, taglineLabel])
        brandText.orientation = .vertical
        brandText.alignment = .leading
        brandText.spacing = 2

        let brand = NSStackView(views: [ToolAppearance.tile("square.grid.2x2.fill", side: 42, size: 18), brandText])
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 10
        headerStack.addArrangedSubview(brand)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ToolColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 59
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.allowsEmptySelection = false
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.style = .plain
        tableView.setAccessibilityLabel(L10n.text("window.productivityTools", "个人效率工具集"))
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let footerDivider = NSBox()
        footerDivider.boxType = .separator
        footerDivider.translatesAutoresizingMaskIntoConstraints = false

        let extButton = NSButton(title: L10n.text("language.menu", "语言设置…"), target: self, action: #selector(openLanguageSettings))
        ToolAppearance.configure(extButton, symbol: "globe")
        extButton.controlSize = .regular
        extButton.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(headerStack)
        sidebar.addSubview(scrollView)
        sidebar.addSubview(footerDivider)
        sidebar.addSubview(extButton)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        detailContainer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(sidebar)
        contentView.addSubview(divider)
        contentView.addSubview(detailContainer)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 228),

            headerStack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerDivider.topAnchor),

            footerDivider.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            footerDivider.bottomAnchor.constraint(equalTo: extButton.topAnchor, constant: -10),

            extButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            extButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            extButton.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),

            divider.topAnchor.constraint(equalTo: contentView.topAnchor),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            detailContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    // MARK: - Tool Selection

    public func selectTool(withID id: String) {
        if let index = tools.firstIndex(where: { $0.id == id }) {
            selectTool(at: index)
        }
    }

    private func selectTool(at index: Int) {
        guard index >= 0 && index < tools.count else { return }
        if tableView.selectedRow != index {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }

        let tool = tools[index]
        let nextVC: NSViewController
        if let cached = cachedControllers[tool.id] {
            nextVC = cached
        } else {
            let created = tool.makeViewController()
            cachedControllers[tool.id] = created
            nextVC = created
        }

        if activeController === nextVC {
            return
        }

        let shouldAnimate = activeController != nil && window?.isVisible == true
        if let current = activeController {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        contentViewController?.addChild(nextVC)
        let childView = nextVC.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(childView)

        NSLayoutConstraint.activate([
            childView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            childView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
        ])

        activeController = nextVC
        if shouldAnimate {
            ToolAppearance.reveal(childView, from: 0.65)
        }
        window?.title = "\(tool.title) — MakeTools"
    }

    @objc private func openLanguageSettings() {
        onOpenLanguageSettings?()
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        tools.count
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ToolNavigationRow()
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tools.indices.contains(row) else { return nil }
        let tool = tools[row]
        let cell = NSView()

        let iconView = ToolAppearance.icon(tool.symbolName, size: 17, tint: ToolAppearance.accent)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: tool.title)
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail

        let subtitleField = NSTextField(labelWithString: tool.subtitle)
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleField, subtitleField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(iconView)
        cell.addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 22),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
            textStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        if row >= 0 && row < tools.count {
            selectTool(at: row)
        }
    }
}
