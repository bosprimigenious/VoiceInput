import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// 系统音频捕获器 - 使用 ScreenCaptureKit 捕获电脑播放的声音
/// 用于线上会议（Zoom/Teams/飞书等）录音
@available(macOS 14.0, *)
class SystemAudioCapture: NSObject, ObservableObject {
    static let shared = SystemAudioCapture()
    
    @Published var isCapturing = false
    @Published var isAuthorized = false
    
    /// 音频数据回调 (PCM samples, sampleRate)
    var onAudioBuffer: (([Float], Int) -> Void)?
    
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    
    // 累积的 Float 音频缓冲区
    private var audioBuffer: [Float] = []
    private let audioBufferQueue = DispatchQueue(label: "SystemAudioCapture.audioQueue")
    private let targetSampleRate: Double = 16000
    
    private override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - 权限检查
    
    func checkPermissions() {
        Task {
            do {
                let content = try await SCShareableContent.current
                DispatchQueue.main.async {
                    self.isAuthorized = !content.displays.isEmpty
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAuthorized = false
                }
                Logger.shared.log("系统音频权限检查失败: \(error.localizedDescription)", level: .warning)
            }
        }
    }
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let content = try await SCShareableContent.current
                let authorized = !content.displays.isEmpty
                DispatchQueue.main.async {
                    self.isAuthorized = authorized
                    completion(authorized)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isAuthorized = false
                    completion(false)
                }
            }
        }
    }
    
    // MARK: - 开始/停止捕获
    
    /// 开始捕获系统音频
    /// - Parameter saveToURL: 如果提供，同时将音频写入文件
    func start(saveToURL: URL? = nil) {
        guard !isCapturing else { return }
        
        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else {
                    Logger.shared.log("系统音频捕获：没有可用的显示器", level: .error)
                    return
                }
                
                // 创建过滤器
                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: [],
                    exceptingWindows: []
                )
                
                // 配置流 - 只捕获音频
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.captureMicrophone = false
                config.excludesCurrentProcessAudio = true
                
                // 音频配置（16kHz 单声道，声纹识别需要）
                config.sampleRate = Int(targetSampleRate)
                config.channelCount = 1
                
                // 创建流
                stream = SCStream(filter: filter, configuration: config, delegate: nil)
                streamOutput = StreamOutput(capture: self)
                
                try stream?.addStreamOutput(
                    streamOutput!,
                    type: .audio,
                    sampleHandlerQueue: audioBufferQueue
                )
                
                // 设置音频文件写入
                if let url = saveToURL {
                    try setupAudioFile(url: url)
                    audioFileURL = url
                }
                
                audioBuffer.removeAll()
                try await stream?.startCapture()
                
                DispatchQueue.main.async {
                    self.isCapturing = true
                    Logger.shared.log("系统音频捕获已启动")
                }
                
            } catch {
                Logger.shared.log("系统音频捕获启动失败: \(error.localizedDescription)", level: .error)
                cleanupAudioFile()
                DispatchQueue.main.async {
                    self.isCapturing = false
                }
            }
        }
    }
    
    /// 停止捕获
    /// - Parameter completion: 完成后返回保存的音频文件 URL
    func stop(completion: @escaping (URL?) -> Void = { _ in }) {
        guard isCapturing else {
            completion(nil)
            return
        }
        
        Task {
            do {
                try await stream?.stopCapture()
            } catch {
                Logger.shared.log("停止系统音频流失败: \(error.localizedDescription)", level: .warning)
            }
            
            stream = nil
            streamOutput = nil
            
            // 完成文件写入
            let savedURL = await finalizeAudioFile()
            
            DispatchQueue.main.async {
                self.isCapturing = false
                completion(savedURL)
            }
        }
    }
    
    // MARK: - 音频文件写入
    
    private func setupAudioFile(url: URL) throws {
        // 删除旧文件
        try? FileManager.default.removeItem(at: url)
        
        // 使用 AVAudioFile 写入 WAV 格式（最稳定的 PCM 写入方式）
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        Logger.shared.log("音频文件写入器已初始化: \(url.lastPathComponent)")
    }
    
    private func finalizeAudioFile() async -> URL? {
        guard let file = audioFile else { return nil }
        
        // 把缓冲区剩余数据写入
        await flushBuffer()
        
        // AVAudioFile 不需要显式 close，释放引用即可
        audioFile = nil
        
        let url = audioFileURL
        audioFileURL = nil
        
        Logger.shared.log("音频文件写入完成: \(url?.lastPathComponent ?? "无")")
        return url
    }
    
    private func cleanupAudioFile() {
        audioFile = nil
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
            audioFileURL = nil
        }
    }
    
    // MARK: - 音频数据处理
    
    fileprivate func handleAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let samples = extractSamples(from: sampleBuffer), !samples.isEmpty else { return }
        
        // 累积到缓冲区
        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.audioBuffer.append(contentsOf: samples)
            
            // 缓冲区达到 1 秒数据时写入文件
            if self.audioBuffer.count >= Int(self.targetSampleRate) {
                self.flushBuffer()
            }
        }
        
        // 回调实时音频数据
        if let callback = onAudioBuffer {
            callback(samples, Int(targetSampleRate))
        }
    }
    
    /// 将缓冲区写入文件（在 audioBufferQueue 中调用）
    private func flushBuffer() {
        guard !audioBuffer.isEmpty, let audioFile = audioFile else { return }
        
        let frameCount = AVAudioFrameCount(audioBuffer.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else { return }
        
        buffer.frameLength = frameCount
        
        if let channelData = buffer.floatChannelData {
            audioBuffer.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
                memcpy(channelData[0], source, audioBuffer.count * MemoryLayout<Float>.size)
            }
        }
        
        do {
            try audioFile.write(from: buffer)
            audioBuffer.removeAll()
        } catch {
            Logger.shared.log("写入音频文件失败: \(error.localizedDescription)", level: .error)
        }
    }
    
    /// 从 CMSampleBuffer 提取 Float PCM 数据
    private func extractSamples(from sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else { return nil }
        
        let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer)
        let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc!)
        
        guard let asbdPointer = asbdPointer else { return nil }
        let asbd = asbdPointer.pointee
        
        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)
        let sampleCount = length / bytesPerSample
        var samples = [Float](repeating: 0, count: sampleCount)
        
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            // Float 格式
            pointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { floatPointer in
                for i in 0..<sampleCount {
                    samples[i] = floatPointer[i]
                }
            }
        } else {
            // 16-bit PCM
            let bytesPerFrame = Int(asbd.mBytesPerFrame)
            let channels = Int(asbd.mChannelsPerFrame)
            
            pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { int16Pointer in
                for i in 0..<sampleCount {
                    let frameIndex = i / channels
                    let channelIndex = i % channels
                    let value = int16Pointer[frameIndex * bytesPerFrame / 2 + channelIndex]
                    samples[i] = Float(value) / 32768.0
                }
            }
        }
        
        return samples
    }
}

// MARK: - SCStreamOutput

@available(macOS 14.0, *)
private class StreamOutput: NSObject, SCStreamOutput {
    weak var capture: SystemAudioCapture?
    
    init(capture: SystemAudioCapture) {
        self.capture = capture
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        capture?.handleAudioBuffer(sampleBuffer)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Logger.shared.log("系统音频流停止: \(error.localizedDescription)", level: .warning)
        DispatchQueue.main.async {
            self.capture?.isCapturing = false
        }
    }
}
