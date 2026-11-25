import Foundation

struct CadenceEvent: Codable, Identifiable, Hashable {
    let eventId: String
    let accountId: String?
    let account: String?
    let title: String
    let description: String?
    let start: String
    let end: String?
    let link: String?
    let meetLink: String?
    let rsvp: String?

    enum CodingKeys: String, CodingKey {
        case eventId = "id"
        case accountId, account, title, description, start, end, link, meetLink, rsvp
    }

    var id: String { "\(accountId ?? "default"):\(eventId)" }

    var startDate: Date? { ISO8601DateFormatter.cadence.date(from: start) }
}

struct CadenceTask: Codable, Identifiable, Hashable {
    let taskId: String
    let accountId: String?
    let listId: String
    let list: String?
    let title: String
    let notes: String?
    let due: String?
    var completed: String?
    var status: String?
    let link: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "id"
        case accountId, listId, list, title, notes, due, completed, status, link
    }

    var id: String { "\(accountId ?? "default"):\(taskId)" }

    var isCompleted: Bool { status == "completed" }
    var dueDate: Date? {
        guard let due else { return nil }
        return ISO8601DateFormatter.cadence.date(from: due)
    }
}

extension ISO8601DateFormatter {
    static let cadence: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let cadenceWithoutFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func cadenceDate(from value: String) -> Date? {
        date(from: value) ?? ISO8601DateFormatter.cadenceWithoutFractions.date(from: value)
    }
}

extension CadenceEvent {
    var parsedStartDate: Date? {
        ISO8601DateFormatter.cadence.cadenceDate(from: start)
    }
}

extension CadenceTask {
    var parsedDueDate: Date? {
        guard let due else { return nil }
        let dateOnly = String(due.prefix(10))
        return DateFormatter.googleTaskDay.date(from: dateOnly)
    }
}

extension DateFormatter {
    static let googleTaskDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
