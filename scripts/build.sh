#!/bin/bash
set -e

echo "🚀 构建 VoiceInput..."

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="VoiceInput"
EXECUTABLE_NAME="VoiceInput"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
RESOURCES_DIR="$PROJECT_DIR/VoiceInputMacApp/Resources"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if [ -z "$SIGN_IDENTITY" ]; then
  LOCAL_IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep '"VoiceInputLocalSigning"' | head -n 1 || true)"
  APPLE_IDENTITY_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development' | head -n 1 || true)"

  if [ -n "$LOCAL_IDENTITY_LINE" ]; then
    SIGN_IDENTITY="$(echo "$LOCAL_IDENTITY_LINE" | awk '{print $2}')"
  elif [ -n "$APPLE_IDENTITY_LINE" ]; then
    SIGN_IDENTITY="$(echo "$APPLE_IDENTITY_LINE" | awk '{print $2}')"
  else
    SIGN_IDENTITY="-"
  fi
fi

if [ "${REQUIRE_STABLE_SIGNING:-0}" = "1" ] && [ "$SIGN_IDENTITY" = "-" ]; then
  echo "❌ 没有找到稳定代码签名身份。"
  echo "   请先运行: ./scripts/setup-local-signing.sh"
  exit 1
fi

mkdir -p "$DIST_DIR"

# 使用 SPM 构建（支持 speech-swift 等 SPM 依赖）
# 注意：这里必须让 swift build 的失败真正中断构建。
# 老写法 `swift build 2>&1 | grep -E "error:|Build complete" || true` 会吞掉退出码，
# 只要 .build/debug 里还留着上一次的旧二进制，就会静默地把旧程序打进 .app，
# 让人以为改动生效了。踩过这个坑，所以改成显式判断退出码。
echo "📦 使用 Swift Package Manager 构建..."
cd "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/build"
BUILD_LOG="$PROJECT_DIR/build/swift-build.log"
if ! swift build > "$BUILD_LOG" 2>&1; then
  echo "❌ SPM 构建失败。完整日志：$BUILD_LOG"
  echo "   最后 30 行："
  tail -30 "$BUILD_LOG" | sed 's/^/   /'
  exit 1
fi
echo "✅ SPM 构建成功"

# 二次确认二进制比源码新，避免打包到陈旧产物
SPM_BINARY="$PROJECT_DIR/.build/debug/VoiceInputMacApp"
if [ ! -f "$SPM_BINARY" ]; then
  echo "❌ SPM 构建失败：未找到二进制文件"
  exit 1
fi
NEWEST_SOURCE=$(find "$PROJECT_DIR/VoiceInputMacApp/Sources" -name '*.swift' -newer "$SPM_BINARY" | head -1)
if [ -n "$NEWEST_SOURCE" ]; then
  echo "❌ 二进制比源码旧（例如 $NEWEST_SOURCE 比 $SPM_BINARY 更新），拒绝打包陈旧产物"
  exit 1
fi

echo "📁 创建 .app 包..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$SPM_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# 复制 whisper-cli 和模型（用于回退转录）
if [ -f "$RESOURCES_DIR/whisper-cli" ]; then
  cp "$RESOURCES_DIR/whisper-cli" "$APP_BUNDLE/Contents/Resources/"
fi

# 复制模型文件：默认只打包 small，让安装包保持小体积。
# 大模型（medium / large-v3-turbo）走外置目录，不进安装包：
#   ~/Library/Application Support/VoiceInput/Models/
# 在 App 设置里选大模型时会自动下载到那里。
# 想让安装包直接自带大模型（约 1.6GB）：WHISPER_MODEL=ggml-large-v3-turbo.bin ./scripts/build.sh
WHISPER_MODEL="${WHISPER_MODEL:-ggml-small.bin}"
if [ -f "$RESOURCES_DIR/$WHISPER_MODEL" ]; then
  cp "$RESOURCES_DIR/$WHISPER_MODEL" "$APP_BUNDLE/Contents/Resources/"
  echo "   模型: $WHISPER_MODEL ($(du -sh "$RESOURCES_DIR/$WHISPER_MODEL" | cut -f1))"
else
  echo "⚠️ 模型文件不存在: $RESOURCES_DIR/$WHISPER_MODEL"
  echo "   声纹识别使用 speech-swift，whisper 模型可选"
fi

cp "$PROJECT_DIR/VoiceInputMacApp/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/VoiceInputMacApp/VoiceInputMacApp.entitlements" "$APP_BUNDLE/Contents/Resources/"

# App 图标（由 scripts/make-icon.py 生成）
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
  cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
  echo "   图标: AppIcon.icns ($(du -sh "$RESOURCES_DIR/AppIcon.icns" | cut -f1))"
else
  echo "⚠️ 缺少 AppIcon.icns，先跑：python3 scripts/make-icon.py"
fi

# 更新 Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
# CFBundleIconFile 可能原本不存在，先删再加，避免 PlistBuddy Set 失败
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist"

# 清掉旧脚本留下的裸二进制和旧 .app
rm -f "$BUILD_DIR/VoiceInputMacApp" "$BUILD_DIR/VoiceInputMacApp.dmg"
rm -rf "$BUILD_DIR/VoiceInputMacApp.app" "$BUILD_DIR/Resources" "$BUILD_DIR/intermediates" "$BUILD_DIR/module-cache"

echo "🔏 签名..."
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "   使用 ad-hoc 签名。"
else
  echo "   使用签名身份: $SIGN_IDENTITY"
fi
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$PROJECT_DIR/VoiceInputMacApp/VoiceInputMacApp.entitlements" "$APP_BUNDLE"
else
  codesign --force --deep --keychain "$KEYCHAIN" --sign "$SIGN_IDENTITY" --entitlements "$PROJECT_DIR/VoiceInputMacApp/VoiceInputMacApp.entitlements" "$APP_BUNDLE"
fi

echo "✅ App 构建完成: $APP_BUNDLE"
echo "🔎 当前签名身份:"
codesign -d -r- "$APP_BUNDLE" 2>&1 | sed 's/^/   /'

# 打包 DMG
if [ "${SKIP_DMG:-0}" = "1" ]; then
  echo "⏭️ 跳过 DMG 生成。"
elif command -v create-dmg >/dev/null 2>&1; then
  echo "📀 生成 DMG..."
  rm -f "$DMG_PATH"
  if create-dmg \
    --volname "VoiceInput Installer" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --app-drop-link 450 185 \
    "$DMG_PATH" \
    "$APP_BUNDLE" >/dev/null; then
    echo "✅ DMG 完成: $DMG_PATH"
  else
    rm -f "$DMG_PATH"
    echo "⚠️ DMG 生成失败，App 已可用: $APP_BUNDLE"
  fi
else
  echo "⚠️ 未安装 create-dmg，已跳过 DMG；可以直接打开 $APP_BUNDLE"
fi

echo ""
echo "👉 启动请双击: $APP_BUNDLE"
