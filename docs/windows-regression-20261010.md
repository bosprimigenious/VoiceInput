# Windows 第 5 步回归与已发布包检验

日期：2026-10-10（北京时间）。

**已发布包自动回归通过；完整实机验收 NOT READY。** 本次测试下载并运行 Release 原 ZIP，没有用重新构建的包替代。真人麦克风、快捷键和实际粘贴仍未测试。

## 验收对象和证据

- 包：[v2.1.0-windows-preview.1](https://github.com/bosprimigenious/VoiceInput/releases/tag/v2.1.0-windows-preview.1)。
- 发布源码/tag：`ae9bee0ed90cf42e003b06e4bb8950fed1b5709c`。
- ZIP SHA-256：`e15eaef1dedd88523d263a70d44461527878f0075b90b92640091e7217613b13`。
- [本次 Windows 回归 37966673335](https://github.com/bosprimigenious/VoiceInput/actions/runs/37966673335)，测试工具提交 `e3ab5bc94ace37419663fefa5006bc991e02de62`，结论 success。
- runner 为 windows-2022；这不等于日常 Windows 11 电脑实测。
- 主线读取本次完整日志，下载诊断 artifact，并独立检查退出码、实际转写、中文音频参数、模型和包哈希。原始 JSON 与正文归档于 [本轮证据](windows-regression-evidence-20261010.json)。

## 各步实际结果

| 检查 | 实际输出 | 结论 |
| --- | --- | --- |
| Mac 核心锁定恢复与生产回归 | 退出 0，Core checks passed: 33 | 通过 |
| Windows runner 生产核心回归 | 退出 0，Core checks passed: 33 | 通过 |
| Mac Windows 应用 Release 编译 | 0 警告、0 错误，退出 0 | 仅编译通过 |
| 文档修正后的精确 build 命令 | 0 警告、0 错误，退出 0 | 命令可复跑 |
| 新脚本 PowerShell Parser | parserErrors=0 | 语法通过 |
| workflow YAML | Ruby Psych 可解析，job/steps 匹配 | 结构通过 |
| 发布 tag、build-info 与预期源码 | ae9bee0 一致 | 通过 |
| 下载 ZIP、校验文件、服务器 digest | 固定 SHA-256 一致 | 完整下载包通过 |
| 模型 | 487601967 字节，固定 SHA-256 一致 | 通过 |
| SDK/运行时/后端元数据 | 10.0.401 / 10.0.12 / whisper v1.7.6 commit 匹配 | 通过 |
| 第三方许可 | 10 个许可/声明文件存在且非空 | 通过 |
| 已发布 EXE 启动和简体转换 | smoke exit code: 0 | 通过 |
| 中文空格目录、中文音频文件名真实推理 | jfk exit code: 0 | 通过 |
| 缺失音频 | missing-audio exit code: 1，无文本文件 | 按预期拒绝 |
| 损坏音频 | malformed-audio exit code: 1，无文本文件 | 按预期拒绝 |
| 主线独立下载诊断并检查 | 六份 JSON、实际转写及参数匹配 | 通过 |
| 原有本地 macOS 改动保护 | 与本轮开始快照一致 | 通过 |

真实转写：

```text
And so my fellow Americans, ask not what your country can do for you, ask what you can do for your country.
```

本次同时验证模型路径、输入 WAV 文件名及输出路径含中文和空格。验证入口固定英文，不能据此宣称中文识别准确率提升。runner 的这条样例在 smoke 结束到转写结束之间约 101 秒，不是目标 Windows 电脑的 P50/P95 测量，也没有满足开发方案中拟定的日常 P95 指标的证据。

## 对照开发方案

| 开发阶段 | 本次核对结论 | 剩余项 |
| --- | --- | --- |
| 一：输入安全及故障恢复 | 代码已实现；配置、格式转换、进程超时/取消的核心回归通过 | WASAPI 设备故障、UIA 焦点及真实文字接收 |
| 二：运行时与固定构建 | 锁定恢复、Release 编译及发布包元数据通过 | .NET 升级后的日常电脑真人回归 |
| 三：完整包自动验收 | 已发布 ZIP 的完整哈希、模型、启动、推理、负控通过 | 损坏模型等附加故障用例 |
| 四：真人输入链路 | 未执行 | 记事本/浏览器、麦克风、热键、权限、退出、离线矩阵 |
| 五：中文准确率与耗时 | 未执行 | 固定录音集、CER、术语、静音、P50/P95 对照 |
| 六：公开预览 | 已发布，当前资产与源码核对通过 | 正式 READY 仍取决于真人门禁 |

更新开发方案及 Windows README：修正“未提交/未发布/未执行 CI”等过期状态，修正 restore/build 参数一致性，增加已发布包独立回归命令，下一版必须使用新 tag。发布、开发状态和历史测试报告均链接本轮结果。

## 操作失败及边界

- 第一次本地语法/YAML 检查从 windows 目录查根目录脚本，路径错误；Python 缺少 yaml 模块，报 ModuleNotFoundError。随后在仓库根重新检查脚本，使用已探测的 Ruby Psych 解析 YAML，均通过。检查工具错误不归因于应用。
- 文档编辑首次 apply_patch 因反斜杠匹配失败而未改文件；修正后完成，主线回读 diff 并重跑文档中的 build 命令。
- Mac 执行发布包检验脚本退出 1：Release regression must execute the published EXE on Windows。属于平台保护，未计作 Windows 执行通过；真正包运行见本次 Windows runner。
- smoke 允许零录音设备，不注册热键、不录音、不查询用户实际输入元素；33 项核心回归不运行实际 WASAPI 回调或 UIA 粘贴。
- 本机未下载完整 ZIP 并运行 Windows 程序；完整下载、哈希与 EXE 运行在 Windows runner 完成，主线复核其新证据。

## 复跑

```bash
gh workflow run windows-release-regression.yml --ref main
gh run list --workflow windows-release-regression.yml --limit 5
gh run view <本次run-id> --log
gh run download <本次run-id> --name Windows-published-package-regression --dir <新的目录>
```

脚本固定当前预览的源码/包哈希；验证下一版本前先审阅并更新预期值，不能静默换包。输出目录存在会拒绝，失败非零退出并保存已产生的诊断。

后续第 6 步已更新 preview.2，workflow 默认值随之更新。本报告保留 preview.1 的历史结果；复测该旧版需显式指定旧 tag/source/hash，并将 app_version 留空。新版证据见 [preview.2 发布记录](windows-preview2-release-20261010.md)。
