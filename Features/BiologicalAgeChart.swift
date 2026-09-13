import SwiftUI
import PulseCore

/// An age ruler rather than a bar with a dot on it. The axis carries real,
/// labelled ages so the number has somewhere to sit; the zones say what the
/// position means; the band shows how sure the estimate is.
///
/// Colour follows the gap, not the age: below chronological is green, above is
/// amber, well above is red. The chronological age itself is the boundary.
struct BiologicalAgeChart: View {
    let estimate: WellnessAgeEstimate
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
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                // Inset so the first and last tick labels are not clipped.
                let inset: CGFloat = 16
                let width = max(1, proxy.size.width - inset * 2)
                let x: (Double) -> CGFloat = { value in
                    CGFloat((min(upper, max(lower, value)) - lower) / (upper - lower)) * width
                }
                ZStack(alignment: .topLeading) {
                    zones(width: width, x: x)
                    chronologicalMarker(x: x)
                    uncertaintyBand(x: x)
                    estimateMarker(x: x)
                }
                .frame(width: width, height: 46)
                .overlay(alignment: .bottom) { tickLabels(x: x).frame(width: width, alignment: .topLeading) }
                .padding(.horizontal, inset)
            }
            .frame(height: 64)
            legend
        }
    }

    /// Green up to the chronological age, then amber, then red. The gradient
    /// stops are placed in age space so they line up with the ruler.
    private func zones(width: CGFloat, x: (Double) -> CGFloat) -> some View {
        let midpoint = Double(x(estimate.chronologicalAge) / max(1, width))
        let amberEnd = Double(x(estimate.chronologicalAge + span * 0.55) / max(1, width))
        return Capsule()
            .fill(LinearGradient(stops: [
                .init(color: AppColors.ageBetter, location: 0),
                .init(color: AppColors.ageBetter, location: max(0, midpoint - 0.03)),
                .init(color: AppColors.ageNeutral, location: midpoint),
                .init(color: AppColors.ageWorse, location: amberEnd),
                .init(color: AppColors.ageMuchWorse, location: 1)
            ], startPoint: .leading, endPoint: .trailing))
            .frame(height: 10)
            .opacity(0.85)
            .padding(.top, 12)
    }

    /// A full-height line: this is the reference everything is measured from.
    private func chronologicalMarker(x: (Double) -> CGFloat) -> some View {
        VStack(spacing: 2) {
            Capsule().fill(AppColors.ink.opacity(0.55)).frame(width: 2, height: 26)
        }
        .offset(x: x(estimate.chronologicalAge) - 1)
    }

    private func uncertaintyBand(x: (Double) -> CGFloat) -> some View {
        Capsule()
            .fill(AppColors.ink.opacity(0.18))
            .frame(width: max(4, x(estimate.range.upperBound) - x(estimate.range.lowerBound)), height: 10)
            .offset(x: x(estimate.range.lowerBound), y: 12)
    }

    private func estimateMarker(x: (Double) -> CGFloat) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(AppColors.ageTint(estimate.delta), lineWidth: 4))
            .frame(width: 20, height: 20)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .offset(x: x(estimate.age) - 10, y: 7)
    }

    private func tickLabels(x: (Double) -> CGFloat) -> some View {
        // Positions are resolved here rather than inside the builder, so no
        // closure has to escape into the view tree.
        let placed = ticks.map { (age: $0, offset: x($0) - 10) }
        return ZStack(alignment: .topLeading) {
            ForEach(placed, id: \.age) { tick in
                let isChronological = abs(tick.age - estimate.chronologicalAge) < 0.5
                Text(number(tick.age))
                    .font(.caption2.weight(isChronological ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(isChronological ? AppColors.ink : .secondary)
                    .fixedSize()
                    .offset(x: tick.offset)
            }
        }
        // Must span the ruler: a bare height leaves the stack sized to its
        // widest label, and every tick offset is then measured from the wrong
        // origin and drifts right.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 14)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            item("ageYou", AppColors.ageTint(estimate.delta))
            item("ageChronological", AppColors.ink.opacity(0.55))
            item("ageUncertainty", AppColors.ink.opacity(0.25))
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
