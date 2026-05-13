import Foundation
import Translation
import NaturalLanguage

@MainActor
class TranslationManager: ObservableObject {
    private let languageDetector = NLLanguageRecognizer()

    var onTranslationComplete: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    private var translationSession: TranslationSession?

    func translate(text: String, to targetLanguage: Locale.Language) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let detectedLang = detectLanguage(from: text)
        let sourceLang = Locale.Language(identifier: detectedLang)

        if sourceLang.languageCode?.identifier == targetLanguage.languageCode?.identifier {
            onTranslationComplete?(text, detectedLang)
            return
        }

        let config = TranslationSession.Configuration(source: sourceLang, target: targetLanguage)

        do {
            let session = TranslationSession(configuration: config)
            let response = try await session.translate(text)
            onTranslationComplete?(response.targetText, detectedLang)
        } catch {
            onError?("การแปลล้มเหลว: \(error.localizedDescription)")
        }
    }

    func detectLanguage(from text: String) -> String {
        guard text.count > 2 else { return "th" }
        languageDetector.reset()
        languageDetector.processString(text)

        let dominant = languageDetector.dominantLanguage?.rawValue ?? "th"
        return dominant
    }

    func languageDisplayName(for code: String) -> String {
        let locale = Locale(identifier: "th")
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    static let supportedTargetLanguages: [(code: String, name: String)] = [
        ("en", "อังกฤษ"),
        ("th", "ไทย"),
        ("zh", "จีน (กลาง)"),
        ("ja", "ญี่ปุ่น"),
        ("ko", "เกาหลี"),
        ("fr", "ฝรั่งเศส"),
        ("de", "เยอรมัน"),
        ("es", "สเปน"),
        ("ru", "รัสเซีย"),
        ("ar", "อาหรับ"),
        ("vi", "เวียดนาม"),
        ("id", "อินโดนีเซีย"),
        ("pt", "โปรตุเกส"),
        ("it", "อิตาลี"),
        ("hi", "ฮินดี"),
    ]
}
