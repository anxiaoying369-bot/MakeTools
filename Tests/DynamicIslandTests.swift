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
        testCustomExpandedLayout()
        testExpandedInteractionRect()
        testCalendarCountdown()
        testSystemCalendarDates()
        testWebBookmarks()
        testHolidayDataAndLunarCalendar()
        testFileDragGesture()
        testSpeedFormattingAndFeatures()
        testCollapsedCustomizationAndShelfPreview()
        testCollapsedMetricRotation()
        testNetworkSpeedPreferences()
        testFocusTimerModel()
        testSystemMetricsReaderBounds()

        print("DynamicIslandTests: \(totalAssertions - failedAssertions)/\(totalAssertions) assertions passed.")
        if failedAssertions > 0 {
            exit(1)
        }
    }

    private static func testCollapsedMetricRotation() {
        let rotation = CollapsedMetricRotation(startedAt: 100)
        let metrics: [CollapsedMetricItem] = [.cpu, .memory, .clock]
        check(rotation.current(in: [], uptime: 104) == nil, "No enabled metrics should leave the metric slot empty")
        check(rotation.current(in: [.clock], uptime: 159) == .clock, "A single selected metric should stay visible")
        check(rotation.current(in: metrics, uptime: 102.99) == .cpu, "First metric should remain until three seconds")
        check(rotation.current(in: metrics, uptime: 103) == .memory, "Second metric should appear after three seconds")
        check(rotation.current(in: metrics, uptime: 106) == .clock, "Third metric should appear after six seconds")
        check(rotation.current(in: metrics, uptime: 109) == .cpu, "The carousel should wrap to the first metric")
        check(rotation.current(in: metrics, uptime: 121) == .memory, "A delayed update should catch up without changing cadence")
    }

    private static func testWebBookmarks() {
        let home = WebBookmark(title: "  ", address: " example.com/docs ")
        check(home?.title == "example.com" && home?.url.absoluteString == "https://example.com/docs",
              "A bare address should use HTTPS and take its title from the hostname")
        check(WebBookmark(title: "local", address: "localhost:8080")?.url.port == 8080,
              "A bare host and port should still be accepted")
        check(WebBookmark(title: "redirect", address: "example.com/?to=https://example.org") != nil,
              "An embedded URL should not be mistaken for the bookmark's scheme")
        check(WebBookmark(title: "", address: "file:///tmp/example") == nil
              && WebBookmark(title: "", address: "javascript:alert(1)") == nil
              && WebBookmark(title: "", address: "https://user:secret@example.com") == nil
              && WebBookmark(title: "", address: "https://") == nil,
              "Only valid web addresses without embedded credentials should be saved")

        let suite = "MakeTools.WebBookmarkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebBookmarkStore(defaults: defaults)
        guard let home,
              let second = WebBookmark(title: "Other", address: "http://example.org"),
              let updated = WebBookmark(title: "Docs", address: home.url.absoluteString) else {
            check(false, "Could not prepare bookmark fixture")
            return
        }
        do {
            let empty = try store.load()
            _ = try store.add(home)
            _ = try store.add(second)
            let bookmarks = try store.add(updated)
            let reloaded = try WebBookmarkStore(defaults: defaults).load()
            check(empty.isEmpty, "A new profile should have no bookmarks")
            check(bookmarks == [updated, second] && reloaded == bookmarks,
                  "Bookmarks should persist, newest first, without duplicating the same URL")
            let remaining = try store.remove(url: updated.url)
            let persisted = try store.load()
            check(remaining == [second] && persisted == remaining, "Deleting one bookmark should persist and retain other entries")
            let unchanged = try store.remove(url: updated.url)
            check(unchanged == remaining, "Deleting an already removed bookmark should be safe")
            let removedLast = try store.remove(url: second.url)
            let persistedEmpty = try store.load()
            check(removedLast.isEmpty && persistedEmpty.isEmpty, "Deleting the last bookmark should persist an empty list")
        } catch {
            check(false, "Bookmark persistence failed: \(error)")
        }
    }

    private static func testNetworkSpeedPreferences() {
        check(CollapsedMetricItem.restoredSelection(from: ["clock", "networkSpeed"]) == [.clock, .downloadSpeed, .uploadSpeed],
              "A previously enabled network metric should become two selected directions")
        check(CollapsedMetricItem.restoredSelection(from: ["downloadSpeed"]) == [.downloadSpeed],
              "A new single-direction selection should remain independent")
        check(CollapsedMetricItem.restoredSelection(from: []) == [], "An empty selection should remain empty")

        let suite = "MakeTools.NetworkPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefix = "feature."
        defaults.set(false, forKey: prefix + "networkSpeed")
        check(!DynamicIslandFeature.downloadSpeed.initialEnabled(in: defaults, keyPrefix: prefix),
              "A disabled legacy network switch should keep downloads hidden")
        check(!DynamicIslandFeature.uploadSpeed.initialEnabled(in: defaults, keyPrefix: prefix),
              "A disabled legacy network switch should keep uploads hidden")
        defaults.set(true, forKey: prefix + "downloadSpeed")
        check(DynamicIslandFeature.downloadSpeed.initialEnabled(in: defaults, keyPrefix: prefix)
              && !DynamicIslandFeature.uploadSpeed.initialEnabled(in: defaults, keyPrefix: prefix),
              "A newly changed download switch should not re-enable uploads")
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

    private static func testCustomExpandedLayout() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let order = IslandExpandedCard.restoredOrder(from: ["shelf", "shelf", "unknown", "focus"])
        check(order == [.shelf, .focus, .performance, .audio, .calendar, .bookmarks],
              "Saved layouts should keep unique cards and append new cards")
        check(IslandExpandedCard.restoredOrder(from: []) == IslandExpandedCard.allCases,
              "An existing installation should keep the default order")
        check(IslandExpandedLayout.grid.gridRows(for: order) == [[.shelf, .focus], [.performance, .audio], [.calendar, .bookmarks]],
              "Grid fills rows from left to right according to the saved order")
        check(IslandExpandedLayout.grid.gridRows(for: [.audio, .shelf, .focus]) == [[.audio, .shelf], [.focus]],
              "A grid with an odd number of active cards should include a final single-card row")

        let left = IslandGeometry.compute(screenFrame: screen, safeAreaTop: 0, notchWidth: nil,
                                          style: .auto, state: .expanded, expandedLayout: .shelfLeft)
        let right = IslandGeometry.compute(screenFrame: screen, safeAreaTop: 0, notchWidth: nil,
                                           style: .auto, state: .expanded, expandedLayout: .shelfRight)
        check(left.pillSize == right.pillSize, "Moving the shelf between sides should preserve the panel size")

        let grid = IslandGeometry.compute(screenFrame: screen, safeAreaTop: 0, notchWidth: nil,
                                          style: .auto, state: .expanded, expandedLayout: .grid)
        check(grid.pillSize == NSSize(width: 512, height: 430), "The grid should fit a shelf row and a compact row")

        let gridWithoutShelf = IslandGeometry.compute(
            screenFrame: screen, safeAreaTop: 0, notchWidth: nil, style: .auto, state: .expanded,
            expandedCardCount: 3, hasFileShelf: false, showFooter: false, expandedLayout: .grid
        )
        check(gridWithoutShelf.pillSize.height == 276, "The grid should fit two compact rows when the shelf is off")
    }

    private static func testCalendarCountdown() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }

        let now = date(2024, 3, 10, hour: 23)
        let tomorrow = CountdownDay(date: date(2024, 3, 11), calendar: calendar)
        let yesterday = CountdownDay(date: date(2024, 3, 9), calendar: calendar)
        let today = CountdownDay(date: now, calendar: calendar)
        check(tomorrow.days(from: now, calendar: calendar) == 1, "Countdown should cross midnight on a DST day")
        check(yesterday.days(from: now, calendar: calendar) == -1, "Elapsed days should count calendar dates across DST")
        check(today.days(from: date(2024, 3, 10, hour: 0), calendar: calendar) == 0, "Different times today should count as zero")
        check(CountdownDay(date: date(2024, 3, 1), calendar: calendar).days(from: date(2024, 2, 28), calendar: calendar) == 2,
              "Countdown should include the leap day")
        check(CalendarCountdown.status(for: -3) == "已过去 3 天", "Past dates should show elapsed days")
        check(CalendarCountdown.status(for: 2) == "还有 2 天", "Future dates should show remaining days")
        check(CalendarCountdown.status(for: 0) == "就是今天", "Today should have a dedicated status")

        let events = [
            CalendarCountdownEvent(id: UUID(), title: "Past", day: yesterday),
            CalendarCountdownEvent(id: UUID(), title: "Tomorrow", day: tomorrow),
            CalendarCountdownEvent(id: UUID(), title: "Today", day: today)
        ]
        check(CalendarCountdown.orderedEvents(events, now: now, calendar: calendar).map(\.event.title) == ["Today", "Tomorrow", "Past"],
              "Upcoming events should appear first, then elapsed events")

        let suite = "MakeTools.CalendarCountdownTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CalendarCountdownStore(defaults: defaults)
        check(store.load().isEmpty, "A fresh calendar should have no user events")
        do {
            try store.save(events)
            check(store.load() == events, "The calendar should persist local dates, titles, and event identities")
        } catch {
            check(false, "Calendar event persistence failed: \(error)")
        }

        let bento = IslandExpandedLayout.shelfRight.bodySize(cardCount: 5, hasShelf: true)
        check(bento.height == 309, "A fourth compact card should enlarge both bento columns")
        check(IslandExpandedLayout.shelfRight.usesGrid(cardCount: 4, hasShelf: false),
              "Four compact cards should wrap into two columns when the shelf is disabled")
    }

    private static func testSystemCalendarDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func day(_ number: Int) -> DateInterval {
            let date = calendar.date(from: DateComponents(year: 2024, month: 3, day: number))!
            return calendar.dateInterval(of: .day, for: date)!
        }

        let allDay = SystemCalendarEvent(title: "Conference", calendarName: "Work",
                                         start: day(9).start, end: day(10).end, isAllDay: true)
        check(allDay.occurs(in: day(9)) && allDay.occurs(in: day(10)),
              "Multi-day events should appear on each day, including a DST transition")
        check(!allDay.occurs(in: day(8)) && !allDay.occurs(in: day(11)),
              "An event ending at midnight should not appear on the following day")
        let point = SystemCalendarEvent(title: "Milestone", calendarName: "Work",
                                        start: day(10).start, end: day(10).start, isAllDay: false)
        check(point.occurs(in: day(10)), "A zero-duration event should appear on its start date")

        let dateOnly = SystemCalendarReminder(title: "All day", listName: "Inbox",
                                              dueComponents: DateComponents(timeZone: .gmt, year: 2024, month: 3, day: 10),
                                              calendar: calendar)
        check(dateOnly.due.map { day(10).contains($0) } == true && !dateOnly.hasDueTime,
              "A date-only reminder should keep its civil date when viewed in another time zone")
        let timed = SystemCalendarReminder(title: "Timed", listName: "Inbox",
                                           dueComponents: DateComponents(timeZone: .gmt, year: 2024, month: 3, day: 11, hour: 1),
                                           calendar: calendar)
        check(timed.due.map { day(10).contains($0) } == true && timed.hasDueTime,
              "A timed reminder should use its designated time zone")
        let floating = SystemCalendarReminder(title: "Floating", listName: "Inbox",
                                              dueComponents: DateComponents(year: 2024, month: 3, day: 11, hour: 1),
                                              calendar: calendar)
        check(floating.due.map { day(11).contains($0) } == true && floating.hasDueTime,
              "A floating timed reminder should use the local time zone")
        let undated = SystemCalendarReminder(title: "Someday", listName: "Inbox", dueComponents: nil, calendar: calendar)
        check(undated.due == nil && !undated.hasDueTime, "An undated reminder should not be assigned a day")
    }

    private static func testHolidayDataAndLunarCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let lunar = CalendarCountdown.lunarCalendar(timeZone: calendar.timeZone)
        let today = CountdownDay(isoDate: "2026-10-01")!
        let now = today.date(in: calendar)!
        let grid = CalendarCountdown.monthGrid(containing: now, calendar: calendar)
        check(grid.count == 42, "Calendar should show six complete weeks")
        check(calendar.component(.weekday, from: grid[0]) == 2, "Calendar should begin on a Monday")
        check(CountdownDay(isoDate: "2026-02-29") == nil, "Holiday decoder should reject nonexistent days")
        let newYear = CountdownDay(isoDate: "2026-02-17")!.date(in: calendar)!
        check(CalendarCountdown.lunarLabel(for: newYear, calendar: lunar, includingMonth: true) == "正月初一",
              "Lunar conversion should show the Chinese New Year date")
        let leapMonth = CountdownDay(isoDate: "2025-07-25")!.date(in: calendar)!
        check(CalendarCountdown.lunarLabel(for: leapMonth, calendar: lunar) == "闰六月",
              "The month grid should distinguish a lunar leap month")
        let months2025 = CalendarCountdown.lunarYearStartingIn(2025, gregorian: calendar)
        check(months2025.count == 13 && months2025.contains { calendar.isDate($0, inSameDayAs: leapMonth) },
              "The lunar editor should enumerate the leap month separately")
        let months2026 = CalendarCountdown.lunarYearStartingIn(2026, gregorian: calendar)
        check(months2026.count == 12 && months2026.first.map { calendar.isDate($0, inSameDayAs: newYear) } == true,
              "The lunar editor should start with the correct new year")


        let json = """
        {"year":2026,"days":[{"name":"国庆节","date":"2026-10-01","isOffDay":true},
        {"name":"国庆节","date":"2026-10-02","isOffDay":true},
        {"name":"国庆节","date":"2026-10-10","isOffDay":false},
        {"name":"元旦","date":"2027-01-01","isOffDay":true}]}
        """
        let year = try! JSONDecoder().decode(ChinaHolidayYear.self, from: Data(json.utf8))
        check(year.validatedDays(for: 2025) == nil, "A holiday dataset cannot be saved under a different year")
        let days = year.validatedDays(for: 2026) ?? []
        check(days.count == 4 && days.contains { !$0.isOffDay }, "The data should preserve makeup workdays and cross-year dates")
        let countdown = HolidayCountdown.upcoming(in: days, now: now, calendar: calendar)
        check(countdown.map(\.holiday.name) == ["国庆节", "元旦"] && countdown.first?.days == 0,
              "Holiday countdown should group the break and ignore makeup workdays")
        check(IslandExpandedCard.moving(.calendar, onto: .audio, in: IslandExpandedCard.allCases)
                == [.performance, .calendar, .audio, .focus, .shelf, .bookmarks],
              "Dragging a card earlier should preserve the relative order of other cards")
        check(IslandExpandedCard.moving(.performance, onto: .focus, in: [.performance, .audio, .focus, .calendar])
                == [.audio, .focus, .performance, .calendar],
              "Dragging a card later should put it in the target position")
    }

    private static func testExpandedInteractionRect() {
        let geometry = IslandGeometry.compute(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 37, notchWidth: 180, style: .notch, state: .expanded
        )
        let duringResize = NSRect(x: 26, y: 22, width: 420, height: 244)
        let interactionRect = geometry.interactionRect(for: duringResize)
        check(interactionRect.contains(NSPoint(x: duringResize.midX, y: duringResize.midY)),
              "The pointer in the card area should be treated as inside the panel")
        check(interactionRect.contains(NSPoint(x: duringResize.minX - 5, y: duringResize.maxY - 1)),
              "The pointer on the notch shoulder should be treated as inside the panel")
        check(!interactionRect.contains(NSPoint(x: duringResize.midX, y: duringResize.minY - 1)),
              "The pointer below the panel should be treated as outside")
        check(!interactionRect.contains(NSPoint(x: duringResize.midX, y: duringResize.maxY + 1)),
              "Tracking should follow the visible panel during a resize")
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

        check(DynamicIslandFeature.allCases.contains(.calendarCountdown), "Should expose the calendar module")
        for feature in DynamicIslandFeature.allCases {
            check(!feature.title.isEmpty, "\(feature.rawValue) title should not be empty")
            check(!feature.subtitle.isEmpty, "\(feature.rawValue) subtitle should not be empty")
            check(!feature.symbolName.isEmpty, "\(feature.rawValue) symbolName should not be empty")
            check(feature.defaultEnabled, "\(feature.rawValue) should default to enabled")
        }
    }

    private static func testCollapsedCustomizationAndShelfPreview() {
        check(CollapsedMetricItem.allCases.count == 7, "Should expose each network direction separately")
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
        check(snap.formatCollapsedMetric(.downloadSpeed) == "↓12K", "Download collapsed format")
        check(snap.formatCollapsedMetric(.uploadSpeed) == "↑2K", "Upload collapsed format")
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

        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let expected = "# File shelf test"
        do {
            try expected.write(to: fixture, atomically: true, encoding: .utf8)
            check(ShelfPreviewHelper.readTextSnippet(from: fixture) == expected,
                  "Should read Markdown text from the shelf fixture")
        } catch {
            check(false, "Could not create shelf fixture: \(error)")
        }
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
