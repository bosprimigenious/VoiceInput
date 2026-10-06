import SwiftUI
import AVFoundation
import ApplicationServices

struct ContentView: View {
    @Binding var selectedTab: SidebarTab
    @AppStorage("selectedProvider") private var selectedProvider = "local"
    @AppStorage("selectedModel") private var selectedModel = LocalWhisperProvider.defaultModelName
    @AppStorage("aiEnhanceEnabled") private var aiEnhanceEnabled = false
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .meeting:
            MeetingView()
        case .transcription:
            TranscriptionSettingsView()
        case .ai:
            AIEnhanceSettingsView()
        case .settings:
            GeneralSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            sidebarView
            Divider()
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    // App 标识
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.tint)
                        Text("VoiceInput")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    
                    // 导航项
                    VStack(spacing: 2) {
                        ForEach(SidebarTab.allCases) { tab in
                            NavItem(
                                icon: tab.icon,
                                title: tab.rawValue,
                                isSelected: selectedTab == tab
                            ) {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 14)
                
                Spacer()
                
                // 底部状态
                VStack(spacing: 8) {
                    Divider()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("就绪")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedProvider == "openai" ? "API" : "本地")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .frame(width: 160)
            .background(Color.primary.opacity(0.03))
    }
}

// MARK: - Nav Item

struct NavItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @AppStorage("selectedProvider") private var selectedProvider = "local"
    @AppStorage("selectedModel") private var selectedModel = LocalWhisperProvider.defaultModelName
    @State private var accessibilityEnabled = false
    @State private var microphoneEnabled = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题
                Text("概览")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 4)
                
                // 快捷键
                HStack(spacing: 10) {
                    KeyCard(keys: "Ctrl + I", desc: "录音转录")
                    KeyCard(keys: "Ctrl + Shift + I", desc: "Prompt 模式")
                }
                
                // 状态
                VStack(alignment: .leading, spacing: 10) {
                    Label("状态", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                    
                    HStack(spacing: 16) {
                        StatusItem(
                            icon: selectedProvider == "openai" ? "cloud" : "cpu",
                            label: selectedProvider == "openai" ? "API 转录" : "本地转录",
                            ok: true
                        )
                        StatusItem(
                            icon: "waveform",
                            label: modelName(selectedModel),
                            ok: true
                        )
                    }
                    
                    HStack(spacing: 16) {
                        StatusItem(
                            icon: accessibilityEnabled ? "checkmark.shield" : "xmark.shield",
                            label: "辅助功能",
                            ok: accessibilityEnabled
                        )
                        StatusItem(
                            icon: microphoneEnabled ? "mic" : "mic.slash",
                            label: "麦克风",
                            ok: microphoneEnabled
                        )
                    }
                }
                
                // 提示
                VStack(alignment: .leading, spacing: 6) {
                    Label("提示", systemImage: "lightbulb")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("说话时保持自然语速，无需刻意停顿。转录结果会自动修正错别字。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .onAppear { updatePermissions() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            updatePermissions()
        }
    }
    
    private func updatePermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        microphoneEnabled = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    private func modelName(_ filename: String) -> String {
        let name = (filename as NSString).deletingPathExtension
        switch name {
        case "ggml-tiny": return "Tiny"
        case "ggml-base": return "Base"
        case "ggml-small": return "Small"
        case "ggml-medium": return "Medium"
        default: return filename
        }
    }
}

// MARK: - Dashboard Components

struct KeyCard: View {
    let keys: String
    let desc: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(keys)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }
}

struct StatusItem: View {
    let icon: String
    let label: String
    let ok: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ok ? .green : .orange)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Transcription Settings

struct TranscriptionSettingsView: View {
    @AppStorage("selectedProvider") private var selectedProvider = "local"
    @AppStorage("selectedModel") private var selectedModel = LocalWhisperProvider.defaultModelName
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""
    @StateObject private var downloader = ModelDownloader.shared
    
    private let models = [
        (name: "ggml-tiny.bin", desc: "75MB · 最快 · 一般"),
        (name: "ggml-base.bin", desc: "142MB · 快 · 一般"),
        (name: "ggml-small.bin", desc: "466MB · 快（推荐，14.5s 录音约 1.4s）"),
        (name: "ggml-medium.bin", desc: "1.5GB · 较慢 · 精确（约 2.8s）"),
        (name: "ggml-large-v3-turbo.bin", desc: "1.6GB · 慢 · 最精确（约 3.2s）")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("转录")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 4)
                
                // 引擎
                VStack(alignment: .leading, spacing: 6) {
                    Label("引擎", systemImage: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Toggle("使用 API 转录（需联网）", isOn: Binding(
                        get: { selectedProvider == "openai" },
                        set: { selectedProvider = $0 ? "openai" : "local" }
                    ))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                }
                
                // 模型
                if selectedProvider == "local" {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("模型", systemImage: "internaldrive")
                            .font(.system(size: 13, weight: .semibold))
                        
                        ForEach(models, id: \.name) { model in
                            ModelRow(name: model.name, desc: model.desc, isSelected: selectedModel == model.name) {
                                if downloader.modelExists(model.name) {
                                    selectedModel = model.name
                                } else {
                                    // 下载模型
                                    downloader.download(modelName: model.name) { success in
                                        if success {
                                            selectedModel = model.name
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 下载进度
                        if downloader.isDownloading {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: downloader.downloadProgress) {
                                    Text("下载中... \(Int(downloader.downloadProgress * 100))%")
                                        .font(.system(size: 11))
                                }
                                .progressViewStyle(.linear)
                                
                                Button("取消") { downloader.cancel() }
                                    .font(.system(size: 10))
                                    .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                        }
                        
                        if let error = downloader.downloadError {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }
                    }
                }
                
                // API Key
                if selectedProvider == "openai" {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("API Key", systemImage: "key")
                            .font(.system(size: 13, weight: .semibold))
                        SecureField("sk-...", text: $openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        Text("仅保存在本地，不上传到任何服务器。")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let name: String
    let desc: String
    let isSelected: Bool
    let action: () -> Void
    
    private var isDownloaded: Bool {
        ModelDownloader.shared.modelExists(name)
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}
