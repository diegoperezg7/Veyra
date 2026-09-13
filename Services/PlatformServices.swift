import Foundation
import UserNotifications
import Vision
import PDFKit
import PulseCore

enum NotificationService {
    static func schedule(id: String, title: String, body: String, date: Date, repeats: Bool = false) async throws {
        guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else { throw CocoaError(.userCancelled) }
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        let fields: Set<Calendar.Component> = repeats ? [.hour, .minute] : [.year, .month, .day, .hour, .minute, .second]
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(fields, from: date), repeats: repeats)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    static func cancel(_ id: String) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
}
enum OCRService {
    static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["es", "en"]; request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
    static func documentText(_ data: Data, pdf: Bool) async throws -> String {
        if pdf {
            let text = await MainActor.run { PDFDocument(data: data)?.string ?? "" }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            let images: [Data] = await MainActor.run {
                guard let document = PDFDocument(data: data) else { return [] }
                return (0..<min(document.pageCount, 30)).compactMap { document.page(at: $0)?.thumbnail(of: CGSize(width: 1600, height: 2200), for: .mediaBox).pngData() }
            }
            var result: [String] = []
            for image in images { result.append(try await recognize(image)) }
            return result.joined(separator: "\n\n")
        }
        return try await recognize(data)
    }
}
