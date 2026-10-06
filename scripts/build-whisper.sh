#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/whisper.cpp"
OUTPUT_DIR="$PROJECT_DIR/VoiceInputMacApp/Resources"
WHISPER_REPO="https://github.com/ggml-org/whisper.cpp.git"
WHISPER_DIR="${WHISPER_DIR:-$BUILD_DIR/src}"
WHISPER_BUILD_DIR="$BUILD_DIR/build-arm64-static"
# Metal 默认关闭，且**不要轻易打开**。
# 实测（whisper.cpp 1.9.4-dev / M5 / macOS 27）：GGML_METAL_EMBED_LIBRARY=ON 嵌入的是
# Metal 源码而不是预编译 metallib，于是 whisper-cli 每次启动都要现场编译 shader 约 15-20 秒。
# 本 App 的架构是「每次转写 fork 一个 whisper-cli 子进程」，这 15 秒每次都要重付，
# 实测 base 从 1.5s 变成 17s、medium 从 11s 变成 21s，比 CPU 还慢。
# 只有装了完整 Xcode（能用 xcrun metal 预编译 metallib）时才值得重新评估。
# 想复现对比：ENABLE_METAL=ON bash ./scripts/build-whisper.sh
ENABLE_METAL="${ENABLE_METAL:-OFF}"

echo "🚀 构建静态 whisper-cli (Metal: ${ENABLE_METAL}) ..."
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

if [ ! -d "$WHISPER_DIR/.git" ]; then
  echo "📥 拉取 whisper.cpp..."
  rm -rf "$WHISPER_DIR"
  git clone --depth 1 "$WHISPER_REPO" "$WHISPER_DIR"
fi

echo "🔨 编译 arm64 静态二进制..."
cmake -S "$WHISPER_DIR" -B "$WHISPER_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL="$ENABLE_METAL" \
  -DWHISPER_METAL="$ENABLE_METAL" \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_NATIVE=OFF

cmake --build "$WHISPER_BUILD_DIR" --target whisper-cli -j "$(sysctl -n hw.ncpu)"

cp "$WHISPER_BUILD_DIR/bin/whisper-cli" "$OUTPUT_DIR/whisper-cli"
chmod +x "$OUTPUT_DIR/whisper-cli"

echo "✅ whisper-cli 已更新: $OUTPUT_DIR/whisper-cli"
echo "🔎 动态依赖:"
otool -L "$OUTPUT_DIR/whisper-cli"
