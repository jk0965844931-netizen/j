import SwiftUI
import AVFoundation

@main
struct VoiceTranslatorApp: App {
    @StateObject private var appState = AppState()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setActive(true)
            DiagnosticLogStore.appendRaw("App audio session configured")
        } catch {
            print("Audio session error: \(error)")
            DiagnosticLogStore.appendRaw("App audio session error: \(error.localizedDescription)", level: .error)
        }
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = windowScene.keyWindow
    }
}
