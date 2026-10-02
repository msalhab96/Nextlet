import AppKit
import NextletCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ServerSettings()
                .tabItem { Label("Server", systemImage: "server.rack") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            FocusSettings()
                .tabItem { Label("Focus", systemImage: "scope") }
        }
        .frame(width: 540)
    }
}

private struct ServerSettings: View {
    @Environment(Store.self) private var store
    @Environment(AppSettings.self) private var settings
    @ViewState private var address = ""
    @ViewState private var password = ""
    @ViewState private var signInError: String?
    @ViewState private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("Server address", text: $address, prompt: Text(AppSettings.defaultServer))
                    .onSubmit(connect)
                Text("Where your Nextlet server runs. With Docker on this Mac, that’s \(AppSettings.defaultServer).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(busy ? "Connecting…" : "Connect", action: connect)
                        .disabled(busy || AppSettings.url(from: address) == nil)
                    Spacer()
                    status
                }
            }
            if store.authRequired {
                Section("Password protection") {
                    if store.phase == .locked {
                        SecureField("Password", text: $password)
                            .onSubmit(signIn)
                        if let signInError {
                            Text(signInError).foregroundStyle(Palette.danger)
                        }
                        Button(busy ? "Signing in…" : "Sign In", action: signIn)
                            .disabled(password.isEmpty || busy)
                    } else {
                        HStack {
                            Text("Signed in to \(settings.serverAddress).")
                            Spacer()
                            Button("Sign Out") { Task { await store.signOut() } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { address = settings.serverAddress }
    }

    @ViewBuilder
    private var status: some View {
        switch store.phase {
        case .ready:
            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .locked:
            Label("Needs a password", systemImage: "lock.fill").foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger).lineLimit(2)
        case .idle, .loading:
            ProgressView().controlSize(.small)
        }
    }

    private func connect() {
        guard let url = AppSettings.url(from: address) else { return }
        let changed = url != settings.serverURL
        settings.serverAddress = url.absoluteString
        address = url.absoluteString
        if changed { settings.sessionToken = nil }
        busy = true
        Task {
            await store.reconnect()
            busy = false
        }
    }

    private func signIn() {
        guard !password.isEmpty else { return }
        busy = true
        signInError = nil
        Task {
            signInError = await store.signIn(password: password)
            busy = false
            if signInError == nil { password = "" }
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @ViewState private var openAtLogin = LoginItem.isEnabled
    @ViewState private var loginItemError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                HStack(spacing: 20) {
                    ForEach(AppearanceMode.allCases) { mode in
                        AppearanceTile(mode: mode, selected: settings.appearance == mode) { settings.appearance = mode }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                Text("Match System switches with the Light or Dark choice in System Settings › Appearance. You can also change it from View › Appearance.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open Nextlet when you log in", isOn: Binding(
                    get: { openAtLogin },
                    set: { value in
                        loginItemError = LoginItem.set(value)
                        openAtLogin = LoginItem.isEnabled
                    }
                ))
                if let loginItemError {
                    Text(loginItemError).font(.callout).foregroundStyle(Palette.danger)
                } else if LoginItem.needsApproval {
                    HStack {
                        Text("macOS needs your OK in Login Items first.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }
}

/// One choice, shown as a little picture of the window in that look.
private struct AppearanceTile: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 112, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Palette.indigo : Palette.line2, lineWidth: selected ? 2.5 : 1))
                Text(mode.label)
                    .font(Typo.sans(12.5, selected ? .semibold : .regular))
                    .foregroundStyle(Palette.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var preview: some View {
        switch mode {
        case .light:
            MiniWindow().environment(\.colorScheme, .light)
        case .dark:
            MiniWindow().environment(\.colorScheme, .dark)
        case .system:
            ZStack {
                MiniWindow().environment(\.colorScheme, .light)
                MiniWindow().environment(\.colorScheme, .dark)
                    .mask { HStack(spacing: 0) { Color.clear; Color.black } }
            }
        }
    }
}

/// A tiny drawing of the main window in the surrounding colour scheme.
private struct MiniWindow: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.indigo).frame(width: 24, height: 6)
                RoundedRectangle(cornerRadius: 2).fill(Palette.faint).frame(width: 18, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Palette.faint).frame(width: 21, height: 4)
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(width: 36, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Palette.sidebar)
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.night).frame(height: 14)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 4) {
                        Circle().strokeBorder(Palette.faint, lineWidth: 1).frame(width: 6, height: 6)
                        RoundedRectangle(cornerRadius: 2).fill(Palette.line2).frame(height: 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
        }
    }
}

private struct ShortcutSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PanelState.self) private var panelState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Quick capture", selection: $settings.hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in Text(preset.label).tag(preset) }
                }
                .onChange(of: settings.hotKey) { AppEnvironment.shared.registerHotKey() }
                if settings.hotKey == .off {
                    Text("Quick capture is still in the File menu and the menu bar.").font(.callout).foregroundStyle(.secondary)
                } else if panelState.hotKeyRegistered {
                    Text("Press \(settings.hotKey.label) in any app to capture a task.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Another app already uses \(settings.hotKey.label). Pick a different shortcut.").font(.callout).foregroundStyle(Palette.danger)
                }
            }
            Section {
                Button("Show All Keyboard Shortcuts") { openWindow(id: "shortcuts") }
            }
        }
        .formStyle(.grouped)
    }
}

private struct FocusSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Session length for tasks without an estimate", selection: $settings.focusMinutes) {
                    ForEach([15, 25, 30, 45, 60, 90], id: \.self) { minutes in Text(Format.estimate(minutes)).tag(minutes) }
                }
                Toggle("Show the floating timer when focus starts", isOn: $settings.showFloatingTimer)
                Toggle("Play a sound when time is up", isOn: $settings.playSound)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutsView: View {
    @Environment(AppSettings.self) private var settings

    private var groups: [(title: String, rows: [(keys: String, action: String)])] {
        [
            ("Anywhere", [
                (settings.hotKey == .off ? "Off" : settings.hotKey.label, "Quick capture (change it in Settings)"),
            ]),
            ("Main window", [
                ("⌘N", "New task"),
                ("⌘K", "Search tasks and notes"),
                ("⌘F", "Start focus on the selected or next task"),
                ("⌘→", "Move the selected task to the next day"),
                ("⌘↵", "Complete the selected task"),
                ("⌘⌫", "Delete the selected task"),
                ("⌘Z", "Undo the last move, completion or delete"),
                ("↑ ↓", "Select the previous or next task"),
                ("Esc", "Deselect"),
                ("⌘1 – ⌘4", "Inbox, Today, Upcoming, Focus"),
                ("⌥⌘I", "Show or hide details"),
                ("⌘R", "Refresh"),
            ]),
            ("Quick capture", [
                ("↵", "Add the task"),
                ("⌘D / ⌘P", "Choose a day or a project"),
                ("⌘1 – ⌘3", "Set the priority (⌘0 clears it)"),
                ("⌘S", "Add subtasks"),
                ("Esc", "Close"),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keyboard shortcuts").font(Typo.display(22, .semibold)).foregroundStyle(Palette.ink)
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title.uppercased()).font(Typo.mono(11)).tracking(0.9).foregroundStyle(Palette.graphite)
                    ForEach(group.rows, id: \.action) { row in
                        HStack {
                            Text(row.action).font(Typo.sans(13)).foregroundStyle(Palette.ink)
                            Spacer()
                            KeyCap(text: row.keys)
                        }
                        .frame(height: 24)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Palette.paper2)
    }
}
