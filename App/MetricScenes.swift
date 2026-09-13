import SwiftUI
import PulseCore

/// Illustrated headers, one atmosphere per metric. Built from a mesh gradient
/// rather than stacked silhouettes: hard-edged shapes read as a collage, while
/// a mesh blends into a single painted field. No bitmaps, so there is nothing
/// to license, it scales to any card size, and each scene has a real light
/// rendition instead of a dark panel pasted onto a white screen.
enum MetricScene: String, CaseIterable {
    case recovery, strain, sleep, stress, energy

    /// Nine colours laid out as a 3×3 mesh: sky row, horizon row, ground row.
    var mesh: [Color] {
        switch self {
        case .recovery:
            [.adaptive(light: 0xCFEAF7, dark: 0x04202B), .adaptive(light: 0xDDF2F7, dark: 0x062832), .adaptive(light: 0xFAF3DC, dark: 0x123037),
             .adaptive(light: 0xDCF0E4, dark: 0x0A3A33), .adaptive(light: 0xE9F6E8, dark: 0x0D4439), .adaptive(light: 0xF6F3D8, dark: 0x14483C),
             .adaptive(light: 0xBFE3CB, dark: 0x0A2B26), .adaptive(light: 0xCDEAD4, dark: 0x0C332C), .adaptive(light: 0xDCEFD6, dark: 0x103A30)]
        case .strain:
            [.adaptive(light: 0xFFD9B5, dark: 0x2A1206), .adaptive(light: 0xFFE3C4, dark: 0x3A1806), .adaptive(light: 0xFFCFA0, dark: 0x4A2008),
             .adaptive(light: 0xFFC9A0, dark: 0x40200A), .adaptive(light: 0xFFD9B8, dark: 0x53290C), .adaptive(light: 0xFFB984, dark: 0x6B360E),
             .adaptive(light: 0xF3B98F, dark: 0x2C1607), .adaptive(light: 0xF7C9A4, dark: 0x361B08), .adaptive(light: 0xEFAF82, dark: 0x40200A)]
        case .sleep:
            [.adaptive(light: 0xC9D3F0, dark: 0x060A22), .adaptive(light: 0xD6DDF5, dark: 0x080E2C), .adaptive(light: 0xE3E4F7, dark: 0x0B1236),
             .adaptive(light: 0xBDC6EA, dark: 0x0C1440), .adaptive(light: 0xCBD2F0, dark: 0x101A4E), .adaptive(light: 0xDAD9F3, dark: 0x151F58),
             .adaptive(light: 0xA9B3DD, dark: 0x070C28), .adaptive(light: 0xB8C0E6, dark: 0x0A1132), .adaptive(light: 0xC6C9EC, dark: 0x0D163C)]
        case .stress:
            [.adaptive(light: 0xE7E2F0, dark: 0x160F1F), .adaptive(light: 0xEFEAF6, dark: 0x1C1428), .adaptive(light: 0xF2E6EC, dark: 0x241730),
             .adaptive(light: 0xDED6EC, dark: 0x281B38), .adaptive(light: 0xE9E1F3, dark: 0x322145), .adaptive(light: 0xF0DFE8, dark: 0x3A2450),
             .adaptive(light: 0xCFC5E2, dark: 0x150E1E), .adaptive(light: 0xDCD3EC, dark: 0x1B1226), .adaptive(light: 0xE6D6E2, dark: 0x21162E)]
        case .energy:
            [.adaptive(light: 0xFFE2D2, dark: 0x2A1408), .adaptive(light: 0xFFEBDD, dark: 0x33190A), .adaptive(light: 0xFFF0D8, dark: 0x3E1F0B),
             .adaptive(light: 0xFFD9BE, dark: 0x40240C), .adaptive(light: 0xFFE7CF, dark: 0x4E2D0E), .adaptive(light: 0xFFEFC8, dark: 0x5C3510),
             .adaptive(light: 0xF6C9A8, dark: 0x2C1708), .adaptive(light: 0xFBD9BC, dark: 0x351C09), .adaptive(light: 0xFCE4B4, dark: 0x3E220B)]
        }
    }
    /// The light source: sun, low sun, or moon. Rendered as a soft radial glow.
    var orb: Color {
        switch self {
        case .recovery: .adaptive(light: 0xFFE08A, dark: 0xFFE8A8)
        case .strain:   .adaptive(light: 0xFFA458, dark: 0xFFBE7A)
        case .sleep:    .adaptive(light: 0xFFFFFF, dark: 0xEDF0FF)
        case .stress:   .adaptive(light: 0xF0E7FA, dark: 0x9C86BC)
        case .energy:   .adaptive(light: 0xFFC978, dark: 0xFFB96A)
        }
    }
    /// Where the glow sits, as a fraction of the card.
    var orbPosition: UnitPoint {
        switch self {
        case .recovery: UnitPoint(x: 0.80, y: 0.20)
        case .strain:   UnitPoint(x: 0.78, y: 0.62)
        case .sleep:    UnitPoint(x: 0.80, y: 0.22)
        case .stress:   UnitPoint(x: 0.72, y: 0.34)
        case .energy:   UnitPoint(x: 0.76, y: 0.70)
        }
    }
    var showsStars: Bool { self == .sleep }

    init(_ metric: Metric) {
        switch metric {
        case .recovery: self = .recovery
        case .strain: self = .strain
        case .sleep: self = .sleep
        case .stress: self = .stress
        case .energy: self = .energy
        }
    }
}

extension MetricScene {
    /// The photograph behind the card. Public-domain landscapes, credited in
    /// Documentation/CREDITS.md, chosen to read as the metric at a glance:
    /// meadow, sunset ridge, night sky, storm front, dawn.
    var asset: String {
        switch self {
        case .recovery: "SceneRecovery"
        case .strain: "SceneStrain"
        case .sleep: "SceneSleep"
        case .stress: "SceneStress"
        case .energy: "SceneEnergy"
        }
    }
}

struct MetricSceneView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let scene: MetricScene
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // The mesh stays as the base: it fills instantly, matches the
                // photograph's palette, and covers the frame before the image
                // has decoded.
                MeshGradient(width: 3, height: 3, points: meshPoints, colors: scene.mesh)

                Image(scene.asset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()

                // Photographs are photographs in both appearances, so the text
                // on top is always light and the scrim is what guarantees it.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(reduceTransparency ? 0.72 : 0.62), location: 0),
                        .init(color: .black.opacity(reduceTransparency ? 0.52 : 0.38), location: 0.45),
                        .init(color: .black.opacity(0.22), location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.22)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    private let meshPoints: [SIMD2<Float>] = [
        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
        [0.0, 0.5], [0.62, 0.42], [1.0, 0.55],
        [0.0, 1.0], [0.45, 1.0], [1.0, 1.0]
    ]
}

struct StarField: View {
    private let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.22, 1.6), (0.17, 0.46, 1.1), (0.26, 0.14, 1.9), (0.34, 0.36, 1.2),
        (0.44, 0.20, 1.5), (0.52, 0.44, 1.0), (0.61, 0.16, 1.7), (0.90, 0.40, 1.3),
        (0.12, 0.62, 1.0), (0.68, 0.52, 1.1)
    ]
    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                Circle()
                    .frame(width: star.2, height: star.2)
                    .position(x: proxy.size.width * star.0, y: proxy.size.height * star.1)
            }
        }
    }
}

/// The page backdrop. Not flat white or flat black — that read as unfinished —
/// but a very low-contrast wash that still leaves the base pure at the centre,
/// so surfaces stay separated by border and elevation rather than by grey.
struct PageBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            AppColors.background
            MeshGradient(
                width: 2, height: 3,
                points: [[0, 0], [1, 0], [0, 0.5], [1, 0.45], [0, 1], [1, 1]],
                colors: colorScheme == .dark
                    ? [Color(red: 0.02, green: 0.10, blue: 0.09), Color(red: 0.04, green: 0.07, blue: 0.11),
                       .black, .black, .black, .black]
                    : [Color(red: 0.90, green: 0.98, blue: 0.96), Color(red: 0.95, green: 0.97, blue: 1.0),
                       .white, .white, .white, .white]
            )
            .opacity(colorScheme == .dark ? 0.75 : 0.9)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview("Scenes") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(MetricScene.allCases, id: \.rawValue) { scene in
                MetricSceneView(scene: scene)
                    .frame(height: 130)
                    .clipShape(.rect(cornerRadius: 24))
                    .overlay(alignment: .topLeading) {
                        Text(scene.rawValue).font(.headline).padding(16)
                    }
            }
        }.padding()
    }
    .background(PageBackdrop())
}
