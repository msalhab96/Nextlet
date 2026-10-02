import AppKit
import NextletCore
import SwiftUI

/// Quick capture (⌥Space by default): jot a task down from any app.
struct QuickCaptureView: View {
    @Environment(Store.self) private var store
    @Environment(PanelState.self) private var panelState
    let onClose: () -> Void
    /// Pre-filled text, used by the snapshot tool.
    var initialText = ""

    private enum DayChoice: Equatable {
        case parsed
        case someday
        case day(Day)
    }

    private enum ProjectChoice: Equatable {
        case parsed
        case none
        case project(String)
    }

    private enum Field: Hashable {
        case title
    }

    @ViewState private var text = ""
    @ViewState private var dayChoice = DayChoice.parsed
    @ViewState private var projectChoice = ProjectChoice.parsed
    @ViewState private var priorityChoice: Int?
    @ViewState private var showSubtasks = false
    @ViewState private var subtasksText = ""
    @ViewState private var confirmation: String?
    @ViewState private var subtasksFocus = 0
    @ViewState private var showingDays = false
    @ViewState private var showingProjects = false
    @ViewState private var pickedDate = Date()
    @FocusState private var focused: Field?

    /// What quick add understood, with any choices made from the menus on top.
    private var result: QuickAdd.Result {
        var result = QuickAdd.parse(text, today: store.today, projects: store.projects, tags: store.knownTags)
        switch dayChoice {
        case .parsed: break
        case .someday: result.day = .someday
        case .day(let day): result.day = .day(day)
        }
        switch projectChoice {
        case .parsed: break
        case .none: result.project = nil
        case .project(let id): result.project = store.project(id).map { .existing($0) }
        }
        if let priorityChoice { result.priority = priorityChoice == 0 ? nil : priorityChoice }
        return result
    }

    /// The day and project from the screen quick capture was opened on, unless overridden.
    private var defaultDay: Day? { panelState.captureDay }
    private var defaultProjectID: String? { projectChoice == .none ? nil : panelState.captureProjectID }
    private var defaultTags: [String] { panelState.captureTags }

    var body: some View {
        let result = self.result
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    LogoMark(size: 34)
                    TextField("What’s next?", text: $text)
                        .textFieldStyle(.plain)
                        .font(Typo.sans(21, .medium))
                        .foregroundStyle(Palette.ink)
                        .focused($focused, equals: .title)
                        .onSubmit(add)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 10) {
                    if !result.title.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("CREATES").font(Typo.mono(11)).tracking(0.9).foregroundStyle(Palette.graphite)
                            Text(result.title).font(Typo.sans(14.5, .semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                        }
                    }
                    if result.day != nil || result.project != nil || result.priority != nil {
                        ParsedChips(parsed: result)
                    } else if text.isEmpty {
                        (Text("Add details as you type: ") + Text("tomorrow #Home @phone !1").font(Typo.mono(12)).foregroundColor(Palette.ink)
                            + Text(", ") + Text("fri").font(Typo.mono(12)).foregroundColor(Palette.ink)
                            + Text(", ") + Text("next week").font(Typo.mono(12)).foregroundColor(Palette.ink)
                            + Text(" or ") + Text("someday").font(Typo.mono(12)).foregroundColor(Palette.ink))
                            .font(Typo.sans(12.5))
                            .foregroundStyle(Palette.graphite)
                    }
                    if showSubtasks {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SUBTASKS · ONE PER LINE").font(Typo.mono(10.5)).tracking(0.8).foregroundStyle(Palette.graphite)
                            PlainTextEditor(text: $subtasksText, placeholder: "One step per line", minHeight: 72, maxHeight: 160, focusRequest: subtasksFocus)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 1))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 68)
                .padding(.trailing, 20)
                .padding(.bottom, 14)

                Rectangle().fill(Palette.line).frame(height: 1)

                HStack(spacing: 4) {
                    optionButton("Day", icon: "calendar", shortcut: "⌘D") { showingDays.toggle() }
                        .keyboardShortcut("d")
                        .popover(isPresented: $showingDays, arrowEdge: .bottom) { dayOptions }
                    optionButton("Project", icon: "square.grid.2x2", shortcut: "⌘P") { showingProjects.toggle() }
                        .keyboardShortcut("p")
                        .popover(isPresented: $showingProjects, arrowEdge: .bottom) { projectOptions }
                    Menu {
                        ForEach(0..<4, id: \.self) { level in
                            Button(Format.priorityLabels[level]) { priorityChoice = level }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flag")
                            Text("Priority")
                            Text("⌘1–3").font(Typo.mono(11)).foregroundStyle(Palette.muted)
                        }
                        .font(Typo.sans(13))
                        .foregroundStyle(Palette.ink2)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    optionButton(showSubtasks ? "Hide subtasks" : "Subtasks", icon: "list.bullet", shortcut: "⌘S") {
                        showSubtasks.toggle()
                        if showSubtasks { subtasksFocus += 1 } else { focused = .title }
                    }
                    .keyboardShortcut("s")
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                HStack(spacing: 10) {
                    (Text("Lands in ") + Text(store.destination(of: result, defaultDay: defaultDay, defaultProjectID: defaultProjectID)).bold().foregroundColor(Palette.ink)
                        + Text(defaultTags.isEmpty ? "" : ", tagged ") + Text(defaultTags.joined(separator: ", ")).bold().foregroundColor(Palette.ink))
                        .font(Typo.sans(12.5))
                        .foregroundStyle(Palette.graphite)
                    Spacer()
                    Button(action: onClose) {
                        HStack(spacing: 6) {
                            KeyCap(text: "esc")
                            Text("Close").font(Typo.sans(13)).foregroundStyle(Palette.ink2)
                        }
                    }
                    .buttonStyle(.plain)
                    Button(action: add) {
                        HStack(spacing: 8) {
                            Text("Add task")
                            Text("↵").font(Typo.mono(12)).foregroundStyle(Palette.onPrimary2)
                        }
                    }
                    .buttonStyle(.nextlet(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(result.title.isEmpty)
                    .help("Add task (↵, or ⌘↵ from the subtasks)")
                }
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .background(Palette.well)
            }
            .frame(width: 640)
            .background(Palette.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.panelBorder, lineWidth: 1))

            if let confirmation {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Palette.onMarker)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Palette.marker))
                    Text(confirmation).font(Typo.sans(13)).foregroundStyle(.white)
                }
                .padding(.leading, 10)
                .padding(.trailing, 16)
                .frame(height: 40)
                .background(Capsule().fill(Palette.night))
                .overlay(Capsule().strokeBorder(Palette.nightEdge, lineWidth: 1))
            }

            // Keyboard shortcuts for priority, kept out of sight.
            HStack {
                ForEach(0..<4, id: \.self) { level in
                    Button("") { priorityChoice = level }
                        .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: .command)
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .padding(1)
        .onExitCommand(perform: onClose)
        .onChange(of: panelState.captureToken, initial: true) {
            reset()
            confirmation = nil
            focused = .title
        }
    }

    private func optionButton(_ title: String, icon: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                Text(shortcut).font(Typo.mono(11)).foregroundStyle(Palette.muted)
            }
            .font(Typo.sans(13))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dayOptions: some View {
        let today = store.today
        return VStack(alignment: .leading, spacing: 2) {
            dayRow("Today", detail: DayFormat.short(today)) { dayChoice = .day(today) }
            dayRow("Tomorrow", detail: DayFormat.short(today.adding(days: 1))) { dayChoice = .day(today.adding(days: 1)) }
            dayRow("Next week", detail: DayFormat.short(today.startOfWeek.adding(days: 7))) { dayChoice = .day(today.startOfWeek.adding(days: 7)) }
            dayRow("Someday", detail: "Inbox") { dayChoice = .someday }
            if dayChoice != .parsed {
                dayRow("As typed", detail: "") { dayChoice = .parsed }
            }
            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.vertical, 4)
            DatePicker("Pick a day", selection: $pickedDate, in: today.date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            Button("Use this day") {
                dayChoice = .day(Day.of(pickedDate))
                showingDays = false
            }
            .buttonStyle(.nextlet(.primary, .small))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(10)
        .frame(width: 250)
    }

    private func dayRow(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showingDays = false
        } label: {
            HStack {
                Text(title).font(Typo.sans(13, .medium)).foregroundStyle(Palette.ink)
                Spacer()
                Text(detail).font(Typo.sans(12)).foregroundStyle(Palette.graphite)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var projectOptions: some View {
        VStack(alignment: .leading, spacing: 2) {
            projectRow("No project", color: Palette.noProject) { projectChoice = .none }
            ForEach(store.projects) { project in
                projectRow(project.name, color: Color(projectHex: project.color)) { projectChoice = .project(project.id) }
            }
            if projectChoice != .parsed {
                projectRow("As typed", color: .clear) { projectChoice = .parsed }
            }
        }
        .padding(8)
        .frame(width: 220)
    }

    private func projectRow(_ name: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showingProjects = false
        } label: {
            HStack(spacing: 8) {
                ProjectDot(color: color, size: 8)
                Text(name).font(Typo.sans(13)).foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reset() {
        text = initialText
        dayChoice = .parsed
        projectChoice = .parsed
        priorityChoice = nil
        showSubtasks = false
        subtasksText = ""
    }

    private func add() {
        let result = self.result
        guard !result.title.isEmpty else { return }
        let day = defaultDay
        let projectID = defaultProjectID
        let tags = defaultTags
        let destination = store.destination(of: result, defaultDay: day, defaultProjectID: projectID)
        let subtasks = showSubtasks
            ? subtasksText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : []
        reset()
        focused = .title
        Task {
            if await store.createFromQuickAdd(result, defaultDay: day, defaultProjectID: projectID, defaultTags: tags, subtasks: subtasks) != nil {
                confirmation = "“\(result.title)” added to \(destination)"
                try? await Task.sleep(for: .seconds(3))
                if confirmation?.contains(result.title) == true { confirmation = nil }
            }
        }
    }
}
