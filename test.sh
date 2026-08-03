#!/bin/bash
# 编译并运行不依赖 UI 与真实硬件的 Pulse 指标测试。

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_BINARY="${TMPDIR:-/tmp}/pulse-metric-tests"
MODULE_CACHE="${TMPDIR:-/tmp}/pulse-swift-module-cache"

mkdir -p "$MODULE_CACHE"

# 将内存领域类型纳入测试编译源列表，以覆盖计算与展示语义的分离。
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
swiftc \
    -framework AppKit \
    -framework IOKit \
    -framework ServiceManagement \
    -o "$TEST_BINARY" \
    "$PROJECT_DIR/Pulse/Models/MemoryMetrics.swift" \
    "$PROJECT_DIR/Pulse/Models/PulseSnapshot.swift" \
    "$PROJECT_DIR/Pulse/Models/MetricCalculations.swift" \
    "$PROJECT_DIR/Pulse/Models/SMCValueDecoder.swift" \
    "$PROJECT_DIR/Pulse/Models/PulseDefaults.swift" \
    "$PROJECT_DIR/Pulse/Services/SMCReader.swift" \
    "$PROJECT_DIR/Pulse/Services/HardwareMonitor.swift" \
    "$PROJECT_DIR/Pulse/Services/SystemMonitor.swift" \
    "$PROJECT_DIR/Pulse/Services/BatteryMonitor.swift" \
    "$PROJECT_DIR/Pulse/Services/LaunchAtLoginController.swift" \
    "$PROJECT_DIR/Pulse/UI/StatusItemView.swift" \
    "$PROJECT_DIR/Pulse/UI/RefreshIntervalControl.swift" \
    "$PROJECT_DIR/Pulse/UI/PopoverContentView.swift" \
    "$PROJECT_DIR/Pulse/UI/StatusBarController.swift" \
    "$PROJECT_DIR/tests/MetricCalculationsTests.swift"

"$TEST_BINARY"
