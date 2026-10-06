import Foundation

/// Whisper 模型下载管理器
class ModelDownloader: ObservableObject {
    static let shared = ModelDownloader()
    
    /// 镜像站点（中国大陆可用）
    private let mirrorBase = "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main"
    /// HuggingFace 官方站点
    private let hfBase = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
    
    /// 模型大小信息
    static let modelSizes: [String: String] = [
        "ggml-tiny.bin": "75MB",
        "ggml-base.bin": "142MB",
        "ggml-small.bin": "466MB",
        "ggml-medium.bin": "1.5GB",
        "ggml-large-v3-turbo.bin": "1.6GB"
    ]
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?
    
    private var downloadTask: URLSessionDownloadTask?
    
    /// 获取模型保存目录。
    /// 统一写到外置目录（~/Library/Application Support/VoiceInput/Models/）：
    /// 写进 App 包会破坏代码签名，而且用户没法单独删掉 1.5GB 的大模型。
    private func modelDirectory() -> String {
        if let dir = LocalWhisperProvider.ensureExternalModelDirectory() {
            return dir.path
        }
        // 兜底：外置目录不可用时退回包内
        if let path = Bundle.main.resourcePath {
            return path
        }
        let executablePath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        let executableURL = URL(fileURLWithPath: executablePath)
        return executableURL.deletingLastPathComponent().appendingPathComponent("Resources").path
    }
    
    /// 检查模型是否已存在（包内或外置目录都算）
    func modelExists(_ modelName: String) -> Bool {
        return LocalWhisperProvider.findModelPath(modelName) != nil
    }
    
    /// 下载模型
    func download(modelName: String, completion: @escaping (Bool) -> Void) {
        if modelExists(modelName) {
            Logger.shared.log("模型 \(modelName) 已存在，跳过下载")
            completion(true)
            return
        }
        
        guard !isDownloading else {
            Logger.shared.log("已有下载任务进行中", level: .warning)
            completion(false)
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        downloadError = nil
        
        let urlString = "\(mirrorBase)/\(modelName)"
        Logger.shared.log("开始下载模型: \(modelName) from \(urlString)")
        
        guard let url = URL(string: urlString) else {
            downloadError = "无效的下载链接"
            isDownloading = false
            completion(false)
            return
        }
        
        let destinationDir = modelDirectory()
        let destinationPath = (destinationDir as NSString).appendingPathComponent(modelName)
        
        let session = URLSession(configuration: .default, delegate: DownloadDelegate(progress: { [weak self] progress in
            DispatchQueue.main.async {
                self?.downloadProgress = progress
            }
        }, completion: { [weak self] tempURL, error in
            guard let self = self else { return }
            self.isDownloading = false
            
            if let error = error {
                self.downloadError = "下载失败: \(error.localizedDescription)"
                Logger.shared.log("模型下载失败: \(error.localizedDescription)", level: .error)
                completion(false)
                return
            }
            
            guard let tempURL = tempURL else {
                self.downloadError = "下载失败: 未获取到临时文件"
                completion(false)
                return
            }
            
            do {
                if FileManager.default.fileExists(atPath: destinationPath) {
                    try FileManager.default.removeItem(atPath: destinationPath)
                }
                try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: destinationPath))
                Logger.shared.log("模型 \(modelName) 下载完成: \(destinationPath)")
                self.downloadProgress = 1.0
                completion(true)
            } catch {
                self.downloadError = "保存失败: \(error.localizedDescription)"
                Logger.shared.log("模型保存失败: \(error.localizedDescription)", level: .error)
                completion(false)
            }
        }), delegateQueue: nil)
        
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    /// 取消下载
    func cancel() {
        downloadTask?.cancel()
        isDownloading = false
        downloadProgress = 0
    }
}

/// URLSession 下载代理
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void
    let completionHandler: (URL?, Error?) -> Void
    
    init(progress: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        self.progressHandler = progress
        self.completionHandler = completion
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // 复制临时文件到一个新的临时位置（原文件会被自动删除）
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.copyItem(at: location, to: tempFile)
            completionHandler(tempFile, nil)
        } catch {
            completionHandler(nil, error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler(nil, error)
        }
    }
}
