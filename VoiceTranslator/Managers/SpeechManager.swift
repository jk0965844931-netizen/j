import Foundation
import Speech
import AVFoundation
import NaturalLanguage

@MainActor
class SpeechManager: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentRecognizer: SFSpeechRecognizer?
    private let languageDetector = NLLanguageRecognizer()

    var onTranscript: ((String, String) -> Void)?
    var onError: ((String) -> Void)?

    private let supportedLocales: [Locale] = [
        Locale(identifier: "th-TH"),
        Locale(identifier: "en-US"),
        Locale(identifier: "zh-Hans"),
        Locale(identifier: "ja-JP"),
        Locale(identifier: "ko-KR"),
        Locale(identifier: "fr-FR"),
        Locale(identifier: "de-DE"),
        Locale(identifier: "es-ES"),
        Locale(identifier: "ru-RU"),
        Locale(identifier: "ar-SA"),
    ]

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        let micStatus = await AVAudioApplication.requestRecordPermission()
        return micStatus
    }

    func startRecording(sourceLocaleIdentifier: String) async throws {
        stopRecording()

        let locale = Locale(identifier: sourceLocaleIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }
        recognizer.defaultTaskHint = .dictation
        currentRecognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = true
        request.contextualStrings = []
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let transcript = result.bestTranscription.formattedString
                Task { @MainActor in
                    let detectedLang = self.detectLanguage(from: transcript)
                    self.onTranscript?(transcript, detectedLang)
                }
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                    Task { @MainActor in
                        self.onError?(error.localizedDescription)
                    }
                }
            }
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        currentRecognizer = nil
    }

    private func detectLanguage(from text: String) -> String {
        guard text.count > 3 else { return "th" }
        languageDetector.reset()
        languageDetector.processString(text)
        return languageDetector.dominantLanguage?.rawValue ?? "th"
    }

    func bestRecognizer(for languageCode: String) -> SFSpeechRecognizer? {
        let matching = supportedLocales.first { locale in
            locale.language.languageCode?.identifier == languageCode
        }
        guard let locale = matching else { return SFSpeechRecognizer(locale: Locale(identifier: "th-TH")) }
        return SFSpeechRecognizer(locale: locale)
    }
}

enum SpeechError: LocalizedError {
    case recognizerUnavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "ไม่สามารถเริ่มการรู้จำเสียงได้"
        case .permissionDenied: return "ไม่ได้รับสิทธิ์การใช้ไมโครโฟนหรือการรู้จำเสียง"
        }
    }
}
