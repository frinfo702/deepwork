import SwiftUI
import AppKit

// MARK: - Palette

enum Ink {
    /// One muted signal color, used sparingly for warnings.
    static let amber = Color(red: 0.75, green: 0.45, blue: 0.18)
    static let rose = Color(red: 0.78, green: 0.27, blue: 0.29)
    static let cool = Color(red: 0.60, green: 0.70, blue: 0.88)

    static func paperWash(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [Color(red: 0.105, green: 0.108, blue: 0.12).opacity(0.82),
                                      Color(red: 0.062, green: 0.066, blue: 0.078).opacity(0.76)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.985, green: 0.982, blue: 0.972).opacity(0.80),
                                      Color(red: 0.945, green: 0.952, blue: 0.968).opacity(0.64)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func glassFill(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [.white.opacity(0.085), .white.opacity(0.032)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.white.opacity(0.62), .white.opacity(0.36)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func glassEdge(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.035)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.white.opacity(0.92), .white.opacity(0.34)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func ascii(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.09)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.50),
                                      Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.14)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func code(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

func hms(_ seconds: Int) -> String {
    seconds >= 3600
        ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
        : String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

func relativeDay(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "" }
    if cal.isDateInTomorrow(date) { return "tomorrow" }
    return dayNames[cal.component(.weekday, from: date)]
}

// MARK: - Paper + glass

/// Translucent paper: real vibrancy, a soft wash, a dot grid and drifting ASCII weather.
struct PaperBackdrop: View {
    enum Kind { case panel, window }
    var kind: Kind = .panel

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                solid
            } else {
                VisualEffectView(material: .underWindowBackground, blending: .behindWindow)
                Ink.paperWash(scheme)
            }
            glow
            DotGrid(spacing: kind == .panel ? 12 : 14,
                    radius: kind == .panel ? 0.62 : 0.58,
                    color: .primary.opacity(scheme == .dark ? 0.075 : 0.105))
            GrainTexture(intensity: scheme == .dark ? 0.22 : 0.18)
            edgeShade
        }
        .allowsHitTesting(false)
    }

    private var solid: Color {
        scheme == .dark ? Color(red: 0.075, green: 0.08, blue: 0.095)
                        : Color(red: 0.972, green: 0.97, blue: 0.962)
    }

    private var glow: some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.035 : 0.30), .clear],
                           center: UnitPoint(x: 0.08, y: 0.0), startRadius: 0,
                           endRadius: kind == .panel ? 240 : 420)
            RadialGradient(colors: [Ink.cool.opacity(scheme == .dark ? 0.12 : 0.10), .clear],
                           center: UnitPoint(x: 0.98, y: 0.96), startRadius: 0,
                           endRadius: kind == .panel ? 300 : 520)
        }
    }

    private var edgeShade: some View {
        LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.04 : 0.18),
                                .clear,
                                .black.opacity(scheme == .dark ? 0.20 : 0.035)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

struct DotGrid: View {
    var spacing: CGFloat
    var radius: CGFloat
    var color: Color

    var body: some View {
        Canvas { context, size in
            guard spacing > 2 else { return }
            var dots = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

struct GrainTexture: View {
    var intensity: Double = 0.2

    var body: some View {
        Image(nsImage: Grain.image)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(intensity)
            .allowsHitTesting(false)
    }
}

private enum Grain {
    static let image: NSImage = {
        let side = 96
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return NSImage(size: NSSize(width: side, height: side)) }
        var seed: UInt64 = 0x2545F4914F6CDD1D
        for i in 0..<(side * side) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8((seed >> 33) & 0xFF)
            let alpha = UInt8(20 + (seed >> 45) % 68)
            data[i * 4] = value
            data[i * 4 + 1] = value
            data[i * 4 + 2] = value
            data[i * 4 + 3] = alpha
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }()
}

// MARK: - ASCII weather

enum ASCIIArt {
    private static let ramp = Array(" .·:cCoOS0#%@")

    private static func ellipse(_ x: Double, _ y: Double,
                                _ cx: Double, _ cy: Double,
                                _ rx: Double, _ ry: Double) -> Double {
        let dx = (x - cx) / rx
        let dy = (y - cy) / ry
        return 1 - dx * dx - dy * dy
    }

    private static func hash(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(bitPattern: Int64(a &* 374_761_393 &+ b &* 668_265_263)) ^ 0x9E37_79B9_7F4A_7C15
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) & 0xFFFF) / 65_535
    }

    /// A cloud with distinct puffs, a dense interior and loose specks of weather.
    static func cloud(cols: Int, rows: Int, phase: Double) -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows)

        let puffs: [(Double, Double, Double, Double)] = [
            (28, 7.5, 11, 6.5),
            (15, 9.5, 8, 5.0),
            (41, 9.0, 9, 5.5),
            (20, 5.0, 6, 4.0),
            (36, 5.0, 6, 4.0),
            (28, 12.0, 18, 3.2)
        ]

        for row in 0..<rows {
            let y = Double(row) / Double(max(1, rows - 1)) * 17
            var line = ""
            line.reserveCapacity(cols)

            for col in 0..<cols {
                let x = Double(col) / Double(max(1, cols - 1)) * 55
                var density = puffs.map { ellipse(x, y, $0.0, $0.1, $0.2, $0.3) }.max() ?? 0

                let noise = 0.08 * sin(0.55 * x + phase + 1.7 * sin(0.5 * y))
                    + 0.055 * sin(0.9 * y - phase * 0.55 + 0.42 * x)
                    + 0.03 * sin(1.7 * (x + y) + phase * 1.2)
                density = density * 1.05 + noise

                let texture = hash(col, row)
                let weather = hash(col + 91, row + 53)

                if density > 0 {
                    if texture < 0.08, density < 0.72 {
                        line.append(" ")
                    } else {
                        let jitter = (texture - 0.5) * 2.0
                        let level = Int((2 + min(1, density * 1.25) * 7 + jitter).rounded())
                        line.append(ramp[min(ramp.count - 1, max(2, level))])
                    }
                } else if density > -0.06, weather < 0.55 {
                    let edge: [Character] = [".", "·", ":"]
                    line.append(edge[min(2, Int(weather * 3))])
                } else if weather > 0.992 {
                    line.append("·")
                } else {
                    line.append(" ")
                }
            }
            lines.append(line.replacingOccurrences(of: " +$", with: "", options: .regularExpression))
        }
        return lines.joined(separator: "\n")
    }
}

/// Ambient ASCII clouds. Static when Reduce Motion is on.
struct ASCIIField: View {
    var size: CGFloat = 7.5
    var cols: Int = 56
    var rows: Int = 18
    var animate: Bool = true
    var opacity: Double = 0.9

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animate && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    art(phase: context.date.timeIntervalSinceReferenceDate * 0.12)
                }
            } else {
                art(phase: 0)
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func art(phase: Double) -> some View {
        Text(ASCIIArt.cloud(cols: cols, rows: rows, phase: phase))
            .font(.system(size: size, weight: .regular, design: .monospaced))
            .lineSpacing(-1.2)
            .foregroundStyle(Ink.ascii(scheme))
            .fixedSize()
    }
}

// MARK: - Surfaces

struct GlassSurface<Content: View>: View {
    var corner: CGFloat = 12
    var padding: CGFloat = 12
    var elevated: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(padding)
            .background {
                let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
                shape
                    .fill(Ink.glassFill(scheme))
                    .overlay(shape.strokeBorder(Ink.glassEdge(scheme), lineWidth: 0.8))
                    .shadow(color: .black.opacity(elevated ? (scheme == .dark ? 0.28 : 0.055) : 0),
                            radius: elevated ? 14 : 0, y: elevated ? 5 : 0)
            }
    }
}

struct DottedLine: View {
    var inset: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            var dot = Path()
            var x: CGFloat = 0
            while x < size.width {
                dot.addEllipse(in: CGRect(x: x, y: size.height / 2 - 0.5, width: 1, height: 1))
                x += 4
            }
            context.fill(dot, with: .color(.primary.opacity(scheme == .dark ? 0.13 : 0.16)))
        }
        .frame(height: 1)
        .padding(.leading, inset)
        .allowsHitTesting(false)
    }
}

struct SectionHeader: View {
    var title: String
    var note: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.ui(12, .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let note {
                Text(note)
                    .font(.code(9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Controls

struct SoftSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { isOn.toggle() }
        } label: {
            ZStack {
                Capsule()
                    .fill(isOn
                          ? AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.92 : 0.84))
                          : AnyShapeStyle(Color.primary.opacity(0.10)))
                    .frame(width: 34, height: 20)
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 0.6))
                Circle()
                    .fill(scheme == .dark && isOn ? Color.black : Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: isOn ? 7 : -7)
            }
            .frame(width: 34, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct SoftButtonStyle: ButtonStyle {
    enum Kind { case quiet, strong }
    var kind: Kind = .quiet
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(11, .medium))
            .foregroundStyle(kind == .strong
                             ? AnyShapeStyle(scheme == .dark ? Color.black : Color.white)
                             : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                if kind == .strong {
                    shape.fill(Color.primary.opacity(configuration.isPressed ? 0.72 : 0.88))
                } else {
                    shape
                        .fill(scheme == .dark
                              ? Color.white.opacity(configuration.isPressed ? 0.13 : 0.075)
                              : Color.white.opacity(configuration.isPressed ? 0.82 : 0.56))
                        .overlay(shape.strokeBorder(Ink.glassEdge(scheme), lineWidth: 0.8))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.05), radius: 5, y: 2)
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
    }
}

struct SoftSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { index in
                let value = options[index].0
                let label = options[index].1
                let on = value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = value }
                } label: {
                    Text(label)
                        .font(.ui(10.5, on ? .medium : .regular))
                        .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(scheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.78))
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Ink.glassEdge(scheme), lineWidth: 0.7))
                                    .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.05), radius: 4, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 0.7))
        }
    }
}

struct SoftStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 5
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            button("minus", enabled: value - step >= range.lowerBound) { value -= step }
            Text("\(value)")
                .font(.ui(12, .medium))
                .monospacedDigit()
                .frame(minWidth: 30)
            button("plus", enabled: value + step <= range.upperBound) { value += step }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.55))
                        .overlay(Circle().strokeBorder(Ink.glassEdge(scheme), lineWidth: 0.7))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.04), radius: 3, y: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.32)
    }
}

struct SoftField: View {
    @Binding var text: String
    var prompt: String
    var action: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    private var canSubmit: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(.tertiary))
                .textFieldStyle(.plain)
                .font(.code(11))
                .focused($focused)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(canSubmit
                                     ? AnyShapeStyle(scheme == .dark ? Color.black : Color.white)
                                     : AnyShapeStyle(.tertiary))
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(canSubmit
                                  ? AnyShapeStyle(Color.primary.opacity(0.86))
                                  : AnyShapeStyle(.primary.opacity(0.05)))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.leading, 11)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background {
            let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
            shape
                .fill(scheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.50))
                .overlay(shape.strokeBorder(focused ? AnyShapeStyle(.primary.opacity(0.20))
                                                    : AnyShapeStyle(.primary.opacity(0.08)), lineWidth: 0.8))
        }
    }

    private func submit() {
        guard canSubmit else { return }
        action()
        text = ""
    }
}

struct RemoveButton: View {
    var action: () -> Void
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(hover ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 20, height: 20)
                .background {
                    Circle()
                        .fill(.primary.opacity(hover ? (scheme == .dark ? 0.10 : 0.06) : 0))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hover = hovering }
        }
        .accessibilityLabel("Remove")
    }
}

struct WeekdayPicker: View {
    @Binding var days: Set<Int>
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(weekOrder, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if on { days.remove(day) } else { days.insert(day) }
                    }
                } label: {
                    Text(dayNames[day].prefix(2).lowercased())
                        .font(.ui(10, .medium))
                        .frame(width: 31, height: 26)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(on
                                      ? AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.88 : 0.82))
                                      : AnyShapeStyle(.clear))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(.primary.opacity(0.10)),
                                                  lineWidth: 0.8))
                        }
                        .foregroundStyle(on ? AnyShapeStyle(scheme == .dark ? Color.black : Color.white)
                                            : AnyShapeStyle(.secondary))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Plain text + icon button with a quiet hover.
struct QuietButton: View {
    var title: String
    var icon: String? = nil
    var shortcut: KeyEquivalent? = nil
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        if let shortcut {
            button.keyboardShortcut(shortcut, modifiers: .command)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 9.5, weight: .regular))
                }
                Text(title).font(.ui(11, .medium))
            }
            .foregroundStyle(hover ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(hover ? 0.045 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hover = hovering }
        }
    }
}

struct CloudMark: View {
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: "cloud.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(LinearGradient(colors: [.primary, .primary.opacity(0.55)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

struct StatusDot: View {
    var active: Bool
    var body: some View {
        Circle()
            .fill(.primary.opacity(active ? 0.78 : 0.16))
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }
}

struct ThinProgress: View {
    var value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(.primary.opacity(0.09))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.68))
                    .scaleEffect(x: min(max(value, 0), 1), anchor: .leading)
            }
            .animation(reduceMotion ? nil : .linear(duration: 1), value: value)
            .accessibilityHidden(true)
    }
}
