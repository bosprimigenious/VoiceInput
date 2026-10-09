# Windows 原生语音输入

这是 .NET 10 WinForms 托盘客户端，使用 NAudio 按默认麦克风的原生格式录音，后台转换为 16 kHz、16 bit、单声道 WAV，调用随包附带的 whisper.cpp CLI 离线转写。Windows 客户端目前只覆盖语音输入，不包含 macOS 的会议或云端 AI 功能。

已发布 [v2.1.0-windows-preview.1](https://github.com/bosprimigenious/VoiceInput/releases/tag/v2.1.0-windows-preview.1)，提供含 `VoiceInput.exe` 的完整离线 ZIP，目前没有安装器。发布时 Windows 自动包门禁已通过；真人麦克风、全局快捷键和实际文字注入尚未验收，完整状态为 **NOT READY**。第 5 步对已发布 ZIP 的独立回归也已通过，详见 [本轮报告](../../docs/windows-regression-20261010.md)。

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

SDK 固定为 10.0.401，运行时固定为 10.0.12。以下命令从仓库根运行；进入项目目录使 `windows/global.json` 生效，build 参数与 restore 保持一致：

```powershell
Get-Command pwsh, git, cmake, dotnet
Push-Location windows/VoiceInput.Windows
dotnet restore VoiceInput.Windows.csproj -r win-x64 --locked-mode -p:PublishSingleFile=true -p:SelfContained=true
if ($LASTEXITCODE -ne 0) { throw '应用依赖恢复失败' }
dotnet build VoiceInput.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true --no-restore
if ($LASTEXITCODE -ne 0) { throw '应用编译失败' }
dotnet restore ../VoiceInput.CoreChecks --locked-mode
if ($LASTEXITCODE -ne 0) { throw '核心检查依赖恢复失败' }
dotnet run --project ../VoiceInput.CoreChecks -c Release --no-restore
if ($LASTEXITCODE -ne 0) { throw '核心检查失败' }
Pop-Location
pwsh -NoProfile -File scripts/build-windows.ps1
```

应用项目不自动下载模型和后端。完整打包脚本需要 Windows、Visual Studio 2022 C++ 工具和 CMake，默认输出 `dist/windows`；已存在时拒绝覆盖，重建需指定新的 `-OutputDirectory`。脚本在最终 ZIP 的中文及空格解压目录运行真实应用并保存证据。后端固定 whisper.cpp v1.7.6，嵌入 UTF-8 进程码页 manifest；简体转换按原生返回字符数读取。

已发布包独立回归优先使用 `windows-release-regression.yml`。从仓库根执行：

```bash
gh workflow run windows-release-regression.yml --ref main
gh run list --workflow windows-release-regression.yml --limit 5
gh run view <本次run-id> --log
gh run download <本次run-id> --name Windows-published-package-regression --dir <新的本地目录>
```

它下载线上 `v2.1.0-windows-preview.1`，核对源码 `ae9bee0ed90cf42e003b06e4bb8950fed1b5709c` 和 ZIP SHA-256 `e15eaef1dedd88523d263a70d44461527878f0075b90b92640091e7217613b13`，校验模型、许可和 fixture，再执行已发布 EXE。音频文件名与解压路径包含中文和空格。必须检查本次 run 和新证据，不能用重新构建的新 ZIP 或旧 CI 绿灯替代；本次独立回归 37966673335 已通过；复跑仍须核对新证据。

Windows 本地复验可从仓库根调用 `scripts/verify-windows-release.ps1`，传入已下载的 `-Zip`、`-Checksum`、固定 JFK `-Fixture`、上述 `-ExpectedCommit` / `-ExpectedSha256` 及全新的 `-OutputDirectory`。现有目录会被拒绝，防止旧文本干扰结果。WinExe 验证以退出码和输出文件为准；脚本逐项传递参数，可处理中文和空格路径。

`--smoke-test` 检查默认发布布局中的 CLI 与 small 模型存在，构造真实托盘窗体与原生窗口句柄、初始化托盘事件、加载 NAudio 并通过 WASAPI 枚举录音设备（零设备不视为失败）、加载 UI Automation 程序集并验证简体转换，随后释放窗口与托盘资源；不注册快捷键，也不录音。`--verify-transcription` 实际调用本地后端，缺文件、后端非零退出、空输出、超时均返回非零退出码。这两个入口不读取用户自定义设置。

完整验收还需日常 Windows 11 x64 电脑上检查：麦克风中文录音、托盘与全局快捷键、重复启动、焦点变化后保留文本、管理员窗口粘贴失败时保留文本、设备断开恢复、转写中退出及无孤儿后端进程。Windows 10 兼容性待验收，不能据 Windows runner 或跨编译声明支持。macOS 上的跨编译无法验证这些操作。准确率也需另行用固定中文录音集评测，不能根据编译或英文样例转写宣称提升。

API 依据：[whisper.cpp CLI](https://github.com/ggml-org/whisper.cpp/blob/master/examples/cli/README.md)、[SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)、[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)。
