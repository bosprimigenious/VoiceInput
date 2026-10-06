import Foundation

/// 转录服务提供者协议
protocol TranscriptionProvider: AnyObject {
    /// 显示名称
    var name: String { get }
    
    /// 当前是否可用（例如本地模型是否存在、API key 是否已设置）
    var isAvailable: Bool { get }
    
    /// 转录音频文件，完成后在主线程回调
    func transcribe(audioURL: URL, completion: @escaping (String?) -> Void)
}
