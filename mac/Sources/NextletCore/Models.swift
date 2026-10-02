import Foundation

public struct Subtask: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var done: Bool
    public var sortOrder: Double

    public init(id: String, title: String, done: Bool, sortOrder: Double) {
        self.id = id
        self.title = title
        self.done = done
        self.sortOrder = sortOrder
    }
}

public enum RepeatRule: Hashable, Sendable, Codable {
    case daily
    case weekdays
    /// ISO weekdays, Monday = 1.
    case weekly(days: [Int])
    case interval(every: Int)
    case monthly

    private enum Keys: String, CodingKey { case type, days, every }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "daily": self = .daily
        case "weekdays": self = .weekdays
        case "weekly": self = .weekly(days: try container.decode([Int].self, forKey: .days))
        case "interval": self = .interval(every: try container.decode(Int.self, forKey: .every))
        case "monthly": self = .monthly
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown repeat \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .daily: try container.encode("daily", forKey: .type)
        case .weekdays: try container.encode("weekdays", forKey: .type)
        case .weekly(let days):
            try container.encode("weekly", forKey: .type)
            try container.encode(days, forKey: .days)
        case .interval(let every):
            try container.encode("interval", forKey: .type)
            try container.encode(every, forKey: .every)
        case .monthly: try container.encode("monthly", forKey: .type)
        }
    }

    /// The JSON the API expects.
    public var json: [String: Any] {
        switch self {
        case .daily: return ["type": "daily"]
        case .weekdays: return ["type": "weekdays"]
        case .weekly(let days): return ["type": "weekly", "days": days]
        case .interval(let every): return ["type": "interval", "every": every]
        case .monthly: return ["type": "monthly"]
        }
    }
}

public struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var notes: String
    public var projectId: String?
    /// The day the task is planned for. Nil means it sits in the Inbox.
    public var day: Day?
    /// Where it was last deliberately scheduled; pushing a task leaves this alone.
    public var plannedDay: Day?
    public var estimateMinutes: Int?
    public var priority: Int
    public var `repeat`: RepeatRule?
    public var sortOrder: Double
    public var completedAt: Date?
    public var completedFromDay: Day?
    public var postponedAt: Date?
    public var nextOccurrenceId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var subtasks: [Subtask]

    public init(
        id: String, title: String, notes: String = "", projectId: String? = nil, day: Day? = nil,
        plannedDay: Day? = nil, estimateMinutes: Int? = nil, priority: Int = 0, repeat: RepeatRule? = nil,
        sortOrder: Double = 0, completedAt: Date? = nil, completedFromDay: Day? = nil, postponedAt: Date? = nil,
        nextOccurrenceId: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), subtasks: [Subtask] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.projectId = projectId
        self.day = day
        self.plannedDay = plannedDay
        self.estimateMinutes = estimateMinutes
        self.priority = priority
        self.repeat = `repeat`
        self.sortOrder = sortOrder
        self.completedAt = completedAt
        self.completedFromDay = completedFromDay
        self.postponedAt = postponedAt
        self.nextOccurrenceId = nextOccurrenceId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.subtasks = subtasks
    }

    public var isOpen: Bool { completedAt == nil }
}

public struct Project: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var color: String
    public var sortOrder: Double
    public var createdAt: Date

    public init(id: String, name: String, color: String, sortOrder: Double = 0, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

/// One field of a task update. Applying it locally and sending it to the API use the same value.
public enum TaskField: Sendable {
    case title(String)
    case notes(String)
    case projectId(String?)
    /// Choosing a day is a deliberate plan, so it also resets the planned day.
    case day(Day?)
    case plannedDay(Day?)
    case estimateMinutes(Int?)
    case priority(Int)
    case repeatRule(RepeatRule?)
    case sortOrder(Double)

    public var key: String {
        switch self {
        case .title: return "title"
        case .notes: return "notes"
        case .projectId: return "projectId"
        case .day: return "day"
        case .plannedDay: return "plannedDay"
        case .estimateMinutes: return "estimateMinutes"
        case .priority: return "priority"
        case .repeatRule: return "repeat"
        case .sortOrder: return "sortOrder"
        }
    }

    public var jsonValue: Any {
        switch self {
        case .title(let value), .notes(let value): return value
        case .projectId(let value): return value ?? NSNull()
        case .day(let value), .plannedDay(let value): return value?.string ?? NSNull()
        case .estimateMinutes(let value): return value ?? NSNull()
        case .priority(let value): return value
        case .repeatRule(let value): return value?.json ?? NSNull()
        case .sortOrder(let value): return value
        }
    }

    public static func json(_ fields: [TaskField]) -> [String: Any] {
        var body: [String: Any] = [:]
        for field in fields { body[field.key] = field.jsonValue }
        return body
    }

    /// Mirrors what the API does with the same update.
    public static func apply(_ fields: [TaskField], to task: inout TaskItem) {
        let setsPlannedDay = fields.contains { if case .plannedDay = $0 { return true } else { return false } }
        for field in fields {
            switch field {
            case .title(let value): task.title = value
            case .notes(let value): task.notes = value
            case .projectId(let value): task.projectId = value
            case .day(let value):
                task.day = value
                if !setsPlannedDay { task.plannedDay = value }
                task.postponedAt = nil
            case .plannedDay(let value): task.plannedDay = value
            case .estimateMinutes(let value): task.estimateMinutes = value
            case .priority(let value): task.priority = value
            case .repeatRule(let value): task.repeat = value
            case .sortOrder(let value): task.sortOrder = value
            }
        }
    }
}

/// What the API needs to create a task.
public struct TaskDraft: Sendable {
    public var title: String
    public var notes: String = ""
    public var projectId: String?
    public var day: Day?
    public var plannedDay: Day?
    public var estimateMinutes: Int?
    public var priority: Int = 0
    public var `repeat`: RepeatRule?
    public var sortOrder: Double?
    public var subtasks: [(title: String, done: Bool)] = []

    public init(title: String, projectId: String? = nil, day: Day? = nil, priority: Int = 0) {
        self.title = title
        self.projectId = projectId
        self.day = day
        self.priority = priority
    }

    public var json: [String: Any] {
        var body: [String: Any] = ["title": title, "notes": notes, "priority": priority]
        body["projectId"] = projectId ?? NSNull()
        body["day"] = day?.string ?? NSNull()
        if let plannedDay { body["plannedDay"] = plannedDay.string }
        body["estimateMinutes"] = estimateMinutes ?? NSNull()
        body["repeat"] = self.repeat?.json ?? NSNull()
        if let sortOrder { body["sortOrder"] = sortOrder }
        if !subtasks.isEmpty { body["subtasks"] = subtasks.map { ["title": $0.title, "done": $0.done] } }
        return body
    }
}

public enum JSONCoding {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = try? fractional.parse(raw) { return date }
            if let date = try? whole.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 date, got \(raw)")
        }
        return decoder
    }
}
