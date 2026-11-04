import AppKit

// ponytail: self-rolled GitHub Releases updater over HTTPS, no signature check beyond bundle id; switch to Sparkle (EdDSA appcast) once the app is Developer ID signed.
let repo = "frinfo702/deepwork"
var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
func isNewer(_ a: String, than b: String) -> Bool { a.compare(b, options: .numeric) == .orderedDescending }

/// Waits for the app to quit, swaps bundles (restoring the old one if the move fails), relaunches.
let swapScript = """
while kill -0 "$3" 2>/dev/null; do sleep 0.2; done
mv "$1" "$1.old" && { mv "$2" "$1" && rm -rf "$1.old" || mv "$1.old" "$1"; }
open "$1"
"""

private struct Release: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: URL }
    let tag_name: String
    let assets: [Asset]
}

private struct Failure: LocalizedError { let errorDescription: String? }

@MainActor final class Updater: ObservableObject {
    @Published var auto: Bool { didSet { UserDefaults.standard.set(auto, forKey: "autoUpdate") } }
    @Published private(set) var available: (version: String, url: URL)?
    @Published private(set) var status: String?
    @Published private(set) var busy = false
    private var timer: Timer?

    init() {
        auto = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.auto == true { Task { await self?.check(silent: true) } } }
        }
        if auto { Task { await check(silent: true) } }
    }

    func check(silent: Bool = false) async {
        busy = true
        defer { busy = false }
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            let r = try JSONDecoder().decode(Release.self, from: data)
            let v = r.tag_name.hasPrefix("v") ? String(r.tag_name.dropFirst()) : r.tag_name
            if isNewer(v, than: appVersion), let a = r.assets.first(where: { $0.name == "Deepwork.zip" }) {
                available = (v, a.browser_download_url)
                status = nil
            } else {
                available = nil
                if !silent { status = "You're up to date (\(appVersion))." }
            }
        } catch {
            if !silent { status = "Couldn't check for updates: \(error.localizedDescription)" }
        }
    }

    func install() async {
        guard let (v, url) = available else { return }
        busy = true
        status = "Downloading \(v)…"
        do {
            let (zip, _) = try await URLSession.shared.download(from: url)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deepwork-update-\(UUID().uuidString)")
            try run("/usr/bin/ditto", "-x", "-k", zip.path, dir.path)
            let new = dir.appendingPathComponent("Deepwork.app")
            guard Bundle(url: new)?.bundleIdentifier == Bundle.main.bundleIdentifier else { throw Failure(errorDescription: "The download doesn't look like Deepwork.") }
            let old = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: old.deletingLastPathComponent().path) else {
                throw Failure(errorDescription: "Can't write to \(old.deletingLastPathComponent().path).")
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", swapScript, "sh", old.path, new.path, String(getpid())]
            try p.run()
            NSApp.terminate(nil)
        } catch {
            status = "Update failed: \(error.localizedDescription)"
            busy = false
        }
    }

    private func run(_ tool: String, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw Failure(errorDescription: "\(tool) failed (\(p.terminationStatus)).") }
    }
}
