import AVKit
import AVFoundation
import UIKit

@MainActor
class PiPManager: NSObject, ObservableObject {
    @Published var isPiPActive = false
    @Published var isPiPAvailable = false
    @Published var isPiPPossible = false

    private var pipController: AVPictureInPictureController?
    private var displayLayer: AVSampleBufferDisplayLayer?

    private var currentOriginalText = ""
    private var currentTranslatedText = ""
    private var currentDetectedLanguage = ""
    private var currentTargetLanguage = ""

    override init() {
        super.init()
    }

    func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPiPAvailable = false
            return
        }
        isPiPAvailable = true

        activateAudioSession()

        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        self.displayLayer = layer

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )

        let pip = AVPictureInPictureController(contentSource: contentSource)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        self.pipController = pip

        pushBlankFrame()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isPiPPossible = pip.isPictureInPicturePossible
        }
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
        }
    }

    func updateContent(original: String, translated: String, detectedLang: String, targetLang: String) {
        currentOriginalText = original
        currentTranslatedText = translated
        currentDetectedLanguage = detectedLang
        currentTargetLanguage = targetLang
        pushFrame()
    }

    func startPiP() {
        activateAudioSession()
        pushFrame()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let pip = self.pipController else { return }
            if pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
            }
        }
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    private func pushBlankFrame() {
        currentTranslatedText = ""
        currentOriginalText = ""
        pushFrame()
    }

    private func pushFrame() {
        guard let layer = displayLayer else { return }

        let size = CGSize(width: 360, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            drawOverlay(in: ctx.cgContext, size: size)
        }

        guard let pixelBuffer = makePixelBuffer(from: image, size: size),
              let sampleBuffer = makeSampleBuffer(from: pixelBuffer) else { return }

        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sampleBuffer)
    }

    private func drawOverlay(in ctx: CGContext, size: CGSize) {
        let bg = UIColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 0.96)
        bg.setFill()
        let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
        path.fill()

        let accent = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1.0)
        accent.setFill()
        let bar = UIBezierPath(roundedRect: CGRect(x: 14, y: 14, width: 4, height: size.height - 28), cornerRadius: 2)
        bar.fill()

        let dim = UIColor(white: 0.55, alpha: 1.0)
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: dim
        ]

        if !currentDetectedLanguage.isEmpty {
            let langLine = "🌐 \(langName(currentDetectedLanguage)) → \(langName(currentTargetLanguage))"
            NSAttributedString(string: langLine, attributes: dimAttrs).draw(at: CGPoint(x: 26, y: 16))
        }

        if !currentOriginalText.isEmpty {
            let origAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor(white: 0.65, alpha: 1.0)
            ]
            let clipped = String(currentOriginalText.prefix(100))
            NSAttributedString(string: clipped, attributes: origAttrs)
                .draw(in: CGRect(x: 26, y: 38, width: size.width - 40, height: 34))
        }

        let sepPath = UIBezierPath()
        sepPath.move(to: CGPoint(x: 26, y: 82))
        sepPath.addLine(to: CGPoint(x: size.width - 14, y: 82))
        UIColor(white: 0.22, alpha: 1.0).setStroke()
        sepPath.lineWidth = 0.5
        sepPath.stroke()

        let transText = currentTranslatedText.isEmpty ? "รอการแปล..." : currentTranslatedText
        let transColor: UIColor = currentTranslatedText.isEmpty ? UIColor(white: 0.35, alpha: 1.0) : .white
        let transAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: transColor
        ]
        let clipped = String(transText.prefix(140))
        NSAttributedString(string: clipped, attributes: transAttrs)
            .draw(in: CGRect(x: 26, y: 92, width: size.width - 40, height: 92))
    }

    private func langName(_ code: String) -> String {
        Locale(identifier: "th").localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func makePixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var buf: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary, &buf
        ) == kCVReturnSuccess, let buf else { return nil }

        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1.0, y: -1.0)
        UIGraphicsPushContext(ctx)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()
        return buf
    }

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &fmt
        )
        guard let fmt else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        var sb: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleTiming: &timing,
            sampleBufferOut: &sb
        )
        return sb
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = true }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = false }
    }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {}
}

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize s: CMVideoDimensions) {}
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval i: CMTime, completion h: @escaping () -> Void) { h() }
}
