import Foundation
import ReplayKit
import SwiftUI
import UIKit

@MainActor
class BroadcastManager: ObservableObject {
    @Published var isBroadcasting = false

    var onTextReceived: ((String, Bool) -> Void)?

    private let appGroupID = "group.com.voicetranslator.shared"
    private let newTextKey = "com.voicetranslator.newText" as CFString
    private let endedKey = "com.voicetranslator.broadcastEnded" as CFString

    init() {
        registerDarwinObservers()
        checkBroadcastState()
    }

    private func checkBroadcastState() {
        let defaults = UserDefaults(suiteName: appGroupID)
        isBroadcasting = defaults?.bool(forKey: "broadcastActive") ?? false
    }

    func setSourceLocale(_ identifier: String) {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.set(identifier, forKey: "sourceLocale")
        defaults?.synchronize()
    }

    private func registerDarwinObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())

        CFNotificationCenterAddObserver(
            center, ptr,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let mgr = Unmanaged<BroadcastManager>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { mgr.handleNewText() }
            },
            newTextKey, nil, .deliverImmediately
        )

        CFNotificationCenterAddObserver(
            center, ptr,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let mgr = Unmanaged<BroadcastManager>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { mgr.isBroadcasting = false }
            },
            endedKey, nil, .deliverImmediately
        )
    }

    private func handleNewText() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let text = defaults.string(forKey: "recognizedText") ?? ""
        let isFinal = defaults.bool(forKey: "isFinal")
        guard !text.isEmpty else { return }
        isBroadcasting = true
        onTextReceived?(text, isFinal)
    }
}

struct BroadcastPickerView: UIViewRepresentable {
    let bundleID: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        picker.preferredExtension = bundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
