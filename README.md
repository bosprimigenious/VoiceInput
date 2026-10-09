# VoiceInput

macOS 菜单栏语音输入工具。本地 Whisper 模型转录（离线、不上传音频），
转写完成后自动把文字粘进录音前所在的那个 App。

- **当前版本**：2.0.0
- **系统要求**：macOS 15.0 或更高（本版在 **macOS 27.0.1 + Xcode 27** 上构建与验证）
- **许可证**：MIT（见 [LICENSE](LICENSE)），第三方组件见下方「第三方组件」

## Windows 预览版

Windows 版本独立放在 [`windows/VoiceInput.Windows`](windows/VoiceInput.Windows)，目标为 Windows 11 x64，Windows 10 兼容性待实机验收。
沿用本地 Whisper 转写流程：系统托盘 → `Ctrl + I` 开始/停止录音 → 转写 → 粘贴到录音前的窗口。
默认使用 small 模型，设置中可选择 medium / large-v3-turbo、语言和自然句提示词。

通过 Windows CI 门禁并发布后的下载入口：[GitHub Releases](https://github.com/bosprimigenious/VoiceInput/releases)。
Windows 预览包为 ZIP，解压整个目录后双击 `VoiceInput.exe`；不要只复制单个 EXE。
包内包含 .NET 运行时、whisper.cpp CPU 后端和 small 模型，转写时不上传音频。
当前不包含 macOS 的实时预览、会议记录、说话人区分或云端 AI 增强。

构建和门禁见 [Windows 开发说明](windows/VoiceInput.Windows/README.md)，当前使用 .NET 10。阶段进度与实际失败记录见 [开发验证记录](docs/windows-development-status.md)。
Windows 实机的麦克风、快捷键和跨应用粘贴尚需验收，预览版不代表这些环节已通过。

## macOS 启动

```bash
./scripts/build.sh
```

构建完成后，双击打开：

```text
dist/VoiceInput.app
```

打开后它会出现在 macOS 菜单栏，名字是 `VoiceInput`。不要直接运行 `build/` 里的中间文件，否则 macOS 会打开 Terminal。

## 终端调试

开发时需要看实时输入输出日志，可以用：

```bash
./scripts/run-debug.sh
```

它会构建 `dist/VoiceInput.app`，跳过 DMG，用 `open` 启动 App，并在终端里跟随 `~/Library/Application Support/VoiceInput/app.log`。这样权限身份和双击 App 保持一致，同时仍然能看到录音、转录、文本注入等日志。

如果不想每次自动构建：

```bash
NO_BUILD=1 ./scripts/run-debug.sh
```

## 开发签名

如果每次重新构建后 macOS 又请求麦克风或辅助功能权限，通常是因为 ad-hoc 签名的 App 每次都会变成新的 `cdhash`。可以创建一个本机稳定签名证书：

```bash
./scripts/setup-local-signing.sh
./scripts/build.sh
```

构建脚本会自动使用名为 `VoiceInputLocalSigning` 的证书。

## 使用

- 第一次启动按引导授予麦克风和辅助功能权限。
- 点击菜单栏里的 `VoiceInput`，或按 `Ctrl + I` 开始/停止录音。
- 录音时录音面板会显示实时预览（Apple Speech）。
- **停止录音后，统一用本地 Whisper 转写整段音频，再一次性粘贴到录音前所在的 App。**

  之前是「边说边把 Apple Speech 的中间结果打字出去」，一旦打错就再也改不回来，
  所以现在 Apple Speech 只负责面板预览，正文一律以 Whisper 结果为准。

## 模型与体积

- 安装包默认只带 `ggml-small.bin`（约 466MB），App 体积约 470MB。
- 大模型（`ggml-medium.bin` 1.4GB / `ggml-large-v3-turbo.bin` 1.5GB）**不进安装包**，
  统一放在外置目录，可以随时单独删掉：

  ```text
  ~/Library/Application Support/VoiceInput/Models/
  ```

  在 设置 → 模型 里选中大模型时会自动下载到该目录。
- 想让安装包自带大模型：`WHISPER_MODEL=ggml-large-v3-turbo.bin ./scripts/build.sh`
- 模型精度优先级：`large-v3-turbo > medium > small > base > tiny`。
  选中的模型缺失时按这个顺序回退；旧逻辑按文件名字母序回退，第一个正好是最差的 `base`。

## 精度与速度：实测结论

基准素材是仓库里那次真实的 14.5 秒录音
（`~/Library/Application Support/VoiceInput/last-recording.wav`），
M5（4P+6E）/ whisper.cpp 1.9.1 / 纯 CPU：

| 模型 | 耗时 | 转录质量 |
| --- | --- | --- |
| `base` | 0.39s | 明显崩坏：「输入」→「诗课」、「转入」→「转租」 |
| **`small`（默认）** | **1.38s** | 有错词但整句可读：「热刺我没加进了」→「热辞我明明加进研究」 |
| `medium` | 2.78s | 接近 turbo：「输入速度太慢」 |
| `large-v3-turbo` | 3.20s | 近乎完美，仅「精准」→「太难」 |

### `-t` 线程数是免费的加速

whisper.cpp 默认 `-t 4`，在 10 核 M5 上白白浪费性能。代码取「核数 - 2」（→ 8），
`-t 10` 反而略慢（6 个能效核参与调度）：

| | `-t 4` | `-t 8` | `-t 10` |
| --- | --- | --- | --- |
| turbo | 4.58s | **3.51s** | 3.59s |
| small | 1.69s | **1.38s** | 1.48s |

`-bs 1`（关掉 beam search）还能再快 10-20%，但会让 small 把「输入」听成「数字」，
所以没有默认开启。

### 为什么默认是 small 而不是 turbo

2026-10-06 一度把默认设成 turbo 追求精度，结果 14.5 秒的话要等 **4.3 秒**
（实测日志：`21:04:11.195 录音停止` → `21:04:15.542 本地转录完成，耗时 4.3s`）。
反馈是「太慢，不需要那么精准」，于是默认回到 small：日常听写够用，比 turbo 快 2.3 倍。
要精度就在 设置 → 模型 里切 medium / turbo。

### 两个精度上的坑

1. **不要把 `--prompt` 填成顿号分隔的词表。** 短音频下 medium 会「接着往下续写词表」，
   把整句压成几个词（实测把 41 个字压成「本地模型﹑不需要输入﹑需要在安静的环境使劲﹑」）。
   旧代码里那段硬编码 prompt 正是这个形状，是短句精度差的主因之一。
   默认留空；确实需要时在 设置 → 转录提示词 里用自然句子填写。
2. **base 不该做默认。** 它是精度最差的一档，旧代码却在两处把它设成默认值。

## 版本库内容

仓库：<https://github.com/bosprimigenious/VoiceInput>（公开，MIT）

只放源码（`.git` 约 1.7MB），模型与构建产物全部排除：

| 排除项 | 体积 | 怎么恢复 |
| --- | --- | --- |
| `VoiceInputMacApp/Resources/*.bin` | 606MB | `bash scripts/download-model.sh small`（支持 tiny/base/small/medium/large-v3/large-v3-turbo） |
| `dist/` | 528MB | `bash scripts/build.sh` |
| `.build/` | 1.6GB | `swift build` 自动重建（首次会重新拉全部依赖） |
| `*.dmg` | 1.3GB | `bash scripts/build.sh` |

另外排除 `.qoder/` 与 `.ai-context/`：那是 AI 工具的本地记忆/知识库，其中各有一份
240KB 的 `repowiki-metadata.json`，内含 Qoder 的 `catalogue_think_content` 编码块
（内容不透明）。文件仍在本地，只是不进版本库。

### 发版流程

```bash
# 1) 改版本号（两处都要改）
#    VoiceInputMacApp/Info.plist : CFBundleShortVersionString / CFBundleVersion
# 2) 重建并跑完所有 gate
bash scripts/rebuild-and-verify.sh
# 3) 出安装包（不带 SKIP_DMG 时 build.sh 会调 create-dmg）
bash scripts/build.sh
# 4) 打 tag 并发 Release
git tag -a v2.0.0 -m "VoiceInput 2.0.0"
git push origin v2.0.0
gh release create v2.0.0 dist/VoiceInput.dmg --title "VoiceInput 2.0.0" --notes-file CHANGELOG.md
```

### 第三方组件

| 组件 | 许可 | 是否随仓库分发 |
| --- | --- | --- |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | MIT | 是 —— `Resources/whisper-cli` 是其编译产物（2.4MB），模型文件不随仓库分发 |
| [speech-swift](https://github.com/soniqo/speech-swift) | 见上游 | 否 —— 以本地路径依赖方式引用，已 `.gitignore` 排除 |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT | 否 —— 由 speech-swift 间接引入 |

### 依赖 .speech-swift

`Package.swift` 用的是**本地路径依赖**：`.package(path: ".speech-swift")`。
该目录自带独立 git 仓库，所以被 `.gitignore` 排除，需要按固定 commit 单独拉：

```bash
git clone https://kkgithub.com/soniqo/speech-swift.git .speech-swift
git -C .speech-swift checkout 79c3a25     # 本次验证使用的 commit
```

它是本项目**必须装完整 Xcode** 的根因（拉进 mlx-swift，其 Cmlx 目标要编译 `.metal`），
见下面「重建与验收」。

## 重建与验收

```bash
bash scripts/rebuild-and-verify.sh
```

按顺序跑 6 个 gate，**全部通过才退出 0**；任何一项失败都会打印原因和修法。

| Gate | 检查内容 |
| --- | --- |
| G1 | `xcrun --find metal` 可用（缺完整 Xcode 会在这里硬停） |
| G2 | `swift build` 成功（外层沙箱下自动回退 `--disable-sandbox`） |
| G3 | `scripts/build.sh` 打包成功 |
| G4 | **反作弊**：`.app` 二进制里必须能读到新逻辑字符串，且不得残留旧逻辑字符串 |
| G5 | 包内与外置目录各有几个可用模型 |
| G6 | 用真实录音跑一次 headless 转录，输出非空 |

G4 专门防「构建失败、却把 `.build` 里的旧二进制打进 `.app`」——
2026-10-06 在本机真实发生过一次（当时静默打包了 7 月的旧产物）。

### 前置条件：完整 Xcode

本机当前**装不了**：依赖链 `.speech-swift → mlx-swift` 的 Cmlx 目标要编译 `.metal` 文件，
只装 Command Line Tools 时没有 `metal` 工具，而 mlx-swift 的 no-Metal 分支只对 Linux 生效
（`Package.swift` 里 `noMetalCmlxExcludes` 只在 `#if os(Linux)` 分支被使用）。

```bash
# 先从 App Store 安装 Xcode，然后：
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
bash scripts/rebuild-and-verify.sh
```

## Metal 为什么默认关着

`scripts/build-whisper.sh` 默认 `ENABLE_METAL=OFF`，**不要随手打开**。

实测（whisper.cpp 1.9.4-dev / M5 / macOS 27）：`GGML_METAL_EMBED_LIBRARY=ON` 嵌入的是
Metal **源码**（`ggml-metal-embed-*.metal`）而不是预编译 metallib，于是 whisper-cli
**每次启动都要现场编译 shader 约 15-20 秒**。本 App 的架构是「每次转写 fork 一个
whisper-cli 子进程」，这 15 秒每次都要重付：

| | base | small | medium |
| --- | --- | --- | --- |
| CPU | 1.5s | 4.2s | 11s |
| Metal | 17.6s | 17.1s | 20.8s |

比纯 CPU 还慢。只有装了完整 Xcode（`xcrun metal` 可用，能预编译 metallib）才值得重新评估。
复现对比：`ENABLE_METAL=ON bash ./scripts/build-whisper.sh`。

