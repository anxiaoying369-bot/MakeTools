import AppKit

private final class CalendarDayButton: NSButton {
    private var isSelectedDay = false
    private var isToday = false

    func update(date: Date, isCurrentMonth: Bool, isSelected: Bool, isToday: Bool, lunar: String, holiday: CalendarHoliday?,
                hasEvents: Bool, hasReminders: Bool) {
        self.isSelectedDay = isSelected
        self.isToday = isToday
        let calendar = CalendarCountdown.localCalendar
        let number = String(calendar.component(.day, from: date))
        let muted = NSColor.tertiaryLabelColor
        let primary: NSColor = isSelected ? ToolAppearance.accent : (isCurrentMonth ? .labelColor : muted)
        let secondary = isCurrentMonth ? NSColor.secondaryLabelColor : muted
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: number, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 16, weight: isToday || isSelected ? .bold : .semibold),
            .foregroundColor: primary, .paragraphStyle: paragraph
        ])
        if let holiday {
            let mark = holiday.isOffDay ? L10n.text("calendar.off", " 休") : L10n.text("calendar.work", " 班")
            text.append(NSAttributedString(string: mark, attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: holiday.isOffDay ? NSColor.systemGreen : NSColor.systemOrange
            ]))
        }
        for (shown, color) in [(hasEvents, NSColor.systemBlue), (hasReminders, NSColor.systemOrange)] where shown {
            text.append(NSAttributedString(string: " •", attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: color
            ]))
        }
        let caption = holiday?.name ?? lunar
        if !caption.isEmpty {
            text.append(NSAttributedString(string: "\n\(caption)", attributes: [
                .font: NSFont.systemFont(ofSize: 10), .foregroundColor: secondary, .paragraphStyle: paragraph
            ]))
        }
        attributedTitle = text
        let dateName = date.formatted(.dateTime.year().month(.wide).day().locale(L10n.locale))
        let details = [
            dateName, lunar, holiday.map { "\($0.name) · \($0.isOffDay ? L10n.text("calendar.dayOff", "休息") : L10n.text("calendar.makeupDay", "补班"))" } ?? "",
            hasEvents ? L10n.text("calendar.hasEvents", "有日程") : "", hasReminders ? L10n.text("calendar.hasIncompleteReminders", "有未完成待办") : ""
        ]
            .filter { !$0.isEmpty }.joined(separator: "，")
        toolTip = details
        setAccessibilityLabel(details)
        setAccessibilityValue(isSelected ? L10n.text("calendar.selected", "已选中") : nil)
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isSelectedDay
                ? ToolAppearance.tint.cgColor
                : ToolAppearance.canvas.cgColor
            layer?.borderColor = (isSelectedDay || isToday)
                ? ToolAppearance.accent.withAlphaComponent(isSelectedDay ? 0.78 : 0.5).cgColor
                : ToolAppearance.line.cgColor
        }
    }
}

final class CalendarMonthGrid: NSView {
    var onSelectDate: ((Date) -> Void)?
    private var dates: [Date] = []
    private var buttons: [CalendarDayButton] = []
    private var weekdayLabels: [NSTextField] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        weekdayLabels = (0..<7).map { _ in
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }

        let headings = NSStackView(views: weekdayLabels)
        headings.orientation = .horizontal
        headings.distribution = .fillEqually
        headings.spacing = 5
        let stack = NSStackView(views: [headings])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        headings.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        for week in 0..<6 {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = 5
            for weekday in 0..<7 {
                let button = CalendarDayButton(frame: .zero)
                button.target = self
                button.action = #selector(handleDay(_:))
                button.tag = week * 7 + weekday
                button.isBordered = false
                button.alignment = .center
                button.cell?.wraps = true
                button.wantsLayer = true
                button.layer?.cornerRadius = 9
                button.layer?.cornerCurve = .continuous
                button.layer?.borderWidth = 1
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                row.addArrangedSubview(button)
                button.heightAnchor.constraint(equalToConstant: 45).isActive = true
                buttons.append(button)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(dates: [Date], month: Date, selected: Date, now: Date, calendar: Calendar, showLunar: Bool,
                holidays: [CountdownDay: CalendarHoliday], eventDays: Set<CountdownDay>, reminderDays: Set<CountdownDay>) {
        self.dates = dates
        let names = [
            L10n.text("calendar.sun", "日"), L10n.text("calendar.mon", "一"),
            L10n.text("calendar.tue", "二"), L10n.text("calendar.wed", "三"),
            L10n.text("calendar.thu", "四"), L10n.text("calendar.fri", "五"),
            L10n.text("calendar.sat", "六")
        ]
        for (date, label) in zip(dates, weekdayLabels) {
            label.stringValue = names[calendar.component(.weekday, from: date) - 1]
        }
        let lunarCalendar = CalendarCountdown.lunarCalendar(timeZone: calendar.timeZone)
        for (date, button) in zip(dates, buttons) {
            let day = CountdownDay(date: date, calendar: calendar)
            button.update(date: date, isCurrentMonth: calendar.isDate(date, equalTo: month, toGranularity: .month),
                          isSelected: calendar.isDate(date, inSameDayAs: selected),
                          isToday: calendar.isDate(date, inSameDayAs: now),
                          lunar: showLunar ? CalendarCountdown.lunarLabel(for: date, calendar: lunarCalendar) : "",
                          holiday: holidays[day], hasEvents: eventDays.contains(day), hasReminders: reminderDays.contains(day))
        }
    }

    @objc private func handleDay(_ sender: NSButton) {
        guard dates.indices.contains(sender.tag) else { return }
        onSelectDate?(dates[sender.tag])
    }
}
