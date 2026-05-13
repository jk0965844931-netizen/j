import SwiftUI
import AVKit
import Translation

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var translationManager = TranslationManager()
    @StateObject private var pipManager = PiPManager()

    @State private var showSettings = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var hasPermissions = false
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var pendingText: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                VStack(spacing: 0) {
                    headerBar
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
                    saveHistory(
                        original: pendingText,
                        translated: response.targetText,
                        detected: detectedLang
                    )
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
            pipManager.setupPiP()
        }
        .onDisappear {
            if appState.isRecording { stopRecording() }
        }
    }

    // MARK: - Background

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

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceTranslator")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("แปลเสียงบนอุปกรณ์")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            HStack(spacing: 12) {
                if pipManager.isPiPAvailable {
                    Button {
                        pipManager.isPiPActive ? pipManager.stopPiP() : pipManager.startPiP()
                    } label: {
                        Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(pipManager.isPiPActive ? .blue : .white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                }
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

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                transcriptCard
                translationCard
                if !appState.translationHistory.isEmpty { historySection }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appState.isRecording ? Color.red : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
                .overlay {
                    if appState.isRecording {
                        Circle()
                            .stroke(Color.red.opacity(0.4), lineWidth: 2)
                            .scaleEffect(1.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: appState.isRecording)
                    }
                }
            Text(appState.isRecording ? "กำลังฟัง..." : "พร้อมฟัง")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(appState.isRecording ? .red : .white.opacity(0.5))
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
            Label("ข้อความต้นฉบับ", systemImage: "mic.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Text(appState.recognizedText.isEmpty ? "เริ่มพูดเพื่อแปล..." : appState.recognizedText)
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
        .background(LinearGradient(colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.blue.opacity(0.2), lineWidth: 0.5))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ประวัติการแปล").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button("ล้างประวัติ") { withAnimation { appState.translationHistory.removeAll() } }
                    .font(.system(size: 12)).foregroundStyle(.red.opacity(0.7))
            }
            ForEach(appState.translationHistory.prefix(10).reversed()) { entry in
                HistoryRow(entry: entry)
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 0) {
            Divider().background(.white.opacity(0.08))
            HStack {
                Spacer()
                if !hasPermissions {
                    Button { Task { await requestPermissions() } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.open.fill").font(.system(size: 22))
                            Text("ขอสิทธิ์").font(.system(size: 11))
                        }.foregroundStyle(.orange)
                    }
                } else {
                    Button { Task { await toggleRecording() } } label: {
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
                }
                Spacer()
            }
            .padding(.vertical, 16).padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Logic

    private func requestPermissions() async {
        hasPermissions = await speechManager.requestPermissions()
    }

    private func setupSpeechManager() {
        speechManager.onTranscript = { [weak appState] text, langCode in
            Task { @MainActor in
                appState?.recognizedText = text
                appState?.detectedLanguage = langCode
            }
            self.debouncedTranslate(text: text)
        }
        speechManager.onError = { [weak appState] error in
            Task { @MainActor in appState?.errorMessage = error }
        }
    }

    private func debouncedTranslate(text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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

    private func toggleRecording() async {
        appState.isRecording ? stopRecording() : await startRecording()
    }

    private func startRecording() async {
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

    private func stopRecording() {
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
