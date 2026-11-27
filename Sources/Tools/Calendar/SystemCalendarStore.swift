import EventKit
import Foundation

struct SystemCalendarEvent {
    let title: String
    let calendarName: String
    let start: Date
    let end: Date
    let isAllDay: Bool

    func occurs(in day: DateInterval) -> Bool {
        // EventKit ends all-day events at the start of the following day.
        start < day.end && (end > day.start || start >= day.start)
    }
}

struct SystemCalendarReminder {
    let title: String
    let listName: String
    let due: Date?
    let hasDueTime: Bool

    init(title: String, listName: String, dueComponents: DateComponents?, calendar: Calendar) {
        self.title = title
        self.listName = listName
        guard var components = dueComponents, components.year != nil,
              components.month != nil, components.day != nil else {
            due = nil
            hasDueTime = false
            return
        }

        hasDueTime = components.hour != nil || components.minute != nil || components.second != nil
        var dateCalendar = calendar
        if hasDueTime, let timeZone = components.timeZone {
            dateCalendar.timeZone = timeZone
        }
        // Date-only and floating reminders belong to their local calendar day.
        components.calendar = dateCalendar
        components.timeZone = dateCalendar.timeZone
        if !hasDueTime { components.hour = 12 }
        due = dateCalendar.date(from: components)
    }
}

final class SystemCalendarStore {
    enum Source: CaseIterable {
        case events
        case reminders

        var entityType: EKEntityType {
            switch self {
            case .events: return .event
            case .reminders: return .reminder
            }
        }

        var settingsAnchor: String {
            switch self {
            case .events: return "Privacy_Calendars"
            case .reminders: return "Privacy_Reminders"
            }
        }

        var title: String {
            switch self {
            case .events: return "日历"
            case .reminders: return "提醒事项"
            }
        }

        var access: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: entityType) }
    }

    private let store = EKEventStore()
    private var storeObserver: NSObjectProtocol?
    private var eventRange: DateInterval?
    private var reminderRequest: Any?
    private var reminderGeneration = UUID()
    private(set) var eventsByDay: [CountdownDay: [SystemCalendarEvent]] = [:]
    private(set) var remindersByDay: [CountdownDay: [SystemCalendarReminder]] = [:]
    private(set) var undatedReminders: [SystemCalendarReminder] = []
    private(set) var reminderLoadFailed = false
    private var didLoadReminders = false

    var isLoadingReminders: Bool { reminderRequest != nil }
    var onStoreChanged: (() -> Void)?
    var onRemindersLoaded: (() -> Void)?

    init() {
        storeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) {
            [weak self] _ in
            self?.onStoreChanged?()
        }
    }

    deinit {
        if let storeObserver { NotificationCenter.default.removeObserver(storeObserver) }
        if let reminderRequest { store.cancelFetchRequest(reminderRequest) }
    }

    func requestAccess(to source: Source, completion: @escaping (Error?) -> Void) {
        let reply: EKEventStoreRequestAccessCompletionHandler = { _, error in
            DispatchQueue.main.async { completion(error) }
        }
        switch source {
        case .events: store.requestFullAccessToEvents(completion: reply)
        case .reminders: store.requestFullAccessToReminders(completion: reply)
        }
    }

    func refresh(visibleDays: [Date], calendar: Calendar, force: Bool = false) {
        refreshEvents(visibleDays: visibleDays, calendar: calendar, force: force)
        refreshReminders(calendar: calendar, force: force)
    }

    private func refreshEvents(visibleDays: [Date], calendar: Calendar, force: Bool) {
        guard Source.events.access == .fullAccess,
              let first = visibleDays.first, let last = visibleDays.last,
              let end = calendar.dateInterval(of: .day, for: last)?.end else {
            eventsByDay = [:]
            eventRange = nil
            return
        }

        let range = DateInterval(start: calendar.startOfDay(for: first), end: end)
        guard force || range != eventRange else { return }
        eventRange = range
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        let events = store.events(matching: predicate).compactMap { event -> SystemCalendarEvent? in
            guard event.status != .canceled, let start = event.startDate, let end = event.endDate else { return nil }
            return SystemCalendarEvent(title: event.title ?? "未命名日程", calendarName: event.calendar?.title ?? "日历",
                                       start: start, end: end, isAllDay: event.isAllDay)
        }.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        eventsByDay = [:]
        for date in visibleDays {
            guard let day = calendar.dateInterval(of: .day, for: date) else { continue }
            let entries = events.filter { $0.occurs(in: day) }
            if !entries.isEmpty { eventsByDay[CountdownDay(date: date, calendar: calendar)] = entries }
        }
    }

    private func refreshReminders(calendar: Calendar, force: Bool) {
        guard Source.reminders.access == .fullAccess else {
            cancelReminderRequest()
            remindersByDay = [:]
            undatedReminders = []
            reminderLoadFailed = false
            didLoadReminders = false
            return
        }
        guard force || (!isLoadingReminders && !didLoadReminders && !reminderLoadFailed) else { return }

        cancelReminderRequest()
        reminderLoadFailed = false
        let generation = reminderGeneration
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        reminderRequest = store.fetchReminders(matching: predicate) { [weak self] fetched in
            let reminders = fetched?.map {
                SystemCalendarReminder(title: $0.title ?? "未命名待办", listName: $0.calendar?.title ?? "提醒事项",
                                       dueComponents: $0.dueDateComponents, calendar: calendar)
            }
            DispatchQueue.main.async {
                guard let self, self.reminderGeneration == generation else { return }
                self.reminderRequest = nil
                if Source.reminders.access == .fullAccess {
                    self.applyReminders(reminders, calendar: calendar)
                } else {
                    self.refreshReminders(calendar: calendar, force: false)
                }
                self.onRemindersLoaded?()
            }
        }
    }

    private func applyReminders(_ reminders: [SystemCalendarReminder]?, calendar: Calendar) {
        didLoadReminders = reminders != nil
        reminderLoadFailed = reminders == nil
        remindersByDay = [:]
        undatedReminders = []
        let sorted = (reminders ?? []).sorted {
            if $0.hasDueTime != $1.hasDueTime { return !$0.hasDueTime }
            if let lhs = $0.due, let rhs = $1.due, lhs != rhs { return lhs < rhs }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        for reminder in sorted {
            if let date = reminder.due {
                remindersByDay[CountdownDay(date: date, calendar: calendar), default: []].append(reminder)
            } else {
                undatedReminders.append(reminder)
            }
        }
    }

    private func cancelReminderRequest() {
        if let reminderRequest { store.cancelFetchRequest(reminderRequest) }
        reminderRequest = nil
        reminderGeneration = UUID()
    }
}
