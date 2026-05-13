import Foundation
import NaturalLanguage

@MainActor
class TranslationManager: ObservableObject {
    private let languageDetector = NLLanguageRecognizer()

    var onTranslationComplete: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    func detectLanguage(from text: String) -> String {
        guard text.count > 2 else { return "th" }
        languageDetector.reset()
        languageDetector.processString(text)
        return languageDetector.dominantLanguage?.rawValue ?? "th"
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
