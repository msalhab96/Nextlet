import Foundation
import NextletCore

struct APIError: LocalizedError, Sendable {
    enum Kind: Sendable {
        case network
        case unauthorized
        case server
        case decoding
    }

    let kind: Kind
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? { message }
    var isUnauthorized: Bool { kind == .unauthorized }
}

struct AuthStatus: Decodable, Sendable {
    let required: Bool
    let authenticated: Bool
}

struct LoginResponse: Decodable, Sendable {
    let ok: Bool
    let token: String?
}

struct CompleteResponse: Decodable, Sendable {
    let task: TaskItem
    let nextOccurrence: TaskItem?
}

struct UncompleteResponse: Decodable, Sendable {
    let task: TaskItem
    let removedTaskId: String?
}

private struct ReorderResponse: Decodable {
    let sortOrders: [String: Double]
}

/// Talks to the same REST API as the web app.
struct APIClient: Sendable {
    let baseURL: URL
    let token: String?

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    private func url(_ path: String) -> URL? {
        URL(string: baseURL.absoluteString + "/api" + path)
    }

    private func data(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data? {
        guard let url = url(path) else {
            throw APIError(kind: .network, status: 0, code: "invalid_address", message: "The server address isn’t valid")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await APIClient.session.data(for: request)
        } catch {
            throw APIError(kind: .network, status: 0, code: "network", message: "Can’t reach Nextlet at \(baseURL.absoluteString)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(kind: .network, status: 0, code: "network", message: "Unexpected response from the server")
        }
        if http.statusCode == 204 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = payload?["error"] as? String ?? "error"
            let message = payload?["message"] as? String ?? "Request failed (\(http.statusCode))"
            throw APIError(kind: http.statusCode == 401 ? .unauthorized : .server, status: http.statusCode, code: code, message: message)
        }
        return data
    }

    private func decode<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let data = try await data(method, path, body: body) else {
            throw APIError(kind: .decoding, status: 204, code: "empty", message: "The server sent no data")
        }
        do {
            return try JSONCoding.decoder().decode(T.self, from: data)
        } catch {
            throw APIError(kind: .decoding, status: 200, code: "decoding", message: "The server sent something Nextlet didn’t understand")
        }
    }

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws {
        _ = try await data(method, path, body: body)
    }

    // MARK: Session

    func health() async throws { try await send("GET", "/health") }
    func authStatus() async throws -> AuthStatus { try await decode("GET", "/auth/status") }
    func login(password: String) async throws -> LoginResponse { try await decode("POST", "/auth/login", body: ["password": password]) }
    func logout() async throws { try await send("POST", "/auth/logout") }

    // MARK: Projects

    func projects() async throws -> [Project] { try await decode("GET", "/projects") }

    func createProject(name: String) async throws -> Project {
        try await decode("POST", "/projects", body: ["name": name])
    }

    func updateProject(id: String, name: String? = nil, color: String? = nil) async throws -> Project {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let color { body["color"] = color }
        return try await decode("PATCH", "/projects/\(id)", body: body)
    }

    func deleteProject(id: String) async throws { try await send("DELETE", "/projects/\(id)") }

    // MARK: Tasks

    func openTasks() async throws -> [TaskItem] { try await decode("GET", "/tasks?status=open") }

    func doneTasks(from: Day, to: Day) async throws -> [TaskItem] {
        try await decode("GET", "/tasks?status=done&from=\(from.string)&to=\(to.string)")
    }

    func search(_ query: String) async throws -> [TaskItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
        return try await decode("GET", "/tasks?q=\(encoded)")
    }

    func createTask(_ draft: TaskDraft) async throws -> TaskItem { try await decode("POST", "/tasks", body: draft.json) }

    func updateTask(id: String, fields: [TaskField]) async throws -> TaskItem {
        try await decode("PATCH", "/tasks/\(id)", body: TaskField.json(fields))
    }

    func deleteTask(id: String) async throws { try await send("DELETE", "/tasks/\(id)") }

    func completeTask(id: String, today: Day) async throws -> CompleteResponse {
        try await decode("POST", "/tasks/\(id)/complete", body: ["today": today.string])
    }

    func uncompleteTask(id: String) async throws -> UncompleteResponse { try await decode("POST", "/tasks/\(id)/uncomplete") }

    func moveTasks(_ moves: [(id: String, day: Day)], postponed: Bool) async throws -> [TaskItem] {
        try await decode("POST", "/tasks/move", body: [
            "moves": moves.map { ["id": $0.id, "day": $0.day.string] },
            "postponed": postponed,
        ])
    }

    func reorder(ids: [String]) async throws -> [String: Double] {
        let response: ReorderResponse = try await decode("POST", "/tasks/reorder", body: ["ids": ids])
        return response.sortOrders
    }

    func addSubtask(taskID: String, title: String) async throws -> Subtask {
        try await decode("POST", "/tasks/\(taskID)/subtasks", body: ["title": title])
    }

    func updateSubtask(id: String, title: String? = nil, done: Bool? = nil) async throws -> Subtask {
        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        if let done { body["done"] = done }
        return try await decode("PATCH", "/subtasks/\(id)", body: body)
    }

    func deleteSubtask(id: String) async throws { try await send("DELETE", "/subtasks/\(id)") }

    // MARK: Tags

    private func tagPath(_ tag: String) -> String {
        "/tags/" + (tag.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? tag)
    }

    /// Renames the tag on every task that has it, finished ones included.
    func renameTag(_ tag: String, to name: String) async throws { try await send("PATCH", tagPath(tag), body: ["name": name]) }
    /// Takes the tag off every task that has it.
    func deleteTag(_ tag: String) async throws { try await send("DELETE", tagPath(tag)) }
}
