//
//  IARecordSession.swift
//  InAppRecord
//
//  Created by tryao on 2023/2/20.
//

import Foundation
import AVFoundation

public let exportFileType = "ExportFileType"
public let exportPreset   = "ExportPreset"
public let videoClipRect  = "VideoClipRect"
public let videoScale     = "VideoScale"
public let videoFrameRate = "VideoFrameRate"

public struct RecordConfig {

    struct RecordType: OptionSet {
        let rawValue: Int

        static let video = RecordType(rawValue: 1)
        static let audio = RecordType(rawValue: 2)
        static let all   = RecordType(rawValue: 3)
    }

    var type: RecordType = .all

    /// used in AVAudioRecorder settings
    var audioSettings: [String: Any]

    /// rect: crop rect
    /// scale: 1 or 2
    /// sampleRate: preferred frames per second
    var videoSettings: [String: Any]

    /// fileType
    /// preset
    var exportSettings: [String: Any]
}

public class RecordSession {

    private(set) var config: RecordConfig!

    private(set) var url: URL

    var recordType: RecordConfig.RecordType {
        return config.type
    }

    lazy var videoRecord = ScreenRecorder()

    lazy var audioRecord = AudioRecorder()

    public init(url: URL, config: RecordConfig) {
        self.config = config
        self.url = url
    }

    public func startRecord() async {
        if recordType.contains(.video) {
            guard await audioRecord.permissionCheck() else {
                return
            }
            videoRecord.startRecord(settings: config.videoSettings)
        }

        if recordType.contains(.audio) {
            audioRecord.startRecord(settings: config.audioSettings)
        }
    }

    public func stopRecord() async {
        var videoUrl: URL?
        var audioUrl: URL?

        if recordType.contains(.audio) {
            audioUrl = audioRecord.stopRecord()
        }
        if recordType.contains(.video) {
            videoUrl = await videoRecord.stopRecord()
        }
        await merge(video: videoUrl, audio: audioUrl, toURL: url)
    }

    private func merge(video: URL?, audio: URL?, toURL: URL) async {
        let mixComposition = AVMutableComposition()

        if let audio {
            let audioAsset = AVURLAsset(url: audio)
            await composition(mixComposition,
                              add: audioAsset,
                              type: .audio)
        }

        if let video {
            let videoAsset = AVURLAsset(url: video)
            await composition(mixComposition,
                              add: videoAsset,
                              type: .video)
        }

        let fileType = config.exportSettings[exportFileType] as? AVFileType ?? .mp4
        let preset = config.exportSettings[exportPreset] as? String ?? AVAssetExportPresetHighestQuality
        let exportSession = AVAssetExportSession(asset: mixComposition,
                                                 presetName: preset)
        exportSession?.outputFileType = fileType
        exportSession?.outputURL = toURL
        exportSession?.shouldOptimizeForNetworkUse = true
        await exportSession?.export()
    }

    private func composition(_ composition: AVMutableComposition,
                             add asset: AVURLAsset,
                             type: AVMediaType) async {
        let compositionTrack = composition.addMutableTrack(
            withMediaType: type,
            preferredTrackID: kCMPersistentTrackID_Invalid)

        var assetTrack: AVAssetTrack?

        var time: CMTime?

        if #available(iOS 16.0, *) {
            assetTrack = try? await asset.loadTracks(withMediaType: type).first
            time = try? await asset.load(.duration)
        } else {
            assetTrack = asset.tracks(withMediaType: type).first
            time = asset.duration
        }

        if let compositionTrack, let assetTrack, let time {
            try? compositionTrack.insertTimeRange(
                CMTimeRangeMake(start: CMTime.zero, duration: time),
                of: assetTrack,
                at: CMTime.zero)
        }
    }
}

extension URL {
    static func temporaryFile(withExtension ext: String) -> URL {
        let filePath = NSTemporaryDirectory().appending("\(UUID().uuidString).\(ext)")
        if #available(iOS 16.0, *) {
            return URL(filePath: filePath)
        } else {
            return URL(fileURLWithPath: filePath)
        }
    }
}
