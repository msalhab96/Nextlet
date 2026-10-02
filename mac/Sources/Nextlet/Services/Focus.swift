import Foundation
import Observation

/// A focus countdown for one task (or a short break). It is saved to UserDefaults,
/// so a running timer survives quitting and relaunching Nextlet.
@MainActor @Observable
final class FocusController {
    struct Session: Codable, Equatable {
        enum Kind: String, Codable {
            case task
            case rest
        }

        var kind: Kind
        var taskID: String?
        var totalSeconds: Int
        /// Seconds left while paused. While running, `endsAt` is the source of truth.
        var remainingSeconds: Int
        var endsAt: Date?
        /// The task was marked done from the focus timer.
        var finished: Bool
    }

    private static let storageKey = "focusSession.v1"

    private(set) var session: Session? {
        didSet {
            save()
            updateTimer()
        }
    }

    /// Ticks every second while a session runs, so views showing the clock refresh.
    private(set) var now = Date()

    /// Called when a running countdown reaches zero.
    @ObservationIgnored var onTimeUp: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: FocusController.storageKey) {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
        updateTimer()
    }

    var isRunning: Bool { session?.endsAt != nil }

    var remaining: Int {
        guard let session else { return 0 }
        return FocusController.remaining(of: session, at: now)
    }

    static func remaining(of session: Session, at date: Date) -> Int {
        guard let endsAt = session.endsAt else { return session.remainingSeconds }
        return max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }

    /// 0 at the start, 1 when time is up.
    var progress: Double {
        guard let session, session.totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remaining) / Double(session.totalSeconds)))
    }

    var isTimeUp: Bool {
        guard let session else { return false }
        return !session.finished && session.endsAt == nil && session.remainingSeconds <= 0
    }

    func start(taskID: String, minutes: Int) {
        now = Date()
        let seconds = max(60, minutes * 60)
        session = Session(
            kind: .task, taskID: taskID, totalSeconds: seconds, remainingSeconds: seconds,
            endsAt: now.addingTimeInterval(TimeInterval(seconds)), finished: false
        )
    }

    func startBreak(minutes: Int = 5) {
        now = Date()
        let seconds = minutes * 60
        session = Session(
            kind: .rest, taskID: nil, totalSeconds: seconds, remainingSeconds: seconds,
            endsAt: now.addingTimeInterval(TimeInterval(seconds)), finished: false
        )
    }

    func pause() {
        guard var current = session, current.endsAt != nil else { return }
        current.remainingSeconds = remaining
        current.endsAt = nil
        session = current
    }

    func resume() {
        guard var current = session, current.endsAt == nil, current.remainingSeconds > 0 else { return }
        now = Date()
        current.endsAt = now.addingTimeInterval(TimeInterval(current.remainingSeconds))
        session = current
    }

    func togglePause() {
        isRunning ? pause() : resume()
    }

    func addMinutes(_ minutes: Int) {
        guard var current = session else { return }
        now = Date()
        let left = remaining + minutes * 60
        current.remainingSeconds = left
        current.totalSeconds = max(current.totalSeconds, left)
        current.endsAt = now.addingTimeInterval(TimeInterval(left))
        current.finished = false
        session = current
    }

    func finish() {
        guard var current = session else { return }
        current.remainingSeconds = remaining
        current.endsAt = nil
        current.finished = true
        session = current
    }

    func end() {
        session = nil
    }

    private func save() {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: FocusController.storageKey)
        } else {
            defaults.removeObject(forKey: FocusController.storageKey)
        }
    }

    private func updateTimer() {
        now = Date()
        if isRunning {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            // .common keeps the clock ticking while a menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        now = Date()
        guard var current = session, current.endsAt != nil, remaining <= 0 else { return }
        current.remainingSeconds = 0
        current.endsAt = nil
        session = current
        onTimeUp?()
    }
}
