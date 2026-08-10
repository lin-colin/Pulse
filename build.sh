#!/bin/bash
# Pulse - macOS 菜单栏系统监控工具 构建脚本

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$PROJECT_DIR/Pulse"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Pulse"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
MODULE_CACHE="${TMPDIR:-/tmp}/pulse-swift-module-cache"

echo "🔨 正在编译 Pulse..."

# 清理并创建构建目录
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$MODULE_CACHE"

# 将内存领域类型纳入编译源列表，以生成拆分后的压力与页统计模型。
# 编译所有模块 Swift 文件
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -framework AppKit \
    -framework IOKit \
    -framework ServiceManagement \
    -target arm64-apple-macos13.0 \
    -O \
    "$SOURCE_DIR/App/main.swift" \
    "$SOURCE_DIR/App/AppDelegate.swift" \
    "$SOURCE_DIR/Models/MemoryMetrics.swift" \
    "$SOURCE_DIR/Models/PulseSnapshot.swift" \
    "$SOURCE_DIR/Models/StatusItemRenderModel.swift" \
    "$SOURCE_DIR/Models/MetricCalculations.swift" \
    "$SOURCE_DIR/Models/SMCValueDecoder.swift" \
    "$SOURCE_DIR/Models/PulseDefaults.swift" \
    "$SOURCE_DIR/UI/StatusItemHost.swift" \
    "$SOURCE_DIR/UI/StatusBarController.swift" \
    "$SOURCE_DIR/UI/StatusItemRenderer.swift" \
    "$SOURCE_DIR/UI/RefreshIntervalControl.swift" \
    "$SOURCE_DIR/UI/ThresholdValueField.swift" \
    "$SOURCE_DIR/UI/PopoverContentView.swift" \
    "$SOURCE_DIR/UI/PanelSession.swift" \
    "$SOURCE_DIR/Services/SMCReader.swift" \
    "$SOURCE_DIR/Services/AppleSmartBatteryReader.swift" \
    "$SOURCE_DIR/Services/HardwareMonitor.swift" \
    "$SOURCE_DIR/Services/SystemMonitor.swift" \
    "$SOURCE_DIR/Services/BatteryMonitor.swift" \
    "$SOURCE_DIR/Services/LaunchAtLoginController.swift" \
    "$SOURCE_DIR/Services/UpdateChecker.swift"

# 复制配置文件和资源
cp "$SOURCE_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$SOURCE_DIR/Resources/AppIcon.icns" ]; then
    cp "$SOURCE_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "✅ 编译成功！"
echo "📦 应用产物: $APP_BUNDLE"
echo ""
echo "运行方式:"
echo "  open $APP_BUNDLE"
