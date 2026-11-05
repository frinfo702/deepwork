import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications

let diaID = "company.thebrowser.dia"
let alwaysAllowed: Set<String> = ["com.apple.finder", "com.apple.systempreferences"]
let weekOrder = [2, 3, 4, 5, 6, 7, 1] // Calendar weekday, Monday first
let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// MARK: - Model / pure logic

struct Schedule: Codable, Identifiable, Hashable {
    var id = UUID()
    var start = 9 * 60
    var end = 18 * 60
    var days: Set<Int> = [2, 3, 4, 5, 6]

    /// `days` refers to the day the block starts; start >= end means it runs past midnight.
    func contains(weekday w: Int, minute m: Int) -> Bool {
        if start < end { return days.contains(w) && m >= start && m < end }
        let prev = w == 1 ? 7 : w - 1
        return (days.contains(w) && m >= start) || (days.contains(prev) && m < end)
    }
}

enum AppAction: String { case hide, quit }
enum SiteAction: String { case page, close }
/// allow = only listed items get through; block = only listed items are blocked.
enum ListMode: String { case allow, block }

func daysLabel(_ d: Set<Int>) -> String {
    switch d {
    case Set(1...7): "Every day"
    case [2, 3, 4, 5, 6]: "Weekdays"
    case [1, 7]: "Weekends"
    case []: "No days"
    default: weekOrder.filter(d.contains).map { dayNames[$0] }.joined(separator: ", ")
    }
}

func nextStart(_ ss: [Schedule], after date: Date, cal: Calendar = .current) -> Date? {
    let day0 = cal.startOfDay(for: date)
    for offset in 0...7 {
        let day = cal.date(byAdding: .day, value: offset, to: day0)!
        let w = cal.component(.weekday, from: day)
        if let d = ss.filter({ $0.days.contains(w) })
            .map({ day.addingTimeInterval(TimeInterval($0.start * 60)) })
            .filter({ $0 > date }).min() { return d }
    }
    return nil
}

func isAllowed(_ urlString: String, _ domains: [String], _ mode: ListMode = .allow) -> Bool {
    guard let u = URL(string: urlString), let scheme = u.scheme?.lowercased(),
          scheme == "http" || scheme == "https", let host = u.host?.lowercased() else { return true } // dia://, about:, data: etc.
    return domains.contains { host == $0 || host.hasSuffix("." + $0) } == (mode == .allow)
}

func isAppBlocked(_ id: String, _ list: [String], _ mode: ListMode) -> Bool {
    !alwaysAllowed.contains(id) && list.contains(id) != (mode == .allow)
}

func normalizeDomain(_ s: String) -> String {
    var d = s.trimmingCharacters(in: .whitespaces).lowercased()
    if let h = URL(string: d.contains("://") ? d : "https://" + d)?.host { d = h }
    return d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
}

func hhmm(_ m: Int) -> String { String(format: "%d:%02d", m / 60, m % 60) }
func clock(_ d: Date) -> String { let c = Calendar.current.dateComponents([.hour, .minute], from: d); return hhmm(c.hour! * 60 + c.minute!) }
func duration(_ sec: Int) -> String { sec >= 3600 ? "\(sec / 3600)h \(sec % 3600 / 60)m" : "\(sec / 60)m" }

func selfTest() {
    assert(Schedule().contains(weekday: 2, minute: 600))
    assert(!Schedule().contains(weekday: 1, minute: 600))
    let night = Schedule(start: 22 * 60, end: 2 * 60, days: [6]) // Fri 22:00 -> Sat 2:00
    assert(night.contains(weekday: 6, minute: 23 * 60)); assert(night.contains(weekday: 7, minute: 60))
    assert(!night.contains(weekday: 6, minute: 60)); assert(!night.contains(weekday: 7, minute: 23 * 60))
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let mon0800 = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8))!
    let sat = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 8))!
    assert(nextStart([Schedule()], after: mon0800, cal: cal) == mon0800.addingTimeInterval(3600))
    assert(nextStart([Schedule()], after: sat, cal: cal) == cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9)))
    assert(daysLabel([2, 3, 4, 5, 6]) == "Weekdays"); assert(daysLabel([2, 4]) == "Mon, Wed")
    assert(isAllowed("https://docs.github.com/x", ["github.com"]))
    assert(!isAllowed("https://notgithub.com", ["github.com"]))
    assert(isAllowed("dia://newtab", []))
    assert(!isAllowed("https://www.youtube.com", ["youtube.com"], .block)); assert(isAllowed("https://github.com", ["youtube.com"], .block))
    assert(isAllowed("dia://newtab", ["youtube.com"], .block))
    assert(isAppBlocked("x", [], .allow)); assert(!isAppBlocked("x", ["x"], .allow))
    assert(isAppBlocked("x", ["x"], .block)); assert(!isAppBlocked("y", ["x"], .block)); assert(!isAppBlocked("com.apple.finder", ["com.apple.finder"], .block))
    assert(normalizeDomain(" https://www.GitHub.com/foo ") == "github.com")
    assert(isNewer("0.10.0", than: "0.9.1")); assert(!isNewer("0.3.0", than: "0.3.0")); assert(!isNewer("0.2.9", than: "0.3.0"))
    print("selftest ok")
}

let blockedURL = "data:text/html;charset=utf-8," + """
<html><head><title>Blocked by Deepwork</title></head><body style="margin:0;height:100vh;display:grid;place-items:center;font:600 22px -apple-system;\
background:linear-gradient(#1e1b4b,#0f172a);color:#cbd5e1"><div style="text-align:center"><div style="font-size:64px">☁️</div>\
Focus time<div style="font-size:14px;font-weight:400;opacity:.6;margin-top:8px">This site is blocked during focus time</div></div></body></html>
""".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

// MARK: - Store + enforcement

@MainActor final class Store: ObservableObject {
    private let ud = UserDefaults.standard
    private var cal: Calendar { .current }

    @Published var enabled: Bool { didSet { ud.set(enabled, forKey: "enabled") } }
    @Published var schedules: [Schedule] { didSet { ud.set(try? JSONEncoder().encode(schedules), forKey: "schedules") } }
    @Published var apps: [String] { didSet { ud.set(apps, forKey: "apps") } }
    @Published var domains: [String] { didSet { ud.set(domains, forKey: "domains") } }
    @Published var blockedApps: [String] { didSet { ud.set(blockedApps, forKey: "blockedApps") } }
    @Published var blockedDomains: [String] { didSet { ud.set(blockedDomains, forKey: "blockedDomains") } }
    @Published var appMode: ListMode { didSet { ud.set(appMode.rawValue, forKey: "appMode") } }
    @Published var siteMode: ListMode { didSet { ud.set(siteMode.rawValue, forKey: "siteMode") } }
    @Published var strict: Bool { didSet { ud.set(strict, forKey: "strict") } }
    @Published var notify: Bool {
        didSet {
            ud.set(notify, forKey: "notify")
            if notify { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        }
    }
    @Published var appAction: AppAction { didSet { ud.set(appAction.rawValue, forKey: "appAction") } }
    @Published var siteAction: SiteAction { didSet { ud.set(siteAction.rawValue, forKey: "siteAction") } }
    @Published var presets: [Int] { didSet { ud.set(presets, forKey: "presets") } }
    @Published private(set) var focusUntil: Date? { didSet { ud.set(focusUntil?.timeIntervalSince1970, forKey: "focusUntil") } }
    @Published private(set) var focusSeconds: Int { didSet { ud.set(focusSeconds, forKey: "focusSeconds") } }
    @Published private(set) var blocked: Int { didSet { ud.set(blocked, forKey: "blocked") } }
    private var statsDay: Double { didSet { ud.set(statsDay, forKey: "statsDay") } }

    @Published private(set) var now = Date()
    @Published private(set) var diaError: String?
    @Published private(set) var loginError: String?

    private var timer: Timer?
    private var wasActive = false
    private var asked = Set<pid_t>() // apps already handled this session; quit is asked once so save dialogs survive
    private lazy var readDia = NSAppleScript(source: "tell application id \"\(diaID)\" to get URL of active tab of every window")

    init() {
        enabled = ud.object(forKey: "enabled") as? Bool ?? true
        schedules = (ud.data(forKey: "schedules")).flatMap { try? JSONDecoder().decode([Schedule].self, from: $0) } ?? [Schedule()]
        apps = ud.stringArray(forKey: "apps") ?? [diaID]
        domains = ud.stringArray(forKey: "domains") ?? ["github.com", "google.com"]
        blockedApps = ud.stringArray(forKey: "blockedApps") ?? []
        blockedDomains = ud.stringArray(forKey: "blockedDomains") ?? ["youtube.com", "x.com"]
        appMode = ListMode(rawValue: ud.string(forKey: "appMode") ?? "") ?? .allow
        siteMode = ListMode(rawValue: ud.string(forKey: "siteMode") ?? "") ?? .allow
        strict = ud.bool(forKey: "strict")
        notify = ud.bool(forKey: "notify")
        appAction = AppAction(rawValue: ud.string(forKey: "appAction") ?? "") ?? .quit
        siteAction = SiteAction(rawValue: ud.string(forKey: "siteAction") ?? "") ?? .page
        presets = ud.array(forKey: "presets") as? [Int] ?? [25, 50, 90]
        focusUntil = (ud.object(forKey: "focusUntil") as? Double).map(Date.init(timeIntervalSince1970:))
        focusSeconds = ud.integer(forKey: "focusSeconds")
        blocked = ud.integer(forKey: "blocked")
        statsDay = ud.double(forKey: "statsDay")

        if !ud.bool(forKey: "didFirstLaunch") {
            ud.set(true, forKey: "didFirstLaunch")
            launchAtLogin = true
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: state

    var minuteNow: Int { let c = cal.dateComponents([.hour, .minute], from: now); return c.hour! * 60 + c.minute! }
    var activeSchedule: Schedule? {
        guard enabled else { return nil }
        let w = cal.component(.weekday, from: now)
        return schedules.first { $0.contains(weekday: w, minute: minuteNow) }
    }
    var isManual: Bool { (focusUntil ?? .distantPast) > now }
    var isActive: Bool { isManual || activeSchedule != nil }
    var locked: Bool { strict && isActive }
    var nextStartDate: Date? { enabled ? nextStart(schedules, after: now) : nil }
    var endsAt: Date? {
        var ends: [Date] = []
        if isManual, let f = focusUntil { ends.append(f) }
        if let s = activeSchedule {
            var e = cal.startOfDay(for: now).addingTimeInterval(TimeInterval(s.end * 60))
            if e <= now { e += 86400 }
            ends.append(e)
        }
        return ends.max()
    }

    /// The list the current mode reads and edits; each mode keeps its own list.
    var appList: [String] {
        get { appMode == .allow ? apps : blockedApps }
        set { if appMode == .allow { apps = newValue } else { blockedApps = newValue } }
    }
    var domainList: [String] {
        get { siteMode == .allow ? domains : blockedDomains }
        set { if siteMode == .allow { domains = newValue } else { blockedDomains = newValue } }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch { loginError = error.localizedDescription }
            objectWillChange.send()
        }
    }

    // MARK: actions

    func startFocus(_ minutes: Int) { focusUntil = max(now, focusUntil ?? now).addingTimeInterval(TimeInterval(minutes * 60)) }
    func stopFocus() { if !locked { focusUntil = nil } }

    func addApps() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard p.runModal() == .OK else { return }
        for id in p.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier }) where !appList.contains(id) { appList.append(id) }
    }

    func addDomain(_ raw: String) {
        let d = normalizeDomain(raw)
        if !d.isEmpty, !domainList.contains(d) { domainList.append(d) }
    }

    func addCurrentDiaSite() {
        let r = NSAppleScript(source: "tell application id \"\(diaID)\" to get URL of active tab of front window")?.executeAndReturnError(nil)
        if let u = r?.stringValue, let h = URL(string: u)?.host { addDomain(h) }
    }

    // MARK: enforcement

    private func tick() {
        now = Date()
        let day = cal.startOfDay(for: now).timeIntervalSince1970
        if day != statsDay { statsDay = day; focusSeconds = 0; blocked = 0 }
        if let f = focusUntil, f <= now { focusUntil = nil }

        let active = isActive
        if active != wasActive {
            wasActive = active
            if active { post("Focus started", endsAt.map { "Stay focused until \(clock($0))." } ?? "") }
            else { asked.removeAll(); post("Focus ended", "Nice work. Time for a break.") }
        }
        guard active else { return }
        focusSeconds += 1 // ponytail: counts ticks, drifts slightly under load; store session start/end if exact totals matter

        let me = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != me, isAppBlocked(id, appList, appMode) else { continue }
            app.hide()
            if asked.insert(app.processIdentifier).inserted {
                blocked += 1
                if appAction == .quit { app.terminate() }
            }
        }
        if !isAppBlocked(diaID, appList, appMode), !NSRunningApplication.runningApplications(withBundleIdentifier: diaID).isEmpty { checkDia() }
    }

    private func checkDia() {
        var err: NSDictionary?
        guard let res = readDia?.executeAndReturnError(&err) else {
            diaError = (err?[NSAppleScript.errorNumber] as? Int) == -1743
                ? "Allow Deepwork to control Dia in System Settings › Privacy & Security › Automation"
                : err?[NSAppleScript.errorMessage] as? String
            return
        }
        diaError = nil
        let urls = res.numberOfItems == 0 ? [] : (1...res.numberOfItems).map { res.atIndex($0)?.stringValue ?? "" }
        for (i, u) in urls.enumerated().reversed() where !isAllowed(u, domainList, siteMode) {
            let cmd = siteAction == .close
                ? "close active tab of window \(i + 1)"
                : "set URL of active tab of window \(i + 1) to \"\(blockedURL)\""
            NSAppleScript(source: "tell application id \"\(diaID)\" to \(cmd)")?.executeAndReturnError(nil)
            blocked += 1
        }
    }

    private func post(_ title: String, _ body: String) {
        guard notify else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

func timeBinding(_ b: Binding<Int>) -> Binding<Date> {
    Binding(get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(b.wrappedValue * 60)) },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); b.wrappedValue = c.hour! * 60 + c.minute! })
}
