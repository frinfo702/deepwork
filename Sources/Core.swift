import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import ScriptingBridge

let diaID = "company.thebrowser.dia"
/// Browsers whose tabs Deepwork can read over Apple Events, mapped to their dictionary's tab property.
/// Firefox has no tab scripting, so it can only be blocked as an app.
let browsers: [String: String] = [
    diaID: "activeTab",
    "company.thebrowser.Browser": "activeTab", // Arc
    "com.google.Chrome": "activeTab",
    "org.chromium.Chromium": "activeTab",
    "com.brave.Browser": "activeTab",
    "com.microsoft.edgemac": "activeTab",
    "com.vivaldi.Vivaldi": "activeTab",
    "com.operasoftware.Opera": "activeTab",
    "com.apple.Safari": "currentTab",
    "com.kagi.kagimacOS": "currentTab", // Orion
]
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

/// `paths` are always-allowed pages ("github.com/me", "youtube.com/watch?v=id") that win over the domain list in either mode.
func isAllowed(_ urlString: String, _ domains: [String], _ mode: ListMode = .allow, paths: [String] = []) -> Bool {
    guard let u = URL(string: urlString), let scheme = u.scheme?.lowercased(),
          scheme == "http" || scheme == "https", let host = u.host?.lowercased() else { return true } // chrome://, about:, data: etc.
    let onHost = { (d: String) in host == d || host.hasSuffix("." + d) }
    let target = u.path + (u.query.map { "?" + $0 } ?? "")
    for entry in paths {
        let slash = entry.firstIndex(of: "/") ?? entry.endIndex
        let prefix = String(entry[slash...])
        // A prefix only counts on a boundary, so "/me" covers "/me/repo" and "/me?tab=1" but not "/meow".
        guard onHost(String(entry[..<slash])), target.hasPrefix(prefix) else { continue }
        let next = target.dropFirst(prefix.count).first
        if next == nil || prefix.hasSuffix("/") || "/?&#".contains(next!) { return true }
    }
    return domains.contains(where: onHost) == (mode == .allow)
}

func isAppBlocked(_ id: String, _ list: [String], _ mode: ListMode) -> Bool {
    !alwaysAllowed.contains(id) && list.contains(id) != (mode == .allow)
}

func normalizeDomain(_ s: String) -> String {
    var d = s.trimmingCharacters(in: .whitespaces).lowercased()
    if let h = URL(string: d.contains("://") ? d : "https://" + d)?.host { d = h }
    return d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
}

/// "https://www.GitHub.com/me/" -> "github.com/me": host lowercased, path and query kept as typed.
func normalizePath(_ s: String) -> String {
    let raw = s.trimmingCharacters(in: .whitespaces)
    guard let u = URL(string: raw.contains("://") ? raw : "https://" + raw), let h = u.host else { return "" }
    let host = normalizeDomain(h)
    var rest = u.path + (u.query.map { "?" + $0 } ?? "")
    while rest.hasSuffix("/") { rest.removeLast() }
    return host + rest
}

/// Break minutes after `round` finished focus rounds, or nil when the run is complete (goal 0 = endless).
func pomoBreak(after round: Int, short: Int, long: Int, every: Int, goal: Int) -> Int? {
    if goal > 0, round >= goal { return nil }
    return round % max(every, 1) == 0 ? long : short
}

/// argv of a same-user process, read with sysctl(KERN_PROCARGS2).
func processArgs(_ pid: pid_t) -> [String] {
    var mib = [CTL_KERN, KERN_PROCARGS2, pid], size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
    let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
    // argc, exec path, NUL padding, then argv; empty argv entries are dropped (harmless for flag checks)
    let parts = buf[4..<size].split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
    return Array(parts.dropFirst().prefix(argc))
}

/// Puppeteer, Playwright and chrome-devtools-mcp start Chromium with this flag;
/// it's what shows "controlled by automated test software".
func isAgentBrowser(_ pid: pid_t) -> Bool { processArgs(pid).contains("--enable-automation") }

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
    assert(processArgs(getpid()) == CommandLine.arguments); assert(!isAgentBrowser(getpid()))
    assert(normalizeDomain(" https://www.GitHub.com/foo ") == "github.com")
    assert(normalizePath(" https://www.GitHub.com/Me/ ") == "github.com/Me"); assert(normalizePath("youtube.com/watch?v=x") == "youtube.com/watch?v=x")
    let yt = ["youtube.com"], ok = ["youtube.com/watch?v=abc", "github.com/me"]
    assert(isAllowed("https://www.youtube.com/watch?v=abc&t=9", yt, .block, paths: ok))
    assert(!isAllowed("https://www.youtube.com/watch?v=abcd", yt, .block, paths: ok))
    assert(!isAllowed("https://youtube.com/", yt, .block, paths: ok))
    assert(isAllowed("https://github.com/me/repo", [], .allow, paths: ok)); assert(isAllowed("https://github.com/me", [], .allow, paths: ok))
    assert(!isAllowed("https://github.com/meow", [], .allow, paths: ok)); assert(!isAllowed("https://github.com/", [], .allow, paths: ok))
    assert(isNewer("0.10.0", than: "0.9.1")); assert(!isNewer("0.3.0", than: "0.3.0")); assert(!isNewer("0.2.9", than: "0.3.0"))
    assert(pomoBreak(after: 1, short: 5, long: 15, every: 4, goal: 0) == 5)
    assert(pomoBreak(after: 4, short: 5, long: 15, every: 4, goal: 0) == 15)
    assert(pomoBreak(after: 8, short: 5, long: 15, every: 4, goal: 0) == 15)
    assert(pomoBreak(after: 3, short: 5, long: 15, every: 4, goal: 3) == nil)
    assert(pomoBreak(after: 2, short: 5, long: 15, every: 2, goal: 3) == 15)
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
    /// Pages allowed in both site modes, e.g. "github.com/me".
    @Published var allowedPaths: [String] { didSet { ud.set(allowedPaths, forKey: "allowedPaths") } }
    @Published var appMode: ListMode { didSet { ud.set(appMode.rawValue, forKey: "appMode") } }
    @Published var siteMode: ListMode { didSet { ud.set(siteMode.rawValue, forKey: "siteMode") } }
    @Published var strict: Bool { didSet { ud.set(strict, forKey: "strict") } }
    /// Leave browsers driven by automation tools (AI agents, tests) unrestricted.
    @Published var spareAgents: Bool { didSet { ud.set(spareAgents, forKey: "spareAgents") } }
    @Published var notify: Bool {
        didSet {
            ud.set(notify, forKey: "notify")
            if notify { requestNotifications() }
        }
    }
    /// Notifications for pomodoro phase changes; `notify` covers everything else.
    @Published var pomoNotify: Bool {
        didSet {
            ud.set(pomoNotify, forKey: "pomoNotify")
            if pomoNotify { requestNotifications() }
        }
    }
    @Published var appAction: AppAction { didSet { ud.set(appAction.rawValue, forKey: "appAction") } }
    @Published var siteAction: SiteAction { didSet { ud.set(siteAction.rawValue, forKey: "siteAction") } }
    @Published var presets: [Int] { didSet { ud.set(presets, forKey: "presets") } }
    @Published var pomoFocus: Int { didSet { ud.set(pomoFocus, forKey: "pomoFocus") } }
    @Published var pomoShort: Int { didSet { ud.set(pomoShort, forKey: "pomoShort") } }
    @Published var pomoLong: Int { didSet { ud.set(pomoLong, forKey: "pomoLong") } }
    @Published var pomoEvery: Int { didSet { ud.set(pomoEvery, forKey: "pomoEvery") } }
    @Published var pomoGoal: Int { didSet { ud.set(pomoGoal, forKey: "pomoGoal") } }
    @Published var pomoAutoBreak: Bool { didSet { ud.set(pomoAutoBreak, forKey: "pomoAutoBreak") } }
    @Published var pomoAutoFocus: Bool { didSet { ud.set(pomoAutoFocus, forKey: "pomoAutoFocus") } }
    /// Finished focus rounds in the current pomodoro run; nil when no run is going.
    @Published private(set) var pomoRound: Int? { didSet { ud.set(pomoRound, forKey: "pomoRound") } }
    /// The current (or, while waiting, upcoming) pomodoro phase is a break.
    @Published private(set) var onBreak: Bool { didSet { ud.set(onBreak, forKey: "onBreak") } }
    /// End of the current manual phase: a focus block, or a break when `onBreak`.
    @Published private(set) var focusUntil: Date? { didSet { ud.set(focusUntil?.timeIntervalSince1970, forKey: "focusUntil") } }
    @Published private(set) var manualStart: Date? { didSet { ud.set(manualStart?.timeIntervalSince1970, forKey: "manualStart") } }
    /// Set while a manual timer is paused; focusUntil/manualStart stay frozen until resume.
    @Published private(set) var pausedAt: Date? { didSet { ud.set(pausedAt?.timeIntervalSince1970, forKey: "pausedAt") } }
    /// Not published: it ticks every second, and the panel's TimelineView already redraws it.
    private(set) var focusSeconds: Int { didSet { ud.set(focusSeconds, forKey: "focusSeconds") } }
    @Published private(set) var blocked: Int { didSet { ud.set(blocked, forKey: "blocked") } }
    private var statsDay: Double { didSet { ud.set(statsDay, forKey: "statsDay") } }

    /// Not published, so the Store only invalidates views on real changes;
    /// views showing countdowns redraw from a TimelineView.
    var now: Date { Date() }
    @Published private(set) var browserError: String?
    @Published private(set) var loginError: String?

    private var timer: Timer?
    private var wasActive = false
    private var asked = Set<pid_t>() // apps already handled this session; quit is asked once so save dialogs survive
    private var agents: [pid_t: Bool] = [:]
    private let tabs = TabGuard()
    private var checkingTabs = false
    private var lastBrowser: NSRunningApplication?

    init() {
        enabled = ud.object(forKey: "enabled") as? Bool ?? true
        schedules = (ud.data(forKey: "schedules")).flatMap { try? JSONDecoder().decode([Schedule].self, from: $0) } ?? [Schedule()]
        apps = ud.stringArray(forKey: "apps") ?? [diaID]
        domains = ud.stringArray(forKey: "domains") ?? ["github.com", "google.com"]
        blockedApps = ud.stringArray(forKey: "blockedApps") ?? []
        blockedDomains = ud.stringArray(forKey: "blockedDomains") ?? ["youtube.com", "x.com"]
        allowedPaths = ud.stringArray(forKey: "allowedPaths") ?? []
        appMode = ListMode(rawValue: ud.string(forKey: "appMode") ?? "") ?? .block
        siteMode = ListMode(rawValue: ud.string(forKey: "siteMode") ?? "") ?? .block
        strict = ud.bool(forKey: "strict")
        spareAgents = ud.bool(forKey: "spareAgents")
        notify = ud.bool(forKey: "notify")
        pomoNotify = ud.bool(forKey: "pomoNotify")
        appAction = AppAction(rawValue: ud.string(forKey: "appAction") ?? "") ?? .quit
        siteAction = SiteAction(rawValue: ud.string(forKey: "siteAction") ?? "") ?? .page
        presets = ud.array(forKey: "presets") as? [Int] ?? [25, 50, 90]
        pomoFocus = ud.object(forKey: "pomoFocus") as? Int ?? 25
        pomoShort = ud.object(forKey: "pomoShort") as? Int ?? 5
        pomoLong = ud.object(forKey: "pomoLong") as? Int ?? 15
        pomoEvery = ud.object(forKey: "pomoEvery") as? Int ?? 4
        pomoGoal = ud.object(forKey: "pomoGoal") as? Int ?? 4
        pomoAutoBreak = ud.object(forKey: "pomoAutoBreak") as? Bool ?? true
        pomoAutoFocus = ud.object(forKey: "pomoAutoFocus") as? Bool ?? false
        pomoRound = ud.object(forKey: "pomoRound") as? Int
        onBreak = ud.bool(forKey: "onBreak")
        focusUntil = (ud.object(forKey: "focusUntil") as? Double).map(Date.init(timeIntervalSince1970:))
        manualStart = (ud.object(forKey: "manualStart") as? Double).map(Date.init(timeIntervalSince1970:))
        pausedAt = (ud.object(forKey: "pausedAt") as? Double).map(Date.init(timeIntervalSince1970:))
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
        timer?.tolerance = 0.2
    }

    // MARK: state

    var minuteNow: Int { let c = cal.dateComponents([.hour, .minute], from: now); return c.hour! * 60 + c.minute! }
    var activeSchedule: Schedule? {
        guard enabled else { return nil }
        let w = cal.component(.weekday, from: now), m = minuteNow
        return schedules.first { $0.contains(weekday: w, minute: m) }
    }
    private var phaseRunning: Bool { pausedAt == nil && (focusUntil ?? .distantPast) > now }
    var isManual: Bool { !onBreak && phaseRunning }
    var isBreak: Bool { onBreak && phaseRunning }
    var isPaused: Bool { pausedAt != nil }
    /// A pomodoro run between phases, waiting for the user to start the next one.
    var isWaiting: Bool { pomoRound != nil && focusUntil == nil }
    var nextPhaseMinutes: Int {
        onBreak ? pomoBreak(after: pomoRound ?? 0, short: pomoShort, long: pomoLong, every: pomoEvery, goal: 0)! : pomoFocus
    }
    /// Seconds left in the manual phase (frozen while paused), or the next phase's length while waiting.
    var phaseRemaining: Int {
        guard let f = focusUntil else { return isWaiting ? nextPhaseMinutes * 60 : 0 }
        return max(0, Int(f.timeIntervalSince(pausedAt ?? now)))
    }
    var phaseProgress: Double? {
        guard let f = focusUntil, let start = manualStart, f > start else { return nil }
        return min(max((pausedAt ?? now).timeIntervalSince(start) / f.timeIntervalSince(start), 0), 1)
    }
    var isActive: Bool { isManual || activeSchedule != nil }
    var locked: Bool { strict && isActive }
    var nextStartDate: Date? { enabled ? nextStart(schedules, after: now) : nil }

    private func length(of schedule: Schedule) -> Int {
        schedule.start < schedule.end ? schedule.end - schedule.start : 24 * 60 - schedule.start + schedule.end
    }

    /// When the current block began, for the progress reading.
    var sessionStart: Date? {
        var starts: [Date] = []
        if isManual, let manualStart { starts.append(manualStart) }
        if let schedule = activeSchedule, let end = endsAt {
            starts.append(end.addingTimeInterval(-TimeInterval(length(of: schedule) * 60)))
        }
        return starts.min()
    }

    /// 0...1, or nil when there is no measurable session.
    var progress: Double? {
        guard let start = sessionStart, let end = endsAt, end > start else { return nil }
        return min(max(now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
    }
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

    func startFocus(_ minutes: Int) {
        resumeFocus()
        if !isManual { manualStart = now }
        focusUntil = max(now, focusUntil ?? now).addingTimeInterval(TimeInterval(minutes * 60))
    }
    func startPomodoro() {
        guard !locked else { return }
        pomoRound = 0
        onBreak = false
        begin(pomoFocus)
    }
    /// Starts whichever phase a waiting pomodoro run is up to.
    func nextPhase() { if isWaiting { begin(nextPhaseMinutes) } }
    func skipBreak() {
        guard onBreak, pomoRound != nil else { return }
        onBreak = false
        begin(pomoFocus)
    }
    private func begin(_ minutes: Int) {
        pausedAt = nil
        manualStart = now
        focusUntil = now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func pauseFocus() {
        guard isManual || isBreak, !locked else { return }
        pausedAt = now
    }
    func resumeFocus() {
        guard let p = pausedAt else { return }
        let shift = now.timeIntervalSince(p)
        focusUntil = focusUntil?.addingTimeInterval(shift)
        manualStart = manualStart?.addingTimeInterval(shift)
        pausedAt = nil
    }
    /// Discards the manual timer and any pomodoro run, running or paused.
    func stopFocus() {
        guard !locked else { return }
        focusUntil = nil
        manualStart = nil
        pausedAt = nil
        pomoRound = nil
        onBreak = false
    }

    private func phaseEnded() {
        focusUntil = nil
        manualStart = nil
        guard let round = pomoRound else { return }
        if onBreak {
            onBreak = false
            if pomoAutoFocus { begin(pomoFocus) } else { post("Break over", "Start the next round from the menu bar.", pomodoro: true) }
        } else if let minutes = pomoBreak(after: round + 1, short: pomoShort, long: pomoLong, every: pomoEvery, goal: pomoGoal) {
            pomoRound = round + 1
            onBreak = true
            if pomoAutoBreak { begin(minutes) }
        } else {
            pomoRound = nil
        }
    }

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
    func addPath(_ raw: String) {
        let p = normalizePath(raw)
        if !p.isEmpty, !allowedPaths.contains(p) { allowedPaths.append(p) }
    }

    /// Adds the site in the front window of the browser used last.
    func addCurrentSite() {
        guard let app = lastBrowser.flatMap({ $0.isTerminated ? nil : $0 })
                ?? NSWorkspace.shared.runningApplications.first(where: { browsers[$0.bundleIdentifier ?? ""] != nil }),
              let tabKey = browsers[app.bundleIdentifier ?? ""] else { return }
        let pid = app.processIdentifier
        Task {
            if let u = await tabs.frontURL(pid, tabKey: tabKey), let h = URL(string: u)?.host { addDomain(h) }
        }
    }

    // MARK: enforcement

    private func tick() {
        if let f = NSWorkspace.shared.frontmostApplication, browsers[f.bundleIdentifier ?? ""] != nil { lastBrowser = f }
        let day = cal.startOfDay(for: now).timeIntervalSince1970
        if day != statsDay { statsDay = day; focusSeconds = 0; blocked = 0 }
        let pomo = pomoRound != nil // read before phaseEnded, which clears it when a run finishes
        if pausedAt == nil, let f = focusUntil, f <= now { phaseEnded() }

        let active = isActive
        if active != wasActive {
            wasActive = active
            objectWillChange.send() // `now` isn't published; this is what flips the menu bar icon
            if active { post("Focus started", endsAt.map { "Stay focused until \(clock($0))." } ?? "", pomodoro: pomo) }
            else {
                asked.removeAll()
                agents.removeAll() // pids get reused; re-check next block
                Task { await tabs.forget() }
                if isPaused { post("Focus paused", "\(hms(phaseRemaining)) left. Resume from the menu bar.", pomodoro: pomo) }
                else if isBreak { post("Break time", "\(phaseRemaining / 60) min. Step away for a bit.", pomodoro: pomo) }
                else if isWaiting { post("Round done", "Start your break from the menu bar.", pomodoro: pomo) }
                else { post("Focus ended", "Nice work. Time for a break.", pomodoro: pomo) }
            }
        }
        guard active else { return }
        focusSeconds += 1 // ponytail: counts ticks, drifts slightly under load; store session start/end if exact totals matter

        let me = Bundle.main.bundleIdentifier
        var targets: [TabTarget] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != me, !isSpared(app) else { continue }
            let appBlocked = isAppBlocked(id, appList, appMode)
            if let tabKey = browsers[id], !appBlocked {
                targets.append(TabTarget(pid: app.processIdentifier, name: app.localizedName ?? "your browser", tabKey: tabKey))
                continue
            }
            guard appBlocked else { continue }
            app.hide()
            if asked.insert(app.processIdentifier).inserted {
                blocked += 1
                if appAction == .quit { app.terminate() }
            }
        }
        checkTabs(targets)
    }

    /// Tab checks are Apple Events (synchronous IPC), so they run on `tabs`, off the main thread.
    /// A tick is skipped while the previous check is still out, e.g. when a browser hangs.
    private func checkTabs(_ targets: [TabTarget]) {
        guard !checkingTabs else { return }
        checkingTabs = true
        let (domains, mode, action, paths) = (domainList, siteMode, siteAction, allowedPaths)
        Task {
            let (count, error) = await tabs.enforce(targets, domains: domains, mode: mode, paths: paths, action: action)
            checkingTabs = false
            if count > 0 { blocked += count }
            if browserError != error { browserError = error }
        }
    }

    private func isSpared(_ app: NSRunningApplication) -> Bool {
        guard spareAgents else { return false }
        let pid = app.processIdentifier
        if agents[pid] == nil { agents[pid] = isAgentBrowser(pid) }
        return agents[pid]!
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func post(_ title: String, _ body: String, pomodoro: Bool = false) {
        guard pomodoro ? pomoNotify : notify else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

struct TabTarget: Sendable {
    let pid: pid_t
    let name: String
    let tabKey: String
}

/// Owns the Scripting Bridge objects, so the Apple Events behind tab checks never block the main thread.
// ponytail: the IPC blocks one cooperative-pool thread (~150 ms/s with 3 browsers); give TabGuard a serial-queue executor if that starves other tasks
actor TabGuard {
    private var bridges: [pid_t: SBApplication] = [:]
    private var permitted = Set<pid_t>() // ponytail: a revoked permission goes unnoticed until the block ends and forget() runs

    /// Scripting Bridge by pid, so an agent's Chrome and the user's Chrome are told apart.
    private func bridge(_ pid: pid_t) -> SBApplication? {
        if bridges[pid] == nil {
            let sb = SBApplication(processIdentifier: pid)
            sb?.timeout = 30 // ticks of 1/60 s: a hung browser costs 0.5 s per event instead of the default minutes
            bridges[pid] = sb
        }
        return bridges[pid]
    }

    /// Replaces or closes off-list tabs; returns how many, and an error worth showing.
    func enforce(_ targets: [TabTarget], domains: [String], mode: ListMode, paths: [String], action: SiteAction) -> (blocked: Int, error: String?) {
        var count = 0, error: String?
        for t in targets {
            if !permitted.contains(t.pid) {
                let target = NSAppleEventDescriptor(processIdentifier: t.pid)
                let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), true)
                if status == errAEEventNotPermitted {
                    error = "Allow Deepwork to control \(t.name) in System Settings › Privacy & Security › Automation"
                    continue
                }
                if status == noErr { permitted.insert(t.pid) }
            }
            let windows = (bridge(t.pid)?.value(forKey: "windows") as? SBElementArray) ?? []
            for case let w as NSObject in windows.reversed() { // closing a last tab closes its window
                guard let tab = w.value(forKey: t.tabKey) as? NSObject,
                      let u = tab.value(forKey: "URL") as? String, !isAllowed(u, domains, mode, paths: paths) else { continue }
                if action == .close { _ = tab.perform(NSSelectorFromString("close")) } else { tab.setValue(blockedURL, forKey: "URL") }
                count += 1
            }
        }
        return (count, error)
    }

    /// URL of the front window's tab.
    func frontURL(_ pid: pid_t, tabKey: String) -> String? {
        let w = (bridge(pid)?.value(forKey: "windows") as? SBElementArray)?.firstObject as? NSObject
        return (w?.value(forKey: tabKey) as? NSObject)?.value(forKey: "URL") as? String
    }

    /// Drops cached bridges and permissions; pids get reused.
    func forget() {
        bridges.removeAll()
        permitted.removeAll()
    }
}

func timeBinding(_ b: Binding<Int>) -> Binding<Date> {
    Binding(get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(b.wrappedValue * 60)) },
            set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); b.wrappedValue = c.hour! * 60 + c.minute! })
}
