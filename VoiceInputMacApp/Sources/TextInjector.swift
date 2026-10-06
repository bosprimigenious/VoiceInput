import Cocoa
import CoreGraphics

class TextInjector {
    /// 将文字输入到当前焦点位置
    func type(text: String, targetApp: NSRunningApplication?) {
        Logger.shared.log("开始文本注入，长度：\(text.count)，目标应用：\(targetApp?.localizedName ?? "未知")")

        // 如果目标 App 是我们自己或系统服务，跳过激活，直接粘贴
        let shouldActivate = shouldActivateApp(targetApp)

        if shouldActivate, let app = targetApp {
            // 使用 activateIgnoringOtherApps 确保 Electron 等 App 也能正确激活
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            Logger.shared.log("已激活目标应用：\(app.localizedName ?? "未知") (PID: \(app.processIdentifier))")
        }

        // 给目标 App 足够时间完成激活和焦点恢复
        let delay = shouldActivate ? 0.35 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pasteText(text)
        }
    }

    /// 判断是否应该激活目标 App（过滤掉系统服务和自身）
    private func shouldActivateApp(_ app: NSRunningApplication?) -> Bool {
        guard let app = app else { return false }
        // 过滤掉不应该激活的 App
        let skipBundleIDs = [
            "com.apple.UserNotificationCenter",
            "com.apple.loginwindow",
            "com.apple.dock",
            "com.apple.finder", // Finder 桌面没有可输入的文本框
        ]
        if let bundleID = app.bundleIdentifier, skipBundleIDs.contains(bundleID) {
            Logger.shared.log("跳过激活系统应用：\(bundleID)")
            return false
        }
        // 跳过自身
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            Logger.shared.log("跳过激活自身")
            return false
        }
        return true
    }

    /// 剪贴板粘贴并恢复原剪贴板
    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let oldItems = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Logger.shared.log("已写入剪贴板，准备发送 Cmd+V")

        if sendPasteShortcut() {
            // 粘贴成功，延迟恢复剪贴板
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.restorePasteboard(pasteboard, items: oldItems)
                Logger.shared.log("文本注入完成，已恢复剪贴板")
            }
        } else {
            // Cmd+V 失败，改用 Unicode 事件
            Logger.shared.log("发送 Cmd+V 失败，改用 Unicode 事件注入", level: .warning)
            restorePasteboard(pasteboard, items: oldItems)
            sendText(text)
            Logger.shared.log("Unicode 事件注入完成")
        }
    }

    /// 发送 Cmd+V 快捷键
    private func sendPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Logger.shared.log("无法创建 Cmd+V 事件源", level: .error)
            return false
        }

        let vKeyCode: CGKeyCode = 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            Logger.shared.log("无法创建 Cmd+V 键盘事件", level: .error)
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    /// 快照当前剪贴板内容
    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        return pasteboard.pasteboardItems?.map { item in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        } ?? []
    }

    /// 恢复剪贴板内容
    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restoredItems = items.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }

    /// 流式输入：直接用 Unicode 事件发送文本，不操作剪贴板，不激活应用
    /// 用于实时转录时边说边打字
    func typeStreaming(_ text: String) {
        guard !text.isEmpty else { return }
        sendText(text)
    }

    /// 使用 Unicode 事件直接发送文本（备选方案）
    private func sendText(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Logger.shared.log("无法创建 Unicode 文本事件源", level: .error)
            return
        }

        let utf16Chars = Array(text.utf16)
        let count = utf16Chars.count
        guard count > 0 else { return }

        var chars = utf16Chars
        chars.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }

            let downEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            downEvent?.keyboardSetUnicodeString(stringLength: count, unicodeString: baseAddress)
            downEvent?.flags = .maskNonCoalesced
            downEvent?.post(tap: .cgAnnotatedSessionEventTap)

            let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            upEvent?.keyboardSetUnicodeString(stringLength: count, unicodeString: baseAddress)
            upEvent?.flags = .maskNonCoalesced
            upEvent?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// 兼容模式：逐个字符输入（某些应用不支持一次性 Unicode 输入）
    func typeCharacterByCharacter(text: String, targetApp: NSRunningApplication?) {
        if shouldActivateApp(targetApp) {
            targetApp?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.sendTextCharacterByCharacter(text)
        }
    }

    private func sendTextCharacterByCharacter(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        for char in text {
            let scalars = Array(char.unicodeScalars.map { UInt16($0.value) })
            var chars = scalars

            chars.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }

                let downEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                downEvent?.keyboardSetUnicodeString(stringLength: scalars.count, unicodeString: baseAddress)
                downEvent?.flags = .maskNonCoalesced
                downEvent?.post(tap: .cgAnnotatedSessionEventTap)

                let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                upEvent?.keyboardSetUnicodeString(stringLength: scalars.count, unicodeString: baseAddress)
                upEvent?.flags = .maskNonCoalesced
                upEvent?.post(tap: .cgAnnotatedSessionEventTap)
            }

            usleep(1000) // 1ms
        }
    }
}
