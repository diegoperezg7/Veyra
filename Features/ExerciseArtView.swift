import SwiftUI
import PulseCore

/// Loads the exercise illustrations out of the bundle.
///
/// The files are alpha masks — the artwork's white paper was made transparent
/// when the catalogue was built — so they are drawn as template images and take
/// whatever colour the view asks for. One file therefore works in both
/// appearances, and the drawing belongs to Veyra's palette rather than sitting
/// on it as a foreign white rectangle.
@MainActor
enum ExerciseArt {
    // Drawing happens on the main actor, so the cache lives there too rather
    // than needing a lock of its own.
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "ExerciseArt"),
              let image = UIImage(contentsOfFile: url.path)?.withRenderingMode(.alwaysTemplate)
        else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

/// One exercise, drawn. `animated` alternates between the relaxed and
/// contracted frames, which shows the movement rather than a pose — the whole
/// reason the catalogue keeps both.
struct ExerciseArtView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var exercise: ExerciseDefinition
    var tint: Color = AppColors.ink
    var animated = false
    @State private var contracted = false

    private var frame: String? {
        guard exercise.art.count > 1 else { return exercise.art.first }
        return (animated && contracted && !reduceMotion) ? exercise.art[0] : exercise.art[1]
    }

    var body: some View {
        Group {
            if let frame, let image = ExerciseArt.image(frame) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(tint.opacity(0.4))
            }
        }
        .accessibilityHidden(true)
        .task(id: animated) {
            guard animated, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) { contracted.toggle() }
            }
        }
    }
}

/// The square thumbnail used in lists and grids.
struct ExerciseThumbnail: View {
    var exercise: ExerciseDefinition
    var size: CGFloat = 56
    var body: some View {
        ExerciseArtView(exercise: exercise, tint: AppColors.ink.opacity(0.82))
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background(AppColors.surfaceRaised, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// Names for the catalogue's coarse groups and equipment keys, so the filters
/// and the detail screen read in the user's language.
enum ExerciseVocabulary {
    static let groups = ["chest", "back", "shoulders", "arms", "legs", "core"]

    static func groupSymbol(_ group: String) -> String {
        switch group {
        case "chest": "figure.arms.open"
        case "back": "figure.rower"
        case "shoulders": "figure.boxing"
        case "arms": "dumbbell.fill"
        case "legs": "figure.walk"
        case "core": "figure.core.training"
        default: "figure.strengthtraining.traditional"
        }
    }
    static func equipmentSymbol(_ equipment: String) -> String {
        switch equipment {
        case "barbell", "ezbar", "bar": "figure.strengthtraining.traditional"
        case "dumbbell": "dumbbell.fill"
        case "cable": "cable.connector"
        case "machine", "smith": "gearshape.2.fill"
        case "band": "wave.3.right"
        case "ball": "circle.circle"
        case "bench": "bed.double.fill"
        case "plate": "circle.grid.cross"
        case "kettlebell": "bag.fill"
        default: "figure.mixed.cardio"
        }
    }
}
