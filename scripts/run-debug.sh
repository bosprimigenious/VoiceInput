#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/dist/VoiceInput.app"
LOG_FILE="$HOME/Library/Application Support/VoiceInput/app.log"

cd "$PROJECT_DIR"

if [ "${NO_BUILD:-0}" != "1" ]; then
  echo "🔨 构建 debug App..."
  REQUIRE_STABLE_SIGNING=1 SKIP_DMG=1 "$PROJECT_DIR/scripts/build.sh"
fi

if [ ! -d "$APP_BUNDLE" ]; then
  echo "❌ 找不到 App: $APP_BUNDLE"
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

echo ""
echo "🐞 Debug 启动 VoiceInput"
echo "   App: $APP_BUNDLE"
echo "   日志文件: $LOG_FILE"
echo ""
echo "提示：如果菜单栏里已有旧的 VoiceInput，请先从菜单退出旧实例。"
echo "这个脚本会用 open 启动 .app，避免终端直跑二进制造成新的权限身份。"
echo "按 Ctrl+C 只会停止日志跟随，不会退出菜单栏 App。"
echo "下面只显示本次启动后的新日志。"
echo ""

open "$APP_BUNDLE"
tail -n 0 -F "$LOG_FILE"
