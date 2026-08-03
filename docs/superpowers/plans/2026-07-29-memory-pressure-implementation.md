# Pulse Memory Pressure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the misleading normalized free-memory value with a real physical-memory usage percentage and a separately sourced macOS normal/warning/critical pressure state.

**Architecture:** Add explicit memory domain types, calculate usage from Mach VM statistics, and keep current pressure state in `SystemMonitor` using an initial sysctl read plus a long-lived Dispatch memory-pressure source. Pass one `MemorySnapshot` through `AppDelegate` to the status bar so the number and color cannot be confused again.

**Tech Stack:** Swift 5, AppKit, Darwin Mach APIs, `sysctlbyname`, Grand Central Dispatch, the repository’s standalone Swift test harness and build scripts.

**Constraint:** The user explicitly requested no Git commit. All commit steps from the generic workflow are intentionally omitted.

---

## File map

- Create `Pulse/Models/MemoryMetrics.swift`: memory pressure enum, presentation role, page-statistics input and immutable snapshot.
- Modify `Pulse/Models/MetricCalculations.swift`: pure, overflow-safe memory usage calculation and byte formatting.
- Modify `Pulse/Models/PulseDefaults.swift`: low-frequency pressure resynchronization interval.
- Modify `Pulse/Services/SystemMonitor.swift`: replace the `memory_pressure -Q` subprocess with Mach/sysctl reads and DispatchSource state monitoring.
- Modify `Pulse/App/AppDelegate.swift`: collect and pass a complete `MemorySnapshot`.
- Modify `Pulse/UI/StatusBarController.swift`: show separate memory usage and pressure details and construct the tooltip.
- Modify `Pulse/UI/StatusItemView.swift`: display usage percentage and color it only from pressure state.
- Modify `Tests/MetricCalculationsTests.swift`: add calculation, mapping, monitor state and degradation tests; remove obsolete parser/cache tests.
- Modify `build.sh` and `test.sh`: compile the new model file.

### Task 1: Add explicit memory types and pure calculations

**Files:**

- Create: `Pulse/Models/MemoryMetrics.swift`
- Modify: `Pulse/Models/MetricCalculations.swift`
- Modify: `Tests/MetricCalculationsTests.swift`
- Modify: `build.sh`
- Modify: `test.sh`

- [ ] **Step 1: Replace the obsolete parser tests with failing memory-domain tests**

In `Tests/MetricCalculationsTests.swift`, replace calls to `testMemoryPressureParsing()` and `testMemoryPressureCache()` in `main()` with:

```swift
testMemoryPressureLevelMapping()
testMemoryUsageCalculation()
testMemoryPresentationRole()
```

Replace `testMemoryPressureParsing()` with:

```swift
/// 验证内核原始值只映射已知的三档压力，未知值不得伪装为正常。
private static func testMemoryPressureLevelMapping() {
    expectTrue(
        MemoryPressureLevel(rawKernelValue: 0x01) == .normal,
        "kernel level 1 should map to normal"
    )
    expectTrue(
        MemoryPressureLevel(rawKernelValue: 0x02) == .warning,
        "kernel level 2 should map to warning"
    )
    expectTrue(
        MemoryPressureLevel(rawKernelValue: 0x04) == .critical,
        "kernel level 4 should map to critical"
    )
    expectTrue(
        MemoryPressureLevel(rawKernelValue: 0x08) == .unavailable,
        "unknown kernel levels should remain unavailable"
    )
    expectTrue(
        MemoryPressureLevel(rawKernelValue: nil) == .unavailable,
        "missing kernel levels should remain unavailable"
    )
}

/// 验证已使用内存排除空闲页和文件缓存页，并且不会溢出或越界。
private static func testMemoryUsageCalculation() {
    let snapshot = MetricCalculations.memorySnapshot(
        statistics: MemoryPageStatistics(
            totalBytes: 24 * 1_024 * 1_024 * 1_024,
            pageSize: 16_384,
            freePages: 6_554,
            externalPages: 262_144
        ),
        pressureLevel: .warning
    )

    expectEqual(
        snapshot.usagePercentage,
        82.92,
        "free and file-backed cache pages should be excluded from used memory",
        tolerance: 0.01
    )
    expectTrue(snapshot.pressureLevel == .warning, "pressure should pass through unchanged")

    let overreported = MetricCalculations.memorySnapshot(
        statistics: MemoryPageStatistics(
            totalBytes: 1_024,
            pageSize: 1_024,
            freePages: UInt64.max,
            externalPages: UInt64.max
        ),
        pressureLevel: .normal
    )
    expectEqual(
        overreported.usagePercentage,
        0,
        "invalidly large available counts should clamp usage to zero"
    )

    let unavailable = MetricCalculations.memorySnapshot(
        statistics: nil,
        pressureLevel: .critical
    )
    expectNil(unavailable.usagePercentage, "missing VM statistics should remain unavailable")
    expectTrue(
        unavailable.pressureLevel == .critical,
        "usage failure must not erase a valid pressure level"
    )
}

/// 验证使用率与颜色状态保持独立。
private static func testMemoryPresentationRole() {
    expectTrue(
        MemoryPressureLevel.normal.presentationRole == .healthy,
        "normal pressure should use the healthy role"
    )
    expectTrue(
        MemoryPressureLevel.warning.presentationRole == .warning,
        "warning pressure should use the warning role"
    )
    expectTrue(
        MemoryPressureLevel.critical.presentationRole == .critical,
        "critical pressure should use the critical role"
    )
    expectTrue(
        MemoryPressureLevel.unavailable.presentationRole == .unavailable,
        "unavailable pressure should not appear healthy"
    )
}
```

- [ ] **Step 2: Run the tests and verify the new types do not exist yet**

Run:

```bash
./test.sh
```

Expected: compilation fails with unresolved `MemoryPressureLevel`, `MemoryPageStatistics`, or `memorySnapshot`.

- [ ] **Step 3: Add the memory domain model**

Create `Pulse/Models/MemoryMetrics.swift`:

```swift
import Foundation

/// macOS 对外表达的系统内存压力状态；不可用必须单独保留。
enum MemoryPressureLevel: Equatable {
    case normal
    case warning
    case critical
    case unavailable

    /// 内核和 Dispatch 使用相同的 1/2/4 位值；拒绝未知组合以免误报。
    init(rawKernelValue: Int32?) {
        switch rawKernelValue {
        case 0x01: self = .normal
        case 0x02: self = .warning
        case 0x04: self = .critical
        default: self = .unavailable
        }
    }

    var presentationRole: MemoryPresentationRole {
        switch self {
        case .normal: return .healthy
        case .warning: return .warning
        case .critical: return .critical
        case .unavailable: return .unavailable
        }
    }

    var displayName: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "警告"
        case .critical: return "严重"
        case .unavailable: return "不可用"
        }
    }
}

/// UI 可测试的语义颜色角色，不让 Models 依赖 AppKit。
enum MemoryPresentationRole: Equatable {
    case healthy
    case warning
    case critical
    case unavailable
}

/// 从 Mach VM API 取得的最小统计集合。
struct MemoryPageStatistics: Equatable {
    let totalBytes: UInt64
    let pageSize: UInt64
    let freePages: UInt64
    let externalPages: UInt64
}

/// 同一刷新周期内的内存使用量和系统压力状态。
struct MemorySnapshot: Equatable {
    let usedBytes: UInt64?
    let totalBytes: UInt64?
    let usagePercentage: Double?
    let pressureLevel: MemoryPressureLevel
}
```

- [ ] **Step 4: Add the overflow-safe pure calculation**

Add to `MetricCalculations`:

```swift
/// 把 Mach 页统计转换成“已使用 / 物理内存”，文件支持页视为可回收缓存。
static func memorySnapshot(
    statistics: MemoryPageStatistics?,
    pressureLevel: MemoryPressureLevel
) -> MemorySnapshot {
    guard let statistics,
          statistics.totalBytes > 0,
          statistics.pageSize > 0 else {
        return MemorySnapshot(
            usedBytes: nil,
            totalBytes: statistics?.totalBytes,
            usagePercentage: nil,
            pressureLevel: pressureLevel
        )
    }

    let availablePages = statistics.freePages.addingReportingOverflow(
        statistics.externalPages
    )
    let availableBytes = availablePages.partialValue.multipliedReportingOverflow(
        by: statistics.pageSize
    )

    // 异常或溢出的系统统计按“最多可回收”处理，避免产生负数或超过 100%。
    let safeAvailableBytes: UInt64
    if availablePages.overflow || availableBytes.overflow {
        safeAvailableBytes = statistics.totalBytes
    } else {
        safeAvailableBytes = min(availableBytes.partialValue, statistics.totalBytes)
    }

    let usedBytes = statistics.totalBytes - safeAvailableBytes
    let percentage = Double(usedBytes) / Double(statistics.totalBytes) * 100.0
    return MemorySnapshot(
        usedBytes: usedBytes,
        totalBytes: statistics.totalBytes,
        usagePercentage: min(max(percentage, 0.0), 100.0),
        pressureLevel: pressureLevel
    )
}

/// 用二进制 GB 呈现，与活动监视器对统一内存容量的显示更接近。
static func formattedGigabytes(_ bytes: UInt64?) -> String {
    guard let bytes else { return "—" }
    let gigabytes = Double(bytes) / 1_073_741_824.0
    return String(format: "%.2f GB", locale: Locale(identifier: "en_US_POSIX"), gigabytes)
}
```

- [ ] **Step 5: Add the new source file to both compile scripts**

In `build.sh`, insert before `MetricCalculations.swift`:

```bash
    "$SOURCE_DIR/Models/MemoryMetrics.swift" \
```

In `test.sh`, insert before `MetricCalculations.swift`:

```bash
    "$PROJECT_DIR/Pulse/Models/MemoryMetrics.swift" \
```

- [ ] **Step 6: Run the tests**

Run:

```bash
./test.sh
```

Expected: all assertions pass; obsolete `normalizedMemoryPressure` parser tests are gone.

### Task 2: Replace the subprocess with Mach/sysctl/Dispatch collection

**Files:**

- Modify: `Pulse/Models/PulseDefaults.swift`
- Modify: `Pulse/Services/SystemMonitor.swift`
- Modify: `Tests/MetricCalculationsTests.swift`

- [ ] **Step 1: Write failing monitor-state tests**

Add `testMemoryMonitorSnapshot()` to the test entry and define:

```swift
/// 验证初始状态、事件更新、定期重读和部分失败互不污染。
private static func testMemoryMonitorSnapshot() {
    var pressureReads = 0
    let baseUptime = ProcessInfo.processInfo.systemUptime
    let monitor = SystemMonitor(
        memoryStatisticsReader: {
            MemoryPageStatistics(
                totalBytes: 1_024,
                pageSize: 1,
                freePages: 100,
                externalPages: 200
            )
        },
        pressureLevelReader: {
            pressureReads += 1
            return pressureReads == 1 ? 0x02 : 0x01
        },
        startPressureEvents: false
    )

    let initial = monitor.getMemorySnapshot(nowUptime: baseUptime)
    expectEqual(initial.usagePercentage, 70, "usage should come from VM statistics")
    expectTrue(initial.pressureLevel == .warning, "initial sysctl state should be warning")

    monitor.recordMemoryPressureEvent(rawValue: 0x04, nowUptime: baseUptime + 1)
    let eventUpdated = monitor.getMemorySnapshot(nowUptime: baseUptime + 1)
    expectTrue(
        eventUpdated.pressureLevel == .critical,
        "Dispatch pressure event should update the cached level"
    )
    expectEqual(Double(pressureReads), 1, "a fresh cache should not poll sysctl every second")

    let resynchronized = monitor.getMemorySnapshot(
        nowUptime: baseUptime + 1 + PulseDefaults.memoryPressureResyncInterval
    )
    expectTrue(
        resynchronized.pressureLevel == .normal,
        "the low-frequency sysctl read should repair missed events"
    )
    expectEqual(Double(pressureReads), 2, "the resync boundary should reread sysctl")
}
```

- [ ] **Step 2: Run the tests and verify the new initializer/API fails**

Run:

```bash
./test.sh
```

Expected: compilation fails because the injected readers, `getMemorySnapshot`, and event method do not exist.

- [ ] **Step 3: Replace the old memory cache fields and initializer**

In `SystemMonitor`, remove `memoryPressureReader`, the subprocess cache, and the testing initializer that accepts `() -> Double?`.

Add:

```swift
private let memoryPressureLock = NSLock()
private let memoryStatisticsReader: () -> MemoryPageStatistics?
private let pressureLevelReader: () -> Int32?
private var cachedPressureLevel: MemoryPressureLevel
private var pressureLevelReadAtUptime: TimeInterval
private var memoryPressureSource: (any DispatchSourceMemoryPressure)?

public convenience init() {
    self.init(
        memoryStatisticsReader: SystemMonitor.readMemoryStatistics,
        pressureLevelReader: SystemMonitor.readKernelMemoryPressureLevel,
        startPressureEvents: true
    )
}

/// 注入只读来源，使压力变化和失败降级无需制造真实内存压力即可测试。
init(
    memoryStatisticsReader: @escaping () -> MemoryPageStatistics?,
    pressureLevelReader: @escaping () -> Int32?,
    startPressureEvents: Bool
) {
    self.memoryStatisticsReader = memoryStatisticsReader
    self.pressureLevelReader = pressureLevelReader
    cachedPressureLevel = MemoryPressureLevel(rawKernelValue: pressureLevelReader())
    pressureLevelReadAtUptime = ProcessInfo.processInfo.systemUptime

    if startPressureEvents {
        startMemoryPressureEvents()
    }
}

deinit {
    memoryPressureSource?.cancel()
}
```

- [ ] **Step 4: Implement the snapshot and pressure event state**

Replace `getMemoryPressure`, `readNormalizedMemoryPressure`, and all `Process` code with:

```swift
/// 读取同一刷新周期的使用率与压力；压力只做低频 sysctl 校验。
func getMemorySnapshot(nowUptime: TimeInterval? = nil) -> MemorySnapshot {
    let now = nowUptime ?? ProcessInfo.processInfo.systemUptime
    let level = currentPressureLevel(nowUptime: now)
    return MetricCalculations.memorySnapshot(
        statistics: memoryStatisticsReader(),
        pressureLevel: level
    )
}

private func currentPressureLevel(nowUptime: TimeInterval) -> MemoryPressureLevel {
    memoryPressureLock.lock()
    defer { memoryPressureLock.unlock() }

    let elapsed = nowUptime - pressureLevelReadAtUptime
    if elapsed < 0 || elapsed >= PulseDefaults.memoryPressureResyncInterval {
        cachedPressureLevel = MemoryPressureLevel(rawKernelValue: pressureLevelReader())
        pressureLevelReadAtUptime = nowUptime
    }
    return cachedPressureLevel
}

/// Dispatch 可能合并多个事件位，必须优先采用最严重的有效状态。
func recordMemoryPressureEvent(
    rawValue: UInt,
    nowUptime: TimeInterval? = nil
) {
    let level: MemoryPressureLevel
    if rawValue & UInt(DISPATCH_MEMORYPRESSURE_CRITICAL) != 0 {
        level = .critical
    } else if rawValue & UInt(DISPATCH_MEMORYPRESSURE_WARN) != 0 {
        level = .warning
    } else if rawValue & UInt(DISPATCH_MEMORYPRESSURE_NORMAL) != 0 {
        level = .normal
    } else {
        return
    }

    memoryPressureLock.lock()
    cachedPressureLevel = level
    pressureLevelReadAtUptime = nowUptime ?? ProcessInfo.processInfo.systemUptime
    memoryPressureLock.unlock()
}

private func startMemoryPressureEvents() {
    let source = DispatchSource.makeMemoryPressureSource(
        eventMask: [.normal, .warning, .critical],
        queue: DispatchQueue(label: "com.hlc.pulse.memory-pressure", qos: .utility)
    )
    memoryPressureSource = source
    source.setEventHandler { [weak self] in
        guard let self, let source = self.memoryPressureSource else { return }
        self.recordMemoryPressureEvent(rawValue: source.data.rawValue)
    }
    source.resume()
}
```

- [ ] **Step 5: Implement the direct kernel readers**

Add to `SystemMonitor`:

```swift
/// 直接读取 Mach 页统计，避免每次刷新创建外部进程。
private static func readMemoryStatistics() -> MemoryPageStatistics? {
    var totalBytes: UInt64 = 0
    var totalSize = MemoryLayout<UInt64>.size
    guard sysctlbyname("hw.memsize", &totalBytes, &totalSize, nil, 0) == 0 else {
        return nil
    }

    var pageSize: vm_size_t = 0
    guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
        return nil
    }

    var statistics = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
    )
    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }

    return MemoryPageStatistics(
        totalBytes: totalBytes,
        pageSize: UInt64(pageSize),
        freePages: UInt64(statistics.free_count),
        externalPages: UInt64(statistics.external_page_count)
    )
}

/// 未公开的当前级别只封装在此处；失败时由上层明确显示不可用。
private static func readKernelMemoryPressureLevel() -> Int32? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(
        "kern.memorystatus_vm_pressure_level",
        &value,
        &size,
        nil,
        0
    ) == 0 else {
        return nil
    }
    return value
}
```

- [ ] **Step 6: Define the pressure resynchronization interval**

Replace obsolete memory command defaults in `PulseDefaults.swift` with:

```swift
/// DispatchSource 负责即时变化；低频重读只用于唤醒或事件遗漏后的状态修复。
static let memoryPressureResyncInterval: TimeInterval = 30.0
```

- [ ] **Step 7: Run the service tests**

Run:

```bash
./test.sh
```

Expected: all assertions pass, and the project no longer references `/usr/bin/memory_pressure`.

Verify removal:

```bash
rg -n "memory_pressure|normalizedMemoryPressure|memoryPressureCommandTimeout" Pulse Tests
```

Expected: no matches.

### Task 3: Pass the snapshot into the A1 status-bar presentation

**Files:**

- Modify: `Pulse/App/AppDelegate.swift`
- Modify: `Pulse/UI/StatusBarController.swift`
- Modify: `Pulse/UI/StatusItemView.swift`

- [ ] **Step 1: Change collection to use one memory snapshot**

In `AppDelegate.collectAndDisplayMetrics()`, replace:

```swift
let memPressure = systemMonitor.getMemoryPressure()
```

with:

```swift
let memory = systemMonitor.getMemorySnapshot()
```

Change the `updateDisplay` argument from `memPressure: memPressure` to:

```swift
memory: memory,
```

- [ ] **Step 2: Change `StatusItemView` to hold explicit memory fields**

Replace:

```swift
var memPressure: Double?
```

with:

```swift
var memoryUsagePercentage: Double?
var memoryPressureLevel: MemoryPressureLevel = .unavailable
```

Use `memoryUsagePercentage` when formatting `memValStr`.

Replace the 60%/80% threshold block with:

```swift
// 内存数字表示使用率，但颜色只表示 macOS 压力状态。
let memColor: NSColor
switch memoryPressureLevel.presentationRole {
case .healthy:
    memColor = .systemGreen
case .warning:
    memColor = .systemYellow
case .critical:
    memColor = .systemRed
case .unavailable:
    memColor = .secondaryLabelColor
}
```

Keep `memorychip` as the symbol and apply `memColor` to both icon and text.

- [ ] **Step 3: Separate usage and pressure in the menu**

In `StatusBarController`:

1. Rename `memMenuItem` to `memoryUsageMenuItem`.
2. Add:

```swift
private let memoryPressureMenuItem = NSMenuItem()
```

3. Assign `memorychip` to the usage item and `gauge.with.dots.needle.33percent` to the pressure item.
4. Add both items to `detailItems`.
5. Change the update signature to:

```swift
func updateDisplay(
    power: Double?,
    memory: MemorySnapshot,
    temperature: Double?,
    cpuUsage: Double,
    cpuFrequency: Double,
    chargeState: String
)
```

6. Synchronize the custom view:

```swift
customView.memoryUsagePercentage = memory.usagePercentage
customView.memoryPressureLevel = memory.pressureLevel
```

7. Build the two detail strings:

```swift
let usagePercent = MetricCalculations.formatted(
    memory.usagePercentage,
    decimals: 0,
    suffix: "%"
)
let used = MetricCalculations.formattedGigabytes(memory.usedBytes)
let total = MetricCalculations.formattedGigabytes(memory.totalBytes)
let usageDetail = memory.usagePercentage == nil
    ? "—"
    : "\(used) / \(total) (\(usagePercent))"

memoryUsageMenuItem.attributedTitle = makeTabAlignedAttributedString(
    label: "内存使用",
    value: usageDetail
)
memoryPressureMenuItem.attributedTitle = makeTabAlignedAttributedString(
    label: "内存压力",
    value: memory.pressureLevel.displayName
)
```

8. Add the tooltip:

```swift
if let button = statusItem.button {
    button.toolTip = "已使用 \(used) / \(total) · 压力：\(memory.pressureLevel.displayName)"
}
```

9. Update the initial placeholder call with:

```swift
memory: MemorySnapshot(
    usedBytes: nil,
    totalBytes: nil,
    usagePercentage: nil,
    pressureLevel: .unavailable
),
```

- [ ] **Step 4: Compile with warnings treated as errors**

Run:

```bash
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/pulse-swift-module-cache" \
SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/pulse-swift-module-cache" \
swiftc -warnings-as-errors -typecheck \
  -framework AppKit -framework IOKit \
  Pulse/App/main.swift \
  Pulse/App/AppDelegate.swift \
  Pulse/Models/MemoryMetrics.swift \
  Pulse/Models/MetricCalculations.swift \
  Pulse/Models/SMCValueDecoder.swift \
  Pulse/Models/PulseDefaults.swift \
  Pulse/UI/StatusBarController.swift \
  Pulse/UI/StatusItemView.swift \
  Pulse/Services/SMCReader.swift \
  Pulse/Services/HardwareMonitor.swift \
  Pulse/Services/SystemMonitor.swift \
  Pulse/Services/BatteryMonitor.swift
```

Expected: exit code 0 with no output.

- [ ] **Step 5: Run the complete test suite and build**

Run:

```bash
./test.sh
./build.sh
```

Expected: all assertions pass and `build/Pulse.app` is produced.

### Task 4: Verify against the current Mac and Activity Monitor

**Files:**

- Modify only if verification exposes a reproducible calculation or UI defect.

- [ ] **Step 1: Capture kernel and VM reference data**

Run:

```bash
/usr/bin/vm_stat
/usr/sbin/sysctl -n hw.memsize
/usr/sbin/sysctl kern.memorystatus_vm_pressure_level
```

Expected:

- page size and page counts are readable;
- total memory corresponds to the Mac’s physical memory;
- pressure raw value maps to the current Activity Monitor color.

- [ ] **Step 2: Compare the usage calculation**

Calculate reference values from the same sample:

```text
used = total - (free_count + external_page_count) × pageSize
usage = used / total × 100
```

Compare with Activity Monitor’s “Memory Used / Physical Memory”. Accept a small sampling difference; reject a persistent discrepancy larger than 3 percentage points across three near-simultaneous samples.

- [ ] **Step 3: Launch the rebuilt app**

Run:

```bash
open build/Pulse.app
```

Expected:

- menu bar uses `memorychip`;
- percentage is close to Activity Monitor’s used/physical ratio;
- green/yellow/red matches Activity Monitor pressure;
- tooltip and menu distinguish “内存使用” from “内存压力”;
- no `memory_pressure` child process appears.

- [ ] **Step 4: Perform final regression checks**

Run:

```bash
./test.sh
./build.sh
plutil -lint build/Pulse.app/Contents/Info.plist
```

Expected: tests pass, build succeeds, and plist reports `OK`.

- [ ] **Step 5: Report results without committing**

Report:

- exact assertion count;
- typecheck/build/plist results;
- observed Pulse usage percentage versus Activity Monitor;
- observed pressure raw value and matching color;
- any remaining limitation from the undocumented current-level sysctl.

Do not run `git add`, `git commit`, or any destructive cleanup.
