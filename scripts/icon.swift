// Generates Resources/AppIcon.icns and docs/icon.png. Run: swiftc -parse-as-library scripts/icon.swift -o /tmp/icon && /tmp/icon
import SwiftUI
import AppKit

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.66, blue: 1.0), Color(red: 0.36, green: 0.27, blue: 0.88)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: .init(x: 0.3, y: 0.15), startRadius: 0, endRadius: 600)))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
            Image(systemName: "cloud.fill")
                .font(.system(size: 420, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.2, green: 0.1, blue: 0.6).opacity(0.35), radius: 24, y: 16)
                .offset(y: 10)
        }
        .frame(width: 1024, height: 1024)
    }
}

@main struct Gen {
    @MainActor static func main() throws {
        let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: set)
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        func png(_ px: Int) -> Data {
            let r = ImageRenderer(content: Icon())
            r.scale = CGFloat(px) / 1024
            return NSBitmapImageRep(cgImage: r.cgImage!).representation(using: .png, properties: [:])!
        }
        for base in [16, 32, 128, 256, 512] {
            try png(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
            try png(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
        try png(512).write(to: URL(fileURLWithPath: "docs/icon.png"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
        try p.run(); p.waitUntilExit()
        print("icon ok")
    }
}
