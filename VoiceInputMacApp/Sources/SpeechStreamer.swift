import Foundation
import Speech
import AVFoundation

/// 基于 Apple Speech Recognition API 的流式语音识别器
/// 真正的实时识别：说一个字出一个字
class SpeechStreamer: ObservableObject {
    static let shared = SpeechStreamer()
    
    @Published var partialText = ""
    @Published var isRecognizing = false
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    /// 每次增量识别的回调
    var onPartialResult: ((String) -> Void)?
    /// 最终结果回调
    var onFinalResult: ((String) -> Void)?
    
    /// 检查权限状态
    var isAuthorized: Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    /// 请求权限
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    /// 开始流式识别
    func start() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            Logger.shared.log("Apple Speech 识别器不可用（可能需要网络或语言不支持）", level: .warning)
            return
        }
        
        // 清理之前的任务
        _ = stop()
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        // macOS 13+ 可用
        if #available(macOS 13, *) {
            recognitionRequest.addsPunctuation = true
        }
        
        let inputNode = audioEngine.inputNode
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.partialText = text
                
                if result.isFinal {
                    Logger.shared.log("Apple Speech 最终结果：\(text.prefix(50))")
                    self.onFinalResult?(text)
                } else {
                    self.onPartialResult?(text)
                }
            }
            
            if let error = error {
                Logger.shared.log("Apple Speech 识别错误：\(error.localizedDescription)", level: .warning)
                // 识别任务超时（60秒）会自动停止，重新启动
                if self.audioEngine.isRunning {
                    self.restartRecognition()
                }
            }
        }
        
        // 配置音频输入
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecognizing = true
            partialText = ""
            Logger.shared.log("Apple Speech 流式识别已启动")
        } catch {
            Logger.shared.log("Apple Speech 音频引擎启动失败：\(error.localizedDescription)", level: .error)
        }
    }
    
    /// 停止流式识别
    func stop() -> String {
        let finalText = partialText
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        isRecognizing = false
        
        Logger.shared.log("Apple Speech 流式识别已停止，最终文本：\(finalText.prefix(50))")
        return finalText
    }
    
    /// 重启识别（处理60秒超时）
    private func restartRecognition() {
        Logger.shared.log("Apple Speech 识别超时，正在重启...")
        
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        
        // 短暂延迟后重启
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.audioEngine.isRunning == false else { return }
            
            // 重新启动音频引擎
            let inputNode = self.audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            self.recognitionRequest?.shouldReportPartialResults = true
            if #available(macOS 13, *) {
                self.recognitionRequest?.addsPunctuation = true
            }
            
            self.recognitionTask = self.speechRecognizer?.recognitionTask(with: self.recognitionRequest!) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.partialText = text
                    self.onPartialResult?(text)
                }
                if let error = error {
                    Logger.shared.log("Apple Speech 重启后错误：\(error.localizedDescription)", level: .warning)
                }
            }
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            do {
                self.audioEngine.prepare()
                try self.audioEngine.start()
                Logger.shared.log("Apple Speech 识别已重启")
            } catch {
                Logger.shared.log("Apple Speech 重启失败：\(error.localizedDescription)", level: .error)
            }
        }
    }
}
