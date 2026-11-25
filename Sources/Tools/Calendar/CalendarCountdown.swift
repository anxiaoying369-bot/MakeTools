import Foundation

struct CountdownDay: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    init?(isoDate: String) {
        let parts = isoDate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = date(in: calendar), Self(date: date, calendar: calendar) == self else { return nil }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(in calendar: Calendar) -> Date? {
        // Noon avoids most clock changes at midnight and preserves the chosen civil date.
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    func days(from now: Date, calendar: Calendar) -> Int? {
        guard let date = date(in: calendar) else { return nil }
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day
    }
}

struct CalendarCountdownEvent: Codable, Equatable {
    let id: UUID
    let title: String
    let day: CountdownDay
    var usesLunarCalendar: Bool? = nil
}

enum CalendarCountdown {
    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.locale = .autoupdatingCurrent
        return calendar
    }

    static func lunarCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    static func lunarYearStartingIn(_ year: Int, gregorian: Calendar) -> [Date] {
        guard let spring = gregorian.date(from: DateComponents(year: year, month: 3, day: 10, hour: 12))
        else { return [] }

        let lunar = lunarCalendar(timeZone: gregorian.timeZone)
        guard let interval = lunar.dateInterval(of: .year, for: spring) else { return [] }
        var months: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            months.append(cursor)
            guard let next = lunar.dateInterval(of: .month, for: cursor)?.end, next > cursor else { break }
            cursor = next
        }
        return months
    }

    static func lunarLabel(for date: Date, calendar: Calendar, includingMonth: Bool = false) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        let months = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        guard let month = components.month, (1...12).contains(month),
              let day = components.day, (1...30).contains(day) else { return "" }
        let monthName = (components.isLeapMonth == true ? "闰" : "") + months[month - 1] + "月"
        if day == 1 && !includingMonth { return monthName }

        let dayName: String
        switch day {
        case 1...10: dayName = "初" + digits[day - 1]
        case 11...19: dayName = "十" + digits[day - 11]
        case 20: dayName = "二十"
        case 21...29: dayName = "廿" + digits[day - 21]
        default: dayName = "三十"
        }
        return includingMonth ? monthName + dayName : dayName
    }

    static func monthGrid(containing date: Date, calendar: Calendar) -> [Date] {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start else { return [] }
        let preceding = (calendar.component(.weekday, from: monthStart) + 5) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - preceding, to: monthStart) }
    }

    static func status(for days: Int) -> String {
        if days < 0 { return "已过去 \(-days) 天" }
        if days > 0 { return "还有 \(days) 天" }
        return "就是今天"
    }

    static func orderedEvents(
        _ events: [CalendarCountdownEvent], now: Date, calendar: Calendar
    ) -> [(event: CalendarCountdownEvent, days: Int)] {
        events.compactMap { event in
            event.day.days(from: now, calendar: calendar).map { (event: event, days: $0) }
        }.sorted { lhs, rhs in
            if lhs.days == rhs.days {
                return lhs.event.title.localizedStandardCompare(rhs.event.title) == .orderedAscending
            }
            if lhs.days < 0 && rhs.days < 0 { return lhs.days > rhs.days }
            if (lhs.days < 0) != (rhs.days < 0) { return lhs.days >= 0 }
            return lhs.days < rhs.days
        }
    }
}

struct CalendarCountdownStore {
    var defaults: UserDefaults = .standard
    private let key = "MakeTools.DynamicIsland.calendarEvents"

    func load() -> [CalendarCountdownEvent] {
        guard let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([CalendarCountdownEvent].self, from: data) else { return [] }
        return events
    }

    func save(_ events: [CalendarCountdownEvent]) throws {
        defaults.set(try JSONEncoder().encode(events), forKey: key)
    }
}
