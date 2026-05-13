import AVKit
import UIKit
import SwiftUI

@MainActor
class PiPManager: NSObject, ObservableObject {
    @Published var isPiPActive = false
    @Published var isPiPAvailable = false

    private var pipController: AVPictureInPictureController?
    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    private var pipContentView: UIView?
    private var containerView: UIView?

    private var currentOriginalText = ""
    private var currentTranslatedText = ""
    private var currentDetectedLanguage = ""
    private var currentTargetLanguage = ""

    override init() {
        super.init()
        isPiPAvailable = AVPictureInPictureController.isPictureInPictureSupported()
    }

    func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let displayLayer = AVSampleBufferDisplayLayer()
        displayLayer.videoGravity = .resizeAspect
        self.sampleBufferDisplayLayer = displayLayer

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let pip = AVPictureInPictureController(contentSource: contentSource)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = pip
    }

    func updateContent(original: String, translated: String, detectedLang: String, targetLang: String) {
        currentOriginalText = original
        currentTranslatedText = translated
        currentDetectedLanguage = detectedLang
        currentTargetLanguage = targetLang

        pushFrameToLayer()
    }

    func startPiP() {
        guard let pipController, pipController.isPictureInPicturePossible else { return }
        pushFrameToLayer()
        pipController.startPictureInPicture()
    }

    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    private func pushFrameToLayer() {
        guard let layer = sampleBufferDisplayLayer else { return }

        let size = CGSize(width: 360, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            drawOverlayContent(in: ctx.cgContext, size: size)
        }

        guard let pixelBuffer = createPixelBuffer(from: image, size: size),
              let sampleBuffer = createSampleBuffer(from: pixelBuffer) else { return }

        layer.enqueue(sampleBuffer)
    }

    private func drawOverlayContent(in context: CGContext, size: CGSize) {
        let bgColor = UIColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.95)
        bgColor.setFill()
        let bgRect = CGRect(origin: .zero, size: size)
        let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 16)
        bgPath.fill()

        let accentColor = UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1.0)
        let indicatorRect = CGRect(x: 16, y: 16, width: 4, height: size.height - 32)
        let indicatorPath = UIBezierPath(roundedRect: indicatorRect, cornerRadius: 2)
        accentColor.setFill()
        indicatorPath.fill()

        let langText = currentDetectedLanguage.isEmpty ? "" : "🌐 \(langDisplayName(currentDetectedLanguage)) → \(langDisplayName(currentTargetLanguage))"
        let langAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor(white: 0.6, alpha: 1.0)
        ]
        let langStr = NSAttributedString(string: langText, attributes: langAttrs)
        langStr.draw(at: CGPoint(x: 28, y: 18))

        if !currentOriginalText.isEmpty {
            let origAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: UIColor(white: 0.72, alpha: 1.0)
            ]
            let clampedOrig = String(currentOriginalText.prefix(80))
            let origStr = NSAttributedString(string: clampedOrig, attributes: origAttrs)
            let origRect = CGRect(x: 28, y: 40, width: size.width - 44, height: 36)
            origStr.draw(in: origRect)
        }

        let separator = UIBezierPath()
        separator.move(to: CGPoint(x: 28, y: 84))
        separator.addLine(to: CGPoint(x: size.width - 16, y: 84))
        UIColor(white: 0.25, alpha: 1.0).setStroke()
        separator.lineWidth = 0.5
        separator.stroke()

        let transText = currentTranslatedText.isEmpty ? "รอการแปล..." : currentTranslatedText
        let transAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let clampedTrans = String(transText.prefix(120))
        let transStr = NSAttributedString(string: clampedTrans, attributes: transAttrs)
        let transRect = CGRect(x: 28, y: 94, width: size.width - 44, height: 88)
        transStr.draw(in: transRect)
    }

    private func langDisplayName(_ code: String) -> String {
        let locale = Locale(identifier: "th")
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func createPixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        UIGraphicsPushContext(context)
        image.draw(in: CGRect(origin: .zero, size: size))
        UIGraphicsPopContext()

        return buffer
    }

    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDesc = formatDescription else { return nil }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in self.isPiPActive = false }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("PiP failed: \(error)")
    }
}

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
