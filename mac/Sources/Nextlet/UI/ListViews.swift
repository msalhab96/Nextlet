import AppKit
import NextletCore
import SwiftUI

// MARK: Shared toolbar pieces

/// Show done tasks, and limit lists to one project.
struct FilterMenu: View {
    @Environment(Store.self) private var store
    var includesDone = true

    var body: some View {
        @Bindable var store = store
        let active = store.projectFilter != nil || (includesDone && !store.showDone)
        Menu {
            if includesDone {
                Toggle("Show Done Tasks", isOn: $store.showDone)
                Divider()
            }
            Picker("Project", selection: $store.projectFilter) {
                Text("All Projects").tag(String?.none)
                ForEach(store.projects) { project in
                    Text(project.name).tag(String?.some(project.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help(active ? "Filter (on)" : "Filter")
    }
}

struct NewTaskButton: View {
    @Environment(Store.self) private var store

    var body: some View {
        Button {
            AppEnvironment.shared.panels.showCapture()
        } label: {
            Label("New Task", systemImage: "plus")
        }
        .help("New task (⌘N)")
    }
}

private func visibleIDs(_ groups: [[TaskItem]]) -> [String] {
    groups.flatMap { $0.map(\.id) }
}

// MARK: Today

struct TodayView: View {
    @Environment(Store.self) private var store

    private struct ProjectGroup: Identifiable {
        let id: String
        let name: String
        let tasks: [TaskItem]
    }

    var body: some View {
        @Bindable var store = store
        let today = store.today
        let all = store.taskList
        let todo = TaskRules.openOn(all, day: today, today: today).filter { store.matchesFilter($0) }
        let done = TaskRules.doneOn(all, day: today).filter { store.matchesFilter($0) }
        let shownDone = store.showDone ? done : []
        let pushed = TaskRules.pushedToTomorrow(all, today: today).filter { store.matchesFilter($0) }
        let total = todo.count + done.count

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let next = todo.first {
                        NextUpCard(task: next)
                    } else {
                        EmptyCard(
                            title: total > 0 ? "All clear for today." : "Nothing planned for today.",
                            message: total > 0
                                ? "Nothing left on your list. Pull something from Upcoming, or call it a day."
                                : "Add a task below, or pick one from your Inbox or Upcoming."
                        )
                    }
                    if !todo.isEmpty {
                        if store.groupByProject {
                            ForEach(groups(todo)) { group in
                                TaskSection(title: group.name, count: "\(group.tasks.count)", tasks: group.tasks, showProject: false)
                            }
                        } else {
                            TaskSection(title: "To do", count: "\(todo.count) left", tasks: todo, reorderable: store.projectFilter == nil)
                        }
                    }
                    if !shownDone.isEmpty {
                        TaskSection(title: "Done", count: "\(shownDone.count)", tasks: shownDone)
                    }
                    if !pushed.isEmpty {
                        MovedSection(tasks: pushed)
                    }
                    AddTaskField(defaultDay: today, defaultProjectID: store.projectFilter, placeholder: "New task — try “Call mom tomorrow #Personal”")
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            TodayFooter(open: todo.count, done: done.count)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ToolbarTitle(title: "Today", subtitle: "\(DayFormat.full(today)) · \(todo.count) left")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Group", selection: $store.groupByProject) {
                    Text("List").tag(false)
                    Text("By project").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Group today’s tasks by project")
                FilterMenu()
                NewTaskButton()
                InspectorToggle()
            }
        }
        .onChange(of: visibleIDs([todo, shownDone, pushed]), initial: true) { _, ids in
            store.visibleOrder = ids
        }
    }

    private func groups(_ tasks: [TaskItem]) -> [ProjectGroup] {
        var result: [ProjectGroup] = store.projects.compactMap { project in
            let list = tasks.filter { $0.projectId == project.id }
            return list.isEmpty ? nil : ProjectGroup(id: project.id, name: project.name, tasks: list)
        }
        let loose = tasks.filter { task in task.projectId == nil || !store.projects.contains { $0.id == task.projectId } }
        if !loose.isEmpty { result.append(ProjectGroup(id: "none", name: "No project", tasks: loose)) }
        return result
    }
}

struct MovedSection: View {
    @Environment(Store.self) private var store
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Moved to tomorrow", count: DayFormat.short(store.today.adding(days: 1), today: store.today))
            ForEach(tasks) { task in
                let project = store.project(task.projectId)
                HStack(spacing: 10) {
                    Text(task.title)
                        .font(Typo.sans(13.5))
                        .foregroundStyle(Palette.graphite)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { store.select(task.id) }
                    HStack(spacing: 5) {
                        ProjectDot(color: Color(projectHex: project?.color))
                        Text(project?.name ?? "No project")
                    }
                    .font(Typo.sans(12))
                    .foregroundStyle(Palette.graphite)
                    Button {
                        Task { await store.bringBackToToday(task.id) }
                    } label: {
                        Label("Back to today", systemImage: "arrow.left.to.line")
                    }
                    .buttonStyle(.nextlet(.outline, .small))
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .frame(height: 38)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.dashed, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }
}

struct TodayFooter: View {
    @Environment(Store.self) private var store
    @Environment(AppSettings.self) private var settings
    let open: Int
    let done: Int

    var body: some View {
        let total = open + done
        HStack(spacing: 6) {
            Button {
                AppEnvironment.shared.panels.showCapture()
            } label: {
                HStack(spacing: 4) {
                    if settings.hotKey != .off {
                        ForEach(settings.hotKey.label.split(separator: " ").map(String.init), id: \.self) { part in
                            KeyCap(text: part)
                        }
                        Text("Capture from any app").padding(.leading, 4)
                    } else {
                        Image(systemName: "plus.rectangle.on.rectangle")
                        Text("Quick capture")
                    }
                }
                .font(Typo.sans(12))
                .foregroundStyle(Palette.graphite)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open quick capture")
            Spacer()
            Button {
                Task { await store.moveUnfinishedToTomorrow() }
            } label: {
                Label("Move unfinished to tomorrow", systemImage: "arrow.right.to.line")
            }
            .buttonStyle(.nextlet(.link, .small))
            .disabled(open == 0)
            Text("\(done) of \(total) done")
                .font(Typo.sans(12))
                .foregroundStyle(Palette.graphite)
                .padding(.leading, 6)
            MiniProgress(value: total == 0 ? 0 : Double(done) / Double(total))
        }
        .padding(.horizontal, 24)
        .frame(height: 40)
        .background(Palette.surface)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

// MARK: Inbox

struct InboxView: View {
    @Environment(Store.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let inbox = TaskRules.inbox(store.taskList).filter { store.matchesFilter($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Everything you’ve captured without a day. Give a task a day when you’re ready for it.")
                    .font(Typo.sans(13))
                    .foregroundStyle(Palette.graphite)
                if inbox.isEmpty {
                    EmptyCard(
                        title: "Inbox zero.",
                        message: settings.hotKey == .off
                            ? "Use File › Quick Capture to jot a task down without picking a day."
                            : "Press \(settings.hotKey.label) anywhere to jot a task down without picking a day."
                    )
                } else {
                    TaskSection(title: "Unscheduled", count: Format.plural(inbox.count, "task"), tasks: inbox, action: .doToday)
                }
                AddTaskField(defaultDay: nil, defaultProjectID: store.projectFilter, placeholder: "Add to the Inbox — try “Plan a weekend trip #Personal”")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ToolbarTitle(title: "Inbox", subtitle: "\(Format.plural(inbox.count, "task")) without a day")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                FilterMenu(includesDone: false)
                NewTaskButton()
                InspectorToggle()
            }
        }
        .onChange(of: inbox.map(\.id), initial: true) { _, ids in store.visibleOrder = ids }
    }
}

// MARK: Upcoming

struct UpcomingView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        let anchor = store.upcomingAnchor
        let weekStart = anchor.startOfWeek
        let weeks = DayFormat.monthWeeks(anchor)
        let rangeStart = store.upcomingMode == .week ? weekStart : (weeks.first?.first ?? anchor)
        let isCurrent = store.upcomingMode == .week
            ? weekStart == store.today.startOfWeek
            : anchor.firstOfMonth() == store.today.firstOfMonth()

        Group {
            if store.upcomingMode == .week {
                WeekList(weekStart: weekStart)
            } else {
                MonthGrid(anchor: anchor, weeks: weeks)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ToolbarTitle(
                    title: "Upcoming",
                    subtitle: store.upcomingMode == .week
                        ? "Week \(weekStart.isoWeekNumber) · \(DayFormat.weekRange(weekStart))"
                        : DayFormat.month(anchor)
                )
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("View", selection: $store.upcomingMode) {
                    ForEach(UpcomingMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                ControlGroup {
                    Button {
                        step(-1)
                    } label: {
                        Label(store.upcomingMode == .week ? "Previous Week" : "Previous Month", systemImage: "chevron.left")
                    }
                    Button(store.upcomingMode == .week ? "This Week" : "This Month") {
                        store.upcomingAnchor = store.today
                    }
                    .disabled(isCurrent)
                    Button {
                        step(1)
                    } label: {
                        Label(store.upcomingMode == .week ? "Next Week" : "Next Month", systemImage: "chevron.right")
                    }
                }
                FilterMenu()
                NewTaskButton()
                InspectorToggle()
            }
        }
        .task(id: rangeStart) { await store.ensureDoneFrom(rangeStart) }
    }

    private func step(_ direction: Int) {
        if store.upcomingMode == .week {
            store.upcomingAnchor = store.upcomingAnchor.startOfWeek.adding(days: 7 * direction)
        } else {
            store.upcomingAnchor = store.upcomingAnchor.firstOfMonth(offset: direction)
        }
    }
}

@MainActor
private func tasksShown(on day: Day, in store: Store) -> (open: [TaskItem], done: [TaskItem]) {
    let all = store.taskList
    return (
        TaskRules.openOn(all, day: day, today: store.today).filter { store.matchesFilter($0) },
        TaskRules.doneOn(all, day: day).filter { store.matchesFilter($0) }
    )
}

struct WeekList: View {
    @Environment(Store.self) private var store
    let weekStart: Day

    var body: some View {
        let days = (0..<7).map { weekStart.adding(days: $0) }
        let shown = days.map { tasksShown(on: $0, in: store) }
        let total = shown.reduce(0) { $0 + $1.open.count + $1.done.count }
        let done = shown.reduce(0) { $0 + $1.done.count }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text("\(Format.plural(total, "task")) this week · \(done) done")
                        .font(Typo.sans(13, .medium))
                        .foregroundStyle(Palette.ink)
                    Label("Push a task to the next day, or drag it onto any day", systemImage: "arrow.right.to.line")
                        .font(Typo.sans(12.5))
                        .foregroundStyle(Palette.graphite)
                }
                .padding(.horizontal, 10)
                ForEach(days, id: \.self) { day in
                    DaySection(day: day)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .onChange(of: shown.flatMap { $0.open.map(\.id) + $0.done.map(\.id) }, initial: true) { _, ids in
            store.visibleOrder = ids
        }
    }
}

struct DaySection: View {
    @Environment(Store.self) private var store
    let day: Day
    @ViewState private var adding = false
    @ViewState private var targeted = false
    @ViewState private var showDone = false

    var body: some View {
        let today = store.today
        let isToday = day == today
        let isPast = day < today
        let shown = tasksShown(on: day, in: store)
        let visibleDone = isToday && !showDone ? [] : shown.done

        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(day.day)")
                    .font(Typo.display(20, .bold))
                    .foregroundStyle(isToday ? Palette.indigo : (isPast ? Palette.muted : Palette.ink))
                Text(DayFormat.weekdayShort[day.isoWeekday - 1].uppercased())
                    .font(Typo.mono(11.5))
                    .tracking(0.8)
                    .foregroundStyle(Palette.graphite)
                if isToday {
                    Text("Today")
                        .font(Typo.sans(11, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.indigo))
                }
                Spacer()
                if isToday, !shown.done.isEmpty {
                    Button(showDone ? "Hide done" : "+ \(shown.done.count) done") { showDone.toggle() }
                        .buttonStyle(.nextlet(.quiet, .small))
                }
                if !isPast {
                    Button {
                        adding = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.nextlet(.quiet, .small))
                    .help("Add a task on \(DayFormat.short(day, today: today))")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            ForEach(shown.open + visibleDone) { task in
                TaskRow(task: task)
            }
            if adding {
                AddTaskField(defaultDay: day, placeholder: "Add a task on \(DayFormat.short(day, today: today))", compact: true) {
                    adding = false
                }
                .padding(.top, 4)
            }
            if shown.open.isEmpty && visibleDone.isEmpty && !adding {
                Text(isPast ? "Nothing done" : "Nothing planned")
                    .font(Typo.sans(12.5))
                    .foregroundStyle(Palette.faint)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(isToday ? Palette.paper : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Palette.indigo : (isToday ? Palette.line : Color.clear), lineWidth: targeted ? 2 : 1))
        .dropDestination(for: String.self) { ids, _ in
            guard !isPast, let id = ids.first, let task = store.tasks[id], task.isOpen,
                  TaskRules.effectiveDay(task, today: today) != day
            else { return false }
            Task { await store.rescheduleTask(id, to: day) }
            return true
        } isTargeted: { targeted = $0 && !isPast }
    }
}

struct MonthGrid: View {
    @Environment(Store.self) private var store
    let anchor: Day
    let weeks: [[Day]]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(DayFormat.weekdayShort, id: \.self) { label in
                        Text(label.uppercased())
                            .font(Typo.mono(11))
                            .tracking(0.8)
                            .foregroundStyle(Palette.graphite)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 6)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(weeks.flatMap { $0 }, id: \.self) { day in
                        MonthCell(day: day, inMonth: day.month == anchor.month && day.year == anchor.year)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }
}

struct MonthCell: View {
    @Environment(Store.self) private var store
    let day: Day
    let inMonth: Bool
    @ViewState private var targeted = false

    var body: some View {
        let today = store.today
        let shown = tasksShown(on: day, in: store)
        let items = shown.open + shown.done
        VStack(alignment: .leading, spacing: 2) {
            Button {
                openWeek()
            } label: {
                Text("\(day.day)")
                    .font(Typo.display(14, .bold))
                    .foregroundStyle(day == today ? .white : (inMonth ? Palette.ink : Palette.muted))
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Circle().fill(day == today ? Palette.indigo : Color.clear))
            }
            .buttonStyle(.plain)
            .help("Open the week of \(DayFormat.short(day, today: today))")
            ForEach(items.prefix(3)) { task in
                Button {
                    store.select(task.id)
                } label: {
                    HStack(spacing: 5) {
                        ProjectDot(color: Color(projectHex: store.project(task.projectId)?.color), size: 6)
                        Text(task.title)
                            .font(Typo.sans(11.5))
                            .foregroundStyle(task.isOpen ? Palette.ink : Palette.muted)
                            .strikethrough(!task.isOpen)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if items.count > 3 {
                Button("+\(items.count - 3) more", action: openWeek)
                    .buttonStyle(.plain)
                    .font(Typo.mono(11))
                    .foregroundStyle(Palette.graphite)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(inMonth ? Palette.surface : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Palette.indigo : Palette.line, style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: inMonth || targeted ? [] : [4, 3]))
        )
        .dropDestination(for: String.self) { ids, _ in
            guard day >= today, let id = ids.first, store.tasks[id]?.isOpen == true else { return false }
            Task { await store.rescheduleTask(id, to: day) }
            return true
        } isTargeted: { targeted = $0 && day >= today }
    }

    private func openWeek() {
        store.upcomingMode = .week
        store.upcomingAnchor = day
    }
}

// MARK: Projects

struct ProjectView: View {
    @Environment(Store.self) private var store
    let projectID: String
    @ViewState private var renaming = false
    @ViewState private var renameText = ""
    @ViewState private var deleting = false

    var body: some View {
        if let project = store.project(projectID) {
            content(project)
        } else {
            VStack(spacing: 12) {
                EmptyCard(title: "Project not found", message: "It may have been deleted.")
                Button("Go to Today") { store.route = .today }.buttonStyle(.nextlet(.outline))
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func content(_ project: Project) -> some View {
        let today = store.today
        let all = store.taskList
        let open = all.filter { $0.isOpen && $0.projectId == projectID }
        let shownDay = { (task: TaskItem) in TaskRules.effectiveDay(task, today: today) }
        let todayList = open.filter { shownDay($0) == today }.sorted(by: TaskRules.bySortOrder)
        let later = open.filter { (shownDay($0).map { $0 > today }) ?? false }
            .sorted { (shownDay($0)!, $0.sortOrder) < (shownDay($1)!, $1.sortOrder) }
        let noDay = open.filter { $0.day == nil }.sorted(by: TaskRules.bySortOrder)
        let recentlyDone = all.filter { !$0.isOpen && $0.projectId == projectID }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(5)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if open.isEmpty && recentlyDone.isEmpty {
                    EmptyCard(title: "Nothing here yet.", message: "Add a task below, or type #\(project.name.replacingOccurrences(of: " ", with: "-")) in any quick add.")
                }
                if !todayList.isEmpty {
                    TaskSection(title: "Today", count: "\(todayList.count)", tasks: todayList, showProject: false)
                }
                if !later.isEmpty {
                    TaskSection(title: "Coming up", count: "\(later.count)", tasks: later, showProject: false, showDay: true)
                }
                if !noDay.isEmpty {
                    TaskSection(title: "No day yet", count: "\(noDay.count)", tasks: noDay, showProject: false, action: .doToday)
                }
                if !recentlyDone.isEmpty {
                    TaskSection(title: "Recently done", tasks: Array(recentlyDone), showProject: false, showDay: true)
                }
                AddTaskField(defaultDay: nil, defaultProjectID: projectID, placeholder: "Add to \(project.name) — try “Book flights next week”")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {
                    ProjectDot(color: Color(projectHex: project.color), size: 12)
                    ToolbarTitle(title: project.name, subtitle: Format.plural(open.count, "open task"))
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Rename…") {
                        renameText = project.name
                        renaming = true
                    }
                    Menu("Colour") {
                        ForEach(Palette.projectColors, id: \.self) { hex in
                            Button {
                                Task { await store.updateProject(project.id, color: hex) }
                            } label: {
                                Label { Text(hex) } icon: { Image(nsImage: swatchImage(hex)) }
                            }
                        }
                    }
                    Divider()
                    Button("Delete Project…", role: .destructive) { deleting = true }
                } label: {
                    Label("Project Options", systemImage: "ellipsis.circle")
                }
                .help("Rename, recolour or delete this project")
                NewTaskButton()
                InspectorToggle()
            }
        }
        .alert("Rename project", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { Task { await store.updateProject(project.id, name: name) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(project.name)”?", isPresented: $deleting) {
            Button("Delete Project", role: .destructive) {
                Task {
                    if await store.deleteProject(project.id) { store.toast("Deleted the project “\(project.name)”") }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(open.isEmpty ? "Its tasks stay in Nextlet, just without a project." : "Its \(Format.plural(open.count, "open task")) stay in Nextlet, just without a project.")
        }
        .onChange(of: visibleIDs([todayList, later, noDay, Array(recentlyDone)]), initial: true) { _, ids in
            store.visibleOrder = ids
        }
    }
}

// MARK: Tags

struct TagView: View {
    @Environment(Store.self) private var store
    let tag: String
    @ViewState private var renaming = false
    @ViewState private var renameText = ""
    @ViewState private var removing = false

    var body: some View {
        let today = store.today
        let all = store.taskList.filter { Tags.contains($0.tags, tag) }
        let open = all.filter(\.isOpen)
        let shownDay = { (task: TaskItem) in TaskRules.effectiveDay(task, today: today) }
        let todayList = open.filter { shownDay($0) == today }.sorted(by: TaskRules.bySortOrder)
        let later = open.filter { (shownDay($0).map { $0 > today }) ?? false }
            .sorted { (shownDay($0)!, $0.sortOrder) < (shownDay($1)!, $1.sortOrder) }
        let noDay = open.filter { $0.day == nil }.sorted(by: TaskRules.bySortOrder)
        let recentlyDone = all.filter { !$0.isOpen }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(5)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if open.isEmpty && recentlyDone.isEmpty {
                    EmptyCard(title: "No tasks tagged “\(tag)”.", message: "Add one below, or type @\(tag.replacingOccurrences(of: " ", with: "-")) in any quick add.")
                }
                if !todayList.isEmpty {
                    TaskSection(title: "Today", count: "\(todayList.count)", tasks: todayList)
                }
                if !later.isEmpty {
                    TaskSection(title: "Coming up", count: "\(later.count)", tasks: later, showDay: true)
                }
                if !noDay.isEmpty {
                    TaskSection(title: "No day yet", count: "\(noDay.count)", tasks: noDay, action: .doToday)
                }
                if !recentlyDone.isEmpty {
                    TaskSection(title: "Recently done", tasks: Array(recentlyDone), showDay: true)
                }
                AddTaskField(defaultDay: nil, defaultTags: [tag], placeholder: "Add a task tagged \(tag)")
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "tag").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.muted)
                    ToolbarTitle(title: tag, subtitle: Format.plural(open.count, "open task"))
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Rename…") {
                        renameText = tag
                        renaming = true
                    }
                    Divider()
                    Button("Remove Tag…", role: .destructive) { removing = true }
                } label: {
                    Label("Tag Options", systemImage: "ellipsis.circle")
                }
                .help("Rename or remove this tag")
                NewTaskButton()
                InspectorToggle()
            }
        }
        .alert("Rename tag", isPresented: $renaming) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let name = renameText
                Task { await store.renameTag(tag, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every task tagged “\(tag)” gets the new name.")
        }
        .confirmationDialog("Remove the tag “\(tag)”?", isPresented: $removing) {
            Button("Remove Tag", role: .destructive) {
                Task {
                    if await store.deleteTag(tag) {
                        store.route = .today
                        store.toast("Removed the tag “\(tag)”")
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The tasks stay; only the tag comes off them.")
        }
        .onChange(of: visibleIDs([todayList, later, noDay, Array(recentlyDone)]), initial: true) { _, ids in
            store.visibleOrder = ids
        }
    }
}

// MARK: Search

struct SearchResultsView: View {
    @Environment(Store.self) private var store
    @ViewState private var results: [TaskItem] = []
    @ViewState private var state = LoadState.idle

    private enum LoadState {
        case idle
        case loading
        case done
        case failed
    }

    var body: some View {
        let term = store.searchText.trimmingCharacters(in: .whitespaces)
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                SectionHeader(title: "Results", count: state == .done ? "\(results.count)" : nil)
                ForEach(results) { task in
                    SearchRow(task: task)
                }
                if state == .done && results.isEmpty {
                    Text("No tasks match “\(term)”.").font(Typo.sans(13)).foregroundStyle(Palette.graphite).padding(10)
                }
                if state == .failed {
                    Text("Search isn’t available right now.").font(Typo.sans(13)).foregroundStyle(Palette.graphite).padding(10)
                }
                if state == .loading && results.isEmpty {
                    ProgressView().controlSize(.small).padding(10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ToolbarTitle(title: "Search", subtitle: "Titles, notes and tags (@phone), including finished tasks")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                NewTaskButton()
                InspectorToggle()
            }
        }
        .task(id: term) {
            guard !term.isEmpty else { return }
            state = .loading
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            if let found = await store.search(term) {
                results = found
                state = .done
            } else {
                state = .failed
            }
        }
        .onChange(of: results.map(\.id), initial: true) { _, ids in store.visibleOrder = ids }
    }
}

struct SearchRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    @ViewState private var hovering = false

    var body: some View {
        let day = TaskRules.effectiveDay(task, today: store.today)
        Button {
            store.open(task)
        } label: {
            HStack(spacing: 10) {
                ProjectDot(color: Color(projectHex: store.project(task.projectId)?.color), size: 8)
                Text(task.title)
                    .font(Typo.sans(13.5, .medium))
                    .foregroundStyle(task.isOpen ? Palette.ink : Palette.muted)
                    .strikethrough(!task.isOpen)
                    .lineLimit(1)
                Spacer()
                Text(task.isOpen ? (day.map { DayFormat.withDate($0, today: store.today) } ?? "Inbox") : "Done")
                    .font(Typo.sans(12))
                    .foregroundStyle(Palette.graphite)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Palette.indigoSoft : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
