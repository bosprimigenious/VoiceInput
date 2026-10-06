import Foundation

/// 基于本地 whisper.cpp 的离线转录提供者
class LocalWhisperProvider: TranscriptionProvider {
    var name: String { "本地 Whisper" }

    /// 默认模型：small。
    ///
    /// 同一段 14.5 秒真人录音实测（M5 / whisper.cpp 1.9.1 / CPU / `-t 8`）：
    ///   base   0.39s  明显崩坏（「输入」→「诗课」）
    ///   small  1.38s  有错词，但整句可读          ← 默认
    ///   medium 2.78s  接近 turbo
    ///   turbo  3.20s  近乎完美，但最慢
    ///
    /// 2026-10-06 一度把默认设成 turbo（追求精度），实测反馈「太慢」，
    /// 于是默认回到 small：日常听写够用，且比 turbo 快 2.3 倍。
    /// 需要精度时在 设置 → 模型 里切 medium / turbo。
    static let defaultModelName = "ggml-small.bin"

    /// 可选的 initial prompt（whisper 的 `--prompt`）。
    ///
    /// 实测结论（M5 / whisper.cpp 1.9.1，把同一段真人录音切成 14 秒短句）：
    /// 一旦传了 `--prompt`，只要里面含一串顿号分隔的词表，medium 就会在短音频上
    /// 「接着往下续写词表」而不是转写，直接吃掉大半内容（例如把 41 个字压成
    /// “本地模型﹑不需要输入﹑需要在安静的环境使劲﹑”）；turbo 也会出现术语漂移。
    /// 不加 prompt 时 medium / turbo 的整句准确率反而最高。
    ///
    /// 所以**默认留空**，只在用户明确填写时才传。
    private var userPrompt: String? {
        let stored = (UserDefaults.standard.string(forKey: "whisperPrompt") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? nil : stored
    }
    
    var isAvailable: Bool {
        guard let cliPath = findResource(named: "whisper-cli", ext: "") else { return false }
        guard let modelPath = LocalWhisperProvider.findModelPath(resolvedModelName()) else { return false }
        return FileManager.default.isExecutableFile(atPath: cliPath)
            && FileManager.default.fileExists(atPath: modelPath)
    }
    
    // MARK: - 模型存放位置
    //
    // 大模型（medium / large-v3-turbo）体积 1.4-1.6GB，不放进 App 安装包：
    // 一是安装包会大到离谱，二是用户没法单独删掉它。
    // 它们统一放在外置目录，App 包内只留一个小模型兜底。
    //   ~/Library/Application Support/VoiceInput/Models/
    
    /// 外置模型目录
    static var externalModelDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("VoiceInput/Models", isDirectory: true)
    }
    
    /// 确保外置模型目录存在
    @discardableResult
    static func ensureExternalModelDirectory() -> URL? {
        guard let dir = externalModelDirectory else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    static func isModelFileName(_ name: String) -> Bool {
        name.hasPrefix("ggml-") && name.hasSuffix(".bin")
    }
    
    /// 查找模型文件：先 App 包内，再外置模型目录
    static func findModelPath(_ fileName: String) -> String? {
        let name = (fileName as NSString).deletingPathExtension
        // 1. App 包内
        if let path = Bundle.main.path(forResource: name, ofType: "bin"),
           FileManager.default.fileExists(atPath: path) {
            return path
        }
        // 2. 可执行文件同级的 Resources（开发调试 / 直接跑二进制）
        let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        let executableURL = URL(fileURLWithPath: executablePath)
        for dir in [
            executableURL.deletingLastPathComponent().appendingPathComponent("Resources"),
            executableURL.deletingLastPathComponent().appendingPathComponent("VoiceInputMacApp.app/Contents/Resources")
        ] {
            let candidate = dir.appendingPathComponent(fileName).path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        // 3. 外置模型目录
        if let dir = externalModelDirectory {
            let candidate = dir.appendingPathComponent(fileName).path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }
    
    /// 当前可用的全部模型文件名（App 包内 + 外置目录）
    static func availableModelNames() -> [String] {
        var names = Set<String>()
        if let resourcePath = Bundle.main.resourcePath,
           let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
            names.formUnion(files.filter { isModelFileName($0) })
        }
        if let dir = externalModelDirectory,
           let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            names.formUnion(files.filter { isModelFileName($0) })
        }
        return Array(names)
    }
    
    /// 模型精度优先级：选中的模型缺失时按这个顺序回退。
    /// 原来用的是 `models.sorted().first`（文件名字母序），第一个正好是
    /// `ggml-base.bin` —— 也就是精度最差的那一档，等于悄悄把用户降级了。
    static let modelPreference = [
        "ggml-large-v3-turbo.bin",
        "ggml-medium.bin",
        "ggml-small.bin",
        "ggml-base.bin",
        "ggml-tiny.bin",
    ]

    /// 获取实际可用的模型文件名，如果选中的不存在则按精度优先级回退
    private func resolvedModelName() -> String {
        let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? LocalWhisperProvider.defaultModelName
        // 如果选中的模型存在，直接返回
        if LocalWhisperProvider.findModelPath(selected) != nil {
            return selected
        }
        // 选中的模型不存在，按精度优先级回退
        let available = LocalWhisperProvider.availableModelNames()
        if let fallback = LocalWhisperProvider.modelPreference.first(where: { available.contains($0) })
            ?? available.sorted().first {
            Logger.shared.log("模型 \(selected) 不存在，按精度优先级回退到 \(fallback)", level: .warning)
            UserDefaults.standard.set(fallback, forKey: "selectedModel")
            return fallback
        }
        return selected
    }

    private var selectedModel: String {
        return UserDefaults.standard.string(forKey: "selectedModel") ?? LocalWhisperProvider.defaultModelName
    }
    
    /// 查找资源文件路径：支持 .app bundle 和直接运行二进制
    private func findResource(named name: String, ext: String) -> String? {
        // 1. 优先从 Bundle 查找
        if let path = Bundle.main.path(forResource: name, ofType: ext) {
            return path
        }
        
        // 2. 直接运行二进制时，资源在可执行文件同目录的 Resources 中
        let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        let executableURL = URL(fileURLWithPath: executablePath)
        let resourceDir = executableURL.deletingLastPathComponent().appendingPathComponent("Resources")
        let fileName = ext.isEmpty ? name : "\(name).\(ext)"
        let candidate = resourceDir.appendingPathComponent(fileName).path
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        
        // 3. 从项目构建目录查找（开发调试）
        let buildResourceDir = executableURL.deletingLastPathComponent()
            .appendingPathComponent("VoiceInputMacApp.app/Contents/Resources")
        let buildCandidate = buildResourceDir.appendingPathComponent(fileName).path
        if FileManager.default.fileExists(atPath: buildCandidate) {
            return buildCandidate
        }
        
        return nil
    }
    
    /// whisper-cli 使用的线程数。
    ///
    /// whisper.cpp 默认 `-t 4`，在 10 核（4P+6E）的 M5 上白白浪费性能。
    /// 实测同一段 14.5 秒录音（whisper.cpp 1.9.1，CPU）：
    ///   turbo  -t 4 → 4.58s   -t 8 → 3.51s
    ///   small  -t 4 → 1.69s   -t 8 → 1.38s
    /// `-t 10` 反而略慢（6 个能效核参与调度），所以取「核数 - 2」。
    private static var threadCount: Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return max(4, min(8, cores - 2))
    }
    
    /// 构造 whisper-cli 参数（快照与整段转录共用，保证两边行为一致）
    private func whisperArguments(modelPath: String, audioPath: String, outputPrefix: String) -> [String] {
        var args = [
            "-m", modelPath,
            "-f", audioPath,
            "-l", "zh",
            "-t", String(LocalWhisperProvider.threadCount)
        ]
        // 默认不传 prompt，见 userPrompt 的说明
        if let prompt = userPrompt {
            args += ["--prompt", prompt]
        }
        args += [
            "--no-prints",
            "-otxt",
            "-of", outputPrefix
        ]
        return args
    }

    /// 读取 whisper 输出并清理静音段产生的标记
    private func readTranscription(outputPrefix: String) -> String? {
        let txtPath = outputPrefix + ".txt"
        guard let raw = try? String(contentsOfFile: txtPath, encoding: .utf8) else { return nil }
        let cleaned = LocalWhisperProvider.cleanTranscription(raw)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// 去掉 whisper 在静音/噪声段写出的占位标记，例如 [BLANK_AUDIO]、(音乐)、♪
    static func cleanTranscription(_ text: String) -> String {
        let markers = [
            "[BLANK_AUDIO]", "[ Silence ]", "[silence]", "[ Silence]", "[silence ]",
            "[Music]", "[MUSIC]", "[music]", "[SOUND]", "[ Pause ]",
            "(音乐)", "（音乐）", "[音乐]", "(掌声)", "（掌声）", "(笑声)",
            "♪", "🎵"
        ]
        var result = text
        for marker in markers {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        // 去掉标记后可能残留只有标点/空白的行
        let lines = result
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty && line.rangeOfCharacter(from: .alphanumerics) != nil
            }
        result = lines.joined(separator: "\n")
        // 中英混排时 whisper 常在英文前后多留空格，收敛为单个空格
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 转录音频快照（不删除源文件，用于实时转录）
    func transcribeSnapshot(audioURL: URL, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            guard let cliPath = self.findResource(named: "whisper-cli", ext: "") else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let actualModel = self.resolvedModelName()
            guard let modelPath = LocalWhisperProvider.findModelPath(actualModel) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("whisper_snapshot_output_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            
            let outputPrefix = outputDir.appendingPathComponent("result").path
            
            let task = Process()
            task.launchPath = cliPath
            task.arguments = self.whisperArguments(
                modelPath: modelPath,
                audioPath: audioURL.path,
                outputPrefix: outputPrefix
            )
            
            let pipe = Pipe()
            task.standardError = pipe
            
            do {
                try task.run()
                
                // 15秒超时
                let timeoutWorkItem = DispatchWorkItem {
                    if task.isRunning { task.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeoutWorkItem)
                
                task.waitUntilExit()
                timeoutWorkItem.cancel()
                
                guard task.terminationStatus == 0 else {
                    try? FileManager.default.removeItem(at: outputDir)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                let resultText = self.readTranscription(outputPrefix: outputPrefix)
                
                try? FileManager.default.removeItem(at: outputDir)
                DispatchQueue.main.async { completion(resultText) }
            } catch {
                try? FileManager.default.removeItem(at: outputDir)
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    func transcribe(audioURL: URL, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            Logger.shared.log("开始本地 Whisper 转录：\(audioURL.lastPathComponent)")
            
            guard let cliPath = self.findResource(named: "whisper-cli", ext: "") else {
                Logger.shared.log("找不到 whisper-cli，搜索路径：\(Bundle.main.resourcePath ?? "无")", level: .error)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let actualModel = self.resolvedModelName()
            guard let modelPath = LocalWhisperProvider.findModelPath(actualModel) else {
                Logger.shared.log("找不到任何可用的模型文件", level: .error)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            Logger.shared.log("使用 whisper-cli: \(cliPath)", level: .debug)
            Logger.shared.log("使用模型: \(modelPath)", level: .debug)
            let debugAudioURL = self.saveDebugAudioCopy(audioURL)
            if let debugAudioURL = debugAudioURL {
                Logger.shared.log("已保存最近一次录音：\(debugAudioURL.path)")
            }
            
            let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("whisper_output_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            
            let outputPrefix = outputDir.appendingPathComponent("result").path
            
            let task = Process()
            task.launchPath = cliPath
            task.arguments = self.whisperArguments(
                modelPath: modelPath,
                audioPath: audioURL.path,
                outputPrefix: outputPrefix
            )
            
            let pipe = Pipe()
            task.standardError = pipe
            
            do {
                let start = Date()
                try task.run()
                task.waitUntilExit()
                let elapsed = Date().timeIntervalSince(start)

                let stderrData = pipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                guard task.terminationStatus == 0 else {
                    if !stderr.isEmpty {
                        Logger.shared.log("whisper stderr: \(stderr)", level: .error)
                    }
                    Logger.shared.log("whisper-cli 退出码：\(task.terminationStatus)，本地转录失败", level: .error)
                    self.saveDebugTranscription(nil)
                    try? FileManager.default.removeItem(at: outputDir)
                    try? FileManager.default.removeItem(at: audioURL)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                let resultText = self.readTranscription(outputPrefix: outputPrefix)
                
                if !stderr.isEmpty {
                    Logger.shared.log("whisper stderr: \(stderr)", level: .debug)
                }
                
                try? FileManager.default.removeItem(at: outputDir)
                try? FileManager.default.removeItem(at: audioURL)
                self.saveDebugTranscription(resultText)
                
                Logger.shared.log("本地转录完成，耗时 \(String(format: "%.1f", elapsed))s，结果：\(resultText ?? "(空)")")
                
                DispatchQueue.main.async {
                    completion(resultText)
                }
            } catch {
                Logger.shared.log("转录失败：\(error)", level: .error)
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func debugDirectoryURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDir = appSupport.appendingPathComponent("VoiceInput", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    private func saveDebugAudioCopy(_ audioURL: URL) -> URL? {
        guard let appDir = debugDirectoryURL() else { return nil }

        let targetURL = appDir.appendingPathComponent("last-recording.wav")
        try? FileManager.default.removeItem(at: targetURL)

        do {
            try FileManager.default.copyItem(at: audioURL, to: targetURL)
            return targetURL
        } catch {
            Logger.shared.log("保存最近一次录音失败：\(error.localizedDescription)", level: .warning)
            return nil
        }
    }

    private func saveDebugTranscription(_ text: String?) {
        guard let appDir = debugDirectoryURL() else { return }

        let targetURL = appDir.appendingPathComponent("last-transcription.txt")
        let output = text ?? ""
        do {
            try output.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.shared.log("保存最近一次转录文本失败：\(error.localizedDescription)", level: .warning)
        }
    }
}
