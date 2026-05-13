import Foundation

enum DiagnosticLogStore {
    private static let directoryName = "VoiceTranslatorLogs"
    private static let fileName = "voice-translator.log"
    private static let maxFileSizeBytes = 1_000_000
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var logFileURL: URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsURL.appendingPathComponent(directoryName, isDirectory: true).appendingPathComponent(fileName)
    }

    static var logFilePath: String {
        logFileURL?.path ?? "ไม่พบ Documents directory"
    }

    static func append(_ entry: DiagnosticLogEntry) {
        appendLine(format(entry))
    }

    static func appendRaw(_ message: String, level: DiagnosticLogEntry.Level = .info) {
        let entry = DiagnosticLogEntry(level: level, message: message, timestamp: Date())
        append(entry)
    }

    static func clear() {
        guard let url = logFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func appendLine(_ line: String) {
        guard let url = logFileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            rotateIfNeeded(at: url)
            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            print("[VoiceTranslator][ERROR] write log file failed: \(error.localizedDescription)")
        }
    }

    private static func rotateIfNeeded(at url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxFileSizeBytes else { return }

        let rotatedURL = url.deletingLastPathComponent().appendingPathComponent("voice-translator.previous.log")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: url, to: rotatedURL)
    }

    private static func format(_ entry: DiagnosticLogEntry) -> String {
        let timestamp = formatter.string(from: entry.timestamp)
        let level = entry.level.rawValue.uppercased()
        return "[\(timestamp)] [\(level)] \(entry.message)"
    }
}
