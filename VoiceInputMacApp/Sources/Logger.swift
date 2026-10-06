import Foundation

/// 简单日志管理器：输出到控制台并保存到文件
class Logger {
    static let shared = Logger()
    
    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.ai.voiceinput.logger")
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VoiceInput", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        logFileURL = appDir.appendingPathComponent("app.log")
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] \(message)\n"
        
        // 控制台输出
        print(line, terminator: "")
        
        // 文件追加
        queue.async { [weak self] in
            guard let self = self else { return }
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }
    }
    
    func readLogs() -> String {
        return (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? "暂无日志"
    }
    
    func clearLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            try? "".write(to: self.logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    var logFilePath: String {
        return logFileURL.path
    }
}

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}
