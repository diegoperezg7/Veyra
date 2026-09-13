import SwiftUI
import PulseCore

/// An age ruler rather than a bar with a dot on it. The axis carries real,
/// labelled ages so the number has somewhere to sit; the zones say what the
/// position means; the band shows how sure the estimate is.
///
/// Colour follows the gap, not the age: below chronological is green, above is
/// amber, well above is red. The chronological age itself is the boundary.
struct BiologicalAgeChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let estimate: WellnessAgeEstimate
    /// Animated position of the marker, so the value travels to its place
    /// instead of appearing already there.
    @State private var progress: Double = 0

    /// How far either side of the chronological age the ruler spans.
    private var span: Double { max(8, min(16, estimate.margin + abs(estimate.delta) + 5)) }
    private var lower: Double { estimate.chronologicalAge - span }
    private var upper: Double { estimate.chronologicalAge + span }

    /// Ticks anchored on the chronological age, which is the one label that
    /// must always be present: everything is read relative to it.
    private var ticks: [Double] {
        let step = span > 12 ? 8.0 : span > 8 ? 5.0 : 4.0
        let offsets = stride(from: -step * 2, through: step * 2, by: step).filter { abs($0) <= span - 1 }
        return ([0] + offsets).sorted().map { estimate.chronologicalAge + $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let inset: CGFloat = 18
                let width = max(1, proxy.size.width - inset * 2)
                let x: (Double) -> CGFloat = { value in
                    CGFloat((min(upper, max(lower, value)) - lower) / (upper - lower)) * width
                }
                VStack(spacing: 0) {
                    track(width: width, x: x)
                    axis(x: x)
                }
                .frame(width: width)
                .padding(.horizontal, inset)
            }
            .frame(height: 86)
            legend
        }
        .onAppear { animate() }
        .onChange(of: estimate.age) { _, _ in animate() }
    }

    private func animate() {
        guard !reduceMotion else { progress = 1; return }
        progress = 0
        withAnimation(.smooth(duration: 0.8)) { progress = 1 }
    }

    /// The scale itself: graded zones, the uncertainty band, and the marker.
    private func track(width: CGFloat, x: (Double) -> CGFloat) -> some View {
        let centre = x(estimate.chronologicalAge)
        let markerX = centre + (x(estimate.age) - centre) * progress
        let bandStart = x(estimate.range.lowerBound)
        let bandWidth = max(6, x(estimate.range.upperBound) - bandStart)
        return ZStack(alignment: .topLeading) {
            // Zones, as discrete segments rather than one smeared gradient:
            // the boundary at the chronological age is the whole point and a
            // continuous ramp hid it.
            HStack(spacing: 2) {
                zone(AppColors.ageBetter, width: centre - 1)
                zone(AppColors.ageWorse, width: (width - centre) * 0.5 - 1)
                zone(AppColors.ageMuchWorse, width: (width - centre) * 0.5 - 1)
            }
            .frame(height: 12)
            .offset(y: 22)

            // Plausible range, drawn over the zones it spans.
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(AppColors.ink.opacity(0.22), lineWidth: 1))
                .frame(width: bandWidth * progress, height: 12)
                .offset(x: bandStart + bandWidth * (1 - progress) / 2, y: 22)

            // The chronological age: a full-height rule, the reference line.
            Rectangle()
                .fill(AppColors.ink.opacity(0.5))
                .frame(width: 1.5, height: 30)
                .offset(x: centre - 0.75, y: 13)

            // The estimate, with its value carried above the marker.
            VStack(spacing: 3) {
                Text(number(estimate.age, digits: 1))
                    .font(.caption2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(AppColors.ageTint(estimate.delta), in: Capsule())
                Circle()
                    .fill(AppColors.ageTint(estimate.delta))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .frame(width: 16, height: 16)
                    .shadow(color: AppColors.ageTint(estimate.delta).opacity(0.5), radius: 4)
            }
            .offset(x: markerX - 18, y: 0)
        }
        .frame(width: width, height: 56)
    }

    private func axis(x: (Double) -> CGFloat) -> some View {
        let placed = ticks.map { (age: $0, offset: x($0) - 12) }
        return ZStack(alignment: .topLeading) {
            ForEach(placed, id: \.age) { tick in
                let isChronological = abs(tick.age - estimate.chronologicalAge) < 0.5
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(AppColors.ink.opacity(isChronological ? 0.35 : 0.15))
                        .frame(width: 1, height: 4)
                    Text(number(tick.age))
                        .font(.caption2.weight(isChronological ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isChronological ? AppColors.ink : .secondary)
                }
                .frame(width: 24)
                .offset(x: tick.offset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 24)
    }

    private func zone(_ colour: Color, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(colour.opacity(0.55))
            .frame(width: max(0, width))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            item("ageYou", AppColors.ageTint(estimate.delta))
            item("ageChronological", AppColors.ink.opacity(0.5))
            item("ageUncertainty", AppColors.ink.opacity(0.22))
            Spacer(minLength: 0)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
    private func item(_ key: String, _ colour: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(L(key))
        }
    }
}

/// The headline number with its gap, sized and coloured by how far off it is.
struct BiologicalAgeHeadline: View {
    let estimate: WellnessAgeEstimate
    var onScene = false
    private var tint: Color { AppColors.ageTint(estimate.delta) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(number(estimate.age, digits: 1))
                    .font(.system(size: 56, weight: .bold))
                    .monospacedDigit().contentTransition(.numericText())
                Text(L("years")).font(.title3.weight(.medium)).opacity(0.75)
            }
            Spacer(minLength: 0)
            deltaChip
        }
    }

    private var deltaChip: some View {
        let years = abs(estimate.delta)
        let key = years < 0.5 ? "ageMatches" : estimate.delta < 0 ? "ageYearsYounger" : "ageYearsOlder"
        return HStack(spacing: 5) {
            if years >= 0.5 {
                Image(systemName: estimate.delta < 0 ? "arrow.down" : "arrow.up").font(.caption.weight(.bold))
            }
            Text(L(key).replacingOccurrences(of: "{0}", with: number(years, digits: 1)))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(onScene ? .white : tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background {
            if onScene { Capsule().fill(.ultraThinMaterial) } else { Capsule().fill(tint.opacity(0.14)) }
        }
        .fixedSize()
    }
}

extension AppColors {
    /// Below chronological age, matching it, above it, and well above it.
    /// Distinct from the brand accent so "younger" never reads as "Veyra".
    static let ageBetter = Color.adaptive(light: 0x2E7D4F, dark: 0x5FD98C)
    static let ageNeutral = Color.adaptive(light: 0xA8B0AE, dark: 0x6B7572)
    static let ageWorse = Color.adaptive(light: 0xC2691A, dark: 0xFF9E52)
    static let ageMuchWorse = Color.adaptive(light: 0xB3261E, dark: 0xFF6B61)

    /// Tint for a gap in years: negative is better, and "well above" starts at
    /// five years, which is roughly where the uncertainty band stops covering it.
    static func ageTint(_ delta: Double) -> Color {
        switch delta {
        case ..<(-0.5): ageBetter
        case ..<1.5: ageNeutral
        case ..<5: ageWorse
        default: ageMuchWorse
        }
    }
}
