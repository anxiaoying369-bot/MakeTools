import AppKit
import Darwin
import QuickLookUI

public final class InstallationTool: ToolModule {
    public let id = "installation-guide"
    public let title = "安装与引导"
    public let subtitle = "应用安装与环境检测"
    public let symbolName = "arrow.down.app"

    public init() {}

    public func makeViewController() -> NSViewController {
        InstallationViewController()
    }
}

private final class FlippedInstallationContainer: NSView {
    override var isFlipped: Bool { true }
}

private enum StatusTone {
    case ready
    case attention
    case neutral
    case error

    var fillColor: NSColor {
        switch self {
        case .ready:
            return NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.systemGreen.withAlphaComponent(dark ? 0.24 : 0.14)
            }
        case .attention:
            return NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.systemOrange.withAlphaComponent(dark ? 0.25 : 0.15)
            }
        case .neutral:
            return NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.labelColor.withAlphaComponent(dark ? 0.12 : 0.07)
            }
        case .error:
            return NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.systemRed.withAlphaComponent(dark ? 0.25 : 0.14)
            }
        }
    }

    var textColor: NSColor {
        switch self {
        case .ready: return .systemGreen
        case .attention: return .systemOrange
        case .neutral: return .secondaryLabelColor
        case .error: return .systemRed
        }
    }

    var symbolName: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .neutral: return "circle.dashed"
        case .error: return "xmark.circle.fill"
        }
    }
}

private final class StatusPillView: NSView {
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var tone: StatusTone = .neutral

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        translatesAutoresizingMaskIntoConstraints = false

        iconView.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        iconView.setAccessibilityElement(false)

        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [iconView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
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
        layer?.cornerRadius = bounds.height / 2
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tone.fillColor.cgColor
        }
    }

    func update(text: String, tone: StatusTone) {
        self.tone = tone
        label.stringValue = text
        label.textColor = tone.textColor
        iconView.image = NSImage(systemSymbolName: tone.symbolName, accessibilityDescription: nil)
        iconView.contentTintColor = tone.textColor
        needsDisplay = true
    }
}

private final class DashedWellView: NSView {
    var isHighlightedTarget = false {
        didSet {
            if oldValue != isHighlightedTarget {
                needsDisplay = true
            }
        }
    }
    var isHovered = false {
        didSet {
            if oldValue != isHovered {
                needsDisplay = true
            }
        }
    }
    var isReadyState = false {
        didSet {
            if oldValue != isReadyState {
                needsDisplay = true
            }
        }
    }
    var useDashedBorder = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let insetRect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 16, yRadius: 16)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let fillColor: NSColor
        let strokeColor: NSColor
        if isHighlightedTarget {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.24 : 0.14)
            strokeColor = NSColor.controlAccentColor
        } else if isReadyState {
            fillColor = NSColor.systemGreen.withAlphaComponent(isDark ? 0.16 : 0.09)
            strokeColor = NSColor.systemGreen.withAlphaComponent(0.55)
        } else if isHovered {
            fillColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.14 : 0.08)
            strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.55)
        } else {
            fillColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.05 : 0.03)
            strokeColor = NSColor.separatorColor.withAlphaComponent(isDark ? 0.65 : 0.85)
        }

        fillColor.setFill()
        path.fill()

        strokeColor.setStroke()
        path.lineWidth = isHighlightedTarget ? 2.0 : 1.25
        if useDashedBorder && !isHighlightedTarget && !isReadyState {
            let pattern: [CGFloat] = [5, 4]
            path.setLineDash(pattern, count: pattern.count, phase: 0)
        }
        path.stroke()
    }
}

private final class DraggableAppTileView: NSView, NSDraggingSource {
    var appURL: URL = Bundle.main.bundleURL {
        didSet { updateIcon() }
    }
    var isDraggingEnabled = true
    var onDragStateChanged: ((Bool) -> Void)?
    var onExternalDragFinished: (() -> Void)?

    private let well = DashedWellView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "MakeTools.app")
    private let captionLabel = NSTextField(labelWithString: "按住拖动到右侧")
    private var mouseDownPoint: NSPoint?
    private var didStartDrag = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(iconView)
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 88),
            well.heightAnchor.constraint(equalToConstant: 88),
            iconView.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64)
        ])

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.alignment = .center

        captionLabel.font = .systemFont(ofSize: 11)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center

        let stack = NSStackView(views: [well, titleLabel, captionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 132)
        ])

        updateIcon()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(appURL: URL, isAlreadyInApplications: Bool) {
        self.appURL = appURL
        self.isDraggingEnabled = !isAlreadyInApplications
        well.isReadyState = isAlreadyInApplications
        captionLabel.stringValue = isAlreadyInApplications ? "已在「应用程序」中" : "按住拖动到右侧或访达"
        toolTip = isAlreadyInApplications
            ? appURL.path
            : "按住 MakeTools 图标，拖到右侧「应用程序」或访达「应用程序」窗口中"
    }

    private func updateIcon() {
        let chosen: NSImage
        if appURL.pathExtension.lowercased() == "app" {
            chosen = NSWorkspace.shared.icon(forFile: appURL.path)
        } else if let appIcon = NSApp.applicationIconImage {
            chosen = appIcon
        } else {
            chosen = NSWorkspace.shared.icon(forFile: appURL.path)
        }
        chosen.size = NSSize(width: 64, height: 64)
        iconView.image = chosen
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isDraggingEnabled {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard isDraggingEnabled else { return }
        well.isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        if well.isHovered {
            well.isHovered = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isDraggingEnabled else { return }
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingEnabled, !didStartDrag, let start = mouseDownPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        guard distance >= 4 else { return }
        didStartDrag = true

        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let icon = iconView.image ?? NSApp.applicationIconImage ?? NSImage()
        let frameInSelf = NSRect(x: current.x - 32, y: current.y - 32, width: 64, height: 64)
        item.setDraggingFrame(frameInSelf, contents: icon)

        onDragStateChanged?(true)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        didStartDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move] : [.copy]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownPoint = nil
        didStartDrag = false
        onDragStateChanged?(false)
        if operation != [] {
            onExternalDragFinished?()
        }
    }
}

private final class ApplicationsDropTileView: NSView {
    var onDropApp: ((URL) -> Void)?
    var onClickOpenApplications: (() -> Void)?

    private let well = DashedWellView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "应用程序")
    private let captionLabel = NSTextField(labelWithString: "拖到这里松开 · 点击打开")
    private var isReadyState = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])

        well.useDashedBorder = true

        let appsIcon = NSWorkspace.shared.icon(forFile: "/Applications")
        appsIcon.size = NSSize(width: 64, height: 64)
        iconView.image = appsIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        well.addSubview(iconView)
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 88),
            well.heightAnchor.constraint(equalToConstant: 88),
            iconView.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64)
        ])

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.alignment = .center

        captionLabel.font = .systemFont(ofSize: 11)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.alignment = .center

        let stack = NSStackView(views: [well, titleLabel, captionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 132)
        ])

        toolTip = "将 MakeTools.app 拖到此处安装，或点击打开「应用程序」文件夹"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(isInstalledRunning: Bool, isDragging: Bool) {
        isReadyState = isInstalledRunning
        well.isReadyState = isInstalledRunning
        if well.isHighlightedTarget {
            captionLabel.stringValue = "松开以安装到「应用程序」"
            captionLabel.textColor = .controlAccentColor
        } else if isDragging {
            captionLabel.stringValue = "拖到这里松开即可安装"
            captionLabel.textColor = .controlAccentColor
        } else if isInstalledRunning {
            captionLabel.stringValue = "/Applications · 已就绪"
            captionLabel.textColor = .systemGreen
        } else {
            captionLabel.stringValue = "拖到这里松开 · 点击打开"
            captionLabel.textColor = .secondaryLabelColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        well.isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        if well.isHovered {
            well.isHovered = false
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClickOpenApplications?()
        }
    }

    private func draggedAppURL(from info: NSDraggingInfo) -> URL? {
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = info.draggingPasteboard.readObjects(forClasses: classes, options: options) as? [URL] else {
            return nil
        }
        return urls.first { $0.pathExtension.lowercased() == "app" }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedAppURL(from: sender) != nil else { return [] }
        well.isHighlightedTarget = true
        captionLabel.stringValue = "松开以安装到「应用程序」"
        captionLabel.textColor = .controlAccentColor
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedAppURL(from: sender) != nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        well.isHighlightedTarget = false
        update(isInstalledRunning: isReadyState, isDragging: false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        well.isHighlightedTarget = false
        guard let appURL = draggedAppURL(from: sender) else { return false }
        update(isInstalledRunning: isReadyState, isDragging: false)
        onDropApp?(appURL)
        return true
    }
}

private final class DragInstallStageView: NSView {
    var onDropIntoApplications: ((URL) -> Void)?
    var onClickApplicationsFolder: (() -> Void)?
    var onExternalDragFinished: (() -> Void)?

    private let surface: ToolSurfaceView
    private let appTile = DraggableAppTileView()
    private let arrowIcon = NSImageView()
    private let arrowCaption = NSTextField(labelWithString: "拖入安装")
    private let applicationsTile = ApplicationsDropTileView()
    private var isInstalledRunning = false

    override init(frame frameRect: NSRect) {
        surface = ToolSurfaceView(
            fill: NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return dark
                    ? NSColor.white.withAlphaComponent(0.035)
                    : NSColor.black.withAlphaComponent(0.024)
            },
            radius: 14,
            border: NSColor.separatorColor
        )
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        arrowIcon.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        arrowIcon.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        arrowIcon.contentTintColor = .controlAccentColor
        arrowIcon.setAccessibilityElement(false)

        arrowCaption.font = .systemFont(ofSize: 11.5, weight: .medium)
        arrowCaption.textColor = .secondaryLabelColor
        arrowCaption.alignment = .center

        let centerStack = NSStackView(views: [arrowIcon, arrowCaption])
        centerStack.orientation = .vertical
        centerStack.alignment = .centerX
        centerStack.spacing = 6
        centerStack.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [appTile, centerStack, applicationsTile])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 24
        row.translatesAutoresizingMaskIntoConstraints = false

        surface.addSubview(row)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),

            row.topAnchor.constraint(equalTo: surface.topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -18),
            row.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: surface.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -16),

            centerStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 78)
        ])

        appTile.onDragStateChanged = { [weak self] dragging in
            guard let self else { return }
            self.applicationsTile.update(isInstalledRunning: self.isInstalledRunning, isDragging: dragging)
            self.arrowCaption.textColor = dragging ? .controlAccentColor : .secondaryLabelColor
        }
        appTile.onExternalDragFinished = { [weak self] in
            self?.onExternalDragFinished?()
        }
        applicationsTile.onDropApp = { [weak self] url in
            self?.onDropIntoApplications?(url)
        }
        applicationsTile.onClickOpenApplications = { [weak self] in
            self?.onClickApplicationsFolder?()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(runningAppURL: URL, installStatus: AppInstallStatus) {
        isInstalledRunning = installStatus.isRunningFromApplications
        appTile.update(appURL: runningAppURL, isAlreadyInApplications: isInstalledRunning)
        applicationsTile.update(isInstalledRunning: isInstalledRunning, isDragging: false)

        switch installStatus {
        case .runningFromApplications:
            arrowIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            arrowIcon.contentTintColor = .systemGreen
            arrowCaption.stringValue = "已完成安装"
            arrowCaption.textColor = .systemGreen
        case .updateAvailable:
            arrowIcon.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
            arrowIcon.contentTintColor = .controlAccentColor
            arrowCaption.stringValue = "拖入覆盖更新"
            arrowCaption.textColor = .secondaryLabelColor
        case .installedSameOrNewer:
            arrowIcon.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
            arrowIcon.contentTintColor = .controlAccentColor
            arrowCaption.stringValue = "已在右侧目录"
            arrowCaption.textColor = .secondaryLabelColor
        case .translocated, .notInstalled:
            arrowIcon.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
            arrowIcon.contentTintColor = .controlAccentColor
            arrowCaption.stringValue = "拖入安装"
            arrowCaption.textColor = .secondaryLabelColor
        }
    }
}

public final class InstallationViewController: NSViewController, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public var onNavigateToTool: ((String) -> Void)?

    private let service: InstallationService
    private var snapshot: InstallationSnapshot?
    private var dynamicIslandObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var isInstallingApp = false
    private var isRegisteringQuickLook = false
    private var pendingRelaunchURL: URL?
    private var previewItemURL: URL?
    private var applicationsDirFD: Int32 = -1
    private var applicationsWatcher: DispatchSourceFileSystemObject?

    // Overview card controls
    private let overviewPill = StatusPillView()
    private let progressTitleLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let envMetaLabel = NSTextField(wrappingLabelWithString: "")
    private let runningPathLabel = NSTextField(wrappingLabelWithString: "")
    private let completeOnboardingButton = NSButton(title: "完成引导，开始使用", target: nil, action: nil)

    // Step 1: App installation controls
    private let installPill = StatusPillView()
    private let dragInstallStage = DragInstallStageView()
    private let installSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let legacyNoticeLabel = NSTextField(wrappingLabelWithString: "")
    private let installSpinner = NSProgressIndicator()
    private let installFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let installFeedbackRow = NSStackView()
    private let installPrimaryButton = NSButton(title: "选择目录直接安装", target: nil, action: nil)
    private let relaunchButton = NSButton(title: "从「应用程序」启动", target: nil, action: nil)
    private let openApplicationsButton = NSButton(title: "打开访达手动拖入", target: nil, action: nil)
    private let copyInstallCommandButton = NSButton(title: "复制终端安装命令", target: nil, action: nil)

    // Step 2: Quick Look extension controls
    private let quickLookPill = StatusPillView()
    private let quickLookBadgeLabel = NSTextField(wrappingLabelWithString: "")
    private let quickLookDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let quickLookDuplicateNoticeLabel = NSTextField(wrappingLabelWithString: "")
    private let quickLookSpinner = NSProgressIndicator()
    private let quickLookFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let quickLookFeedbackRow = NSStackView()
    private let registerQuickLookButton = NSButton(title: "注册扩展并刷新缓存", target: nil, action: nil)
    private let openExtensionsButton = NSButton(title: "打开系统扩展设置", target: nil, action: nil)
    private let previewDemoButton = NSButton(title: "预览示例 Markdown", target: nil, action: nil)
    private let copyVerifyCommandButton = NSButton(title: "复制校验命令", target: nil, action: nil)

    // Step 3: Login item, Dynamic Island & Ad-hoc note controls
    private let loginItemPill = StatusPillView()
    private let loginItemDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let loginItemSwitch = NSSwitch()
    private let loginItemFeedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let openLoginItemsButton = NSButton(title: "打开系统登录项设置", target: nil, action: nil)
    private let islandSwitch = NSSwitch()
    private let islandStatusDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let copyQuarantineCommandButton = NSButton(title: "复制解除隔离命令", target: nil, action: nil)

    public init(service: InstallationService = .shared) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var nibName: NSNib.Name? { nil }
    public override var acceptsFirstResponder: Bool { true }

    deinit {
        stopApplicationsWatcher()
        if let dynamicIslandObserver {
            NotificationCenter.default.removeObserver(dynamicIslandObserver)
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }

    public override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let container = FlippedInstallationContainer()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 32, bottom: 36, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = ToolAppearance.header(
            title: "安装与引导",
            subtitle: "将 MakeTools 安装到「应用程序」、注册访达 Quick Look 扩展，并一键检查常用系统配置。",
            symbol: "arrow.down.app"
        )

        let overviewCard = buildOverviewCard()
        let installCard = buildAppInstallCard()
        let quickLookCard = buildQuickLookCard()
        let runtimeCard = buildRuntimeSetupCard()

        stack.addArrangedSubview(header)
        stack.setCustomSpacing(24, after: header)
        stack.addArrangedSubview(overviewCard)
        stack.addArrangedSubview(installCard)
        stack.addArrangedSubview(quickLookCard)
        stack.addArrangedSubview(runtimeCard)

        for item in [header, overviewCard, installCard, quickLookCard, runtimeCard] {
            item.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64).isActive = true
        }

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

    public override func viewDidLoad() {
        super.viewDidLoad()
        refreshSnapshot()

        dynamicIslandObserver = NotificationCenter.default.addObserver(
            forName: DynamicIslandManager.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncDynamicIslandRow()
            self?.refreshProgressHeaderOnly()
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshSnapshot()
        }
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        startApplicationsWatcher()
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        stopApplicationsWatcher()
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.dataSource === self {
            panel.orderOut(nil)
        }
    }

    private func startApplicationsWatcher() {
        guard applicationsWatcher == nil else { return }
        let fd = open("/Applications", O_EVTONLY)
        guard fd >= 0 else { return }
        applicationsDirFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refreshSnapshot()
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        applicationsWatcher = source
        source.resume()
    }

    private func stopApplicationsWatcher() {
        if let watcher = applicationsWatcher {
            watcher.cancel()
            applicationsWatcher = nil
            applicationsDirFD = -1
        } else if applicationsDirFD >= 0 {
            close(applicationsDirFD)
            applicationsDirFD = -1
        }
    }

    // MARK: - Card Builders

    private func makeCard(title: String, symbol: String, accessoryViews: [NSView] = [], bodyViews: [NSView]) -> NSView {
        let card = ToolSurfaceView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 12
        inner.translatesAutoresizingMaskIntoConstraints = false

        let titleView = ToolAppearance.sectionTitle(title, symbol: symbol)
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(titleView)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(spacer)

        for accessory in accessoryViews {
            headerRow.addArrangedSubview(accessory)
        }

        inner.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        for view in bodyViews {
            inner.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
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

    private func makeButtonRow(_ buttons: [NSButton]) -> NSView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrapper.topAnchor),
            row.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func configureWrappingLabel(_ label: NSTextField, size: CGFloat = 13, color: NSColor = .labelColor) {
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func buildOverviewCard() -> NSView {
        let refreshButton = NSButton(title: "重新检测", target: self, action: #selector(handleRefresh(_:)))
        ToolAppearance.configure(refreshButton, symbol: "arrow.clockwise")
        refreshButton.controlSize = .small

        progressTitleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        progressTitleLabel.isSelectable = true

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 3
        progressBar.controlSize = .small
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        envMetaLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        envMetaLabel.textColor = .secondaryLabelColor
        envMetaLabel.isSelectable = true
        envMetaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        runningPathLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        runningPathLabel.textColor = .secondaryLabelColor
        runningPathLabel.isSelectable = true
        runningPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        completeOnboardingButton.target = self
        completeOnboardingButton.action = #selector(handleCompleteOnboarding(_:))
        ToolAppearance.configure(completeOnboardingButton, symbol: "checkmark.circle")
        completeOnboardingButton.bezelColor = .controlAccentColor

        let islandButton = NSButton(title: "灵动岛设置", target: self, action: #selector(handleOpenDynamicIsland(_:)))
        ToolAppearance.configure(islandButton, symbol: "rectangle.topthird.inset.filled")

        let markdownButton = NSButton(title: "Markdown 预览", target: self, action: #selector(handleOpenMarkdown(_:)))
        ToolAppearance.configure(markdownButton, symbol: "doc.richtext")

        let quickNavRow = makeButtonRow([completeOnboardingButton, islandButton, markdownButton])

        return makeCard(
            title: "环境检测与进度",
            symbol: "checkmark.shield",
            accessoryViews: [overviewPill, refreshButton],
            bodyViews: [progressTitleLabel, progressBar, envMetaLabel, runningPathLabel, quickNavRow]
        )
    }

    private func buildAppInstallCard() -> NSView {
        dragInstallStage.onDropIntoApplications = { [weak self] _ in
            self?.promptAndInstallIntoApplications()
        }
        dragInstallStage.onClickApplicationsFolder = { [weak self] in
            self?.handleOpenApplicationsFolder(nil)
        }
        dragInstallStage.onExternalDragFinished = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refreshSnapshot()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                self?.refreshSnapshot()
            }
        }

        configureWrappingLabel(installSummaryLabel, size: 13, color: .labelColor)
        configureWrappingLabel(legacyNoticeLabel, size: 12, color: .systemOrange)
        legacyNoticeLabel.isHidden = true

        installSpinner.style = .spinning
        installSpinner.controlSize = .small
        installSpinner.isDisplayedWhenStopped = false

        configureWrappingLabel(installFeedbackLabel, size: 12, color: .secondaryLabelColor)

        installFeedbackRow.orientation = .horizontal
        installFeedbackRow.alignment = .centerY
        installFeedbackRow.spacing = 8
        installFeedbackRow.addArrangedSubview(installSpinner)
        installFeedbackRow.addArrangedSubview(installFeedbackLabel)
        installFeedbackRow.isHidden = true

        openApplicationsButton.target = self
        openApplicationsButton.action = #selector(handleOpenApplicationsFolder(_:))
        ToolAppearance.configure(openApplicationsButton, symbol: "folder")

        installPrimaryButton.target = self
        installPrimaryButton.action = #selector(handleInstallPrimary(_:))
        ToolAppearance.configure(installPrimaryButton, symbol: "arrow.down.app")

        relaunchButton.target = self
        relaunchButton.action = #selector(handleRelaunchFromApplications(_:))
        ToolAppearance.configure(relaunchButton, symbol: "arrow.uturn.forward.circle")
        relaunchButton.isHidden = true

        copyInstallCommandButton.target = self
        copyInstallCommandButton.action = #selector(handleCopyInstallCommand(_:))
        ToolAppearance.configureCopy(copyInstallCommandButton, symbol: "terminal")

        let primaryRow = makeButtonRow([openApplicationsButton, relaunchButton])
        let secondaryRow = makeButtonRow([installPrimaryButton, copyInstallCommandButton])

        let sandboxNote = NSTextField(wrappingLabelWithString: "拖入方式：可直接按住上方 MakeTools 图标拖入右侧「应用程序」完成安装，或拖出窗口放入访达的「应用程序」文件夹；拖入访达后本页面会自动检测完成状态。")
        configureWrappingLabel(sandboxNote, size: 11.5, color: .secondaryLabelColor)

        return makeCard(
            title: "步骤 1 · 拖动应用到「应用程序」",
            symbol: "square.and.arrow.down",
            accessoryViews: [installPill],
            bodyViews: [dragInstallStage, installSummaryLabel, legacyNoticeLabel, installFeedbackRow, primaryRow, secondaryRow, sandboxNote]
        )
    }

    private func buildQuickLookCard() -> NSView {
        quickLookBadgeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        quickLookBadgeLabel.textColor = .secondaryLabelColor
        quickLookBadgeLabel.isSelectable = true
        quickLookBadgeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureWrappingLabel(quickLookDetailLabel, size: 13, color: .labelColor)
        configureWrappingLabel(quickLookDuplicateNoticeLabel, size: 12, color: .systemOrange)
        quickLookDuplicateNoticeLabel.isHidden = true

        quickLookSpinner.style = .spinning
        quickLookSpinner.controlSize = .small
        quickLookSpinner.isDisplayedWhenStopped = false

        configureWrappingLabel(quickLookFeedbackLabel, size: 12, color: .secondaryLabelColor)
        quickLookFeedbackRow.orientation = .horizontal
        quickLookFeedbackRow.alignment = .centerY
        quickLookFeedbackRow.spacing = 8
        quickLookFeedbackRow.addArrangedSubview(quickLookSpinner)
        quickLookFeedbackRow.addArrangedSubview(quickLookFeedbackLabel)
        quickLookFeedbackRow.isHidden = true

        registerQuickLookButton.target = self
        registerQuickLookButton.action = #selector(handleRegisterQuickLook(_:))
        ToolAppearance.configure(registerQuickLookButton, symbol: "arrow.triangle.2.circlepath")

        openExtensionsButton.target = self
        openExtensionsButton.action = #selector(handleOpenExtensionsSettings(_:))
        ToolAppearance.configure(openExtensionsButton, symbol: "gearshape")

        previewDemoButton.target = self
        previewDemoButton.action = #selector(handlePreviewDemoQuickLook(_:))
        ToolAppearance.configure(previewDemoButton, symbol: "eye")

        copyVerifyCommandButton.target = self
        copyVerifyCommandButton.action = #selector(handleCopyVerifyCommand(_:))
        ToolAppearance.configureCopy(copyVerifyCommandButton, symbol: "doc.on.doc")

        let row1 = makeButtonRow([registerQuickLookButton, openExtensionsButton])
        let row2 = makeButtonRow([previewDemoButton, copyVerifyCommandButton])

        return makeCard(
            title: "步骤 2 · 访达 Markdown 快速预览",
            symbol: "doc.richtext",
            accessoryViews: [quickLookPill],
            bodyViews: [quickLookBadgeLabel, quickLookDetailLabel, quickLookDuplicateNoticeLabel, quickLookFeedbackRow, row1, row2]
        )
    }

    private func buildRuntimeSetupCard() -> NSView {
        // Row A: Launch at login
        let loginTitle = NSTextField(labelWithString: "开机自动启动")
        loginTitle.font = .systemFont(ofSize: 13, weight: .medium)
        loginTitle.isSelectable = true

        let loginTitleSpacer = NSView()
        loginTitleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let loginTitleRow = NSStackView(views: [loginTitle, loginItemPill, loginTitleSpacer])
        loginTitleRow.orientation = .horizontal
        loginTitleRow.alignment = .centerY
        loginTitleRow.spacing = 8

        configureWrappingLabel(loginItemDetailLabel, size: 12, color: .secondaryLabelColor)

        let loginTextStack = NSStackView(views: [loginTitleRow, loginItemDetailLabel])
        loginTextStack.orientation = .vertical
        loginTextStack.alignment = .leading
        loginTextStack.spacing = 3
        loginTextStack.translatesAutoresizingMaskIntoConstraints = false
        loginItemDetailLabel.widthAnchor.constraint(equalTo: loginTextStack.widthAnchor).isActive = true

        loginItemSwitch.controlSize = .small
        loginItemSwitch.target = self
        loginItemSwitch.action = #selector(handleLoginItemSwitchChanged(_:))
        loginItemSwitch.setAccessibilityLabel("开机自动启动")
        loginItemSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let loginSpacer = NSView()
        loginSpacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        let loginRow = NSStackView(views: [loginTextStack, loginSpacer, loginItemSwitch])
        loginRow.orientation = .horizontal
        loginRow.alignment = .centerY
        loginRow.spacing = 12
        loginRow.translatesAutoresizingMaskIntoConstraints = false

        configureWrappingLabel(loginItemFeedbackLabel, size: 12, color: .systemOrange)
        loginItemFeedbackLabel.isHidden = true

        openLoginItemsButton.target = self
        openLoginItemsButton.action = #selector(handleOpenLoginItemsSettings(_:))
        ToolAppearance.configure(openLoginItemsButton, symbol: "gearshape")
        openLoginItemsButton.controlSize = .small
        let loginSettingsRow = makeButtonRow([openLoginItemsButton])

        let divider1 = NSBox()
        divider1.boxType = .separator

        // Row B: Dynamic Island quick toggle
        let islandTitle = NSTextField(labelWithString: "启用系统灵动岛")
        islandTitle.font = .systemFont(ofSize: 13, weight: .medium)
        islandTitle.isSelectable = true

        configureWrappingLabel(islandStatusDetailLabel, size: 12, color: .secondaryLabelColor)

        let islandTextStack = NSStackView(views: [islandTitle, islandStatusDetailLabel])
        islandTextStack.orientation = .vertical
        islandTextStack.alignment = .leading
        islandTextStack.spacing = 3
        islandTextStack.translatesAutoresizingMaskIntoConstraints = false
        islandStatusDetailLabel.widthAnchor.constraint(equalTo: islandTextStack.widthAnchor).isActive = true

        islandSwitch.controlSize = .small
        islandSwitch.target = self
        islandSwitch.action = #selector(handleIslandSwitchChanged(_:))
        islandSwitch.setAccessibilityLabel("启用系统灵动岛")
        islandSwitch.setContentHuggingPriority(.required, for: .horizontal)

        let islandSpacer = NSView()
        islandSpacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        let islandRow = NSStackView(views: [islandTextStack, islandSpacer, islandSwitch])
        islandRow.orientation = .horizontal
        islandRow.alignment = .centerY
        islandRow.spacing = 12
        islandRow.translatesAutoresizingMaskIntoConstraints = false

        let divider2 = NSBox()
        divider2.boxType = .separator

        // Row C: Ad-hoc signing tip
        let adHocTitle = NSTextField(labelWithString: "关于 Ad-hoc 签名与首次打开提示")
        adHocTitle.font = .systemFont(ofSize: 12.5, weight: .medium)
        adHocTitle.isSelectable = true

        let adHocBody = NSTextField(wrappingLabelWithString: "GitHub Releases 分发包采用 Ad-hoc 签名，未经 Apple 公证。如在另一台 Mac 解压后被系统拦截，可右键点击 MakeTools.app 选择「打开」，或在终端移除隔离属性。")
        configureWrappingLabel(adHocBody, size: 12, color: .secondaryLabelColor)

        copyQuarantineCommandButton.target = self
        copyQuarantineCommandButton.action = #selector(handleCopyQuarantineCommand(_:))
        ToolAppearance.configureCopy(copyQuarantineCommandButton, symbol: "doc.on.doc")
        copyQuarantineCommandButton.controlSize = .small
        let quarantineRow = makeButtonRow([copyQuarantineCommandButton])

        return makeCard(
            title: "步骤 3 · 启动与运行配置",
            symbol: "sparkles",
            bodyViews: [
                loginRow,
                loginItemFeedbackLabel,
                loginSettingsRow,
                divider1,
                islandRow,
                divider2,
                adHocTitle,
                adHocBody,
                quarantineRow
            ]
        )
    }

    // MARK: - State Sync

    public func refreshSnapshot() {
        let current = service.makeSnapshot(dynamicIslandEnabled: DynamicIslandManager.shared.isEnabled)
        snapshot = current
        applySnapshot(current)
    }

    private func refreshProgressHeaderOnly() {
        guard let current = snapshot else { return }
        let updated = InstallationSnapshot(
            runningAppURL: current.runningAppURL,
            runningVersion: current.runningVersion,
            osVersion: current.osVersion,
            architecture: current.architecture,
            installStatus: current.installStatus,
            legacyAppURL: current.legacyAppURL,
            quickLook: current.quickLook,
            loginItemState: current.loginItemState,
            dynamicIslandEnabled: DynamicIslandManager.shared.isEnabled
        )
        snapshot = updated
        applyOverview(updated)
    }

    private func applySnapshot(_ snap: InstallationSnapshot) {
        applyOverview(snap)
        applyInstallCard(snap)
        applyQuickLookCard(snap)
        applyLoginItemRow(snap.loginItemState)
        syncDynamicIslandRow()
    }

    private func applyOverview(_ snap: InstallationSnapshot) {
        let progress = snap.progress
        progressTitleLabel.stringValue = progress.title
        progressBar.maxValue = Double(progress.totalSteps)
        progressBar.doubleValue = Double(progress.completedSteps)

        if progress.completedSteps >= progress.totalSteps {
            overviewPill.update(text: "已全部就绪", tone: .ready)
        } else if progress.isCoreReady {
            overviewPill.update(text: "\(progress.completedSteps)/\(progress.totalSteps) 已就绪", tone: .ready)
        } else {
            overviewPill.update(text: "\(progress.completedSteps)/\(progress.totalSteps) 待配置", tone: .attention)
        }

        envMetaLabel.stringValue = "当前版本：\(snap.runningVersion.displayString)  ·  系统：\(snap.osVersion)  ·  架构：\(snap.architecture)"
        runningPathLabel.stringValue = "运行位置：\(snap.runningAppURL.path)"

        let alreadyDismissed = service.preferences.dismissedOnboardingVersion == snap.runningVersion.shortVersion
        if snap.installStatus.isRunningFromApplications || alreadyDismissed {
            completeOnboardingButton.title = "进入 MakeTools"
            completeOnboardingButton.bezelColor = nil
        } else {
            completeOnboardingButton.title = "完成引导，开始使用"
            completeOnboardingButton.bezelColor = .controlAccentColor
        }
    }

    private func applyInstallCard(_ snap: InstallationSnapshot) {
        let status = snap.installStatus
        dragInstallStage.update(runningAppURL: snap.runningAppURL, installStatus: status)
        installSummaryLabel.stringValue = status.summaryText

        switch status {
        case .runningFromApplications:
            installPill.update(text: status.badgeText, tone: .ready)
            openApplicationsButton.title = "打开「应用程序」目录"
            openApplicationsButton.bezelColor = nil
            installPrimaryButton.title = "在访达中显示应用"
            ToolAppearance.configure(installPrimaryButton, symbol: "folder")
            installPrimaryButton.bezelColor = nil
            relaunchButton.isHidden = true
        case .updateAvailable:
            installPill.update(text: status.badgeText, tone: .attention)
            openApplicationsButton.title = "打开访达手动拖入"
            openApplicationsButton.bezelColor = .controlAccentColor
            installPrimaryButton.title = "选择目录覆盖更新"
            ToolAppearance.configure(installPrimaryButton, symbol: "arrow.down.app")
            installPrimaryButton.bezelColor = nil
            relaunchButton.title = "启动已安装版本"
            relaunchButton.isHidden = false
        case .installedSameOrNewer:
            installPill.update(text: status.badgeText, tone: .attention)
            openApplicationsButton.title = "打开「应用程序」目录"
            openApplicationsButton.bezelColor = nil
            installPrimaryButton.title = "重新覆盖安装"
            ToolAppearance.configure(installPrimaryButton, symbol: "arrow.down.app")
            installPrimaryButton.bezelColor = nil
            relaunchButton.title = "从「应用程序」启动"
            relaunchButton.bezelColor = .controlAccentColor
            relaunchButton.isHidden = false
        case .translocated, .notInstalled:
            installPill.update(text: status.badgeText, tone: .attention)
            openApplicationsButton.title = "打开访达手动拖入"
            openApplicationsButton.bezelColor = .controlAccentColor
            installPrimaryButton.title = "选择目录直接安装"
            ToolAppearance.configure(installPrimaryButton, symbol: "arrow.down.app")
            installPrimaryButton.bezelColor = nil
            relaunchButton.bezelColor = nil
            relaunchButton.isHidden = (pendingRelaunchURL == nil)
            if pendingRelaunchURL != nil {
                relaunchButton.title = "从「应用程序」启动"
            }
        }

        if let legacy = snap.legacyAppURL {
            legacyNoticeLabel.stringValue = "检测到旧版独立应用 \(legacy.path)，执行一键安装时会自动清理并替换。"
            legacyNoticeLabel.isHidden = false
        } else {
            legacyNoticeLabel.isHidden = true
        }

        installPrimaryButton.isEnabled = !isInstallingApp
        relaunchButton.isEnabled = !isInstallingApp
    }

    private func applyQuickLookCard(_ snap: InstallationSnapshot) {
        let ql = snap.quickLook
        let tone: StatusTone
        if !ql.hasEmbeddedExtension {
            tone = .error
        } else if ql.registeredForCurrentTarget {
            tone = .ready
        } else {
            tone = .attention
        }
        quickLookPill.update(text: ql.badgeText, tone: tone)

        if let ext = ql.embeddedExtension {
            quickLookBadgeLabel.stringValue = "\(ext.bundleIdentifier)  ·  \(ext.version.displayString)"
            var detailLines: [String] = []
            if ql.registeredForCurrentTarget, let registeredAt = ql.lastRegisteredAt {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                detailLines.append("• 已为 \(ql.targetAppURL.path) 提交扩展注册并刷新缓存（\(formatter.string(from: registeredAt))）。")
            } else {
                detailLines.append("• 目标应用包已内置 \(ext.displayName) 扩展，点击下方按钮即可向系统提交注册并刷新 Quick Look 缓存。")
            }
            detailLines.append("• 受 macOS 沙盒限制，应用无法直接读取系统扩展勾选状态；如访达按空格未生效，请在「系统设置 → 通用 → 登录项与扩展 → 快速查看」中勾选 MakeTools Markdown 预览。")
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 4
            quickLookDetailLabel.attributedStringValue = NSAttributedString(
                string: detailLines.joined(separator: "\n"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
            )
        } else {
            quickLookBadgeLabel.stringValue = InstallationInspector.quickLookExtensionIdentifier
            quickLookDetailLabel.stringValue = "未在当前应用包中发现 MarkdownQuickLook.appex，请重新执行 make build 或下载完整发布包。"
        }

        if ql.hasMultipleRegisteredCopies {
            let paths = Set(ql.registeredAppURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }).sorted()
            quickLookDuplicateNoticeLabel.stringValue = "提示：系统当前登记了 \(paths.count) 份 MakeTools.app 副本，建议以 /Applications/MakeTools.app 为准以防扩展版本冲突。"
            quickLookDuplicateNoticeLabel.isHidden = false
        } else {
            quickLookDuplicateNoticeLabel.isHidden = true
        }

        registerQuickLookButton.isEnabled = ql.hasEmbeddedExtension && !isRegisteringQuickLook
    }

    private func applyLoginItemRow(_ state: LoginItemState) {
        let tone: StatusTone
        switch state {
        case .enabled:
            tone = .ready
        case .requiresApproval:
            tone = .attention
        case .notRegistered, .notFound:
            tone = .neutral
        }
        loginItemPill.update(text: state.badgeText, tone: tone)
        loginItemDetailLabel.stringValue = state.detailText
        loginItemSwitch.state = (state == .enabled) ? .on : .off
        loginItemSwitch.isEnabled = (state != .notFound)
    }

    private func syncDynamicIslandRow() {
        let manager = DynamicIslandManager.shared
        islandSwitch.state = manager.isEnabled ? .on : .off
        let statusText = manager.isEnabled ? "已开启" : "已关闭"
        islandStatusDetailLabel.stringValue = "当前状态：\(statusText) · 显示样式：\(manager.style.displayTitle) · 关闭主窗口后会在菜单栏后台保持运行。"
    }

    // MARK: - Actions

    @objc private func handleRefresh(_ sender: Any?) {
        refreshSnapshot()
    }

    @objc private func handleCompleteOnboarding(_ sender: Any?) {
        let version = snapshot?.runningVersion ?? service.currentRunningVersion()
        service.preferences.markOnboardingCompleted(for: version)
        refreshSnapshot()
        onNavigateToTool?("dynamic-island")
    }

    @objc private func handleOpenDynamicIsland(_ sender: Any?) {
        onNavigateToTool?("dynamic-island")
    }

    @objc private func handleOpenMarkdown(_ sender: Any?) {
        onNavigateToTool?("markdown-preview")
    }

    @objc private func handleInstallPrimary(_ sender: Any?) {
        guard let snap = snapshot else { return }
        if case .runningFromApplications(let appURL, _) = snap.installStatus {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
            return
        }
        promptAndInstallIntoApplications()
    }

    private func promptAndInstallIntoApplications() {
        let panel = NSOpenPanel()
        panel.title = "确认「应用程序」目录"
        panel.message = "请确认选择「应用程序」（/Applications）文件夹，以授权 MakeTools 完成安装与扩展注册。"
        panel.prompt = "安装到此目录"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        let handleChoice: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let destinationDir = panel.url else { return }
            self.beginInstall(into: destinationDir)
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: handleChoice)
        } else {
            handleChoice(panel.runModal())
        }
    }

    private func beginInstall(into destinationDir: URL) {
        isInstallingApp = true
        installPrimaryButton.isEnabled = false
        relaunchButton.isEnabled = false
        installFeedbackRow.isHidden = false
        installFeedbackLabel.textColor = .secondaryLabelColor
        installFeedbackLabel.stringValue = "准备安装到 \(destinationDir.path)…"
        installSpinner.startAnimation(nil)

        service.installApp(
            into: destinationDir,
            progress: { [weak self] message in
                self?.installFeedbackLabel.stringValue = message
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.isInstallingApp = false
                self.installSpinner.stopAnimation(nil)

                switch result {
                case .success(let (copyOutcome, regOutcome)):
                    self.pendingRelaunchURL = copyOutcome.destinationURL
                    self.installFeedbackLabel.textColor = .systemGreen
                    let verb: String
                    switch copyOutcome {
                    case .installedFresh: verb = "已安装到"
                    case .replacedExisting: verb = "已更新覆盖"
                    case .alreadyInPlace: verb = "已就位于"
                    }
                    if let warning = regOutcome.warning {
                        self.installFeedbackLabel.textColor = .systemOrange
                        self.installFeedbackLabel.stringValue = "\(verb) \(copyOutcome.destinationURL.path)，但扩展注册提示：\(warning)"
                    } else {
                        self.installFeedbackLabel.stringValue = "\(verb) \(copyOutcome.destinationURL.path)，并已提交 Quick Look 扩展注册。点击「从「应用程序」启动」即可切换。"
                    }
                    self.refreshSnapshot()
                case .failure(let error):
                    self.installFeedbackLabel.textColor = .systemRed
                    self.installFeedbackLabel.stringValue = "\(error.localizedDescription)（如因目录权限受限，可点击下方「复制终端安装命令」在终端中完成安装。）"
                    self.refreshSnapshot()
                }
            }
        )
    }

    @objc private func handleRelaunchFromApplications(_ sender: Any?) {
        let targetURL = pendingRelaunchURL
            ?? snapshot?.installStatus.installedAppURL
            ?? URL(fileURLWithPath: "/Applications/\(InstallationInspector.appBundleName)", isDirectory: true)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            installFeedbackRow.isHidden = false
            installFeedbackLabel.textColor = .systemRed
            installFeedbackLabel.stringValue = "未找到可启动的目标应用：\(targetURL.path)"
            return
        }

        installFeedbackRow.isHidden = false
        installFeedbackLabel.textColor = .secondaryLabelColor
        installFeedbackLabel.stringValue = "正在启动 \(targetURL.path)…"
        service.relaunchApp(at: targetURL) { [weak self] error in
            if let error {
                self?.installFeedbackLabel.textColor = .systemRed
                self?.installFeedbackLabel.stringValue = "无法启动目标应用：\(error.localizedDescription)"
            }
        }
    }

    @objc private func handleOpenApplicationsFolder(_ sender: Any?) {
        let appsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        NSWorkspace.shared.open(appsURL)
        if let runningURL = snapshot?.runningAppURL,
           snapshot?.installStatus.isRunningFromApplications == false {
            NSWorkspace.shared.activateFileViewerSelecting([runningURL])
        }
    }

    @objc private func handleCopyInstallCommand(_ sender: Any?) {
        let sourceURL = snapshot?.runningAppURL ?? service.currentRunningAppURL()
        let cmd = InstallationCommandBuilder.terminalInstallCommand(sourceAppURL: sourceURL)
        ClipboardHelper.copyText(cmd)
        ClipboardHelper.flashButton(copyInstallCommandButton, restoreTitle: "复制终端安装命令")
    }

    @objc private func handleRegisterQuickLook(_ sender: Any?) {
        let targetAppURL = snapshot?.quickLook.targetAppURL ?? service.currentRunningAppURL()
        isRegisteringQuickLook = true
        registerQuickLookButton.isEnabled = false
        quickLookFeedbackRow.isHidden = false
        quickLookFeedbackLabel.textColor = .secondaryLabelColor
        quickLookFeedbackLabel.stringValue = "正在注册扩展并刷新 Quick Look 缓存…"
        quickLookSpinner.startAnimation(nil)

        service.registerQuickLookExtension(for: targetAppURL) { [weak self] outcome in
            guard let self else { return }
            self.isRegisteringQuickLook = false
            self.quickLookSpinner.stopAnimation(nil)

            if outcome.succeeded {
                self.quickLookFeedbackLabel.textColor = .systemGreen
                self.quickLookFeedbackLabel.stringValue = outcome.steps.joined(separator: " · ")
            } else {
                self.quickLookFeedbackLabel.textColor = .systemOrange
                let summary = outcome.warning ?? "部分步骤未完成"
                self.quickLookFeedbackLabel.stringValue = "已完成部分操作（\(summary)），可在「系统扩展设置」中确认启用。"
            }
            self.refreshSnapshot()
        }
    }

    @objc private func handleOpenExtensionsSettings(_ sender: Any?) {
        service.openExtensionsSettings()
    }

    @objc private func handlePreviewDemoQuickLook(_ sender: Any?) {
        guard let url = resolveQuickLookDemoURL() else {
            onNavigateToTool?("markdown-preview")
            return
        }
        previewItemURL = url
        view.window?.makeFirstResponder(self)
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible && panel.dataSource === self {
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    private func resolveQuickLookDemoURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "demo", withExtension: "md") {
            return bundled
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("MakeTools-QuickLook-Demo.md")
        let fallback = """
        # MakeTools Quick Look 预览测试

        如果你看到了格式化后的标题、列表与代码块，说明 **MakeTools Markdown 预览** Quick Look 扩展已正常工作。

        - [x] 安装 MakeTools.app 到「应用程序」
        - [x] 注册并启用 MarkdownQuickLook 扩展
        """
        do {
            try fallback.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }

    @objc private func handleCopyVerifyCommand(_ sender: Any?) {
        ClipboardHelper.copyText(InstallationCommandBuilder.quickLookVerifyCommand)
        ClipboardHelper.flashButton(copyVerifyCommandButton, restoreTitle: "复制校验命令")
    }

    @objc private func handleLoginItemSwitchChanged(_ sender: NSSwitch) {
        let wantsEnabled = (sender.state == .on)
        do {
            let newState = try service.setLoginItemEnabled(wantsEnabled)
            loginItemFeedbackLabel.isHidden = true
            applyLoginItemRow(newState)
        } catch {
            loginItemFeedbackLabel.stringValue = "更新开机自启失败：\(error.localizedDescription)。可尝试先安装到「应用程序」，或在系统登录项中手动添加。"
            loginItemFeedbackLabel.isHidden = false
            applyLoginItemRow(service.currentLoginItemState())
        }
    }

    @objc private func handleOpenLoginItemsSettings(_ sender: Any?) {
        service.openLoginItemsSettings()
    }

    @objc private func handleIslandSwitchChanged(_ sender: NSSwitch) {
        DynamicIslandManager.shared.setEnabled(sender.state == .on)
    }

    @objc private func handleCopyQuarantineCommand(_ sender: Any?) {
        let targetURL = snapshot?.installStatus.installedAppURL ?? snapshot?.runningAppURL ?? service.currentRunningAppURL()
        let cmd = InstallationCommandBuilder.quarantineClearCommand(appURL: targetURL)
        ClipboardHelper.copyText(cmd)
        ClipboardHelper.flashButton(copyQuarantineCommandButton, restoreTitle: "复制解除隔离命令")
    }

    // MARK: - QLPreviewPanelController & DataSource

    public override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        previewItemURL != nil
    }

    public override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    public override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if panel.dataSource === self {
            panel.dataSource = nil
        }
        if panel.delegate === self {
            panel.delegate = nil
        }
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItemURL == nil ? 0 : 1
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewItemURL as NSURL?
    }
}
