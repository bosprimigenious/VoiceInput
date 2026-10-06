import SwiftUI
import AppKit

/// 转录结果确认面板：显示转录文本，让用户确认是否插入
struct ConfirmationPanel: View {
    let text: String
    let onInsert: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            // 转录文本
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 100)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            
            // 按钮栏
            HStack(spacing: 8) {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text("\(text.count) 字")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Button("插入 ⏎") {
                    onInsert()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

/// 确认面板控制器
class ConfirmationPanelController: ObservableObject {
    private var panel: NSPanel?
    
    func show(text: String, onInsert: @escaping () -> Void, onCancel: @escaping () -> Void) {
        dismiss()
        
        let contentView = ConfirmationPanel(
            text: text,
            onInsert: { [weak self] in
                self?.dismiss()
                onInsert()
            },
            onCancel: { [weak self] in
                self?.dismiss()
                onCancel()
            }
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.borderless, .closable],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = hostingView
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isMovableByWindowBackground = true
        newPanel.hasShadow = true
        newPanel.isOpaque = false
        newPanel.becomesKeyOnlyIfNeeded = false
        
        // 居中显示
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 190
            let y = frame.midY + 50
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = newPanel
    }
    
    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
