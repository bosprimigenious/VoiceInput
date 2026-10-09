# VoiceInput Windows 适配开发方案

更新日期：2026 年 10 月 10 日。适用仓库：VoiceInput。

## 目标与推荐方案

把现有 macOS 语音输入体验适配为 Windows 原生托盘应用：用户在输入框中按 Ctrl+I 录音，再按 Ctrl+I 停止，由本地 Whisper 完成转写，随后安全地粘贴文本。首个交付物是包含 `VoiceInput.exe`、转写后端和 small 模型的 Windows x64 ZIP，并通过 GitHub Release 分发。

推荐沿用已新增的 C# WinForms 客户端和 whisper.cpp 后端。macOS 的 SwiftUI、AppKit、Apple Speech、辅助功能接口无法直接成为 Windows 程序；本次共享转写约定、模型和验收用例，分别实现平台接口。此阶段引入 Electron、统一两端 UI 或抽象整个 Swift 工程都属于过度设计。

首版采用完整离线 ZIP，是更稳妥的默认：解压即可使用，无需首次启动下载运行时或模型。后续在核心输入链路稳定后，再提供安装器 EXE。用户所说的“Windows exe”需要区分运行程序与安装程序；本方案先交付可运行程序，安装器单列后续阶段。

## 当前状态与硬阻塞

测试阶段确认的转写输出管道超时缺陷已修复，发布准备阶段核心回归为 33 项通过。Windows 完整包验收与预览发布正在执行，历史失败证据见 [测试报告](windows-test-report-20261010.md)。

当前完整验收状态为 **NOT READY**。本地原型已有代码，但不能把跨编译成功当作 Windows 可用。

| 项目 | 当前事实 | 下一项验收 |
| --- | --- | --- |
| macOS 主工程 | Swift 项目，仍有会话开始前的未提交改动 | 单独保留，不混入 Windows 提交 |
| Windows 客户端 | `windows/VoiceInput.Windows` 已新增，已迁移 .NET 10、NAudio 2.2.1 | Windows 原生运行与录音验收 |
| 应用编译 | 前一轮主线重跑成功，0 警告、0 错误 | 锁定源码提交后由 Windows runner 重建 |
| 应用 EXE | 原型 EXE 已生成；当前 .NET 10 产物见 `dist/windows-net10-crosscompile/VoiceInput.exe` | 配齐 Windows 后端与模型后运行 |
| 完整打包 | `scripts/build-windows.ps1` 已新增 | Windows 上编译后端、组包、解压验收 |
| 自动门禁 | `scripts/verify-windows.ps1` 已新增，PowerShell 语法检查通过 | Windows 上实际执行门禁 |
| GitHub CI | `.github/workflows/windows.yml` 已新增 | 推送后实际运行 |
| 公开发布 | 本次 Windows 改动未提交、未推送、未发布 | 用户明确授权提交，门禁通过后发布 |
| 中文识别精度 | 沿用 small 默认，尚无新增中文基准结果 | 固定录音集评测 |

硬阻塞包括：尚未执行 Windows CI；尚未完成真人麦克风、全局快捷键及跨应用粘贴验收；UI Automation 元素核对已实现，但浏览器及原生窗口的实际焦点行为尚未验收；提交授权尚未获得。

前一轮曾出现 `async WndProc(ref Message)` 的 CS1988 编译错误，已改为同步分派异步任务。录音关闭异常不结算任务、退出无界等待的问题已修补，但仍需 Windows 故障场景复验。macOS 执行完整 Windows 构建脚本会返回平台错误，这是预期的平台限制，不是 Windows 构建已通过。

## 首版功能边界

首版必须包含以下流程：

1. 托盘启动、单实例检测，显示就绪、录音、停止、转写状态。
2. Ctrl+I 开始和停止录音，录制 16 kHz、16 bit、单声道 WAV，最长 5 分钟。
3. 本地 whisper.cpp 转写，默认 small、中文、提示词留空；可选择 medium、large-v3-turbo 和 zh/en/auto。
4. 可选繁体转简体，过滤明确的静音占位符；无语音时不注入文字。
5. 保存最近文本，核对目标窗口和输入位置后尝试粘贴。无法确认目标时保留文本，提供手动复制。
6. 配置持久化；录音失败、设备断开、后端失败及超时后可重新使用；退出无遗留转写进程。
7. ZIP 自带运行时、small 模型、后端、第三方许可和构建信息。

首版不移植实时语音预览、会议记录、说话人区分、云端 AI 增强、自动更新、GPU 后端和 ARM64 版本。设置中的模型链接目前是手动下载入口，不能写成“已实现自动下载”。

## 技术结构与数据约定

| 模块或文件 | 职责 | 开发要求 |
| --- | --- | --- |
| `Program.cs` | 入口、单实例、验证命令 | 正常 UI 与验证入口都必须执行真实组件 |
| `TrayForm.cs` | 状态和任务编排 | 状态切换互斥，取消和退出有界，错误后返回待机 |
| `AudioRecorder.cs` | NAudio 麦克风与 WAV 写入 | 关闭失败也结算任务，避免回调异常逸出 |
| `WhisperService.cs` | 子进程调用和文本读取 | 参数逐项传递，异步读取输出，退出码、超时和空结果均检查 |
| `NativeMethods.cs` | 热键、窗口、输入及简体转换 | 不能把发送快捷键成功当作目标应用已收到文本 |
| `AppSettings.cs` 和 `SettingsForm.cs` | 设置、模型目录与保存 | 无效配置可恢复，失败不覆盖可用设置 |
| `build-windows.ps1` | 后端构建、模型校验、完整 ZIP | 固定源版本，禁用 runner 特有 CPU 指令，禁止覆盖已有输出 |
| `verify-windows.ps1` | 真实应用与音频门禁 | 测试最终 ZIP 解压出的应用，失败退出非零 |

发布目录约定：

```text
VoiceInput 语音输入/
  VoiceInput.exe
  backend/whisper-cli.exe
  models/ggml-small.bin
  licenses/
  build-info.json
  WINDOWS-PREVIEW.txt
```

配置和最近文本位于 `%LOCALAPPDATA%\VoiceInput`；录音使用系统临时目录，任务结束删除。新转写会覆盖剪贴板，首版明确保留最近文本供恢复，不自动恢复旧剪贴板。后续若提供恢复选项，必须检测剪贴板是否已被用户更新，避免覆盖用户新复制的内容。

现有打包固定 whisper.cpp v1.7.6，commit 为 `a8d002cfd879315632a579e73f0148d06959de36`。small 文件大小为 487601967 字节，SHA-256 为 `1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b`。下载成功不等于模型有效，大小与哈希两项均须匹配。

## 阶段一 固定原型并解决输入安全

先保留现有工作区快照，再审阅 Windows 文件，明确提交范围。已有 macOS 改动保持独立，不能用 `git add .` 把它们混入本次发布。

优先完善以下项目：

1. 输入目标：增加 Windows UI Automation 的输入元素身份核对，结合窗口、进程和焦点变化记录。浏览器等无法稳定识别元素的场景，采用只复制或用户明确确认粘贴的降级方式。任何核对失败均不自动注入。
2. 生命周期：复查录音关闭、设备断开、停止超时、转写中退出、系统关闭与界面释放后的延迟回调。所有等待有上限，回调不能访问已释放资源。
3. 录音设备：先验证常见设备是否支持当前 16 kHz 录制；不支持时再增加按设备格式录制后重采样的路径，不能静默录出坏 WAV。
4. 配置恢复：处理损坏 JSON、模型目录不可写、模型缺失、模型文件损坏和剪贴板占用，提示要包含可操作的恢复步骤。
5. 验收证据：补充本地诊断日志，仅记录状态、错误、耗时、模型和退出码，默认不记录完整音频与转写正文；最近文本保留功能在说明中明确。

完成标准：关键异常有真实复现或可控故障注入用例；错误后下一次录音可成功；目标无法确认时只保留文本；Windows 上至少完成记事本及浏览器两个输入框之间切换的验证。当前原型不能仅靠使用说明规避误粘贴风险。

## 阶段二 更新运行时并固定构建

当前源码已迁移至 .NET 10 LTS，SDK 固定为 10.0.401、运行时固定为 10.0.12，并有依赖锁文件。迁移的 Windows 实机回归尚未完成。.NET 8 将于 2026 年 11 月 10 日结束支持，.NET 10 支持至 2028 年 11 月 14 日。自包含程序的运行时由发布者维护，不能依赖用户机器的 .NET 更新自动修复包内运行时。[微软支持政策](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core)

迁移应单独实施：先备份旧项目和构建配置，再把目标框架改为 `net10.0-windows`，同步更新 workflow SDK、打包许可和说明。安装 SDK 后记录实际版本，通过 `global.json` 固定；生成 NuGet 锁文件，并在 CI 使用锁定恢复。不能只改目标框架而继续下载 .NET 8 的许可和运行时说明。

系统范围先按 Windows 11 x64 验收。若要继续宣称支持 Windows 10，必须列出实际版本和生命周期条件，并重跑对应系统；“exe 可以启动”不等于操作系统仍有厂商支持。ARM64 后续独立构建，不把 x64 模拟执行当作原生支持。

完成标准：选定运行时的 Windows build/publish 均成功；NAudio、托盘、快捷键、中文转换和故障用例无回归；build-info 记录源码 commit、SDK、运行时和依赖版本。运行时迁移失败时停止正式发布，保留旧原型供排错。

## 阶段三 Windows 自动构建与包验收

Windows 构建机需要 PowerShell 7、选定 .NET SDK、Git、CMake 和 Visual Studio 2022 C++ 工具。当前后端脚本使用 VS 2022 生成器；更换生成器须单独验证。

仓库根目录执行以下现有命令，`dotnet` 必须先可用：

```powershell
Get-Command pwsh, git, cmake, dotnet
dotnet --info
Push-Location windows/VoiceInput.Windows
dotnet restore VoiceInput.Windows.csproj --locked-mode
dotnet build VoiceInput.Windows.csproj -c Release --no-restore
Pop-Location
pwsh -NoProfile -File scripts/build-windows.ps1
```

默认输出目录为 `dist/windows`，已存在时脚本拒绝覆盖。复测使用新目录，例如：

```powershell
pwsh -NoProfile -File scripts/build-windows.ps1 -OutputDirectory dist/windows-verify-02
```

打包顺序为：固定后端源码 → 编译后端 → publish 应用 → 下载并校验模型 → 附带许可 → ZIP → 解压 → 全文件哈希核对 → 运行解压出的应用。若先测开发目录再替换包文件，验收对象就与用户下载的包不同，因此门禁必须放在最终 ZIP 解压后。

自动门禁完成标准：

| 门禁 | 通过条件 | 证据 |
| --- | --- | --- |
| 构建 | 应用和 Windows 后端都从当前源码构建 | runner 日志和 build-info |
| 包完整性 | 原目录与 ZIP 解压目录的文件数及逐文件哈希一致 | 完整性检查日志 |
| 应用启动 | 中文和空格路径中运行 smoke 成功 | 退出码及 verification.json |
| 真实转写 | 应用实际调用后端，JFK 音频出现预期句子 | jfk-transcription.txt |
| 负控制 | 缺失音频返回非零退出码 | 退出码及验证记录 |
| 产物 | ZIP、ZIP SHA-256、验证证据齐全 | Actions artifact |

当前 smoke 不注册热键、不录音；JFK 是英文录音，不能替代中文准确率评测。后续补充损坏模型、后端非零退出、空语音、超时及取消用例。自动门禁全部通过，只能报告“包自动验收通过”，完整 READY 还需要下一阶段。

CPU 基础指令集构建先确保兼容性，其性能必须在目标 Windows 电脑实测。是否启用 SIMD、长驻后端或 GPU 由基准决定，首版不同时引入这些变量。

## 阶段四 Windows 真人链路验收

至少使用一台日常 Windows 11 x64 电脑；如宣称 Windows 10 支持，再增加相应电脑。每条用例记录系统版本、CPU、麦克风、包 SHA-256、源码 commit、步骤、实际结果与证据路径。

| 场景 | 操作 | 完成标准 |
| --- | --- | --- |
| 基础输入 | 记事本中录中文短句和长句 | 可停止、转写、实际出现文本；无重复粘贴 |
| 浏览器焦点 | 在两个网页输入框之间切换 | 不向错误输入框自动粘贴，文本可恢复 |
| 目标变化 | 录音后切应用、关窗口、打开新窗口 | 不向新目标误注入 |
| 权限边界 | 尝试向管理员窗口输入 | 阻止时可手动恢复，不提高应用权限绕过 |
| 麦克风异常 | 拒绝权限、拔设备、使用不兼容格式 | 提示具体原因、不卡死，恢复后可再录音 |
| 快捷键与实例 | 连按、占用 Ctrl+I、重复打开 | 无并发录音或多个托盘实例，冲突可恢复 |
| 剪贴板异常 | 占用剪贴板、转写中复制其他内容 | 失败可从最近文本恢复，行为符合说明 |
| 退出 | 录音中和转写中退出 | 等待有界，无孤儿进程和持续占用麦克风 |
| 离线使用 | 解压完整包后断网录音 | 本地转写和粘贴链路仍可用 |
| 路径 | 中文、空格目录，普通用户权限运行 | 不依赖管理员权限或开发目录 |

完成标准：必须用例全过，无崩溃、永久等待、误粘贴或文字不可恢复的问题。程序打印“已发送粘贴指令”不是通过证据，必须确认目标输入框中的实际文本。

## 阶段五 识别准确率与等待时间

适配和精度优化分开验收。先建立用户真实中文录音基准：建议不少于 30 条，覆盖日常短句、专业术语、中英文混合、长句和静音噪声；逐条人工校对参考文本，保存素材授权与音频哈希。私人录音不提交公开仓库，使用本地私有目录，并公开可分享的评测方法和汇总结果。

在相同电脑、后端版本和线程数下，依次比较 small、medium、large-v3-turbo。提示词默认留空，用户自然句提示词作为独立对照；先改变模型，再评估提示词，避免无法判断改善来自哪个变量。

记录中文 CER、重要术语错误、静音误输出、停止录音至文本可用的 P50/P95 耗时，以及冷启动和重复使用差异。CER 的简繁、空格和标点归一化规则固定，不能把繁体转简体后的外观改善直接算作模型识别能力提升。

建议候选配置进入发布的门槛：相对 small 的整体 CER 降低至少 10%，关键术语错误不增加，静音不注入幻觉文本；日常 15 秒以内录音停止后的 P95 等待不超过 5 秒。这是拟定验收目标，未达成前不得写成实测结果。如果精度提升但等待不达标，作为用户可选“精度优先”模式，默认仍用 small。

完成标准：保留可复跑的评测脚本、参数、逐条输出和汇总表；只有固定测试集上复验通过才能声称准确率提升。Mac 的已有耗时表不作为 Windows 速度结论。

## 阶段六 提交并发布预览包

先完成代码和证据，再发布。当前方案编写不包含提交、推送或 Release 操作；执行以下流程前按仓库约定获得明确提交授权。

授权后只暂存本次适配范围。README 同时含已有改动时必须按 hunk 检查，不得整文件混入：

```bash
git diff -- .gitignore README.md
git add windows/VoiceInput.Windows scripts/build-windows.ps1 scripts/verify-windows.ps1 .github/workflows/windows.yml docs/windows-development-plan.md .gitignore
git add -p README.md
git diff --cached --check
git diff --cached --stat
git commit -m "feat(windows): add offline voice input preview"
git push origin HEAD
```

按实际分支执行。自动 push 构建先通过，随后手动触发 workflow；未授权公开发布时只生成 artifact：

```bash
gh workflow run windows.yml --ref <已推送分支> -f publish=false
gh run list --workflow windows.yml --limit 5
gh run view <run-id> --log-failed
gh run download <run-id> --name VoiceInput-windows-x64 --dir <新的本地目录>
```

独立检查下载包和证据后，且发布已获授权，再执行：

```bash
gh workflow run windows.yml --ref <已验收分支> -f publish=true -f release_tag=v2.1.0-windows-preview.1
gh release view v2.1.0-windows-preview.1
```

尖括号是需要替换的占位值；`run-id` 必须匹配目标 commit，不能选列表中无关的绿灯。Windows 使用独立 prerelease tag，不覆盖 `v2.0.0` macOS Release，也不更换既有 DMG。

完成标准：Release tag 指向构建 commit，ZIP 与 SHA-256 上传完整，下载后二次哈希匹配；发布说明准确列出系统、模型、离线方式、验收范围和已知问题。仅自动门禁通过、人工门禁未过时，可以在说明充分披露后发布测试预览包，但不能标记正式 READY。

## 安装器和后续迁移

核心链路验收通过后，再新增安装器 EXE。推荐先采用当前用户安装方式，安装到用户目录，保留模型和配置；桌面快捷方式可选，开机启动默认关闭。安装器需覆盖安装、升级、运行中更新、卸载及用户模型保留的测试。

新版本安装前保存旧包和设置副本，退出旧进程后再替换文件；反过来会遇到文件占用或运行时文件混用。发布中发现问题时保留原 tag 和校验文件，撤回推荐并发布新版本说明，不静默替换同名资产。未签名预览说明实际情况；正式版签名方式确定后再加入证书管理，禁止把私钥放入仓库。

ZIP 更新目前不提供配置迁移和自动回滚。新增配置字段应有默认值，原有模型目录继续可用；发生不兼容时使用设置副本恢复，而非覆盖用户模型。

## 完成状态如何报告

| 交付等级 | 必须具备的证据 | 允许的报告 |
| --- | --- | --- |
| 原型 | 源码和跨编译 EXE | 原型已实现，Windows 验收 NOT READY |
| 自动包验收 | Windows 构建、ZIP、真实推理、负控制 | 自动包验收通过，人工链路待验收 |
| 公开预览 | 有授权、tag、资产哈希、范围准确的说明 | 预览包已发布，明确未验收项目 |
| 正式核心输入版本 | 支持中的运行时、全部人工用例通过、无硬阻塞 | 核心 Windows 输入链路 READY |
| 准确率提升 | 固定中文基准和相同条件的对照结果 | 仅对已测素材、模型和硬件报告提升 |

推荐执行顺序为阶段一至四完成 Windows 核心可用性，再推进预览发布；阶段五单独决定是否更换默认模型，阶段六不以精度优化的口头承诺代替发布证据。安装器随后实施。每阶段附实际命令、退出码、结果和未完成项，任何硬门禁失败均保持 NOT READY。

## 本轮开发记录

本轮完成 .NET 10 迁移、UI Automation 输入元素跟踪、原生 WASAPI 采集和后台重采样、停止与退出恢复、损坏配置备份恢复、状态诊断及 CoreChecks。主线实际重跑 32 项核心检查通过，Windows 应用跨编译 0 警告、0 错误；完整 Windows 后端构建、离线 ZIP、真人麦克风、UIA 和粘贴尚未运行，整体 NOT READY。当前未提交、推送或发布。详细命令与限制见 [开发验证记录](windows-development-status.md)。
