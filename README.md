# VoiceTranslator — แอพแปลเสียงบนอุปกรณ์พร้อม PiP

แอพ iOS ที่แปลเสียงพูดแบบ real-time บนอุปกรณ์ (ไม่ต้องอินเทอร์เน็ต) และแสดงผลในหน้าต่าง PiP (Picture-in-Picture) แบบ floating

## ฟีเจอร์หลัก

- **On-Device Speech Recognition** — ใช้ `SFSpeechRecognizer` รู้จำเสียงบนอุปกรณ์โดยตรง
- **On-Device Translation** — ใช้ Apple Translation framework (iOS 17+) แปลโดยไม่ต้องอินเทอร์เน็ต
- **Auto Language Detection** — ตรวจจับภาษาต้นฉบับอัตโนมัติด้วย `NLLanguageRecognizer`
- **PiP Overlay** — หน้าต่างลอยที่แสดงคำแปลข้ามแอพได้
- **15+ ภาษา** — ไทย, อังกฤษ, จีน, ญี่ปุ่น, เกาหลี, ฝรั่งเศส, เยอรมัน, สเปน, รัสเซีย, อาหรับ ฯลฯ
- **ประวัติการแปล** — เก็บประวัติการแปลล่าสุด

## ความต้องการ

- **iOS 17.0+**
- **iPhone** (iPad รองรับบางส่วน)
- Xcode 15+

## วิธี Build ผ่าน GitHub Actions (สร้าง Unsigned IPA)

### ขั้นตอนที่ 1 — Push ขึ้น GitHub

```bash
git init
git add .
git commit -m "Initial commit: VoiceTranslator iOS app"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

### ขั้นตอนที่ 2 — รอ GitHub Actions

GitHub Actions จะรันอัตโนมัติบน macOS runner เมื่อ push ขึ้น branch `main`

ดูความคืบหน้าที่: `https://github.com/YOUR_USERNAME/YOUR_REPO/actions`

### ขั้นตอนที่ 3 — ดาวน์โหลด IPA

เมื่อ workflow เสร็จ ไปที่ Actions → เลือก run ล่าสุด → ดาวน์โหลด artifact `VoiceTranslator-unsigned-*`

## วิธีติดตั้ง Unsigned IPA

เนื่องจากเป็น unsigned IPA จะติดตั้งได้ด้วยวิธีเหล่านี้:

### วิธีที่ 1 — AltStore (แนะนำ)
1. ติดตั้ง [AltStore](https://altstore.io) บน iPhone
2. เปิด AltStore → My Apps → กด `+` → เลือกไฟล์ `.ipa`

### วิธีที่ 2 — Sideloadly
1. ดาวน์โหลด [Sideloadly](https://sideloadly.io) บน Mac/PC
2. เชื่อมต่อ iPhone
3. ลาก `.ipa` ไปใส่ Sideloadly แล้วกด Start

### วิธีที่ 3 — TrollStore (iOS 14-16.6.1)
1. ติดตั้ง [TrollStore](https://github.com/opa334/TrollStore)
2. Import ไฟล์ `.ipa` ผ่าน Files app

## โครงสร้างโปรเจกต์

```
ios-voice-translator/
├── project.yml                    # XcodeGen config
├── VoiceTranslator/
│   ├── App/
│   │   └── VoiceTranslatorApp.swift   # App entry point
│   ├── Managers/
│   │   ├── AppState.swift             # Global state
│   │   ├── SpeechManager.swift        # Speech recognition
│   │   ├── TranslationManager.swift   # Translation logic
│   │   └── PiPManager.swift           # PiP window management
│   ├── Views/
│   │   ├── ContentView.swift          # Main UI
│   │   └── SettingsView.swift         # Settings screen
│   └── Assets.xcassets/
└── .github/
    └── workflows/
        └── build-ipa.yml              # GitHub Actions build
```

## วิธีใช้ PiP

1. เปิดแอพ → อนุญาตสิทธิ์ไมโครโฟนและการรู้จำเสียง
2. กดปุ่ม **PiP** (⊞) มุมขวาบน เพื่อเปิดหน้าต่าง PiP
3. กดปุ่ม **ไมโครโฟน** เพื่อเริ่มพูด
4. คำแปลจะปรากฏในหน้าต่าง PiP แบบ floating
5. กด **Home** เพื่อซ่อนแอพ — PiP ยังแสดงผลอยู่
6. ลากหน้าต่าง PiP ไปวางตำแหน่งที่ต้องการ

## หมายเหตุ

- Apple Translation framework ต้องดาวน์โหลด language pack ครั้งแรกที่ใช้ (ต้องมีอินเทอร์เน็ตครั้งเดียว)
- หลังจากนั้นทำงานแบบ off-line ได้ทั้งหมด
- PiP ต้องอนุญาตใน Settings > General > Picture in Picture
