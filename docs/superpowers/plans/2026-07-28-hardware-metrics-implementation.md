# Pulse Hardware Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fabricated or misleading power, temperature, and memory values with validated macOS metrics and explicit unavailable states.

**Architecture:** Pure conversion and parsing rules live in `MetricCalculations` and are tested without AppKit or IOKit. `HardwareMonitor` creates one optional-valued snapshot per refresh, while `SystemMonitor` reads and caches the system `memory_pressure` result. UI layers accept optional metrics and render unavailable values as `—`.

**Tech Stack:** Swift 5.9+, Foundation, AppKit, IOKit, Darwin, macOS `/usr/bin/memory_pressure`, shell build scripts.

**Git policy:** Do not create commits, tags, or branches.

---

### Task 1: Add failing metric calculation tests

**Files:**
- Create: `tests/MetricCalculationsTests.swift`
- Create: `test.sh`
- Test: `tests/MetricCalculationsTests.swift`

- [x] **Step 1: Create a standalone Swift test executable**

The test program must exercise these wished-for APIs before they exist:

```swift
MetricCalculations.systemLoadWatts(fromMilliwatts:)
MetricCalculations.batteryTemperatureCelsius(fromCentiDegrees:)
MetricCalculations.normalizedMemoryPressure(from:)
MetricCalculations.formatted(_:decimals:suffix:)
```

It must assert:

```swift
5270 -> 5.27 W
0 -> 0 W
-1 and infinity -> nil
3100 -> 31 °C
-2000 and 10000 -> valid boundary temperatures
-2001 and 10001 -> nil
"System-wide memory free percentage: 91%" -> 9
free percentages 0 and 100 -> pressures 100 and 0
missing, nonnumeric, and out-of-range free percentages -> nil
nil formatted value -> "—"
5.27 formatted with one decimal and W suffix -> "5.3 W"
```

- [x] **Step 2: Add a repeatable test runner**

`test.sh` must compile the production calculation file with the standalone tests:

```bash
swiftc \
  -o "${TMPDIR:-/tmp}/pulse-metric-tests" \
  Pulse/Models/MetricCalculations.swift \
  tests/MetricCalculationsTests.swift
"${TMPDIR:-/tmp}/pulse-metric-tests"
```

- [x] **Step 3: Run the tests and verify RED**

Run:

```bash
./test.sh
```

Expected: compilation fails because `Pulse/Models/MetricCalculations.swift` and `MetricCalculations` do not exist.

### Task 2: Implement pure metric rules

**Files:**
- Create: `Pulse/Models/MetricCalculations.swift`
- Test: `tests/MetricCalculationsTests.swift`

- [x] **Step 1: Add the minimal tested implementation**

Create an internal namespace with:

```swift
enum MetricCalculations {
    static func systemLoadWatts(fromMilliwatts rawValue: Double?) -> Double?
    static func batteryTemperatureCelsius(fromCentiDegrees rawValue: Double?) -> Double?
    static func normalizedMemoryPressure(from output: String) -> Double?
    static func formatted(_ value: Double?, decimals: Int, suffix: String) -> String
}
```

Rules:

- Accept system load only when finite and nonnegative, then divide by `1000`.
- Accept battery temperature only when finite and its converted value is in `-20...100`.
- Match exactly one line containing `System-wide memory free percentage: N%`; accept only `0...100`, then return `100 - N`.
- Return `—` for nil formatted values; otherwise use fixed decimal places and add the suffix separated by one space.
- Add comments explaining units, validity checks, and why the memory percentage is normalized.

- [x] **Step 2: Run the tests and verify GREEN**

Run:

```bash
./test.sh
```

Expected: all assertions pass and the process exits with status 0.

### Task 3: Replace the metric data sources

**Files:**
- Modify: `Pulse/Services/HardwareMonitor.swift`
- Modify: `Pulse/Services/SystemMonitor.swift`
- Modify: `Pulse/App/AppDelegate.swift`
- Modify: `build.sh`
- Test: `tests/MetricCalculationsTests.swift`

- [x] **Step 1: Replace separate hardware reads with one snapshot**

Add:

```swift
struct HardwareSnapshot {
    let systemLoadWatts: Double?
    let batteryTemperatureCelsius: Double?
}
```

Replace `getSystemPower()` and `getBatteryTemperature()` with:

```swift
func getSnapshot() -> HardwareSnapshot
```

The method must:

- Read `AppleSmartBattery` properties once.
- Extract `PowerTelemetryData.SystemLoad`.
- Extract physical `Temperature`.
- Pass both values through `MetricCalculations`.
- Return both values as nil when the service or property read fails.
- Remove current/voltage multiplication, adapter formulas, compensation constants, and fabricated fallback values.
- Preserve comments that state the source fields and units.

- [x] **Step 2: Replace the memory usage formula**

Change `getMemoryPressure()` to return `Double?`. Add a five-second cache:

```swift
private var cachedMemoryPressure: Double?
private var memoryPressureReadAt: Date?
private let memoryPressureCacheDuration: TimeInterval = 5
```

On cache expiry:

- Execute `/usr/bin/memory_pressure` with argument `-Q` using `Process`.
- Capture standard output with `Pipe`.
- Require termination status 0.
- Decode UTF-8 and call `MetricCalculations.normalizedMemoryPressure(from:)`.
- Cache only valid results.
- Return nil on launch, exit, decoding, or parsing failure.
- Add comments explaining that this normalized value does not claim to reproduce Activity Monitor’s private graph algorithm.

- [x] **Step 3: Update application refresh flow**

In `AppDelegate.refreshData()`:

```swift
let hardware = hardwareMonitor.getSnapshot()
let memPressure = systemMonitor.getMemoryPressure()
```

Pass the optional snapshot values directly to the UI. Change the default interval fallback from `3.0` to `1.0`.

- [x] **Step 4: Include the calculation model in production builds**

Add this source before the services in `build.sh`:

```bash
"$SOURCE_DIR/Models/MetricCalculations.swift"
```

- [x] **Step 5: Re-run calculation tests**

Run:

```bash
./test.sh
```

Expected: all calculation tests still pass.

### Task 4: Render unavailable values honestly

**Files:**
- Modify: `Pulse/UI/StatusBarController.swift`
- Modify: `Pulse/UI/StatusItemView.swift`
- Test: `tests/MetricCalculationsTests.swift`

- [x] **Step 1: Change UI metric types to optionals**

Change power, temperature, and memory pressure parameters and stored properties from `Double` to `Double?`. Initialize them as nil.

- [x] **Step 2: Use shared formatting**

Use:

```swift
MetricCalculations.formatted(power, decimals: 1, suffix: "W")
MetricCalculations.formatted(temperature, decimals: 1, suffix: "°C")
MetricCalculations.formatted(memPressure, decimals: 0, suffix: "%")
```

Use the same strings for width calculations, status-bar drawing, and menu values. Rename the menu label from `系统功耗` to `系统负载`.

- [x] **Step 3: Guard color thresholds**

Apply threshold colors only when a value exists:

```swift
if let temperature, temperature >= 45 { ... }
if let memPressure, memPressure >= 75 { ... }
```

Use orange for normalized memory pressure at `50...74` and red at `75...100`; comments must identify these as Pulse display thresholds, not Activity Monitor thresholds.

- [x] **Step 4: Run tests**

Run:

```bash
./test.sh
```

Expected: all assertions pass.

### Task 5: Build and perform same-machine verification

**Files:**
- Modify only if verification exposes a root-cause defect.

- [x] **Step 1: Build the application**

Run:

```bash
./build.sh
```

Expected: `build/Pulse.app/Contents/MacOS/Pulse` is created and compilation exits with status 0.

- [x] **Step 2: Verify forbidden formulas are gone**

Run:

```bash
rg -n '0\\.93|max\\(1\\.5|return 5\\.0|InstantAmperage|VirtualTemperature' Pulse
```

Expected: no matches in production metric code.

- [x] **Step 3: Verify live source values**

Read the current `AppleSmartBattery` dictionary and compare:

```text
Pulse system load = PowerTelemetryData.SystemLoad / 1000
Pulse battery temperature = Temperature / 100
Pulse memory pressure = 100 - memory_pressure -Q free percentage
```

Expected: values agree within UI rounding precision.

- [x] **Step 4: Verify source and documentation consistency**

Run:

```bash
rg -n '系统功耗|系统负载|内存压力|VirtualTemperature|SystemLoad|Temperature' Pulse README.md
```

Expected: UI uses `系统负载`; implementation comments identify the exact sources; no claim says the Activity Monitor private algorithm is exactly reproduced.

- [x] **Step 5: Report actual verification evidence**

Report:

- Test pass count.
- Build exit status.
- Current raw and converted metric values.
- Any remaining limitations, especially driver-controlled update cadence.
- Confirmation that no Git commit was created.
