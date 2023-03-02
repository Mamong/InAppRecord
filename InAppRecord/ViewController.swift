//
//  ViewController.swift
//  InAppRecord
//
//  Created by tryao on 2023/2/20.
//

import UIKit
import SnapKit
import AVFAudio
import AVFoundation
import Photos
import WebKit

class ViewController: UIViewController {

    lazy var timerBtn = UIButton(type: .system)

    lazy var recordBtn = UIButton(type: .system)

    lazy var label = UILabel()

    var tableView: UITableView!

    var webView: WKWebView!

    var timer: Timer?

    var counter = 0

    var colors: [UIColor] = []

    var recordSession: RecordSession!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        for _ in 0..<50 {
            colors.append(UIColor(red: CGFloat(Int.random(in: 0...255))/255,
                                  green: CGFloat(Int.random(in: 0...255))/255,
                                  blue: CGFloat(Int.random(in: 0...255))/255,
                                  alpha: 1))
        }
        setupUI()
    }

    func setupUI() {
        timerBtn.setTitle("开始计数", for: .normal)
        timerBtn.addTarget(self, action: #selector(handleBtnTap(_:)), for: .touchUpInside)
        view.addSubview(timerBtn)

        recordBtn.setTitle("录制", for: .normal)
        recordBtn.setTitle("停止", for: .selected)
        recordBtn.addTarget(self, action: #selector(handleRecordTap(_:)), for: .touchUpInside)
        view.addSubview(recordBtn)

        label.text = "0"
        view.addSubview(label)

        tableView = UITableView.init()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 60
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "plain-cell")
        view.addSubview(tableView)

        label.snp.makeConstraints { make in
            make.top.equalTo(view).offset(80)
            make.centerX.equalTo(timerBtn)
        }

        timerBtn.snp.makeConstraints { make in
            make.top.equalTo(label.snp.bottom).offset(20)
            make.centerX.equalTo(view)
        }

        recordBtn.snp.makeConstraints { make in
            make.left.equalTo(timerBtn.snp.centerX).offset(60)
            make.centerY.equalTo(timerBtn)
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(timerBtn.snp.bottom).offset(20)
            make.left.right.bottom.equalTo(0)
        }
    }

    @objc
    func handleBtnTap(_ sender: UIButton) {
        if timer == nil {
            timerBtn.setTitle("停止", for: .normal)
            timer = Timer.init(timeInterval: 1, repeats: true, block: { [weak self] _ in
                if let self {
                    self.counter += 1
                    self.label.text = "\(self.counter)"
                }
            })
            RunLoop.main.add(timer!, forMode: .common)
        } else {
            timer!.invalidate()
            timer = nil
            timerBtn.setTitle("开始计数", for: .normal)
        }
    }

    @objc
    func handleRecordTap(_ sender: UIButton) {
        Task {
            if sender.isSelected {
                sender.isSelected = false
                await stopRecord()
            } else {
                sender.isSelected = true
                await startRecord()
            }
        }
    }

    func startRecord() async {
        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                          AVSampleRateKey: 8000,
                                    AVNumberOfChannelsKey: 1,
                                 AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]

        /// record entire screen
        var rect = view.bounds

        /// record tableview only
        rect = tableView.frame

        let videoSettings: [String: Any] = [
            videoClipRect: rect,
            videoScale: 1.0,
            videoFrameRate: 20
        ]

        let exportSettings: [String: Any] = [
            exportFileType: AVFileType.mp4,
            exportPreset: AVAssetExportPresetHighestQuality
        ]

        let config = RecordConfig(audioSettings: audioSettings,
                                  videoSettings: videoSettings,
                                  exportSettings: exportSettings)
        let fileUrl = URL.temporaryFile(withExtension: "mp4")
        recordSession = RecordSession(url: fileUrl, config: config)
        await recordSession.startRecord()
    }

    func stopRecord() async {
        await recordSession.stopRecord()
        print(recordSession.url)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.recordSession.url)
            }
        } catch {
            print("保存失败:\(error.localizedDescription)")
        }
    }
}

extension ViewController: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return colors.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = indexPath.row
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "plain-cell",
            for: indexPath)
        cell.contentView.backgroundColor = colors[row]
        cell.textLabel?.text = "text"
        return cell
    }
}
