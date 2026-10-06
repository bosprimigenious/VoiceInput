import SwiftUI
import AVFoundation
import ApplicationServices

// MARK: - AI 润色设置

struct AIEnhanceSettingsView: View {
    @AppStorage("aiEnhanceEnabled") private var aiEnhanceEnabled = false
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("openAIBaseURL") private var openAIBaseURL = "https://true-sota.com/v1"
    @AppStorage("aiEnhanceModel") private var aiEnhanceModel = "gpt-5.5"
    @State private var showAPIKey = false
    @State private var testStatus: TestStatus = .idle
    
    enum TestStatus {
        case idle, testing, success, failed(String)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("润色")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 4)
                
                Text("转录后的文本会自动经过语义修正，修复同音字错误和口语化表达。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                
                // API 配置
                SectionHeader(title: "API 配置", icon: "server.rack")
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Base URL")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("https://api.openai.com/v1", text: $openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack {
                        Group {
                            if showAPIKey {
                                TextField("sk-...", text: $openAIAPIKey)
                            } else {
                                SecureField("sk-...", text: $openAIAPIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .id(showAPIKey)
                        
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("模型")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("gpt-5.5", text: $aiEnhanceModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
                
                // 测试
                HStack(spacing: 10) {
                    Button {
                        testAPI()
                    } label: {
                        HStack(spacing: 4) {
                            if case .testing = testStatus {
                                ProgressView().controlSize(.small)
                            }
                            Text("测试连接")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    switch testStatus {
                    case .idle: EmptyView()
                    case .testing:
                        Text("测试中...").font(.system(size: 11)).foregroundStyle(.secondary)
                    case .success:
                        Label("成功", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(.green)
                    case .failed(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func testAPI() {
        testStatus = .testing
        var baseURL = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseURL.hasSuffix("/v1") && !baseURL.hasSuffix("/v1/") {
            baseURL = baseURL.hasSuffix("/") ? "\(baseURL)v1" : "\(baseURL)/v1"
        }
        let urlString = baseURL.hasSuffix("/")
            ? "\(baseURL)chat/completions"
            : "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            testStatus = .failed("URL 无效"); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        let body: [String: Any] = [
            "model": aiEnhanceModel,
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 5
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            testStatus = .failed("请求失败"); return
        }
        request.httpBody = httpBody
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { testStatus = .failed(error.localizedDescription.prefix(30).description); return }
                if let r = response as? HTTPURLResponse, (200...299).contains(r.statusCode) {
                    testStatus = .success
                } else {
                    testStatus = .failed("状态码 \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                }
            }
        }.resume()
    }
}

// MARK: - 通用设置

struct GeneralSettingsView: View {
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设置")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 4)
                
                VStack(spacing: 12) {
                    Toggle("启动时显示欢迎面板", isOn: $showWelcomeOnLaunch)
                        .font(.system(size: 12))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                
                // 权限
                SectionHeader(title: "权限", icon: "shield")
                
                VStack(spacing: 6) {
                    PermissionRow(title: "麦克风", ok: micOK())
                    PermissionRow(title: "辅助功能", ok: accOK())
                }
                
                // 日志
                HStack {
                    Button("查看日志") {
                        let p = logPath()
                        if let p = p, FileManager.default.fileExists(atPath: p) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: p))
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    
                    Button("清除日志") {
                        if let p = logPath() { try? FileManager.default.removeItem(atPath: p) }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                }
            }
            .padding(20)
        }
    }
    
    private func micOK() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    private func accOK() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func logPath() -> String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("VoiceInput/app.log").path
    }
}

struct PermissionRow: View {
    let title: String
    let ok: Bool
    
    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Text(ok ? "已授权" : "未授权")
                .font(.system(size: 11))
                .foregroundStyle(ok ? .green : .orange)
        }
    }
}

// MARK: - 关于

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("关于")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 4)
                
                HStack(spacing: 14) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VoiceInput").font(.system(size: 18, weight: .bold))
                        Text("版本 1.2.0").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("macOS 语音转文字").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("隐私", systemImage: "lock.shield")
                        .font(.system(size: 13, weight: .semibold))
                    Text("语音转录全程本地处理。API Key 仅保存在本地。不收集任何用户数据。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("快捷键", systemImage: "command")
                        .font(.system(size: 13, weight: .semibold))
                    HStack { Text("Ctrl + I").font(.system(size: 11, design: .monospaced)).fontWeight(.bold)
                        Text("录音").font(.system(size: 11)).foregroundStyle(.secondary) }
                    HStack { Text("Ctrl + Shift + I").font(.system(size: 11, design: .monospaced)).fontWeight(.bold)
                        Text("Prompt 模式").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                
                Text("© 2024 VoiceInput · whisper.cpp 本地转录")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
    }
}
