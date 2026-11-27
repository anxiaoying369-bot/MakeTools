import AppKit
import Foundation

struct IslandClipboardEntry {
    let id = UUID()
    let text: String
    let preview: String

    init?(text: String) {
        let singleLine = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return nil }

        self.text = text
        preview = singleLine.count > 120 ? String(singleLine.prefix(120)) + "…" : singleLine
    }
}

/// Central coordinator for Dynamic Island settings, modular features, live telemetry, and overlay lifecycle.
public final class DynamicIslandManager {
    public static let shared = DynamicIslandManager()
    public static let didUpdateNotification = Notification.Name("MakeTools.DynamicIslandDidUpdate")
    public static let maxShelfFiles = 9

    private enum DefaultsKey {
        static let isEnabled = "MakeTools.DynamicIsland.isEnabled"
        static let material = "MakeTools.DynamicIsland.material"
        static let style = "MakeTools.DynamicIsland.style"
        static let expandedLayout = "MakeTools.DynamicIsland.expandedLayout"
        static let expandedCardOrder = "MakeTools.DynamicIsland.expandedCardOrder"
        static let hiddenExpandedCards = "MakeTools.DynamicIsland.hiddenExpandedCards"
        static let hoverToExpand = "MakeTools.DynamicIsland.hoverToExpand"
        static let dragToExpand = "MakeTools.DynamicIsland.dragToExpand"
        static let showCollapsedCustomTitle = "MakeTools.DynamicIsland.showCollapsedCustomTitle"
        static let collapsedCustomTitle = "MakeTools.DynamicIsland.collapsedCustomTitle"
        static let collapsedMetrics = "MakeTools.DynamicIsland.collapsedMetrics"
        static let collapsedCustomWidth = "MakeTools.DynamicIsland.collapsedCustomWidth"
        static let featurePrefix = "MakeTools.DynamicIsland.feature."
    }

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
            if isEnabled {
                startLoopAndWindow()
            } else {
                stopLoopAndWindow()
            }
            notifyUpdated()
        }
    }

    var material: DynamicIslandMaterial {
        didSet {
            guard material != oldValue else { return }
            UserDefaults.standard.set(material.rawValue, forKey: DefaultsKey.material)
            windowController?.applyMaterial(material)
            notifyUpdated()
        }
    }

    public var style: DynamicIslandStyle {
        didSet {
            guard style != oldValue else { return }
            UserDefaults.standard.set(style.rawValue, forKey: DefaultsKey.style)
            windowController?.syncState(animated: false)
            notifyUpdated()
        }
    }

    private(set) var expandedLayout: IslandExpandedLayout
    private(set) var expandedCardOrder: [IslandExpandedCard]
    private(set) var hiddenExpandedCards: Set<IslandExpandedCard>
    private(set) var calendarEvents: [CalendarCountdownEvent]
    private let calendarStore = CalendarCountdownStore()
    private(set) var expandedNotice: (title: String, detail: String)?

    private var layoutEditor: IslandLayoutEditor?

    var layoutDraft: IslandLayoutDraft {
        IslandLayoutDraft(layout: expandedLayout, order: expandedCardOrder, hidden: hiddenExpandedCards)
    }

    func openLayoutEditor(from anchor: NSView?) {
        if let layoutEditor, layoutEditor.window?.isVisible == true {
            layoutEditor.window?.makeKeyAndOrderFront(nil)
            return
        }
        let editor = IslandLayoutEditor(manager: self)
        layoutEditor = editor
        editor.show(from: anchor)
    }

    func applyLayoutDraft(_ draft: IslandLayoutDraft) {
        if draft.hidden.contains(.shelf) && !hiddenExpandedCards.contains(.shelf) {
            endExternalFileDrag(shouldCollapseIfNeeded: false)
        }
        updateExpandedLayout(draft.layout, order: draft.order, hidden: draft.hidden)
    }

    private func updateExpandedLayout(
        _ layout: IslandExpandedLayout, order: [IslandExpandedCard], hidden: Set<IslandExpandedCard>? = nil
    ) {
        let hidden = hidden ?? hiddenExpandedCards
        guard layout != expandedLayout || order != expandedCardOrder || hidden != hiddenExpandedCards else { return }
        expandedLayout = layout
        expandedCardOrder = order
        hiddenExpandedCards = hidden
        UserDefaults.standard.set(layout.rawValue, forKey: DefaultsKey.expandedLayout)
        UserDefaults.standard.set(order.map(\.rawValue), forKey: DefaultsKey.expandedCardOrder)
        UserDefaults.standard.set(IslandExpandedCard.allCases.filter { hidden.contains($0) }.map(\.rawValue),
                                  forKey: DefaultsKey.hiddenExpandedCards)
        windowController?.syncState(animated: state == .expanded)
        notifyUpdated()
    }

    public var hoverToExpand: Bool {
        didSet {
            UserDefaults.standard.set(hoverToExpand, forKey: DefaultsKey.hoverToExpand)
            notifyUpdated()
        }
    }

    public var dragToExpand: Bool {
        didSet {
            UserDefaults.standard.set(dragToExpand, forKey: DefaultsKey.dragToExpand)
            if !dragToExpand {
                endExternalFileDrag(shouldCollapseIfNeeded: false)
            }
            notifyUpdated()
        }
    }

    public var showCollapsedCustomTitle: Bool {
        didSet {
            UserDefaults.standard.set(showCollapsedCustomTitle, forKey: DefaultsKey.showCollapsedCustomTitle)
            windowController?.syncState(animated: state == .collapsed)
            notifyUpdated()
        }
    }

    public var collapsedCustomTitle: String {
        didSet {
            UserDefaults.standard.set(collapsedCustomTitle, forKey: DefaultsKey.collapsedCustomTitle)
            windowController?.syncState(animated: state == .collapsed)
            notifyUpdated()
        }
    }

    /// 0 means automatic adaptation; > 0 fixes the collapsed pill width within 160...680 pt.
    public var collapsedCustomWidth: CGFloat {
        didSet {
            if collapsedCustomWidth > 0 {
                let clamped = min(680, max(160, collapsedCustomWidth))
                if clamped != collapsedCustomWidth {
                    collapsedCustomWidth = clamped
                    return
                }
            } else if collapsedCustomWidth < 0 {
                collapsedCustomWidth = 0
                return
            }
            UserDefaults.standard.set(Double(collapsedCustomWidth), forKey: DefaultsKey.collapsedCustomWidth)
            if state == .collapsed {
                windowController?.syncState(animated: false)
            }
            notifyUpdated()
        }
    }

    public var currentCollapsedPillWidth: CGFloat {
        windowController?.currentCollapsedPillWidth ?? (collapsedCustomWidth > 0 ? collapsedCustomWidth : 196)
    }

    public var orderedEnabledCollapsedMetrics: [CollapsedMetricItem] {
        CollapsedMetricItem.allCases.filter { collapsedMetrics.contains($0) }
    }

    public var hoverDelay: TimeInterval = 0.18

    public var clipboardToastEnabled: Bool {
        get { isFeatureEnabled(.clipboardHistory) }
        set { setFeature(.clipboardHistory, enabled: newValue) }
    }

    public private(set) var isPinned: Bool = false
    public private(set) var state: DynamicIslandState = .collapsed
    public private(set) var latestSnapshot: SystemSnapshot = .empty
    public let focusTimer = FocusTimerModel(minutes: 25)
    public let audioController = SystemAudioController()
    public let keepAwakeController = KeepAwakeController()

    public private(set) var droppedFiles: [URL] = []
    public private(set) var selectedFileIndex: Int = 0

    public var selectedDroppedFile: URL? {
        guard !droppedFiles.isEmpty,
              selectedFileIndex >= 0,
              selectedFileIndex < droppedFiles.count else {
            return droppedFiles.first
        }
        return droppedFiles[selectedFileIndex]
    }

    private(set) var clipboardEntries: [IslandClipboardEntry] = []
    public var clipboardHistory: [String] { clipboardEntries.map(\.preview) }
    public private(set) var clipboardHistoryIndex: Int = 0

    public var isInternalDragInProgress: Bool = false
    public private(set) var isExternalFileDragActive: Bool = false

    public var latestClipboardText: String {
        currentClipboardItem
    }

    public var currentClipboardItem: String {
        guard clipboardEntries.indices.contains(clipboardHistoryIndex) else { return "" }
        return clipboardEntries[clipboardHistoryIndex].preview
    }

    public var isKeepAwakeActive: Bool {
        keepAwakeController.isActive
    }

    public var activeExpandedCardCount: Int { activeExpandedCards.count }

    var activeExpandedCards: [IslandExpandedCard] {
        expandedCardOrder.filter { !hiddenExpandedCards.contains($0) && isExpandedCardEnabled($0) }
    }

    var isFileShelfVisible: Bool { isExpandedCardEnabled(.shelf) && !hiddenExpandedCards.contains(.shelf) }

    func isExpandedCardEnabled(_ card: IslandExpandedCard) -> Bool {
        switch card {
        case .performance:
            return isFeatureEnabled(.systemMonitor) || isFeatureEnabled(.downloadSpeed) || isFeatureEnabled(.uploadSpeed)
        case .audio: return isFeatureEnabled(.audioControl) || isFeatureEnabled(.keepAwake)
        case .focus: return isFeatureEnabled(.focusTimer)
        case .shelf: return isFeatureEnabled(.fileShelf)
        case .calendar: return isFeatureEnabled(.calendarCountdown)
        case .bookmarks: return isFeatureEnabled(.webBookmarks)
        case .lanTransfer: return isFeatureEnabled(.lanTransfer)
        }
    }

    public var onOpenMainWindow: (() -> Void)?

    private let metricsReader = SystemMetricsReader()
    private var featureStates: [DynamicIslandFeature: Bool] = [:]
    private var collapsedMetrics: Set<CollapsedMetricItem> = []
    private var collapsedMetricRotation = CollapsedMetricRotation()
    private var windowController: DynamicIslandWindowController?
    private var tickTimer: Timer?
    private var focusTickTimer: Timer?
    private var focusDeadline: ContinuousClock.Instant?
    private var pendingLanguageRefresh = false
    private var hudDismissWorkItem: DispatchWorkItem?
    private var dragAutoCollapseWorkItem: DispatchWorkItem?
    private var lastPasteboardChangeCount: Int
    private var fileDragGesture = IslandFileDragGesture()
    private var hasSampledBaseline = false
    private var expandedByExternalDrag = false
    private var screenObserver: NSObjectProtocol?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?

    private init() {
        let defaults = UserDefaults.standard
        self.calendarEvents = CalendarCountdownStore(defaults: defaults).load()
        if defaults.object(forKey: DefaultsKey.isEnabled) == nil {
            defaults.set(true, forKey: DefaultsKey.isEnabled)
        }
        self.isEnabled = defaults.bool(forKey: DefaultsKey.isEnabled)

        material = DynamicIslandMaterial.restored(defaults.string(forKey: DefaultsKey.material))
        let rawStyle = defaults.integer(forKey: DefaultsKey.style)
        self.style = DynamicIslandStyle(rawValue: rawStyle) ?? .auto
        let savedLayout = defaults.string(forKey: DefaultsKey.expandedLayout) ?? ""
        self.expandedLayout = IslandExpandedLayout(rawValue: savedLayout) ?? .shelfRight
        self.expandedCardOrder = IslandExpandedCard.restoredOrder(
            from: defaults.stringArray(forKey: DefaultsKey.expandedCardOrder) ?? []
        )
        self.hiddenExpandedCards = Set(
            (defaults.stringArray(forKey: DefaultsKey.hiddenExpandedCards) ?? []).compactMap(IslandExpandedCard.init(rawValue:))
        )

        if defaults.object(forKey: DefaultsKey.hoverToExpand) == nil {
            defaults.set(true, forKey: DefaultsKey.hoverToExpand)
        }
        self.hoverToExpand = defaults.bool(forKey: DefaultsKey.hoverToExpand)

        if defaults.object(forKey: DefaultsKey.dragToExpand) == nil {
            defaults.set(true, forKey: DefaultsKey.dragToExpand)
        }
        self.dragToExpand = defaults.bool(forKey: DefaultsKey.dragToExpand)

        if defaults.object(forKey: DefaultsKey.showCollapsedCustomTitle) == nil {
            defaults.set(false, forKey: DefaultsKey.showCollapsedCustomTitle)
        }
        self.showCollapsedCustomTitle = defaults.bool(forKey: DefaultsKey.showCollapsedCustomTitle)
        self.collapsedCustomTitle = defaults.string(forKey: DefaultsKey.collapsedCustomTitle) ?? "MakeTools"
        let storedCustomWidth = CGFloat(defaults.double(forKey: DefaultsKey.collapsedCustomWidth))
        self.collapsedCustomWidth = storedCustomWidth > 0 ? min(680, max(160, storedCustomWidth)) : 0

        let storedMetrics = defaults.stringArray(forKey: DefaultsKey.collapsedMetrics)
        let selection = CollapsedMetricItem.restoredSelection(from: storedMetrics)
        self.collapsedMetrics = selection
        if storedMetrics == nil || storedMetrics?.contains("networkSpeed") == true {
            defaults.set(CollapsedMetricItem.allCases.filter { selection.contains($0) }.map(\.rawValue),
                         forKey: DefaultsKey.collapsedMetrics)
        }

        for feature in DynamicIslandFeature.allCases {
            featureStates[feature] = feature.initialEnabled(in: defaults, keyPrefix: DefaultsKey.featurePrefix)
        }

        self.lastPasteboardChangeCount = NSPasteboard.general.changeCount
        if isFeatureEnabled(.clipboardHistory),
           let text = ClipboardHelper.historyText(from: .general),
           let entry = IslandClipboardEntry(text: text) {
            self.clipboardEntries = [entry]
        }
        self.latestSnapshot = metricsReader.sample()
    }

    func saveCalendarEvent(_ event: CalendarCountdownEvent) throws {
        var updated = calendarEvents
        if let index = updated.firstIndex(where: { $0.id == event.id }) {
            updated[index] = event
        } else {
            updated.append(event)
        }
        try updateCalendarEvents(updated)
    }

    func removeCalendarEvent(id: UUID) throws {
        try updateCalendarEvents(calendarEvents.filter { $0.id != id })
    }

    private func updateCalendarEvents(_ events: [CalendarCountdownEvent]) throws {
        try calendarStore.save(events)
        calendarEvents = events
        windowController?.refreshContents()
        notifyUpdated()
    }

    // MARK: - Feature Toggles

    public func isFeatureEnabled(_ feature: DynamicIslandFeature) -> Bool {
        featureStates[feature] ?? feature.defaultEnabled
    }

    public func setFeature(_ feature: DynamicIslandFeature, enabled: Bool) {
        featureStates[feature] = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.featurePrefix + feature.rawValue)

        if !enabled {
            if feature == .keepAwake {
                _ = keepAwakeController.setActive(false)
            } else if feature == .focusTimer {
                focusTimer.pause()
                syncFocusTicker()
            } else if feature == .fileShelf {
                endExternalFileDrag(shouldCollapseIfNeeded: false)
            }
        }

        windowController?.syncState(animated: state == .expanded)
        notifyUpdated()
    }

    public func isCollapsedMetricEnabled(_ item: CollapsedMetricItem) -> Bool {
        collapsedMetrics.contains(item)
    }

    public func setCollapsedMetric(_ item: CollapsedMetricItem, enabled: Bool) {
        guard enabled != collapsedMetrics.contains(item) else { return }
        if enabled {
            collapsedMetrics.insert(item)
        } else {
            collapsedMetrics.remove(item)
        }
        collapsedMetricRotation = CollapsedMetricRotation()
        UserDefaults.standard.set(collapsedMetrics.map(\.rawValue), forKey: DefaultsKey.collapsedMetrics)
        windowController?.syncState(animated: state == .collapsed)
        notifyUpdated()
    }

    var currentCollapsedMetric: CollapsedMetricItem? {
        collapsedMetricRotation.current(in: orderedEnabledCollapsedMetrics, uptime: ProcessInfo.processInfo.systemUptime)
    }

    public func collapsedDisplayContent(now: Date = Date()) -> (leftText: String?, rightText: String?) {
        (collapsedStatusText, currentCollapsedMetric.map { latestSnapshot.formatCollapsedMetric($0, now: now) })
    }

    var collapsedStatusText: String? {
        let leftText: String?
        if isFeatureEnabled(.focusTimer), focusTimer.isRunning {
            leftText = L10n.text("island.focus", "专注 {arg1}", ["arg1": String(describing: focusTimer.formattedRemaining)])
        } else if isFeatureEnabled(.keepAwake), isKeepAwakeActive {
            leftText = L10n.text("island.keepingAwake", "防休眠中")
        } else if isFeatureEnabled(.fileShelf), !droppedFiles.isEmpty {
            leftText = L10n.text("island.staged", "{count} 项暂存", ["count": String(describing: droppedFiles.count)])
        } else if showCollapsedCustomTitle {
            let trimmed = collapsedCustomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            leftText = trimmed.isEmpty ? nil : trimmed
        } else {
            leftText = nil
        }

        return leftText
    }

    // MARK: - Lifecycle

    public func startIfEnabled() {
        if isEnabled {
            startLoopAndWindow()
        }
    }

    public func ensureOverlayVisible() {
        if isEnabled {
            windowController?.ensureVisible()
        }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func reloadLocalizedInterface() {
        guard let previous = windowController else { return }
        pendingLanguageRefresh = previous.hasOpenEditor
        guard !pendingLanguageRefresh else { return }
        previous.hideIsland()
        windowController = DynamicIslandWindowController(manager: self)
        if isEnabled { windowController?.showIsland() }
        windowController?.refreshContents()
    }

    public func shutdown() {
        layoutEditor?.close()
        layoutEditor = nil
        focusTimer.pause()
        syncFocusTicker()
        _ = keepAwakeController.setActive(false)
        stopLoopAndWindow()
    }

    private func startLoopAndWindow() {
        if windowController == nil {
            windowController = DynamicIslandWindowController(manager: self)
        }
        windowController?.showIsland()

        installDragMonitors()

        if tickTimer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.handleTick()
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        }

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.windowController?.syncState(animated: false)
            }
        }

        latestSnapshot = metricsReader.sample()
        hasSampledBaseline = false
        windowController?.refreshContents()
    }

    private func stopLoopAndWindow() {
        removeDragMonitors()
        fileDragGesture.mouseUp()
        dragAutoCollapseWorkItem?.cancel()
        dragAutoCollapseWorkItem = nil
        hudDismissWorkItem?.cancel()
        hudDismissWorkItem = nil
        expandedNotice = nil
        tickTimer?.invalidate()
        tickTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        isExternalFileDragActive = false
        expandedByExternalDrag = false
        isPinned = false
        state = .collapsed
        windowController?.setExternalDropHighlight(false)
        windowController?.hideIsland()
    }

    // MARK: - Global File-Drag Auto-Expand

    private func installDragMonitors() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if globalDragMonitor == nil {
            globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
                self?.handleDragEvent(event)
            }
        }
        if localDragMonitor == nil {
            localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.handleDragEvent(event)
                return event
            }
        }
    }

    private func removeDragMonitors() {
        if let globalDragMonitor {
            NSEvent.removeMonitor(globalDragMonitor)
            self.globalDragMonitor = nil
        }
        if let localDragMonitor {
            NSEvent.removeMonitor(localDragMonitor)
            self.localDragMonitor = nil
        }
    }

    private func handleDragEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            windowController?.cancelPendingHoverExpansion()
            // A previous Finder drag can leave its file URLs on this pasteboard.
            fileDragGesture.mouseDown(pasteboardChangeCount: NSPasteboard(name: .drag).changeCount)
        case .leftMouseDragged:
            guard isEnabled, dragToExpand, isFeatureEnabled(.fileShelf),
                  !isInternalDragInProgress, !isExternalFileDragActive,
                  windowController?.isPointerOverPill == true else { return }

            let dragPasteboard = NSPasteboard(name: .drag)
            if fileDragGesture.detectsFileDrag(
                pasteboardChangeCount: dragPasteboard.changeCount,
                leftButtonPressed: (NSEvent.pressedMouseButtons & 1) != 0,
                hasFileURLs: dragPasteboard.canReadObject(
                    forClasses: [NSURL.self],
                    options: [.urlReadingFileURLsOnly: true]
                )
            ) {
                beginExternalFileDrag()
            }
        case .leftMouseUp:
            finishMouseDrag()
        default:
            break
        }
    }

    private func finishMouseDrag() {
        fileDragGesture.mouseUp()
        if isExternalFileDragActive {
            endExternalFileDrag(shouldCollapseIfNeeded: true)
        }
    }

    private func beginExternalFileDrag() {
        dragAutoCollapseWorkItem?.cancel()
        dragAutoCollapseWorkItem = nil
        isExternalFileDragActive = true
        if state != .expanded {
            expandedByExternalDrag = true
            expand()
        }
        windowController?.setExternalDropHighlight(true)
    }

    private func endExternalFileDrag(shouldCollapseIfNeeded: Bool) {
        isExternalFileDragActive = false
        windowController?.setExternalDropHighlight(false)

        guard shouldCollapseIfNeeded, expandedByExternalDrag else {
            expandedByExternalDrag = false
            return
        }
        expandedByExternalDrag = false

        dragAutoCollapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapse(force: false)
        }
        dragAutoCollapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    // MARK: - State Transitions

    public func toggleExpanded() {
        if case .expanded = state {
            collapse(force: true)
        } else {
            expand()
        }
    }

    public func expand() {
        if !isEnabled {
            isEnabled = true
        }
        dragAutoCollapseWorkItem?.cancel()
        dragAutoCollapseWorkItem = nil
        hudDismissWorkItem?.cancel()
        hudDismissWorkItem = nil
        expandedNotice = nil
        state = .expanded
        windowController?.syncState(animated: true)
        notifyUpdated()
    }

    public func collapse(force: Bool = false) {
        if !force {
            guard state == .expanded, !isPinned, !isExternalFileDragActive, !isInternalDragInProgress,
                  windowController?.blocksAutomaticCollapse != true else { return }
        }
        if force {
            isPinned = false
        }
        expandedByExternalDrag = false
        dragAutoCollapseWorkItem?.cancel()
        dragAutoCollapseWorkItem = nil
        hudDismissWorkItem?.cancel()
        hudDismissWorkItem = nil
        expandedNotice = nil
        state = .collapsed
        windowController?.syncState(animated: true)
        notifyUpdated()
    }

    public func togglePin() {
        isPinned.toggle()
        if isPinned && state != .expanded {
            state = .expanded
            windowController?.syncState(animated: true)
        } else {
            windowController?.refreshContents()
        }
        notifyUpdated()
    }

    public func showHUD(
        title: String,
        detail: String,
        symbolName: String = "sparkles",
        duration: TimeInterval = 2.4
    ) {
        if !isEnabled {
            isEnabled = true
        }
        hudDismissWorkItem?.cancel()
        if state == .expanded {
            expandedNotice = (title, detail)
            windowController?.refreshContents()
        } else {
            state = .hud(title: title, detail: detail, symbolName: symbolName)
            windowController?.syncState(animated: true)
        }
        notifyUpdated()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            hudDismissWorkItem = nil
            if case .hud = state {
                state = .collapsed
                windowController?.syncState(animated: true)
            } else if expandedNotice != nil {
                expandedNotice = nil
                windowController?.refreshContents()
            }
            notifyUpdated()
        }
        hudDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    // MARK: - Modular Feature Actions

    public func setVolume(_ value: Float) {
        guard audioController.setVolume(value) else { return }
        if value > 0.01 && latestSnapshot.isMuted {
            _ = audioController.setMuted(false)
        }
        latestSnapshot = metricsReader.sample()
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func toggleMute() {
        let nextMuted = !(audioController.getMuted() ?? latestSnapshot.isMuted)
        guard audioController.setMuted(nextMuted) else { return }
        latestSnapshot = metricsReader.sample()
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func toggleKeepAwake() {
        guard isFeatureEnabled(.keepAwake) else { return }
        let target = !keepAwakeController.isActive
        if keepAwakeController.setActive(target) {
            if state != .expanded {
                showHUD(
                    title: target ? L10n.text("island.keepAwakeOn", "防休眠已开启") : L10n.text("island.keepAwakeOff", "防休眠已关闭"),
                    detail: target ? L10n.text("island.theDisplayWillStayOn", "屏幕将保持常亮") : L10n.text("island.normalDisplaySleepRestored", "恢复系统息屏策略"),
                    symbolName: "cup.and.saucer.fill",
                    duration: 2.0
                )
            } else {
                windowController?.refreshContents()
                notifyUpdated()
            }
        }
    }

    public func setFocusDuration(minutes: Int) {
        focusTimer.setDuration(minutes: minutes)
        syncFocusTicker()
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func toggleFocusTimer() {
        guard isFeatureEnabled(.focusTimer) else { return }
        if focusTimer.isRunning {
            updateFocusTimer()
            if !focusTimer.isRunning { return }
        }
        focusTimer.toggle()
        syncFocusTicker()
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func resetFocusTimer() {
        focusTimer.reset()
        syncFocusTicker()
        windowController?.refreshContents()
        notifyUpdated()
    }

    private func syncFocusTicker() {
        if !focusTimer.isRunning {
            focusDeadline = nil
            focusTickTimer?.invalidate()
            focusTickTimer = nil
        } else if focusTickTimer == nil {
            focusDeadline = ContinuousClock.now.advanced(by: .seconds(focusTimer.remainingSeconds))
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateFocusTimer() }
            timer.tolerance = 0.04
            RunLoop.main.add(timer, forMode: .common)
            focusTickTimer = timer
        }
    }

    private func updateFocusTimer() {
        guard let focusDeadline, focusTimer.isRunning else { return }
        let timeLeft = ContinuousClock.now.duration(to: focusDeadline).components
        let remaining = max(0, Int(timeLeft.seconds) + (timeLeft.attoseconds > 0 ? 1 : 0))
        let elapsed = focusTimer.remainingSeconds - remaining
        guard elapsed > 0 else { return }
        if focusTimer.tick(elapsedSeconds: elapsed) {
            syncFocusTicker()
            NSSound(named: "Glass")?.play()
            if isEnabled {
                showHUD(title: L10n.text("island.focusSessionComplete", "专注完成"),
                        detail: L10n.text("island.takeABreak", "休息一下吧"),
                        symbolName: "checkmark.circle.fill", duration: 3.5)
            }
        }
        if isEnabled { windowController?.refreshContents() }
        notifyUpdated()
    }

    // MARK: - 9-Slot File Shelf

    public func addDroppedFiles(_ urls: [URL]) {
        var addedCount = 0
        for url in urls.reversed() {
            if let existingIdx = droppedFiles.firstIndex(of: url) {
                droppedFiles.remove(at: existingIdx)
            } else {
                addedCount += 1
            }
            droppedFiles.insert(url, at: 0)
        }
        if droppedFiles.count > Self.maxShelfFiles {
            droppedFiles = Array(droppedFiles.prefix(Self.maxShelfFiles))
        }
        selectedFileIndex = 0
        isExternalFileDragActive = false
        expandedByExternalDrag = false
        windowController?.setExternalDropHighlight(false)
        windowController?.refreshContents()

        if addedCount > 0 && state != .expanded {
            let name = urls.first?.lastPathComponent ?? L10n.text("menu.file", "文件")
            showHUD(title: L10n.text("island.filesJustStaged", "已暂存 {count} 项", ["count": String(describing: addedCount)]), detail: name, symbolName: "tray.and.arrow.down.fill", duration: 2.4)
        }
        notifyUpdated()
    }

    public func selectDroppedFile(at index: Int) {
        guard index >= 0 && index < droppedFiles.count else { return }
        selectedFileIndex = index
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func openDroppedFile(at index: Int) {
        guard index >= 0 && index < droppedFiles.count else { return }
        NSWorkspace.shared.open(droppedFiles[index])
    }

    public func openSelectedDroppedFile() {
        if let file = selectedDroppedFile {
            NSWorkspace.shared.open(file)
        }
    }

    public func openFirstDroppedFile() {
        openSelectedDroppedFile()
    }

    public func removeDroppedFile(at index: Int) {
        guard index >= 0 && index < droppedFiles.count else { return }
        droppedFiles.remove(at: index)
        if droppedFiles.isEmpty {
            selectedFileIndex = 0
        } else {
            // Keep the same selected file when an earlier slot shifts left.
            if index < selectedFileIndex { selectedFileIndex -= 1 }
            selectedFileIndex = min(selectedFileIndex, droppedFiles.count - 1)
        }
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func removeSelectedDroppedFile() {
        removeDroppedFile(at: selectedFileIndex)
    }

    public func clearDroppedFiles() {
        droppedFiles.removeAll()
        selectedFileIndex = 0
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func shareDroppedFiles(from anchorView: NSView) {
        let items: [URL]
        if let selected = selectedDroppedFile {
            items = [selected]
        } else {
            items = droppedFiles
        }
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }

    // MARK: - Clipboard History

    public func selectPreviousClipboard() {
        guard clipboardEntries.count > 1 else { return }
        selectClipboardItem(at: (clipboardHistoryIndex + 1) % clipboardEntries.count)
    }

    public func selectNextClipboard() {
        guard clipboardEntries.count > 1 else { return }
        selectClipboardItem(at: (clipboardHistoryIndex - 1 + clipboardEntries.count) % clipboardEntries.count)
    }

    private func selectClipboardItem(at index: Int) {
        guard clipboardHistoryIndex != index else { return }
        clipboardHistoryIndex = index
        windowController?.refreshContents()
        notifyUpdated()
    }

    func copyClipboardItem(id: UUID) {
        guard isFeatureEnabled(.clipboardHistory),
              let index = clipboardEntries.firstIndex(where: { $0.id == id }) else { return }
        writeClipboardEntry(clipboardEntries[index])
        selectClipboardItem(at: index)
    }

    public func copyCurrentClipboardItem() {
        guard clipboardEntries.indices.contains(clipboardHistoryIndex) else { return }
        writeClipboardEntry(clipboardEntries[clipboardHistoryIndex])
    }

    private func writeClipboardEntry(_ entry: IslandClipboardEntry) {
        ClipboardHelper.copyText(entry.text)
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
    }

    public func copyLatestClipboard() {
        copyCurrentClipboardItem()
    }

    public func clearClipboardHistory() {
        clipboardEntries.removeAll()
        clipboardHistoryIndex = 0
        windowController?.refreshContents()
        notifyUpdated()
    }

    public func openMainWindow() {
        onOpenMainWindow?()
    }

    // MARK: - 1s Ticker & Smart Alerts

    private func handleTick() {
        if pendingLanguageRefresh, windowController?.hasOpenEditor == false {
            reloadLocalizedInterface()
        }
        if (NSEvent.pressedMouseButtons & 1) == 0 {
            finishMouseDrag()
        }

        let prev = latestSnapshot
        let next = metricsReader.sample()
        latestSnapshot = next

        if hasSampledBaseline && state != .expanded {
            if isFeatureEnabled(.audioControl) {
                if next.isMuted != prev.isMuted {
                    let pct = next.volumePercentInt ?? 0
                    showHUD(
                        title: next.isMuted ? L10n.text("island.muted", "已静音") : L10n.text("island.unmute", "取消静音"),
                        detail: next.isMuted ? L10n.text("island.systemAudioOutputIsMuted", "系统音频输出已静音") : L10n.text("island.currentVolume", "当前音量 {arg1}%", ["arg1": String(describing: pct)]),
                        symbolName: next.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        duration: 1.8
                    )
                } else if let newVol = next.volume, let oldVol = prev.volume, abs(newVol - oldVol) >= 0.02 {
                    let pct = Int((newVol * 100).rounded())
                    showHUD(
                        title: L10n.text("island.systemVolume", "系统音量 {arg1}%", ["arg1": String(describing: pct)]),
                        detail: next.isMuted ? L10n.text("island.muted", "已静音") : L10n.text("island.audioOutput", "音频输出"),
                        symbolName: pct == 0 ? "speaker.fill" : (pct < 50 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
                        duration: 1.8
                    )
                }
            }

            if isFeatureEnabled(.batteryAlerts), let pct = next.batteryPercent {
                if next.isCharging != prev.isCharging {
                    showHUD(
                        title: next.isCharging ? L10n.text("island.chargingStarted", "开始充电") : L10n.text("island.runningOnBattery", "使用电池供电"),
                        detail: L10n.text("island.currentBattery", "当前电量 {arg1}%", ["arg1": String(describing: pct)]),
                        symbolName: next.isCharging ? "battery.100.bolt" : "battery.75",
                        duration: 2.6
                    )
                } else if !next.isCharging && pct <= 20 && (prev.batteryPercent ?? 100) > 20 {
                    showHUD(
                        title: L10n.text("island.lowBattery", "电量不足 {arg1}%", ["arg1": String(describing: pct)]),
                        detail: L10n.text("island.connectThePowerAdapter", "请及时连接电源适配器"),
                        symbolName: "battery.25",
                        duration: 3.2
                    )
                }
            }
        }
        hasSampledBaseline = true

        let currentChange = NSPasteboard.general.changeCount
        if currentChange != lastPasteboardChangeCount {
            lastPasteboardChangeCount = currentChange
            if isFeatureEnabled(.clipboardHistory),
               let text = ClipboardHelper.historyText(from: .general),
               let entry = IslandClipboardEntry(text: text) {
                clipboardEntries.removeAll { $0.text == text }
                clipboardEntries.insert(entry, at: 0)
                if clipboardEntries.count > 8 { clipboardEntries.removeLast() }
                clipboardHistoryIndex = 0
                if state != .expanded {
                    showHUD(title: L10n.text("island.copied", "已复制"), detail: entry.preview, symbolName: "doc.on.clipboard.fill", duration: 2.2)
                }
            }
        }

        windowController?.refreshContents()
        notifyUpdated()
    }

    private func notifyUpdated() {
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
    }
}
