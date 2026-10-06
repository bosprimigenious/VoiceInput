# Changelog

## 2.0.0 — 2026-10-06

首个公开发布。在 **macOS 27.0.1 + Xcode 27** 上构建并验证。

### ⚠️ 破坏性变更

- **普通模式不再「边说边打字」。** 录音时面板仍显示实时预览（Apple Speech），
  但正文改为：停止录音 → Whisper 转写整段 → 一次性粘贴到录音前所在的 App。
  原因是旧链路用的识别结果精度更低，错字一旦打出去就再也改不回来。

### 转写精度

- **修掉精度差的主因**：旧代码在普通模式下直接采用 Apple Speech 的结果并结束
  （`AppDelegate` 里「Apple Speech 已提供实时结果：无需再转录」分支），
  Whisper 只在 Apple Speech 没有结果时才兜底。也就是说，**默认路径根本没走 Whisper**。
- **去掉硬编码 `--prompt`**。它是一串顿号分隔的词表，短音频下会让 medium
  「接着往下续写词表」而不是转写 —— 实测把 41 个字压成
  「本地模型﹑不需要输入﹑需要在安静的环境使劲﹑」。现在默认不传，设置里可填自然句子。
- **修正模型回退顺序**，改为按精度优先级
  `large-v3-turbo > medium > small > base > tiny`。
  旧逻辑按文件名字母序回退，第一个正好是精度最差的 `ggml-base.bin`。

### 速度

- 默认模型 `ggml-base.bin` → `ggml-small.bin`（base 曾是默认，但它是最差的一档）。
- whisper-cli 显式传 `-t`（核数 − 2）。whisper.cpp 默认 `-t 4`，
  在 10 核（4P+6E）的 M5 上白白浪费性能。

同一段 14.5 秒真人录音，纯 CPU：

| 配置 | 耗时 | 转录质量 |
| --- | --- | --- |
| `base` | 0.39s | 崩坏：「输入」→「诗课」 |
| **`small`（新默认）** | **1.38s** | 有错词，但整句可读 |
| `medium` | 2.78s | 接近 turbo |
| `large-v3-turbo` | 3.20s | 近乎完美 |
| ~~turbo + 默认线程（2.0 之前的实际体验）~~ | ~~4.30s~~ | 近乎完美 |

### 体积

- 大模型（medium / large-v3-turbo，1.4–1.6GB）**移出安装包**，改从
  `~/Library/Application Support/VoiceInput/Models/` 读取，安装包保持在约 530MB。
- 模型下载也改写到该外置目录，不再写进 `.app`（避免破坏代码签名，
  也让大模型可以单独删掉而不动 App）。

### 界面

- 新增 App 图标：macOS 原生圆角方块 + 蓝紫渐变 + 白色声波，
  由 `scripts/make-icon.py` 可复现生成，含 16–1024 全套尺寸。
- 设置里新增「转录提示词」输入框（默认留空）。

### macOS 27 适配

- **修正 `LSMinimumSystemVersion`**：原为 `13.0`，与二进制实际的部署目标 `15.0` 不符，
  会导致 macOS 13/14 上「装得上但起不来」。
- **清理 5 处废弃 API**（`activateIgnoringOtherApps` 系列，macOS 14 起废弃且无效果），
  构建不再有相关废弃警告。
- 菜单栏图标继续使用 SF Symbol `waveform`，自动跟随 macOS 26/27 的新菜单栏样式。

### 构建与验证

- **修掉一个会静默产出错误产物的 bug**：`build.sh` 旧写法
  `swift build 2>&1 | grep -E "error:|Build complete" || true` 会吞掉退出码 ——
  只要 `.build` 里还留着上一次的二进制，构建失败时就会把**旧程序**打进 `.app`。
  开发过程中真实踩到过。现在构建失败会硬中断，并拒绝打包比源码旧的产物。
- 新增 `scripts/rebuild-and-verify.sh`：6 个 gate 全部通过才退出 0，
  其中 G4 直接读 `.app` 二进制里的字符串做反作弊。
- `build-whisper.sh` 保持 Metal 关闭并写明原因：`GGML_METAL_EMBED_LIBRARY`
  嵌入的是 Metal **源码**而非预编译 metallib，导致 whisper-cli 每次启动都要现场
  编译 shader 约 15–20 秒。本 App 每次转写 fork 一个进程，这 15 秒每次都要重付 ——
  实测 base 1.5s→17.6s、medium 11s→20.8s，比纯 CPU 还慢。

### 已知限制

- 本地 whisper 的中文短句精度仍不及微信输入法（后者是云端大模型 + 热词自适应）。
  本版提供的手段是切 `medium` / `large-v3-turbo` 换精度，代价是变慢。
- 会议模式的声纹识别依赖本地路径依赖 `.speech-swift`，需另外准备才能构建，见 README。
