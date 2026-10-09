# VoiceInput Windows 开发验证记录

日期：2026 年 10 月 10 日。

## 当前结论

Windows x64 预览版已发布：[v2.1.0-windows-preview.1](https://github.com/bosprimigenious/VoiceInput/releases/tag/v2.1.0-windows-preview.1)。Windows runner 通过 33 项核心检查、完整离线 ZIP 解压完整性、中文空格路径启动及简体转换、真实 JFK 转写和坏音频负控。发布标签指向实际通过门禁的源码提交，线上 ZIP digest 与校验附件一致。详细记录见 [发布验收记录](windows-release-20261010.md)。第 5 步已重新下载并执行线上原 ZIP，自动回归通过；当前结果与剩余项见 [回归报告](windows-regression-20261010.md)。

**完整实机验收 NOT READY**：真人麦克风、设备拔出、热键和跨应用粘贴尚未验收，中文识别准确率提升尚无固定录音集证据。以下开发阶段的 32 项测试及缺失门禁是历史记录，当前结果以上述发布记录为准。

## 开发阶段实现记录

- SDK 固定 10.0.401，运行时固定 10.0.12；应用及 CoreChecks 生成依赖锁文件，CI 使用 locked restore。
- 原生窗口、进程、控件焦点与 UI Automation RuntimeId 联合检查。原窗口中输入元素变化或身份无法确认时，不自动粘贴；UIA 在后台 MTA 线程执行，取消及超时后禁用迟到粘贴。
- 默认输入设备按原生格式录音，后台下混和重采样为 16 kHz / PCM16 / mono。停止任务结算后才开始转写；重采样支持取消。停止和释放不在 UI 等待音频写入锁或 NAudio 的无界 Join。
- 损坏配置保留原文件并生成备份，恢复默认设置后提示；保存已有配置前先备份。磁盘保存文本失败时，当前结果仍在内存，可继续复制。
- 日志记录状态、模型、子进程 PID、退出码和异常类型，不记录音频、提示词或转写正文。
- CoreChecks 直接链接生产设置、音频和转写代码；子进程夹具用于验证故障处理，实际模型精度由 Windows 真人推理门禁另验。

## 开发阶段主线实际验证（历史记录）

在 `windows/VoiceInput.Windows` 目录，通过本机临时 SDK 执行：

```bash
/tmp/voiceinput-dotnet10/dotnet restore ../VoiceInput.CoreChecks --locked-mode
/tmp/voiceinput-dotnet10/dotnet run --project ../VoiceInput.CoreChecks -c Release --no-restore
/tmp/voiceinput-dotnet10/dotnet build VoiceInput.Windows.csproj -c Release --no-restore
/tmp/voiceinput-dotnet10/dotnet restore VoiceInput.Windows.csproj -r win-x64 --locked-mode -p:PublishSingleFile=true -p:SelfContained=true
/tmp/voiceinput-dotnet10/dotnet publish VoiceInput.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:PublishTrimmed=false --no-restore -o ../../dist/windows-net10-crosscompile
```

CoreChecks 实际输出：`Core checks passed: 32`。覆盖配置损坏、原配置保留、保存备份、UTF-8 往返、无效字段恢复；四种采样率和声道 WAV 的格式、时长及写句柄释放；相反双声道下混；真实子进程在中文空格路径运行；后端非零退出、缺失输出、静音空结果；stdout/stderr 同时大量输出；超时、主动取消和取消后进程确已退出；缺失 WAV 在启动前拒绝。

Windows 应用 build 和 self-contained publish 成功，均 0 警告、0 错误。输出 `dist/windows-net10-crosscompile/VoiceInput.exe` 是 Windows x64 GUI EXE；不含 Windows whisper-cli 和模型，不能作为完整用户包分发。

PowerShell 7 Parser 对两个 Windows 脚本均报告 `parserErrors=0`。workflow YAML 可解析，build/publish job 存在。语法检查不等于 Windows 脚本实际执行通过。

## 过程失败与修复

| 实际失败 | 原因与处理 |
| --- | --- |
| NETSDK1045 | 迁移期间使用旧 SDK 8 编译 net10；切换已安装的 SDK 10 |
| NETSDK1005 | 目标框架已改、依赖资产尚为 net8；重新 restore |
| WasapiCapture 类型找不到 | 缺少 NAudio.CoreAudioApi 引用；补充 using |
| 55 个 System.IO 类型缺失错误 | 启用 WPF 提供 UIA 框架引用改变隐式 using；增加项目级 System.IO using |
| CS1674 | 主线误对不实现 IDisposable 的 MMDeviceCollection 使用 using；改为普通局部变量并重编通过 |
| 构建代理两次错误相对路径、主线读取错误 global.json 路径 | 操作路径错误，已纠正；不作为应用缺陷 |
| 同步释放可能等待音频线程或磁盘转换 | 查 NAudio 源码和独立审计发现；退出取消和回收放后台，UI 不等待文件锁 |
| 全仓库空白检查报告两处 Swift 尾空格 | 会话开始前已有 macOS 改动，未顺手修改 |

## 开发阶段未完成的硬门禁（历史记录）

1. 在 Windows runner 构建真正的 Windows whisper-cli、自包含应用、模型及完整 ZIP，校验 ZIP 成员，再执行解压出的 EXE。
2. Windows smoke 的 WASAPI 枚举、UIA 程序集、托盘和简体转换，以及真实 JFK WAV 转写、缺失和损坏 WAV 负控。
3. 真人麦克风、设备拔出、热键冲突、录音和转写中退出、无孤儿后端进程。
4. 记事本和浏览器输入区域切换、焦点竞争、权限阻止及剪贴板占用时的恢复。UIA 检查与 SendInput 无法原子化，不能声称绝对没有焦点竞争。
5. 固定中文录音集的准确率和 Windows 耗时评测。32 项核心检查不证明识别准确率提升。
6. 匹配源码 commit 的 CI、Release tag、ZIP 和哈希验收（提交和发布授权已取得）。

下一步按照 [开发方案](windows-development-plan.md) 执行 Windows 自动及真人门禁，保留每条实际结果后再决定预览或正式发布。
