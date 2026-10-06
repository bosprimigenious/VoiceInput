import Foundation

/// 会议记录模型
struct Meeting: Identifiable, Codable {
    let id: UUID
    let title: String
    let date: Date
    var duration: TimeInterval
    var transcription: String
    var summary: String
    var isProcessing: Bool  // 转录/总结进行中
    var audioSourceType: String  // 音频源类型
    var diarizationResult: String?  // 声纹识别结果
    var audioFilePath: String?  // 录音文件路径（用于后续声纹识别）
    
    init(title: String = "", duration: TimeInterval = 0, audioSourceType: AudioSourceType = .microphone) {
        self.id = UUID()
        self.title = title.isEmpty ? Self.defaultTitle(for: Date()) : title
        self.date = Date()
        self.duration = duration
        self.transcription = ""
        self.summary = ""
        self.isProcessing = true
        self.audioSourceType = audioSourceType.rawValue
        self.diarizationResult = nil
        self.audioFilePath = nil
    }
    
    static func defaultTitle(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日 HH:mm"
        return "会议 \(fmt.string(from: date))"
    }
}

/// 会议管理器：负责录音、转录、总结、持久化
class MeetingManager: ObservableObject {
    static let shared = MeetingManager()
    
    @Published var meetings: [Meeting] = []
    @Published var isRecording = false
    @Published var currentRecordingMeetingId: UUID?
    
    private let storageDir: URL
    private let meetingsFile: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("VoiceInput/Meetings")
        meetingsFile = storageDir.appendingPathComponent("meetings.json")
        
        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        loadMeetings()
    }
    
    // MARK: - 持久化
    
    func loadMeetings() {
        guard FileManager.default.fileExists(atPath: meetingsFile.path),
              let data = try? Data(contentsOf: meetingsFile),
              let decoded = try? JSONDecoder().decode([Meeting].self, from: data) else {
            return
        }
        // 加载时确保没有 isProcessing 卡住
        meetings = decoded.map { meeting in
            var m = meeting
            m.isProcessing = false
            return m
        }
    }
    
    func saveMeetings() {
        guard let data = try? JSONEncoder().encode(meetings) else { return }
        try? data.write(to: meetingsFile)
    }
    
    // MARK: - 录音管理
    
    /// 会议录音累积的 Apple Speech 文本
    private var accumulatedSpeechText = ""
    
    /// 当前录音的音频源类型
    private var currentAudioSourceType: AudioSourceType = .microphone
    
    /// 系统音频捕获器（macOS 14+）
    @available(macOS 14.0, *)
    private var systemAudioCapture: SystemAudioCapture? {
        if #available(macOS 14.0, *) {
            return SystemAudioCapture.shared
        }
        return nil
    }
    
    /// 录音文件保存路径
    private var currentAudioFilePath: URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupport.appendingPathComponent("VoiceInput/Recordings")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        return recordingsDir.appendingPathComponent("meeting_\(UUID().uuidString.prefix(8)).wav")
    }
    
    /// 开始会议录音
    /// - Parameters:
    ///   - audioSourceType: 音频源类型（麦克风/系统音频/混合）
    /// - Returns: 新建会议的 ID
    func startMeetingRecording(audioSourceType: AudioSourceType = .microphone) -> UUID {
        let meeting = Meeting(audioSourceType: audioSourceType)
        meetings.insert(meeting, at: 0)
        currentRecordingMeetingId = meeting.id
        currentAudioSourceType = audioSourceType
        isRecording = true
        accumulatedSpeechText = ""
        saveMeetings()
        
        // 根据音频源类型启动不同的录音方式
        switch audioSourceType {
        case .microphone:
            // 麦克风：使用 Apple Speech 流式识别
            startSpeechRecognition()
        case .system:
            // 系统音频：使用 ScreenCaptureKit
            startSystemAudioCapture()
        case .mixed:
            // 混合模式：同时启动两者
            startSpeechRecognition()
            startSystemAudioCapture()
        }
        
        Logger.shared.log("开始会议录音：\(meeting.title)，音频源：\(audioSourceType.rawValue)")
        return meeting.id
    }
    
    /// 启动 Apple Speech 流式识别
    private func startSpeechRecognition() {
        let streamer = SpeechStreamer.shared
        
        if !streamer.isAuthorized {
            streamer.requestAuthorization { [weak self] granted in
                if granted {
                    self?.startSpeechRecognition()
                } else {
                    Logger.shared.log("会议录音：Apple Speech 权限被拒绝", level: .warning)
                }
            }
            return
        }
        
        streamer.onPartialResult = { [weak self] text in
            guard let self = self, !text.isEmpty else { return }
            self.accumulatedSpeechText = text
            // 实时更新会议转录文本（让用户看到进度）
            if let id = self.currentRecordingMeetingId,
               let idx = self.meetings.firstIndex(where: { $0.id == id }) {
                self.meetings[idx].transcription = text
            }
        }
        
        streamer.start()
    }
    
    /// 启动系统音频捕获（用于线上会议）
    private func startSystemAudioCapture() {
        if #available(macOS 14.0, *) {
            let capture = SystemAudioCapture.shared
            
            if !capture.isAuthorized {
                capture.requestAuthorization { [weak self] granted in
                    if granted {
                        self?.startSystemAudioCapture()
                    } else {
                        Logger.shared.log("会议录音：屏幕录制权限被拒绝", level: .warning)
                        // 提示用户需要授予权限
                        DispatchQueue.main.async {
                            if let id = self?.currentRecordingMeetingId,
                               let idx = self?.meetings.firstIndex(where: { $0.id == id }) {
                                self?.meetings[idx].transcription = "（请在系统偏好设置中授予屏幕录制权限）"
                                self?.saveMeetings()
                            }
                        }
                    }
                }
                return
            }
            
            // 开始捕获系统音频，同时保存到文件
            if let audioPath = currentAudioFilePath {
                capture.start(saveToURL: audioPath)
                Logger.shared.log("系统音频捕获已启动，保存到：\(audioPath.lastPathComponent)")
            } else {
                capture.start()
            }
        } else {
            Logger.shared.log("系统音频捕获需要 macOS 14.0+", level: .warning)
        }
    }
    
    /// 停止会议录音
    func stopMeetingRecording(duration: TimeInterval) {
        guard let id = currentRecordingMeetingId,
              let idx = meetings.firstIndex(where: { $0.id == id }) else { return }
        
        var finalText = ""
        var pendingAudioFilePath: URL? = nil
        
        // 先停止 Apple Speech（同步）
        if currentAudioSourceType == .microphone || currentAudioSourceType == .mixed {
            let speechText = SpeechStreamer.shared.stop()
            finalText = !speechText.isEmpty ? speechText : accumulatedSpeechText
        }
        
        // 设置当前会议为处理中状态
        meetings[idx].duration = duration
        meetings[idx].transcription = finalText.isEmpty ? "正在处理录音..." : finalText
        meetings[idx].isProcessing = true
        isRecording = false
        saveMeetings()
        
        // 停止系统音频捕获（异步）
        if currentAudioSourceType == .system || currentAudioSourceType == .mixed {
            if #available(macOS 14.0, *) {
                SystemAudioCapture.shared.stop { [weak self] savedURL in
                    guard let self = self else { return }
                    
                    if let url = savedURL, FileManager.default.fileExists(atPath: url.path) {
                        pendingAudioFilePath = url
                        self.meetings[idx].audioFilePath = url.path
                        self.saveMeetings()
                    }
                    
                    self.finalizeMeetingRecording(id: id, text: finalText, audioPath: pendingAudioFilePath)
                }
            } else {
                finalizeMeetingRecording(id: id, text: finalText, audioPath: nil)
            }
        } else {
            finalizeMeetingRecording(id: id, text: finalText, audioPath: nil)
        }
    }
    
    /// 完成会议录音处理
    private func finalizeMeetingRecording(id: UUID, text: String, audioPath: URL?) {
        guard let idx = meetings.firstIndex(where: { $0.id == id }) else { return }
        
        currentRecordingMeetingId = nil
        
        Logger.shared.log("会议录音停止，时长：\(String(format: "%.1f", meetings[idx].duration))s，音频源：\(currentAudioSourceType.rawValue)，转录：\(text.count) 字")
        
        if !text.isEmpty {
            // 有麦克风转录文本，直接 AI 总结
            meetings[idx].transcription = text
            meetings[idx].isProcessing = false
            saveMeetings()
            summarizeMeeting(id: id)
        } else if let path = audioPath, FileManager.default.fileExists(atPath: path.path) {
            // 只有系统音频文件，进行声纹识别 + 转录
            meetings[idx].transcription = "正在识别说话人..."
            saveMeetings()
            processSystemAudioRecording(id: id, audioPath: path)
        } else {
            meetings[idx].transcription = "（未检测到语音）"
            meetings[idx].isProcessing = false
            saveMeetings()
        }
    }
    
    /// 处理系统音频录音（声纹识别 + 转录）
    private func processSystemAudioRecording(id: UUID, audioPath: URL) {
        guard let idx = meetings.firstIndex(where: { $0.id == id }) else { return }
        
        meetings[idx].isProcessing = true
        meetings[idx].transcription = "正在识别说话人..."
        saveMeetings()
        
        Logger.shared.log("开始处理系统音频：\(audioPath.lastPathComponent)")
        
        // 先进行声纹识别
        DiarizationManager.shared.diarize(audioFileURL: audioPath) { [weak self] result in
            guard let self = self,
                  let idx = self.meetings.firstIndex(where: { $0.id == id }) else { return }
            
            if let result = result {
                self.meetings[idx].diarizationResult = result.formattedText
                self.meetings[idx].transcription = "检测到 \(result.numSpeakers) 个说话人，正在转录..."
                self.saveMeetings()
                
                // TODO: 这里可以结合 ASR 转录结果
                // 目前直接使用声纹识别的时间线
                self.meetings[idx].transcription = result.formattedText
                self.meetings[idx].isProcessing = false
                self.saveMeetings()
                
                Logger.shared.log("声纹识别完成：\(result.numSpeakers) 个说话人")
                
                // 触发 AI 总结
                self.summarizeMeeting(id: id)
            } else {
                self.meetings[idx].transcription = "（声纹识别失败）"
                self.meetings[idx].isProcessing = false
                self.saveMeetings()
            }
        }
    }
    
    func cancelRecording() {
        if let id = currentRecordingMeetingId {
            meetings.removeAll { $0.id == id }
            saveMeetings()
        }
        isRecording = false
        currentRecordingMeetingId = nil
    }
    
    // MARK: - AI 总结
    
    func summarizeMeeting(id: UUID) {
        guard let idx = meetings.firstIndex(where: { $0.id == id }),
              !meetings[idx].transcription.isEmpty else { return }
        
        let transcription = meetings[idx].transcription
        meetings[idx].isProcessing = true
        
        let enhancer = AppDelegate.shared?.aiEnhancer
        enhancer?.summarize(text: transcription) { [weak self] summary in
            guard let self = self,
                  let idx = self.meetings.firstIndex(where: { $0.id == id }) else { return }
            
            self.meetings[idx].summary = summary
            self.meetings[idx].isProcessing = false
            self.saveMeetings()
            Logger.shared.log("会议总结完成：\(summary.count) 字")
        }
    }
    
    // MARK: - CRUD
    
    func deleteMeeting(id: UUID) {
        meetings.removeAll { $0.id == id }
        saveMeetings()
    }
    
    func deleteAll() {
        meetings.removeAll()
        saveMeetings()
    }
}
