# Windows 预览版发布验收

日期：2026-10-10（北京时间）。

Windows x64 预览包已发布；完整实机验收 **NOT READY**。

## 发布产物

- [Release v2.1.0-windows-preview.1](https://github.com/bosprimigenious/VoiceInput/releases/tag/v2.1.0-windows-preview.1)，prerelease=true、draft=false。
- [完整离线 ZIP](https://github.com/bosprimigenious/VoiceInput/releases/download/v2.1.0-windows-preview.1/VoiceInput-windows-x64.zip)，518,928,318 字节，约 495 MiB。
- 源码及 Release tag：`ae9bee0ed90cf42e003b06e4bb8950fed1b5709c`。
- ZIP SHA-256：`e15eaef1dedd88523d263a70d44461527878f0075b90b92640091e7217613b13`。
- 包含自包含 .NET 10 应用、CPU whisper.cpp v1.7.6、小模型及许可证；目标 Windows 11 x64，Windows 10 兼容性待验收。
- 当前稳定 Release 仍为 v2.0.0，ID 404730894；独立 Windows 预览未替换稳定版。

## 主线实际复核

[发布工作流 37965373065](https://github.com/bosprimigenious/VoiceInput/actions/runs/37965373065) 的 build 和 publish 均为 success。主线读取实际完整日志，下载该次 Windows 诊断 artifact，独立检查各 result.json、verification.json 与转写文本。

| 门禁 | 实际输出 |
| --- | --- |
| 核心回归 | Core checks passed: 33 |
| Windows 后端及应用构建 | 成功，locked restore 通过 |
| 模型与 ZIP 解压完整性 | 固定模型大小/SHA-256、每个 ZIP 成员校验均通过 |
| 中文空格目录下应用启动、UIA/WASAPI 组件和简体转换 | smoke exit code: 0 |
| small 模型真实 JFK 音频转写 | jfk exit code: 0 |
| 缺失 WAV | missing-audio exit code: 1，无文本输出 |
| 损坏 WAV | malformed-audio exit code: 1，无文本输出 |
| Release 线上附件 | uploaded；ZIP server digest 与下载的 .sha256 一致 |
| Release tag | Git ref 指向 ae9bee0，与已验证源码一致 |

实际转写正文：

```text
And so my fellow Americans, ask not what your country can do for you, ask what you can do for your country.
```

附加 `verification.json` 上传至 Release。完整 ZIP 本地下载因约三分钟仅收到 17 MB 而主动终止，退出 143；未宣称本地全包哈希或 Windows EXE 实机运行通过。实际全包运行及成员哈希在 Windows runner 执行；主线复核了发布日志、独立下载的诊断、线上 ZIP server digest 和校验附件。前三次 CI 失败及主线检查失误完整保留在 [测试报告](windows-test-report-20261010.md)。

## 使用与剩余验收

解压整个 ZIP，运行目录内 VoiceInput.exe，保留 backend/ 与 models/。系统托盘 Ctrl+I 开始/停止录音。校验下载可在 PowerShell 使用：

```powershell
Get-FileHash .\VoiceInput-windows-x64.zip -Algorithm SHA256
```

尚未执行真人麦克风、设备拔出、热键冲突、录音/转写期间退出、浏览器输入元素切换、焦点竞争与权限阻止的实机矩阵。UIA 查询及 SendInput 不能原子化。JFK 为英文样本，不证明中文准确率提升；第 5 步已补测中文文件名 WAV 输入并通过，见 [独立回归报告](windows-regression-20261010.md)。未签名，可能触发 SmartScreen。正式版仍需完成开发方案中的真人门禁。
