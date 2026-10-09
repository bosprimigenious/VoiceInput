# VoiceInput Windows 测试报告

测试日期：2026 年 10 月 10 日。测试主机：macOS arm64，.NET SDK 10.0.401，PowerShell 7.4.6。

## 测试阶段结论与未通过项目

**NOT READY。** 已发现并亲自复现转写超时失效；回归检查为 **32 项通过、1 项失败**。完整 Windows ZIP、真人麦克风、热键、焦点和粘贴链路缺少 Windows 执行环境，尚未运行。

本次测试只新增失败回归与测试报告，没有修改生产代码，没有提交、推送或发布。

## 失败的回归

`WhisperService.cs` 对进程退出施加取消期限，但输出流读取和结束后的等待没有期限。后端根进程退出时，其后代可能仍持有继承的 stdout/stderr 管道，导致读取一直等待 EOF，绕过转写超时。

先用临时夹具直接链接生产源码复现：后端启动持有管道的后代后立即退出，超时设置为 1 秒。主线重跑实际输出：

```text
transcription.start model=small pid=85960
elapsed=4.2s; timeout=1s; completed=False; child_pid=85962
transcription.exit code=0
result=InvalidOperationException; elapsed=4.2s
```

夹具在 4 秒观察点主动结束自己的后代才解除阻塞。PID 仅用于记录这次夹具执行，不能用于以后清理。这个反例验证的是生产包装层的超时契约，不代表已观察到 bundled whisper.cpp 在日常转写中产生相同后代。

随后把同类夹具加入 `windows/VoiceInput.CoreChecks/Program.cs`：用真实 .NET 后代继承管道，生产超时 1 秒，4 秒观察点要求任务结束；测试结束清理夹具后代。主线实际运行：

```bash
cd windows/VoiceInput.Windows
/tmp/voiceinput-dotnet10/dotnet run --project ../VoiceInput.CoreChecks -c Release --no-restore
```

关键输出：

```text
Existing core checks passed: 32
System.InvalidOperationException: FAIL inherited output pipe: production timeout=1s, task still pending after 4s
```

命令退出码 **1**。新增回归直接调用生产 `WhisperService.TranscribeAsync`，没有复制一份转写实现。当前 workflow 会在该检查失败时阻止后续打包和发布。

修复方向：把取消与截止时间覆盖到整个进程等待、stdout/stderr 读取和清理流程；保留有界清理，避免退出后的后代继续占用管道时无期限等待。修复后先使这个回归通过，再重跑现有取消、输出洪泛、真实 Windows 转写与孤儿进程检查。不能删掉失败回归来恢复绿灯。

## 各步实际结果

| 步骤 | 实际输出 | 状态 |
| --- | --- | --- |
| 环境探测 | Darwin；SDK 10.0.401；PowerShell 7.4.6；未检测到 Windows 虚拟机或兼容运行器命令 | Windows 运行环境缺失 |
| CoreChecks 锁定恢复 | 所有项目均为最新，退出 0 | 通过 |
| 原有核心检查 | `Core checks passed: 32`，退出 0 | 通过，范围有限 |
| 新增继承管道回归 | 生产 1 秒超时，4 秒仍 pending，退出 1 | 失败 |
| 应用锁定恢复 | 所有项目均为最新，退出 0 | 通过 |
| Windows 自包含 publish | 生成 `dist/windows-test-20261010/VoiceInput.exe`，退出 0 | 跨编译通过 |
| 禁用增量 build | 0 警告、0 错误，退出 0 | 通过 |
| PowerShell Parser | 两个脚本 `parserErrors=0`，退出 0 | 语法通过 |
| workflow YAML | 可解析，build/publish job 存在，退出 0 | 结构通过 |
| 完整构建脚本在 Mac 执行 | `This build requires Windows...`，退出 1 | 平台保护按预期拒绝，不计 Windows 构建通过 |
| 完整包验收脚本在 Mac 执行 | `Verification must execute the real package on Windows.`，退出 1 | 平台保护按预期拒绝，不计 Windows 验收通过 |
| 产物格式 | PE32+ GUI x86-64，173544506 字节 | 只验证文件格式 |
| 产物组件 | 后端 false，模型 false | 不是完整离线包 |
| macOS 原有改动比较 | 原源码、脚本和 CHANGELOG 与初始快照一致 | 完整保留 |

本次应用 EXE 的 SHA-256：

```text
76c0c6435332e772571be1603e73fb9783537c920e88acc1f1674a6c41b21e87
```

包内运行时配置为 Microsoft.NETCore.App 10.0.12 和 Microsoft.WindowsDesktop.App 10.0.12。该 EXE 没有后端和模型，不可作为已验收用户包提供。

## 测试范围的边界

32 项核心检查包含配置备份恢复、四种 WAV 格式转换、多声道下混、真实子进程输出、非零退出、空输出、管道洪泛、根进程超时和主动取消。音频部分只调用静态转换函数；不覆盖 WASAPI 设备回调、停止和退出生命周期。

CoreChecks 不编译或运行 `InputTargetTracker`、`TrayForm` 及真正的 Win32 `NativeMethods`。UI Automation、目标恢复、热键和发送输入仍没有自动执行证据。

应用 smoke 构造窗口句柄并探测组件，但不启动正常消息循环、不注册热键、不录音、不查询实际输入元素。零麦克风也允许通过，因此 smoke 成功不能写成真人交互链路通过。

## 下一步门禁

先修复继承输出管道导致的超时失效，使全部核心回归通过。随后使用 Windows CI 或可连接的 Windows 电脑运行完整构建、ZIP 解压完整性、应用 smoke、JFK 真人音频推理及坏输入负控，再完成麦克风、设备拔出、热键、浏览器焦点和粘贴的实机矩阵。

本次已询问 Windows 执行方式。若选择 GitHub CI，需要按仓库约定明确授权提交并推送测试分支；测试分支不发布 Release。未取得该授权前，没有提交或改变远端状态。

## 发布准备阶段修复复验

用户随后授权打包发布。生产超时现在同时覆盖根进程退出及stdout/stderr读取，取消后的根进程清理等待有2秒上限，并关闭读取端。主线重跑实际输出 `PASS inherited output pipe obeys production timeout`、`Core checks passed: 33`，退出0。回归未删除。修复期间发生一次CS0136局部变量重名编译失败，纠正后Windows应用build为0警告、0错误。前文32通过1失败是测试阶段的历史结果；最终Windows构建和发布证据另行记录。

## Windows CI 发布准备过程

- [第一次 CI](https://github.com/bosprimigenious/VoiceInput/actions/runs/37962376561)：核心检查通过，Windows whisper.cpp 编译通过；应用 locked restore 因锁文件含 osx-arm64 而失败（NU1004）。固定单一 win-x64 RuntimeIdentifier 并重新生成锁文件后重试。
- [第二次 CI](https://github.com/bosprimigenious/VoiceInput/actions/runs/37962930633)：核心检查、Windows 编译、模型校验和 ZIP 完整性通过；解压后的应用简体转换 smoke 失败。LCMapStringEx 的显式源长度不保证输出 NUL，而 StringBuilder 回拷依赖 NUL；已改用 char[] 并按 API 返回字符数构造字符串，增加空文本与中英混合检查，没有跳过门禁。
- 修复后本机应用编译 0 警告、0 错误，核心检查 33 项通过。主线曾从错误目录构建，触发 NU1004；改用 windows 目录下的规定锁定恢复命令后重跑通过。
- [第三次 CI](https://github.com/bosprimigenious/VoiceInput/actions/runs/37963953009)：简体转换与启动 smoke 通过；真实 JFK 转写失败，后端退出 3，无法打开中文路径下的模型。为原生后端嵌入 UTF-8 activeCodePage manifest 后重试，保留中文空格 ZIP 解压路径门禁。Windows 10 兼容性仍待验收；该 manifest 需要 Windows 10 1903 或更高。
- 第四次 CI 与最终发布结果另见发布记录。真人麦克风、热键和跨应用输入仍未验收。

- [第四次 CI](https://github.com/bosprimigenious/VoiceInput/actions/runs/37964395754)：完整门禁通过，33 项核心检查；smoke=0、JFK=0、missing-audio=1、malformed-audio=1。JFK 实际文本为 `And so my fellow Americans, ask not what your country can do for you, ask what you can do for your country.`。主线下载诊断附件并逐项检查 JSON 与转写正文，结果一致。
- 本地完整 artifact 下载约三分钟收到 17 MB / 519 MB；主动终止下载进程，退出 143，切换到同一源码提交的 workflow_dispatch 发布链路，重新执行全部门禁并在 runner 上传。没有把未完成的本地下载计作校验通过。
- README 原文保护检查第一次遗漏允许的平台标题改名，断言失败；查看 diff 后修正检查，确认除 Windows 部分及“macOS 启动”标题外原文一致。macOS 源码、脚本及 CHANGELOG 与初始快照一致。

最终发布及逐项验收结果见 [Windows 发布验收记录](windows-release-20261010.md)。
