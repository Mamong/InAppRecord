//
//  IAAudioRecorder.swift
//  InAppRecord
//
//  Created by tryao on 2023/2/20.
//

import Foundation
import AVFoundation

/// only provide basic microphone record, do not support in app audio
public class AudioRecorder: NSObject {

    var recorder: AVAudioRecorder?

    private(set) var settings: [String: Any]!

    var tempFilePath: URL!

    public func permissionCheck() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func startRecord(settings: [String: Any]) {
        self.settings = settings

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord)
        try? session.setActive(true)

        if let recorder, recorder.isRecording {
            cancelRecord()
        }

        tempFilePath = URL.temporaryFile(withExtension: "aac")

        do {
            recorder = try AVAudioRecorder.init(url: tempFilePath,
                                           settings: settings)
        } catch {
            print("录制音频失败:\(error.localizedDescription)")
        }
        // recorder!.delegate = self
        recorder?.prepareToRecord()
        recorder?.record()
    }

    public func record() {
        recorder?.record()
    }

    public func pause() {
        recorder?.pause()
    }

    public func stopRecord() -> URL {
        recorder?.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        return tempFilePath
    }

    public func cancelRecord() {
        recorder?.stop()
        recorder?.deleteRecording()
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {

}
