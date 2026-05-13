import SwiftUI
import AVKit
import Translation
import ReplayKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var translationManager = TranslationManager()
    @StateObject private var pipManager = PiPManager()
    @StateObject private var broadcastManager = BroadcastManager()

    @State private var showSettings = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var hasPermissions = false
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var pendingText: String = ""
    @State private var captureMode: CaptureMode = .systemAudio

    enum CaptureMode {
        case microphone, systemAudio
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                VStack(spacing: 0) {
                    headerBar
                    modeSelector
                    mainContent
                    controlBar
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(appState)
        }
        .translationTask(translationConfig) { session in
            guard !pendingText.isEmpty else { return }
            do {
                let response = try await session.translate(pendingText)
                let detectedLang = translationManager.detectLanguage(from: pendingText)
                await MainActor.run {
                    appState.translatedText = response.targetText
                    appState.isTranslating = false
                    appState.detectedLanguage = detectedLang
                    pipManager.updateContent(
                        original: pendingText,
                        translated: response.targetText,
                        detectedLang: detectedLang,
                        targetLang: appState.targetLanguageCode
                    )
                    saveHistory(original: pendingText, translated: response.targetText, detected: detectedLang)
                }
            } catch {
                await MainActor.run {
                    appState.isTranslating = false
                    appState.errorMessage = error.localizedDescription
                }
            }
        }
        .task {
            await requestPermissions()
            setupSpeechManager()
            setupBroadcastManager()
            pipManager.setupPiP()
        }
        .onDisappear {
            if appState.isRecording { stopMicRecording() }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.10),
                Color(red: 0.06, green: 0.09, blue: 0.16),
                Color(red: 0.04, green: 0.06, blue: 0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceTranslator")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("แปลเสียงแบบเรียลไทม์")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            HStack(spacing: 12) {
                pipButton
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.08), in: Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var pipButton: some View {
        if pipManager.isPiPAvailable {
            Button {
                if pipManager.isPiPActive {
                    pipManager.stopPiP()
                } else {
                    pipManager.startPiP()
                }
            } label: {
                Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(pipManager.isPiPActive ? .blue : .white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: Circle())
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 0) {
            modePill(
                title: "เสียงระบบ",
                icon: "play.tv.fill",
                mode: .systemAudio,
                active: captureMode == .systemAudio
            )
            modePill(
                title: "ไมโครโฟน",
                icon: "mic.fill",
                mode: .microphone,
                active: captureMode == .microphone
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func modePill(title: String, icon: String, mode: CaptureMode, active: Bool) -> some View {
        Button {
            if mode != captureMode {
                if appState.isRecording { stopMicRecording() }
                captureMode = mode
                appState.recognizedText = ""
                appState.translatedText = ""
                appState.detectedLanguage = ""
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(active ? .white : .white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? Color.blue.opacity(0.25) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(active ? Color.blue.opacity(0.6) : Color.white.opacity(0.1), lineWidth: active ? 1 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 4)
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                if captureMode == .systemAudio {
                    systemAudioInfoCard
                }
                transcriptCard
                translationCard
                if !appState.translationHistory.isEmpty { historySection }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }

    private var systemAudioInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: broadcastManager.isBroadcasting ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(broadcastManager.isBroadcasting ? .red : .white.opacity(0.5))
                Text(broadcastManager.isBroadcasting ? "กำลังจับเสียงจากระบบ..." : "กด ปุ่มด้านล่างเพื่อเริ่มจับเสียง")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(broadcastManager.isBroadcasting ? .red : .white.opacity(0.6))
            }
            Text("แอพจะแปลเสียงจาก YouTube, Netflix และแอพอื่นๆ แบบเรียลไทม์")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(broadcastManager.isBroadcasting ? Color.red.opacity(0.3) : Color.white.opacity(0.07), lineWidth: 0.5)
        )
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            let isActive = captureMode == .microphone ? appState.isRecording : broadcastManager.isBroadcasting
            Circle()
                .fill(isActive ? Color.red : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
                .overlay {
                    if isActive {
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 2)
                            .scaleEffect(1.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: isActive)
                    }
                }
            Text(isActive ? "กำลังฟัง..." : "พร้อมฟัง")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .red : .white.opacity(0.5))
            Spacer()
            if !appState.detectedLanguage.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.microphone").font(.system(size: 11))
                    Text(appState.detectedLanguage.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.blue.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.blue.opacity(0.12), in: Capsule())
            }
            if appState.isTranslating {
                ProgressView().progressViewStyle(.circular).scaleEffect(0.7).tint(.white)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right").font(.system(size: 10))
                    Text(appState.targetLanguageCode.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.green.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.green.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ต้นฉบับ", systemImage: "mic.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Text(appState.recognizedText.isEmpty ? "เริ่มเพื่อแปล..." : appState.recognizedText)
                .font(.system(size: 16))
                .foregroundStyle(appState.recognizedText.isEmpty ? .white.opacity(0.25) : .white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: appState.recognizedText)
        }
        .padding(16)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 0.5))
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("คำแปล", systemImage: "text.bubble.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.blue.opacity(0.7))
                Spacer()
                if !appState.translatedText.isEmpty {
                    Button { UIPasteboard.general.string = appState.translatedText } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Text(appState.translatedText.isEmpty ? "ผลการแปลจะแสดงที่นี่..." : appState.translatedText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(appState.translatedText.isEmpty ? .white.opacity(0.2) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: appState.translatedText)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.blue.opacity(0.2), lineWidth: 0.5))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ประวัติ").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button("ล้าง") { withAnimation { appState.translationHistory.removeAll() } }
                    .font(.system(size: 12)).foregroundStyle(.red.opacity(0.7))
            }
            ForEach(appState.translationHistory.prefix(10).reversed()) { entry in
                HistoryRow(entry: entry)
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 0) {
            Divider().background(.white.opacity(0.08))
            HStack(spacing: 32) {
                Spacer()
                if captureMode == .systemAudio {
                    systemAudioControl
                } else {
                    microphoneControl
                }
                Spacer()
            }
            .padding(.vertical, 16).padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var systemAudioControl: some View {
        VStack(spacing: 6) {
            BroadcastPickerView(bundleID: "com.voicetranslator.app.broadcast")
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(broadcastManager.isBroadcasting ? Color.red.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 2)
                )
                .shadow(color: broadcastManager.isBroadcasting ? .red.opacity(0.4) : .clear, radius: 10)
            Text(broadcastManager.isBroadcasting ? "กำลังจับเสียง" : "จับเสียงระบบ")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var microphoneControl: some View {
        VStack(spacing: 6) {
            Button { Task { await toggleMicRecording() } } label: {
                ZStack {
                    Circle()
                        .fill(appState.isRecording ? Color.red : Color.blue)
                        .frame(width: 64, height: 64)
                        .shadow(color: (appState.isRecording ? Color.red : Color.blue).opacity(0.5), radius: 12)
                    if appState.isRecording {
                        RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "mic.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    }
                }
            }
            .scaleEffect(appState.isRecording ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: appState.isRecording)
            Text(appState.isRecording ? "หยุด" : "เริ่มพูด")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func requestPermissions() async {
        hasPermissions = await speechManager.requestPermissions()
    }

    private func setupSpeechManager() {
        speechManager.onTranscript = { text, langCode in
            Task { @MainActor in
                appState.recognizedText = text
                appState.detectedLanguage = langCode
                self.debouncedTranslate(text: text)
            }
        }
        speechManager.onError = { error in
            Task { @MainActor in appState.errorMessage = error }
        }
    }

    private func setupBroadcastManager() {
        broadcastManager.setSourceLocale(appState.sourceLocaleIdentifier)
        broadcastManager.onTextReceived = { text, isFinal in
            Task { @MainActor in
                appState.recognizedText = text
                if isFinal || text.count > 30 {
                    self.debouncedTranslate(text: text)
                }
            }
        }
    }

    private func debouncedTranslate(text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await MainActor.run {
                appState.isTranslating = true
                pendingText = text
                let detectedLang = translationManager.detectLanguage(from: text)
                let sourceLang = Locale.Language(identifier: detectedLang)
                translationConfig = TranslationSession.Configuration(
                    source: sourceLang,
                    target: appState.targetLanguage
                )
            }
        }
    }

    private func saveHistory(original: String, translated: String, detected: String) {
        guard !original.isEmpty, !translated.isEmpty else { return }
        let entry = TranslationEntry(
            originalText: original,
            translatedText: translated,
            detectedLanguage: detected,
            targetLanguage: appState.targetLanguageCode,
            timestamp: Date()
        )
        appState.translationHistory.append(entry)
        if appState.translationHistory.count > 50 { appState.translationHistory.removeFirst() }
    }

    private func toggleMicRecording() async {
        appState.isRecording ? stopMicRecording() : await startMicRecording()
    }

    private func startMicRecording() async {
        appState.recognizedText = ""
        appState.translatedText = ""
        appState.detectedLanguage = ""
        appState.isRecording = true
        do {
            try await speechManager.startRecording()
        } catch {
            appState.isRecording = false
            appState.errorMessage = error.localizedDescription
        }
    }

    private func stopMicRecording() {
        speechManager.stopRecording()
        appState.isRecording = false
    }
}

struct HistoryRow: View {
    let entry: TranslationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.detectedLanguage.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2), in: Capsule())
                Image(systemName: "arrow.right").font(.system(size: 9))
                Text(entry.targetLanguage.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                Spacer()
                Text(entry.timestamp, style: .time).font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
            }
            .foregroundStyle(.white.opacity(0.5))
            Text(entry.originalText).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            Text(entry.translatedText).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
