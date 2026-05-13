import SwiftUI
import AVKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var translationManager = TranslationManager()
    @StateObject private var pipManager = PiPManager()

    @State private var showSettings = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var pipContainerView: UIView?
    @State private var hasPermissions = false

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
            SettingsView()
                .environmentObject(appState)
        }
        .task {
            await requestPermissions()
            setupManagers()
            pipManager.setupPiP()
        }
        .onDisappear {
            if appState.isRecording {
                stopRecording()
            }
        }
    }

    // MARK: - Subviews

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
                Text("แปลเสียงบนอุปกรณ์")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            HStack(spacing: 12) {
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
                            .foregroundStyle(pipManager.isPiPActive ? Color.blue : .white.opacity(0.8))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                }

                Button {
                    showSettings = true
                } label: {
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

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard
                transcriptCard
                translationCard
                historySection
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
                            .scaleEffect(appState.isRecording ? 1.8 : 1)
                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: appState.isRecording)
                    }
                }

            Text(appState.isRecording ? "กำลังฟัง..." : "พร้อมฟัง")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(appState.isRecording ? .red : .white.opacity(0.5))

            Spacer()

            if !appState.detectedLanguage.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.badge.microphone")
                        .font(.system(size: 11))
                    Text(appState.detectedLanguage.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.blue.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12), in: Capsule())
            }

            if !appState.isTranslating {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                    Text(appState.targetLanguageCode.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.green.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.10), in: Capsule())
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ข้อความต้นฉบับ", systemImage: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(appState.recognizedText.isEmpty ? "เริ่มพูดเพื่อแปล..." : appState.recognizedText)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(appState.recognizedText.isEmpty ? .white.opacity(0.25) : .white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: appState.recognizedText)
        }
        .padding(16)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 0.5)
        )
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("คำแปล", systemImage: "text.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue.opacity(0.7))

                Spacer()

                if !appState.translatedText.isEmpty {
                    Button {
                        UIPasteboard.general.string = appState.translatedText
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Text(appState.translatedText.isEmpty ? "ผลการแปลจะแสดงที่นี่..." : appState.translatedText)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(appState.translatedText.isEmpty ? .white.opacity(0.2) : .white)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: appState.translatedText)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.12), Color.blue.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var historySection: some View {
        Group {
            if !appState.translationHistory.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ประวัติการแปล")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Button("ล้างประวัติ") {
                            withAnimation { appState.translationHistory.removeAll() }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                    }

                    ForEach(appState.translationHistory.prefix(10).reversed()) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 0) {
            Divider().background(.white.opacity(0.08))

            HStack(spacing: 24) {
                Spacer()

                if !hasPermissions {
                    Button {
                        Task { await requestPermissions() }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 22, weight: .medium))
                            Text("ขอสิทธิ์")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.orange)
                    }
                } else {
                    Button {
                        Task { await toggleRecording() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(appState.isRecording ? Color.red : Color.blue)
                                .frame(width: 64, height: 64)
                                .shadow(color: (appState.isRecording ? Color.red : Color.blue).opacity(0.5), radius: 12)

                            if appState.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.white)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .scaleEffect(appState.isRecording ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3), value: appState.isRecording)
                }

                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Logic

    private func requestPermissions() async {
        hasPermissions = await speechManager.requestPermissions()
    }

    private func setupManagers() {
        speechManager.onTranscript = { [weak appState] text, langCode in
            guard let appState else { return }
            Task { @MainActor in
                appState.recognizedText = text
                appState.detectedLanguage = langCode
            }
            debouncedTranslate(text: text)
        }

        speechManager.onError = { [weak appState] error in
            Task { @MainActor in appState?.errorMessage = error }
        }

        translationManager.onTranslationComplete = { [weak appState, weak pipManager] translated, detectedLang in
            Task { @MainActor in
                guard let appState else { return }
                appState.translatedText = translated
                appState.isTranslating = false

                let original = appState.recognizedText
                let targetCode = appState.targetLanguageCode

                pipManager?.updateContent(
                    original: original,
                    translated: translated,
                    detectedLang: detectedLang,
                    targetLang: targetCode
                )

                if !original.isEmpty && !translated.isEmpty {
                    let entry = TranslationEntry(
                        originalText: original,
                        translatedText: translated,
                        detectedLanguage: detectedLang,
                        targetLanguage: targetCode,
                        timestamp: Date()
                    )
                    appState.translationHistory.append(entry)
                    if appState.translationHistory.count > 50 {
                        appState.translationHistory.removeFirst()
                    }
                }
            }
        }

        translationManager.onError = { [weak appState] error in
            Task { @MainActor in
                appState?.isTranslating = false
                appState?.errorMessage = error
            }
        }
    }

    private func debouncedTranslate(text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await MainActor.run { appState.isTranslating = true }
            await translationManager.translate(text: text, to: appState.targetLanguage)
        }
    }

    private func toggleRecording() async {
        if appState.isRecording {
            stopRecording()
        } else {
            await startRecording()
        }
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2), in: Capsule())

                Image(systemName: "arrow.right")
                    .font(.system(size: 9))

                Text(entry.targetLanguage.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())

                Spacer()

                Text(entry.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .foregroundStyle(.white.opacity(0.5))

            Text(entry.originalText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            Text(entry.translatedText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
