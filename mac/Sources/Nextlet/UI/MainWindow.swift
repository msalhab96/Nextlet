import AppKit
import NextletCore
import SwiftUI

struct MainWindow: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch store.phase {
            case .ready:
                MainSplitView()
            case .locked:
                SignInView()
            case .failed(let message):
                ConnectionErrorView(message: message)
            case .idle, .loading:
                LoadingView()
            }
        }
        .frame(minWidth: 940, minHeight: 580)
        .background(WindowAccessor { window in
            guard let window else { return }
            AppEnvironment.shared.mainWindow = window
        })
        .onAppear {
            AppEnvironment.shared.openMainWindowAction = { openWindow(id: "main") }
        }
        .tint(Palette.indigo)
    }
}

struct MainSplitView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 300)
        } detail: {
            // The details sit in a plain column, not `.inspector`: on current macOS, text fields
            // and pop-up menus in a scroll view inside an inspector never receive clicks.
            HStack(spacing: 0) {
                ContentRouter()
                    .background(Palette.surface)
                if store.inspectorVisible && store.selectedTask != nil {
                    DetailsColumn()
                }
            }
        }
        .overlay(alignment: .bottom) {
            ToastStack().padding(.bottom, 54).padding(.horizontal, 24)
        }
        .toolbar(removing: .title)
        .navigationTitle("Nextlet")
    }
}

/// The task details to the right of the list. Drag its leading edge to resize it.
struct DetailsColumn: View {
    static let widths: ClosedRange<CGFloat> = 290...420
    private static let widthKey = "detailsColumnWidth"

    @ViewState private var width = DetailsColumn.savedWidth
    @ViewState private var widthAtDragStart: CGFloat?

    private static var savedWidth: CGFloat {
        let saved = CGFloat(UserDefaults.standard.double(forKey: widthKey))
        return saved > 0 ? min(max(saved, widths.lowerBound), widths.upperBound) : 320
    }

    var body: some View {
        InspectorPane()
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Rectangle().fill(Palette.hairline).frame(width: 1).allowsHitTesting(false)
            }
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .offset(x: -4)
                    .pointerStyle(.columnResize)
                    .gesture(resize)
                    .help("Drag to resize")
            }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { drag in
                let start = widthAtDragStart ?? width
                widthAtDragStart = start
                width = min(max(start - drag.translation.width, Self.widths.lowerBound), Self.widths.upperBound)
            }
            .onEnded { _ in
                widthAtDragStart = nil
                UserDefaults.standard.set(Double(width), forKey: Self.widthKey)
            }
    }
}

// MARK: Sidebar

struct SidebarView: View {
    @Environment(Store.self) private var store
    @Environment(FocusController.self) private var focus
    @FocusState private var searchFocused: Bool
    @ViewState private var creatingProject = false
    @ViewState private var newProjectName = ""
    @FocusState private var newProjectFocused: Bool
    @ViewState private var renaming: Project?
    @ViewState private var renameText = ""
    @ViewState private var deleting: Project?

    var body: some View {
        @Bindable var store = store
        let counts = store.counts

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                TextField("Search", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(Typo.sans(13))
                    .focused($searchFocused)
                    .onExitCommand {
                        store.searchText = ""
                        searchFocused = false
                    }
                if store.searchText.isEmpty {
                    Text("⌘K").font(Typo.mono(11)).foregroundStyle(Palette.muted)
                } else {
                    IconButton(systemImage: "xmark.circle.fill", help: "Clear search", size: 18, symbolSize: 11) { store.searchText = "" }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.ink.opacity(0.06)))

            VStack(spacing: 1) {
                NavRow(route: .inbox, title: "Inbox", icon: "tray", count: counts.inbox)
                NavRow(route: .today, title: "Today", icon: "sun.max", count: counts.today)
                NavRow(route: .upcoming, title: "Upcoming", icon: "calendar", count: counts.upcoming)
                NavRow(route: .focus, title: "Focus", icon: "scope", badge: focusBadge)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Projects")
                    .font(Typo.sans(11, .semibold))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                ForEach(store.projects) { project in
                    NavRow(
                        route: .project(project.id), title: project.name, color: Color(projectHex: project.color),
                        count: counts.byProject[project.id] ?? 0
                    )
                    .contextMenu {
                        Button("Rename…") {
                            renameText = project.name
                            renaming = project
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
                        Button("Delete…", role: .destructive) { deleting = project }
                    }
                }
                if creatingProject {
                    HStack(spacing: 9) {
                        ProjectDot(color: Palette.noProject, size: 9).padding(.horizontal, 3.5)
                        TextField("Project name", text: $newProjectName)
                            .textFieldStyle(.plain)
                            .font(Typo.sans(13))
                            .focused($newProjectFocused)
                            .onSubmit(createProject)
                            .onExitCommand { cancelProject() }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.surface))
                    .onAppear { newProjectFocused = true }
                    .onChange(of: newProjectFocused) { if !newProjectFocused { createProject() } }
                } else {
                    Button {
                        newProjectName = ""
                        creatingProject = true
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 16)
                            Text("New project")
                            Spacer()
                        }
                        .font(Typo.sans(13))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                SyncStatusView()
                Spacer()
                if store.authRequired {
                    IconButton(systemImage: "lock", help: "Lock Nextlet") { Task { await store.signOut() } }
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.leading, 10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebar)
        .onChange(of: store.searchRequest) { searchFocused = true }
        .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                if let project = renaming, !name.isEmpty { Task { await store.updateProject(project.id, name: name) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Delete Project", role: .destructive) {
                if let project = deleting {
                    Task {
                        if await store.deleteProject(project.id) { store.toast("Deleted the project “\(project.name)”") }
                    }
                }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Its tasks stay in Nextlet, just without a project.")
        }
    }

    private var focusBadge: String? {
        guard let session = focus.session, !session.finished else { return nil }
        return focus.isTimeUp ? "Done" : Format.clock(focus.remaining)
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        creatingProject = false
        newProjectName = ""
        guard !name.isEmpty else { return }
        Task {
            if let project = await store.createProject(name: name) { store.route = .project(project.id) }
        }
    }

    private func cancelProject() {
        newProjectName = ""
        creatingProject = false
    }
}

/// A sidebar row. Tasks can be dropped on Inbox, Today and projects.
struct NavRow: View {
    @Environment(Store.self) private var store
    let route: Route
    let title: String
    var icon: String?
    var color: Color?
    var count = 0
    var badge: String?
    @ViewState private var hovering = false
    @ViewState private var targeted = false

    var body: some View {
        let active = store.route == route && store.searchText.isEmpty
        Button {
            store.searchText = ""
            store.route = route
        } label: {
            HStack(spacing: 9) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(active ? .white : Palette.indigo)
                        .frame(width: 16)
                } else if let color {
                    ProjectDot(color: color, size: 9).padding(.horizontal, 3.5)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(Typo.mono(11.5)).foregroundStyle(active ? .white : Palette.indigo)
                } else if count > 0 {
                    Text("\(count)").font(Typo.mono(11.5)).foregroundStyle(active ? .white : Palette.muted)
                }
            }
            .font(Typo.sans(13, active ? .medium : .regular))
            .foregroundStyle(active ? .white : Palette.ink2)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? Palette.indigo : (targeted ? Palette.indigoSoft : (hovering ? Palette.sidebarHover : Color.clear)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, store.tasks[id] != nil else { return false }
            switch route {
            case .inbox: Task { await store.rescheduleTask(id, to: nil) }
            case .today: Task { await store.rescheduleTask(id, to: store.today) }
            case .project(let projectID): Task { await store.updateTask(id, [.projectId(projectID)]) }
            case .upcoming, .focus: return false
            }
            return true
        } isTargeted: { targeted = $0 && (route != .upcoming && route != .focus) }
    }
}

struct SyncStatusView: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            if store.pending > 0 {
                ProgressView().controlSize(.mini)
                Text("Saving…")
            } else if let error = store.syncError {
                Image(systemName: "exclamationmark.icloud").foregroundStyle(Palette.danger)
                Text("Not saved").foregroundStyle(Palette.danger).help(error)
            } else {
                Image(systemName: "checkmark.icloud")
                Text("Synced")
            }
        }
        .font(Typo.sans(12))
        .foregroundStyle(Palette.muted)
    }
}

// MARK: Content

struct ContentRouter: View {
    @Environment(Store.self) private var store

    var body: some View {
        Group {
            if !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                SearchResultsView()
            } else {
                switch store.route {
                case .today: TodayView()
                case .inbox: InboxView()
                case .upcoming: UpcomingView()
                case .focus: FocusPane()
                case .project(let id): ProjectView(projectID: id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The title and subtitle in the toolbar, in the brand typeface.
struct ToolbarTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Typo.display(17, .bold)).foregroundStyle(Palette.ink)
            if let subtitle {
                Text(subtitle).font(Typo.sans(11.5)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.leading, 4)
        .fixedSize()
    }
}

/// The inspector toggle that sits at the end of every toolbar.
struct InspectorToggle: View {
    @Environment(Store.self) private var store

    var body: some View {
        Button {
            store.inspectorVisible.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
        .help(store.selectedTask == nil ? "Select a task to see its details" : (store.inspectorVisible ? "Hide details" : "Show details"))
        .disabled(store.selectedTask == nil)
    }
}

// MARK: Status screens

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            LogoMark(size: 44)
            ProgressView().controlSize(.small)
            Text("Loading your day…").font(Typo.sans(13)).foregroundStyle(Palette.graphite)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}

struct SignInView: View {
    @Environment(Store.self) private var store
    @Environment(AppSettings.self) private var settings
    @ViewState private var password = ""
    @ViewState private var error: String?
    @ViewState private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            LogoMark(size: 44)
            Text("Nextlet is locked").font(Typo.display(26, .semibold)).foregroundStyle(Palette.ink)
            Text("Enter the password for \(settings.serverAddress).")
                .font(Typo.sans(13.5))
                .foregroundStyle(Palette.graphite)
            HStack(spacing: 8) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .font(Typo.sans(14))
                    .frame(width: 260)
                    .focused($focused)
                    .onSubmit(submit)
                Button(busy ? "Unlocking…" : "Unlock", action: submit)
                    .buttonStyle(.nextlet(.primary))
                    .disabled(password.isEmpty || busy)
            }
            if let error {
                Text(error).font(Typo.sans(13)).foregroundStyle(Palette.danger)
            }
            SettingsLink { Text("Change server…") }
                .buttonStyle(.nextlet(.link, .small))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !password.isEmpty, !busy else { return }
        busy = true
        error = nil
        Task {
            let message = await store.signIn(password: password)
            busy = false
            if let message {
                error = message
                password = ""
                focused = true
            }
        }
    }
}

struct ConnectionErrorView: View {
    @Environment(Store.self) private var store
    @Environment(AppSettings.self) private var settings
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            LogoMark(size: 44)
            Text("Can’t reach Nextlet").font(Typo.display(26, .semibold)).foregroundStyle(Palette.ink)
            Text(message)
                .font(Typo.sans(13.5))
                .foregroundStyle(Palette.graphite)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text("Start the server with “docker compose up -d” in the Nextlet folder, or point the app at another address in Settings.")
                .font(Typo.sans(12.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 8) {
                Button("Try Again") { Task { await store.load() } }
                    .buttonStyle(.nextlet(.primary))
                SettingsLink { Text("Open Settings") }
                    .buttonStyle(.nextlet(.outline))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper)
    }
}
