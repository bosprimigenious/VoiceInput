import SwiftUI
import AppKit

@main
struct VoiceInputMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var selectedTab: SidebarTab = .dashboard
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some Scene {
        // 主窗口 - Sidebar + Detail 布局
        Window("VoiceInput", id: "main") {
            ContentView(selectedTab: $selectedTab)
                .environmentObject(appDelegate)
                .frame(minWidth: 700, minHeight: 480)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        
        // 菜单栏
        MenuBarExtra("VoiceInput", systemImage: "waveform") {
            Button("开始/停止录音 (Ctrl+I)") {
                appDelegate.toggleRecordingFromMenu()
            }
            Button("Prompt 模式 (Ctrl+Shift+I)") {
                appDelegate.togglePromptRecordingFromMenu()
            }
            Divider()
            Button("显示主窗口") {
                appDelegate.showMainWindow()
            }
            .keyboardShortcut("1", modifiers: [.command])
            Button("设置...") {
                selectedTab = .settings
                appDelegate.showMainWindow()
            }
            .keyboardShortcut(",", modifiers: [.command])
            Divider()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .menuBarExtraStyle(.menu)
        
        // 系统设置窗口（Cmd+,）
        Settings {
            SettingsView()
        }
    }
}

// MARK: - Navigation

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard = "概览"
    case meeting = "会议"
    case transcription = "转录"
    case ai = "AI 润色"
    case settings = "设置"
    case about = "关于"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .meeting: return "person.3"
        case .transcription: return "waveform"
        case .ai: return "sparkles"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}
