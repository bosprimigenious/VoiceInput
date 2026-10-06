#!/bin/bash
set -euo pipefail

# 下载 whisper.cpp GGML 模型到 Resources 目录
# 用法: ./scripts/download-model.sh [model_name]
# 示例: ./scripts/download-model.sh small
#       ./scripts/download-model.sh medium

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/VoiceInputMacApp/Resources"
MODEL_NAME="${1:-small}"

# 模型列表和大小
declare -A MODELS=(
  ["tiny"]="ggml-tiny.bin|75 MB|最快，准确率一般"
  ["base"]="ggml-base.bin|142 MB|较快，准确率可用"
  ["small"]="ggml-small.bin|466 MB|速度与准确率平衡（推荐）"
  ["medium"]="ggml-medium.bin|1.5 GB|准确率高，较慢"
  ["large-v3"]="ggml-large-v3.bin|2.9 GB|最高准确率，很慢"
  ["large-v3-turbo"]="ggml-large-v3-turbo.bin|1.6 GB|large-v3 加速版"
)

# HuggingFace 镜像（中国大陆优先）
HF_BASE="https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main"
HF_FALLBACK="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

if [[ -z "${MODELS[$MODEL_NAME]+x}" ]]; then
  echo "❌ 未知模型: $MODEL_NAME"
  echo ""
  echo "可用模型："
  for key in "${!MODELS[@]}"; do
    IFS='|' read -r file size desc <<< "${MODELS[$key]}"
    printf "  %-16s %-10s %s\n" "$key" "$size" "$desc"
  done
  exit 1
fi

IFS='|' read -r FILENAME SIZE DESC <<< "${MODELS[$MODEL_NAME]}"
OUTPUT_FILE="$OUTPUT_DIR/$FILENAME"

if [[ -f "$OUTPUT_FILE" ]]; then
  echo "✅ 模型已存在: $OUTPUT_FILE ($(du -sh "$OUTPUT_FILE" | cut -f1))"
  exit 0
fi

mkdir -p "$OUTPUT_DIR"

echo "📥 下载模型: $MODEL_NAME ($FILENAME, $SIZE)"
echo "   目标: $OUTPUT_FILE"
echo ""

# 先尝试 hf-mirror.com（中国大陆镜像）
if curl -L --connect-timeout 10 -o "$OUTPUT_FILE" "$HF_BASE/$FILENAME" 2>/dev/null; then
  echo ""
  echo "✅ 下载完成: $OUTPUT_FILE ($(du -sh "$OUTPUT_FILE" | cut -f1))"
  exit 0
fi

# 回退到 huggingface.co
echo "⚠️ 镜像下载失败，尝试 HuggingFace 主站..."
if curl -L --connect-timeout 15 --max-time 1800 -o "$OUTPUT_FILE" "$HF_FALLBACK/$FILENAME"; then
  echo ""
  echo "✅ 下载完成: $OUTPUT_FILE ($(du -sh "$OUTPUT_FILE" | cut -f1))"
else
  echo "❌ 下载失败。请手动下载："
  echo "   $HF_FALLBACK/$FILENAME"
  echo "   放到: $OUTPUT_FILE"
  rm -f "$OUTPUT_FILE"
  exit 1
fi
