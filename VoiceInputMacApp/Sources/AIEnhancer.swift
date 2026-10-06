import Foundation

/// AI 文本润色器：将转录的口语文本通过 OpenAI API 转化为专业 Prompt
class AIEnhancer {
    
    /// 是否启用 AI 润色
    var isEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "aiEnhanceEnabled")
    }
    
    /// 当前选中的 Prompt 模式 ID
    private var selectedModeID: String {
        return UserDefaults.standard.string(forKey: "aiEnhanceMode") ?? "default"
    }
    
    /// OpenAI API Key
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "openAIAPIKey") ?? ""
    }
    
    /// 自定义 API Base URL（可选，用于兼容其他 API）
    private var apiBaseURL: String {
        var url = UserDefaults.standard.string(forKey: "openAIBaseURL") ?? "https://api.openai.com/v1"
        // 自动补全 /v1：很多代理服务只填了域名，需要补全到 /v1 才能调用 chat/completions
        url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty && !url.hasSuffix("/v1") && !url.hasSuffix("/v1/") {
            // 如果 URL 看起来是根域名（没有路径），自动补 /v1
            let hasPath = URL(string: url)?.path.isEmpty == false && URL(string: url)?.path != "/"
            if !hasPath {
                url = url.hasSuffix("/") ? "\(url)v1" : "\(url)/v1"
            }
        }
        return url
    }
    
    /// 润色模型
    private var model: String {
        let stored = UserDefaults.standard.string(forKey: "aiEnhanceModel") ?? ""
        return stored.isEmpty ? "gpt-5.5" : stored
    }
    
    /// 对转录文本进行 AI 润色
    /// - Parameters:
    ///   - text: 原始转录文本
    ///   - forcePrompt: 强制使用 Prompt 模式
    ///   - completion: 润色后的文本（失败时返回原文）
    func enhance(text: String, forcePrompt: Bool = false, completion: @escaping (String) -> Void) {
        let key = apiKey
        
        // 第一步：本地纠错（快速，无需网络）
        let correctedText = localCorrection(text)
        
        // 始终开启 AI 语义修正，这是修正转录错误的核心
        guard !key.isEmpty else {
            // API Key 未设置，仅返回本地纠错结果
            Logger.shared.log("AI 语义修正：API Key 未设置，仅应用本地纠错", level: .warning)
            completion(correctedText)
            return
        }
        
        // 获取当前模式的 system prompt
        let mode = PromptTemplates.allModes.first { $0.id == selectedModeID }
            ?? PromptTemplates.allModes[0]
        
        Logger.shared.log("AI 润色开始，模式：\(mode.name)，模型：\(model)")
        let start = Date()
        
        // 构建请求
        let urlString = apiBaseURL.hasSuffix("/")
            ? "\(apiBaseURL)chat/completions"
            : "\(apiBaseURL)/chat/completions"
        
        guard let url = URL(string: urlString) else {
            Logger.shared.log("AI 润色：API URL 无效：\(urlString)", level: .error)
            completion(correctedText)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": mode.systemPrompt],
                ["role": "user", "content": correctedText]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            Logger.shared.log("AI 润色：序列化请求体失败", level: .error)
            completion(text)
            return
        }
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let elapsed = Date().timeIntervalSince(start)
            
            if let error = error {
                Logger.shared.log("AI 润色请求失败：\(error.localizedDescription)，返回纠错文本", level: .error)
                DispatchQueue.main.async { completion(correctedText) }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(无响应体)"
                Logger.shared.log("AI 润色失败，状态码：\(statusCode)，响应：\(body)，返回纠错文本", level: .error)
                DispatchQueue.main.async { completion(correctedText) }
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Logger.shared.log("AI 润色：解析响应失败，返回纠错文本", level: .error)
                DispatchQueue.main.async { completion(correctedText) }
                return
            }
            
            guard let content = self.extractText(from: json), !content.isEmpty else {
                Logger.shared.log("AI 润色：无法从响应中提取文本，返回纠错文本", level: .error)
                DispatchQueue.main.async { completion(correctedText) }
                return
            }
            
            let enhanced = content.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.shared.log("AI 润色完成，耗时 \(String(format: "%.1f", elapsed))s")
            Logger.shared.log("  原文：\(correctedText.prefix(50))...")
            Logger.shared.log("  润色：\(enhanced.prefix(50))...")
            
            DispatchQueue.main.async {
                completion(enhanced.isEmpty ? correctedText : enhanced)
            }
        }
        task.resume()
    }
    
    /// 对会议转录文本进行 AI 总结
    func summarize(text: String, completion: @escaping (String) -> Void) {
        let key = apiKey
        guard !key.isEmpty else {
            completion("（AI 总结需要配置 API Key）")
            return
        }
        
        let urlString = apiBaseURL.hasSuffix("/")
            ? "\(apiBaseURL)chat/completions"
            : "\(apiBaseURL)/chat/completions"
        
        guard let url = URL(string: urlString) else {
            completion("（API URL 无效）")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        let systemPrompt = """
        你是一个专业的会议纪要整理助手。请将以下会议录音转录文本整理为结构清晰的会议纪要。
        
        输出格式：
        1. **会议主题**：一句话概括
        2. **关键讨论点**：列出 3-5 个主要话题
        3. **决议事项**：明确列出达成的共识或决定
        4. **待办事项**：明确列出后续需要执行的任务（如有负责人则标注）
        
        要求：
        - 去除口语化表达、重复内容和无关废话
        - 保留关键信息和数据
        - 使用清晰的中文表达
        """
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "请整理以下会议录音转录：\n\n\(text)"]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion("（请求序列化失败）")
            return
        }
        request.httpBody = httpBody
        
        Logger.shared.log("开始 AI 会议总结，转录长度：\(text.count) 字")
        let start = Date()
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.shared.log("AI 总结失败：\(error.localizedDescription)", level: .error)
                DispatchQueue.main.async { completion("（AI 总结失败：\(error.localizedDescription)）") }
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(无响应体)"
            Logger.shared.log("AI 总结响应状态码：\(statusCode)，响应体：\(body)", level: .info)
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(无响应体)"
                if body.hasPrefix("<!doctype") || body.hasPrefix("<html") {
                    Logger.shared.log("AI 总结返回了网页而不是 JSON，请检查 API Base URL 是否包含 /v1 路径", level: .error)
                    DispatchQueue.main.async { completion("（API 地址错误：请检查 Base URL 是否以 /v1 结尾）") }
                } else {
                    Logger.shared.log("AI 总结响应不是有效 JSON，响应体：\(body)", level: .error)
                    DispatchQueue.main.async { completion("（AI 总结响应解析失败）") }
                }
                return
            }
            
            // 优先显示 API 返回的错误信息（如模型不支持）
            if let errorMessage = self.extractErrorMessage(from: json) {
                Logger.shared.log("AI 总结 API 返回错误：\(errorMessage)", level: .error)
                DispatchQueue.main.async { completion("（AI 总结失败：\(errorMessage)）") }
                return
            }
            
            // 尝试多种常见响应格式提取文本
            let extractedText = self.extractText(from: json)
            
            guard let text = extractedText, !text.isEmpty else {
                Logger.shared.log("AI 总结响应解析失败，响应体：\(body)", level: .error)
                DispatchQueue.main.async { completion("（AI 总结响应解析失败）") }
                return
            }
            
            let elapsed = Date().timeIntervalSince(start)
            Logger.shared.log("AI 会议总结完成，耗时 \(String(format: "%.1f", elapsed))s")
            DispatchQueue.main.async { completion(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        task.resume()
    }
    
    /// 从 API 错误响应中提取可读错误信息
    private func extractErrorMessage(from json: [String: Any]) -> String? {
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let error = json["error"] as? String {
            return error
        }
        if let message = json["message"] as? String {
            return message
        }
        return nil
    }
    
    /// 从各种 API 响应格式中提取文本内容
    private func extractText(from json: [String: Any]) -> String? {
        // 1. OpenAI 标准格式：choices[0].message.content
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        // 2. 流式格式：choices[0].delta.content
        if let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let delta = firstChoice["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        
        // 3. 某些代理格式：data.choices[0].message.content
        if let data = json["data"] as? [String: Any],
           let choices = data["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        // 4. 简单文本格式：text 或 content 或 response
        if let content = json["text"] as? String {
            return content
        }
        if let content = json["content"] as? String {
            return content
        }
        if let content = json["response"] as? String {
            return content
        }
        
        // 5. 智谱/文心等格式：result
        if let content = json["result"] as? String {
            return content
        }
        
        return nil
    }
    
    // MARK: - 本地纠错（Whisper 常见同音错字）
    
    /// 常见 Whisper 中文同音错字纠正表
    private static let typoCorrections: [(wrong: String, correct: String)] = [
        // UI/UX 相关
        ("UIAX", "UI/UX"),
        ("UAX", "UX"),
        ("UIA", "UI"),
        // 语音转文字常见错字 - “实施”系列
        ("实施转录", "实时转录"),
        ("实施转路", "实时转录"),
        ("实施输入", "实时输入"),
        ("实施转写", "实时转写"),
        ("实施记录", "实时记录"),
        ("实施语音", "实时语音"),
        ("实施显示", "实时显示"),
        ("实施翻译", "实时翻译"),
        ("实施转录", "实时转录"),
        // “牛头不对马嘴” 系列
        ("扭头不对马嘴", "牛头不对马嘴"),
        ("牛头不对马嘴", "牛头不对马嘴"), // 保留正确
        // 吐字/发音 相关
        ("吐刺", "吐字"),
        ("兔刺", "吐字"),
        // 转录/输入 相关
        ("转路", "转录"),
        ("赚录", "转录"),
        ("殊入", "输入"),
        // 其他常见同音错字
        ("因为因", "因为"),
        ("然后然后", "然后"),
        ("嗯嗯", ""),
        ("啊嗯", ""),
        ("这个这个", "这个"),
        ("那个那个", "那个"),
        ("就是说", ""),
        ("对对对", ""),
        // 技术术语常见错字
        ("见本", "脚本"),
        ("脚本", "脚本"), // 保留正确
        ("接口", "接口"), // 保留正确
        ("摸块", "模块"),
        ("摸型", "模型"),
        ("建摸", "建模"),
        ("开园", "开源"),
        ("源玛", "源码"),
        ("代玛", "代码"),
        ("偏移", "偏移"),
        ("构健", "构建"),
        ("部薯", "部署"),
    ]
    
    /// 本地快速纠错（基于同音错字表）
    private func localCorrection(_ text: String) -> String {
        var result = text
        for (wrong, correct) in AIEnhancer.typoCorrections {
            if result.contains(wrong) {
                result = result.replacingOccurrences(of: wrong, with: correct)
                Logger.shared.log("本地纠错：'\(wrong)' → '\(correct)'", level: .debug)
            }
        }
        // 去除重复空格
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
