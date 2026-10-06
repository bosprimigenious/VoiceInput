import SwiftUI
import AVFoundation
import ApplicationServices

/// 系统设置窗口（Cmd+, 打开）
struct SettingsView: View {
    var body: some View {
        TabView {
            SettingsGeneralTab()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }
            
            SettingsModelTab()
                .tabItem {
                    Label("模型", systemImage: "cpu")
                }
            
            SettingsPermissionsTab()
                .tabItem {
                    Label("权限", systemImage: "lock.shield")
                }
            
            SettingsLogsTab()
                .tabItem {
                    Label("日志", systemImage: "doc.text")
                }
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - 通用设置 Tab

struct SettingsGeneralTab: View {
    @AppStorage("showWelcomeOnLaunch") private var showWelcomeOnLaunch = true
    @AppStorage("selectedProvider") private var selectedProvider = "local"
    
    var body: some View {
        Form {
            Section("转录引擎") {
                Picker("引擎", selection: $selectedProvider) {
                    Text("本地 Whisper（离线）").tag("local")
                    Text("OpenAI API（联网）").tag("openai")
                }
                .pickerStyle(.radioGroup)
            }
            
            Section("启动") {
                Toggle("启动时显示欢迎面板", isOn: $showWelcomeOnLaunch)
            }
            
            Section("快捷键") {
                HStack {
                    Text("Ctrl + I").font(.system(.body, design: .monospaced)).fontWeight(.bold)
                    Text("开始/停止录音")
                }
                HStack {
                    Text("Ctrl + Shift + I").font(.system(.body, design: .monospaced)).fontWeight(.bold)
                    Text("Prompt 模式")
                }
            }
        }
        .padding()
    }
}

// MARK: - 模型设置 Tab

struct SettingsModelTab: View {
    @AppStorage("selectedModel") private var selectedModel = LocalWhisperProvider.defaultModelName
    @AppStorage("whisperPrompt") private var whisperPrompt = ""
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @AppStorage("openAIBaseURL") private var openAIBaseURL = "https://true-sota.com"
    
    private let models = [
        ("ggml-tiny.bin", "~75MB，最快"),
        ("ggml-base.bin", "~142MB，较快"),
        ("ggml-small.bin", "~466MB，快（推荐）"),
        ("ggml-medium.bin", "~1.5GB，精确"),
        ("ggml-large-v3-turbo.bin", "~1.6GB，最精确但慢")
    ]
    
    var body: some View {
        Form {
            Section("本地模型") {
                Picker("模型", selection: $selectedModel) {
                    ForEach(models, id: \.0) { model in
                        Text("\(model.0) (\(model.1))").tag(model.0)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            Section("转录提示词（进阶，默认留空）") {
                TextField("initial prompt", text: $whisperPrompt, axis: .vertical)
                    .lineLimit(2...4)
                Text("留空即不传 --prompt，实测短句准确率最高。填成顿号分隔的词表会让 medium 续写词表、吃掉正文，请慎用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("OpenAI API") {
                TextField("Base URL", text: $openAIBaseURL)
                SecureField("API Key", text: $openAIAPIKey)
                Text("API Key 仅保存在本地，不上传到任何服务器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - 权限设置 Tab

struct SettingsPermissionsTab: View {
    @State private var micStatus = "检查中..."
    @State private var accStatus = "检查中..."
    
    var body: some View {
        Form {
            Section("系统权限") {
                HStack {
                    Image(systemName: "mic.fill").frame(width: 20)
                    Text("麦克风")
                    Spacer()
                    Text(micStatus)
                        .foregroundStyle(micStatus == "已授权" ? .green : .orange)
                    if micStatus != "已授权" {
                        Button("打开设置") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                    }
                }
                
                HStack {
                    Image(systemName: "accessibility").frame(width: 20)
                    Text("辅助功能")
                    Spacer()
                    Text(accStatus)
                        .foregroundStyle(accStatus == "已授权" ? .green : .orange)
                    if accStatus != "已授权" {
                        Button("打开设置") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
            
            Text("权限修改后可能需要重启应用才能生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            updateStatuses()
        }
    }
    
    private func updateStatuses() {
        switch AudioRecorder.microphonePermission {
        case .authorized: micStatus = "已授权"
        case .denied: micStatus = "已拒绝"
        case .restricted: micStatus = "受限制"
        default: micStatus = "未授权"
        }
        
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        accStatus = AXIsProcessTrustedWithOptions(options as CFDictionary) ? "已授权" : "未授权"
    }
}

// MARK: - 日志 Tab

struct SettingsLogsTab: View {
    @State private var logContent = "加载中..."
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用日志")
                    .font(.headline)
                Spacer()
                Button("刷新") { loadLog() }
                Button("清除") {
                    let logPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                        .first?.appendingPathComponent("VoiceInput/app.log")
                    if let path = logPath {
                        try? FileManager.default.removeItem(at: path)
                        logContent = "日志已清除"
                    }
                }
                Button("在 Finder 中打开") {
                    let logPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                        .first?.appendingPathComponent("VoiceInput/app.log")
                    if let path = logPath {
                        NSWorkspace.shared.open(path)
                    }
                }
            }
            
            ScrollView {
                Text(logContent)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(Color.black.opacity(0.05))
            .cornerRadius(6)
        }
        .padding()
        .onAppear { loadLog() }
    }
    
    private func loadLog() {
        let logPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("VoiceInput/app.log")
        if let path = logPath,
           let content = try? String(contentsOf: path, encoding: .utf8) {
            logContent = String(content.suffix(5000))
        } else {
            logContent = "暂无日志"
        }
    }
}
