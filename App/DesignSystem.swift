import SwiftUI
import Charts
import PulseCore

extension Color {
    /// Resolves to one of two hexes depending on the rendering environment.
    /// Every colour in the app is defined this way so light and dark are
    /// decided once, here, and never by a view guessing from `colorScheme`.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

enum AppColors {
    /// Pure white in light, pure black in dark. Surfaces are separated from it
    /// by borders and elevation, never by tinting the background grey.
    static let background = Color.adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x0B0D0C)
    static let surfaceRaised = Color.adaptive(light: 0xF7FAF9, dark: 0x141816)
    static let border = Color.adaptive(light: 0xE2E8E6, dark: 0x232A27)

    /// The logo green. `#27F6CC` is only legible on dark, so light mode uses a
    /// darker step of the same hue (4.94:1 on white) for text and symbols.
    static let accent = Color.adaptive(light: 0x0A7F68, dark: 0x27F6CC)
    /// For large fills and strokes, where 3:1 is the bar and more chroma reads better.
    static let accentVivid = Color.adaptive(light: 0x0E9C7F, dark: 0x27F6CC)
    static let accentSoft = Color.adaptive(light: 0xE6F7F2, dark: 0x0E2A24)

    /// Status colours stay out of the accent's hue so "good" and "brand" never
    /// collide: the accent marks Veyra, these mark a state.
    static let warn = Color.adaptive(light: 0xB26A00, dark: 0xFFB454)
    static let danger = Color.adaptive(light: 0xB3261E, dark: 0xFF6B61)

    static let ink = Color.adaptive(light: 0x111A18, dark: 0xF2F5F4)
    static let divider = Color.adaptive(light: 0xEDF1F0, dark: 0x1C2220)

    static func metric(_ metric: Metric) -> Color {
        switch metric {
        case .recovery: accent
        case .sleep: .adaptive(light: 0x3F55B8, dark: 0x8FA5FF)
        case .strain: .adaptive(light: 0xBE5411, dark: 0xFF9E52)
        case .stress: .adaptive(light: 0x8A3FB8, dark: 0xC98CF5)
        case .energy: .adaptive(light: 0x8A6A00, dark: 0xFFD666)
        }
    }
    /// The dark-mode metric colours, used on photographic scenes in either
    /// appearance: a scene is always dark behind its text.
    static func metricOnScene(_ metric: Metric) -> Color {
        switch metric {
        case .recovery: Color(red: 0x27 / 255, green: 0xF6 / 255, blue: 0xCC / 255)
        case .sleep: Color(red: 0x8F / 255, green: 0xA5 / 255, blue: 1)
        case .strain: Color(red: 1, green: 0x9E / 255, blue: 0x52 / 255)
        case .stress: Color(red: 0xC9 / 255, green: 0x8C / 255, blue: 0xF5 / 255)
        case .energy: Color(red: 1, green: 0xD6 / 255, blue: 0x66 / 255)
        }
    }
    /// Low → high scale used by gauges. Deliberately skips the brand green so a
    /// green needle never reads as "Veyra" instead of "good".
    static func scale(_ fraction: Double) -> Color {
        let stops: [(Double, Color)] = [
            (0.0, .adaptive(light: 0x2E7D4F, dark: 0x5FD98C)),
            (0.4, .adaptive(light: 0xB08800, dark: 0xF2C94C)),
            (0.7, .adaptive(light: 0xC2691A, dark: 0xFF9E52)),
            (1.0, danger)
        ]
        let f = min(1, max(0, fraction))
        guard let upper = stops.firstIndex(where: { $0.0 >= f }), upper > 0 else { return stops[0].1 }
        return stops[upper].1.mix(with: stops[upper - 1].1, by: (stops[upper].0 - f) / (stops[upper].0 - stops[upper - 1].0))
    }
    static var scaleGradient: [Color] { stride(from: 0.0, through: 1.0, by: 0.1).map(scale) }
    /// Explicit bands for a charge level, so a two-thirds-full battery is
    /// unambiguously green instead of landing mid-ramp in amber.
    static func battery(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.15: danger
        case ..<0.35: warn
        case ..<0.60: .adaptive(light: 0xA8B520, dark: 0xD8E05A)
        // Leaning teal, to sit with the app's own mint rather than against it.
        default: .adaptive(light: 0x2DBE8C, dark: 0x45E3B0)
        }
    }
    /// The unfilled part of a battery cell. Deep enough that a white figure
    /// over it keeps its contrast, in both appearances.
    static let batteryWell = Color.adaptive(light: 0xB9C2BF, dark: 0x2A312E)
    static let batteryHatch = Color.adaptive(light: 0xCCD4D1, dark: 0x3A423F)
    /// Energy level as a colour: depleted is red, full is green. Used as a
    /// vertical gradient over a 0–100 plot so the line is tinted by its height.
    static func energyLevel(_ fraction: Double) -> Color {
        let stops: [(Double, Color)] = [
            (0.00, danger),
            (0.30, .adaptive(light: 0xD98A19, dark: 0xFFB454)),
            (0.55, .adaptive(light: 0xB8A800, dark: 0xE8DC5A)),
            (1.00, .adaptive(light: 0x2DBE8C, dark: 0x45E3B0))
        ]
        return interpolate(stops, fraction)
    }
    /// Activation as a colour: blue when very low, then green, yellow, orange
    /// and red. Deliberately separate from the generic scale, which starts at
    /// green and so had nothing left to express "unusually calm".
    static func stressLevel(_ fraction: Double) -> Color {
        let stops: [(Double, Color)] = [
            (0.00, .adaptive(light: 0x2C7FD4, dark: 0x5FB4F5)),
            (0.25, .adaptive(light: 0x2E9E5B, dark: 0x5FD98C)),
            (0.50, .adaptive(light: 0xC9A400, dark: 0xF2D24C)),
            (0.75, .adaptive(light: 0xD97A1A, dark: 0xFF9E52)),
            (1.00, danger)
        ]
        return interpolate(stops, fraction)
    }
    /// Top-to-bottom gradient for a 0–100 plot, so a line is coloured by height.
    ///
    /// `fade` ramps the opacity down towards the baseline. An area fill spans
    /// from the line to zero, so a solid height gradient painted the bottom of
    /// every column in the low-end colour — a full battery still showed a red
    /// wash under it. Fading means the colour is only visible near the line,
    /// which is where it means something.
    static func verticalScale(_ colour: @escaping (Double) -> Color, fade: Bool = false) -> LinearGradient {
        LinearGradient(
            stops: stride(from: 1.0, through: 0.0, by: -0.1).map { level in
                .init(color: colour(level).opacity(fade ? max(0, level - 0.08) : 1),
                      location: 1 - level)
            },
            startPoint: .top, endPoint: .bottom)
    }
    private static func interpolate(_ stops: [(Double, Color)], _ fraction: Double) -> Color {
        let f = min(1, max(0, fraction))
        guard let upper = stops.firstIndex(where: { $0.0 >= f }), upper > 0 else { return stops[0].1 }
        let span = stops[upper].0 - stops[upper - 1].0
        return stops[upper].1.mix(with: stops[upper - 1].1, by: span > 0 ? (stops[upper].0 - f) / span : 0)
    }
}

/// San Francisco throughout — the system faces, at system sizes, so the app
/// reads as an iOS app and scales with Dynamic Type. No rounded variant and no
/// custom family: mixing them is what made the screens look unrelated.
enum AppTypography {
    static let title = Font.largeTitle.weight(.bold)
    static let score = Font.system(size: 44, weight: .semibold)
    static let cardTitle = Font.headline
}

struct VeyraBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme
    var compact = false
    var body: some View {
        Image("VeyraLogo")
            .renderingMode(colorScheme == .dark ? .template : .original)
            .resizable()
            .scaledToFit()
            .frame(width: compact ? 132 : 220, height: compact ? 44 : 74)
            .foregroundStyle(AppColors.accent)
            .accessibilityLabel("Veyra")
    }
}

struct BrandHeader: View {
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VeyraBrandMark(compact: true)
            if let subtitle { Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            Spacer()
        }
    }
}

/// The single surface primitive. `scene` replaces the old `hero` flag: instead
/// of a fixed dark gradient that ignored light mode, a card can carry an
/// illustrated scene that has its own light and dark rendition.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var scene: MetricScene? = nil
    var accent: Color? = nil
    /// Stacking of the card's own rows. Dense cards need less than the default.
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if let scene { MetricSceneView(scene: scene) } else { AppColors.surface }
            }
            .foregroundStyle(scene == nil ? AppColors.ink : Color.white)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(scene == nil ? AppColors.border : (accent ?? AppColors.accent).opacity(0.28), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 10, y: 4)
    }
}

struct SectionTitle: View {
    var title: String
    var symbol: String
    var body: some View {
        HStack {
            Label(L(title), systemImage: symbol).font(AppTypography.cardTitle)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}

/// A closed ring that draws itself in, shaded light-to-deep along the arc.
///
/// Two things make this work where earlier attempts did not. The gradient's
/// angular range is set to exactly the drawn arc, so the full light-to-deep
/// range lands on the stroke whatever the value — spanning the whole circle
/// meant a low score only ever showed the first sliver of the ramp. And the
/// light end is the tint mixed towards *white*, not the tint at low opacity:
/// a translucent start let the grey track show through and read as the ring
/// being cut open.
///
/// The common trick in circular-progress libraries is to begin and end the
/// gradient on the same colour so the wrap is invisible. That is unavailable
/// here precisely because the point is for the two ends to differ.
struct ScoreRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var metric: Metric
    var value: Double?
    var size: CGFloat = 88
    var onScene = false

    /// Drawn length, animated from zero on appear and on every change.
    @State private var sweep: Double = 0

    private var tint: Color { onScene ? AppColors.metricOnScene(metric) : AppColors.metric(metric) }
    private var width: CGFloat { max(9, size * 0.145) }
    private var fraction: Double { min(1, max(0, (value ?? 0) / 100)) }

    /// Opaque throughout: light where the arc begins, full colour at its head.
    ///
    /// Angles start at zero, **not** at −90. `rotationEffect` below rotates the
    /// gradient along with the shape, so subtracting 90 here too offset the ramp
    /// by a quarter turn and dropped its wrap point in the middle of the visible
    /// arc — which is exactly what looked like the ring being cut.
    private var shade: AngularGradient {
        let light = tint.mix(with: .white, by: onScene ? 0.34 : 0.52)
        let mid = tint.mix(with: .white, by: onScene ? 0.15 : 0.24)
        return AngularGradient(
            gradient: Gradient(colors: [light, mid, tint]),
            center: .center,
            startAngle: .degrees(0),
            // Exactly the drawn arc, so the ramp is the same shape at any value.
            endAngle: .degrees(360 * max(0.12, sweep))
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(onScene ? Color.white.opacity(0.20) : AppColors.border, lineWidth: width)
            if value != nil {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: reduceTransparency ? 0 : width * 0.5)
                    .opacity(reduceTransparency ? 0 : 0.45)
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(shade, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(number(value))
                        .font(.system(size: size * 0.33, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: size * 0.17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "ellipsis")
                    .font(.system(size: size * 0.22, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animate(to: fraction) }
        .onChange(of: fraction) { _, target in animate(to: target) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(metric.rawValue))
        .accessibilityValue(value.map { number($0) + "%" } ?? L("noData"))
    }

    private func animate(to target: Double) {
        guard value != nil else { sweep = 0; return }
        let length = max(0.004, target)
        guard !reduceMotion else { sweep = length; return }
        withAnimation(.smooth(duration: 0.55 + 0.5 * length)) { sweep = length }
    }
}

/// Confidence as a percentage rather than a four-step word. The label is never
/// dropped: a lone "46%" in a corner tells the reader nothing about what is
/// 46% of what. `compact` only makes it smaller.
struct ConfidenceBadge: View {
    var percent: Double
    var compact = false
    /// On a photographic scene a tinted wash has nothing to sit against, so the
    /// badge switches to a material capsule with light text.
    var onScene = false
    private var tint: Color {
        switch percent { case ..<20: AppColors.danger; case ..<45: AppColors.warn; default: AppColors.accent }
    }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
            Text(L("confidence")).opacity(0.8)
            Text(number(percent) + "%").monospacedDigit().fontWeight(.semibold)
        }
        .font((compact ? Font.caption2 : Font.caption).weight(.medium))
        .foregroundStyle(onScene ? Color.white : tint)
        .padding(.horizontal, compact ? 7 : 9).padding(.vertical, compact ? 4 : 5)
        .background {
            if onScene { Capsule().fill(.ultraThinMaterial) } else { Capsule().fill(tint.opacity(0.12)) }
        }
        .fixedSize()
        .accessibilityLabel(L("confidence"))
        .accessibilityValue(number(percent) + "%")
    }
}

struct EmptyMetricState: View {
    var title = "noData"
    var detail = "noDataDetail"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L(title), systemImage: "waveform.path").font(.subheadline.weight(.medium))
            Text(L(detail)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

struct MetricTimeline: View {
    var points: [TimelinePoint]
    var metric: Metric
    var height: CGFloat = 110
    var body: some View { HealthTrendChart(points: points, metric: metric, height: height) }
}

struct ValueRow: View {
    var title: String
    var value: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            if let symbol { Image(systemName: symbol).foregroundStyle(AppColors.accent).frame(width: 24) }
            Text(L(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }
}

struct PrimaryButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(L(title)).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.accentVivid)
    }
}

struct PageIntro: View {
    var title: String
    var subtitle: String
    var symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(AppColors.accent)
                .frame(width: 50, height: 50)
                .background(AppColors.accentSoft, in: .rect(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(L(title)).font(.title2.weight(.bold))
                Text(L(subtitle)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

extension View {
    /// Flat background. The previous version painted three blurred colour blobs
    /// over a grey-blue base, which is what stopped light mode from being white.
    func pulsePage() -> some View {
        background(PageBackdrop()).tint(AppColors.accent)
    }
}

extension Color {
    /// Linear blend between two colours. Used to lighten a tint towards white
    /// without making it transparent, which is the difference between a ring
    /// that looks shaded and one that looks cut.
    func mix(with other: Color, by amount: Double) -> Color {
        let t = min(1, max(0, amount))
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t)
    }
}

/// Diagonal hatching, used for the unfilled part of the battery so empty reads
/// as "not yet charged" rather than as a plain gap.
struct DiagonalHatch: Shape {
    var spacing: CGFloat = 7
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
