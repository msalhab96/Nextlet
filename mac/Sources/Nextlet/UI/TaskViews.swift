import AppKit
import NextletCore
import SwiftUI

/// What the trailing button of a row does.
enum RowAction {
    case push
    case doToday
    case none
}

struct TaskRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    var showProject = true
    var showDay = false
    var action: RowAction = .push
    @ViewState private var hovering = false

    var body: some View {
        let selected = store.selectedTaskID == task.id
        let project = store.project(task.projectId)
        let carried = TaskRules.carriedFrom(task, today: store.today)
        let doneSubtasks = task.subtasks.filter(\.done).count

        HStack(spacing: 2) {
            CheckButton(task: task)
            HStack(spacing: 10) {
                Text(task.title)
                    .font(Typo.sans(13.5, .medium))
                    .foregroundStyle(task.isOpen ? Palette.ink : Palette.muted)
                    .strikethrough(!task.isOpen, color: Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if let carried {
                    CarryTag(text: DayFormat.from(carried, today: store.today))
                }
                if showDay, let day = TaskRules.effectiveDay(task, today: store.today) {
                    Text(DayFormat.withDate(day, today: store.today))
                        .font(Typo.sans(12))
                        .foregroundStyle(Palette.graphite)
                        .lineLimit(1)
                }
                if let estimate = task.estimateMinutes, task.isOpen {
                    Text(Format.estimate(estimate)).font(Typo.sans(12)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                if !task.subtasks.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet").font(.system(size: 9.5, weight: .bold))
                        Text("\(doneSubtasks)/\(task.subtasks.count)")
                    }
                    .font(Typo.sans(12))
                    .foregroundStyle(Palette.muted)
                    .help("Subtasks done")
                }
                if let rule = task.repeat {
                    Image(systemName: "repeat")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .help("Repeats: \(rule.label)")
                }
                if showProject {
                    HStack(spacing: 5) {
                        ProjectDot(color: Color(projectHex: project?.color))
                        Text(project?.name ?? "No project").lineLimit(1)
                    }
                    .font(Typo.sans(12))
                    .foregroundStyle(Palette.graphite)
                    .frame(width: 88, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(task.id) }

            Group {
                if task.priority > 0, task.isOpen {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.priority[task.priority])
                        .help(Format.priorityLabels[task.priority])
                } else {
                    Color.clear
                }
            }
            .frame(width: 22)

            trailingButton(visible: hovering || selected)
                .frame(width: 30)
        }
        .padding(.leading, 0)
        .padding(.trailing, 4)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Palette.indigoSoft : (hovering ? Palette.paper : Color.clear))
        )
        .onHover { hovering = $0 }
        .contextMenu { TaskMenuItems(task: task) }
        .draggable(task.id) {
            Text(task.title)
                .font(Typo.sans(13, .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
        }
    }

    @ViewBuilder
    private func trailingButton(visible: Bool) -> some View {
        if task.isOpen && visible {
            switch action {
            case .push:
                let next = (TaskRules.effectiveDay(task, today: store.today) ?? store.today).adding(days: 1)
                let label = DayFormat.relative(next, today: store.today) == "Tomorrow" ? "Move to tomorrow (⌘→)" : "Move to \(DayFormat.short(next, today: store.today))"
                IconButton(systemImage: "arrow.right.to.line", help: label, size: 26, symbolSize: 11.5, foreground: Palette.indigoInk, hoverBackground: Palette.indigo.opacity(0.18), background: Palette.indigo.opacity(0.12)) {
                    Task { await store.pushToNextDay([task.id]) }
                }
            case .doToday:
                IconButton(systemImage: "sun.max", help: "Do today", size: 26, symbolSize: 12, foreground: Palette.indigoInk, hoverBackground: Palette.indigo.opacity(0.18), background: Palette.indigo.opacity(0.12)) {
                    Task { await store.rescheduleTask(task.id, to: store.today) }
                }
            case .none:
                Color.clear
            }
        } else {
            Color.clear
        }
    }
}

/// The right-click menu for a task, also used by the inspector's ••• menu.
struct TaskMenuItems: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    var body: some View {
        let today = store.today
        let shown = TaskRules.effectiveDay(task, today: today)
        Button(task.isOpen ? "Complete" : "Mark as Not Done") { Task { await store.toggleComplete(task.id) } }
        if task.isOpen {
            if let shown {
                let next = shown.adding(days: 1)
                Button(DayFormat.relative(next, today: today) == "Tomorrow" ? "Move to Tomorrow" : "Move to \(DayFormat.short(next, today: today))") {
                    Task { await store.pushToNextDay([task.id]) }
                }
                if shown != today {
                    Button("Back to Today") { Task { await store.bringBackToToday(task.id) } }
                }
                Button("Remove Day (Inbox)") { Task { await store.rescheduleTask(task.id, to: nil) } }
            } else {
                Button("Do Today") { Task { await store.rescheduleTask(task.id, to: today) } }
                Button("Do Tomorrow") { Task { await store.rescheduleTask(task.id, to: today.adding(days: 1)) } }
            }
            if shown == today, store.nextUp?.id != task.id {
                Button("Make Next Up") { Task { await store.makeNextUp(task.id) } }
            }
            Button("Start Focus") {
                AppEnvironment.shared.startFocus(on: task.id)
            }
        }
        Divider()
        Menu("Priority") {
            ForEach(0..<4, id: \.self) { level in
                Button {
                    Task { await store.updateTask(task.id, [.priority(level)]) }
                } label: {
                    if level == task.priority { Label(Format.priorityLabels[level], systemImage: "checkmark") } else { Text(Format.priorityLabels[level]) }
                }
            }
        }
        Menu("Project") {
            Button {
                Task { await store.updateTask(task.id, [.projectId(nil)]) }
            } label: {
                if task.projectId == nil { Label("No Project", systemImage: "checkmark") } else { Text("No Project") }
            }
            ForEach(store.projects) { project in
                Button {
                    Task { await store.updateTask(task.id, [.projectId(project.id)]) }
                } label: {
                    Label { Text(project.name) } icon: { Image(nsImage: swatchImage(project.color)) }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { Task { await store.deleteTask(task.id) } }
    }
}

/// A titled list of rows. Rows can be dragged to reorder when `reorderable`.
struct TaskSection: View {
    @Environment(Store.self) private var store
    let title: String
    var count: String?
    let tasks: [TaskItem]
    var reorderable = false
    var showProject = true
    var showDay = false
    var action: RowAction = .push
    @ViewState private var targetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionHeader(title: title, count: count)
            ForEach(tasks) { task in
                TaskRow(task: task, showProject: showProject, showDay: showDay, action: action)
                    .overlay(alignment: .top) {
                        if targetID == task.id {
                            Capsule().fill(Palette.indigo).frame(height: 2).padding(.horizontal, 8).offset(y: -1)
                        }
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard reorderable, let id = ids.first, id != task.id, tasks.contains(where: { $0.id == id }) else { return false }
                        let order = tasks.map(\.id)
                        let without = order.filter { $0 != id }
                        let index = without.firstIndex(of: task.id) ?? without.count
                        Task { await store.reorder(TaskRules.moveInOrder(order, id: id, to: index)) }
                        return true
                    } isTargeted: { targeted in
                        guard reorderable else { return }
                        if targeted { targetID = task.id } else if targetID == task.id { targetID = nil }
                    }
            }
        }
    }
}

/// The one thing to do now.
struct NextUpCard: View {
    @Environment(Store.self) private var store
    @Environment(AppSettings.self) private var settings
    let task: TaskItem

    var body: some View {
        let project = store.project(task.projectId)
        let carried = TaskRules.carriedFrom(task, today: store.today)
        let doneSubtasks = task.subtasks.filter(\.done).count

        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(Palette.marker).frame(width: 7, height: 7)
                    Text("NEXT UP").font(Typo.mono(11, .medium)).tracking(1.1).foregroundStyle(Palette.onDark2)
                }
                Text(task.title)
                    .font(Typo.display(21, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .onTapGesture { store.select(task.id) }
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        ProjectDot(color: Color(projectHex: project?.color).lightened(0.42), size: 8)
                        Text(project?.name ?? "No project")
                    }
                    if let estimate = task.estimateMinutes { Text(Format.estimate(estimate)) }
                    if !task.subtasks.isEmpty { Text("\(doneSubtasks)/\(task.subtasks.count) steps") }
                    if let carried { Text(DayFormat.from(carried, today: store.today)) }
                }
                .font(Typo.sans(12.5))
                .foregroundStyle(Palette.onDark2)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                AppEnvironment.shared.startFocus(on: task.id)
                if !settings.showFloatingTimer { store.route = .focus }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Start focus")
                    Text("⌘F").font(Typo.mono(11, .medium)).opacity(0.7)
                }
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
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.nightEdge, lineWidth: 1))
    }
}

/// The "New task" field under a list. Understands quick add.
struct AddTaskField: View {
    @Environment(Store.self) private var store
    var defaultDay: Day?
    var defaultProjectID: String?
    var placeholder = "New task"
    var compact = false
    var onClose: (() -> Void)?
    @ViewState private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickAdd.parse(text, today: store.today, projects: store.projects)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.indigo)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(Typo.sans(compact ? 12.5 : 13.5))
                    .focused($focused)
                    .onSubmit { submit(parsed) }
                    .onExitCommand {
                        if text.isEmpty { onClose?() }
                        text = ""
                        focused = false
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: compact ? 30 : 34)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(focused ? Palette.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(focused ? Palette.indigo : Palette.dashed, style: StrokeStyle(lineWidth: focused ? 1.5 : 1, dash: focused ? [] : [4, 3]))
            )
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                ParsedChips(parsed: parsed).padding(.leading, 4)
            }
        }
        .onAppear {
            if compact { focused = true }
        }
    }

    private func submit(_ parsed: QuickAdd.Result) {
        guard !parsed.title.isEmpty else { return }
        let day: Day? = parsed.day.map { $0.day } ?? defaultDay
        var landsElsewhere = day != defaultDay
        if case .new? = parsed.project { landsElsewhere = true }
        let destination = store.destination(of: parsed, defaultDay: defaultDay, defaultProjectID: defaultProjectID)
        text = ""
        Task {
            if await store.createFromQuickAdd(parsed, defaultDay: defaultDay, defaultProjectID: defaultProjectID) != nil, landsElsewhere {
                store.toast("“\(parsed.title)” added to \(destination)", icon: .check)
            }
        }
    }
}
