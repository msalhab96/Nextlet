import AppKit
import NextletCore
import SwiftUI

struct InspectorPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        Group {
            if let task = store.selectedTask {
                TaskInspector(task: task).id(task.id)
            } else {
                VStack(spacing: 6) {
                    Text("No task selected").font(Typo.sans(13, .medium)).foregroundStyle(Palette.graphite)
                    Text("Select a task to see its details.").font(Typo.sans(12)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.paper2)
    }
}

struct TaskInspector: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    @ViewState private var title: String
    @FocusState private var titleFocused: Bool
    @ViewState private var notes: String
    @ViewState private var notesDirty = false
    @ViewState private var newSubtask = ""
    @ViewState private var pickingDay = false
    @ViewState private var pickedDate = Date()
    @ViewState private var pickingWeekdays = false

    init(task: TaskItem) {
        self.task = task
        _title = ViewState(initialValue: task.title)
        _notes = ViewState(initialValue: task.notes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                titleRow
                dayBlock
                fields
                Rectangle().fill(Palette.hairline).frame(height: 1)
                subtasks
                notesSection
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onChange(of: task.title) { if !titleFocused { title = task.title } }
        .onChange(of: task.notes) { if !notesDirty { notes = task.notes } }
        .task(id: notes) {
            guard notesDirty else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            saveNotes()
        }
        .onDisappear {
            saveNotes()
            commitTitle()
        }
    }

    // MARK: Header and title

    private var header: some View {
        let project = store.project(task.projectId)
        return HStack(spacing: 4) {
            Menu {
                Button("No Project") { Task { await store.updateTask(task.id, [.projectId(nil)]) } }
                ForEach(store.projects) { candidate in
                    Button {
                        Task { await store.updateTask(task.id, [.projectId(candidate.id)]) }
                    } label: {
                        Label { Text(candidate.name) } icon: { Image(nsImage: swatchImage(candidate.color)) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    ProjectDot(color: Color(projectHex: project?.color))
                    Text(project?.name ?? "No project").font(Typo.sans(12, .medium)).foregroundStyle(Palette.ink)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.chip))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Project")
            .accessibilityLabel("Project")
            .accessibilityValue(project?.name ?? "No project")
            Spacer()
            Menu {
                TaskMenuItems(task: task)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 28)
            .help("More actions")
            .accessibilityLabel("More actions")
            IconButton(systemImage: "sidebar.trailing", help: "Hide details") { store.inspectorVisible = false }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 2) {
            CheckButton(task: task, size: 18)
                .padding(.leading, -8)
                .padding(.top, -3)
            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.display(20, .semibold))
                .foregroundStyle(task.isOpen ? Palette.ink : Palette.muted)
                .focused($titleFocused)
                .onSubmit { commitTitle() }
                .onChange(of: titleFocused) { if !titleFocused { commitTitle() } }
                .padding(.top, 2)
        }
    }

    private func commitTitle() {
        let value = title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        guard !value.isEmpty else {
            title = task.title
            return
        }
        title = value
        if value != task.title { Task { await store.updateTask(task.id, [.title(value)]) } }
    }

    // MARK: Day

    private var dayBlock: some View {
        let today = store.today
        let shown = TaskRules.effectiveDay(task, today: today)
        let carried = TaskRules.carriedFrom(task, today: today)
        let label: String = {
            if !task.isOpen { return "Done · \(task.day.map { DayFormat.withDate($0, today: today) } ?? "Today")" }
            return shown.map { DayFormat.withDate($0, today: today) } ?? "No day · Inbox"
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Label("Day", systemImage: "calendar")
                .font(Typo.sans(12))
                .foregroundStyle(Palette.muted)
            HStack(spacing: 8) {
                Text(label).font(Typo.sans(14, .semibold)).foregroundStyle(Palette.ink)
                if let carried { CarryTag(text: DayFormat.from(carried, today: today)) }
            }
            if task.isOpen {
                HStack(spacing: 6) {
                    if let shown {
                        let next = shown.adding(days: 1)
                        Button {
                            Task { await store.pushToNextDay([task.id]) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.to.line")
                                Text(DayFormat.relative(next, today: today) == "Tomorrow" ? "Move to tomorrow" : "Push to \(DayFormat.short(next, today: today))")
                                Text("⌘→").font(Typo.mono(11)).foregroundStyle(Palette.muted)
                            }
                        }
                        .buttonStyle(.nextlet(.outline, .small))
                        if shown != today {
                            Button {
                                Task { await store.bringBackToToday(task.id) }
                            } label: {
                                Label("Back to today", systemImage: "arrow.left.to.line")
                            }
                            .buttonStyle(.nextlet(.outline, .small))
                        }
                    } else {
                        Button {
                            Task { await store.rescheduleTask(task.id, to: today) }
                        } label: {
                            Label("Today", systemImage: "sun.max")
                        }
                        .buttonStyle(.nextlet(.outline, .small))
                        Button("Tomorrow") { Task { await store.rescheduleTask(task.id, to: today.adding(days: 1)) } }
                            .buttonStyle(.nextlet(.outline, .small))
                    }
                }
                HStack(spacing: 6) {
                    Button("Pick a day…") {
                        pickedDate = (shown ?? today).date()
                        pickingDay = true
                    }
                    .buttonStyle(.nextlet(.outline, .small))
                    .popover(isPresented: $pickingDay, arrowEdge: .bottom) { dayPicker }
                    if task.day != nil {
                        Button("Remove day") { Task { await store.rescheduleTask(task.id, to: nil) } }
                            .buttonStyle(.nextlet(.quiet, .small))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }

    private var dayPicker: some View {
        VStack(alignment: .trailing, spacing: 10) {
            DatePicker("Day", selection: $pickedDate, in: store.today.date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Button("Cancel") { pickingDay = false }
                    .buttonStyle(.nextlet(.quiet, .small))
                Button("Move") {
                    pickingDay = false
                    let day = Day.of(pickedDate)
                    Task { await store.rescheduleTask(task.id, to: day) }
                }
                .buttonStyle(.nextlet(.primary, .small))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    // MARK: Fields

    private var fields: some View {
        let anchorDay = task.day ?? store.today
        let choice = RepeatChoice.of(task.repeat, day: anchorDay)
        var estimates = Format.estimateChoices
        if let current = task.estimateMinutes, !estimates.contains(current) { estimates = (estimates + [current]).sorted() }

        let estimate = Binding<Int?>(
            get: { task.estimateMinutes },
            set: { value in Task { await store.updateTask(task.id, [.estimateMinutes(value)]) } }
        )
        let priority = Binding<Int>(
            get: { task.priority },
            set: { value in Task { await store.updateTask(task.id, [.priority(value)]) } }
        )
        let repeatChoice = Binding<RepeatChoice>(
            get: { pickingWeekdays ? .custom : choice },
            set: { value in
                pickingWeekdays = value == .custom
                let rule = value.rule(day: anchorDay, current: task.repeat)
                Task { await store.updateTask(task.id, [.repeatRule(rule)]) }
            }
        )

        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Label("Estimate", systemImage: "hourglass").font(Typo.sans(12.5)).foregroundStyle(Palette.muted)
                Picker("Estimate", selection: estimate) {
                    Text("None").tag(Int?.none)
                    ForEach(estimates, id: \.self) { minutes in
                        Text(Format.estimate(minutes)).tag(Int?.some(minutes))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            GridRow {
                Label("Priority", systemImage: "flag").font(Typo.sans(12.5)).foregroundStyle(Palette.muted)
                Picker("Priority", selection: priority) {
                    ForEach(0..<4, id: \.self) { level in
                        Text(Format.priorityLabels[level]).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            GridRow {
                Label("Repeat", systemImage: "repeat").font(Typo.sans(12.5)).foregroundStyle(Palette.muted)
                Picker("Repeat", selection: repeatChoice) {
                    ForEach(RepeatChoice.options(day: anchorDay, rule: task.repeat), id: \.choice) { option in
                        Text(option.label).tag(option.choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if case .weekly(let days)? = task.repeat, pickingWeekdays || choice == .custom {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    HStack(spacing: 4) {
                        ForEach(1...7, id: \.self) { weekday in
                            let on = days.contains(weekday)
                            Button {
                                let next = on ? days.filter { $0 != weekday } : (days + [weekday]).sorted()
                                guard !next.isEmpty else { return }
                                Task { await store.updateTask(task.id, [.repeatRule(.weekly(days: next))]) }
                            } label: {
                                Text(String(DayFormat.weekdayShort[weekday - 1].prefix(2)))
                                    .font(Typo.sans(11.5, .medium))
                                    .foregroundStyle(on ? .white : Palette.graphite)
                                    .frame(width: 28, height: 26)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? Palette.indigo : Palette.surface))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Palette.indigo : Palette.line2, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(DayFormat.weekdayLong[weekday - 1])
                        }
                    }
                }
            }
        }
    }

    // MARK: Subtasks

    private var subtasks: some View {
        let doneCount = task.subtasks.filter(\.done).count
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Subtasks").font(Typo.sans(12, .semibold))
                Spacer()
                if !task.subtasks.isEmpty {
                    Text("\(doneCount)/\(task.subtasks.count)").font(Typo.mono(11)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, 2)
            if task.subtasks.isEmpty {
                Text("No subtasks yet. Break it down if it feels big.")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(Palette.graphite)
                    .padding(.vertical, 2)
            }
            ForEach(task.subtasks) { subtask in
                SubtaskRow(taskID: task.id, subtask: subtask)
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.indigo).frame(width: 18)
                TextField("Add subtask", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .font(Typo.sans(12.5))
                    .onSubmit {
                        let value = newSubtask.trimmingCharacters(in: .whitespaces)
                        guard !value.isEmpty else { return }
                        newSubtask = ""
                        Task { await store.addSubtask(task.id, title: value) }
                    }
            }
            .frame(height: 28)
        }
    }

    // MARK: Notes and footer

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(Typo.sans(12, .semibold))
            NotesEditor(text: $notes, placeholder: "Add notes, links or context…")
                .onChange(of: notes) {
                    if notes != task.notes { notesDirty = true }
                }
                .background {
                    RoundedRectangle(cornerRadius: 9).fill(Palette.surface)
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.cardBorder, lineWidth: 1)
                }
        }
    }

    private func saveNotes() {
        guard notesDirty else { return }
        notesDirty = false
        if notes != task.notes { Task { await store.updateTask(task.id, [.notes(notes)]) } }
    }

    private var footer: some View {
        let canMakeNext = task.isOpen && TaskRules.effectiveDay(task, today: store.today) == store.today && store.nextUp?.id != task.id
        return VStack(alignment: .leading, spacing: 10) {
            if task.isOpen {
                Button {
                    AppEnvironment.shared.startFocus(on: task.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").foregroundStyle(Palette.primaryAccent)
                        Text("Start focus session")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nextlet(.primary))
            }
            HStack(spacing: 6) {
                if canMakeNext {
                    Button {
                        Task { await store.makeNextUp(task.id) }
                    } label: {
                        Label("Make next up", systemImage: "arrow.up")
                    }
                    .buttonStyle(.nextlet(.outline, .small))
                }
                Button {
                    Task { await store.deleteTask(task.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.nextlet(.danger, .small))
                Spacer()
            }
            Text("Added \(DayFormat.short(Day.of(task.createdAt), today: store.today))")
                .font(Typo.sans(11.5))
                .foregroundStyle(Palette.muted)
        }
        .padding(.top, 4)
    }
}

struct SubtaskRow: View {
    @Environment(Store.self) private var store
    let taskID: String
    let subtask: Subtask
    @ViewState private var title = ""
    @FocusState private var focused: Bool
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.updateSubtask(taskID, subtask.id, done: !subtask.done) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4.5).fill(subtask.done ? Palette.indigo : Color.clear)
                    RoundedRectangle(cornerRadius: 4.5).strokeBorder(subtask.done ? Palette.indigo : Palette.faint, lineWidth: 1.5)
                    if subtask.done {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 15, height: 15)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.done ? "Uncheck \(subtask.title)" : "Check \(subtask.title)")
            TextField("Subtask", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.sans(13))
                .foregroundStyle(subtask.done ? Palette.muted : Palette.ink)
                .strikethrough(subtask.done)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
            if hovering {
                IconButton(systemImage: "xmark", help: "Delete subtask", size: 22, symbolSize: 9.5) {
                    Task { await store.deleteSubtask(taskID, subtask.id) }
                }
            }
        }
        .onHover { hovering = $0 }
        .onAppear { title = subtask.title }
        .onChange(of: subtask.title) { if !focused { title = subtask.title } }
    }

    private func commit() {
        let value = title.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else {
            title = subtask.title
            return
        }
        if value != subtask.title { Task { await store.updateSubtask(taskID, subtask.id, title: value) } }
    }
}
