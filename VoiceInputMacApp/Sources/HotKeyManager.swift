import Cocoa
import Carbon
import CoreGraphics

protocol HotKeyDelegate: AnyObject {
    func hotKeyTriggered()
    func promptHotKeyTriggered()
}

enum HotKeyError: LocalizedError {
    case accessibilityDenied
    case tapCreateFailed
    
    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "需要辅助功能权限才能监听全局快捷键。请在系统设置中允许本应用。"
        case .tapCreateFailed:
            return "无法创建键盘事件监听。"
        }
    }
}

class HotKeyManager {
    weak var delegate: HotKeyDelegate?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isListening = false
    
    /// 快捷键1：Ctrl + I（普通转录）
    private let targetKeyCode: CGKeyCode = 34 // 'I'
    private let targetModifiers: CGEventFlags = .maskControl
    
    /// 快捷键2：Ctrl + Shift + I（Prompt 工程化模式）
    private let promptKeyCode: CGKeyCode = 34 // 'I'
    private let promptModifiers: CGEventFlags = [.maskControl, .maskShift]
    
    var isAccessibilityEnabled: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func startListening() -> Bool {
        guard !isListening else { return true }
        
        guard isAccessibilityEnabled else {
            return false
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotKeyCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("[HotKey] 无法创建事件监听")
            return false
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isListening = true
        print("[HotKey] 开始监听 Ctrl+I（转录）和 Ctrl+Shift+I（Prompt）")
        return true
    }
    
    func stopListening() {
        guard isListening else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isListening = false
    }
    
    func handleEvent(_ event: CGEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        
        let flags = event.flags.intersection([.maskControl, .maskShift, .maskCommand, .maskAlternate])
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Ctrl+Shift+I → Prompt 模式（优先匹配，因为它包含更多修饰键）
        if flags == promptModifiers && keyCode == Int64(promptKeyCode) {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.promptHotKeyTriggered()
            }
            return true
        }
        
        // Ctrl+I → 普通转录模式
        if flags == targetModifiers && keyCode == Int64(targetKeyCode) {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotKeyTriggered()
            }
            return true
        }
        return false
    }
}

private func hotKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
    
    if manager.handleEvent(event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
