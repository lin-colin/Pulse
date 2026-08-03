#!/bin/bash
# Pulse 发布打包脚本

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Pulse"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
RELEASE_DIR="$PROJECT_DIR/release"
ZIP_NAME="${APP_NAME}_macOS.zip"

echo "🚀 开始制作 Pulse 发布包..."

# 1. 构建应用
echo "📦 正在编译..."
bash "$PROJECT_DIR/build.sh"

# 2. 代码签名 (Ad-hoc)
echo "✍️ 正在进行 Ad-hoc 代码签名..."
codesign --force --deep --sign - "$APP_BUNDLE"

# 3. 打包压缩
echo "🗜️ 正在压缩包..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

cd "$BUILD_DIR"
zip -r "$RELEASE_DIR/$ZIP_NAME" "$APP_NAME.app"
cd "$PROJECT_DIR"

echo "✅ 发布包制作完成！"
echo "📂 输出路径: $RELEASE_DIR/$ZIP_NAME"
