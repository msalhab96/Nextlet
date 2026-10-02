import AppKit
import NextletCore
import SwiftUI

// MARK: Buttons

struct NLButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case marker
        case onDark
        case outline
        case quiet
        case link
        case danger
    }

    enum Size {
        case small
        case regular
        case large
    }

    var kind: Kind = .outline
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonLabel(configuration: configuration, kind: kind, size: size)
    }
}

private struct StyledButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let kind: NLButtonStyle.Kind
    let size: NLButtonStyle.Size
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var hovering = false

    private var height: CGFloat {
        switch size {
        case .small: return 28
        case .regular: return 34
        case .large: return 44
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: return 12.5
        case .regular: return 13
        case .large: return 15
        }
    }

    private var radius: CGFloat { size == .small ? 7 : (size == .large ? 12 : 9) }

    private var foreground: Color {
        switch kind {
        case .primary: return Palette.onPrimary
        case .onDark: return Palette.onDark
        case .marker: return Palette.onMarker
        case .outline, .quiet: return Palette.ink
        case .link: return Palette.indigoInk
        case .danger: return Palette.danger
        }
    }

    private var background: Color {
        let pressed = configuration.isPressed
        switch kind {
        case .primary: return pressed ? Palette.primaryPressed : (hovering ? Palette.primaryHover : Palette.primary)
        case .marker: return pressed ? Color(hex: 0xF2C93B) : (hovering ? Color(hex: 0xFFE174) : Palette.marker)
        case .onDark: return pressed ? .white.opacity(0.16) : (hovering ? .white.opacity(0.08) : .clear)
        case .outline: return pressed ? Palette.paper : (hovering ? Palette.paper2 : Palette.surface)
        case .quiet, .link, .danger: return pressed ? Palette.ink.opacity(0.08) : (hovering ? Palette.ink.opacity(0.05) : .clear)
        }
    }

    private var border: Color {
        switch kind {
        case .onDark: return .white.opacity(0.28)
        case .outline: return Palette.line2
        default: return .clear
        }
    }

    var body: some View {
        configuration.label
            .font(Typo.sans(fontSize, kind == .primary || kind == .marker ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .small ? 9 : 13)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: radius).fill(background))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == NLButtonStyle {
    static func nextlet(_ kind: NLButtonStyle.Kind, _ size: NLButtonStyle.Size = .regular) -> NLButtonStyle {
        NLButtonStyle(kind: kind, size: size)
    }
}

/// A small square button with an SF Symbol, used in toolbars, rows and panels.
struct IconButton: View {
    let systemImage: String
    let help: String
    var size: CGFloat = 28
    var symbolSize: CGFloat = 13
    var foreground: Color = Palette.muted
    var hoverBackground: Color = Palette.ink.opacity(0.06)
    var background: Color = .clear
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? hoverBackground : background))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

// MARK: Small pieces

struct ProjectDot: View {
    var color: Color
    var size: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(color)
            .frame(width: size, height: size)
    }
}

struct CarryTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.sans(11.5, .medium))
            .foregroundStyle(Palette.carryText)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.carryBackground))
            .fixedSize()
    }
}

struct KeyCap: View {
    let text: String
    var onDark = false

    var body: some View {
        Text(text)
            .font(Typo.mono(11, .medium))
            .foregroundStyle(onDark ? Palette.onDark2 : Palette.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(onDark ? Color.clear : Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(onDark ? Color.white.opacity(0.22) : Palette.line2, lineWidth: 1))
            .fixedSize()
    }
}

struct SectionHeader: View {
    let title: String
    var count: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Typo.sans(12, .semibold)).foregroundStyle(Palette.ink)
            if let count {
                Text(count).font(Typo.mono(11)).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }
}

struct MiniProgress: View {
    var value: Double
    var width: CGFloat = 64
    var height: CGFloat = 4
    var track: Color = Palette.line
    var fill: Color = Palette.indigo

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(track)
            Capsule().fill(fill).frame(width: max(0, min(1, value)) * width)
        }
        .frame(width: width, height: height)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

struct LogoMark: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(Palette.night)
            RoundedRectangle(cornerRadius: size * 0.3).strokeBorder(Palette.nightEdge, lineWidth: 1)
            Canvas { context, canvasSize in
                let scale = canvasSize.width / 24
                var chevron = Path()
                chevron.move(to: CGPoint(x: 8 * scale, y: 6.5 * scale))
                chevron.addLine(to: CGPoint(x: 13.5 * scale, y: 12 * scale))
                chevron.addLine(to: CGPoint(x: 8 * scale, y: 17.5 * scale))
                context.stroke(chevron, with: .color(.white), style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round, lineJoin: .round))
                let dot = CGRect(x: 15.5 * scale, y: 10 * scale, width: 4 * scale, height: 4 * scale)
                context.fill(Path(ellipseIn: dot), with: .color(Palette.marker))
            }
            .frame(width: size * 0.66, height: size * 0.66)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The circle you click to complete a task.
struct CheckButton: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    var size: CGFloat = 16
    @ViewState private var hovering = false

    var body: some View {
        let done = !task.isOpen
        Button {
            Task { await store.toggleComplete(task.id) }
        } label: {
            ZStack {
                Circle()
                    .fill(done ? Palette.indigo : (hovering ? Palette.indigoSoft : Color.clear))
                Circle()
                    .strokeBorder(done ? Palette.indigo : (hovering ? Palette.indigo : (task.priority == 1 ? Palette.priority[1] : Palette.faint)), lineWidth: size > 17 ? 1.75 : 1.5)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.55, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .frame(width: size + 16, height: size + 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(done ? "Mark as not done" : "Complete")
        .accessibilityLabel(done ? "Mark “\(task.title)” as not done" : "Complete “\(task.title)”")
    }
}

/// The day, project and priority quick add understood.
struct ParsedChips: View {
    @Environment(Store.self) private var store
    let parsed: QuickAdd.Result

    var body: some View {
        HStack(spacing: 8) {
            if let day = parsed.day {
                chip(
                    icon: "calendar", text: day.day.map { DayFormat.withDate($0, today: store.today) } ?? "Someday · Inbox",
                    foreground: Palette.indigoInk, background: Palette.indigoSoft
                )
            }
            if let project = parsed.project {
                switch project {
                case .existing(let existing):
                    projectChip(existing.name, color: Color(projectHex: existing.color))
                case .new(let name):
                    projectChip("New project: \(name)", color: Palette.noProject)
                }
            }
            ForEach(parsed.tags, id: \.self) { tag in
                chip(icon: "tag", text: tag, foreground: Palette.graphite, background: Palette.chip)
            }
            if let priority = parsed.priority {
                chip(
                    icon: "flag.fill", text: Format.priorityLabels[priority],
                    foreground: priority == 1 ? Palette.carryText : (priority == 2 ? Palette.indigoInk : Palette.graphite),
                    background: priority == 1 ? Palette.carryBackground : (priority == 2 ? Palette.indigoSoft : Palette.hairline)
                )
            }
        }
    }

    private func chip(icon: String, text: String, foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text)
        }
        .font(Typo.sans(12.5, .medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(background))
    }

    private func projectChip(_ name: String, color: Color) -> some View {
        HStack(spacing: 6) {
            ProjectDot(color: color, size: 8)
            Text(name)
        }
        .font(Typo.sans(12.5, .medium))
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.line, lineWidth: 1))
    }
}

// MARK: Toasts

struct ToastStack: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.toasts) { toast in
                ToastView(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.toasts.map(\.id))
    }
}

struct ToastView: View {
    @Environment(Store.self) private var store
    let toast: Store.Toast

    private var icon: String? {
        switch toast.icon {
        case .push: return "arrow.right.to.line"
        case .check: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(toast.icon == .error ? Color(hex: 0xFFB4A8) : Palette.marker)
            }
            Text(toast.message)
                .font(Typo.sans(12.5))
                .foregroundStyle(.white)
                .lineLimit(2)
            if let label = toast.actionLabel {
                Button {
                    toast.action?()
                    store.dismissToast(toast.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(label).font(Typo.sans(12.5, .semibold)).foregroundStyle(Palette.marker)
                        if label == "Undo" { Text("⌘Z").font(Typo.mono(11)).foregroundStyle(Palette.onDark2) }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            IconButton(systemImage: "xmark", help: "Dismiss", size: 24, symbolSize: 10, foreground: Palette.onDark2, hoverBackground: .white.opacity(0.1)) {
                store.dismissToast(toast.id)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: 10).fill(toast.icon == .error ? Color(hex: 0x3A1410) : Palette.night))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.nightEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
        .frame(maxWidth: 560)
    }
}

// MARK: Empty and window helpers

struct EmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typo.display(20, .semibold)).foregroundStyle(Palette.ink)
            Text(message).font(Typo.sans(13)).foregroundStyle(Palette.graphite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// Hands back the NSWindow a SwiftUI view lives in.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

// MARK: Tags

/// A small tag label. With `onRemove` it gets an × for taking the tag off.
struct TagChip: View {
    let name: String
    var compact = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(name).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove this tag")
                .accessibilityLabel("Remove tag \(name)")
            }
        }
        .font(Typo.sans(compact ? 11.5 : 12, .medium))
        .foregroundStyle(Palette.graphite)
        .padding(.leading, compact ? 6 : 8)
        .padding(.trailing, onRemove == nil ? (compact ? 6 : 8) : 3)
        .frame(height: compact ? 18 : 22)
        .background(Capsule().fill(Palette.chip))
    }
}

/// A row's tags: the first couple, then "+3".
struct TagList: View {
    let tags: [String]
    var limit = 2

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(limit), id: \.self) { TagChip(name: $0, compact: true) }
            if tags.count > limit {
                Text("+\(tags.count - limit)").font(Typo.sans(11.5, .medium)).foregroundStyle(Palette.muted)
            }
        }
        .help(tags.joined(separator: ", "))
    }
}

/// Lays views out in rows, wrapping onto the next line when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
