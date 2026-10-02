import AppKit
import NextletCore
import SwiftUI

struct FocusRing: View {
    let progress: Double
    let time: String
    let status: String
    var size: CGFloat = 188
    var lineWidth: CGFloat = 8
    var highlighted = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, 1 - progress))
                .stroke(Palette.marker, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: progress)
            VStack(spacing: 4) {
                Text(time)
                    .font(Typo.mono(size * 0.22, .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(status)
                    .font(Typo.sans(12, highlighted ? .semibold : .regular))
                    .foregroundStyle(highlighted ? Palette.marker : Palette.onDark2)
            }
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(time) remaining, \(status)")
    }
}

struct PillButton: View {
    let title: String
    var icon: String?
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
                Text(title)
            }
            .font(Typo.sans(13, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 40)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.18 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The running timer or the "done" screen, shared by the Focus page and the floating timer.
struct FocusSessionContent: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    let compact: Bool

    var body: some View {
        if let session = focus.session {
            if session.finished {
                FocusDoneContent(compact: compact, wasBreak: session.kind == .rest)
            } else {
                FocusTimerContent(session: session, compact: compact)
            }
        }
    }
}

private struct FocusTimerContent: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    let session: FocusController.Session
    let compact: Bool

    var body: some View {
        let task = session.taskID.flatMap { store.tasks[$0] }
        let status: String = {
            if focus.isTimeUp { return session.kind == .rest ? "Break’s over" : "Time’s up" }
            if focus.isRunning { return "of \(Format.estimate(max(1, session.totalSeconds / 60)))" }
            return "Paused"
        }()

        VStack(spacing: compact ? 14 : 18) {
            Text(session.kind == .rest ? "Short break" : (task?.title ?? "Focus"))
                .font(Typo.display(compact ? 17 : 24, .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if session.kind == .rest {
                Text("Stand up, drink some water, look away from the screen.")
                    .font(Typo.sans(13))
                    .foregroundStyle(Palette.onDark2)
                    .multilineTextAlignment(.center)
            }
            FocusRing(
                progress: focus.progress, time: Format.clock(focus.remaining), status: status,
                size: compact ? 172 : 232, lineWidth: compact ? 8 : 10, highlighted: focus.isTimeUp
            )
            HStack(spacing: 14) {
                PillButton(title: "+5 min") { focus.addMinutes(5) }
                Button {
                    if focus.isTimeUp { focus.addMinutes(5) } else { focus.togglePause() }
                } label: {
                    Image(systemName: focus.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 18 : 22, weight: .bold))
                        .foregroundStyle(Palette.onMarker)
                        .frame(width: compact ? 56 : 64, height: compact ? 56 : 64)
                        .background(Circle().fill(Palette.marker))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(focus.isTimeUp ? "Add 5 minutes and keep going" : (focus.isRunning ? "Pause" : "Resume"))
                if session.kind == .task {
                    PillButton(title: "Done", icon: "checkmark") { AppEnvironment.shared.completeFocusTask() }
                } else {
                    PillButton(title: "Skip") { focus.finish() }
                }
            }
            if let task, !task.subtasks.isEmpty {
                FocusStepRow(task: task)
            }
        }
    }
}

private struct FocusStepRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    var body: some View {
        let step = task.subtasks.first { !$0.done }
        let doneCount = task.subtasks.filter(\.done).count
        HStack(spacing: 8) {
            Button {
                if let step { Task { await store.updateSubtask(task.id, step.id, done: true) } }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(step == nil ? Palette.marker : Color.clear)
                    RoundedRectangle(cornerRadius: 5).strokeBorder(step == nil ? Palette.marker : Color(hex: 0x8A8D96), lineWidth: 1.5)
                    if step == nil {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.ink)
                    }
                }
                .frame(width: 17, height: 17)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(step == nil)
            .help(step.map { "Complete step: \($0.title)" } ?? "All steps done")
            VStack(alignment: .leading, spacing: 2) {
                Text(step == nil ? "ALL STEPS DONE" : "CURRENT STEP")
                    .font(Typo.mono(10.5))
                    .tracking(0.8)
                    .foregroundStyle(Palette.onDark2)
                Text(step?.title ?? "Wrap up and mark it done")
                    .font(Typo.sans(13.5))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
            Spacer()
            Text("\(doneCount)/\(task.subtasks.count)")
                .font(Typo.mono(12))
                .foregroundStyle(Palette.onDark2)
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }
}

private struct FocusDoneContent: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    let compact: Bool
    let wasBreak: Bool

    var body: some View {
        let current = focus.session?.taskID
        let upNext = store.todayOpen.first { $0.id != current }
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: compact ? 24 : 30, weight: .bold))
                .foregroundStyle(Palette.onMarker)
                .frame(width: compact ? 56 : 64, height: compact ? 56 : 64)
                .background(Circle().fill(Palette.marker))
            Text(wasBreak ? "Break’s over." : "Done. Nice work.")
                .font(Typo.display(compact ? 20 : 24, .semibold))
                .foregroundStyle(.white)
            Group {
                if let upNext {
                    Text("Up next: ") + Text(upNext.title).foregroundColor(.white)
                        + Text(upNext.estimateMinutes.map { " · \(Format.estimate($0))" } ?? "")
                } else {
                    Text("That was the last task on today’s list.")
                }
            }
            .font(Typo.sans(13.5))
            .foregroundStyle(Palette.onDark2)
            .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                if upNext != nil {
                    Button {
                        AppEnvironment.shared.startNextFocus()
                    } label: {
                        Label("Start next", systemImage: "play.fill")
                    }
                    .buttonStyle(.nextlet(.marker, compact ? .regular : .large))
                }
                if !wasBreak {
                    Button("5-min break") { focus.startBreak(minutes: 5) }
                        .buttonStyle(.nextlet(.onDark, compact ? .regular : .large))
                }
            }
            Button("Back to Today") {
                focus.end()
                AppEnvironment.shared.go(to: .today)
            }
            .buttonStyle(.plain)
            .font(Typo.sans(13))
            .foregroundStyle(Palette.onDark2)
            .underline()
        }
        .padding(.vertical, compact ? 6 : 12)
    }
}

// MARK: Focus page in the main window

struct FocusPane: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    @Environment(PanelState.self) private var panelState

    var body: some View {
        let session = focus.session
        let hasTask = session.map { $0.kind == .rest || $0.taskID.flatMap { store.tasks[$0] } != nil } ?? false

        Group {
            if let session, hasTask {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 18) {
                            HStack {
                                Text(label(for: session))
                                    .font(Typo.mono(12, .medium))
                                    .tracking(1)
                                    .foregroundStyle(Palette.onDark2)
                                Spacer()
                                Button(panelState.focusTimerVisible ? "Hide floating timer" : "Show floating timer") {
                                    if panelState.focusTimerVisible {
                                        AppEnvironment.shared.panels.hideFocusTimer()
                                    } else {
                                        AppEnvironment.shared.panels.showFocusTimer()
                                    }
                                }
                                .buttonStyle(.nextlet(.onDark, .small))
                                Button("End session") { focus.end() }
                                    .buttonStyle(.nextlet(.onDark, .small))
                            }
                            FocusSessionContent(compact: false)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                        .padding(.bottom, 26)
                        .background(RoundedRectangle(cornerRadius: 24).fill(Palette.night))
                        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.nightEdge, lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
                        if session.kind == .task, !session.finished,
                           let next = store.todayOpen.first(where: { $0.id != session.taskID }) {
                            (Text("Up next: ").foregroundColor(Palette.graphite) + Text(next.title).foregroundColor(Palette.ink))
                                .font(Typo.sans(13.5))
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
            } else {
                FocusPicker()
            }
        }
        .background(Palette.paper)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ToolbarTitle(title: "Focus", subtitle: subtitle(session))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                InspectorToggle()
            }
        }
        .onChange(of: store.todayOpen.map(\.id), initial: true) { _, ids in store.visibleOrder = ids }
    }

    private func label(for session: FocusController.Session) -> String {
        guard session.kind == .task else { return "BREAK" }
        let task = session.taskID.flatMap { store.tasks[$0] }
        return "FOCUS · \((store.project(task?.projectId)?.name ?? "No project").uppercased())"
    }

    private func subtitle(_ session: FocusController.Session?) -> String {
        guard let session, !session.finished else { return "One task at a time" }
        return focus.isRunning ? "\(Format.clock(focus.remaining)) left" : (focus.isTimeUp ? "Time’s up" : "Paused")
    }
}

struct FocusPicker: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    @Environment(AppSettings.self) private var settings
    @ViewState private var length = 0 // 0 means "use the task's estimate"

    var body: some View {
        let tasks = store.todayOpen
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What’s next?")
                    .font(Typo.display(34, .bold))
                    .foregroundStyle(Palette.ink)
                if let first = tasks.first {
                    HStack(spacing: 12) {
                        Text("Session length").font(Typo.sans(13)).foregroundStyle(Palette.graphite)
                        Picker("Session length", selection: $length) {
                            Text("Task estimate").tag(0)
                            ForEach([15, 25, 45, 60], id: \.self) { minutes in Text("\(minutes) min").tag(minutes) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 7) {
                            Circle().fill(Palette.marker).frame(width: 7, height: 7)
                            Text("NEXT UP").font(Typo.mono(11, .medium)).tracking(1.1).foregroundStyle(Palette.onDark2)
                        }
                        Text(first.title).font(Typo.display(26, .semibold)).foregroundStyle(.white)
                        Button {
                            start(first)
                        } label: {
                            Label("Focus for \(Format.estimate(minutes(for: first)))", systemImage: "play.fill")
                        }
                        .buttonStyle(.nextlet(.marker, .large))
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Palette.night))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.nightEdge, lineWidth: 1))
                    if tasks.count > 1 {
                        SectionHeader(title: "Or pick another task from today")
                        ForEach(tasks.dropFirst()) { task in
                            HStack(spacing: 12) {
                                ProjectDot(color: Color(projectHex: store.project(task.projectId)?.color), size: 8)
                                Text(task.title).font(Typo.sans(13.5, .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                                Spacer()
                                Button {
                                    start(task)
                                } label: {
                                    Label(Format.estimate(minutes(for: task)), systemImage: "play.fill")
                                }
                                .buttonStyle(.nextlet(.outline, .small))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
                        }
                    }
                } else {
                    EmptyCard(title: "Nothing on today’s list.", message: "Add a task to Today, or bring one over from your Inbox or Upcoming.")
                    Button("Go to Today") { store.route = .today }.buttonStyle(.nextlet(.outline))
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
        }
    }

    private func minutes(for task: TaskItem) -> Int {
        length == 0 ? (task.estimateMinutes ?? settings.focusMinutes) : length
    }

    private func start(_ task: TaskItem) {
        focus.start(taskID: task.id, minutes: minutes(for: task))
        if settings.showFloatingTimer { AppEnvironment.shared.panels.showFocusTimer() }
    }
}

// MARK: Floating timer

/// The always-on-top focus timer from the design.
struct FocusTimerPanel: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    @Environment(PanelState.self) private var panelState
    let onHide: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                IconButton(systemImage: "xmark", help: "Hide timer (it keeps running)", size: 28, symbolSize: 10, foreground: Palette.onDark2, hoverBackground: .white.opacity(0.16), background: .white.opacity(0.08), action: onHide)
                Spacer()
                Text(label)
                    .font(Typo.mono(11, .medium))
                    .tracking(1)
                    .foregroundStyle(Palette.onDark2)
                    .lineLimit(1)
                Spacer()
                IconButton(
                    systemImage: panelState.focusTimerPinned ? "pin.fill" : "pin",
                    help: panelState.focusTimerPinned ? "Stop keeping on top" : "Keep on top",
                    size: 28, symbolSize: 11,
                    foreground: panelState.focusTimerPinned ? Palette.marker : Palette.onDark2,
                    hoverBackground: .white.opacity(0.16),
                    background: panelState.focusTimerPinned ? Palette.marker.opacity(0.14) : .white.opacity(0.08)
                ) {
                    AppEnvironment.shared.panels.setFocusTimerPinned(!panelState.focusTimerPinned)
                }
            }
            if focus.session != nil {
                FocusSessionContent(compact: true)
            } else {
                Text("No focus session").font(Typo.sans(13)).foregroundStyle(Palette.onDark2).padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(width: 304)
        .background(RoundedRectangle(cornerRadius: 20).fill(Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .onChange(of: focus.session == nil) { _, ended in
            if ended { onHide() }
        }
    }

    private var label: String {
        guard let session = focus.session else { return "FOCUS" }
        if session.kind == .rest { return "BREAK" }
        let task = session.taskID.flatMap { store.tasks[$0] }
        return "FOCUS · \((store.project(task?.projectId)?.name ?? "No project").uppercased())"
    }
}
