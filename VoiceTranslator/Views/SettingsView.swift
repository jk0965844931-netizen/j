import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.07, blue: 0.12)
                    .ignoresSafeArea()

                List {
                    Section {
                        Picker("ภาษาเป้าหมาย", selection: Binding(
                            get: { appState.targetLanguageCode },
                            set: { newCode in
                                appState.targetLanguage = Locale.Language(identifier: newCode)
                            }
                        )) {
                            ForEach(TranslationManager.supportedTargetLanguages, id: \.code) { lang in
                                Text(lang.name)
                                    .tag(lang.code)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } header: {
                        Text("การแปล")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section {
                        InfoRow(label: "เวอร์ชัน", value: "1.0.0")
                        InfoRow(label: "iOS ต่ำสุด", value: "17.0")
                        InfoRow(label: "การแปล", value: "On-Device")
                        InfoRow(label: "การรู้จำเสียง", value: "On-Device")
                    } header: {
                        Text("เกี่ยวกับ")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("วิธีใช้ PiP")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("1. กดปุ่ม PiP (⊞) ที่มุมขวาบน\n2. กดปุ่มไมโครโฟนเพื่อเริ่มพูด\n3. หน้าต่าง PiP จะแสดงคำแปลแบบ floating\n4. สามารถย้ายหน้าต่างได้โดยการลาก\n5. กด Home เพื่อซ่อนแอพ PiP ยังทำงานต่อ")
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
