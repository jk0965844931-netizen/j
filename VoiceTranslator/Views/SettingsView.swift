import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    static let sourceLocales: [(id: String, name: String)] = [
        ("en-US", "🇺🇸 อังกฤษ (US)"),
        ("en-GB", "🇬🇧 อังกฤษ (UK)"),
        ("th-TH", "🇹🇭 ไทย"),
        ("zh-Hans", "🇨🇳 จีน (กลาง)"),
        ("zh-Hant", "🇹🇼 จีน (ดั้งเดิม)"),
        ("ja-JP", "🇯🇵 ญี่ปุ่น"),
        ("ko-KR", "🇰🇷 เกาหลี"),
        ("fr-FR", "🇫🇷 ฝรั่งเศส"),
        ("de-DE", "🇩🇪 เยอรมัน"),
        ("es-ES", "🇪🇸 สเปน"),
        ("ru-RU", "🇷🇺 รัสเซีย"),
        ("ar-SA", "🇸🇦 อาหรับ"),
        ("vi-VN", "🇻🇳 เวียดนาม"),
        ("id-ID", "🇮🇩 อินโดนีเซีย"),
        ("pt-BR", "🇧🇷 โปรตุเกส"),
        ("it-IT", "🇮🇹 อิตาลี"),
        ("hi-IN", "🇮🇳 ฮินดี"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.12)
                    .ignoresSafeArea()

                List {
                    Section {
                        Picker("ภาษาต้นฉบับ (เสียงที่ฟัง)", selection: $appState.sourceLocaleIdentifier) {
                            ForEach(Self.sourceLocales, id: \.id) { lang in
                                Text(lang.name).tag(lang.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .foregroundStyle(.white.opacity(0.85))
                        Picker("ภาษาเป้าหมาย (คำแปล)", selection: Binding(
                            get: { appState.targetLanguageCode },
                            set: { newCode in
                                appState.targetLanguage = Locale.Language(identifier: newCode)
                            }
                        )) {
                            ForEach(TranslationManager.supportedTargetLanguages, id: \.code) { lang in
                                Text(lang.name).tag(lang.code)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .foregroundStyle(.white.opacity(0.85))
                    } header: {
                        Text("ภาษา")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section {
                        InfoRow(label: "เวอร์ชัน", value: "1.0.0")
                        InfoRow(label: "iOS ต่ำสุด", value: "18.0")
                        InfoRow(label: "การแปล", value: "On-Device")
                        InfoRow(label: "การรู้จำเสียง", value: "On-Device")
                    } header: {
                        Text("เกี่ยวกับ")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("วิธีใช้ จับเสียงระบบ")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("1. เลือกโหมด \"เสียงระบบ\"\n2. กดปุ่ม Screen Record (วงกลมแดง)\n3. เลือก VoiceTranslator Broadcast\n4. กด \"เริ่ม\" แล้วกลับไปแอพที่ต้องการ\n5. เปิด YouTube / Netflix ตามปกติ\n6. กดปุ่ม PiP ⊞ เพื่อแสดงคำแปลลอยทับหน้าจอ")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("วิธีใช้ ไมโครโฟน")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("1. เลือกโหมด \"ไมโครโฟน\"\n2. กดปุ่มไมโครโฟนสีน้ำเงิน\n3. พูดภาษาที่เลือกไว้\n4. คำแปลจะแสดงแบบ real-time\n5. กดปุ่ม PiP ⊞ เพื่อแสดงคำแปลลอยทับ")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("คำแนะนำ")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("ตั้งค่า")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("เสร็จสิ้น") { dismiss() }
                        .foregroundStyle(.blue)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.45))
        }
        .font(.system(size: 14))
    }
}
