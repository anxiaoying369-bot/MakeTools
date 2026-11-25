import AppKit

private final class WebBookmarksPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BookmarkActionButton: NSButton {
    var hoverTint: NSColor = .controlAccentColor
    private var pointerArea: NSTrackingArea?
    private var isHovered = false

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted || isHovered {
            hoverTint.withAlphaComponent(isHighlighted ? 0.19 : 0.10).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
}

final class WebBookmarksWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let addressField = NSTextField(string: "")
    private let titleField = NSTextField(string: "")
    private let status = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyState = NSStackView()
    private let store: WebBookmarkStore
    private let openURL: (URL) -> Bool
    private var bookmarks: [WebBookmark] = []

    var onChange: (([WebBookmark]) -> Void)?

    init(store: WebBookmarkStore = WebBookmarkStore(), openURL: @escaping (URL) -> Bool = NSWorkspace.shared.open) {
        self.store = store
        self.openURL = openURL
        let size = NSSize(width: 510, height: 398)
        let panel = WebBookmarksPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.title = "网络书签"
        panel.contentMinSize = size
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        configureView()
        panel.setContentSize(size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(from anchor: NSView) {
        guard let window, let parent = anchor.window else { return }
        if !window.isVisible {
            do {
                updateList(try store.load())
            } catch {
                status.stringValue = "无法读取已保存的书签。"
            }
            if let screen = parent.screen {
                let visible = screen.visibleFrame.insetBy(dx: 10, dy: 10)
                let x = max(visible.minX, min(parent.frame.midX - window.frame.width / 2, visible.maxX - window.frame.width))
                let y = min(max(parent.frame.minY - 8, visible.minY + window.frame.height), visible.maxY)
                window.setFrameTopLeftPoint(NSPoint(x: x, y: y))
            } else {
                window.center()
            }
        }
        window.makeKeyAndOrderFront(nil)
    }

    func openBookmark(_ bookmark: WebBookmark) -> Bool {
        WebBookmark.isWebAddress(bookmark.url) && openURL(bookmark.url)
    }

    private func configureView() {
        guard let window, let root = window.contentView else { return }

        addressField.placeholderString = "example.com"
        addressField.setAccessibilityLabel("书签网址")
        titleField.placeholderString = "使用网站域名"
        titleField.setAccessibilityLabel("书签名称")
        let address = fieldGroup("网址", field: addressField)
        let title = fieldGroup("名称（可选）", field: titleField)
        title.widthAnchor.constraint(equalToConstant: 126).isActive = true
        addressField.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)

        let add = NSButton(title: "添加书签", target: self, action: #selector(addBookmark))
        ToolAppearance.configure(add, symbol: "plus")
        add.keyEquivalent = "\r"
        add.controlSize = .large
        add.setContentHuggingPriority(.required, for: .horizontal)
        add.setContentCompressionResistancePriority(.required, for: .horizontal)
        let form = NSStackView(views: [address, title, add])
        form.orientation = .horizontal
        form.alignment = .bottom
        form.distribution = .fill
        form.spacing = 10
        let composerFill = NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return .controlAccentColor.withAlphaComponent(dark ? 0.09 : 0.045)
        }
        let composer = ToolSurfaceView(fill: composerFill, radius: 14)
        composer.addSubview(form)
        form.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 14),
            form.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -14),
            form.topAnchor.constraint(equalTo: composer.topAnchor, constant: 12),
            form.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -12)
        ])
        window.initialFirstResponder = addressField

        let heading = NSTextField(labelWithString: "已保存的书签")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        status.textColor = .systemRed
        status.alignment = .right
        let listHeader = NSStackView(views: [heading, countLabel, status])
        listHeader.orientation = .horizontal
        listHeader.alignment = .firstBaseline
        listHeader.distribution = .fill
        listHeader.spacing = 8
        for label in [heading, countLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("WebBookmark"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 58
        table.intercellSpacing = NSSize(width: 0, height: 6)
        table.style = .plain
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("已保存的网络书签")

        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table

        let emptyTitle = NSTextField(labelWithString: "暂无书签")
        emptyTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let emptyHint = NSTextField(labelWithString: "在上方输入网址，收藏常用网页。")
        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.textColor = .secondaryLabelColor
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 7
        for view in [ToolAppearance.tile("bookmark", side: 42, size: 17), emptyTitle, emptyHint] {
            emptyState.addArrangedSubview(view)
        }

        for view in [composer, listHeader, scroll, emptyState] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            composer.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            composer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            composer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            listHeader.topAnchor.constraint(equalTo: composer.bottomAnchor, constant: 18),
            listHeader.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 2),
            listHeader.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -2),
            scroll.topAnchor.constraint(equalTo: listHeader.bottomAnchor, constant: 9),
            scroll.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            emptyState.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -5)
        ])
        updateList([])
    }

    private func fieldGroup(_ caption: String, field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: caption)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.setAccessibilityElement(false)
        field.controlSize = .large
        field.cell?.usesSingleLineMode = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let group = NSStackView(views: [label, field])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 5
        field.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }

    private func updateList(_ items: [WebBookmark]) {
        bookmarks = items
        status.stringValue = ""
        countLabel.stringValue = "\(items.count) 条"
        scroll.isHidden = items.isEmpty
        emptyState.isHidden = !items.isEmpty
        table.reloadData()
    }

    @objc private func addBookmark() {
        guard let bookmark = WebBookmark(title: titleField.stringValue, address: addressField.stringValue) else {
            status.stringValue = "请输入有效的 HTTP 或 HTTPS 网址。"
            return
        }

        do {
            let items = try store.add(bookmark)
            updateList(items)
            addressField.stringValue = ""
            titleField.stringValue = ""
            table.scrollRowToVisible(0)
            onChange?(items)
        } catch {
            status.stringValue = "无法保存书签，请重试。"
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { bookmarks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let bookmark = bookmarks[row]
        let open = BookmarkActionButton(title: "", target: self, action: #selector(openFromList(_:)))
        open.isBordered = false
        open.wantsLayer = true
        open.tag = row
        open.toolTip = bookmark.url.absoluteString
        open.setAccessibilityLabel("打开书签 \(bookmark.title)")

        let title = NSTextField(labelWithString: bookmark.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        let address = NSTextField(labelWithString: bookmark.url.absoluteString)
        address.font = .systemFont(ofSize: 11)
        address.textColor = .secondaryLabelColor
        address.lineBreakMode = .byTruncatingMiddle
        for label in [title, address] {
            label.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setAccessibilityElement(false)
        }
        let details = NSStackView(views: [title, address])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 2
        address.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
        title.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
        let arrow = ToolAppearance.icon("arrow.up.right", size: 10, tint: .secondaryLabelColor)
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        let content = NSStackView(views: [ToolAppearance.tile("globe", side: 34, size: 15), details, arrow])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.distribution = .fill
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        open.addSubview(content)

        let remove = BookmarkActionButton(title: "", target: self, action: #selector(confirmRemoval(_:)))
        remove.isBordered = false
        remove.wantsLayer = true
        remove.hoverTint = .systemRed
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        remove.imagePosition = .imageOnly
        remove.contentTintColor = .secondaryLabelColor
        remove.tag = row
        remove.toolTip = "删除书签"
        remove.setAccessibilityLabel("删除书签 \(bookmark.title)")
        let cell = ToolSurfaceView(radius: 12)
        for button in [open, remove] {
            button.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(button)
        }
        NSLayoutConstraint.activate([
            open.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            open.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            open.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
            open.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -4),
            content.leadingAnchor.constraint(equalTo: open.leadingAnchor, constant: 7),
            content.trailingAnchor.constraint(equalTo: open.trailingAnchor, constant: -8),
            content.centerYAnchor.constraint(equalTo: open.centerYAnchor),
            remove.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -9),
            remove.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 30),
            remove.heightAnchor.constraint(equalToConstant: 30)
        ])
        return cell
    }

    @objc private func confirmRemoval(_ sender: NSButton) {
        guard bookmarks.indices.contains(sender.tag), let window, window.attachedSheet == nil else { return }
        let bookmark = bookmarks[sender.tag]
        let alert = NSAlert()
        alert.messageText = "删除这条书签？"
        alert.informativeText = bookmark.title
        let cancel = alert.addButton(withTitle: "取消")
        cancel.keyEquivalent = "\r"
        let remove = alert.addButton(withTitle: "删除")
        remove.keyEquivalent = ""
        remove.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            do {
                let items = try store.remove(url: bookmark.url)
                updateList(items)
                onChange?(items)
            } catch {
                status.stringValue = "无法删除书签，请重试。"
            }
        }
    }

    @objc private func openFromList(_ sender: NSButton) {
        guard bookmarks.indices.contains(sender.tag) else { return }
        status.stringValue = openBookmark(bookmarks[sender.tag]) ? "" : "无法打开该网页。"
    }
}
