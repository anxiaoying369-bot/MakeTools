import Foundation

struct ChinaHoliday: Equatable {
    let name: String
    let day: CountdownDay
    let isOffDay: Bool
}

struct ChinaHolidayYear: Codable {
    struct Entry: Codable {
        let name: String
        let date: String
        let isOffDay: Bool
    }

    let year: Int
    let days: [Entry]

    func validatedDays(for expectedYear: Int) -> [ChinaHoliday]? {
        guard year == expectedYear, (2000...2099).contains(year), !days.isEmpty, days.count <= 366 else { return nil }
        var result: [ChinaHoliday] = []
        for item in days {
            guard let day = CountdownDay(isoDate: item.date), (year - 1...year + 1).contains(day.year),
                  !item.name.isEmpty, item.name.count <= 60 else { return nil }
            result.append(ChinaHoliday(name: item.name, day: day, isOffDay: item.isOffDay))
        }
        return result
    }
}

struct HolidayCountdown {
    let holiday: ChinaHoliday
    let days: Int

    static func upcoming(in holidays: [ChinaHoliday], now: Date, calendar: Calendar) -> [Self] {
        let today = CountdownDay(date: now, calendar: calendar)
        let sorted = holidays.filter { $0.isOffDay && $0.day >= today }.sorted { $0.day < $1.day }
        var lastDayOfBreak: Date?
        var lastName: String?
        return sorted.compactMap { holiday in
            guard let date = holiday.day.date(in: calendar),
                  let days = holiday.day.days(from: now, calendar: calendar) else { return nil }
            let interval = lastDayOfBreak.flatMap { calendar.dateComponents([.day], from: $0, to: date).day }
            let continuesBreak = lastName == holiday.name && interval == 1
            lastDayOfBreak = date
            lastName = holiday.name
            return continuesBreak ? nil : Self(holiday: holiday, days: days)
        }

    }
}

/// Fetches the dates and makeup workdays published by the China State Council.
final class ChinaHolidayCalendar {
    static let shared = ChinaHolidayCalendar()
    static let didUpdate = Notification.Name("MakeTools.ChinaHolidayCalendarDidUpdate")

    private struct CachedYear: Codable {
        let updatedAt: Date
        let holidays: ChinaHolidayYear
    }

    private static let cacheKey = "MakeTools.DynamicIsland.chinaHolidays"
    private let defaults: UserDefaults
    private var cache: [Int: CachedYear]
    private var nextRequest: [Int: Date] = [:]
    private var inFlight = Set<Int>()
    private(set) var revision = 0
    private(set) var daysByDate: [CountdownDay: ChinaHoliday] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cache = defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode([Int: CachedYear].self, from: $0) } ?? [:]
        updateDays()
    }

    func refresh(around year: Int, now: Date = Date()) {
        for year in [year, year + 1] where (2000...2099).contains(year) {
            if let notBefore = nextRequest[year], now < notBefore { continue }
            if let entry = cache[year], now.timeIntervalSince(entry.updatedAt) < 86_400 { continue }
            guard inFlight.insert(year).inserted else { continue }
            fetch(year: year)
        }
    }

    func isSyncing(around year: Int) -> Bool {
        inFlight.contains(year) || inFlight.contains(year + 1)
    }

    private func fetch(year: Int, mirror: Bool = false) {
        let base = mirror
            ? "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/"
            : "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/"
        guard let url = URL(string: base + "\(year).json") else { return }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let result: ChinaHolidayYear?
            if let data, data.count <= 128_000, (response as? HTTPURLResponse)?.statusCode == 200,
               let decoded = try? JSONDecoder().decode(ChinaHolidayYear.self, from: data),
               decoded.validatedDays(for: year) != nil {
                result = decoded
            } else {
                result = nil
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let result {
                    inFlight.remove(year)
                    nextRequest.removeValue(forKey: year)
                    cache[year] = CachedYear(updatedAt: Date(), holidays: result)
                    if let data = try? JSONEncoder().encode(cache) {
                        defaults.set(data, forKey: Self.cacheKey)
                    }
                    updateDays()
                    revision += 1
                    NotificationCenter.default.post(name: Self.didUpdate, object: self)
                } else if !mirror {
                    fetch(year: year, mirror: true)
                } else {
                    inFlight.remove(year)
                    nextRequest[year] = Date().addingTimeInterval(900)
                    NotificationCenter.default.post(name: Self.didUpdate, object: self)
                }
            }
        }.resume()
    }

    private func updateDays() {
        daysByDate.removeAll(keepingCapacity: true)
        for year in cache.keys.sorted() {
            for day in cache[year]?.holidays.validatedDays(for: year) ?? [] {
                daysByDate[day.day] = day
            }
        }
    }
}
