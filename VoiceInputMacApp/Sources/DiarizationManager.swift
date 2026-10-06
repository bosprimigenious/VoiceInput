import Foundation
import AVFoundation
import SpeechVAD

/// 声纹识别管理器 - 使用 speech-swift 的 DiarizationPipeline
/// 识别"谁在什么时候说话"
class DiarizationManager: ObservableObject {
    static let shared = DiarizationManager()
    
    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var speakers: [SpeakerInfo] = []
    
    private var pipeline: DiarizationPipeline?
    private var isInitialized = false
    
    struct SpeakerInfo: Identifiable {
        let id: Int
        var name: String  // 用户可自定义的名称
        var segments: [SpeechSegment]
    }
    
    struct SpeechSegment: Identifiable {
        let id = UUID()
        let speakerId: Int
        let startTime: Double
        let endTime: Double
        var text: String
    }
    
    /// 转录结果，包含按说话人分段的文本
    struct DiarizationResult {
        let segments: [SpeechSegment]
        let numSpeakers: Int
        let formattedText: String  // 格式化后的完整文本
    }
    
    private init() {}
    
    // MARK: - 初始化
    
    /// 初始化声纹识别模型（首次调用时下载模型）
    func initialize() async throws {
        guard !isInitialized else { return }
        
        Logger.shared.log("初始化声纹识别模型...")
        
        // 使用 Pyannote pipeline（默认引擎）
        pipeline = try await DiarizationPipeline.fromPretrained()
        
        isInitialized = true
        Logger.shared.log("声纹识别模型初始化完成")
    }
    
    // MARK: - 声纹识别
    
    /// 对音频进行声纹识别
    /// - Parameters:
    ///   - audioSamples: PCM 音频数据（Float 数组，范围 -1.0 到 1.0）
    ///   - sampleRate: 采样率（推荐 16000）
    ///   - completion: 完成回调，返回声纹识别结果
    func diarize(
        audioSamples: [Float],
        sampleRate: Int = 16000,
        completion: @escaping (DiarizationResult?) -> Void
    ) {
        guard let pipeline = pipeline else {
            Logger.shared.log("声纹识别：模型未初始化", level: .error)
            completion(nil)
            return
        }
        
        guard !audioSamples.isEmpty else {
            Logger.shared.log("声纹识别：音频为空", level: .warning)
            completion(nil)
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.progress = 0
        }
        
        // 在后台线程执行声纹识别
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                Logger.shared.log("开始声纹识别，音频长度：\(String(format: "%.1f", Double(audioSamples.count) / Double(sampleRate)))秒")
                
                // 执行声纹识别，带进度回调
                let result = pipeline.diarize(
                    audio: audioSamples,
                    sampleRate: sampleRate
                ) { progress, stage in
                    DispatchQueue.main.async {
                        self.progress = Double(progress)
                    }
                    Logger.shared.log("声纹识别进度：\(Int(progress * 100))% - \(stage)")
                    return true  // 继续处理
                }
                
                // 解析结果
                var segments: [SpeechSegment] = []
                for seg in result.segments {
                    let segment = SpeechSegment(
                        speakerId: seg.speakerId,
                        startTime: Double(seg.startTime),
                        endTime: Double(seg.endTime),
                        text: ""  // 文本需要后续通过 ASR 填充
                    )
                    segments.append(segment)
                }
                
                Logger.shared.log("声纹识别完成：检测到 \(result.numSpeakers) 个说话人，\(segments.count) 个片段")
                
                // 生成格式化文本
                let formattedText = self.formatSegments(segments)
                
                let diarizationResult = DiarizationResult(
                    segments: segments,
                    numSpeakers: result.numSpeakers,
                    formattedText: formattedText
                )
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.progress = 1.0
                    completion(diarizationResult)
                }
                
            } catch {
                Logger.shared.log("声纹识别失败：\(error.localizedDescription)", level: .error)
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(nil)
                }
            }
        }
    }
    
    /// 对音频文件进行声纹识别
    func diarize(
        audioFileURL: URL,
        completion: @escaping (DiarizationResult?) -> Void
    ) {
        // 加载音频文件
        guard let (samples, sampleRate) = loadAudioFile(url: audioFileURL) else {
            Logger.shared.log("无法加载音频文件：\(audioFileURL.lastPathComponent)", level: .error)
            completion(nil)
            return
        }
        
        diarize(audioSamples: samples, sampleRate: sampleRate, completion: completion)
    }
    
    // MARK: - 辅助方法
    
    /// 格式化声纹片段为可读文本
    private func formatSegments(_ segments: [SpeechSegment]) -> String {
        guard !segments.isEmpty else { return "" }
        
        var lines: [String] = []
        var currentSpeaker = -1
        
        for seg in segments {
            let speakerLabel = currentSpeaker != seg.speakerId ? "[说话人 \(seg.speakerId + 1)]" : ""
            let timeStr = "[\(formatTime(seg.startTime)) - \(formatTime(seg.endTime))]"
            
            if !seg.text.isEmpty {
                lines.append("\(speakerLabel) \(timeStr) \(seg.text)")
            } else {
                lines.append("\(speakerLabel) \(timeStr)")
            }
            
            currentSpeaker = seg.speakerId
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// 格式化时间为 mm:ss 格式
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    /// 加载音频文件为 PCM 数据
    private func loadAudioFile(url: URL) -> ([Float], Int)? {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }
            
            try audioFile.read(into: buffer)
            
            // 转换为 Float 数组
            guard let channelData = buffer.floatChannelData else { return nil }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
            
            return (samples, Int(format.sampleRate))
            
        } catch {
            Logger.shared.log("加载音频文件失败：\(error.localizedDescription)", level: .error)
            return nil
        }
    }
    
    // MARK: - 与转录结合
    
    /// 将声纹识别结果与转录文本结合
    /// - Parameters:
    ///   - diarizationResult: 声纹识别结果
    ///   - transcription: 转录文本（按时间戳分段）
    /// - Returns: 按说话人分段的完整文本
    func combineWithTranscription(
        diarizationResult: DiarizationResult,
        transcription: [(startTime: Double, endTime: Double, text: String)]
    ) -> String {
        var segments = diarizationResult.segments
        
        // 将转录文本匹配到声纹片段
        for (start, end, text) in transcription {
            // 找到时间重叠最大的声纹片段
            if let idx = findOverlappingSegment(segments: segments, start: start, end: end) {
                segments[idx].text = text
            }
        }
        
        // 按说话人整理
        return formatSegmentsBySpeaker(segments)
    }
    
    /// 找到与给定时间范围重叠最大的声纹片段
    private func findOverlappingSegment(segments: [SpeechSegment], start: Double, end: Double) -> Int? {
        var bestIdx: Int?
        var bestOverlap: Double = 0
        
        for (idx, seg) in segments.enumerated() {
            let overlapStart = max(seg.startTime, start)
            let overlapEnd = min(seg.endTime, end)
            let overlap = max(0, overlapEnd - overlapStart)
            
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestIdx = idx
            }
        }
        
        return bestIdx
    }
    
    /// 按说话人整理文本
    private func formatSegmentsBySpeaker(_ segments: [SpeechSegment]) -> String {
        // 按说话人分组
        var bySpeaker: [Int: [SpeechSegment]] = [:]
        for seg in segments {
            bySpeaker[seg.speakerId, default: []].append(seg)
        }
        
        var lines: [String] = []
        for (speakerId, speakerSegments) in bySpeaker.sorted(by: { $0.key < $1.key }) {
            lines.append("【说话人 \(speakerId + 1)】")
            for seg in speakerSegments where !seg.text.isEmpty {
                lines.append("  \(seg.text)")
            }
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
}
