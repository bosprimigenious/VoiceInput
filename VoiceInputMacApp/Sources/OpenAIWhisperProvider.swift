import Foundation

/// 基于 OpenAI Whisper API 的云端转录提供者
class OpenAIWhisperProvider: TranscriptionProvider {
    var name: String { "OpenAI API" }
    
    var isAvailable: Bool {
        return !apiKey.isEmpty
    }
    
    private var apiKey: String {
        return UserDefaults.standard.string(forKey: "openAIAPIKey") ?? ""
    }
    
    func transcribe(audioURL: URL, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let key = self.apiKey
            guard !key.isEmpty else {
                Logger.shared.log("OpenAI API key 未设置", level: .error)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            Logger.shared.log("开始 OpenAI 转录：\(audioURL.lastPathComponent)")
            let start = Date()
            
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            
            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            
            // 音频文件
            if let audioData = try? Data(contentsOf: audioURL) {
                body.append(formDataField(boundary: boundary, name: "file", filename: audioURL.lastPathComponent, contentType: "audio/wav", data: audioData))
            } else {
                Logger.shared.log("无法读取音频文件", level: .error)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // 模型
            body.append(formTextField(boundary: boundary, name: "model", value: "whisper-1"))
            // 语言：简体中文
            body.append(formTextField(boundary: boundary, name: "language", value: "zh"))
            // 返回纯文本
            body.append(formTextField(boundary: boundary, name: "response_format", value: "text"))
            // 提示词，引导简体中文
            body.append(formTextField(boundary: boundary, name: "prompt", value: "以下是普通话简体中文转录："))
            
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    Logger.shared.log("OpenAI 请求失败：\(error.localizedDescription)", level: .error)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.shared.log("OpenAI 响应无效", level: .error)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    let responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(无响应体)"
                    Logger.shared.log("OpenAI 请求失败，状态码：\(httpResponse.statusCode)，响应：\(responseBody)", level: .error)
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                let text = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let elapsed = Date().timeIntervalSince(start)
                Logger.shared.log("OpenAI 转录完成，耗时 \(String(format: "%.1f", elapsed))s，结果：\(text ?? "(空)")")
                
                // 清理临时音频文件
                try? FileManager.default.removeItem(at: audioURL)
                
                DispatchQueue.main.async {
                    completion(text?.isEmpty == true ? nil : text)
                }
            }
            task.resume()
        }
    }
    
    private func formDataField(boundary: String, name: String, filename: String, contentType: String, data: Data) -> Data {
        var field = Data()
        field.append("--\(boundary)\r\n".data(using: .utf8)!)
        field.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        field.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        field.append(data)
        field.append("\r\n".data(using: .utf8)!)
        return field
    }
    
    private func formTextField(boundary: String, name: String, value: String) -> Data {
        var field = Data()
        field.append("--\(boundary)\r\n".data(using: .utf8)!)
        field.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        field.append(value.data(using: .utf8)!)
        field.append("\r\n".data(using: .utf8)!)
        return field
    }
}
