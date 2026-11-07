import SwiftUI
import AppKit

// MARK: - Menu bar panel

struct PanelView: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var u: Updater
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Store doesn't publish the clock; this redraws countdowns while the panel is on screen.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 16) {
                header
                if s.isActive {
                    activeBody
                } else if s.isPaused || s.isBreak || s.isWaiting {
                    timerBody
                } else {
                    idleBody
                }
                if !s.isActive || !s.schedules.isEmpty {
                    statsRow
                }
                alerts
                schedules
                footer
            }
        }
        .padding(20)
        .frame(width: 352)
        .background {
            PaperBackdrop(kind: .panel)
            ClearHostWindow()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: scheme == .dark
                    ? [.white.opacity(0.16), .white.opacity(0.03), .white.opacity(0.09)]
                    : [.white.opacity(0.9), .white.opacity(0.38), .white.opacity(0.62)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(scheme == .dark ? 0.05 : 0.32))
                .frame(height: 1)
                .padding(.horizontal, 26)
                .mask(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing))
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 10) {
            CloudMark(size: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text("deepwork")
                    .font(.ui(15, .semibold))
                    .tracking(-0.1)
                HStack(spacing: 5) {
                    StatusDot(active: s.isActive)
                    Text(status)
                        .font(.ui(10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            SoftSwitch(isOn: $s.enabled)
                .disabled(s.locked)
                .opacity(s.locked ? 0.5 : 1)
                .help("Enable schedules")
        }
    }

    private var status: String {
        if s.isActive, let end = s.endsAt {
            return "focusing · until \(clock(end))"
        }
        if s.isPaused { return "paused · \(hms(s.phaseRemaining)) left" }
        if s.isBreak, let end = s.focusUntil { return "break · until \(clock(end))" }
        if s.isWaiting { return s.onBreak ? "pomodoro · break up next" : "pomodoro · focus up next" }
        guard s.enabled else { return "schedules off" }
        guard let next = s.nextStartDate else { return "nothing scheduled" }
        let day = relativeDay(next)
        return day.isEmpty ? "ready · next at \(clock(next))" : "ready · \(day) at \(clock(next))"
    }

    // MARK: active

    private var activeBody: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if let end = s.endsAt {
                        Text(hms(max(0, Int(end.timeIntervalSince(s.now)))))
                            .font(.ui(38, .light))
                            .monospacedDigit()
                            .tracking(-1.4)
                    }
                    Text(s.isManual ? "until \(s.endsAt.map(clock) ?? "") · \(pomoLabel ?? "manual")" : "until \(s.endsAt.map(clock) ?? "")")
                        .font(.ui(10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if s.locked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 8.5, weight: .medium))
                        Text("locked").font(.ui(10, .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                } else if s.isManual || s.isPaused {
                    timerControls
                        .padding(.top, 4)
                }
            }

            if let progress = s.progress {
                ThinProgress(value: progress)
            }

            if s.isManual, !s.locked {
                HStack(spacing: 6) {
                    Text("extend")
                        .font(.ui(10))
                        .foregroundStyle(.secondary)
                    ForEach(s.presets, id: \.self) { minutes in
                        Button("+\(minutes) min") { s.startFocus(minutes) }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
            }
        }
    }

    /// "round 2 of 4" while a pomodoro run is going; counts the round in progress or just finished.
    private var pomoLabel: String? {
        guard let done = s.pomoRound else { return nil }
        let round = s.onBreak ? done : done + 1
        return s.pomoGoal > 0 ? "round \(round) of \(s.pomoGoal)" : "round \(round)"
    }

    private var timerControls: some View {
        HStack(spacing: 6) {
            if s.isWaiting {
                Button("Start") { s.nextPhase() }
                    .buttonStyle(SoftButtonStyle(kind: .strong))
            } else if s.isPaused {
                Button("Resume") { s.resumeFocus() }
            } else {
                Button("Pause") { s.pauseFocus() }
            }
            if s.onBreak {
                Button("Skip") { s.skipBreak() }
                    .help("Skip the break and start focusing")
            }
            Button("Reset") { s.stopFocus() }
        }
        .buttonStyle(SoftButtonStyle())
    }

    // MARK: paused / break / between rounds

    private var timerBody: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hms(s.phaseRemaining))
                        .font(.ui(38, .light))
                        .monospacedDigit()
                        .tracking(-1.4)
                        .foregroundStyle(s.isBreak ? .primary : .secondary)
                    Text(timerCaption)
                        .font(.ui(10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                timerControls
                    .padding(.top, 4)
            }
            if !s.isWaiting, let progress = s.phaseProgress {
                ThinProgress(value: progress)
                    .opacity(s.isPaused ? 0.5 : 1)
            }
        }
    }

    private var timerCaption: String {
        let kind = s.onBreak ? "break" : (pomoLabel ?? "manual")
        if s.isWaiting { return s.onBreak ? "\(pomoLabel ?? "") done · break up next" : "\(pomoLabel ?? "") up next" }
        if s.isPaused { return "paused · \(kind)" }
        return "until \(s.focusUntil.map(clock) ?? "") · \(pomoLabel.map { "break after \($0)" } ?? "break")"
    }

    // MARK: idle

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("make room to think.")
                    .font(.ui(23, .light))
                    .tracking(-0.5)
                Text("only what you allow gets through.")
                    .font(.ui(10.5))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(s.presets.indices, id: \.self) { index in
                    PanelPresetButton(minutes: s.presets[index]) {
                        withAnimation(.easeOut(duration: 0.2)) { s.startFocus(s.presets[index]) }
                    }
                    if index < s.presets.count - 1 {
                        Rectangle()
                            .fill(.primary.opacity(0.075))
                            .frame(width: 1, height: 17)
                    }
                }
            }
            .padding(3)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape
                    .fill(Ink.glassFill(scheme))
                    .overlay(shape.strokeBorder(Ink.glassEdge(scheme), lineWidth: 0.8))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.05), radius: 10, y: 4)
            }

            HStack(spacing: 8) {
                Text("pomodoro")
                    .font(.ui(10.5))
                    .foregroundStyle(.secondary)
                Text("\(s.pomoFocus) / \(s.pomoShort) min" + (s.pomoGoal > 0 ? " · ×\(s.pomoGoal)" : ""))
                    .font(.code(9.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Start") {
                    withAnimation(.easeOut(duration: 0.2)) { s.startPomodoro() }
                }
                .buttonStyle(SoftButtonStyle())
            }
        }
    }

    // MARK: stats

    private var statsRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("focused today").foregroundStyle(.secondary)
                Text(duration(s.focusSeconds)).foregroundStyle(.primary).fontWeight(.medium)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(s.blocked)").foregroundStyle(.primary).fontWeight(.medium).monospacedDigit()
                Text("blocked").foregroundStyle(.secondary)
            }
        }
        .font(.ui(10.5))
    }

    // MARK: alerts

    @ViewBuilder private var alerts: some View {
        if let available = u.available {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Version \(available.version) is available")
                        .font(.ui(10.5, .medium))
                    Text(u.busy ? (u.status ?? "Installing…") : "Ready when you are.")
                        .font(.ui(9.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Install") { Task { await u.install() } }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(s.locked || u.busy)
                    .opacity(s.locked || u.busy ? 0.45 : 1)
            }
            .padding(11)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.primary.opacity(scheme == .dark ? 0.05 : 0.035))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 0.7))
            }
        }

        if let error = s.browserError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Ink.amber)
                    .padding(.top, 1)
                Text(error)
                    .font(.ui(9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Ink.amber.opacity(scheme == .dark ? 0.12 : 0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Ink.amber.opacity(0.16), lineWidth: 0.7))
            }
        }
    }

    // MARK: schedules

    @ViewBuilder private var schedules: some View {
        if s.enabled, !s.schedules.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "schedules", note: "\(s.schedules.count)")
                if s.schedules.count > 3 {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 7) { scheduleLines }
                    }
                    .frame(maxHeight: 88)
                    .scrollIndicators(.hidden)
                } else {
                    VStack(alignment: .leading, spacing: 7) { scheduleLines }
                }
            }
        }
    }

    private var scheduleLines: some View {
        ForEach(s.schedules) { schedule in
            HStack(spacing: 8) {
                StatusDot(active: schedule == s.activeSchedule)
                Text(daysLabel(schedule.days))
                    .font(.ui(11))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(hhmm(schedule.start)) – \(hhmm(schedule.end))")
                    .font(.code(9.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            DottedLine()
            HStack(spacing: 6) {
                QuietButton(title: "Settings…", icon: "gearshape", shortcut: ",") {
                    SettingsWindowController.shared.show(store: s, updater: u)
                }
                .help("Open settings (⌘,)")

                Spacer()

                if s.locked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill").font(.system(size: 8.5))
                        Text("strict mode").font(.ui(10, .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                } else {
                    QuietButton(title: "Quit", icon: "power", shortcut: "q") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}

struct PanelPresetButton: View {
    let minutes: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text("\(minutes) min")
                .font(.ui(11.5, .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.primary.opacity(hover ? 0.045 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hover = hovering }
        }
    }
}

// MARK: - Settings window

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, schedules, apps, sites

    var id: String { rawValue }
    var title: String { rawValue }
    var index: Int { Self.allCases.firstIndex(of: self)! + 1 }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .schedules: "calendar"
        case .apps: "square.grid.2x2"
        case .sites: "globe"
        }
    }

    var blurb: String {
        switch self {
        case .general: "How Deepwork starts, updates and locks itself."
        case .schedules: "Weekly focus blocks. Times are local."
        case .apps: "Which apps stay open while a block runs."
        case .sites: "Domains your browsers are allowed to show."
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var s: Store
    @State private var tab: SettingsTab = .general
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(.primary.opacity(0.07))
                .frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    detailHeader
                    if s.locked { strictBanner }
                    tabContent
                        .disabled(s.locked)
                        .opacity(s.locked ? 0.62 : 1)
                    footer
                }
                .padding(.horizontal, 34)
                .padding(.top, 46)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .mask(LinearGradient(stops: [.init(color: .white, location: 0),
                                         .init(color: .white, location: 0.93),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .frame(width: 860)
        .frame(maxHeight: .infinity)
        .onAppear {
            // Don't hand the first text field focus and a selected range on open.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .background {
            PaperBackdrop(kind: .window)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: scheme == .dark
                    ? [.white.opacity(0.15), .white.opacity(0.03), .white.opacity(0.08)]
                    : [.white.opacity(0.92), .white.opacity(0.35), .white.opacity(0.7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .general: GeneralTab()
        case .schedules: SchedulesTab()
        case .apps: AppsTab()
        case .sites: SitesTab()
        }
    }

    // MARK: rail

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                CloudMark(size: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text("deepwork")
                        .font(.ui(14.5, .semibold))
                        .tracking(-0.1)
                    Text("settings")
                        .font(.ui(9.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 46)

            VStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { item in
                    SettingsNavRow(
                        tab: item,
                        selected: tab == item,
                        badge: badge(for: item)
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) { tab = item }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 32)

            Spacer(minLength: 20)

            railStatus
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 216)
        .frame(maxHeight: .infinity)
    }

    private func badge(for item: SettingsTab) -> String? {
        switch item {
        case .general: nil
        case .schedules: "\(s.schedules.count)"
        case .apps: "\(s.appList.count)"
        case .sites: "\(s.domainList.count)"
        }
    }

    private var railStatus: some View {
        GlassSurface(corner: 14, padding: 13) {
            // Inside the surface: GlassSurface holds a closure, so a TimelineView around it wouldn't redraw this.
            TimelineView(.periodic(from: .now, by: 1)) { _ in railStatusBody }
        }
    }

    private var railStatusBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                StatusDot(active: s.isActive)
                Text(s.isActive ? "in focus" : "status")
                    .font(.ui(10, .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if s.locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if s.isActive, let end = s.endsAt {
                Text(hms(max(0, Int(end.timeIntervalSince(s.now)))))
                    .font(.ui(28, .light))
                    .monospacedDigit()
                    .tracking(-0.9)
                if let progress = s.progress {
                    ThinProgress(value: progress)
                }
                Text("until \(clock(end))")
                    .font(.code(9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if s.isPaused || s.isBreak || s.isWaiting {
                Text(hms(s.phaseRemaining))
                    .font(.ui(28, .light))
                    .monospacedDigit()
                    .tracking(-0.9)
                    .foregroundStyle(.secondary)
                Text(s.isPaused ? "paused" : s.isBreak ? "break" : "up next")
                    .font(.code(9))
                    .foregroundStyle(.secondary)
            } else {
                Text("idle")
                    .font(.ui(24, .light))
                Text(idleStatus)
                    .font(.ui(9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
    }
    }

    private var idleStatus: String {
        guard s.enabled else { return "schedules paused" }
        guard let next = s.nextStartDate else { return "nothing scheduled" }
        let day = relativeDay(next)
        return day.isEmpty ? "next at \(clock(next))" : "next \(day) at \(clock(next))"
    }

    // MARK: detail

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tab.title)
                    .font(.ui(26, .light))
                    .tracking(-0.6)
                Text(tab.blurb)
                    .font(.ui(11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            ASCIIField(size: 6.1, cols: 52, rows: 17, opacity: 0.9)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .white, location: 0.12),
                                             .init(color: .white, location: 0.90),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                .mask(LinearGradient(stops: [.init(color: .white, location: 0),
                                             .init(color: .white, location: 0.88),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 240, height: 138, alignment: .trailing)
                .allowsHitTesting(false)
        }
        .frame(minHeight: 132)
    }

    private var strictBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Ink.amber)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Strict mode")
                    .font(.ui(10.5, .medium))
                Text("Settings stay locked until this focus block ends\(s.endsAt.map { " at \(clock($0))" } ?? "").")
                    .font(.ui(10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Ink.amber.opacity(scheme == .dark ? 0.11 : 0.08))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Ink.amber.opacity(0.18), lineWidth: 0.8))
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text("Settings stay on this Mac.")
                .font(.ui(9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Text("v\(appVersion)")
                .font(.code(8.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
    }
}

struct SettingsNavRow: View {
    let tab: SettingsTab
    let selected: Bool
    let badge: String?
    let action: () -> Void
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .regular))
                    .frame(width: 15)
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Text(tab.title)
                    .font(.ui(12.5, selected ? .medium : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Spacer(minLength: 6)
                if let badge {
                    Text(badge)
                        .font(.code(9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if selected || hover {
                    let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                    shape
                        .fill(selected
                              ? AnyShapeStyle(scheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.62))
                              : AnyShapeStyle(.primary.opacity(0.03)))
                        .overlay(shape.strokeBorder(selected ? AnyShapeStyle(Ink.glassEdge(scheme)) : AnyShapeStyle(.clear), lineWidth: 0.8))
                        .shadow(color: .black.opacity(selected ? (scheme == .dark ? 0.18 : 0.05) : 0), radius: 6, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(tab.index)")), modifiers: .command)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hover = hovering }
        }
    }
}

// MARK: - Settings building blocks

struct SettingsSection<Content: View>: View {
    var title: String
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: title, note: note)
                .padding(.bottom, 2)
            content()
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    var title: String
    var note: String? = nil
    var divider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.ui(12.5, .medium))
                    if let note {
                        Text(note)
                            .font(.ui(10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.vertical, 13)
            if divider { DottedLine() }
        }
    }
}

struct TimeField: View {
    let label: String
    @Binding var minutes: Int

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.ui(9.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.tertiary)
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.code(11))
                    .focused($focused)
                    .onSubmit(commit)
            }
            .padding(.horizontal, 9)
            .frame(width: 96, height: 28)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                shape
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55))
                    .overlay(shape.strokeBorder(focused ? AnyShapeStyle(.primary.opacity(0.18))
                                                        : AnyShapeStyle(.primary.opacity(0.08)), lineWidth: 0.8))
            }
        }
        .onAppear { text = display }
        .onChange(of: minutes) { _, _ in if !focused { text = display } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private var display: String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: ":")
        if parts.count == 2,
           let hour = Int(parts[0]), let minute = Int(parts[1]),
           (0...23).contains(hour), (0...59).contains(minute) {
            minutes = hour * 60 + minute
        }
        text = display
    }
}

struct AddBlockButton: View {
    let action: () -> Void
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9.5, weight: .medium))
                Text("Add block")
                    .font(.ui(11.5, .medium))
            }
            .foregroundStyle(hover ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(hover ? 0.035 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(hover ? 0.18 : 0.12),
                                      style: StrokeStyle(lineWidth: 0.8, dash: [4, 4])))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hover = hovering }
        }
    }
}

// MARK: - Tabs

struct GeneralTab: View {
    @EnvironmentObject var s: Store
    @EnvironmentObject var u: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SettingsSection(title: "Startup") {
                SettingsRow(title: "Launch at login",
                            note: "Open Deepwork quietly when you sign in.",
                            divider: s.loginError != nil) {
                    SoftSwitch(isOn: $s.launchAtLogin)
                        .accessibilityLabel("Launch at login")
                }
                if let error = s.loginError {
                    SettingsRow(title: "Login item error", note: error, divider: false) {
                        EmptyView()
                    }
                }
            }

            SettingsSection(title: "Updates", note: "github releases") {
                SettingsRow(title: "Check automatically",
                            note: "Look for a new version every few hours.") {
                    SoftSwitch(isOn: $u.auto)
                        .accessibilityLabel("Check for updates automatically")
                }
                SettingsRow(title: "Installed version", note: updateNote, divider: false) {
                    HStack(spacing: 8) {
                        Text("v\(appVersion)")
                            .font(.code(10))
                            .foregroundStyle(.secondary)
                        if let available = u.available {
                            Button("Install \(available.version)") {
                                Task { await u.install() }
                            }
                            .buttonStyle(SoftButtonStyle(kind: .strong))
                            .disabled(u.busy)
                        } else {
                            Button(u.busy ? "Checking…" : "Check now") {
                                Task { await u.check() }
                            }
                            .buttonStyle(SoftButtonStyle())
                            .disabled(u.busy)
                        }
                    }
                }
            }

            SettingsSection(title: "Focus") {
                SettingsRow(title: "Strict mode",
                            note: "While focusing, settings, stopping and quitting stay locked.") {
                    SoftSwitch(isOn: $s.strict)
                        .accessibilityLabel("Strict mode")
                }
                SettingsRow(title: "Notifications",
                            note: "A note when a focus block starts and ends.",
                            divider: false) {
                    SoftSwitch(isOn: $s.notify)
                        .accessibilityLabel("Notifications")
                }
            }

            SettingsSection(title: "Blocking") {
                SettingsRow(title: "Blocked apps",
                            note: "Quit them, or just hide them.") {
                    SoftSegmented(selection: $s.appAction,
                                  options: [(.quit, "Quit"), (.hide, "Hide")])
                        .frame(width: 136)
                }
                SettingsRow(title: "Blocked sites",
                            note: "Show a block page or close the tab.") {
                    SoftSegmented(selection: $s.siteAction,
                                  options: [(.page, "Page"), (.close, "Close")])
                        .frame(width: 136)
                }
                SettingsRow(title: "Spare agent browsers",
                            note: "Leave browsers marked “controlled by automated test software” alone, so AI agents and tests keep working.",
                            divider: false) {
                    SoftSwitch(isOn: $s.spareAgents)
                        .accessibilityLabel("Spare agent browsers")
                }
            }

            SettingsSection(title: "Quick focus", note: "shown in this order") {
                ForEach(s.presets.indices, id: \.self) { index in
                    SettingsRow(title: "Preset \(index + 1)",
                                note: index == 0 ? "The durations in the menu bar, left to right." : nil,
                                divider: index < s.presets.count - 1) {
                        SoftStepper(value: $s.presets[index], range: 5...240, step: 5)
                    }
                }
            }

            SettingsSection(title: "Pomodoro", note: "minutes") {
                SettingsRow(title: "Focus", note: "One round of blocking.") {
                    SoftStepper(value: $s.pomoFocus, range: 5...180, step: 5)
                }
                SettingsRow(title: "Short break", note: "Between rounds. Nothing is blocked.") {
                    SoftStepper(value: $s.pomoShort, range: 1...60, step: 1)
                }
                SettingsRow(title: "Long break", note: "Instead of a short one, every few rounds.") {
                    SoftStepper(value: $s.pomoLong, range: 5...90, step: 5)
                }
                SettingsRow(title: "Long break every", note: "Rounds between long breaks.") {
                    SoftStepper(value: $s.pomoEvery, range: 1...12, step: 1)
                }
                SettingsRow(title: "Rounds", note: s.pomoGoal == 0 ? "Keeps going until you reset." : "The run ends after this many rounds. 0 = no limit.") {
                    SoftStepper(value: $s.pomoGoal, range: 0...16, step: 1)
                }
                SettingsRow(title: "Start breaks automatically", note: "Otherwise wait for Start in the menu bar.") {
                    SoftSwitch(isOn: $s.pomoAutoBreak)
                        .accessibilityLabel("Start breaks automatically")
                }
                SettingsRow(title: "Start rounds automatically", note: "Begin the next focus round when a break ends.") {
                    SoftSwitch(isOn: $s.pomoAutoFocus)
                        .accessibilityLabel("Start rounds automatically")
                }
                SettingsRow(title: "Notifications", note: "A note when a round or break starts and ends.", divider: false) {
                    SoftSwitch(isOn: $s.pomoNotify)
                        .accessibilityLabel("Pomodoro notifications")
                }
            }
        }
    }

    private var updateNote: String {
        if let available = u.available {
            return "Version \(available.version) is ready."
        }
        if let status = u.status { return status }
        return "Checks quietly in the background."
    }
}

struct SchedulesTab: View {
    @EnvironmentObject var s: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "Schedules") {
                SettingsRow(title: "Enable schedules",
                            note: "Blocks start and end on their own.",
                            divider: false) {
                    SoftSwitch(isOn: $s.enabled)
                        .accessibilityLabel("Enable schedules")
                }
            }

            ForEach($s.schedules) { $schedule in
                ScheduleCard(schedule: $schedule) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        s.schedules.removeAll { $0.id == schedule.id }
                    }
                }
            }

            AddBlockButton {
                withAnimation(.easeOut(duration: 0.2)) {
                    s.schedules.append(Schedule())
                }
            }

            Text("A block that ends before it starts runs past midnight.")
                .font(.ui(9.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 3)
        }
    }
}

struct ScheduleCard: View {
    @Binding var schedule: Schedule
    let remove: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassSurface(corner: 14, padding: 15) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Text("Focus block")
                        .font(.ui(12, .medium))
                    Text(schedule.start >= schedule.end ? "overnight" : "same day")
                        .font(.ui(9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    RemoveButton(action: remove)
                }

                WeekdayPicker(days: $schedule.days)

                DottedLine()

                HStack(alignment: .top, spacing: 14) {
                    TimeField(label: "Start", minutes: $schedule.start)
                    Text("to")
                        .font(.ui(10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20)
                    TimeField(label: "End", minutes: $schedule.end)
                    Spacer()
                    if schedule.start >= schedule.end {
                        Text("ends \(hhmm(schedule.end)) next day")
                            .font(.ui(9.5))
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                }
            }
        }
    }
}

struct AppsTab: View {
    @EnvironmentObject var s: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Mode") {
                VStack(alignment: .leading, spacing: 8) {
                    SoftSegmented(selection: $s.appMode,
                                  options: [(.allow, "Allow only listed"), (.block, "Block listed")])
                        .frame(width: 282)
                    Text(s.appMode == .allow
                         ? "Everything else is hidden while focusing."
                         : "Everything else stays open while focusing.")
                        .font(.ui(10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            SettingsSection(title: s.appMode == .allow ? "Allowed apps" : "Blocked apps",
                            note: "\(s.appList.count)") {
                VStack(spacing: 0) {
                    if s.appList.isEmpty {
                        Text("No apps listed yet.")
                            .font(.ui(11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                    } else {
                        ForEach(s.appList, id: \.self) { id in
                            AppListRow(id: id, divider: id != s.appList.last) {
                                s.appList.removeAll { $0 == id }
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        s.addApps()
                    } label: {
                        Label("Choose apps…", systemImage: "plus")
                    }
                    .buttonStyle(SoftButtonStyle())

                    RunningAppMenu()

                    Spacer()
                }
                .padding(.top, 10)

                Text(s.appMode == .allow
                     ? "Finder and System Settings are always allowed. Browsers left off the list are blocked too."
                     : "Everything else is allowed. Finder and System Settings are never blocked.")
                    .font(.ui(9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }
}

struct AppListRow: View {
    let id: String
    var divider: Bool
    let remove: () -> Void
    @State private var hover = false

    private var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    private var name: String {
        url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .saturation(hover ? 1 : 0.65)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.ui(12, .medium))
                        .lineLimit(1)
                    if name != id {
                        Text(id)
                            .font(.code(8.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                RemoveButton(action: remove)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, hover ? 7 : 0)
            .background {
                if hover {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.primary.opacity(0.03))
                }
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { hover = hovering }
            }
            if divider { DottedLine() }
        }
    }
}

struct RunningAppMenu: View {
    @EnvironmentObject var s: Store
    @Environment(\.colorScheme) private var scheme
    @State private var running: [NSRunningApplication] = []

    private var apps: [NSRunningApplication] {
        running.filter {
            $0.activationPolicy == .regular
                && !s.appList.contains($0.bundleIdentifier ?? "")
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 9, weight: .medium))
                Text("Add running app…").font(.ui(11, .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                shape
                    .fill(scheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.56))
                    .overlay(shape.strokeBorder(Ink.glassEdge(scheme), lineWidth: 0.8))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.05), radius: 5, y: 2)
            }

            Menu {
                ForEach(apps, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? "?") {
                        if let id = app.bundleIdentifier { s.appList.append(id) }
                    }
                }
            } label: {
                Color.clear
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 156, height: 28)
            .accessibilityLabel("Add a running app")
        }
        .frame(height: 28)
        .onReceive(NSWorkspace.shared.publisher(for: \.runningApplications)) { running = $0 }
    }
}

struct SitesTab: View {
    @EnvironmentObject var s: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Mode") {
                VStack(alignment: .leading, spacing: 8) {
                    SoftSegmented(selection: $s.siteMode,
                                  options: [(.allow, "Allow only listed"), (.block, "Block listed")])
                        .frame(width: 282)
                    Text(s.siteMode == .allow
                         ? "Only these domains open in your browsers during focus."
                         : "These domains are closed or replaced during focus.")
                        .font(.ui(10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            SettingsSection(title: s.siteMode == .allow ? "Allowed sites" : "Blocked sites",
                            note: "\(s.domainList.count)") {
                EntryList(items: $s.domainList, icon: "globe", empty: "No domains listed yet.")

                SoftField(text: $newDomain, prompt: "example.com") {
                    s.addDomain(newDomain)
                }
                .padding(.top, 10)

                HStack(spacing: 8) {
                    Button {
                        s.addCurrentSite()
                    } label: {
                        Label("Add site open in browser", systemImage: "plus")
                    }
                    .buttonStyle(SoftButtonStyle())
                    Spacer()
                }
                .padding(.top, 10)

                Text("Subdomains are included. Browser pages like a new tab stay available. Works in Safari, Chrome, Arc, Dia, Edge, Brave, Vivaldi, Opera and Orion. Firefox can't be filtered, so block it under Apps.")
                    .font(.ui(9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            SettingsSection(title: "Always allowed pages", note: "\(s.allowedPaths.count)") {
                EntryList(items: $s.allowedPaths, icon: "link", empty: "No pages listed yet.")

                SoftField(text: $newPath, prompt: "github.com/you") {
                    s.addPath(newPath)
                }
                .padding(.top, 10)

                Text("Open in either mode, even on a blocked domain. Covers everything under the path, so github.com/you also allows github.com/you/repo. Add a query to pin one page, like youtube.com/watch?v=….")
                    .font(.ui(9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    @State private var newDomain = ""
    @State private var newPath = ""
}

/// Rows of removable entries, as in the site lists.
struct EntryList: View {
    @Binding var items: [String]
    var icon: String
    var empty: String

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text(empty)
                    .font(.ui(11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                ForEach(items, id: \.self) { item in
                    VStack(spacing: 0) {
                        HStack(spacing: 9) {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.tertiary)
                                .frame(width: 15)
                            Text(item)
                                .font(.code(11.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            RemoveButton { items.removeAll { $0 == item } }
                        }
                        .padding(.vertical, 9)
                        if item != items.last { DottedLine() }
                    }
                }
            }
        }
    }
}

// MARK: - App

@main
struct DeepworkApp: App {
    @StateObject private var store = Store()
    @StateObject private var updater = Updater()

    init() { if CommandLine.arguments.contains("--selftest") { selfTest(); exit(0) } }

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store).environmentObject(updater)
        } label: {
            Image(systemName: store.isActive ? "cloud.fill" : "cloud")
        }
        .menuBarExtraStyle(.window)
    }
}
