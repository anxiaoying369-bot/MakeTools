import Foundation

struct CalendarHoliday: Equatable {
    let name: String
    let day: CountdownDay
    let isOffDay: Bool
}

struct HolidayYear: Codable {
    struct Entry: Codable {
        let name: String
        let date: String
        let isOffDay: Bool
        var englishName: String? = nil
    }

    let year: Int
    let days: [Entry]

    func validatedDays(for expectedYear: Int, preferEnglish: Bool = false) -> [CalendarHoliday]? {
        guard year == expectedYear, (2000...2099).contains(year), days.count <= 366 else { return nil }
        var result: [CalendarHoliday] = []
        for item in days {
            guard let day = CountdownDay(isoDate: item.date), (year - 1...year + 1).contains(day.year),
                  !item.name.isEmpty, item.name.count <= 240, (item.englishName?.count ?? 0) <= 240 else { return nil }
            result.append(CalendarHoliday(name: preferEnglish ? (item.englishName ?? item.name) : item.name, day: day, isOffDay: item.isOffDay))
        }
        return result
    }
}

struct HolidayCountdown {
    let holiday: CalendarHoliday
    let days: Int

    static func upcoming(in holidays: [CalendarHoliday], now: Date, calendar: Calendar) -> [Self] {
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

struct InternationalHoliday: Decodable {
    let date: String
    let localName: String
    let name: String
    let countryCode: String
    let global: Bool
    let types: [String]

    static func nationalHolidays(from data: Data, year: Int, country: String) -> HolidayYear? {
        guard let holidays = try? JSONDecoder().decode([Self].self, from: data), holidays.count <= 500 else { return nil }
        let nationwide = holidays.filter { $0.countryCode == country && $0.global && $0.types.contains("Public") }
        var days: [HolidayYear.Entry] = []
        for (date, entries) in Dictionary(grouping: nationwide, by: \.date) {
            guard let day = CountdownDay(isoDate: date), day.year == year else { return nil }
            let local = Set(entries.map(\.localName).filter { !$0.isEmpty }).sorted().joined(separator: " / ")
            let english = Set(entries.map(\.name).filter { !$0.isEmpty }).sorted().joined(separator: " / ")
            days.append(.init(name: local.isEmpty ? english : local, date: date, isOffDay: true,
                              englishName: english.isEmpty ? nil : english))
        }
        let result = HolidayYear(year: year, days: days)
        return result.validatedDays(for: year) == nil ? nil : result
    }
}

final class HolidayCalendar {
    static let shared = HolidayCalendar()
    static let didUpdate = Notification.Name("MakeTools.HolidayCalendarDidUpdate")

    // Source: https://date.nager.at/api/v3/AvailableCountries
    static let regions = Set("""
        AD AG AI AL AM AO AR AT AU AW AX BA BB BD BE BF BG BH BI BJ BL BM BO BQ BR BS BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ
        DE DJ DK DM DO DZ EC EE EG ER ES ET FI FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GT GW GY HK HN HR HT HU ID IE IM IQ IS IT JE JM JP
        KE KH KI KM KN KR KY KZ LC LI LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MN MP MQ MR MS MT MW MX MZ NA NC NE NF NG NI NL NO NR NU NZ PA PE
        PF PG PH PL PM PR PT PW PY RO RS RU RW SB SC SD SE SG SH SI SJ SK SL SM SO SR SS ST SV SX SY SZ TC TD TG TK TN TO TR TT TV TZ UA UG US UY VA
        VC VE VG VI VN VU WF WS YE ZA ZM ZW
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    struct CachedYear: Codable {
        let updatedAt: Date
        let holidays: HolidayYear
    }

    private struct RequestKey: Hashable {
        let region: String
        let year: Int
    }

    private static let cacheKey = "MakeTools.DynamicIsland.regionalHolidays"
    private static let legacyCacheKey = "MakeTools.DynamicIsland.chinaHolidays"
    private static let selectionKey = "MakeTools.DynamicIsland.holidayRegion"
    private let defaults: UserDefaults
    private let systemRegion: () -> String?
    private var cache: [String: [Int: CachedYear]]
    private var nextRequest: [RequestKey: Date] = [:]
    private var inFlight = Set<RequestKey>()
    private var preferEnglishNames: Bool
    private(set) var region: String?
    private(set) var revision = 0
    private(set) var daysByDate: [CountdownDay: CalendarHoliday] = [:]

    var selectedRegion: String? { Self.configuredRegion(in: defaults) }
    var hasSource: Bool { region.map(Self.regions.contains) ?? false }

    init(defaults: UserDefaults = .standard, systemRegion: @escaping () -> String? = {
        Locale.autoupdatingCurrent.region?.identifier
    }) {
        self.defaults = defaults
        self.systemRegion = systemRegion
        cache = defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode([String: [Int: CachedYear]].self, from: $0) } ?? [:]
        if cache["CN"] == nil, let data = defaults.data(forKey: Self.legacyCacheKey),
           let legacy = try? JSONDecoder().decode([Int: CachedYear].self, from: data) {
            cache["CN"] = legacy
        }
        region = (Self.configuredRegion(in: defaults) ?? systemRegion())?.uppercased()
        preferEnglishNames = L10n.locale.language.languageCode?.identifier == "en"
        updateDays()
    }

    private static func configuredRegion(in defaults: UserDefaults) -> String? {
        guard let code = defaults.string(forKey: selectionKey)?.uppercased(), regions.contains(code) else { return nil }
        return code
    }

    func setRegion(_ region: String?) {
        guard region.map(Self.regions.contains) ?? true else { return }
        defaults.set(region, forKey: Self.selectionKey)
        updateSelection()
    }

    func refresh(around year: Int, now: Date = Date()) {
        updateSelection()
        guard hasSource, let region else { return }
        for year in [year, year + 1] where (2000...2099).contains(year) {
            let key = RequestKey(region: region, year: year)
            if let notBefore = nextRequest[key], now < notBefore { continue }
            if let entry = cache[region]?[year], now.timeIntervalSince(entry.updatedAt) < 86_400 { continue }
            guard inFlight.insert(key).inserted else { continue }
            fetch(key)
        }
    }

    func isSyncing(around year: Int) -> Bool {
        guard let region else { return false }
        return [year, year + 1].contains { inFlight.contains(RequestKey(region: region, year: $0)) }
    }

    func syncFailed(around year: Int) -> Bool {
        guard let region else { return false }
        return [year, year + 1].allSatisfy { nextRequest[RequestKey(region: region, year: $0)] != nil }
    }

    private func updateSelection() {
        let effectiveRegion = (selectedRegion ?? systemRegion())?.uppercased()
        let useEnglish = L10n.locale.language.languageCode?.identifier == "en"
        guard region != effectiveRegion || preferEnglishNames != useEnglish else { return }
        region = effectiveRegion
        preferEnglishNames = useEnglish
        publish()
    }

    private func fetch(_ key: RequestKey, mirror: Bool = false) {
        let url: URL
        if key.region == "CN" {
            let base = mirror ? "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/"
                : "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/"
            url = URL(string: base + "\(key.year).json")!
        } else {
            url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(key.year)/\(key.region)")!
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            var result: HolidayYear?
            if let data, data.count <= 128_000, (response as? HTTPURLResponse)?.statusCode == 200 {
                if key.region == "CN" {
                    if let decoded = try? JSONDecoder().decode(HolidayYear.self, from: data),
                       !decoded.days.isEmpty, decoded.validatedDays(for: key.year) != nil {
                        result = decoded
                    }
                } else {
                    result = InternationalHoliday.nationalHolidays(from: data, year: key.year, country: key.region)
                }
            }
            let fetched = result
            DispatchQueue.main.async { [weak self] in self?.finish(key, result: fetched, mirror: mirror) }
        }.resume()
    }

    private func finish(_ key: RequestKey, result: HolidayYear?, mirror: Bool) {
        if result == nil, key.region == "CN", !mirror {
            fetch(key, mirror: true)
            return
        }
        inFlight.remove(key)
        if let result {
            nextRequest.removeValue(forKey: key)
            cache[key.region, default: [:]][key.year] = CachedYear(updatedAt: Date(), holidays: result)
            if let data = try? JSONEncoder().encode(cache) {
                defaults.set(data, forKey: Self.cacheKey)
            }
        } else {
            nextRequest[key] = Date().addingTimeInterval(900)
        }
        if region == key.region { publish() }
    }

    private func publish() {
        updateDays()
        revision += 1
        // A calendar render can notice a region change while it is already refreshing.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: Self.didUpdate, object: self)
        }
    }

    private func updateDays() {
        daysByDate.removeAll(keepingCapacity: true)
        guard let region, let years = cache[region] else { return }
        for year in years.keys.sorted() {
            for day in years[year]?.holidays.validatedDays(for: year, preferEnglish: preferEnglishNames) ?? [] {
                daysByDate[day.day] = day
            }
        }
    }
}
