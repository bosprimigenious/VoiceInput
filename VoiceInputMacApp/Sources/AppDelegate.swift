import Cocoa
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static weak var shared: AppDelegate?
    
    let hotKeyManager = HotKeyManager()
    let audioRecorder = AudioRecorder()
    var transcriptionProvider: TranscriptionProvider!
    let textInjector = TextInjector()
    let recordingPanel = RecordingPanelController()
    let confirmationPanel = ConfirmationPanelController()
    let aiEnhancer = AIEnhancer()
    
    private var previousApp: NSRunningApplication?
    private var isRecording = false
    private var isProcessing = false
    private var promptMode = false
    private var hotKeyRetryTimer: Timer?
    
    // 实时转录状态
    private var isStreamingTranscribing = false
    private var pendingSnapshotURL: URL?
    /// 已经实时打字输入的文本（用于增量计算）
    private var streamingTypedText = ""
    private var streamingTypedLength = 0
    /// Apple Speech 是否正在提供实时文本
    private var appleSpeechActive = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        ProcessInfo.processInfo.disableAutomaticTermination("菜单栏应用需要持续运行以监听快捷键")
        
        // 注册默认值（True SOTA API）
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "openAIBaseURL": "https://true-sota.com/v1",
            "aiEnhanceModel": "gpt-5.5",
            "aiEnhanceEnabled": true,
        ])
        // 确保 API 配置不为空（register 不会覆盖已存在的空值）
        if defaults.string(forKey: "openAIBaseURL")?.isEmpty ?? true {
            defaults.set("https://true-sota.com/v1", forKey: "openAIBaseURL")
        }
        if defaults.string(forKey: "aiEnhanceModel")?.isEmpty ?? true {
            defaults.set("gpt-5.5", forKey: "aiEnhanceModel")
        }
        // 迁移旧的不受支持模型到 gpt-5.5
        if defaults.string(forKey: "aiEnhanceModel") == "gpt-4o-mini" {
            defaults.set("gpt-5.5", forKey: "aiEnhanceModel")
        }
        // API Key 不再硬编码，必须由用户在设置中手动输入
        
        // 一次性迁移：把老版本的 ggml-base.bin 升级到精度更高的模型。
        // base 在中文短句上的错误率明显高于 small / medium / large-v3-turbo
        // （实测：同一段录音切 14 秒短句，base 会把 webcoding 听成「外部扣紧」、
        //  DeepSeek 听成「Depcyl」、轻量化听成「青年化」）。
        if defaults.string(forKey: "selectedModel") == "ggml-base.bin",
           !defaults.bool(forKey: "didUpgradeDefaultModel") {
            let candidates = [LocalWhisperProvider.defaultModelName, "ggml-medium.bin", "ggml-large-v3-turbo.bin"]
            // 同时看 App 包内和外置模型目录（大模型在外置目录里）
            let upgraded = candidates.first { LocalWhisperProvider.findModelPath($0) != nil }
            if let upgraded = upgraded {
                defaults.set(upgraded, forKey: "selectedModel")
                defaults.set(true, forKey: "didUpgradeDefaultModel")
                Logger.shared.log("默认模型已从 ggml-base.bin 升级为 \(upgraded)")
            }
        }
        
        Logger.shared.log("App 启动")
        logPermissionStatus()
        
        audioRecorder.delegate = self
        updateTranscriptionProvider()
        hotKeyManager.delegate = self
        startHotKeyListening()
        
        // 启动时显示主窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMainWindow()
        }
        
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }
    
    /// 显示主窗口
    func showMainWindow() {
        // 切换为 regular 让窗口能获取焦点和显示在 Dock
        NSApp.setActivationPolicy(.regular)
        
        // 查找并显示 SwiftUI Window scene
        for window in NSApp.windows {
            if window.className.contains("SwiftUI") || window.title == "VoiceInput" || !window.title.isEmpty {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
        
        NSApp.activate()   // macOS 14 起 activate(ignoringOtherApps:) 已废弃且参数无效果
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    private func startHotKeyListening() {
        let hotKeyStarted = hotKeyManager.startListening()
        Logger.shared.log("快捷键监听状态：\(hotKeyStarted ? "成功" : "等待辅助功能权限")")

        guard !hotKeyStarted else {
            hotKeyRetryTimer?.invalidate()
            hotKeyRetryTimer = nil
            return
        }

        hotKeyRetryTimer?.invalidate()
        hotKeyRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            guard self.hotKeyManager.isAccessibilityEnabled else { return }

            if self.hotKeyManager.startListening() {
                Logger.shared.log("辅助功能权限已可用，快捷键监听已启动")
                timer.invalidate()
                self.hotKeyRetryTimer = nil
            }
        }
    }
    
    private func logPermissionStatus() {
        let microphoneStatus: String
        switch AudioRecorder.microphonePermission {
        case .authorized:
            microphoneStatus = "已授权"
        case .denied:
            microphoneStatus = "已拒绝"
        case .restricted:
            microphoneStatus = "受限制"
        case .notDetermined:
            microphoneStatus = "未决定"
        @unknown default:
            microphoneStatus = "未知"
        }

        Logger.shared.log("麦克风权限状态：\(microphoneStatus)")
    }
    
    func updateTranscriptionProvider() {
        let providerType = UserDefaults.standard.string(forKey: "selectedProvider") ?? "local"
        if providerType == "openai" {
            transcriptionProvider = OpenAIWhisperProvider()
            Logger.shared.log("使用转录引擎：OpenAI API")
        } else {
            transcriptionProvider = LocalWhisperProvider()
            Logger.shared.log("使用转录引擎：本地 Whisper")
        }
    }
    
    // MARK: - Menu Bar 菜单调用
    
    func toggleRecordingFromMenu() {
        guard !isProcessing else { return }
        if isRecording {
            stopRecording()
        } else {
            promptMode = false
            startRecording()
        }
    }
    
    func togglePromptRecordingFromMenu() {
        guard !isProcessing else { return }
        if isRecording {
            stopRecording()
        } else {
            promptMode = true
            startRecording()
        }
    }
    
    // MARK: - Onboarding
    
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 VoiceInput"
        window.center()
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.makeKeyAndOrderFront(nil)
        
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
    
    // MARK: - Recording
    
    func startRecording() {
        guard !isRecording && !isProcessing else { return }
        
        if !hotKeyManager.isAccessibilityEnabled {
            showAccessibilityAlert()
            return
        }
        
        if AudioRecorder.microphonePermission != .authorized {
            AudioRecorder.requestPermission { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.beginRecording() }
                } else {
                    self?.showMicrophoneAlert()
                }
            }
            return
        }
        
        beginRecording()
    }
    
    private func beginRecording() {
        previousApp = captureTargetApp()
        Logger.shared.log("开始录音，目标应用：\(previousApp?.localizedName ?? "未知") (bundleID: \(previousApp?.bundleIdentifier ?? "nil"))")
        
        // 隐藏 VoiceInput 所有窗口，让焦点回到目标应用
        hideAllWindows()
        
        // 启动 Apple Speech 流式识别（实时转录）
        startStreamingRecognition()
        
        recordingPanel.show()
        audioRecorder.start()
    }
    
    /// 启动 Apple Speech 流式识别
    private func startStreamingRecognition() {
        let streamer = SpeechStreamer.shared
        
        // 检查权限
        if !streamer.isAuthorized {
            streamer.requestAuthorization { [weak self] granted in
                if granted {
                    self?.startStreamingRecognition()
                } else {
                    Logger.shared.log("Apple Speech 权限被拒绝，回退到 Whisper 快照模式", level: .warning)
                    self?.appleSpeechActive = false
                }
            }
            return
        }
        
        // 重置增量状态
        streamingTypedText = ""
        streamingTypedLength = 0
        appleSpeechActive = true
        
        // 设置回调
        streamer.onPartialResult = { [weak self] text in
            guard let self = self, !text.isEmpty else { return }
            
            // 只更新录音面板做实时预览，**不再**把中间结果打字到目标 App。
            // 原因：Apple Speech 的中间结果精度明显低于 Whisper，一旦打字出去，
            // 后面 Whisper 的更正无法覆盖已经落地的错字。
            // 最终文本统一在录音结束后由 Whisper 一次性注入。
            self.recordingPanel.updatePartialText(text)
        }
        
        streamer.start()
    }
    
    /// 隐藏 VoiceInput 的所有窗口（录音时让焦点回到目标应用）
    private func hideAllWindows() {
        for window in NSApp.windows {
            if window.isVisible && window.className != "NSPanel" {
                window.orderOut(nil)
            }
        }
        // 将焦点还给目标应用
        if let app = previousApp, shouldActivateApp(app) {
            // 同上：.activateIgnoringOtherApps 自 macOS 14 起已废弃、无效果
            app.activate(options: [.activateAllWindows])
        }
    }
    
    private func shouldActivateApp(_ app: NSRunningApplication) -> Bool {
        let skipBundleIDs = [
            "com.apple.UserNotificationCenter",
            "com.apple.loginwindow",
            "com.apple.dock",
        ]
        if let bundleID = app.bundleIdentifier, skipBundleIDs.contains(bundleID) {
            return false
        }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        return true
    }

    private func captureTargetApp() -> NSRunningApplication? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != selfPID {
            let bundleID = app.bundleIdentifier ?? ""
            let skipIDs = [
                "com.apple.UserNotificationCenter",
                "com.apple.loginwindow",
                "com.apple.dock",
            ]
            if !skipIDs.contains(bundleID) {
                return app
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if app.processIdentifier != selfPID
                && app.activationPolicy == .regular
                && app.isActive {
                return app
            }
        }
        return nil
    }
    
    func stopRecording() {
        guard isRecording else { return }
        audioRecorder.stop()
    }
    
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "VoiceInput 需要在 系统设置 → 隐私与安全性 → 辅助功能 中开启权限，才能监听全局快捷键 Ctrl+I。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    private func showMicrophoneAlert() {
        let alert = NSAlert()
        alert.messageText = "需要麦克风权限"
        alert.informativeText = "VoiceInput 需要麦克风权限才能录制语音。请在系统设置 → 隐私与安全性 → 麦克风中开启。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
}

extension AppDelegate: HotKeyDelegate {
    func hotKeyTriggered() {
        Logger.shared.log("快捷键触发")
        promptMode = false
        toggleRecording()
    }

    func promptHotKeyTriggered() {
        Logger.shared.log("Prompt 快捷键触发")
        promptMode = true
        toggleRecording()
    }
    
    private func toggleRecording() {
        guard !isProcessing else { return }
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
}

extension AppDelegate: AudioRecorderDelegate {
    func audioRecorderDidStart() {
        isRecording = true
        isStreamingTranscribing = false
        pendingSnapshotURL = nil
        streamingTypedText = ""
        streamingTypedLength = 0
        Logger.shared.log("录音已开始")
    }
    
    /// 音频快照回调，用于实时转录显示
    func audioRecorderDidSnapshot(url: URL) {
        // 普通模式由 Apple Speech 处理实时转录，跳过 Whisper 快照
        if appleSpeechActive && !promptMode {
            try? FileManager.default.removeItem(at: url)
            return
        }
        
        if isStreamingTranscribing {
            if let oldURL = pendingSnapshotURL {
                try? FileManager.default.removeItem(at: oldURL)
            }
            pendingSnapshotURL = url
            return
        }
        
        isStreamingTranscribing = true
        
        guard let localProvider = transcriptionProvider as? LocalWhisperProvider else {
            isStreamingTranscribing = false
            try? FileManager.default.removeItem(at: url)
            return
        }
        
        localProvider.transcribeSnapshot(audioURL: url) { [weak self] text in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: url)
            
            if let text = text, !text.isEmpty {
                // 更新录音面板显示
                self.recordingPanel.updatePartialText(text)
                
                // Prompt 模式：Whisper 快照仅显示预览，不打字
                // 打字只在停止后通过确认弹窗完成
            }
            
            self.isStreamingTranscribing = false
            
            if let nextURL = self.pendingSnapshotURL {
                self.pendingSnapshotURL = nil
                self.audioRecorderDidSnapshot(url: nextURL)
            }
        }
    }
    
    /// 计算增量文本：新转录结果中尚未打字的部分
    private func computeDelta(newText: String) -> String {
        let oldText = streamingTypedText
        if newText.hasPrefix(oldText) {
            // 新文本以旧文本开头，增量就是后面的部分
            return String(newText.dropFirst(oldText.count))
        }
        // 用最长公共前缀容错（Whisper 可能修正前面的错误）
        let oldChars = Array(oldText)
        let newChars = Array(newText)
        var commonPrefixLen = 0
        let minLen = min(oldChars.count, newChars.count)
        for i in 0..<minLen {
            if oldChars[i] == newChars[i] {
                commonPrefixLen += 1
            } else {
                break
            }
        }
        // 返回公共前缀之后的所有内容
        return String(newChars.dropFirst(commonPrefixLen))
    }
    
    func audioRecorderDidStop(url: URL?, averagePower: Float, peakPower: Float, duration: TimeInterval) {
        // 停止 Apple Speech 流式识别并获取结果
        let speechResult = SpeechStreamer.shared.stop()
        appleSpeechActive = false
        
        if let pendingURL = pendingSnapshotURL {
            try? FileManager.default.removeItem(at: pendingURL)
            pendingSnapshotURL = nil
        }
        
        guard let url = url else {
            isRecording = false
            recordingPanel.hide()
            return
        }
        
        Logger.shared.log("录音停止，时长：\(String(format: "%.1f", duration))s，平均音量：\(String(format: "%.1f", averagePower)) dB，峰值音量：\(String(format: "%.1f", peakPower)) dB")
        
        if averagePower < -55 && peakPower < -45 {
            Logger.shared.log("录音音量过低，可能没有录到声音", level: .warning)
            isRecording = false
            recordingPanel.hide()
            
            let alert = NSAlert()
            alert.messageText = "没有检测到声音"
            alert.informativeText = "请检查麦克风是否正常工作，或说话声音是否足够大。你也可以在系统设置 → 声音 → 输入中测试麦克风。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            return
        }
        
        isRecording = false
        isProcessing = true
        recordingPanel.setProcessing(true)
        
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isProcessing else { return }
            Logger.shared.log("转录超时（60s），强制恢复状态", level: .warning)
            self.isProcessing = false
            self.recordingPanel.hide()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeoutWorkItem)
        
        transcriptionProvider.transcribe(audioURL: url) { [weak self] text in
            guard let self = self else { return }
            let whisperText = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // 普通模式一律以 Whisper（或 API 转录）结果为准。
            // Apple Speech 的实时结果只作为转录完全失败时的兜底 —— 它的精度明显低于 Whisper，
            // 之前正是因为「有 Apple Speech 结果就直接结束」才让 base 模型 / 系统识别的问题暴露在正文里。
            let finalText = whisperText.isEmpty ? speechResult : whisperText

            if !finalText.isEmpty {
                Logger.shared.log("转录完成，来源：\(whisperText.isEmpty ? "Apple Speech 兜底" : "Whisper")，长度：\(finalText.count)，目标应用：\(self.previousApp?.localizedName ?? "未知")")
                
                if self.promptMode {
                    // Prompt 模式：AI 增强 → 确认弹窗
                    let enhancer = self.aiEnhancer
                    enhancer.enhance(text: finalText, forcePrompt: true) { enhancedText in
                        Logger.shared.log("Prompt 文本已就绪，长度：\(enhancedText.count)")
                        self.recordingPanel.hide()
                        self.isProcessing = false
                        
                        self.confirmationPanel.show(
                            text: enhancedText,
                            onInsert: {
                                Logger.shared.log("用户确认插入 Prompt 文本")
                                self.textInjector.type(text: enhancedText, targetApp: self.previousApp)
                                self.promptMode = false
                            },
                            onCancel: {
                                Logger.shared.log("用户取消插入")
                                self.promptMode = false
                            }
                        )
                    }
                } else {
                    // 普通模式：以 Whisper 结果一次性注入（不再用 Apple Speech 的中间结果）
                    self.recordingPanel.hide()
                    self.isProcessing = false
                    self.textInjector.type(text: finalText, targetApp: self.previousApp)
                    Logger.shared.log("普通模式完成（Whisper），插入\(finalText.count)字")
                    self.streamingTypedText = ""
                    self.streamingTypedLength = 0
                }
            } else {
                Logger.shared.log("转录结果为空", level: .warning)
                self.isProcessing = false
                self.recordingPanel.hide()
            }
        }
    }
    
    func audioRecorderDidFail(error: Error) {
        isRecording = false
        isProcessing = false
        recordingPanel.hide()
        
        if let audioError = error as? AudioRecorderError,
           audioError == .permissionDenied {
            showMicrophoneAlert()
        } else {
            Logger.shared.log("录音失败：\(error.localizedDescription)", level: .error)
            let alert = NSAlert()
            alert.messageText = "录音失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}
