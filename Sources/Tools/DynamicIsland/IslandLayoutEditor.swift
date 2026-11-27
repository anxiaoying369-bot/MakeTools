import AppKit

private final class IslandLayoutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class LayoutDropArea: NSView {
    var updateDrop: ((NSDraggingInfo) -> Bool)?
    var performDrop: ((NSDraggingInfo) -> Bool)?
    var clearDrop: (() -> Void)?
    var highlighted = false {
        didSet { if oldValue != highlighted { needsDisplay = true } }
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = ToolAppearance.accent.cgColor
            layer?.cornerRadius = 16
            layer?.borderWidth = highlighted ? 2 : 0
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrop?(sender) == true ? .move : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { clearDrop?() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearDrop?() }
        return performDrop?(sender) ?? false
    }
}

private final class LayoutScrollDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class LayoutTile: NSView, NSDraggingSource {
    static let dragType = NSPasteboard.PasteboardType("com.make.MakeTools.layout-editor-card")
    let card: IslandExpandedCard
    let inPreview: Bool
    weak var owner: IslandLayoutEditor?
    private var pressedAt: NSPoint?
    var highlighted = false {
        didSet { if oldValue != highlighted { needsDisplay = true } }
    }

    init(card: IslandExpandedCard, inPreview: Bool, owner: IslandLayoutEditor, height: CGFloat) {
        self.card = card
        self.inPreview = inPreview
        self.owner = owner
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = L10n.text("island.dragToReorder", "拖动{arg1}以调整位置", ["arg1": card.title])
        heightAnchor.constraint(equalToConstant: height).isActive = true

        let symbol: String
        switch card {
        case .performance: symbol = "chart.bar.xaxis"
        case .audio: symbol = "speaker.wave.2"
        case .focus: symbol = "timer"
        case .shelf: symbol = "tray.and.arrow.down"
        case .calendar: symbol = "calendar"
        case .bookmarks: symbol = "bookmark"
        case .lanTransfer: symbol = "wifi"
        }
        let glyph = ToolAppearance.icon(symbol, size: 14, tint: ToolAppearance.accent)
        glyph.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let name = NSTextField(labelWithString: card.title)
        name.lineBreakMode = .byTruncatingTail
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let primary = action(inPreview ? "minus.circle" : "plus.circle",
                             title: inPreview ? L10n.text("island.remove", "移除{arg1}", ["arg1": card.title])
                                              : L10n.text("island.layout.addCard", "添加{card}", ["card": card.title]),
                             selector: #selector(toggle))
        let row = NSStackView(views: [glyph, name, spacer, primary])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 13)
        ])

        if inPreview && card == .shelf {
            let slots = NSStackView(views: (0..<3).map { _ in
                let row = NSStackView(views: (0..<3).map { _ in
                    ToolSurfaceView(fill: ToolAppearance.rail, radius: 5, border: nil)
                })
                row.orientation = .horizontal
                row.distribution = .fillEqually
                row.spacing = 5
                for slot in row.arrangedSubviews {
                    slot.heightAnchor.constraint(equalTo: row.heightAnchor).isActive = true
                }
                return row
            })
            slots.orientation = .vertical
            slots.distribution = .fillEqually
            slots.spacing = 5
            for row in slots.arrangedSubviews {
                row.widthAnchor.constraint(equalTo: slots.widthAnchor).isActive = true
            }
            slots.setAccessibilityElement(false)
            slots.translatesAutoresizingMaskIntoConstraints = false
            addSubview(slots)
            NSLayoutConstraint.activate([
                slots.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 11),
                slots.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                slots.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                slots.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
            ])
        }

        if inPreview {
            let menu = NSMenu()
            for (title, selector, offset) in [
                (L10n.text("island.moveUp", "前移"), #selector(moveEarlier), -1),
                (L10n.text("island.moveDown", "后移"), #selector(moveLater), 1)
            ] {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = self
                item.isEnabled = owner.canMove(card, by: offset)
                menu.addItem(item)
            }
            menu.autoenablesItems = false
            self.menu = menu
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (highlighted ? ToolAppearance.tint : ToolAppearance.surface).cgColor
            layer?.borderColor = (highlighted ? ToolAppearance.accent : ToolAppearance.line).cgColor
            layer?.borderWidth = highlighted ? 2 : 1
            layer?.cornerRadius = 10
        }
    }

    private func action(_ symbol: String, title: String, selector: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: selector)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.contentTintColor = ToolAppearance.accent
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    @objc private func toggle() { owner?.toggle(card, remove: inPreview) }
    @objc private func moveEarlier() { owner?.move(card, by: -1) }
    @objc private func moveLater() { owner?.move(card, by: 1) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSControl && !(hit is NSTextField) ? hit : self
    }

    override func mouseDown(with event: NSEvent) {
        pressedAt = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) { pressedAt = nil }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let pressedAt, hypot(point.x - pressedAt.x, point.y - pressedAt.y) >= 4 else { return }
        self.pressedAt = nil
        let pasteboard = NSPasteboardItem()
        pasteboard.setString(card.rawValue, forType: Self.dragType)
        let item = NSDraggingItem(pasteboardWriter: pasteboard)
        let rep = bitmapImageRepForCachingDisplay(in: bounds)
        let image = rep.map {
            cacheDisplay(in: bounds, to: $0)
            let image = NSImage(size: bounds.size)
            image.addRepresentation($0)
            return image
        }
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        owner?.clearHighlight()
    }
}

final class IslandLayoutEditor: NSWindowController {
    private weak var manager: DynamicIslandManager?
    private var draft: IslandLayoutDraft
    private var enabled: Set<IslandExpandedCard>
    private var observer: NSObjectProtocol?
    private let picker = NSPopUpButton()
    private let preview = LayoutDropArea()
    private let library = LayoutDropArea()
    private let previewItems = NSStackView()
    private let libraryItems = NSStackView()
    private var tiles: [LayoutTile] = []
    private var currentZone: LayoutDropArea?

    init(manager: DynamicIslandManager) {
        self.manager = manager
        draft = manager.layoutDraft
        enabled = Set(IslandExpandedCard.allCases.filter(manager.isExpandedCardEnabled))
        let panel = IslandLayoutPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 558),
                                      styleMask: [.titled, .closable, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.title = L10n.text("island.layout.title", "灵动岛布局")
        panel.backgroundColor = ToolAppearance.canvas
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        configure()
        render()
        observer = NotificationCenter.default.addObserver(forName: DynamicIslandManager.didUpdateNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            guard let self, let manager = self.manager else { return }
            let enabled = Set(IslandExpandedCard.allCases.filter(manager.isExpandedCardEnabled))
            guard enabled != self.enabled else { return }
            self.enabled = enabled
            self.render()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func show(from anchor: NSView?) {
        guard let window else { return }
        if let parent = anchor?.window, let screen = parent.screen {
            let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let x = max(visible.minX, min(parent.frame.midX - window.frame.width / 2, visible.maxX - window.frame.width))
            let y = max(visible.minY + window.frame.height, min(parent.frame.maxY - 32, visible.maxY))
            window.setFrameTopLeftPoint(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func configure() {
        guard let root = window?.contentView else { return }
        let header = ToolAppearance.header(
            title: L10n.text("island.layout.title", "灵动岛布局"),
            subtitle: L10n.text("island.layout.help", "在预览中拖动组件排序，也可在预览与组件库之间拖动。"),
            symbol: "square.grid.2x2"
        )
        picker.addItems(withTitles: IslandExpandedLayout.allCases.map(\.title))
        picker.setAccessibilityLabel(L10n.text("island.expandedPanelLayout", "展开面板的布局"))
        picker.target = self
        picker.action = #selector(pickLayout)
        let previewHeading = L10n.text("island.layout.preview", "布局预览")
        let libraryHeading = L10n.text("island.layout.library", "组件库")
        configureZone(preview, items: previewItems, title: previewHeading, accessory: picker)
        configureZone(library, items: libraryItems, title: libraryHeading, accessory: nil)
        let columns = stack([preview, library], orientation: .horizontal, spacing: 12)
        columns.alignment = .top
        NSLayoutConstraint.activate([
            library.widthAnchor.constraint(equalToConstant: 240),
            preview.heightAnchor.constraint(equalTo: columns.heightAnchor),
            library.heightAnchor.constraint(equalTo: columns.heightAnchor)
        ])

        let reset = button(L10n.text("island.restoreDefaults", "恢复默认"), symbol: "arrow.counterclockwise", action: #selector(resetDraft))
        let cancel = button(L10n.text("passwords.cancel", "取消"), symbol: nil, action: #selector(cancelEditing))
        cancel.keyEquivalent = "\u{1b}"
        let done = button(L10n.text("island.layout.done", "完成"), symbol: nil, action: #selector(apply))
        done.keyEquivalent = "\r"
        let footer = stack([reset, spacer(), cancel, done], orientation: .horizontal, spacing: 8)

        let content = stack([header, columns, footer], orientation: .vertical, spacing: 12)
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        for view in [header, columns, footer] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18)
        ])
    }

    private func configureZone(_ zone: LayoutDropArea, items: NSStackView, title: String, accessory: NSView?) {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        let controls = stack([heading, spacer()] + (accessory.map { [$0] } ?? []), orientation: .horizontal, spacing: 8)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = LayoutScrollDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        items.orientation = .vertical
        items.alignment = .leading
        items.spacing = 7
        items.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(items)
        scroll.documentView = document
        let body = stack([controls, scroll], orientation: .vertical, spacing: 10)
        let card = ToolAppearance.section(body, fill: ToolAppearance.rail, inset: 12)
        card.translatesAutoresizingMaskIntoConstraints = false
        zone.wantsLayer = true
        zone.addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: zone.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: zone.trailingAnchor),
            card.topAnchor.constraint(equalTo: zone.topAnchor),
            card.bottomAnchor.constraint(equalTo: zone.bottomAnchor),
            controls.widthAnchor.constraint(equalTo: body.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: body.widthAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            items.topAnchor.constraint(equalTo: document.topAnchor),
            items.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            items.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            items.trailingAnchor.constraint(equalTo: document.trailingAnchor)
        ])
        zone.registerForDraggedTypes([LayoutTile.dragType])
        zone.updateDrop = { [weak self, weak zone] sender in
            guard let self, let zone else { return false }
            return self.handleDrop(sender, in: zone, commit: false)
        }
        zone.performDrop = { [weak self, weak zone] sender in
            guard let self, let zone else { return false }
            return self.handleDrop(sender, in: zone, commit: true)
        }
        zone.clearDrop = { [weak self, weak zone] in
            guard let self, self.currentZone === zone else { return }
            self.clearHighlight()
        }
    }

    private func render() {
        clearHighlight()
        picker.selectItem(at: IslandExpandedLayout.allCases.firstIndex(of: draft.layout) ?? 0)
        for stack in [previewItems, libraryItems] {
            for item in stack.arrangedSubviews { stack.removeArrangedSubview(item); item.removeFromSuperview() }
        }
        tiles.removeAll()
        let cards = draft.visible(in: enabled)
        let hasShelf = cards.contains(.shelf)
        let compact = cards.filter { $0 != .shelf }
        if cards.isEmpty {
            append(hint(L10n.text("island.layout.emptyPreview", "把组件拖到这里，或在右侧点击添加。")), to: previewItems)
        } else if draft.layout.usesGrid(cardCount: cards.count, hasShelf: hasShelf) {
            for group in draft.layout.gridRows(for: cards) {
                append(row(group.map { tile($0, inPreview: true, height: $0 == .shelf ? 106 : 48) }), to: previewItems)
            }
        } else if hasShelf && !compact.isEmpty {
            let strip = stack(compact.map { tile($0, inPreview: true, height: 48) }, orientation: .vertical, spacing: 7)
            for item in strip.arrangedSubviews { item.widthAnchor.constraint(equalTo: strip.widthAnchor).isActive = true }
            let shelf = tile(.shelf, inPreview: true, height: max(106, CGFloat(compact.count) * 55 - 7))
            let columns = draft.layout == .shelfLeft ? [shelf, strip] : [strip, shelf]
            append(row(columns), to: previewItems)
        } else {
            append(row(cards.map { tile($0, inPreview: true, height: $0 == .shelf ? 106 : 48) }), to: previewItems)
        }

        let available = draft.order.filter { enabled.contains($0) && draft.hidden.contains($0) }
        if available.isEmpty {
            append(hint(L10n.text("island.layout.emptyLibrary", "没有可添加的组件。可把组件拖到这里移出布局。")), to: libraryItems)
        }
        for card in available { append(tile(card, inPreview: false, height: 49), to: libraryItems) }
    }

    private func handleDrop(_ sender: NSDraggingInfo, in zone: LayoutDropArea, commit: Bool) -> Bool {
        guard let source = sender.draggingSource as? LayoutTile, source.owner === self,
              enabled.contains(source.card), zone === preview || source.inPreview else { return false }
        let point = zone.convert(sender.draggingLocation, from: nil)
        guard zone.bounds.contains(point) else { return false }
        let hover = tiles.first {
            $0.inPreview == (zone === preview) && $0.convert($0.bounds, to: zone).contains(point)
        }
        if !commit {
            currentZone = zone
            preview.highlighted = zone === preview
            library.highlighted = zone === library
            for tile in tiles { tile.highlighted = tile === hover }
            return true
        }
        if zone === library {
            toggle(source.card, remove: true)
        } else if source.card == .shelf && draft.layout != .grid {
            draft.layout = point.x < zone.bounds.midX ? .shelfLeft : .shelfRight
            draft.hidden.remove(source.card)
            render()
        } else if hover?.card != source.card {
            let target = hover.flatMap { draft.layout != .grid && $0.card == .shelf ? nil : $0 }
            let after = target.map {
                let bounds = $0.convert($0.bounds, to: zone)
                let visible = draft.visible(in: enabled)
                let verticalStrip = draft.layout != .grid && visible.contains(.shelf) && visible.count > 1
                return verticalStrip ? point.y < bounds.midY : point.x > bounds.midX
            } ?? true
            draft.place(source.card, nextTo: target?.card, after: after)
            render()
        }
        return true
    }

    func clearHighlight() {
        currentZone = nil
        preview.highlighted = false
        library.highlighted = false
        for tile in tiles { tile.highlighted = false }
    }

    func toggle(_ card: IslandExpandedCard, remove: Bool) {
        if remove { draft.hidden.insert(card) } else { draft.place(card) }
        render()
    }

    func canMove(_ card: IslandExpandedCard, by offset: Int) -> Bool {
        let order = draft.movable(in: enabled)
        return order.firstIndex(of: card).map { order.indices.contains($0 + offset) } ?? false
    }

    func move(_ card: IslandExpandedCard, by offset: Int) {
        draft.move(card, by: offset, enabled: enabled)
        render()
    }

    @objc private func pickLayout() {
        let layouts = IslandExpandedLayout.allCases
        guard layouts.indices.contains(picker.indexOfSelectedItem) else { return }
        draft.layout = layouts[picker.indexOfSelectedItem]
        render()
    }

    @objc private func resetDraft() {
        draft = .defaults
        render()
    }

    @objc private func cancelEditing() { close() }

    @objc private func apply() {
        manager?.applyLayoutDraft(draft)
        close()
    }

    private func tile(_ card: IslandExpandedCard, inPreview: Bool, height: CGFloat) -> LayoutTile {
        let tile = LayoutTile(card: card, inPreview: inPreview, owner: self, height: height)
        tiles.append(tile)
        return tile
    }

    private func append(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let row = stack(views, orientation: .horizontal, spacing: 7)
        row.distribution = .fillEqually
        row.alignment = .top
        return row
    }

    private func stack(_ views: [NSView], orientation: NSUserInterfaceLayoutOrientation, spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        stack.alignment = orientation == .horizontal ? .centerY : .leading
        stack.spacing = spacing
        return stack
    }

    private func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        return spacer
    }

    private func hint(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 12)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func button(_ title: String, symbol: String?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        if let symbol { ToolAppearance.configure(button, symbol: symbol) }
        return button
    }
}
