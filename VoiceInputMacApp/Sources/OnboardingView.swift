import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    
    private let pages = [
        OnboardingPage(
            icon: "mic.fill",
            title: "欢迎使用 VoiceInput",
            description: "按住 Ctrl+I 说话，松开后文字会自动输入到光标位置。完全本地运行，无需联网。"
        ),
        OnboardingPage(
            icon: "keyboard.fill",
            title: "全局快捷键",
            description: "无论焦点在哪个 App，按 Ctrl+I 即可开始录音，再按一次停止。"
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "需要两项权限",
            description: "1. 麦克风：录制你的声音\n2. 辅助功能：监听全局快捷键\n\n第一次录音时会请求麦克风权限。"
        )
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: pages[currentPage].icon)
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text(pages[currentPage].title)
                .font(.title)
                .fontWeight(.bold)
            
            Text(pages[currentPage].description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            
            Spacer()
            
            // 分页指示器
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            
            Button(action: {
                if currentPage < pages.count - 1 {
                    currentPage += 1
                } else {
                    dismiss()
                }
            }) {
                Text(currentPage < pages.count - 1 ? "下一步" : "开始使用")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 20)
        }
        .padding()
        .frame(width: 480, height: 420)
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}
