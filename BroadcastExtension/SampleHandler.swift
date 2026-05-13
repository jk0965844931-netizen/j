import ReplayKit
import Speech
import Foundation

class SampleHandler: RPBroadcastSampleHandler {

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let appGroupID = "group.com.voicetranslator.shared"
    private let newTextNotification = "com.voicetranslator.newText" as CFString
    private let broadcastEndedNotification = "com.voicetranslator.broadcastEnded" as CFString

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(true, forKey: "broadcastActive")
        defaults?.synchronize()
        startRecognition()
    }

    private func startRecognition() {
        let defaults = UserDefaults(suiteName: appGroupID)
        let localeID = defaults?.string(forKey: "sourceLocale") ?? "en-US"

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        speechRecognizer?.defaultTaskHint = .dictation

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest,
              let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                guard !text.isEmpty else { return }
                let isFinal = result.isFinal

                if let sharedDefaults = UserDefaults(suiteName: self.appGroupID) {
                    sharedDefaults.set(text, forKey: "recognizedText")
                    sharedDefaults.set(isFinal, forKey: "isFinal")
                    sharedDefaults.set(Date().timeIntervalSince1970, forKey: "lastUpdate")
                    sharedDefaults.synchronize()
                }

                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFNotificationName(self.newTextNotification),
                    nil, nil, true
                )

                if isFinal {
                    self.restartRecognition()
                }
            }

            if let error = error {
                let nsErr = error as NSError
                if nsErr.code != 301 && nsErr.code != 216 {
                    self.restartRecognition()
                }
            }
        }
    }

    private func restartRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startRecognition()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .audioApp:
            recognitionRequest?.appendAudioSampleBuffer(sampleBuffer)
        default:
            break
        }
    }

    override func broadcastPaused() {
        recognitionRequest?.endAudio()
    }

    override func broadcastResumed() {
        restartRecognition()
    }

    override func broadcastFinished() {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()

        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(false, forKey: "broadcastActive")
            defaults.set("", forKey: "recognizedText")
            defaults.synchronize()
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(broadcastEndedNotification),
            nil, nil, true
        )
    }
}
