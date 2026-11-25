import AppKit

private final class CalendarCountdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CalendarListDocument: NSView {
    override var isFlipped: Bool { true }
}

final class CalendarCountdownWindowController: NSWindowController {
    private weak var manager: DynamicIslandManager?
    private let holidays = ChinaHolidayCalendar.shared
    private var holidayObserver: NSObjectProtocol?
    private let monthGrid = CalendarMonthGrid()
    private let monthHeading = NSTextField(labelWithString: "")
    private let showLunar = NSButton(checkboxWithTitle: "显示农历", target: nil, action: nil)
    private let datePicker = NSDatePicker()
    private let dateMode = NSPopUpButton()
    private let lunarYear = NSPopUpButton()
    private let lunarMonth = NSPopUpButton()
    private let lunarDay = NSPopUpButton()
    private let lunarInputs = NSStackView()
    private var lunarMonths: [Date] = []
    private var lunarYears: ClosedRange<Int> = 1900...2100
    private let titleField = NSTextField(string: "")
    private let selectedDateLabel = NSTextField(wrappingLabelWithString: "")
    private let dateSummary = NSTextField(labelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "添加事件", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除事件", target: nil, action: nil)
    private let mode = NSSegmentedControl(labels: ["我的倒计时", "节假日"], trackingMode: .selectOne, target: nil, action: nil)
    private let eventList = NSStackView()
    private let editor = NSStackView()
    private var eventRows: [(CalendarCountdownEvent, Int)] = []
    private var holidayRows: [HolidayCountdown] = []
    private var month = Date()
    private var selectedID: UUID?
    private var lastRefreshDay: CountdownDay?

    private static let showLunarKey = "MakeTools.DynamicIsland.calendarShowsLunar"

    init(manager: DynamicIslandManager) {
        self.manager = manager
        let panel = CalendarCountdownPanel(contentRect: NSRect(x: 0, y: 0, width: 820, height: 465),
                                            styleMask: [.titled, .closable, .nonactivatingPanel],
                                            backing: .buffered, defer: false)
        panel.title = "日历与日期倒计时"
        panel.contentMinSize = NSSize(width: 820, height: 465)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        configureView()
        panel.setContentSize(panel.contentMinSize)
        holidayObserver = NotificationCenter.default.addObserver(forName: ChinaHolidayCalendar.didUpdate, object: holidays, queue: .main) {
            [weak self] _ in
            guard let self, window?.isVisible == true else { return }
            render()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let holidayObserver { NotificationCenter.default.removeObserver(holidayObserver) }
    }

    func show(from anchor: NSView) {
        guard let window, let parent = anchor.window else { return }
        if !window.isVisible {
            if let screen = parent.screen {
                let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
                let x = max(visible.minX, min(parent.frame.midX - window.frame.width / 2, visible.maxX - window.frame.width))
                let y = min(max(parent.frame.minY - 8, visible.minY + window.frame.height), visible.maxY)
                window.setFrameTopLeftPoint(NSPoint(x: x, y: y))
            } else {
                window.center()
            }
        }
        window.makeKeyAndOrderFront(nil)
        render()
    }

    func refresh(now: Date, calendar: Calendar) {
        guard window?.isVisible == true else { return }
        let day = CountdownDay(date: now, calendar: calendar)
        if day != lastRefreshDay { render(now: now) }
    }

    private func configureView() {
        guard let window, let root = window.contentView else { return }
        let previous = button("上个月", symbol: "chevron.left", action: #selector(changeMonth(_:)))
        previous.tag = -1
        let next = button("下个月", symbol: "chevron.right", action: #selector(changeMonth(_:)))
        next.tag = 1
        monthHeading.font = .systemFont(ofSize: 20, weight: .semibold)
        monthHeading.setContentCompressionResistancePriority(.required, for: .horizontal)
        let today = button("今天", symbol: "calendar", action: #selector(handleToday))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        let monthHeader = horizontal([previous, next, monthHeading, spacer, today], spacing: 7)

        showLunar.target = self
        showLunar.action = #selector(toggleLunar)
        showLunar.state = (UserDefaults.standard.object(forKey: Self.showLunarKey) as? Bool ?? true) ? .on : .off
        let legend = NSTextField(labelWithString: "休  节假日     班  调休补班")
        legend.font = .systemFont(ofSize: 11)
        legend.textColor = .secondaryLabelColor
        let calendarFooter = horizontal([showLunar, legend], spacing: 14)
        monthGrid.onSelectDate = { [weak self] date in self?.selectDate(date) }
        let monthColumn = vertical([monthHeader, monthGrid, calendarFooter], spacing: 12)
        for item in [monthHeader, monthGrid, calendarFooter] {
            item.widthAnchor.constraint(equalTo: monthColumn.widthAnchor).isActive = true
        }

        mode.selectedSegment = 0
        mode.target = self
        mode.action = #selector(handleTab)
        selectedDateLabel.font = .systemFont(ofSize: 12)
        selectedDateLabel.textColor = .secondaryLabelColor
        selectedDateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateSummary.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        feedback.font = .systemFont(ofSize: 11)
        feedback.textColor = .secondaryLabelColor

        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.calendar = CalendarCountdown.localCalendar
        datePicker.dateValue = Date()
        datePicker.target = self
        datePicker.action = #selector(handleDateChanged)
        datePicker.setAccessibilityLabel("事件日期")
        dateMode.addItems(withTitles: ["公历", "农历"])
        dateMode.target = self
        dateMode.action = #selector(handleDateModeChanged)
        dateMode.setAccessibilityLabel("事件日期历法")
        titleField.placeholderString = "事件名称"
        titleField.setAccessibilityLabel("事件名称")

        setup(saveButton, symbol: "checkmark", action: #selector(handleSave))
        saveButton.keyEquivalent = "\r"
        setup(deleteButton, symbol: "trash", action: #selector(handleDelete))
        let add = button("新增", symbol: "plus", action: #selector(startNewEvent))
        lunarInputs.orientation = .horizontal
        lunarInputs.alignment = .centerY
        lunarInputs.spacing = 4
        for (picker, label) in [(lunarYear, "农历年份"), (lunarMonth, "农历月份"), (lunarDay, "农历日期")] {
            picker.controlSize = .small
            picker.target = self
            picker.action = #selector(handleLunarDateChanged(_:))
            picker.setAccessibilityLabel(label)
            lunarInputs.addArrangedSubview(picker)
        }
        lunarInputs.isHidden = true
        let dateInputs = horizontal([dateMode, datePicker, lunarInputs], spacing: 6)
        let buttons = horizontal([saveButton, add, deleteButton], spacing: 7)
        editor.orientation = .vertical
        editor.alignment = .leading
        editor.spacing = 8
        for view in [titleField, dateInputs, buttons] { editor.addArrangedSubview(view) }
        titleField.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true

        let list = configureListScrollView()
        let sidebar = vertical([mode, selectedDateLabel, dateSummary, list, editor, feedback], spacing: 10)
        for item in [mode, selectedDateLabel, list, editor, feedback] {
            item.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        }

        let separator = NSBox()
        separator.boxType = .separator
        for view in [monthColumn, separator, sidebar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            monthColumn.topAnchor.constraint(equalTo: root.topAnchor, constant: 19),
            monthColumn.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            monthColumn.widthAnchor.constraint(equalToConstant: 445),
            monthColumn.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            separator.leadingAnchor.constraint(equalTo: monthColumn.trailingAnchor, constant: 18),
            separator.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            separator.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            separator.widthAnchor.constraint(equalToConstant: 1),
            sidebar.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 16),
            sidebar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor, constant: 19),
            sidebar.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            list.heightAnchor.constraint(equalToConstant: 174)
        ])
        window.initialFirstResponder = titleField
        updateEditorButtons()
    }

    private func configureListScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = CalendarListDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        eventList.orientation = .vertical
        eventList.alignment = .leading
        eventList.spacing = 6
        eventList.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(eventList)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            eventList.topAnchor.constraint(equalTo: document.topAnchor),
            eventList.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            eventList.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            eventList.trailingAnchor.constraint(equalTo: document.trailingAnchor)
        ])
        return scroll
    }

    private func horizontal(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func button(_ title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        setup(button, symbol: symbol, action: action)
        return button
    }

    private func setup(_ button: NSButton, symbol: String, action: Selector) {
        ToolAppearance.configure(button, symbol: symbol)
        button.target = self
        button.action = action
    }

    private func render(now: Date = Date()) {
        let calendar = CalendarCountdown.localCalendar
        let today = CountdownDay(date: now, calendar: calendar)
        lastRefreshDay = today
        holidays.refresh(around: today.year, now: now)
        let displayedYear = calendar.component(.year, from: month)
        if displayedYear != today.year { holidays.refresh(around: displayedYear, now: now) }

        let parts = calendar.dateComponents([.year, .month], from: month)
        monthHeading.stringValue = "\(parts.year ?? today.year) 年 \(parts.month ?? today.month) 月"
        let lunar = showLunar.state == .on
        monthGrid.update(month: month, selected: datePicker.dateValue, now: now, calendar: calendar,
                         showLunar: lunar, holidays: holidays.daysByDate)
        let day = CountdownDay(date: datePicker.dateValue, calendar: calendar)
        let formatted = DateFormatter.localizedString(from: datePicker.dateValue, dateStyle: .medium, timeStyle: .none)
        let lunarText = lunar ? CalendarCountdown.lunarLabel(
            for: datePicker.dateValue, calendar: CalendarCountdown.lunarCalendar(timeZone: calendar.timeZone), includingMonth: true
        ) : ""
        let holidayText = holidays.daysByDate[day].map { "\($0.name) · \($0.isOffDay ? "休息" : "补班")" } ?? ""
        selectedDateLabel.stringValue = [formatted, lunarText, holidayText].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        dateSummary.stringValue = day.days(from: now, calendar: calendar).map(CalendarCountdown.status(for:)) ?? "日期不可用"
        renderList(now: now, calendar: calendar)
    }

    private func renderList(now: Date, calendar: Calendar) {
        for row in eventList.arrangedSubviews { eventList.removeArrangedSubview(row); row.removeFromSuperview() }
        let showHolidays = mode.selectedSegment == 1
        editor.isHidden = showHolidays
        if showHolidays {
            holidayRows = HolidayCountdown.upcoming(in: Array(holidays.daysByDate.values), now: now, calendar: calendar)
            if holidayRows.isEmpty {
                let syncing = holidays.isSyncing(around: calendar.component(.year, from: now))
                appendEmptyRow(syncing ? "正在同步中国大陆节假日…" : "暂无已同步的近期节假日")
            }
            for (index, item) in holidayRows.enumerated() {
                appendRow(item.holiday.name, day: item.holiday.day, days: item.days, symbol: "calendar.badge.checkmark",
                          index: index, selected: item.holiday.day == CountdownDay(date: datePicker.dateValue, calendar: calendar))
            }
        } else {
            eventRows = CalendarCountdown.orderedEvents(manager?.calendarEvents ?? [], now: now, calendar: calendar)
            if eventRows.isEmpty { appendEmptyRow("选择日期并添加事件") }
            for (index, item) in eventRows.enumerated() {
                appendRow(item.0.title, day: item.0.day, days: item.1, symbol: "hourglass", index: index,
                          selected: item.0.id == selectedID)
            }
        }
    }

    private func appendEmptyRow(_ title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        eventList.addArrangedSubview(label)
    }

    private func appendRow(_ title: String, day: CountdownDay, days: Int, symbol: String, index: Int, selected: Bool) {
        let count = CalendarCountdown.status(for: days)
        let row = button("\(title)  ·  \(count)", symbol: symbol, action: #selector(handleListSelection(_:)))
        row.tag = index
        row.alignment = .left
        row.cell?.lineBreakMode = .byTruncatingTail
        row.toolTip = "\(title) · \(day.month) 月 \(day.day) 日 · \(count)"
        if selected { row.contentTintColor = .controlAccentColor }
        eventList.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: eventList.widthAnchor).isActive = true
    }

    private func selectDate(_ date: Date) {
        datePicker.dateValue = date
        if dateMode.indexOfSelectedItem == 1 { showLunarDate(date) }
        month = date
        if selectedID != nil { startNewEvent() } else { render() }
    }

    private func updateEditorButtons() {
        saveButton.title = selectedID == nil ? "添加事件" : "更新事件"
        deleteButton.isEnabled = selectedID != nil
    }

    @objc private func changeMonth(_ sender: NSButton) {
        let calendar = CalendarCountdown.localCalendar
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let result = calendar.date(byAdding: .month, value: sender.tag, to: start) else { return }
        month = result
        render()
    }

    @objc private func handleToday() { selectDate(Date()) }

    @objc private func toggleLunar() {
        UserDefaults.standard.set(showLunar.state == .on, forKey: Self.showLunarKey)
        render()
    }

    @objc private func handleTab() {
        feedback.stringValue = ""
        render()
    }

    @objc private func handleDateChanged() {
        month = datePicker.dateValue
        feedback.stringValue = ""
        render()
    }

    @objc private func handleDateModeChanged() {
        let isLunar = dateMode.indexOfSelectedItem == 1
        datePicker.isHidden = isLunar
        lunarInputs.isHidden = !isLunar
        if isLunar { showLunarDate(datePicker.dateValue) }
    }

    private func showLunarDate(_ date: Date) {
        let gregorian = CalendarCountdown.localCalendar
        let lunar = CalendarCountdown.lunarCalendar(timeZone: gregorian.timeZone)
        guard let yearStart = lunar.dateInterval(of: .year, for: date)?.start else { return }
        let year = gregorian.component(.year, from: yearStart)
        if lunarYear.numberOfItems == 0 || !lunarYears.contains(year) {
            lunarYears = min(lunarYears.lowerBound, year)...max(lunarYears.upperBound, year)
            lunarYear.removeAllItems()
            lunarYear.addItems(withTitles: lunarYears.map { "\($0)年" })
        }
        lunarYear.selectItem(at: year - lunarYears.lowerBound)
        loadLunarMonths(year: year, gregorian: gregorian)
        let monthIndex = lunarMonths.lastIndex { $0 <= date } ?? 0
        lunarMonth.selectItem(at: monthIndex)
        loadLunarDays(preferredDay: lunar.component(.day, from: date), lunar: lunar)
    }

    private func loadLunarMonths(year: Int, gregorian: Calendar) {
        lunarMonths = CalendarCountdown.lunarYearStartingIn(year, gregorian: gregorian)
        let lunar = CalendarCountdown.lunarCalendar(timeZone: gregorian.timeZone)
        lunarMonth.removeAllItems()
        lunarMonth.addItems(withTitles: lunarMonths.map { CalendarCountdown.lunarLabel(for: $0, calendar: lunar) })
    }

    private func loadLunarDays(preferredDay: Int, lunar: Calendar) {
        let monthIndex = lunarMonth.indexOfSelectedItem
        guard lunarMonths.indices.contains(monthIndex) else { return }
        let start = lunarMonths[monthIndex]
        guard let range = lunar.range(of: .day, in: .month, for: start) else { return }
        lunarDay.removeAllItems()
        lunarDay.addItems(withTitles: range.map { "\($0)日" })
        lunarDay.selectItem(at: min(max(0, preferredDay - 1), range.count - 1))
    }

    @objc private func handleLunarDateChanged(_ sender: NSPopUpButton) {
        let gregorian = CalendarCountdown.localCalendar
        let lunar = CalendarCountdown.lunarCalendar(timeZone: gregorian.timeZone)
        let previous = lunar.dateComponents([.month, .day], from: datePicker.dateValue)
        if sender === lunarYear {
            loadLunarMonths(year: lunarYears.lowerBound + lunarYear.indexOfSelectedItem, gregorian: gregorian)
            let index = lunarMonths.firstIndex {
                let parts = lunar.dateComponents([.month, .day], from: $0)
                return parts.month == previous.month && parts.isLeapMonth == previous.isLeapMonth
            } ?? lunarMonths.firstIndex { lunar.component(.month, from: $0) == previous.month } ?? 0
            lunarMonth.selectItem(at: index)
        }
        if sender !== lunarDay { loadLunarDays(preferredDay: previous.day ?? 1, lunar: lunar) }
        let monthIndex = lunarMonth.indexOfSelectedItem
        guard lunarMonths.indices.contains(monthIndex), lunarDay.indexOfSelectedItem >= 0,
              let date = gregorian.date(byAdding: .day, value: lunarDay.indexOfSelectedItem, to: lunarMonths[monthIndex])
        else { return }
        datePicker.dateValue = date
        handleDateChanged()
    }

    @objc private func startNewEvent() {
        selectedID = nil
        titleField.stringValue = ""
        feedback.stringValue = ""
        updateEditorButtons()
        render()
    }

    @objc private func handleListSelection(_ sender: NSButton) {
        let calendar = CalendarCountdown.localCalendar
        if mode.selectedSegment == 1 {
            guard holidayRows.indices.contains(sender.tag),
                  let date = holidayRows[sender.tag].holiday.day.date(in: calendar) else { return }
            selectDate(date)
        } else {
            guard eventRows.indices.contains(sender.tag),
                  let date = eventRows[sender.tag].0.day.date(in: calendar) else { return }
            let event = eventRows[sender.tag].0
            selectedID = event.id
            titleField.stringValue = event.title
            dateMode.selectItem(at: event.usesLunarCalendar == true ? 1 : 0)
            datePicker.dateValue = date
            handleDateModeChanged()
            month = date
            feedback.stringValue = ""
            updateEditorButtons()
            render()
        }
    }

    @objc private func handleSave() {
        guard let manager else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { feedback.stringValue = "请输入事件名称。"; return }
        let day = CountdownDay(date: datePicker.dateValue, calendar: CalendarCountdown.localCalendar)
        let event = CalendarCountdownEvent(id: selectedID ?? UUID(), title: title, day: day,
                                           usesLunarCalendar: dateMode.indexOfSelectedItem == 1)
        do {
            try manager.saveCalendarEvent(event)
            selectedID = event.id
            feedback.stringValue = "已保存。"
            updateEditorButtons()
            render()
        } catch {
            feedback.stringValue = "保存失败，请重试。"
        }
    }

    @objc private func handleDelete() {
        guard let manager, let selectedID else { return }
        do {
            try manager.removeCalendarEvent(id: selectedID)
            startNewEvent()
            feedback.stringValue = "已删除。"
        } catch {
            feedback.stringValue = "删除失败，请重试。"
        }
    }
}
