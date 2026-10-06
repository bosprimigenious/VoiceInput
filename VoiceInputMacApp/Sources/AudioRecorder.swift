import Foundation
import AVFoundation

protocol AudioRecorderDelegate: AnyObject {
    func audioRecorderDidStart()
    func audioRecorderDidStop(url: URL?, averagePower: Float, peakPower: Float, duration: TimeInterval)
    func audioRecorderDidFail(error: Error)
    /// 录音过程中的音频快照，用于实时转录
    func audioRecorderDidSnapshot(url: URL)
}

class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var levelTimer: Timer?
    private var snapshotTimer: Timer?
    private var startTime: Date?
    private var averagePowerSum: Float = 0
    private var powerCount: Int = 0
    private var peakPower: Float = -160
    
    weak var delegate: AudioRecorderDelegate?
    
    static var microphonePermission: AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .audio)
    }
    
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func start() {
        guard AudioRecorder.microphonePermission == .authorized else {
            delegate?.audioRecorderDidFail(error: AudioRecorderError.permissionDenied)
            return
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        audioURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisper_input_\(UUID().uuidString)")
            .appendingPathExtension("wav")
        
        guard let url = audioURL else {
            delegate?.audioRecorderDidFail(error: AudioRecorderError.invalidURL)
            return
        }
        
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()
            
            startTime = Date()
            averagePowerSum = 0
            powerCount = 0
            peakPower = -160
            startLevelTimer()
            startSnapshotTimer()
            delegate?.audioRecorderDidStart()
        } catch {
            delegate?.audioRecorderDidFail(error: error)
        }
    }
    
    func stop() {
        levelTimer?.invalidate()
        levelTimer = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        
        guard let recorder = recorder else {
            delegate?.audioRecorderDidStop(url: nil, averagePower: -160, peakPower: -160, duration: 0)
            return
        }
        
        recorder.stop()
        let url = audioURL
        let duration = Date().timeIntervalSince(startTime ?? Date())
        let avgPower = powerCount > 0 ? averagePowerSum / Float(powerCount) : -160
        let maxPower = peakPower
        
        self.recorder = nil
        self.audioURL = nil
        self.startTime = nil
        
        // 稍微延迟，确保文件写入完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.delegate?.audioRecorderDidStop(url: url, averagePower: avgPower, peakPower: maxPower, duration: duration)
        }
    }
    
    private func startLevelTimer() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.recorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let peak = recorder.peakPower(forChannel: 0)
            self.averagePowerSum += power
            self.powerCount += 1
            self.peakPower = max(self.peakPower, peak)
            Logger.shared.log("录音音量: avg \(String(format: "%.1f", power)) dB / peak \(String(format: "%.1f", peak)) dB", level: .debug)
        }
    }
    
    /// 每 3 秒创建音频快照，用于实时转录
    private func startSnapshotTimer() {
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, let sourceURL = self.audioURL else { return }
            // 确保录音文件存在
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
            
            // 复制到临时快照文件
            let snapshotURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("whisper_snapshot_\(UUID().uuidString)")
                .appendingPathExtension("wav")
            
            do {
                try FileManager.default.copyItem(at: sourceURL, to: snapshotURL)
                self.delegate?.audioRecorderDidSnapshot(url: snapshotURL)
            } catch {
                Logger.shared.log("创建音频快照失败：\(error.localizedDescription)", level: .warning)
            }
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            delegate?.audioRecorderDidFail(error: AudioRecorderError.recordingFailed)
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case permissionDenied
    case invalidURL
    case recordingFailed
    case noAudioDetected
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "麦克风权限被拒绝，请在系统设置中开启。"
        case .invalidURL:
            return "无法创建录音文件路径。"
        case .recordingFailed:
            return "录音失败。"
        case .noAudioDetected:
            return "没有检测到声音，请检查麦克风是否正常。"
        }
    }
}
