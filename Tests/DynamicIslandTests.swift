import AppKit
import Foundation

private var totalAssertions = 0
private var failedAssertions = 0

private func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    totalAssertions += 1
    if !condition {
        failedAssertions += 1
        fputs("FAIL [\(file):\(line)] \(message)\n", stderr)
    }
}

@main
struct DynamicIslandTests {
    static func main() {
        testNotchGeometry()
        testNonNotchGeometry()
        testHUDSafeArea()
        testAdaptiveExpandedGeometry()
        testFileDragGesture()
        testSpeedFormattingAndFeatures()
        testCollapsedCustomizationAndShelfPreview()
        testFocusTimerModel()
        testSystemMetricsReaderBounds()

        print("DynamicIslandTests: \(totalAssertions - failedAssertions)/\(totalAssertions) assertions passed.")
        if failedAssertions > 0 {
            exit(1)
        }
    }

    private static func testFileDragGesture() {
        var gesture = IslandFileDragGesture()
        check(!gesture.detectsFileDrag(pasteboardChangeCount: 4, leftButtonPressed: true, hasFileURLs: true),
              "An unobserved press cannot start file drag expansion")

        gesture.mouseDown(pasteboardChangeCount: 4)
        check(!gesture.detectsFileDrag(pasteboardChangeCount: 4, leftButtonPressed: true, hasFileURLs: true),
              "A window drag cannot reuse the previous gesture's file URLs")
        check(!gesture.detectsFileDrag(pasteboardChangeCount: 5, leftButtonPressed: true, hasFileURLs: false),
              "A new non-file drag does not trigger expansion")
        check(gesture.detectsFileDrag(pasteboardChangeCount: 6, leftButtonPressed: true, hasFileURLs: true),
              "New file URLs during a press can trigger expansion")
        check(!gesture.detectsFileDrag(pasteboardChangeCount: 6, leftButtonPressed: true, hasFileURLs: true),
              "The same pasteboard revision only triggers once")
        check(!gesture.detectsFileDrag(pasteboardChangeCount: 7, leftButtonPressed: false, hasFileURLs: true),
              "A delayed drag event cannot trigger expansion after release")

        gesture.mouseUp()
        check(!gesture.detectsFileDrag(pasteboardChangeCount: 7, leftButtonPressed: true, hasFileURLs: true),
              "Mouse-up discards the completed gesture")
        gesture.mouseDown(pasteboardChangeCount: 7)
        check(gesture.detectsFileDrag(pasteboardChangeCount: 8, leftButtonPressed: true, hasFileURLs: true),
              "A separate file drag can trigger expansion")
    }

    private static func testNotchGeometry() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)

        let collapsed = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 37,
            notchWidth: 180,
            style: .auto,
            state: .collapsed
        )
        check(collapsed.isTopAttached, "Notch screen in .auto mode should attach to top")
        check(collapsed.earRadius == 10, "Top-attached notch should have 10pt concave ear radius")
        check(collapsed.panelFrame.maxY == screen.maxY, "Top-attached collapsed island should flush with top edge")
        check(collapsed.notchReservedWidth == 192, "Notched screen with 180pt notch should reserve 192pt center gap")
        check(collapsed.pillSize.width >= 288, "Collapsed notch island should wrap notch gap with symmetric wings")
        check(collapsed.pillSize.height == 37, "Collapsed notch height should match safeAreaTop 37")
        check(abs(collapsed.panelFrame.midX - screen.midX) <= 1.0, "Collapsed island should be horizontally centered")

        let collapsedFallback = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 37,
            notchWidth: nil,
            style: .auto,
            state: .collapsed
        )
        check(collapsedFallback.notchReservedWidth == 204, "Notched screen without auxiliary area should reserve fallback 204pt center gap")

        let collapsedManualWide = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 37,
            notchWidth: 180,
            style: .auto,
            state: .collapsed,
            collapsedDesiredWidth: 480
        )
        check(collapsedManualWide.pillSize.width == 480, "Collapsed notch island should respect custom 480pt width")
        check(collapsedManualWide.notchReservedWidth == 192, "Wide collapsed notch island should preserve 192pt center notch gap")

        let expanded = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 37,
            notchWidth: 180,
            style: .auto,
            state: .expanded
        )
        check(expanded.pillSize.width == 512, "Expanded pill width should be 512 when 3x3 shelf + left cards are active")
        check(expanded.pillSize.height == 316, "Expanded pill height should be 316 for 3x3 shelf + footer")
        check(expanded.cornerRadius == 24, "Expanded corner radius should be 24")
    }

    private static func testHUDSafeArea() {
        let screen = NSRect(x: 1440, y: -120, width: 1512, height: 982)
        let state = DynamicIslandState.hud(title: "已复制", detail: "剪贴板内容", symbolName: "doc.on.clipboard.fill")
        let safeTop: CGFloat = 37.5
        let notchBottom = screen.maxY - safeTop

        for style in DynamicIslandStyle.allCases {
            let hud = IslandGeometry.compute(
                screenFrame: screen, safeAreaTop: safeTop, notchWidth: 180, style: style, state: state
            )
            let pillTop = hud.panelFrame.minY + hud.pillRect.maxY
            let rowTop = pillTop - hud.hudContentTopInset
            let rowBottom = rowTop - IslandGeometry.hudRowHeight
            check(rowTop < notchBottom, "HUD content should be below the camera cutout for \(style)")
            check(rowBottom >= hud.panelFrame.minY + hud.pillRect.minY,
                  "The full HUD row should fit inside the pill for \(style)")
            check(hud.pillSize.width == 308, "The HUD should keep its width for \(style)")
            if style == .floatingPill {
                check(hud.hudContentTopInset == 0, "The floating HUD should move its entire pill below the cutout")
            } else {
                check(pillTop == screen.maxY, "The attached HUD should remain anchored to the top edge")
            }
        }

        let noNotch = IslandGeometry.compute(
            screenFrame: screen, safeAreaTop: 0, notchWidth: nil, style: .auto, state: state
        )
        check(noNotch.hudContentTopInset == 0, "A screen without a notch should not reserve a camera band")
        check(noNotch.pillSize.height == IslandGeometry.hudRowHeight, "The HUD remains compact without a notch")
    }

    private static func testAdaptiveExpandedGeometry() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let noShelfTwoCards = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 0,
            notchWidth: nil,
            style: .auto,
            state: .expanded,
            expandedCardCount: 2,
            hasFileShelf: false,
            showFooter: true
        )
        check(noShelfTwoCards.pillSize.width == 456, "No-shelf 2-card layout should use 456pt width")
        check(noShelfTwoCards.pillSize.height == 192, "No-shelf 2-card layout with footer should be 192pt tall")

        let noShelfNoFooter = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 0,
            notchWidth: nil,
            style: .auto,
            state: .expanded,
            expandedCardCount: 2,
            hasFileShelf: false,
            showFooter: false
        )
        check(noShelfNoFooter.pillSize.height == 162, "No-shelf 2-card layout without footer should be 162pt tall")

        let shelfOnly = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 0,
            notchWidth: nil,
            style: .auto,
            state: .expanded,
            expandedCardCount: 1,
            hasFileShelf: true,
            showFooter: true
        )
        check(shelfOnly.pillSize.width == 360, "Shelf-only layout should use compact 360pt width")
        check(shelfOnly.pillSize.height == 316, "Shelf-only layout should keep 3x3 grid height")

        let zeroCardsWithFooter = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 0,
            notchWidth: nil,
            style: .auto,
            state: .expanded,
            expandedCardCount: 0,
            hasFileShelf: false,
            showFooter: true
        )
        check(zeroCardsWithFooter.pillSize.width == 360, "0-card layout should use compact 360pt width")
        check(zeroCardsWithFooter.pillSize.height == 78, "0-card layout with footer should be 78pt tall")
    }

    private static func testSpeedFormattingAndFeatures() {
        check(SystemSnapshot.formatSpeed(0) == "0 B/s", "0 speed should format as 0 B/s")
        check(SystemSnapshot.formatSpeed(512) == "512 B/s", "Sub-KB speed should format as B/s")
        check(SystemSnapshot.formatSpeed(15 * 1024) == "15 KB/s", "KB speed should format cleanly")
        check(SystemSnapshot.formatSpeed(2.5 * 1024 * 1024) == "2.5 MB/s", "MB speed should format with 1 decimal")

        check(DynamicIslandFeature.allCases.count == 8, "Should expose all 8 modular Dynamic Island features")
        for feature in DynamicIslandFeature.allCases {
            check(!feature.title.isEmpty, "\(feature.rawValue) title should not be empty")
            check(!feature.subtitle.isEmpty, "\(feature.rawValue) subtitle should not be empty")
            check(!feature.symbolName.isEmpty, "\(feature.rawValue) symbolName should not be empty")
            check(feature.defaultEnabled, "\(feature.rawValue) should default to enabled")
        }
    }

    private static func testCollapsedCustomizationAndShelfPreview() {
        check(CollapsedMetricItem.allCases.count == 6, "Should expose 6 collapsed metric items")
        check(SystemSnapshot.formatCompactSpeed(0) == "0B", "0 compact speed")
        check(SystemSnapshot.formatCompactSpeed(15 * 1024) == "15K", "KB compact speed")
        check(SystemSnapshot.formatCompactSpeed(2.4 * 1024 * 1024) == "2.4M", "MB compact speed")

        let snap = SystemSnapshot(
            cpuUsage: 0.23,
            memoryUsedBytes: 8 * 1_073_741_824,
            memoryTotalBytes: 16 * 1_073_741_824,
            memoryUsage: 0.50,
            batteryPercent: 84,
            isCharging: true,
            downloadBytesPerSec: 12 * 1024,
            uploadBytesPerSec: 2 * 1024,
            volume: 0.45,
            isMuted: false
        )
        check(snap.formatCollapsedMetric(.cpu) == "CPU 23%", "CPU collapsed format")
        check(snap.formatCollapsedMetric(.memory) == "内存 50%", "Memory collapsed format")
        check(snap.formatCollapsedMetric(.networkSpeed) == "↓12K ↑2K", "Network collapsed format")
        check(snap.formatCollapsedMetric(.battery) == "⚡84%", "Charging battery collapsed format")
        check(snap.formatCollapsedMetric(.volume) == "音量 45%", "Volume collapsed format")

        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let narrow = IslandGeometry.compute(screenFrame: screen, safeAreaTop: 0, notchWidth: nil, style: .auto, state: .collapsed, collapsedDesiredWidth: 90)
        check(narrow.pillSize.width == 136, "Collapsed pill should clamp to min 136pt")
        let wide = IslandGeometry.compute(screenFrame: screen, safeAreaTop: 0, notchWidth: nil, style: .auto, state: .collapsed, collapsedDesiredWidth: 310)
        check(wide.pillSize.width == 310, "Collapsed pill should expand to requested multi-metric width")
        let capped = IslandGeometry.compute(screenFrame: screen, safeAreaTop: 0, notchWidth: nil, style: .auto, state: .collapsed, collapsedDesiredWidth: 900)
        check(capped.pillSize.width == 680, "Collapsed pill should clamp to max 680pt")

        check(ShelfPreviewHelper.classify(url: URL(fileURLWithPath: "/tmp/photo.png")) == .image, "PNG should classify as image")
        check(ShelfPreviewHelper.classify(url: URL(fileURLWithPath: "/tmp/shot.jpg")) == .image, "JPG should classify as image")
        check(ShelfPreviewHelper.classify(url: URL(fileURLWithPath: "/tmp/README.md")) == .text, "Markdown should classify as text")
        check(ShelfPreviewHelper.classify(url: URL(fileURLWithPath: "/tmp/Makefile")) == .text, "Makefile should classify as text")
        check(ShelfPreviewHelper.classify(url: URL(fileURLWithPath: "/tmp/archive.zip")) == .other, "ZIP should classify as other")

        let snippet = ShelfPreviewHelper.readTextSnippet(from: URL(fileURLWithPath: "/Users/make/project/MakeTools/README.md"))
        check(snippet != nil && !(snippet?.isEmpty ?? true), "Should read non-empty text snippet from README.md")
    }

    private static func testNonNotchGeometry() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let autoNotch = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 0,
            notchWidth: nil,
            style: .auto,
            state: .collapsed
        )
        check(autoNotch.isTopAttached, "Non-notch screen in .auto mode should render sleek top-attached notch silhouette")
        check(autoNotch.pillSize.height == 28, "Collapsed pill height on non-notch display should be slim 28pt")
        check(autoNotch.panelFrame.height <= 42, "Collapsed panel height including shadow padding should be <= 42pt")
        check(autoNotch.panelFrame.maxY == screen.maxY, "Top-attached notch should flush with top edge")

        let forcedFloating = IslandGeometry.compute(
            screenFrame: screen,
            safeAreaTop: 37,
            notchWidth: 180,
            style: .floatingPill,
            state: .collapsed
        )
        check(!forcedFloating.isTopAttached, "Explicit .floatingPill style should detach from top even on notch display")
        check(forcedFloating.earRadius == 0, "Floating pill should have zero concave ear radius")
        check(forcedFloating.cornerRadius == forcedFloating.pillSize.height / 2.0, "Floating collapsed pill should have full capsule radius")
    }

    private static func testFocusTimerModel() {
        let timer = FocusTimerModel(minutes: 1)
        check(timer.totalSeconds == 60, "1 minute duration should equal 60 seconds")
        check(timer.formattedRemaining == "01:00", "Initial formatted time should be 01:00")
        check(!timer.isRunning, "Timer should start paused")

        timer.start()
        check(timer.isRunning, "Timer should be running after start()")

        let completedEarly = timer.tick()
        check(!completedEarly, "Ticking from 60 to 59 should not complete")
        check(timer.remainingSeconds == 59, "Remaining seconds should decrement to 59")
        check(timer.formattedRemaining == "00:59", "Formatted time should be 00:59")

        timer.pause()
        let pausedTick = timer.tick()
        check(!pausedTick && timer.remainingSeconds == 59, "Ticking while paused should not change remaining time")

        timer.setDuration(minutes: 1)
        timer.start()
        var completedCount = 0
        for _ in 0..<60 {
            if timer.tick() {
                completedCount += 1
            }
        }
        check(completedCount == 1, "Timer should complete exactly once at 0")
        check(timer.remainingSeconds == 0 && !timer.isRunning, "Completed timer should stop at 0")

        timer.reset()
        check(timer.remainingSeconds == 60 && !timer.isRunning, "Reset should restore totalSeconds and pause")
    }

    private static func testSystemMetricsReaderBounds() {
        let reader = SystemMetricsReader()
        let snap = reader.sample()
        check((0.0...1.0).contains(snap.cpuUsage), "CPU usage should be within 0...1")
        check((0.0...1.0).contains(snap.memoryUsage), "Memory usage should be within 0...1")
        check(snap.memoryTotalBytes > 0, "Total memory should be positive")
        if let battery = snap.batteryPercent {
            check((0...100).contains(battery), "Battery percent should be within 0...100")
        }
        check(snap.downloadBytesPerSec >= 0, "Download speed should be non-negative")
        check(snap.uploadBytesPerSec >= 0, "Upload speed should be non-negative")
        if let vol = snap.volume {
            check((0.0...1.0).contains(vol), "Volume should be within 0...1")
        }
    }
}
