import SwiftUI

struct RecordingPanel: View {
    let duration: TimeInterval
    let isProcessing: Bool
    let partialText: String
    
    private var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%01d:%02d", minutes, seconds)
    }
    
    private var panelHeight: CGFloat {
        partialText.isEmpty ? 44 : 90
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 顶栏：状态指示
            HStack(spacing: 12) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                    Text("转录中...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    // 录音脉冲动画
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .scaleEffect(isProcessing ? 0.8 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: duration)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                    }
                    
                    Text(formattedDuration)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    
                    Text("Ctrl+I 停止")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(4)
                }
            }
            
            // 实时转录文本区域
            if !partialText.isEmpty && !isProcessing {
                Divider()
                    .opacity(0.3)
                
                ScrollView {
                    Text(partialText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: partialText)
                }
                .frame(maxHeight: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .animation(.easeInOut(duration: 0.2), value: panelHeight)
    }
}

class RecordingPanelController: ObservableObject {
    private var panel: NSPanel?
    private var timer: Timer?
    @Published var duration: TimeInterval = 0
    @Published var isProcessing: Bool = false
    @Published var partialText: String = ""
    
    func show() {
        if panel == nil {
            let contentView = NSHostingView(rootView: RecordingPanel(duration: duration, isProcessing: isProcessing, partialText: partialText))
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.contentView = contentView
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.backgroundColor = .clear
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // 放在屏幕顶部中央
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - 160
                let y = screenFrame.maxY - 120
                newPanel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            panel = newPanel
        }
        
        duration = 0
        isProcessing = false
        partialText = ""
        updateContent()
        panel?.orderFront(nil)
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.duration += 0.05
            self?.updateContent()
        }
    }
    
    func hide() {
        timer?.invalidate()
        timer = nil
        partialText = ""
        panel?.orderOut(nil)
    }
    
    func setProcessing(_ processing: Bool) {
        isProcessing = processing
        updateContent()
    }
    
    func updatePartialText(_ text: String) {
        partialText = text
        updateContent()
    }
    
    private func updateContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let panel = self.panel else { return }
            panel.contentView = NSHostingView(rootView: RecordingPanel(duration: self.duration, isProcessing: self.isProcessing, partialText: self.partialText))
        }
    }
}
