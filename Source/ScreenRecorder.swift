//
//  IAScreenRecorder.swift
//  InAppRecord
//
//  Created by tryao on 2023/2/20.
//

import Foundation
import AVFoundation
import UIKit

public class ScreenRecorder {

    var bufferPool: CVPixelBufferPool?

    var writer: AVAssetWriter!

    var writerInput: AVAssetWriterInput!

    var adapter: AVAssetWriterInputPixelBufferAdaptor!

    var bufferQueue = DispatchQueue(label: "com.lion.bufferq")

    var displayLink: CADisplayLink!

    let frameRenderingSemaphore = DispatchSemaphore(value: 1)

    let pixelAppendSemaphore = DispatchSemaphore(value: 1)

    var firstTimeStamp: TimeInterval = 0

    var tempFilePath: URL!

    var videoRect: CGRect!

    var scale: CGFloat = 1

    var sampleRate: Int = 20

    private(set) var settings: [String: Any]!

    public func startRecord(settings: [String: Any]) {
        self.settings = settings

        videoRect = settings[videoClipRect] as? CGRect
        scale = CGFloat(settings[videoScale] as? Double ?? 1)
        sampleRate = settings[videoFrameRate] as? Int ?? 20

        prepareToRecord()

        displayLink = CADisplayLink.init(target: self,
                                         selector: #selector(writeVideoFrame))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(sampleRate),
                maximum: Float(sampleRate),
                preferred: Float(sampleRate))
        } else {
            displayLink.preferredFramesPerSecond = sampleRate
        }
        displayLink.add(to: RunLoop.main, forMode: .common)
    }

    public func stopRecord() async -> URL {
        displayLink.invalidate()

        writerInput.markAsFinished()
        await writer.finishWriting()
        cleanUp()
        return tempFilePath
    }

    private func prepareToRecord() {
        tempFilePath = URL.temporaryFile(withExtension: "mp4")

        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferWidthKey: videoRect.size.width * scale,
            kCVPixelBufferHeightKey: videoRect.size.height * scale,
            kCVPixelBufferBytesPerRowAlignmentKey: videoRect.size.width * scale * 4]

        CVPixelBufferPoolCreate(nil, nil, poolAttributes as CFDictionary, &bufferPool)

        let pixelNumber = videoRect.size.width * videoRect.size.height * scale

        let videoCompression: [String: Any] = [AVVideoAverageBitRateKey: pixelNumber * 10.1,
                                                 AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]

        let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                            AVVideoWidthKey: videoRect.size.width * scale,
                                           AVVideoHeightKey: videoRect.size.height * scale,
                            AVVideoCompressionPropertiesKey: videoCompression]

        writerInput = AVAssetWriterInput(mediaType: .video,
                                         outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true
        writerInput.transform = videoTransformForDeviceOrientation()

        adapter = AVAssetWriterInputPixelBufferAdaptor.init(assetWriterInput: writerInput)

        do {
            writer = try AVAssetWriter(url: tempFilePath,
                                        fileType: AVFileType.mp4)
        } catch {
            print("AVAssetWriter init failed")
        }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: CMTime(value: 0, timescale: 1000))
    }

    private func videoTransformForDeviceOrientation() -> CGAffineTransform {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown:
            return CGAffineTransformMakeRotation(.pi)
        case .landscapeLeft:
            return CGAffineTransformMakeRotation(-.pi / 2)
        case .landscapeRight:
            return CGAffineTransformMakeRotation(.pi / 2)
        case .faceUp, .faceDown, .portrait, .unknown:
            return CGAffineTransformIdentity
        @unknown default:
            return CGAffineTransformIdentity
        }
    }

    @objc
    private func writeVideoFrame() {

        defer {
            frameRenderingSemaphore.signal()
        }

        if frameRenderingSemaphore.wait(timeout: DispatchTime.now()) == .timedOut {
            return
        }

        guard writerInput.isReadyForMoreMediaData else { return }

        guard let pixelBuffer = createPixelBuffer() else { return }

        let currentTimestamp = displayLink.timestamp

        if firstTimeStamp == 0 {
            firstTimeStamp = currentTimestamp
        }

        let elapsed = currentTimestamp - firstTimeStamp
        let time = CMTimeMakeWithSeconds(elapsed, preferredTimescale: 1000)

        if pixelAppendSemaphore.wait(timeout: DispatchTime.now()) == .timedOut {
            pixelAppendSemaphore.signal()
        } else {
            bufferQueue.async {
                self.adapter.append(pixelBuffer,
                                     withPresentationTime: time)
                self.pixelAppendSemaphore.signal()
            }
        }
    }

    private func createPixelBuffer() -> CVPixelBuffer? {
        guard let bufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?

        CVPixelBufferPoolCreatePixelBuffer(nil, bufferPool, &pixelBuffer)

        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)

        assert(context != nil, "Could not create context from pixel buffer")

        context?.scaleBy(x: scale, y: scale)
        let flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, videoRect.size.height)
        context?.concatenate(flipVertical)

        context?.clear(CGRect(origin: CGPoint.zero, size: videoRect.size))

        var windows: [UIWindow]
        if #available(iOS 15.0, *) {
            windows = UIApplication.shared.connectedScenes
            // Keep only active scenes, onscreen and visible to the user
                .filter { $0.activationState == .foregroundActive }
            // Keep only the first `UIWindowScene`
                .first(where: { $0 is UIWindowScene })
            // Get its associated windows
                .flatMap({ $0 as? UIWindowScene })?.windows ?? []
        } else {
            windows = UIApplication.shared.windows
        }

        UIGraphicsPushContext(context!)
        for window in windows {
            let rect = window.bounds.offsetBy(dx: -videoRect.origin.x, dy: -videoRect.origin.y)
            /// set afterScreenUpdates to true will block main thread
            window.drawHierarchy(in: rect, afterScreenUpdates: false)
        }
        UIGraphicsPopContext()

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)

        return pixelBuffer
    }

    private func cleanUp() {
        firstTimeStamp = 0
        bufferPool = nil
    }
}
