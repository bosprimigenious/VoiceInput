#!/bin/bash
# VoiceInput 重建 + 验收
#
# 用法：
#   bash scripts/rebuild-and-verify.sh
#   SKIP_DMG=0 bash scripts/rebuild-and-verify.sh     # 顺便生成 dmg
#
# 设计原则：所有 gate 必须真实通过才退出 0。
# 其中 G4 是反作弊检查——它直接读 .app 二进制里的字符串，用来防止
# 「swift build 失败、却把 .build 里的旧二进制打进 .app」被当成成功。
# 这个坑真实发生过：2026-10-06 本机就因为缺 Xcode 而静默打包了 7 月的旧产物。
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
hdr() { echo; echo "── $1 ──"; }

APP_BUNDLE="$PROJECT_DIR/dist/VoiceInput.app"
BIN="$APP_BUNDLE/Contents/MacOS/VoiceInput"
EXTERNAL_DIR="$HOME/Library/Application Support/VoiceInput/Models"

echo "VoiceInput 重建 + 验收"
echo "项目：$PROJECT_DIR"

# ── G1 工具链 ────────────────────────────────────────────────
hdr "G1 构建工具链"
# 注意：不能只判断 `xcrun --find metal` 能不能找到文件。
# Xcode 16+ 把 Metal Toolchain 拆成了单独下载的组件：装了 Xcode 但没下组件时，
# `xcrun --find metal` 会成功返回一个路径，真正执行却报
# "cannot execute tool 'metal' due to missing Metal Toolchain"。
# 所以这里必须真的跑一次。
METAL_BIN="$(xcrun --find metal 2>/dev/null || true)"
METAL_OUT="$("$METAL_BIN" --version 2>&1 || true)"
if [ -n "$METAL_BIN" ] && ! printf '%s' "$METAL_OUT" | grep -qi "missing Metal Toolchain"; then
  ok "metal 编译器可用：$METAL_BIN"
  printf '%s\n' "$METAL_OUT" | head -1 | sed 's/^/     /'
elif printf '%s' "$METAL_OUT" | grep -qi "missing Metal Toolchain"; then
  # 区分两种子情况：资产「已下载但没挂载」vs「压根没下载」。
  # 挂载要把资产接到 /Applications/Xcode.app/.../Toolchains 下面，属主是 root:wheel，
  # 非 root 执行时表现为静默挂起（无网络连接、无写入）。
  COMPONENT_JSON="$(xcodebuild -showComponent MetalToolchain -json 2>/dev/null || true)"
  if printf '%s' "$COMPONENT_JSON" | grep -q '"status" *: *"installed"'; then
    bad "Metal Toolchain 已下载，但没挂载成功"
    echo "     资产已就位（$(du -sh /System/Library/AssetsV2/com_apple_MobileAsset_MetalToolchain 2>/dev/null | cut -f1)），"
    echo "     只差挂载这一步，重跑一次即可（通常几秒）："
    echo "       xcodebuild -downloadComponent MetalToolchain"
    echo "     若报权限错误，加 sudo："
    echo "       sudo xcodebuild -downloadComponent MetalToolchain"
  else
    bad "Metal Toolchain 组件未下载"
    echo "     修复（二选一）："
    echo "       A. Xcode → Settings…(⌘,) → Components → Metal Toolchain → Get"
    echo "       B. sudo xcodebuild -downloadComponent MetalToolchain"
  fi
  echo
  echo "     注意：截图里的 Developer Documentation 和 iOS Simulator 都不是这个，"
  echo "     我们只需要 Metal Toolchain（命令行里也只支持这一个组件）。"
  echo
  echo "结论：NOT READY（G1 硬性阻塞）"
  exit 1
else
  bad "找不到 metal 编译器"
  echo "     原因：依赖链 .speech-swift → mlx-swift 的 Cmlx 目标要编译 .metal 文件，"
  echo "     而只有 Command Line Tools 时没有 metal 工具，mlx-swift 也没有关掉它的开关"
  echo "     （它的 noMetal 分支只对 Linux 生效）。"
  echo
  echo "     修复：装完整 Xcode（App Store 搜 Xcode），然后"
  echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  echo "         sudo xcodebuild -runFirstLaunch"
  echo "         xcodebuild -downloadComponent MetalToolchain"
  echo "     再重跑本脚本。"
  echo
  echo "结论：NOT READY（G1 硬性阻塞）"
  exit 1
fi

# ── G2 SPM 构建 ─────────────────────────────────────────────
hdr "G2 SPM 构建"
# CLANG_MODULE_CACHE_PATH 只对 swiftc/clang 生效，**metal 驱动会忽略它**
# （实测：metal 仍然去写 /var/folders/<...>/C/clang/ModuleCache）。
# 能生效的只有 -fmodules-cache-path，但 SwiftPM 的 CompileMetalFile 任务没给我们
# 注入 metal flag 的入口（CCC_OVERRIDE_OPTIONS 也试过，无效）。
# 所以在受限沙箱里跑这个脚本时，必须让进程能写系统 clang 模块缓存，
# 否则会看到 "could not build module 'metal_types'" —— 那是沙箱问题，
# 不是 mlx-swift 与新编译器不兼容。
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PROJECT_DIR/.build/module-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-$CLANG_MODULE_CACHE_PATH}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PROJECT_DIR/build"
BUILD_LOG="$PROJECT_DIR/build/swift-build.log"

if swift build > "$BUILD_LOG" 2>&1; then
  ok "swift build 成功"
elif grep -q "sandbox_apply: Operation not permitted" "$BUILD_LOG" \
     && swift build --disable-sandbox > "$BUILD_LOG" 2>&1; then
  ok "swift build 成功（--disable-sandbox，用于绕过外层沙箱）"
else
  bad "swift build 失败，完整日志：$BUILD_LOG"
  if grep -q "could not build module 'metal_types'" "$BUILD_LOG"; then
    echo "     诊断：metal 编译器写不了系统 clang 模块缓存"
    echo "     （/var/folders/<...>/C/clang/ModuleCache）。"
    echo "     这是**沙箱/权限**问题，不是 mlx-swift 与新编译器不兼容 ——"
    echo "     在正常 Terminal 里跑就不会有这个错。"
    echo "     若在受限沙箱内，请放宽到可写工作区之外后再跑。"
  fi
  tail -20 "$BUILD_LOG" | sed 's/^/     /'
  echo
  echo "结论：NOT READY"
  exit 1
fi

SPM_BINARY="$PROJECT_DIR/.build/debug/VoiceInputMacApp"
if [ -f "$SPM_BINARY" ]; then
  ok "产出二进制：$SPM_BINARY"
else
  bad "未产出 $SPM_BINARY"
  echo "结论：NOT READY"
  exit 1
fi

# ── G3 打包 .app ────────────────────────────────────────────
hdr "G3 打包 .app"
if SKIP_DMG="${SKIP_DMG:-1}" bash "$PROJECT_DIR/scripts/build.sh" \
     > "$PROJECT_DIR/build/package.log" 2>&1; then
  ok "build.sh 成功"
else
  bad "build.sh 失败，完整日志：build/package.log"
  tail -20 "$PROJECT_DIR/build/package.log" | sed 's/^/     /'
  echo
  echo "结论：NOT READY"
  exit 1
fi

# ── G4 反作弊：新代码是否真的进了二进制 ──────────────────────
hdr "G4 产物新鲜度 / 新代码是否真的进了二进制"
if [ ! -f "$BIN" ]; then
  bad "找不到 $BIN"
else
  STALE=$(find "$PROJECT_DIR/VoiceInputMacApp/Sources" -name '*.swift' -newer "$BIN" | head -1)
  if [ -z "$STALE" ]; then
    ok "没有源码比二进制新"
  else
    bad "源码比二进制新：$STALE"
  fi

  for s in "普通模式完成（Whisper）" "按精度优先级回退到"; do
    if LC_ALL=C grep -qa "$s" "$BIN"; then
      ok "二进制含新逻辑：$s"
    else
      bad "二进制缺少新逻辑：$s —— 打进去的很可能是旧产物"
    fi
  done

  if LC_ALL=C grep -qa "普通模式完成（Apple Speech）" "$BIN"; then
    bad "二进制里还残留旧逻辑「普通模式完成（Apple Speech）」"
  else
    ok "旧逻辑「Apple Speech 有结果就直接结束」已消失"
  fi
fi

# ── G5 模型可解析 ───────────────────────────────────────────
hdr "G5 模型"
# 注意：目录名里有空格（Application Support），不能用 ls | xargs basename
count_models() { find "$1" -maxdepth 1 -name 'ggml-*.bin' 2>/dev/null | wc -l | tr -d ' '; }
list_models()  { find "$1" -maxdepth 1 -name 'ggml-*.bin' -exec basename {} \; 2>/dev/null | sort | tr '\n' ' '; }

BUNDLED=$(count_models "$APP_BUNDLE/Contents/Resources")
EXTERNAL=$(count_models "$EXTERNAL_DIR")

if [ "$BUNDLED" -gt 0 ]; then
  ok "包内模型 $BUNDLED 个：$(list_models "$APP_BUNDLE/Contents/Resources")"
else
  bad "包内没有任何 ggml-*.bin，App 无法转录"
fi
if [ "$EXTERNAL" -gt 0 ]; then
  ok "外置模型 $EXTERNAL 个：$(list_models "$EXTERNAL_DIR")"
else
  echo "  ⚠️  外置目录 $EXTERNAL_DIR 目前为空（可选；放 medium / large-v3-turbo 用）"
fi

# ── G6 端到端转录 ───────────────────────────────────────────
hdr "G6 端到端转录（headless，不加 --prompt）"
CLI="$APP_BUNDLE/Contents/Resources/whisper-cli"
WAV="$HOME/Library/Application Support/VoiceInput/last-recording.wav"
MODEL=""
for m in ggml-large-v3-turbo.bin ggml-medium.bin ggml-small.bin ggml-base.bin; do
  if [ -f "$EXTERNAL_DIR/$m" ]; then MODEL="$EXTERNAL_DIR/$m"; break; fi
  if [ -f "$APP_BUNDLE/Contents/Resources/$m" ]; then MODEL="$APP_BUNDLE/Contents/Resources/$m"; break; fi
done

if [ ! -x "$CLI" ]; then
  bad "找不到 whisper-cli：$CLI"
elif [ -z "$MODEL" ]; then
  bad "找不到任何模型"
elif [ ! -f "$WAV" ]; then
  echo "  ⚠️  没有测试音频 $WAV，跳过（录一次音后就会有）"
else
  OUT_PREFIX="$(mktemp -d)/verify"
  START=$(python3 -c 'import time;print(time.time())')
  "$CLI" -m "$MODEL" -f "$WAV" -l zh --no-prints -otxt -of "$OUT_PREFIX" >/dev/null 2>&1
  RC=$?
  END=$(python3 -c 'import time;print(time.time())')
  if [ "$RC" -eq 0 ] && [ -s "$OUT_PREFIX.txt" ]; then
    ok "转录成功：$(basename "$MODEL")，耗时 $(python3 -c "print(f'{$END-$START:.1f}s')")"
    echo "     结果：$(tr '\n' ' ' < "$OUT_PREFIX.txt" | cut -c1-100)…"
  else
    bad "转录失败（退出码 $RC）"
  fi
  rm -rf "$(dirname "$OUT_PREFIX")"
fi

# ── 汇总 ────────────────────────────────────────────────────
echo
if [ "$FAIL" -eq 0 ]; then
  echo "结论：READY —— $PASS 项 gate 全部通过"
  echo
  echo "仍需人工确认（脚本代替不了）："
  echo "  1. 打开 dist/VoiceInput.app，按 Ctrl+I 说一句话，确认文字落进光标处"
  echo "  2. 设置 → 模型，确认当前模型是 ggml-small.bin 或你选的大模型"
  echo "  3. 录音时面板有实时预览，但正文只在停止后出现（这是本次改动的预期行为）"
  exit 0
else
  echo "结论：NOT READY —— $FAIL 项失败 / $PASS 项通过"
  exit 1
fi
