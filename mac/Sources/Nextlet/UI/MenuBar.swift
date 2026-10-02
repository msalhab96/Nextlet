import AppKit
import NextletCore
import SwiftUI

/// The menu bar item: the next task, or the running focus clock.
struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    @Environment(\.openWindow) private var openWindow
    private static let mark = menuBarMark()

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarLabel.mark)
            if !title.isEmpty { Text(title) }
        }
        .onAppear {
            let env = AppEnvironment.shared
            if env.openMainWindowAction == nil { env.openMainWindowAction = { openWindow(id: "main") } }
        }
    }

    private var title: String {
        if let session = focus.session, !session.finished {
            let name = session.kind == .rest ? "Break" : (session.taskID.flatMap { store.tasks[$0]?.title } ?? "Focus")
            return "\(focus.isTimeUp ? "Time’s up" : Format.clock(focus.remaining)) · \(short(name))"
        }
        if store.phase == .ready, let next = store.nextUp { return short(next.title) }
        return ""
    }

    private func short(_ text: String) -> String {
        text.count > 26 ? String(text.prefix(25)) + "…" : text
    }
}

struct MenuBarView: View {
    @Environment(Store.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today").font(Typo.display(17, .bold)).foregroundStyle(Palette.ink)
                if store.phase == .ready {
                    Text("\(store.todayOpen.count) left").font(Typo.mono(12)).foregroundStyle(Palette.graphite)
                }
                Spacer()
                IconButton(systemImage: "macwindow", help: "Open Nextlet") { AppEnvironment.shared.showMainWindow() }
                IconButton(systemImage: "gearshape", help: "Settings") {
                    NSApp.activate()
                    openSettings()
                }
            }
            .padding(.horizontal, 4)

            switch store.phase {
            case .ready:
                MenuBarContent()
            case .locked:
                prompt(title: "Nextlet is locked", message: "Open Nextlet to sign in.", button: "Open Nextlet") {
                    AppEnvironment.shared.showMainWindow()
                }
            case .failed(let message):
                prompt(title: "Can’t reach Nextlet", message: message, button: "Try Again") {
                    Task { await store.load() }
                }
            case .idle, .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(24)
            }

            Rectangle().fill(Palette.hairline).frame(height: 1)
            HStack(spacing: 6) {
                Button {
                    AppEnvironment.shared.showMainWindow()
                } label: {
                    HStack(spacing: 8) {
                        Text("Open Nextlet").font(Typo.sans(12.5, .medium)).foregroundStyle(Palette.ink)
                        Text("⌘O").font(Typo.sans(11.5, .medium)).foregroundStyle(Palette.graphite)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o")
                Spacer()
                Button {
                    AppEnvironment.shared.panels.showCapture()
                } label: {
                    HStack(spacing: 6) {
                        Text(settings.hotKey == .off ? "Quick capture" : "Capture anywhere")
                        if settings.hotKey != .off { Text(settings.hotKey.label).font(Typo.mono(11)) }
                    }
                    .font(Typo.sans(12))
                    .foregroundStyle(Palette.graphite)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open quick capture")
                IconButton(systemImage: "power", help: "Quit Nextlet", size: 24, symbolSize: 11) { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 384)
        .background(Palette.surface)
    }

    private func prompt(title: String, message: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typo.display(17, .semibold)).foregroundStyle(Palette.ink)
            Text(message).font(Typo.sans(12.5)).foregroundStyle(Palette.graphite).fixedSize(horizontal: false, vertical: true)
            Button(button, action: action).buttonStyle(.nextlet(.primary, .small))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
    }
}

private struct MenuBarContent: View {
    @Environment(Store.self) private var store
    @ViewState private var draft = ""

    var body: some View {
        let open = store.todayOpen
        let done = TaskRules.doneOn(store.taskList, day: store.today)
        let later = Array(open.dropFirst()) + done

        if let next = open.first {
            MenuNextCard(task: next)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("All clear for today.").font(Typo.display(17, .semibold)).foregroundStyle(Palette.ink)
                Text(done.isEmpty ? "Nothing planned. Add something below." : "Enjoy the rest of your day.")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(Palette.graphite)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.paper))
        }

        if !later.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Also today")
                    .font(Typo.sans(11.5, .semibold))
                    .foregroundStyle(Palette.graphite)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(later) { task in MenuTaskRow(task: task) }
                    }
                }
                .frame(maxHeight: 260)
                .fixedSize(horizontal: false, vertical: later.count <= 7)
            }
        }

        if let toast = store.latestUndoable {
            HStack(spacing: 8) {
                Image(systemName: toast.icon == .check ? "checkmark" : "arrow.right.to.line")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.indigo)
                Text(toast.message).font(Typo.sans(12.5)).foregroundStyle(Palette.ink2).lineLimit(1)
                Spacer()
                Button("Undo") {
                    toast.action?()
                    store.dismissToast(toast.id)
                }
                .buttonStyle(.nextlet(.link, .small))
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Palette.paper))
        }

        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.indigo)
            TextField("Add to Today…", text: $draft)
                .textFieldStyle(.plain)
                .font(Typo.sans(13.5))
                .onSubmit(add)
            Text("↵").font(Typo.mono(11)).foregroundStyle(Palette.graphite)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.paper2))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func add() {
        let parsed = QuickAdd.parse(draft, today: store.today, projects: store.projects)
        guard !parsed.title.isEmpty else { return }
        draft = ""
        Task { await store.createFromQuickAdd(parsed, defaultDay: store.today) }
    }
}

private struct MenuNextCard: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    let task: TaskItem

    var body: some View {
        let session = focus.session
        let focusing = session?.taskID == task.id && session?.finished == false
        let project = store.project(task.projectId)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(Palette.marker).frame(width: 7, height: 7)
                    Text(focusing ? (focus.isRunning ? "FOCUSING" : (focus.isTimeUp ? "TIME’S UP" : "PAUSED")) : "NEXT UP")
                }
                Spacer()
                Text((project?.name ?? "No project").uppercased())
            }
            .font(Typo.mono(11, .medium))
            .tracking(1)
            .foregroundStyle(Palette.onDark2)

            Text(task.title)
                .font(Typo.display(19, .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .onTapGesture {
                    store.open(task)
                    AppEnvironment.shared.showMainWindow()
                }

            if focusing, let session {
                VStack(alignment: .leading, spacing: 6) {
                    MiniProgress(value: focus.progress, width: 332, track: .white.opacity(0.14), fill: Palette.marker)
                    Text("\(Format.clock(focus.remaining)) left of \(Format.estimate(max(1, session.totalSeconds / 60)))")
                        .font(Typo.mono(12))
                        .foregroundStyle(Palette.onDark2)
                }
            } else {
                Text("Today\(task.estimateMinutes.map { " · \(Format.estimate($0))" } ?? "")")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(Palette.onDark2)
            }

            HStack(spacing: 8) {
                Button {
                    if focusing {
                        if focus.isTimeUp { focus.addMinutes(5) } else { focus.togglePause() }
                    } else {
                        AppEnvironment.shared.startFocus(on: task.id)
                    }
                } label: {
                    Label(
                        focusing ? (focus.isTimeUp ? "+5 min" : (focus.isRunning ? "Pause" : "Resume")) : "Start focus",
                        systemImage: focusing && focus.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nextlet(.marker))
                Button {
                    Task { await store.toggleComplete(task.id) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(.nextlet(.onDark))
                Button {
                    Task { await store.pushToNextDay([task.id]) }
                } label: {
                    Label("Tomorrow", systemImage: "arrow.right.to.line")
                }
                .buttonStyle(.nextlet(.onDark))
                .help("Move to tomorrow")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.nightEdge, lineWidth: 1))
    }
}

private struct MenuTaskRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 2) {
            CheckButton(task: task)
            ProjectDot(color: Color(projectHex: store.project(task.projectId)?.color))
                .padding(.trailing, 6)
            Text(task.title)
                .font(Typo.sans(13.5))
                .foregroundStyle(task.isOpen ? Palette.ink : Palette.muted)
                .strikethrough(!task.isOpen)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.open(task)
                    AppEnvironment.shared.showMainWindow()
                }
            if task.isOpen {
                IconButton(systemImage: "arrow.right.to.line", help: "Move to tomorrow", size: 28, symbolSize: 11.5) {
                    Task { await store.pushToNextDay([task.id]) }
                }
                .opacity(hovering ? 1 : 0.55)
            }
        }
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Palette.paper : Color.clear))
        .onHover { hovering = $0 }
    }
}
