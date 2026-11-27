import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import UniformTypeIdentifiers

/// Individual toggleable feature modules inside the Dynamic Island.
public enum DynamicIslandFeature: String, CaseIterable {
    case systemMonitor
    case downloadSpeed
    case uploadSpeed
    case audioControl
    case focusTimer
    case fileShelf
    case keepAwake
    case clipboardHistory
    case batteryAlerts
    case calendarCountdown
    case webBookmarks
    case lanTransfer

    public var title: String {
        switch self {
        case .systemMonitor: return L10n.text("island.performanceMonitorCpuMemory", "性能监控（CPU / 内存）")
        case .downloadSpeed: return L10n.text("island.downloadSpeed", "下行网速")
        case .uploadSpeed: return L10n.text("island.uploadSpeed", "上行网速")
        case .audioControl: return L10n.text("island.volumeControlAndAlerts", "音量控制与 HUD 提醒")
        case .focusTimer: return L10n.text("island.focusTimer", "专注倒计时")
        case .fileShelf: return L10n.text("island.fileShelfAndAirdrop", "文件暂存架与隔空投送")
        case .keepAwake: return L10n.text("island.keepAwake", "屏幕防休眠（咖啡因）")
        case .clipboardHistory: return L10n.text("island.clipboardHistoryAndCopyFeedback", "剪贴板历史与复制提示")
        case .batteryAlerts: return L10n.text("island.batteryAndPowerAlerts", "电池充放电与低电量提醒")
        case .calendarCountdown: return L10n.text("calendar.calendarAndCountdowns", "日历与日期倒计时")
        case .webBookmarks: return L10n.text("island.webBookmarks", "网络书签")
        case .lanTransfer: return L10n.text("island.localNetworkTransferCard", "局域网传输卡片")
        }
    }

    public var subtitle: String {
        switch self {
        case .systemMonitor: return L10n.text("island.showCpuUsageMemoryUsageAndProgress", "实时显示 CPU 负载、内存占用及进度条")
        case .downloadSpeed: return L10n.text("island.showLiveDownloadSpeedInTheExpanded", "在展开面板显示实时下载速度")
        case .uploadSpeed: return L10n.text("island.showLiveUploadSpeedInTheExpanded", "在展开面板显示实时上传速度")
        case .audioControl: return L10n.text("island.adjustVolumeMuteAudioAndShowVolume", "支持音量调节、一键静音及音量变动灵动提示")
        case .focusTimer: return L10n.text("island.useTheFocusTimerAndSeeIt", "内置番茄钟倒计时，收起后仍在顶部持续显示")
        case .fileShelf: return L10n.text("island.stageFilesInAGridOpenThe", "九宫格多文件暂存，拖动文件自动弹出，支持点选/拖出/隔空投送")
        case .keepAwake: return L10n.text("island.preventAutomaticSleepDuringPresentationsOrLong", "一键阻止 Mac 自动息屏与休眠，适合演示或长时间下载")
        case .clipboardHistory: return L10n.text("island.keepTheLastEightTextEntriesAnd", "记录最近 8 条复制内容并支持历史切换与一键恢复")
        case .batteryAlerts: return L10n.text("island.showANotificationWhenPowerChangesOr", "接入/断开电源或电量低于 20% 时在灵动岛弹出提示")
        case .calendarCountdown: return L10n.text("island.browseTheCalendarAndSeeDaysRemaining", "浏览月历，查看事件还剩几天或已过去几天")
        case .webBookmarks: return L10n.text("island.saveFrequentlyUsedWebsitesAndOpenThem", "保存常用网页并用默认浏览器打开")
        case .lanTransfer: return L10n.text("island.startReceivingFilesShowAQrCode", "在展开面板开启接收、查看二维码或复制上传链接")
        }
    }

    public var symbolName: String {
        switch self {
        case .systemMonitor: return "cpu"
        case .downloadSpeed: return "arrow.down"
        case .uploadSpeed: return "arrow.up"
        case .audioControl: return "speaker.wave.2.fill"
        case .focusTimer: return "timer"
        case .fileShelf: return "tray.and.arrow.down.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .clipboardHistory: return "doc.on.clipboard.fill"
        case .batteryAlerts: return "battery.100.bolt"
        case .calendarCountdown: return "calendar"
        case .webBookmarks: return "bookmark"
        case .lanTransfer: return "wifi"
        }
    }

    public var defaultEnabled: Bool { true }

    func initialEnabled(in defaults: UserDefaults, keyPrefix: String) -> Bool {
        let key = keyPrefix + rawValue
        if let value = defaults.object(forKey: key) as? Bool { return value }
        let legacy = (self == .downloadSpeed || self == .uploadSpeed)
            ? defaults.object(forKey: keyPrefix + "networkSpeed") as? Bool : nil
        let enabled = legacy ?? defaultEnabled
        defaults.set(enabled, forKey: key)
        return enabled
    }
}

/// Display style for the floating Dynamic Island overlay.
public enum DynamicIslandStyle: Int, CaseIterable {
    case auto = 0
    case notch = 1
    case floatingPill = 2

    public var displayTitle: String {
        switch self {
        case .auto: return L10n.text("island.automatic", "自动适配")
        case .notch: return L10n.text("island.notchAligned", "贴顶刘海")
        case .floatingPill: return L10n.text("island.floatingPill", "悬浮胶囊")
        }
    }
}

enum DynamicIslandMaterial: String, CaseIterable {
    case midnight
    case frostedGlass
    case graphite
    case warmAmber

    var title: String {
        switch self {
        case .midnight: return L10n.text("island.material.midnight", "午夜蓝")
        case .frostedGlass: return L10n.text("island.material.frostedGlass", "磨砂玻璃")
        case .graphite: return L10n.text("island.material.graphite", "石墨灰")
        case .warmAmber: return L10n.text("island.material.warmAmber", "暖琥珀")
        }
    }

    var usesBackdrop: Bool { self == .frostedGlass }

    static func restored(_ stored: String?) -> Self {
        stored.flatMap(Self.init(rawValue:)) ?? .midnight
    }
}

public enum IslandExpandedLayout: String, CaseIterable {
    case shelfRight
    case shelfLeft
    case grid

    var title: String {
        switch self {
        case .shelfRight: return L10n.text("island.shelfOnRight", "暂存架靠右")
        case .shelfLeft: return L10n.text("island.shelfOnLeft", "暂存架靠左")
        case .grid: return L10n.text("island.twoColumnGrid", "双列网格")
        }
    }

    static let spacing: CGFloat = 8
    static let compactSpacing: CGFloat = 7
    static let minimumCompactHeight: CGFloat = 72
    static let cardHeight: CGFloat = 106
    static let shelfHeight: CGFloat = 230

    func bodySize(cardCount: Int, hasShelf: Bool) -> NSSize {
        guard cardCount > 0 else { return NSSize(width: 360, height: 0) }
        if usesGrid(cardCount: cardCount, hasShelf: hasShelf) {
            let rows = (cardCount + 1) / 2
            let standardHeight = CGFloat(rows) * Self.cardHeight + CGFloat(rows - 1) * Self.spacing
            let extraHeight = hasShelf ? Self.shelfHeight - Self.cardHeight : 0
            return NSSize(width: cardCount > 1 ? 512 : 360, height: standardHeight + extraHeight)
        }
        if hasShelf {
            let compactCount = CGFloat(cardCount - 1)
            let compactHeight = compactCount * Self.minimumCompactHeight
                + max(0, compactCount - 1) * Self.compactSpacing
            return NSSize(width: cardCount > 1 ? 512 : 360, height: max(Self.shelfHeight, compactHeight))
        }
        return NSSize(width: 456, height: Self.cardHeight)
    }

    func usesGrid(cardCount: Int, hasShelf: Bool) -> Bool {
        self == .grid || (!hasShelf && cardCount > 2)
    }

    func gridRows(for cards: [IslandExpandedCard]) -> [[IslandExpandedCard]] {
        stride(from: 0, to: cards.count, by: 2).map { start in
            Array(cards[start..<min(start + 2, cards.count)])
        }
    }
}

enum IslandExpandedCard: String, CaseIterable {
    case performance
    case audio
    case focus
    case shelf
    case calendar
    case bookmarks
    case lanTransfer

    var title: String {
        switch self {
        case .performance: return L10n.text("island.performanceAndNetwork", "性能与网速")
        case .audio: return L10n.text("island.audioAndKeepAwake", "音频与防休眠")
        case .focus: return L10n.text("island.focus.186", "专注")
        case .shelf: return L10n.text("island.shelf", "暂存架")
        case .calendar: return L10n.text("calendar.calendar", "日历")
        case .bookmarks: return L10n.text("island.webBookmarks", "网络书签")
        case .lanTransfer: return L10n.text("lanTransfer.title", "局域网传输")
        }
    }

    static func moving(_ card: Self, onto target: Self, in order: [Self]) -> [Self] {
        guard card != target, let source = order.firstIndex(of: card),
              let destination = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: source)
        result.insert(card, at: destination)
        return result
    }

    static func restoredOrder(from rawValues: [String]) -> [Self] {
        var seen = Set<Self>()
        let saved = rawValues.compactMap(Self.init(rawValue:)).filter { seen.insert($0).inserted }
        return saved + allCases.filter { !seen.contains($0) }
    }
}

struct IslandLayoutDraft: Equatable {
    var layout: IslandExpandedLayout
    var order: [IslandExpandedCard]
    var hidden: Set<IslandExpandedCard>

    static let defaults = IslandLayoutDraft(layout: .shelfRight, order: IslandExpandedCard.allCases, hidden: [])

    func visible(in enabled: Set<IslandExpandedCard>) -> [IslandExpandedCard] {
        order.filter { enabled.contains($0) && !hidden.contains($0) }
    }

    func movable(in enabled: Set<IslandExpandedCard>) -> [IslandExpandedCard] {
        visible(in: enabled).filter { layout == .grid || $0 != .shelf }
    }

    mutating func place(_ card: IslandExpandedCard, nextTo target: IslandExpandedCard? = nil, after: Bool = false) {
        hidden.remove(card)
        guard card != target else { return }
        order.removeAll { $0 == card }
        let index = target.flatMap { order.firstIndex(of: $0) }.map { $0 + (after ? 1 : 0) } ?? order.endIndex
        order.insert(card, at: index)
    }

    mutating func move(_ card: IslandExpandedCard, by offset: Int, enabled: Set<IslandExpandedCard>) {
        let movable = movable(in: enabled)
        guard let source = movable.firstIndex(of: card), movable.indices.contains(source + offset) else { return }
        place(card, nextTo: movable[source + offset], after: offset > 0)
    }
}

/// Metrics that can be independently toggled for display on the collapsed Dynamic Island bar.
public enum CollapsedMetricItem: String, CaseIterable {
    case cpu
    case memory
    case downloadSpeed
    case uploadSpeed
    case battery
    case volume
    case clock

    public var displayTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return L10n.text("island.memory", "内存")
        case .downloadSpeed: return L10n.text("island.downloadSpeed", "下行网速")
        case .uploadSpeed: return L10n.text("island.uploadSpeed", "上行网速")
        case .battery: return L10n.text("island.battery", "电量")
        case .volume: return L10n.text("island.volume", "音量")
        case .clock: return L10n.text("island.time", "时间")
        }
    }

    public var defaultEnabled: Bool {
        self == .cpu || self == .downloadSpeed || self == .uploadSpeed
    }

    static func restoredSelection(from stored: [String]?) -> Set<Self> {
        guard let stored else { return Set(allCases.filter(\.defaultEnabled)) }
        var selection = Set(stored.compactMap(Self.init(rawValue:)))
        if stored.contains("networkSpeed") {
            selection.formUnion([.downloadSpeed, .uploadSpeed])
        }
        return selection
    }
}

struct CollapsedMetricRotation {
    static let interval: TimeInterval = 3

    var startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime

    func current(in metrics: [CollapsedMetricItem], uptime: TimeInterval) -> CollapsedMetricItem? {
        guard metrics.count > 1 else { return metrics.first }
        let elapsed = max(0, uptime - startedAt)
        let cycle = Self.interval * Double(metrics.count)
        let offset = elapsed.truncatingRemainder(dividingBy: cycle)
        return metrics[Int(offset / Self.interval)]
    }
}

/// Classification of staged shelf files for thumbnail/snippet preview rendering.
public enum ShelfFileKind: Equatable {
    case image
    case text
    case other
}

/// Helper for classifying staged files and reading safe text snippet previews.
public enum ShelfPreviewHelper {
    private static let textExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mdx", "txt", "log", "rtf",
        "swift", "py", "js", "jsx", "ts", "tsx", "json", "yml", "yaml",
        "sh", "bash", "zsh", "html", "htm", "css", "scss", "csv", "xml",
        "toml", "ini", "conf", "c", "h", "cpp", "hpp", "m", "mm", "go",
        "rs", "java", "kt", "rb", "php", "sql", "plist"
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "icns", "svg"
    ]

    public static func classify(url: URL) -> ShelfFileKind {
        let name = url.lastPathComponent.lowercased()
        if name == "makefile" || name == "dockerfile" || name == "readme" || name == "license" {
            return .text
        }
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            return .image
        }
        if textExtensions.contains(ext) {
            return .text
        }
        if !ext.isEmpty, let ut = UTType(filenameExtension: ext) {
            if ut.conforms(to: .image) {
                return .image
            }
            if ut.conforms(to: .text) || ut.conforms(to: .sourceCode) || ut.conforms(to: .json) || ut.conforms(to: .xml) {
                return .text
            }
        }
        return .other
    }

    public static func readTextSnippet(
        from url: URL,
        maxBytes: Int = 1024,
        maxLines: Int = 4,
        maxChars: Int = 120
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxBytes), !data.isEmpty else {
            return nil
        }
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return nil
        }
        let normalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return nil
        }
        let joined = lines.prefix(maxLines).joined(separator: "\n")
        if joined.count > maxChars {
            return String(joined.prefix(maxChars)) + "…"
        }
        return joined
    }
}

/// Visual state of the Dynamic Island overlay.
struct IslandFileDragGesture {
    private var pasteboardChangeCount: Int?

    mutating func mouseDown(pasteboardChangeCount: Int) {
        self.pasteboardChangeCount = pasteboardChangeCount
    }

    mutating func mouseUp() {
        pasteboardChangeCount = nil
    }

    mutating func detectsFileDrag(
        pasteboardChangeCount currentCount: Int,
        leftButtonPressed: Bool,
        hasFileURLs: @autoclosure () -> Bool
    ) -> Bool {
        guard leftButtonPressed, let previousCount = pasteboardChangeCount,
              previousCount != currentCount else { return false }
        pasteboardChangeCount = currentCount
        return hasFileURLs()
    }
}

public enum DynamicIslandState: Equatable {
    case collapsed
    case hud(title: String, detail: String, symbolName: String)
    case expanded
}

/// Real-time hardware, network, and audio telemetry snapshot.
public struct SystemSnapshot: Equatable {
    public let cpuUsage: Double
    public let memoryUsedBytes: UInt64
    public let memoryTotalBytes: UInt64
    public let memoryUsage: Double
    public let batteryPercent: Int?
    public let isCharging: Bool
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let volume: Float?
    public let isMuted: Bool

    public init(
        cpuUsage: Double,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        memoryUsage: Double,
        batteryPercent: Int?,
        isCharging: Bool,
        downloadBytesPerSec: Double = 0,
        uploadBytesPerSec: Double = 0,
        volume: Float? = nil,
        isMuted: Bool = false
    ) {
        self.cpuUsage = min(1.0, max(0.0, cpuUsage))
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryUsage = min(1.0, max(0.0, memoryUsage))
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.downloadBytesPerSec = max(0, downloadBytesPerSec)
        self.uploadBytesPerSec = max(0, uploadBytesPerSec)
        self.volume = volume.map { min(1.0, max(0.0, $0)) }
        self.isMuted = isMuted
    }

    public var cpuPercentInt: Int {
        Int((cpuUsage * 100).rounded())
    }

    public var memoryPercentInt: Int {
        Int((memoryUsage * 100).rounded())
    }

    public var volumePercentInt: Int? {
        volume.map { Int(($0 * 100).rounded()) }
    }

    public var formattedMemory: String {
        let usedGB = Double(memoryUsedBytes) / 1_073_741_824.0
        let totalGB = Double(memoryTotalBytes) / 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", usedGB, totalGB)
    }

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        let clamped = max(0, bytesPerSec)
        if clamped < 1024 {
            return "\(Int(clamped.rounded())) B/s"
        }
        let kb = clamped / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB/s", kb)
        }
        let mb = kb / 1024.0
        if mb < 100 {
            return String(format: "%.1f MB/s", mb)
        }
        return String(format: "%.0f MB/s", mb)
    }

    private static let compactClockFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    public static func formatCompactSpeed(_ bytesPerSec: Double) -> String {
        let clamped = max(0, bytesPerSec)
        if clamped < 1024 {
            return "\(Int(clamped.rounded()))B"
        }
        let kb = clamped / 1024.0
        if kb < 1024 {
            return String(format: "%.0fK", kb)
        }
        let mb = kb / 1024.0
        if mb < 100 {
            return String(format: "%.1fM", mb)
        }
        return String(format: "%.0fM", mb)
    }

    public func formatCollapsedMetric(_ item: CollapsedMetricItem, now: Date = Date()) -> String {
        switch item {
        case .cpu:
            return "CPU \(cpuPercentInt)%"
        case .memory:
            return L10n.text("island.memory.197", "内存 {arg1}%", ["arg1": String(describing: memoryPercentInt)])
        case .downloadSpeed:
            return "↓\(Self.formatCompactSpeed(downloadBytesPerSec))"
        case .uploadSpeed:
            return "↑\(Self.formatCompactSpeed(uploadBytesPerSec))"
        case .battery:
            if let pct = batteryPercent {
                return "\(isCharging ? "⚡" : "")\(pct)%"
            }
            return "AC"
        case .volume:
            if isMuted { return L10n.text("island.muted.198", "静音") }
            if let pct = volumePercentInt { return L10n.text("island.volume.199", "音量 {arg1}%", ["arg1": String(describing: pct)]) }
            return L10n.text("island.volume.200", "音量 --")
        case .clock:
            return Self.compactClockFormatter.string(from: now)
        }
    }

    public static let empty = SystemSnapshot(
        cpuUsage: 0,
        memoryUsedBytes: 0,
        memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
        memoryUsage: 0,
        batteryPercent: nil,
        isCharging: false
    )
}

/// Computed screen geometry and corner styling for the Dynamic Island panel.
public struct IslandGeometry: Equatable {
    static let hudRowHeight: CGFloat = 38

    public let panelFrame: NSRect
    public let pillRect: NSRect
    let collapsedShelfRect: NSRect?
    public let pillSize: NSSize
    public let cornerRadius: CGFloat
    public let earRadius: CGFloat
    public let isTopAttached: Bool
    public let notchReservedWidth: CGFloat
    let hudContentTopInset: CGFloat

    /// Returns the effective hardware notch width in points when attached to a notched screen.
    public static func effectiveNotchWidth(safeAreaTop: CGFloat, detectedNotchWidth: CGFloat?) -> CGFloat {
        guard safeAreaTop > 0 else { return 0 }
        if let detected = detectedNotchWidth, detected > 20 {
            return detected
        }
        return 192
    }

    public static func compute(
        screenFrame: NSRect,
        safeAreaTop: CGFloat,
        notchWidth: CGFloat?,
        style: DynamicIslandStyle,
        state: DynamicIslandState,
        expandedCardCount: Int = 4,
        hasFileShelf: Bool = true,
        showFooter: Bool = true,
        collapsedDesiredWidth: CGFloat? = nil,
        expandedLayout: IslandExpandedLayout = .shelfRight,
        floatingTopInset: CGFloat = 0,
        collapsedFileCount: Int = 0
    ) -> IslandGeometry {
        let attached = (style != .floatingPill)
        let earRadius: CGFloat = attached ? 10 : 0
        let padX: CGFloat = 16 + earRadius
        let padBottom: CGFloat = (state == .expanded) ? 22 : 8
        let safeTop = ceil(max(0, safeAreaTop))
        let padTop: CGFloat = attached ? 0 : 4
        let panelTop = screenFrame.maxY - (attached ? 0 : max(safeTop, floatingTopInset))
        var hudContentTopInset: CGFloat = 0

        let rawNotch = attached ? effectiveNotchWidth(safeAreaTop: safeAreaTop, detectedNotchWidth: notchWidth) : 0
        let notchReserved: CGFloat = (state == .collapsed && rawNotch > 0) ? (rawNotch + 12) : 0
        let maxCollapsed = min(680, max(240, screenFrame.width - 80))

        var pillWidth: CGFloat
        let pillHeight: CGFloat

        switch state {
        case .collapsed:
            let baseMin: CGFloat = notchReserved > 0 ? max(notchReserved + 96, 280) : 136
            let target = collapsedDesiredWidth ?? 196
            pillWidth = max(baseMin, min(target, maxCollapsed))
            pillHeight = attached ? max(safeAreaTop, 28) : 28
        case .hud:
            if attached && safeTop > 0 {
                hudContentTopInset = safeTop + 2
            }
            pillWidth = 308
            pillHeight = hudContentTopInset + hudRowHeight
        case .expanded:
            let bodySize = expandedLayout.bodySize(cardCount: expandedCardCount, hasShelf: hasFileShelf)
            pillWidth = bodySize.width
            let footerHeight: CGFloat = showFooter ? 30 : 0
            pillHeight = 12 + 24 + (bodySize.height > 0 ? 8 + bodySize.height : 0) + footerHeight + 12
        }

        pillWidth = min(pillWidth, max(160, screenFrame.width - 48))
        let fileCount = state == .collapsed ? min(9, max(0, collapsedFileCount)) : 0
        let shelfHeight: CGFloat = fileCount > 0 ? 38 : 0
        let shelfGap: CGFloat = fileCount > 0 ? 5 : 0
        let shelfWidth = min(CGFloat(fileCount) * 42 + 12, max(160, screenFrame.width - 48))
        let panelWidth = max(pillWidth, fileCount > 0 ? shelfWidth : 0) + padX * 2
        let panelHeight = pillHeight + padTop + padBottom + shelfHeight + shelfGap

        let panelX = round(screenFrame.midX - panelWidth / 2.0)
        let panelY = floor(panelTop - panelHeight)
        let pillRect = NSRect(x: (panelWidth - pillWidth) / 2, y: padBottom + shelfHeight + shelfGap,
                              width: pillWidth, height: pillHeight)
        let shelfRect = fileCount > 0
            ? NSRect(x: (panelWidth - shelfWidth) / 2, y: padBottom, width: shelfWidth, height: shelfHeight)
            : nil

        let cornerRadius: CGFloat
        if case .expanded = state {
            cornerRadius = 24
        } else if case .hud = state {
            cornerRadius = attached ? 16 : pillHeight / 2.0
        } else {
            cornerRadius = attached ? 13 : pillHeight / 2.0
        }

        return IslandGeometry(
            panelFrame: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            pillRect: pillRect,
            collapsedShelfRect: shelfRect,
            pillSize: NSSize(width: pillWidth, height: pillHeight),
            cornerRadius: cornerRadius,
            earRadius: earRadius,
            isTopAttached: attached,
            notchReservedWidth: notchReserved,
            hudContentTopInset: hudContentTopInset
        )
    }

    func interactionRect(for visiblePill: NSRect) -> NSRect {
        visiblePill.insetBy(dx: -earRadius, dy: 0)
    }

    /// Estimates the hardware camera notch width when running on a notched Mac display.
    public static func detectNotchWidth(for screen: NSScreen) -> CGFloat? {
        guard screen.safeAreaInsets.top > 0,
              let leftRect = screen.auxiliaryTopLeftArea,
              let rightRect = screen.auxiliaryTopRightArea else {
            return nil
        }
        let gap = rightRect.minX - leftRect.maxX
        return gap > 20 ? gap : nil
    }
}

/// CoreAudio helper for reading and controlling default system output volume & mute.
public final class SystemAudioController {
    public init() {}

    public func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }
        return deviceID
    }

    public func getVolume() -> Float? {
        guard let deviceID = getDefaultOutputDeviceID() else { return nil }

        var virtualAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &virtualAddr) {
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &virtualAddr, 0, nil, &size, &volume) == noErr {
                return min(1.0, max(0.0, volume))
            }
        }

        var scalarAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )
        if AudioObjectHasProperty(deviceID, &scalarAddr) {
            var volume: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &scalarAddr, 0, nil, &size, &volume) == noErr {
                return min(1.0, max(0.0, volume))
            }
        }
        return nil
    }

    @discardableResult
    public func setVolume(_ value: Float) -> Bool {
        guard let deviceID = getDefaultOutputDeviceID() else { return false }
        var clamped: Float32 = min(1.0, max(0.0, value))
        let size = UInt32(MemoryLayout<Float32>.size)

        var virtualAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &virtualAddr),
           AudioObjectSetPropertyData(deviceID, &virtualAddr, 0, nil, size, &clamped) == noErr {
            return true
        }

        var scalarAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )
        if AudioObjectHasProperty(deviceID, &scalarAddr),
           AudioObjectSetPropertyData(deviceID, &scalarAddr, 0, nil, size, &clamped) == noErr {
            return true
        }
        return false
    }

    public func getMuted() -> Bool? {
        guard let deviceID = getDefaultOutputDeviceID() else { return nil }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &muteAddr) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    @discardableResult
    public func setMuted(_ isMuted: Bool) -> Bool {
        guard let deviceID = getDefaultOutputDeviceID() else { return false }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &muteAddr) else { return false }
        var muted: UInt32 = isMuted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, size, &muted) == noErr
    }
}

/// Manages an IOKit display-sleep prevention assertion (Caffeine / Keep-Awake).
public final class KeepAwakeController {
    public private(set) var isActive: Bool = false
    private var assertionID: IOPMAssertionID = 0

    public init() {}

    deinit {
        _ = setActive(false)
    }

    @discardableResult
    public func setActive(_ active: Bool) -> Bool {
        if active == isActive {
            return true
        }
        if active {
            var newID: IOPMAssertionID = 0
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "MakeTools DynamicIsland KeepAwake" as CFString,
                &newID
            )
            if status == kIOReturnSuccess {
                assertionID = newID
                isActive = true
                return true
            }
            return false
        } else {
            if assertionID != 0 {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
            }
            isActive = false
            return true
        }
    }
}

/// Reads delta CPU utilization, memory usage, battery state, network throughput, and audio status.
public final class SystemMetricsReader {
    private var previousTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetSample: (inBytes: UInt64, outBytes: UInt64, timestamp: Date)?
    private let audioController = SystemAudioController()

    public init() {}

    public func sample() -> SystemSnapshot {
        let cpu = sampleCPU()
        let (usedBytes, totalBytes, memRatio) = sampleMemory()
        let (batteryPercent, isCharging) = sampleBattery()
        let (downSpeed, upSpeed) = sampleNetworkSpeed()
        let volume = audioController.getVolume()
        let isMuted = audioController.getMuted() ?? false

        return SystemSnapshot(
            cpuUsage: cpu,
            memoryUsedBytes: usedBytes,
            memoryTotalBytes: totalBytes,
            memoryUsage: memRatio,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            downloadBytesPerSec: downSpeed,
            uploadBytesPerSec: upSpeed,
            volume: volume,
            isMuted: isMuted
        )
    }

    private func sampleCPU() -> Double {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }

        let user = UInt64(cpuInfo.cpu_ticks.0)
        let system = UInt64(cpuInfo.cpu_ticks.1)
        let idle = UInt64(cpuInfo.cpu_ticks.2)
        let nice = UInt64(cpuInfo.cpu_ticks.3)

        defer {
            previousTicks = (user, system, idle, nice)
        }

        guard let prev = previousTicks else {
            let total = user + system + idle + nice
            guard total > 0 else { return 0 }
            return Double(user + system + nice) / Double(total)
        }

        let dUser = user >= prev.user ? user - prev.user : 0
        let dSystem = system >= prev.system ? system - prev.system : 0
        let dIdle = idle >= prev.idle ? idle - prev.idle : 0
        let dNice = nice >= prev.nice ? nice - prev.nice : 0

        let totalDelta = dUser + dSystem + dIdle + dNice
        guard totalDelta > 0 else { return 0 }
        let busyDelta = dUser + dSystem + dNice
        return min(1.0, max(0.0, Double(busyDelta) / Double(totalDelta)))
    }

    private func sampleMemory() -> (used: UInt64, total: UInt64, ratio: Double) {
        let total = ProcessInfo.processInfo.physicalMemory
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, total > 0 else {
            return (0, total, 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count)
        let wired = UInt64(vmStats.wire_count)
        let compressed = UInt64(vmStats.compressor_page_count)
        let used = (active + wired + compressed) * pageSize
        let clampedUsed = min(used, total)
        let ratio = min(1.0, max(0.0, Double(clampedUsed) / Double(total)))
        return (clampedUsed, total, ratio)
    }

    private func sampleBattery() -> (percent: Int?, isCharging: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }

        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            guard let current = info[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCap = info[kIOPSMaxCapacityKey as String] as? Int,
                  maxCap > 0 else {
                continue
            }
            let percent = min(100, max(0, Int((Double(current) / Double(maxCap) * 100.0).rounded())))
            let charging = (info[kIOPSIsChargingKey as String] as? Bool) ?? false
            return (percent, charging)
        }

        return (nil, false)
    }

    private func sampleNetworkSpeed() -> (download: Double, upload: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return (0, 0)
        }
        defer { freeifaddrs(first) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp && !isLoopback,
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totalIn &+= UInt64(data.pointee.ifi_ibytes)
                totalOut &+= UInt64(data.pointee.ifi_obytes)
            }
            ptr = current.pointee.ifa_next
        }

        let now = Date()
        defer {
            previousNetSample = (totalIn, totalOut, now)
        }

        guard let prev = previousNetSample else {
            return (0, 0)
        }
        let dt = now.timeIntervalSince(prev.timestamp)
        guard dt > 0.05 else {
            return (0, 0)
        }
        let dIn = totalIn >= prev.inBytes ? Double(totalIn - prev.inBytes) : 0
        let dOut = totalOut >= prev.outBytes ? Double(totalOut - prev.outBytes) : 0
        return (dIn / dt, dOut / dt)
    }
}

/// Countdown timer model driving the Focus Live Activity in the Dynamic Island.
public final class FocusTimerModel {
    public private(set) var totalSeconds: Int
    public private(set) var remainingSeconds: Int
    public private(set) var isRunning: Bool = false

    public init(minutes: Int = 25) {
        let clamped = max(1, minutes)
        self.totalSeconds = clamped * 60
        self.remainingSeconds = clamped * 60
    }

    public func setDuration(minutes: Int) {
        let clamped = max(1, minutes)
        totalSeconds = clamped * 60
        remainingSeconds = totalSeconds
        isRunning = false
    }

    public func start() {
        if remainingSeconds <= 0 {
            remainingSeconds = totalSeconds
        }
        isRunning = true
    }

    public func pause() {
        isRunning = false
    }

    public func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    public func reset() {
        isRunning = false
        remainingSeconds = totalSeconds
    }

    /// Advances by elapsed whole seconds and reports completion once.
    @discardableResult
    public func tick(elapsedSeconds: Int = 1) -> Bool {
        guard isRunning, elapsedSeconds > 0 else { return false }
        remainingSeconds = max(0, remainingSeconds - min(remainingSeconds, elapsedSeconds))
        if remainingSeconds > 0 { return false }
        isRunning = false
        return true
    }

    public var formattedRemaining: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let elapsed = totalSeconds - remainingSeconds
        return min(1.0, max(0.0, Double(elapsed) / Double(totalSeconds)))
    }
}
