// Benchmarks the real app code. bench/run.sh compiles Sources/ (at a git ref and in the
// working tree) into a testable library and links this file against each build.
@testable import Deepwork
import AppKit
import Combine
import ScriptingBridge

@main @MainActor struct Bench {
    static func main() async {
        // Store persists to UserDefaults.standard, which for this binary is the
        // "deepwork-bench" domain, never the app's. Schedules off, no timer running:
        // the Store never becomes active, so it never hides apps or touches tabs.
        UserDefaults.standard.removePersistentDomain(forName: "deepwork-bench")
        UserDefaults.standard.set(false, forKey: "enabled")
        UserDefaults.standard.set(true, forKey: "didFirstLaunch") // skip login item registration

        report("ascii_us", perCall(2000) { ASCIIArt.cloud(cols: 52, rows: 17, phase: Double($0) * 0.06).utf8.count })

        let store = Store()
        store.schedules = (0..<5).map { Schedule(start: $0 * 60, end: $0 * 60 + 120, days: []) } // never match: worst case
        store.enabled = true
        report("active_schedule_us", perCall(20000) { _ in store.activeSchedule == nil ? 0 : 1 })
        store.enabled = false

        let timer = Mirror(reflecting: store).children.first { $0.label == "timer" }?.value as? Timer
        report("timer_tolerance_s", timer?.tolerance ?? 0)

        // Idle: no focus, menu closed. Every objectWillChange invalidates SwiftUI views
        // observing the Store, including the menu bar icon's Scene body.
        RunLoop.main.run(until: Date() + 1.2) // let the first tick reset daily stats
        var changes = 0
        let sub = store.objectWillChange.sink { changes += 1 }
        RunLoop.main.run(until: Date() + 5)
        sub.cancel()
        report("idle_changes_per_s", Double(changes) / 5)

        await tabCheck()
        UserDefaults.standard.removePersistentDomain(forName: "deepwork-bench")
    }

    /// Reads every window's tab URL in running browsers, the work a focus tick does,
    /// with no URL on the list so nothing is changed. Skipped without Automation access;
    /// never asks for it.
    static func tabCheck() async {
        let apps = NSWorkspace.shared.runningApplications.filter { app in
            guard browsers[app.bundleIdentifier ?? ""] != nil else { return false }
            let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), false) == noErr
        }
        guard !apps.isEmpty else { return report("tab_browsers", 0) }
        report("tab_browsers", Double(apps.count))
        let rounds = 20
        var main = 0.0, total = 0.0
        #if HAS_TABGUARD
        let targets = apps.map { TabTarget(pid: $0.processIdentifier, name: $0.localizedName ?? "", tabKey: browsers[$0.bundleIdentifier!]!) }
        let tabs = TabGuard()
        for _ in 0..<rounds {
            let t0 = clock()
            let task = Task { await tabs.enforce(targets, domains: [], mode: .block, action: .page) }
            main += clock() - t0
            _ = await task.value
            total += clock() - t0
        }
        #else
        // The pre-TabGuard tick ran this synchronously on the main thread (old Store.checkTabs).
        var bridges: [pid_t: SBApplication] = [:]
        for _ in 0..<rounds {
            let t0 = clock()
            for app in apps {
                let pid = app.processIdentifier
                let target = NSAppleEventDescriptor(processIdentifier: pid)
                _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), true)
                if bridges[pid] == nil { bridges[pid] = SBApplication(processIdentifier: pid) }
                let windows = (bridges[pid]?.value(forKey: "windows") as? SBElementArray) ?? []
                for case let w as NSObject in windows.reversed() {
                    guard let tab = w.value(forKey: browsers[app.bundleIdentifier!]!) as? NSObject,
                          let u = tab.value(forKey: "URL") as? String, !isAllowed(u, [], .block) else { continue }
                }
            }
            main += clock() - t0
            total = main
        }
        #endif
        report("tab_main_ms", main / Double(rounds) * 1000)
        report("tab_total_ms", total / Double(rounds) * 1000)
    }

    static func clock() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    static func perCall(_ n: Int, _ f: (Int) -> Int) -> Double {
        var sink = 0
        for i in 0..<n / 10 { sink &+= f(i) } // warm up
        let t0 = clock()
        for i in 0..<n { sink &+= f(i) }
        if sink == .min { print(sink) }
        return (clock() - t0) / Double(n) * 1e6
    }

    static func report(_ key: String, _ value: Double) { print("\(key)\t\(value)") }
}
