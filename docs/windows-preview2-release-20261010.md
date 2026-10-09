# Windows preview.2 更新与验证

日期：2026-10-10（北京时间）。

已发布并通过自动包验收；完整实机验收 **NOT READY**。

## 更新内容

- 应用版本为 2.1.0-preview.2，文件版本 2.1.0.1。语音输入功能及 small 默认模型沿用当前实现。
- ZIP 新增 `使用说明.md`，包含启动、热键、手动恢复文本和新目录更新/回退步骤。
- build-info.json 增加 appVersion；发布前即验证中文 WAV 文件名，固定 JFK fixture 哈希。
- Release 自动上传 verification.json。已发布包回归可指定 tag/source/hash/app_version，并核对 EXE 产品版本和随包说明。

## 产物与证据

[Release v2.1.0-windows-preview.2](https://github.com/bosprimigenious/VoiceInput/releases/tag/v2.1.0-windows-preview.2)。

- ZIP：518929796 字节，约 495 MiB；自包含运行时、CPU 后端、small 模型和许可证。
- 源码及 tag：`9d71a9a88a459481cdc8354670c38e5e75b1cc4b`。
- SHA-256：`ec70af872186621961fa94f3356b067d9fd58d197306411549f046eba62bc386`。
- [构建发布 37967660645](https://github.com/bosprimigenious/VoiceInput/actions/runs/37967660645)：build/publish 均 success。
- [线上原 ZIP 独立回归 37968351515](https://github.com/bosprimigenious/VoiceInput/actions/runs/37968351515)：success。
- [主线下载并独立核对的回归 JSON](windows-preview2-evidence-20261010.json)。

| 实际检查 | 输出 |
| --- | --- |
| 本机 Release build | 0 警告、0 错误，退出 0 |
| 本机及 Windows 核心回归 | Core checks passed: 33 |
| 两个 PowerShell 脚本 Parser | parserErrors=0 |
| 两份 workflow YAML | Ruby Psych 解析通过 |
| 构建 ZIP 与解压目录逐文件哈希 | 通过 |
| 已发布 ZIP 完整下载、服务器 digest、校验文件 | 固定 SHA-256 一致 |
| build-info、EXE 产品版本、随包说明 | 2.1.0-preview.2 匹配，说明存在且非空 |
| 模型与 10 个许可/声明 | 大小/哈希及文件检查通过 |
| 中文路径下应用及简体转换 | smoke=0 |
| 中文 WAV 文件名真实 JFK 转写 | jfk=0，预期两个句子存在 |
| 缺失、损坏 WAV | 分别退出 1，未生成文本 |

主线读取两次 CI 实际日志，下载新版 Release 的 SHA-256/verification.json 与本次回归 artifact，独立核对哈希、退出码、正文和中文音频参数。完整 ZIP 下载和 Windows EXE 执行在 Windows runner 完成，未宣称本机运行过 Windows 程序。未发生本轮构建或测试失败。

preview.1 包哈希仍为 e15eaef1dedd88523d263a70d44461527878f0075b90b92640091e7217613b13，旧资产保留。macOS 稳定版仍为 v2.0.0。源码/脚本/README 中原有未提交 macOS 改动独立保留。

## 使用和限制

退出旧程序，将新 ZIP 解压到新目录后运行 VoiceInput.exe；保留 backend/models。原目录用于回退。原设置继续保留，自定义模型路径须确认有效。

真人麦克风、热键、跨应用粘贴、设备故障及退出矩阵尚未验收。中文准确率和日常 P95 速度未评测，本次不宣称提升；Windows 10 兼容性待验收，包未签名。

复跑当前版本：

```bash
gh workflow run windows-release-regression.yml --ref main
gh run list --workflow windows-release-regression.yml --limit 5
gh run view <本次run-id> --log
```

默认预期值对应 preview.2。其他版本必须显式传入 release_tag、source_commit、zip_sha256、app_version；已有发布资产不得静默覆盖。
