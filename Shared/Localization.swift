import Foundation
func L(_ key: String) -> String {
    let language = UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.current.language.languageCode?.identifier ?? "es"
    let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    return NSLocalizedString(key, bundle: bundle, comment: "")
}
func duration(_ minutes: Double) -> String { guard minutes.isFinite else { return "—" }; let rounded = max(0, Int(minutes.rounded())); return "\(rounded / 60)h \(rounded % 60)m" }
func number(_ value: Double?, digits: Int = 0) -> String { value.flatMap { $0.isFinite ? $0.formatted(.number.precision(.fractionLength(digits))) : nil } ?? "—" }
