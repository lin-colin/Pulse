#!/bin/bash
# 编译并运行不依赖 UI 与真实硬件的 Pulse 指标测试与位图几何测试。

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_BINARY="${TMPDIR:-/tmp}/pulse-metric-tests"
MODULE_CACHE="${TMPDIR:-/tmp}/pulse-swift-module-cache"

mkdir -p "$MODULE_CACHE"

# 编译主套件
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
swiftc \
    -framework AppKit \
    -framework IOKit \
    -framework ServiceManagement \
    -o "$TEST_BINARY" \
    "$PROJECT_DIR/Pulse/Models/MemoryMetrics.swift" \
    "$PROJECT_DIR/Pulse/Models/PulseSnapshot.swift" \
    "$PROJECT_DIR/Pulse/Models/StatusItemRenderModel.swift" \
    "$PROJECT_DIR/Pulse/Models/MetricCalculations.swift" \
    "$PROJECT_DIR/Pulse/Models/SMCValueDecoder.swift" \
    "$PROJECT_DIR/Pulse/Models/PulseDefaults.swift" \
    "$PROJECT_DIR/Pulse/Services/SMCReader.swift" \
    "$PROJECT_DIR/Pulse/Services/AppleSmartBatteryReader.swift" \
    "$PROJECT_DIR/Pulse/Services/HardwareMonitor.swift" \
    "$PROJECT_DIR/Pulse/Services/SystemMonitor.swift" \
    "$PROJECT_DIR/Pulse/Services/BatteryMonitor.swift" \
    "$PROJECT_DIR/Pulse/Services/LaunchAtLoginController.swift" \
    "$PROJECT_DIR/Pulse/Services/UpdateChecker.swift" \
    "$PROJECT_DIR/Pulse/UI/StatusItemHost.swift" \
    "$PROJECT_DIR/Pulse/UI/StatusItemRenderer.swift" \
    "$PROJECT_DIR/Pulse/UI/RefreshIntervalControl.swift" \
    "$PROJECT_DIR/Pulse/UI/ThresholdValueField.swift" \
    "$PROJECT_DIR/Pulse/UI/PopoverContentView.swift" \
    "$PROJECT_DIR/Pulse/UI/PanelSession.swift" \
    "$PROJECT_DIR/Pulse/UI/StatusBarController.swift" \
    "$PROJECT_DIR/tests/MetricCalculationsTests.swift"

# 运行主套件并捕获输出与真实退出码
set +e
main_output="$("$TEST_BINARY" 2>&1)"
main_status=$?
set -e
printf '%s\n' "$main_output"
if [ "$main_status" -ne 0 ]; then
    echo "ERROR: Main test suite exited with status $main_status"
    exit 1
fi
if ! printf '%s\n' "$main_output" | grep -Eq '^PASSED: [0-9]+ assertions$'; then
    echo "ERROR: Main test suite failed to produce a valid PASSED summary"
    exit 1
fi

# 编译聚焦位图套件
FOCUS_TEST_BINARY="${TMPDIR:-/tmp}/pulse-icon-sizing-tests"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
swiftc \
    -framework AppKit \
    -framework IOKit \
    -framework ServiceManagement \
    -o "$FOCUS_TEST_BINARY" \
    "$PROJECT_DIR/Pulse/Models/MemoryMetrics.swift" \
    "$PROJECT_DIR/Pulse/Models/PulseSnapshot.swift" \
    "$PROJECT_DIR/Pulse/Models/StatusItemRenderModel.swift" \
    "$PROJECT_DIR/Pulse/Models/MetricCalculations.swift" \
    "$PROJECT_DIR/Pulse/Models/PulseDefaults.swift" \
    "$PROJECT_DIR/Pulse/Services/BatteryMonitor.swift" \
    "$PROJECT_DIR/Pulse/UI/StatusItemRenderer.swift" \
    "$PROJECT_DIR/Tests/StatusItemIconSizingTests.swift"

# 运行聚焦套件并捕获输出与真实退出码
set +e
focus_output="$("$FOCUS_TEST_BINARY" 2>&1)"
focus_status=$?
set -e
printf '%s\n' "$focus_output"
if [ "$focus_status" -ne 0 ]; then
    echo "ERROR: Focused test suite exited with status $focus_status"
    exit 1
fi
if ! printf '%s\n' "$focus_output" | grep -Eq '^PASSED: focused status icon sizing$'; then
    echo "ERROR: Focused test suite failed to produce a valid PASSED summary"
    exit 1
fi
