import SwiftUI
import AppKit

let accentGradient = LinearGradient(colors: [Color(red: 0.42, green: 0.60, blue: 1.0), Color(red: 0.40, green: 0.30, blue: 0.92)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - Menu bar panel

struct PanelView: View {
    @EnvironmentObject var s: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            focusCard
            HStack(spacing: 8) {
                Tile(icon: "timer", title: "今日の集中", value: duration(s.focusSeconds))
                Tile(icon: "hand.raised.fill", title: "ブロック", value: "\(s.blocked)回")
            }
            if s.enabled, !s.schedules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(s.schedules) { sch in
                        HStack(spacing: 6) {
                            Circle().fill(sch == s.activeSchedule ? Color.green : Color.secondary.opacity(0.3)).frame(width: 6, height: 6)
                            Text(daysLabel(sch.days))
                            Spacer()
                            Text("\(hhmm(sch.start)) – \(hhmm(sch.end))").monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            if let e = s.diaError {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            HStack {
                Button { openWindow(id: "settings"); NSApp.activate() } label: { Label("設定…", systemImage: "gearshape") }
                    .keyboardShortcut(",")
                Spacer()
                if !s.locked { Button("終了") { NSApp.terminate(nil) }.keyboardShortcut("q") }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(s.isActive ? AnyShapeStyle(accentGradient) : AnyShapeStyle(.quaternary))
                Image(systemName: s.isActive ? "cloud.fill" : "cloud").foregroundStyle(s.isActive ? .white : .secondary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Deepwork").font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if s.locked { Image(systemName: "lock.fill").foregroundStyle(.secondary).help("厳格モード: 集中中は変更できません") }
            Toggle("", isOn: $s.enabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
                .disabled(s.locked).help("スケジュールを有効にする")
        }
    }

    private var status: String {
        if s.isActive { return "集中中" + (s.endsAt.map { " · \(clock($0)) まで" } ?? "") }
        if let n = s.nextStartDate {
            let cal = Calendar.current
            let day = cal.isDateInToday(n) ? "" : cal.isDateInTomorrow(n) ? "明日 " : "\(dayNames[cal.component(.weekday, from: n)])曜 "
            return "次は \(day)\(clock(n)) から"
        }
        return s.enabled ? "待機中" : "スケジュールはオフ"
    }

    @ViewBuilder private var focusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if s.isActive, let end = s.endsAt {
                let left = max(0, Int(end.timeIntervalSince(s.now)))
                HStack(alignment: .firstTextBaseline) {
                    Text(left >= 3600 ? String(format: "%d:%02d:%02d", left / 3600, left % 3600 / 60, left % 60)
                                      : String(format: "%02d:%02d", left / 60, left % 60))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    if s.isManual, !s.locked { Button("停止") { s.stopFocus() }.controlSize(.small) }
                }
                Text(s.isManual ? "クイック集中 · \(clock(end)) に終了" : "スケジュール · \(clock(end)) に終了")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("今すぐ集中").font(.subheadline.weight(.semibold))
            }
            if !s.isActive || s.isManual {
                HStack(spacing: 6) {
                    ForEach(s.presets, id: \.self) { m in
                        Button { s.startFocus(m) } label: {
                            Text(s.isManual ? "+\(m)分" : "\(m)分").frame(maxWidth: .infinity)
                        }
                        .controlSize(.regular)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(s.isActive ? AnyShapeStyle(accentGradient.opacity(0.16)) : AnyShapeStyle(Color.primary.opacity(0.05))))
    }
}

struct Tile: View {
    let icon: String, title: String, value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @EnvironmentObject var s: Store
    var body: some View {
        VStack(spacing: 0) {
            if s.locked {
                Label("厳格モード中のため、集中タイムが終わるまで設定は変更できません", systemImage: "lock.fill")
                    .font(.callout).frame(maxWidth: .infinity).padding(8).background(.orange.opacity(0.15))
            }
            TabView {
                GeneralTab().tabItem { Label("一般", systemImage: "gearshape") }
                SchedulesTab().tabItem { Label("スケジュール", systemImage: "calendar") }
                AppsTab().tabItem { Label("アプリ", systemImage: "square.grid.2x2") }
                SitesTab().tabItem { Label("サイト", systemImage: "globe") }
            }
        }
        .frame(width: 500, height: 480)
    }
}

struct GeneralTab: View {
    @EnvironmentObject var s: Store
    var body: some View {
        Form {
            Section("起動") {
                Toggle("ログイン時に起動", isOn: $s.launchAtLogin)
                if let e = s.loginError { Text(e).font(.caption).foregroundStyle(.red) }
            }
            Section("集中タイム") {
                Toggle(isOn: $s.strict) {
                    Text("厳格モード")
                    Text("集中中は設定の変更・停止・アプリの終了ができなくなります")
                }
                Toggle("開始・終了を通知", isOn: $s.notify)
            }
            Section("ブロックの方法") {
                Picker("許可していないアプリ", selection: $s.appAction) {
                    Text("終了する").tag(AppAction.quit)
                    Text("隠すだけ").tag(AppAction.hide)
                }
                Picker("許可していないサイト (Dia)", selection: $s.siteAction) {
                    Text("ブロック画面を表示").tag(SiteAction.page)
                    Text("タブを閉じる").tag(SiteAction.close)
                }
            }
            Section("クイック集中の時間") {
                ForEach(s.presets.indices, id: \.self) { i in
                    Stepper("\(s.presets[i]) 分", value: $s.presets[i], in: 5...240, step: 5)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(s.locked)
    }
}

struct SchedulesTab: View {
    @EnvironmentObject var s: Store
    var body: some View {
        Form {
            Section { Toggle("スケジュールを有効にする", isOn: $s.enabled) }
            ForEach($s.schedules) { $sch in
                Section {
                    WeekdayPicker(days: $sch.days)
                    DatePicker("開始", selection: timeBinding($sch.start), displayedComponents: .hourAndMinute)
                    DatePicker("終了", selection: timeBinding($sch.end), displayedComponents: .hourAndMinute)
                    if sch.start >= sch.end { Text("日付をまたいで翌日 \(hhmm(sch.end)) まで").font(.caption).foregroundStyle(.secondary) }
                    Button("このスケジュールを削除", role: .destructive) { s.schedules.removeAll { $0.id == sch.id } }
                        .buttonStyle(.borderless)
                }
            }
            Section { Button { s.schedules.append(Schedule()) } label: { Label("スケジュールを追加", systemImage: "plus") } }
        }
        .formStyle(.grouped)
        .disabled(s.locked)
    }
}

struct WeekdayPicker: View {
    @Binding var days: Set<Int>
    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekOrder, id: \.self) { d in
                let on = days.contains(d)
                Button { if on { days.remove(d) } else { days.insert(d) } } label: {
                    Text(dayNames[d]).font(.callout.weight(.medium))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(on ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AppsTab: View {
    @EnvironmentObject var s: Store
    var body: some View {
        Form {
            Section {
                ForEach(s.apps, id: \.self) { id in AppRow(id: id) { s.apps.removeAll { $0 == id } } }
            } header: { Text("集中中に使えるアプリ") } footer: {
                Text("Finder とシステム設定は常に使えます。Dia を外すと、Dia 自体がブロックされます。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button { s.addApps() } label: { Label("アプリを選んで追加…", systemImage: "plus") }
                Menu("実行中のアプリから追加") {
                    ForEach(NSWorkspace.shared.runningApplications.filter {
                        $0.activationPolicy == .regular && !s.apps.contains($0.bundleIdentifier ?? "") && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                    }, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? "?") { if let id = app.bundleIdentifier { s.apps.append(id) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(s.locked)
    }
}

struct SitesTab: View {
    @EnvironmentObject var s: Store
    @State private var newDomain = ""
    var body: some View {
        Form {
            Section {
                ForEach(s.domains, id: \.self) { d in Row(icon: Image(systemName: "globe"), title: d) { s.domains.removeAll { $0 == d } } }
                TextField("ドメインを追加", text: $newDomain, prompt: Text("example.com"))
                    .onSubmit { s.addDomain(newDomain); newDomain = "" }
            } header: { Text("集中中に開けるサイト (Dia)") } footer: {
                Text("サブドメインも含めて許可されます。新しいタブなど Dia の内部ページは常に開けます。").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button { s.addCurrentDiaSite() } label: { Label("Dia で開いているサイトを追加", systemImage: "plus.circle") } }
        }
        .formStyle(.grouped)
        .disabled(s.locked)
    }
}

struct AppRow: View {
    let id: String
    let remove: () -> Void
    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        Row(icon: Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()),
            title: url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id,
            remove: remove)
    }
}

struct Row: View {
    let icon: Image
    let title: String
    let remove: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            icon.resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(.secondary)
            Text(title).lineLimit(1)
            Spacer()
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.tertiary).opacity(hover ? 1 : 0.35)
        }
        .onHover { hover = $0 }
    }
}

// MARK: - App

@main
struct DeepworkApp: App {
    @StateObject private var store = Store()
    init() { if CommandLine.arguments.contains("--selftest") { selfTest(); exit(0) } }
    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(store)
        } label: {
            Image(systemName: store.isActive ? "cloud.fill" : "cloud")
        }
        .menuBarExtraStyle(.window)

        Window("Deepwork 設定", id: "settings") {
            SettingsView().environmentObject(store)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
