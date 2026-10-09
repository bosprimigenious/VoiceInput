# Windows 原生语音输入

这是 .NET 10 WinForms 托盘客户端，使用 NAudio 按默认麦克风的原生格式录音，后台转换为 16 kHz、16 bit、单声道 WAV，调用随包附带的 whisper.cpp CLI 离线转写。Windows 客户端目前只覆盖语音输入，不包含 macOS 的会议或云端 AI 功能。

## 使用

完整解压 Windows ZIP 后运行 `VoiceInput.exe`。发布目录必须保留：

```text
VoiceInput.exe
backend/whisper-cli.exe
backend/（构建产生的依赖 DLL，如有）
models/ggml-small.bin
```

在记事本或其他编辑器中点入输入框，按 **Ctrl+I** 开始录音，再按 **Ctrl+I** 停止。单次最长 5 分钟；转写中快捷键不重复启动任务。系统托盘会显示录音与转写状态。

转写后尝试恢复录音开始前的窗口，同时核对 HWND、进程、原生焦点和 UI Automation 输入元素 RuntimeId，再发送 Ctrl+V。录音或转写过程中，原窗口内切换输入元素会使本次自动粘贴失效；不支持 UI Automation、无法确认可写性、密码框和核对异常均只保留文本。Windows 焦点核对与发送键盘输入无法原子化，仍需 Windows 实机验证竞争场景。Windows 前台激活限制、管理员窗口权限、焦点变化或剪贴板占用可能阻止自动输入。文本保留在托盘的“查看 / 复制最近文本”中，转写成功后也保存到 `%LOCALAPPDATA%\VoiceInput\last-transcript.txt`；可自行手动粘贴。发送输入成功不能证明目标编辑器实际接收了文本，应现场确认。新文本会覆盖系统剪贴板，不自动恢复旧内容。

右键托盘打开设置，可选 `small`、`medium`、`large-v3-turbo`，语言 `zh` / `en` / `auto`，简体中文转换与自然句提示词。默认模型为 small，默认语言为中文，提示词默认留空。使用提示词需要自己验证识别结果，提示词不能保证准确率提升。模型目录中必须有对应的 `ggml-模型名.bin`。完整 small 包可直接离线使用；缺模型时程序会显示具体路径与下载指引。其他模型从 [whisper.cpp 模型仓库](https://huggingface.co/ggerganov/whisper.cpp/tree/main) 下载。配置保存到 `%LOCALAPPDATA%\VoiceInput\settings.json`。配置损坏时保留原文件并新增备份、恢复默认设置和提示；每次保存前备份已有配置。状态诊断位于同目录的 `app.log`，默认不记录音频、提示词或转写正文。

Ctrl+I 被其他软件占用时会提示并退出，释放冲突后重启。没有麦克风时检查 Windows 的桌面应用麦克风权限。转写失败会显示错误并恢复待机，超过 10 分钟会终止后端；退出会取消转写并清理当前临时音频。音频使用系统临时目录，转写文本存于本地，无应用内联网上传。

## 构建与验证

SDK 固定为 10.0.401，运行时固定为 10.0.12。进入 Windows 项目目录，使 `windows/global.json` 生效：

```powershell
cd windows/VoiceInput.Windows
dotnet restore VoiceInput.Windows.csproj --locked-mode
dotnet build VoiceInput.Windows.csproj -c Release --no-restore
# 故障恢复、真实子进程及音频格式转换检查
dotnet restore ../VoiceInput.CoreChecks --locked-mode
dotnet run --project ../VoiceInput.CoreChecks -c Release --no-restore
# 完整ZIP必须在Windows上从仓库根调用 scripts/build-windows.ps1
```

应用项目不自动下载模型和后端；完整发布打包流程使用仓库 `scripts/build-windows.ps1`。WinExe 发布不能依赖控制台错误显示，自动验证以退出码与文件内容为准：

```powershell
$p = Start-Process '.\VoiceInput.exe' -ArgumentList '--smoke-test' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw '依赖检查失败' }
# WAV 必须为 16 bit PCM；此入口固定英文，用于官方 jfk.wav 实际推理验证。
$p = Start-Process '.\VoiceInput.exe' -ArgumentList '--verify-transcription sample.wav transcript.txt' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw '转写检查失败' }
Get-Content transcript.txt
```

`--smoke-test` 检查默认发布布局中的 CLI 与 small 模型存在，构造真实托盘窗体与原生窗口句柄、初始化托盘事件、加载 NAudio 并通过 WASAPI 枚举录音设备（零设备不视为失败）、加载 UI Automation 程序集并验证简体转换，随后释放窗口与托盘资源；不注册快捷键，也不录音。`--verify-transcription` 实际调用本地后端，缺文件、后端非零退出、空输出、超时均返回非零退出码。这两个入口不读取用户自定义设置。

完整验收还需真实 Windows 10/11 x64 上检查：麦克风中文录音、托盘与全局快捷键、重复启动、焦点变化后保留文本、管理员窗口粘贴失败时保留文本、设备断开恢复、转写中退出及无孤儿后端进程。macOS 上的跨编译无法验证这些操作。准确率也需另行用固定中文录音集评测，不能根据编译或英文样例转写宣称提升。

API 依据：[whisper.cpp CLI](https://github.com/ggml-org/whisper.cpp/blob/master/examples/cli/README.md)、[SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)、[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)。
