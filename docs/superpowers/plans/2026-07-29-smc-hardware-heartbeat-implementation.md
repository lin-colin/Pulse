# Pulse SMC Hardware Heartbeat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the charging-invalid `AppleSmartBattery.SystemLoad` reading with read-only SMC `PSTR`, align battery temperature with `TB0T`, and retain only truthful state-aware fallbacks.

**Architecture:** Add a pure SMC byte decoder and a focused read-only `SMCReader`. `HardwareMonitor` gathers SMC and `AppleSmartBattery` values, while `MetricCalculations` owns validation and source selection so charging, battery, and unavailable-source behavior can be tested without hardware.

**Tech Stack:** Swift 5, Foundation, IOKit `AppleSMC`/`AppleSmartBattery`, shell-based `swiftc` build and tests.

**User constraint:** Do not run `git commit` or create Git history. Commit steps normally required by the planning skill are intentionally omitted.

---

## File map

- Create `Pulse/Models/SMCValueDecoder.swift`: Pure decoding of hardware-reported SMC `flt ` and `sp78` byte payloads.
- Create `Pulse/Services/SMCReader.swift`: Read-only connection to `AppleSMC` and reads of `PSTR`/`TB0T`.
- Modify `Pulse/Models/MetricCalculations.swift`: Validate and select primary/fallback power and temperature values.
- Modify `Pulse/Services/HardwareMonitor.swift`: Gather both sources and apply the selection policy.
- Modify `tests/MetricCalculationsTests.swift`: Regression tests for charging behavior, temperature priority, and SMC decoding.
- Modify `test.sh`: Compile the new pure decoder into the test binary.
- Modify `build.sh`: Compile the new decoder and SMC reader into Pulse.
- Modify `README.md`: Document the new metric definitions and private-interface compatibility constraint.

### Task 1: Lock down state-aware power and temperature selection

**Files:**

- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `Pulse/Models/MetricCalculations.swift`

- [x] **Step 1: Add failing source-selection tests**

Add calls in `main()`:

```swift
testPreferredSystemLoad()
testPreferredBatteryTemperature()
```

Add these tests:

```swift
/// 验证系统负载始终优先使用 PSTR，并禁止充电状态回退到错误的旧字段。
private static func testPreferredSystemLoad() {
    expectEqual(
        MetricCalculations.preferredSystemLoadWatts(
            smcWatts: 9.148,
            legacyMilliwatts: 79_283,
            externalConnected: true
        ),
        9.148,
        "PSTR should override the charging-invalid legacy SystemLoad"
    )
    expectNil(
        MetricCalculations.preferredSystemLoadWatts(
            smcWatts: nil,
            legacyMilliwatts: 79_283,
            externalConnected: true
        ),
        "external power must not fall back to the legacy SystemLoad"
    )
    expectEqual(
        MetricCalculations.preferredSystemLoadWatts(
            smcWatts: nil,
            legacyMilliwatts: 6_349,
            externalConnected: false
        ),
        6.349,
        "battery power may use the validated legacy fallback"
    )
    expectNil(
        MetricCalculations.preferredSystemLoadWatts(
            smcWatts: nil,
            legacyMilliwatts: 6_349,
            externalConnected: nil
        ),
        "unknown power state must not guess from the legacy field"
    )
    expectNil(
        MetricCalculations.preferredSystemLoadWatts(
            smcWatts: 501,
            legacyMilliwatts: 6_349,
            externalConnected: true
        ),
        "an invalid PSTR value must not unlock the AC fallback"
    )
}

/// 验证电池温度优先采用 TB0T，并在其不可用时回退到 BMS 物理温度。
private static func testPreferredBatteryTemperature() {
    expectEqual(
        MetricCalculations.preferredBatteryTemperatureCelsius(
            smcCelsius: 32.8,
            bmsCentiDegrees: 3_060
        ),
        32.8,
        "TB0T should be the primary battery temperature"
    )
    expectEqual(
        MetricCalculations.preferredBatteryTemperatureCelsius(
            smcCelsius: nil,
            bmsCentiDegrees: 3_060
        ),
        30.6,
        "BMS temperature should remain a truthful fallback"
    )
    expectEqual(
        MetricCalculations.preferredBatteryTemperatureCelsius(
            smcCelsius: 101,
            bmsCentiDegrees: 3_060
        ),
        30.6,
        "an invalid TB0T value should use the BMS fallback"
    )
    expectNil(
        MetricCalculations.preferredBatteryTemperatureCelsius(
            smcCelsius: .nan,
            bmsCentiDegrees: nil
        ),
        "invalid and missing temperature sources should remain unavailable"
    )
}
```

- [x] **Step 2: Run the tests and verify the new API is missing**

Run:

```bash
./test.sh
```

Expected: compilation fails because `preferredSystemLoadWatts` and `preferredBatteryTemperatureCelsius` do not exist.

- [x] **Step 3: Implement minimal validation and selection**

In `MetricCalculations`, add:

```swift
/// 选择可信的整机功率：PSTR 优先，旧字段仅允许在明确使用电池时回退。
static func preferredSystemLoadWatts(
    smcWatts: Double?,
    legacyMilliwatts: Double?,
    externalConnected: Bool?
) -> Double? {
    if let smcWatts = validatedPowerWatts(smcWatts) {
        return smcWatts
    }

    guard externalConnected == false,
          let legacyMilliwatts,
          legacyMilliwatts.isFinite else {
        return nil
    }
    return validatedPowerWatts(legacyMilliwatts / 1_000.0)
}

/// 选择可信的电池温度：TB0T 优先，BMS Temperature 作为真实测点回退。
static func preferredBatteryTemperatureCelsius(
    smcCelsius: Double?,
    bmsCentiDegrees: Double?
) -> Double? {
    if let smcCelsius = validatedTemperatureCelsius(smcCelsius) {
        return smcCelsius
    }
    return batteryTemperatureCelsius(fromCentiDegrees: bmsCentiDegrees)
}

/// 拒绝损坏或单位错误的系统功率，不对合法值做截断。
private static func validatedPowerWatts(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (0.0...500.0).contains(value) else {
        return nil
    }
    return value
}

/// 共用电池温度的有限值与物理范围校验。
private static func validatedTemperatureCelsius(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (-20.0...100.0).contains(value) else {
        return nil
    }
    return value
}
```

Refactor `batteryTemperatureCelsius(fromCentiDegrees:)` to call `validatedTemperatureCelsius(rawValue / 100.0)`.

- [x] **Step 4: Run the pure tests**

Run:

```bash
./test.sh
```

Expected: all assertions pass, including the new charging regression.

### Task 2: Add a tested pure SMC decoder

**Files:**

- Create: `Pulse/Models/SMCValueDecoder.swift`
- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `test.sh`

- [x] **Step 1: Add failing decoder tests**

Add `testSMCValueDecoding()` to `main()` and add:

```swift
/// 验证 SMC 返回的 flt 与 sp78 按各自字节序正确解码。
private static func testSMCValueDecoding() {
    expectEqual(
        SMCValueDecoder.decode(
            dataType: SMCValueDecoder.floatDataType,
            bytes: [0x00, 0x00, 0xF4, 0x40]
        ),
        7.625,
        "little-endian flt bytes should decode to watts"
    )
    expectEqual(
        SMCValueDecoder.decode(
            dataType: SMCValueDecoder.sp78DataType,
            bytes: [0x20, 0xC0]
        ),
        32.75,
        "big-endian sp78 bytes should decode to Celsius"
    )
    expectEqual(
        SMCValueDecoder.decode(
            dataType: SMCValueDecoder.sp78DataType,
            bytes: [0xFE, 0x80]
        ),
        -1.5,
        "signed sp78 bytes should preserve negative values"
    )
    expectNil(
        SMCValueDecoder.decode(
            dataType: SMCValueDecoder.floatDataType,
            bytes: [0x00, 0x00]
        ),
        "short flt payloads should be rejected"
    )
    expectNil(
        SMCValueDecoder.decode(dataType: 0, bytes: [0, 0, 0, 0]),
        "unknown SMC data types should be rejected"
    )
}
```

- [x] **Step 2: Run tests and verify the decoder type is missing**

Run:

```bash
./test.sh
```

Expected: compilation fails because `SMCValueDecoder` does not exist.

- [x] **Step 3: Implement the pure decoder**

Create `Pulse/Models/SMCValueDecoder.swift`:

```swift
import Foundation

/// 只负责把 Apple SMC 原始载荷解码为数值，不访问硬件或选择数据源。
enum SMCValueDecoder {
    static let floatDataType = fourCharacterCode("flt ")
    static let sp78DataType = fourCharacterCode("sp78")

    /// 解码功率使用的原生小端 Float，或温度使用的大端 signed 7.8 定点数。
    static func decode(dataType: UInt32, bytes: [UInt8]) -> Double? {
        switch dataType {
        case floatDataType:
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))

        case sp78DataType:
            guard bytes.count >= 2 else { return nil }
            let bits = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: bits)) / 256.0

        default:
            return nil
        }
    }

    /// 将四字符 SMC 类型编码成内核接口使用的 UInt32。
    static func fourCharacterCode(_ string: String) -> UInt32 {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { return 0 }
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }
}
```

In `test.sh`, add the new source immediately after `MetricCalculations.swift`:

```bash
"$PROJECT_DIR/Pulse/Models/SMCValueDecoder.swift" \
```

- [x] **Step 4: Run the pure tests**

Run:

```bash
./test.sh
```

Expected: all assertions pass.

### Task 3: Implement read-only AppleSMC access

**Files:**

- Create: `Pulse/Services/SMCReader.swift`
- Modify: `build.sh`

- [x] **Step 1: Define the narrow reader interface and snapshot**

At the top of `SMCReader.swift`, define:

```swift
import Foundation
import IOKit

/// 同一轮 SMC 读取中的整机功率与电池温度。
struct SMCSnapshot {
    let systemPowerWatts: Double?
    let batteryTemperatureCelsius: Double?
}

/// 允许 HardwareMonitor 注入真实或测试 SMC 数据源。
protocol SMCReading {
    func readSnapshot() -> SMCSnapshot
}
```

- [x] **Step 2: Define ABI-compatible read-only SMC structures**

In the same file, add private structures matching the `AppleSMC` user client ABI:

```swift
private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
```

- [x] **Step 3: Implement connection lifetime and snapshot reads**

Add:

```swift
/// 通过 AppleSMC 私有 IOKit 用户客户端只读传感器；不包含任何写命令。
final class SMCReader: SMCReading {
    private static let kernelMethodIndex: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9

    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var openedConnection: io_connect_t = IO_OBJECT_NULL
        guard IOServiceOpen(service, mach_task_self_, 0, &openedConnection) == KERN_SUCCESS else {
            return nil
        }
        connection = openedConnection
    }

    deinit {
        IOServiceClose(connection)
    }

    /// 连续读取 PSTR 与 TB0T；任一键失败不会阻断另一个键。
    func readSnapshot() -> SMCSnapshot {
        SMCSnapshot(
            systemPowerWatts: readValue(for: "PSTR"),
            batteryTemperatureCelsius: readValue(for: "TB0T")
        )
    }
}
```

- [x] **Step 4: Implement the two-call read protocol**

Add private methods:

```swift
private extension SMCReader {
    func readValue(for key: String) -> Double? {
        guard let keyCode = keyCode(for: key),
              let value = readKey(keyCode) else {
            return nil
        }

        let bytes = withUnsafeBytes(of: value.bytes) {
            Array($0.prefix(Int(value.keyInfo.dataSize)))
        }
        return SMCValueDecoder.decode(
            dataType: value.keyInfo.dataType,
            bytes: bytes
        )
    }

    func readKey(_ key: UInt32) -> SMCKeyData? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key
        input.data8 = Self.readKeyInfoCommand

        guard call(input: &input, output: &output) == KERN_SUCCESS else {
            return nil
        }

        let keyInfo = output.keyInfo
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = Self.readBytesCommand
        output = SMCKeyData()
        guard call(input: &input, output: &output) == KERN_SUCCESS else {
            return nil
        }

        // 字节读取响应不会重复返回键类型，保留第一次查询的元数据。
        output.keyInfo = keyInfo
        return output
    }

    func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            Self.kernelMethodIndex,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
    }

    func keyCode(for key: String) -> UInt32? {
        let code = SMCValueDecoder.fourCharacterCode(key)
        return code == 0 ? nil : code
    }
}
```

- [x] **Step 5: Wire new files into the application build**

In `build.sh`, add:

```bash
"$SOURCE_DIR/Models/SMCValueDecoder.swift" \
```

after `MetricCalculations.swift`, and:

```bash
"$SOURCE_DIR/Services/SMCReader.swift" \
```

before `HardwareMonitor.swift`.

- [x] **Step 6: Type-check the SMC ABI integration**

Run the same `swiftc` source list as `build.sh`, replacing `-O -o ...` with:

```bash
-warnings-as-errors -typecheck
```

Expected: exit code 0 with no warnings. The final reader must retain the exact ABI structure fields above and contain no SMC write command.

### Task 4: Switch HardwareMonitor to PSTR/TB0T

**Files:**

- Modify: `Pulse/Services/HardwareMonitor.swift`

- [x] **Step 1: Add an injectable optional SMC source**

Inside `HardwareMonitor`, add:

```swift
private let smcReader: SMCReading?

/// 默认使用真实 AppleSMC；注入点让失败和选择策略可独立验证。
init(smcReader: SMCReading? = SMCReader()) {
    self.smcReader = smcReader
}
```

- [x] **Step 2: Read SMC before AppleSmartBattery**

At the start of `getSnapshot()` add:

```swift
let smc = smcReader?.readSnapshot()
```

If `AppleSmartBattery` cannot be opened or its properties fail, return validated SMC values instead of returning two nil values:

```swift
return HardwareSnapshot(
    systemLoadWatts: MetricCalculations.preferredSystemLoadWatts(
        smcWatts: smc?.systemPowerWatts,
        legacyMilliwatts: nil,
        externalConnected: nil
    ),
    batteryTemperatureCelsius: MetricCalculations
        .preferredBatteryTemperatureCelsius(
            smcCelsius: smc?.batteryTemperatureCelsius,
            bmsCentiDegrees: nil
        )
)
```

- [x] **Step 3: Replace direct legacy conversions with source selection**

Read the additional state:

```swift
let externalConnected = parseBool(props["ExternalConnected"])
```

Replace direct power and temperature conversion with:

```swift
// PSTR 是整机主板当前功率；旧 SystemLoad 仅在明确使用电池时安全回退。
let systemLoad = MetricCalculations.preferredSystemLoadWatts(
    smcWatts: smc?.systemPowerWatts,
    legacyMilliwatts: rawSystemLoad,
    externalConnected: externalConnected
)

// TB0T 与 AlDente 的电池温度测点一致，BMS Temperature 仅作真实值回退。
let temperature = MetricCalculations.preferredBatteryTemperatureCelsius(
    smcCelsius: smc?.batteryTemperatureCelsius,
    bmsCentiDegrees: rawTemperature
)
```

Add:

```swift
/// 安全解析 IOKit 布尔值，避免把未知状态误判为未连接电源。
private func parseBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    return nil
}
```

- [x] **Step 4: Run unit tests and production build**

Run:

```bash
./test.sh
./build.sh
```

Expected: all assertions pass and `build/Pulse.app` is produced.

### Task 5: Document definitions and perform live charging verification

**Files:**

- Modify: `README.md`
- Verify: `build/Pulse.app`

- [x] **Step 1: Update metric documentation**

Document these exact definitions:

```markdown
- **系统负载**：优先读取 Apple SMC `PSTR`（Total Board Power），每秒刷新。
  `PowerTelemetryData.SystemLoad` 仅在明确使用电池且 PSTR 不可用时回退，
  避免充电功率被误显示为系统负载。
- **电池温度**：优先读取 Apple SMC `TB0T`，不可用时回退到
  `AppleSmartBattery.Temperature`。
```

Add a compatibility note:

```markdown
> `AppleSMC` 是 macOS 非公开 IOKit 接口。Pulse 只读取传感器，不写入 SMC；
> 该方案面向当前非沙盒独立分发方式，不保证 Mac App Store 审核兼容。
```

- [x] **Step 2: Re-run all deterministic checks**

Run:

```bash
./test.sh
./build.sh
plutil -lint build/Pulse.app/Contents/Info.plist
```

Expected:

- test output reports zero failures;
- build succeeds;
- `plutil` reports `OK`.

- [x] **Step 3: Confirm there are no SMC writes or obsolete direct UI path**

Run:

```bash
rg -n "SMC_CMD_WRITE|writeKey|SystemLoad" Pulse tests README.md
```

Expected:

- no SMC write symbol exists;
- `SystemLoad` appears only in the documented battery-only fallback path and its tests;
- UI receives `HardwareSnapshot.systemLoadWatts`, not a raw registry value.

- [x] **Step 4: Launch and compare while charging**

Launch `build/Pulse.app`, keep AlDente visible, and observe at least eight one-second samples while AC charging.

Acceptance criteria:

- Pulse system load stays in the same physical range as SMC `PSTR` and AlDente;
- the former 70–80 W charging artifact never appears;
- Pulse changes at the one-second heartbeat rather than remaining frozen with `SystemLoad`;
- Pulse battery temperature follows `TB0T`;
- a small instantaneous difference from AlDente is acceptable because sampling moments are not synchronized.

- [x] **Step 5: Record completion without committing**

Update all plan checkboxes, summarize changed files and measured sample range, and explicitly state that no Git commit was performed.

## Execution results

- Pure and integration tests: `68` assertions passed.
- Warnings-as-errors full type-check: exit code `0`.
- Production build and Info.plist validation: passed.
- SMC C ABI: stride `80`, with critical offsets asserted in tests.
- Protocol safety added during review: both SMC calls require IOKit success,
  `output.result == 0`, and an 80-byte response; invalid payload lengths return no value.
- Final live AC samples: selected system power matched `PSTR` for all eight samples
  (`8.252...14.612 W`), and selected battery temperature matched `TB0T` (`34.1 °C`).
- The UI automation service could not attach to the windowless `LSUIElement` app.
  Verification therefore exercised the exact `HardwareMonitor` used by the built app
  and captured its final snapshot against the same injected SMC reads.
- Independent review found no remaining Critical or Important issues.
- No Git commit was performed.
