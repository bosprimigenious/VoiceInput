import SwiftUI
import AVFoundation
import ApplicationServices

struct WelcomeView: View {
    let onDismiss: () -> Void
    
    @AppStorage("selectedProvider") private var selectedProvider = "local"
    @AppStorage("selectedModel") private var selectedModel = LocalWhisperProvider.defaultModelName
    @AppStorage("hideWelcomeOnLaunch") private var hideWelcomeOnLaunch = false
    
    @State private var accessibilityEnabled = false
    @State private var microphoneEnabled = false
    @State private var animateIn = false
    
    private let tips = [
        ("keyboard", "按住 Ctrl+I 说话，松开自动输入"),
        ("sparkles", "Ctrl+Shift+I 生成结构化 Prompt"),
        ("speedometer", "设置中可切换模型，平衡速度与准确率"),
        ("wand.and.stars", "开启 AI 润色，口语自动优化为专业表达"),
        ("text.bubble", "录音面板实时显示转录文字"),
    ]
    
    @State private var currentTips: [(icon: String, text: String)] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部留白给 title bar 红绿灯
            Color.clear.frame(height: 36)
            
            // Hero Section
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.indigo.opacity(0.15)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)
                        .shadow(color: .blue.opacity(0.15), radius: 12, y: 4)
                    
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(.blue)
                }
                .scaleEffect(animateIn ? 1.0 : 0.8)
                .opacity(animateIn ? 1.0 : 0.0)
                
                VStack(spacing: 6) {
                    Text("VoiceInput")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .scaleEffect(animateIn ? 1.0 : 0.95)
                        .opacity(animateIn ? 1.0 : 0.0)
                    
                    Text("语音转文字 · 本地运行 · 隐私优先")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(animateIn ? 1.0 : 0.0)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            // Quick Actions - 快捷键卡片
            HStack(spacing: 10) {
                ShortcutCard(
                    keys: "⌃ I",
                    title: "普通转录",
                    subtitle: "语音直接转文字",
                    gradient: [Color.blue, Color.cyan]
                )
                
                ShortcutCard(
                    keys: "⌃ ⇧ I",
                    title: "Prompt 模式",
                    subtitle: "转为结构化提示词",
                    gradient: [Color.purple, Color.pink]
                )
            }
            .padding(.horizontal, 28)
            .opacity(animateIn ? 1.0 : 0.0)
            .offset(y: animateIn ? 0 : 10)
            
            // Status Bar
            HStack(spacing: 20) {
                StatusPill(icon: selectedProvider == "openai" ? "wifi" : "cpu",
                           label: selectedProvider == "openai" ? "OpenAI API" : "本地 Whisper",
                           color: .blue)
                
                StatusPill(icon: "internaldrive",
                           label: modelName(selectedModel),
                           color: .gray)
                
                StatusPill(icon: accessibilityEnabled ? "lock.open" : "lock",
                           label: accessibilityEnabled ? "权限正常" : "需要权限",
                           color: accessibilityEnabled && microphoneEnabled ? .green : .orange)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .opacity(animateIn ? 1.0 : 0.0)
            
            Spacer(minLength: 8)
            
            // Tips
            VStack(spacing: 6) {
                ForEach(Array(currentTips.enumerated()), id: \.offset) { index, tip in
                    HStack(spacing: 8) {
                        Image(systemName: tip.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(tip.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .opacity(animateIn ? 1.0 : 0.0)
                    .offset(y: animateIn ? 0 : 5)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer(minLength: 8)
            
            // Footer
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    } label: {
                        Text("打开设置")
                            .fontWeight(.medium)
                            .frame(width: 100)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button {
                        onDismiss()
                    } label: {
                        Text("开始使用")
                            .fontWeight(.semibold)
                            .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.blue)
                }
                
                Toggle("启动时显示此面板", isOn: .init(
                    get: { !hideWelcomeOnLaunch },
                    set: { hideWelcomeOnLaunch = !$0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 20)
            .opacity(animateIn ? 1.0 : 0.0)
        }
        .frame(width: 520, height: 480)
        .onAppear {
            currentTips = Array(tips.shuffled().prefix(3))
            updatePermissions()
            withAnimation(.easeOut(duration: 0.5)) {
                animateIn = true
            }
        }
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

// MARK: - Sub-components

struct ShortcutCard: View {
    let keys: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(keys)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(8)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct StatusPill: View {
    let icon: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.04))
        )
    }
}
