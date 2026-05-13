import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var translatedText = ""
    @Published var detectedLanguage = ""
    @Published var targetLanguage = Locale.Language(identifier: "th")
    @Published var sourceLocaleIdentifier = UserDefaults.standard.string(forKey: "sourceLocale") ?? "en-US" {
        didSet { UserDefaults.standard.set(sourceLocaleIdentifier, forKey: "sourceLocale") }
    }
    @Published var isPiPActive = false
    @Published var errorMessage: String?
    @Published var isTranslating = false
    @Published var translationHistory: [TranslationEntry] = []
    @Published var diagnosticLogs: [DiagnosticLogEntry] = []

    var targetLanguageCode: String {
        targetLanguage.languageCode?.identifier ?? "en"
    }

    func addLog(_ message: String, level: DiagnosticLogEntry.Level = .info) {
        let entry = DiagnosticLogEntry(level: level, message: message, timestamp: Date())
        diagnosticLogs.append(entry)
        if diagnosticLogs.count > 80 {
            diagnosticLogs.removeFirst(diagnosticLogs.count - 80)
        }
        print("[VoiceTranslator][\(level.rawValue.uppercased())] \(message)")
    }

    func clearLogs() {
        diagnosticLogs.removeAll()
        addLog("ล้าง log แล้ว")
    }
}

struct DiagnosticLogEntry: Identifiable {
    enum Level: String {
        case info
        case warning
        case error
    }

    let id = UUID()
    let level: Level
    let message: String
    let timestamp: Date
}

struct TranslationEntry: Identifiable {
    let id = UUID()
    let originalText: String
    let translatedText: String
    let detectedLanguage: String
    let targetLanguage: String
    let timestamp: Date
}
