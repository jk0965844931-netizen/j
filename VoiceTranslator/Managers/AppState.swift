import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var translatedText = ""
    @Published var detectedLanguage = ""
    @Published var targetLanguage = Locale.Language(identifier: "en")
    @Published var isPiPActive = false
    @Published var errorMessage: String?
    @Published var isTranslating = false
    @Published var translationHistory: [TranslationEntry] = []

    var targetLanguageCode: String {
        targetLanguage.languageCode?.identifier ?? "en"
    }

    var sourceLocaleIdentifier: String {
        UserDefaults.standard.string(forKey: "sourceLocale") ?? "en-US"
    }
}

struct TranslationEntry: Identifiable {
    let id = UUID()
    let originalText: String
    let translatedText: String
    let detectedLanguage: String
    let targetLanguage: String
    let timestamp: Date
}
