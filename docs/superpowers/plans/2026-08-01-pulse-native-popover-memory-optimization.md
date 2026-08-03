# Pulse Native Popover and Memory Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fragile custom `NSMenu` UI with a system-settings-style native popover, guarantee complete 2×2 status-bar rendering, and remove proven high-frequency allocation waste.

**Architecture:** `AppDelegate` produces one `PulseSnapshot` per refresh and sends it to a `StatusBarController`. The controller owns one dynamically sized `StatusItemView` and one persistent transient `NSPopover`; `PopoverContentView` reuses native AppKit controls, while `BatteryMonitor` derives all power state from one IOKit snapshot per refresh.

**Tech Stack:** Swift 5.9, AppKit, ServiceManagement, IOKit, Mach APIs, shell-based Swift test runner.

---

## Constraints

- Add concise Chinese “why” comments to new or materially changed Swift logic.
- Do not add SwiftUI or third-party UI dependencies.
- Do not keep the old custom menu views as fallback code.
- Do not commit or push Git changes.
- Preserve the existing read-only SMC and system-monitoring behavior.

## File Map

- Create `Pulse/Models/PulseSnapshot.swift`: immutable UI snapshot shared by both presentation surfaces.
- Create `Pulse/UI/PopoverContentView.swift`: system-settings-style metric and control groups.
- Create `Pulse/UI/RefreshIntervalControl.swift`: native popup selection plus approved normal/hover backgrounds.
- Create `Pulse/Services/LaunchAtLoginController.swift`: testable boundary around `SMAppService`.
- Modify `Pulse/Models/PulseDefaults.swift`: centralize valid refresh intervals and validation.
- Modify `Pulse/Services/BatteryMonitor.swift`: read and derive power state once per refresh.
- Modify `Pulse/App/AppDelegate.swift`: construct one `PulseSnapshot` and own one validated timer.
- Modify `Pulse/UI/StatusItemView.swift`: reusable native subviews and deterministic intrinsic width.
- Modify `Pulse/UI/StatusBarController.swift`: toggle one transient popover and synchronize status width.
- Modify `tests/MetricCalculationsTests.swift`: replace hard-coded UI assertions with production behavior tests.
- Modify `test.sh`: compile AppKit UI and the new files into the test binary.
- Modify `build.sh`: compile the new files and remove deleted sources.
- Delete `Pulse/UI/MainMenuView.swift`, `Pulse/UI/MetricsCardView.swift`, `Pulse/UI/SettingsControlCardView.swift`, and `Pulse/UI/PopUpSelectView.swift` after migration.

### Task 1: Validate refresh intervals at one shared boundary

**Files:**
- Modify: `Pulse/Models/PulseDefaults.swift`
- Modify: `tests/MetricCalculationsTests.swift`

- [ ] **Step 1: Add failing behavior tests**

Add the calls below to `MetricCalculationsTests.main()`:

```swift
testRefreshIntervalValidation()
```

Add the test:

```swift
/// 为什么：偏好数据可能损坏，菜单和计时器必须共享同一套合法刷新档位。
private static func testRefreshIntervalValidation() {
    expectEqual(Double(PulseDefaults.allowedRefreshIntervals.count), 5, "refresh interval should expose five choices")
    expectEqual(PulseDefaults.validatedRefreshInterval(2), 2, "two seconds should remain valid")
    expectEqual(
        PulseDefaults.validatedRefreshInterval(0),
        PulseDefaults.defaultRefreshInterval,
        "zero should fall back to the shared default"
    )
    expectEqual(
        PulseDefaults.validatedRefreshInterval(4),
        PulseDefaults.defaultRefreshInterval,
        "unsupported values should fall back to the shared default"
    )
    expectEqual(
        PulseDefaults.validatedRefreshInterval(.nan),
        PulseDefaults.defaultRefreshInterval,
        "non-finite values should fall back to the shared default"
    )
}
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `./test.sh`

Expected: compilation fails because `allowedRefreshIntervals` and `validatedRefreshInterval` do not exist.

- [ ] **Step 3: Implement the smallest shared policy**

Replace `PulseDefaults` with:

```swift
import Foundation

/// Pulse 跨组件共享的运行参数，避免菜单、偏好和计时器产生不同理解。
enum PulseDefaults {
    static let defaultRefreshInterval: TimeInterval = 1.0
    static let allowedRefreshIntervals: [TimeInterval] = [1, 2, 3, 5, 10]

    /// 为什么：UserDefaults 不是可信输入，进入计时器前必须归一化到已支持档位。
    static func validatedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        allowedRefreshIntervals.contains(value) ? value : defaultRefreshInterval
    }

    /// DispatchSource 负责即时变化；三十秒重读只用于修复唤醒或事件遗漏后的状态。
    static let memoryPressureResyncInterval: TimeInterval = 30.0
}
```

- [ ] **Step 4: Run the test and confirm GREEN**

Run: `./test.sh`

Expected: all assertions pass.

### Task 2: Collapse battery state to one IOKit snapshot

**Files:**
- Modify: `Pulse/Services/BatteryMonitor.swift`
- Modify: `tests/MetricCalculationsTests.swift`

- [ ] **Step 1: Add failing snapshot-derivation tests**

Add `import IOKit.ps` beside the existing imports in `MetricCalculationsTests.swift`.

Add `testPowerSourceSnapshotDerivation()` to `main()`, then add:

```swift
/// 为什么：单次 IOKit 结果必须派生全部状态，防止一轮刷新重复创建三份系统快照。
private static func testPowerSourceSnapshotDerivation() {
    let charging = BatteryMonitor.snapshot(from: [[
        kIOPSIsChargingKey: true,
        kIOPSPowerSourceStateKey: kIOPSACPowerValue
    ]])
    expectTrue(charging.isCharging, "charging flag should be preserved")
    expectTrue(charging.isPluggedIn, "charging source should be plugged in")
    expectEqual(charging.description, "正在充电", "charging description should be concise")

    let battery = BatteryMonitor.snapshot(from: [[
        kIOPSIsChargingKey: false,
        kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue
    ]])
    expectFalse(battery.isCharging, "battery power should not be charging")
    expectFalse(battery.isPluggedIn, "battery power should not be plugged in")
    expectEqual(battery.description, "使用电池", "battery description should remain truthful")

    let unknown = BatteryMonitor.snapshot(from: [])
    expectEqual(unknown.description, "未知", "an empty source list should remain unknown")
}
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `./test.sh`

Expected: compilation fails because `PowerSourceSnapshot` and `snapshot(from:)` do not exist.

- [ ] **Step 3: Implement one-shot derivation**

Add above `BatteryMonitor`:

```swift
/// 单轮刷新中共享的电源状态，避免 UI 再从本地化字符串反推布尔值。
struct PowerSourceSnapshot {
    let isCharging: Bool
    let isPluggedIn: Bool
    let description: String
}
```

Replace the three public query methods with:

```swift
/// 一次读取并派生全部状态，调用方不得在同一刷新周期重复查询 IOKit。
func getSnapshot() -> PowerSourceSnapshot {
    Self.snapshot(from: fetchPowerSourceDescriptions())
}

/// 为什么：纯函数让真实 IOKit 只负责取数，状态矩阵可以无硬件依赖地完整测试。
static func snapshot(from descriptions: [[String: Any]]) -> PowerSourceSnapshot {
    guard !descriptions.isEmpty else {
        return PowerSourceSnapshot(isCharging: false, isPluggedIn: false, description: "未知")
    }

    let isCharging = descriptions.contains { source in
        (source[kIOPSIsChargingKey] as? Bool)
            ?? (source[kIOPSIsChargingKey] as? NSNumber)?.boolValue
            ?? false
    }
    let isPluggedIn = isCharging || descriptions.contains { source in
        guard let state = source[kIOPSPowerSourceStateKey] as? String else { return false }
        return state == kIOPSACPowerValue || state == "AC Power"
    }
    let isBatteryPower = descriptions.contains { source in
        guard let state = source[kIOPSPowerSourceStateKey] as? String else { return false }
        return state == kIOPSBatteryPowerValue || state == "Battery Power"
    }
    let description: String
    if isCharging {
        description = "正在充电"
    } else if isPluggedIn {
        description = "已连接电源 (未充电)"
    } else if isBatteryPower {
        description = "使用电池"
    } else {
        description = "未知"
    }
    return PowerSourceSnapshot(
        isCharging: isCharging,
        isPluggedIn: isPluggedIn,
        description: description
    )
}
```

Remove `powerSourceState()`, `isCharging()`, and `isPluggedIn()` after all production callers migrate in Task 7.

- [ ] **Step 4: Run the test and confirm GREEN**

Run: `./test.sh`

Expected: all assertions pass and no existing power description test regresses.

### Task 3: Introduce one immutable presentation snapshot

**Files:**
- Create: `Pulse/Models/PulseSnapshot.swift`
- Modify: `test.sh`
- Modify: `build.sh`

- [ ] **Step 1: Create the snapshot type**

```swift
import Foundation

/// 同一刷新时刻的完整展示数据，确保菜单栏与详情面板不会混用不同时刻的值。
struct PulseSnapshot {
    let power: Double?
    let memory: MemorySnapshot
    let temperature: Double?
    let cpuUsage: Double
    let cpuFrequency: Double
    let powerSource: PowerSourceSnapshot
}
```

- [ ] **Step 2: Add the file to both compilation scripts**

Insert immediately after `MemoryMetrics.swift` in both `test.sh` and `build.sh`:

```bash
"$PROJECT_DIR/Pulse/Models/PulseSnapshot.swift" \
```

Use `$SOURCE_DIR` instead of `$PROJECT_DIR/Pulse` in `build.sh`, matching its existing variables.

- [ ] **Step 3: Prove the build scripts include the new type**

Run: `./test.sh && ./build.sh`

Expected: tests pass and `build/Pulse.app/Contents/MacOS/Pulse` is produced.

### Task 4: Replace draw-time resizing with deterministic status-item sizing

**Files:**
- Modify: `Pulse/UI/StatusItemView.swift`
- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `test.sh`

- [ ] **Step 1: Compile the real UI into the test binary**

Add `-framework AppKit -framework ServiceManagement` to `test.sh`, then append these production files before the test file:

```bash
"$PROJECT_DIR/Pulse/UI/StatusItemView.swift" \
```

- [ ] **Step 2: Add a failing dynamic-width test**

Add `testStatusItemWidthTracksLongestValues()` to `main()`, then add:

```swift
/// 为什么：父状态项必须在绘制前获得完整宽度，不能让子视图扩张后被按钮裁切。
private static func testStatusItemWidthTracksLongestValues() {
    let view = StatusItemView(frame: NSRect(x: 0, y: 0, width: 1, height: 22))
    let compact = view.update(
        power: 7.1,
        memoryUsagePercentage: 8,
        memoryPressureLevel: .normal,
        temperature: 32.2,
        cpuUsage: 7,
        isCharging: false,
        isPluggedIn: true
    )
    let expanded = view.update(
        power: 137.8,
        memoryUsagePercentage: 100,
        memoryPressureLevel: .critical,
        temperature: 102.2,
        cpuUsage: 100,
        isCharging: false,
        isPluggedIn: false
    )
    expectTrue(expanded > compact, "long values must increase required status-item width")
    expectEqual(expanded, view.intrinsicContentSize.width, "intrinsic width must match the reported width")
}
```

- [ ] **Step 3: Run the test and confirm RED**

Run: `./test.sh`

Expected: compilation fails because `StatusItemView.update(...)` does not exist.

- [ ] **Step 4: Refactor `StatusItemView` to persistent native subviews**

Replace draw-time frame mutation with four persistent icon views and four persistent labels. The key public boundary must be:

```swift
/// 更新既有控件并返回父 NSStatusItem 必须采用的完整宽度。
@discardableResult
func update(
    power: Double?,
    memoryUsagePercentage: Double?,
    memoryPressureLevel: MemoryPressureLevel,
    temperature: Double?,
    cpuUsage: Double,
    isCharging: Bool,
    isPluggedIn: Bool
) -> CGFloat {
    powerLabel.stringValue = MetricCalculations.formatted(power, decimals: 1, suffix: "W")
    temperatureLabel.stringValue = MetricCalculations.formatted(temperature, decimals: 1, suffix: "°C")
    memoryLabel.stringValue = MetricCalculations.formatted(memoryUsagePercentage, decimals: 0, suffix: "%")
    cpuLabel.stringValue = MetricCalculations.formatted(cpuUsage, decimals: 0, suffix: "%")
    updateColors(
        power: power,
        memoryPressureLevel: memoryPressureLevel,
        temperature: temperature,
        cpuUsage: cpuUsage,
        isCharging: isCharging,
        isPluggedIn: isPluggedIn
    )
    invalidateIntrinsicContentSize()
    needsLayout = true
    return intrinsicContentSize.width
}
```

Use reusable helpers:

```swift
private func makeLabel() -> NSTextField {
    let label = NSTextField(labelWithString: "—")
    label.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    label.lineBreakMode = .byClipping
    return label
}

private func makeIcon(_ symbolName: String) -> NSImageView {
    let imageView = NSImageView()
    imageView.image = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: nil
    )?.withSymbolConfiguration(.init(pointSize: 8.5, weight: .semibold))
    imageView.symbolConfiguration = .init(pointSize: 8.5, weight: .semibold)
    return imageView
}
```

Compute the intrinsic width without mutating `frame` inside `draw(_:)`:

```swift
override var intrinsicContentSize: NSSize {
    let firstColumn = max(powerLabel.intrinsicContentSize.width, temperatureLabel.intrinsicContentSize.width)
    let secondColumn = max(memoryLabel.intrinsicContentSize.width, cpuLabel.intrinsicContentSize.width)
    let width = horizontalPadding * 2
        + iconSize + iconTextGap + firstColumn
        + columnGap
        + iconSize + iconTextGap + secondColumn
    return NSSize(width: ceil(width), height: 22)
}
```

Lay out the eight existing subviews in `layout()` using the same measured column widths. Set colors with `NSImageView.contentTintColor` and `NSTextField.textColor`; do not retain `NSImage.tinted(with:)`.

- [ ] **Step 5: Run the test and confirm GREEN**

Run: `./test.sh`

Expected: all assertions pass and the expanded width exceeds the compact width.

### Task 5: Build the system-settings-style popover content

**Files:**
- Create: `Pulse/UI/PopoverContentView.swift`
- Create: `Pulse/UI/RefreshIntervalControl.swift`
- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `test.sh`
- Modify: `build.sh`

- [ ] **Step 1: Add the source to both compilation scripts**

Append before `StatusBarController.swift`:

```bash
"$PROJECT_DIR/Pulse/UI/PopoverContentView.swift" \
```

Use `$SOURCE_DIR` in `build.sh`.

- [ ] **Step 2: Add failing interaction tests**

Add `testPopoverRefreshSelectionAndHover()` to `main()`, then add:

```swift
/// 为什么：测试必须触达真实原生控件，不能继续用硬编码常量冒充 UI 覆盖。
private static func testPopoverRefreshSelectionAndHover() {
    let control = RefreshIntervalControl(frame: NSRect(x: 0, y: 0, width: 90, height: 32))
    var received: TimeInterval?
    control.onIntervalChanged = { received = $0 }
    control.select(interval: 5, notify: true)
    expectEqual(received, 5, "native popup selection should forward the represented interval")
    expectFalse(control.isHovered, "refresh control should start unhovered")
    control.setHovered(true)
    expectTrue(control.isHovered, "hover entry should update only the presentation state")
    control.setHovered(false)
    expectFalse(control.isHovered, "hover exit should restore the normal state")
}
```

- [ ] **Step 3: Run the test and confirm RED**

Run: `./test.sh`

Expected: compilation fails because `PopoverContentView` does not exist.

- [ ] **Step 4: Implement the native content hierarchy**

Create a 340 pt wide `NSVisualEffectView` containing:

```swift
final class PopoverContentView: NSVisualEffectView {
    var onRefreshIntervalChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggled: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    private var valueLabels: [MetricKey: NSTextField] = [:]
    private let refreshControl = RefreshIntervalControl(frame: .zero)
    private let launchSwitch = NSSwitch(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        buildViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        buildViewHierarchy()
    }
}
```

Define the six keys in the same file:

```swift
private enum MetricKey: CaseIterable {
    case power, temperature, memoryUsage, memoryPressure, cpu, powerSource
}
```

Build each metric row from persistent native controls:

```swift
private func makeMetricRow(
    symbol: String,
    title: String,
    key: MetricKey
) -> NSView {
    let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage())
    icon.contentTintColor = .labelColor
    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 13)
    let valueLabel = NSTextField(labelWithString: "—")
    valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    valueLabel.alignment = .right
    valueLabels[key] = valueLabel
    return makeRow(icon: icon, title: titleLabel, trailing: valueLabel, height: 30)
}
```

Use `NSBox` with `boxType = .custom`, `cornerRadius = 12`, zero border width, and `fillColor = .controlBackgroundColor` for each group. Add one-pixel separators only between rows. The control group uses 44 pt rows, and the quit button is a borderless `NSButton` with `keyEquivalent = "q"` and `.command` modifier mask.

Expose a single data update method:

```swift
func update(snapshot: PulseSnapshot) {
    valueLabels[.power]?.stringValue = MetricCalculations.formatted(snapshot.power, decimals: 1, suffix: "W")
    valueLabels[.temperature]?.stringValue = MetricCalculations.formatted(snapshot.temperature, decimals: 1, suffix: "°C")
    valueLabels[.memoryUsage]?.stringValue = memoryUsageText(snapshot.memory)
    valueLabels[.memoryPressure]?.stringValue = snapshot.memory.pressureLevel.displayName
    valueLabels[.cpu]?.stringValue = cpuText(snapshot.cpuUsage, frequency: snapshot.cpuFrequency)
    valueLabels[.powerSource]?.stringValue = snapshot.powerSource.description
}
```

- [ ] **Step 5: Implement the native popup with two hover states**

In the same file, define:

```swift
final class RefreshIntervalControl: NSView {
    var onIntervalChanged: ((TimeInterval) -> Void)?
    private(set) var isHovered = false
    private let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        PulseDefaults.allowedRefreshIntervals.forEach { interval in
            let item = NSMenuItem(
                title: Self.title(for: interval),
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = interval
            popUpButton.menu?.addItem(item)
        }
        popUpButton.isBordered = false
        popUpButton.target = self
        popUpButton.action = #selector(selectionChanged(_:))
        addSubview(popUpButton)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaReference = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    @objc private func selectionChanged(_ sender: NSPopUpButton) {
        guard let interval = sender.selectedItem?.representedObject as? TimeInterval else { return }
        onIntervalChanged?(interval)
    }

    /// 为什么：测试和鼠标事件共用同一状态入口，避免出现只在测试中成立的伪路径。
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    /// 选择真实菜单项并按需发送与用户操作相同的回调。
    func select(interval: TimeInterval, notify: Bool) {
        guard let item = popUpButton.itemArray.first(where: {
            ($0.representedObject as? TimeInterval) == interval
        }) else { return }
        popUpButton.select(item)
        if notify { selectionChanged(popUpButton) }
    }

    private static func title(for interval: TimeInterval) -> String {
        switch interval {
        case 1: return "1 秒 (高频)"
        case 3: return "3 秒 (推荐)"
        case 10: return "10 秒 (省电)"
        default: return "\(Int(interval)) 秒"
        }
    }
}
```

In `draw(_:)`, draw a full rounded gray rect only when hovered; otherwise draw only the 30 pt trailing arrow circle. Do not override `mouseDown` or create another `NSMenu`.

The test instantiates `RefreshIntervalControl` directly and calls the same internal `select(interval:notify:)` and `setHovered(_:)` paths used by production state synchronization and mouse events; do not add test-only methods to `PopoverContentView`.

- [ ] **Step 6: Run the test and confirm GREEN**

Run: `./test.sh`

Expected: all assertions pass, including real selection callback and hover transitions.

### Task 6: Isolate launch-at-login state and failure handling

**Files:**
- Create: `Pulse/Services/LaunchAtLoginController.swift`
- Modify: `build.sh`
- Modify: `test.sh`
- Modify: `tests/MetricCalculationsTests.swift`

- [ ] **Step 1: Add a failing controller-contract test**

Add `testLaunchAtLoginFailurePreservesActualState()` to `main()`, then add:

```swift
/// 为什么：注册失败时 UI 必须回到系统真实状态，不能保留用户期望状态冒充成功。
private static func testLaunchAtLoginFailurePreservesActualState() {
    final class FailingLaunchController: LaunchAtLoginControlling {
        var isEnabled = false
        func setEnabled(_ enabled: Bool) throws { throw LaunchAtLoginError.operationFailed }
    }
    let controller = FailingLaunchController()
    do {
        try controller.setEnabled(true)
        expectTrue(false, "a failing controller must throw")
    } catch {
        expectFalse(controller.isEnabled, "failed registration must preserve the actual disabled state")
    }
}
```

- [ ] **Step 2: Run the test and confirm RED**

Run: `./test.sh`

Expected: compilation fails because `LaunchAtLoginControlling` does not exist.

- [ ] **Step 3: Implement the ServiceManagement adapter**

```swift
import Foundation
import ServiceManagement

enum LaunchAtLoginError: Error {
    case operationFailed
}

protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// 为什么：隔离系统服务后，UI 能在失败时重新读取真实状态并可进行确定性测试。
final class LaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { throw LaunchAtLoginError.operationFailed }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            throw LaunchAtLoginError.operationFailed
        }
    }
}
```

Add the new source before `BatteryMonitor.swift` in both compilation scripts.

- [ ] **Step 4: Run the test and confirm GREEN**

Run: `./test.sh`

Expected: all assertions pass.

### Task 7: Replace `NSMenu` orchestration with one transient popover

**Files:**
- Modify: `Pulse/UI/StatusBarController.swift`
- Modify: `Pulse/App/AppDelegate.swift`
- Modify: `test.sh`

- [ ] **Step 1: Rewrite the controller around the approved boundary**

The controller initializer must accept the launch service for testing and production:

```swift
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let customView: StatusItemView
    private let popover = NSPopover()
    private let contentView = PopoverContentView(frame: NSRect(x: 0, y: 0, width: 340, height: 320))
    private let launchController: LaunchAtLoginControlling
    var onRefreshIntervalChanged: ((TimeInterval) -> Void)?

    init(launchController: LaunchAtLoginControlling = LaunchAtLoginController()) {
        self.launchController = launchController
        statusItem = NSStatusBar.system.statusItem(withLength: 80)
        customView = StatusItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        super.init()
        configureStatusButton()
        configurePopover()
        bindActions()
    }
}
```

Configure the button without forcing its frame:

```swift
private func configureStatusButton() {
    guard let button = statusItem.button else { return }
    customView.translatesAutoresizingMaskIntoConstraints = false
    button.addSubview(customView)
    NSLayoutConstraint.activate([
        customView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        customView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        customView.topAnchor.constraint(equalTo: button.topAnchor),
        customView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
    ])
    button.target = self
    button.action = #selector(togglePopover(_:))
    button.sendAction(on: [.leftMouseUp])
}
```

Configure transient popover behavior:

```swift
private func configurePopover() {
    let controller = NSViewController()
    controller.view = contentView
    controller.preferredContentSize = NSSize(width: 340, height: 320)
    popover.contentViewController = controller
    popover.contentSize = controller.preferredContentSize
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
}
```

Bind native actions and always restore launch state after an operation:

```swift
private func bindActions() {
    contentView.onRefreshIntervalChanged = { [weak self] interval in
        self?.onRefreshIntervalChanged?(interval)
    }
    contentView.onLaunchAtLoginToggled = { [weak self] requestedState in
        guard let self else { return }
        do { try self.launchController.setEnabled(requestedState) }
        catch { NSLog("Pulse 开机启动设置失败: %@", String(describing: error)) }
        self.contentView.setLaunchAtLoginEnabled(self.launchController.isEnabled)
    }
    contentView.onQuit = { NSApplication.shared.terminate(nil) }
    contentView.setLaunchAtLoginEnabled(launchController.isEnabled)
}
```

Use one snapshot update and synchronize the parent width before layout:

```swift
func update(snapshot: PulseSnapshot) {
    let requiredWidth = customView.update(
        power: snapshot.power,
        memoryUsagePercentage: snapshot.memory.usagePercentage,
        memoryPressureLevel: snapshot.memory.pressureLevel,
        temperature: snapshot.temperature,
        cpuUsage: snapshot.cpuUsage,
        isCharging: snapshot.powerSource.isCharging,
        isPluggedIn: snapshot.powerSource.isPluggedIn
    )
    statusItem.length = requiredWidth
    contentView.update(snapshot: snapshot)
}
```

- [ ] **Step 2: Migrate `AppDelegate` to one validated snapshot**

Use validated preferences at startup and on change:

```swift
let storedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
startTimer(interval: PulseDefaults.validatedRefreshInterval(storedInterval))
```

Construct and send one snapshot:

```swift
private func collectAndDisplayMetrics() {
    let hardware = hardwareMonitor.getSnapshot()
    let memory = systemMonitor.getMemorySnapshot()
    let cpuUsage = systemMonitor.getCPUUsage()
    let cpuFrequency = systemMonitor.getCPUFrequency()
    let powerSource = batteryMonitor.getSnapshot()
    let snapshot = PulseSnapshot(
        power: hardware.systemLoadWatts,
        memory: memory,
        temperature: hardware.batteryTemperatureCelsius,
        cpuUsage: cpuUsage,
        cpuFrequency: cpuFrequency,
        powerSource: powerSource
    )

    DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.statusBar.update(snapshot: snapshot)
        self.isRefreshInProgress = false
    }
}
```

Validate and persist changed intervals before restarting the timer:

```swift
statusBar.onRefreshIntervalChanged = { [weak self] requestedInterval in
    let interval = PulseDefaults.validatedRefreshInterval(requestedInterval)
    UserDefaults.standard.set(interval, forKey: "refreshInterval")
    self?.startTimer(interval: interval)
}
```

- [ ] **Step 3: Compile the complete migrated graph**

Add `AppDelegate.swift`, `StatusBarController.swift`, and all their new dependencies to `test.sh` without adding `main.swift`.

Run: `./test.sh && ./build.sh`

Expected: tests pass and the app builds with the popover controller.

### Task 8: Remove dead UI and false tests

**Files:**
- Delete: `Pulse/UI/MainMenuView.swift`
- Delete: `Pulse/UI/MetricsCardView.swift`
- Delete: `Pulse/UI/SettingsControlCardView.swift`
- Delete: `Pulse/UI/PopUpSelectView.swift`
- Modify: `build.sh`
- Modify: `tests/MetricCalculationsTests.swift`

- [ ] **Step 1: Remove obsolete build references and files**

Remove the four old source paths from `build.sh`, then delete the four files. Confirm no production reference remains:

Run: `rg -n "MainMenuView|MetricsCardView|SettingsControlCardView|PopUpSelectView|tinted\(with" Pulse build.sh`

Expected: no matches.

- [ ] **Step 2: Remove non-behavior UI assertions**

Delete these calls and their methods from `MetricCalculationsTests.swift`:

```swift
testMetricsCardViewLabelFormatting()
testMetricsCardViewAlignmentBoundary()
testSettingsControlCardFormatting()
testNestedShellCardLayout()
testCheckmarkPopUpFormatting()
```

Keep the new tests that instantiate real production types.

- [ ] **Step 3: Run the complete regression suite**

Run: `./test.sh`

Expected: zero failures. The total assertion count may be lower than 165 because fake assertions were removed, but every remaining UI assertion touches production code.

### Task 9: Static verification and code-quality audit

**Files:**
- Modify only files implicated by verification failures.

- [ ] **Step 1: Run warnings-as-errors type checking**

Run the same source list as `build.sh`, replacing `-O -o ...` with:

```bash
swiftc -warnings-as-errors -typecheck \
  -framework AppKit \
  -framework IOKit \
  -framework ServiceManagement \
  -target arm64-apple-macos13.0 \
  Pulse/App/main.swift \
  Pulse/App/AppDelegate.swift \
  Pulse/Models/*.swift \
  Pulse/UI/*.swift \
  Pulse/Services/*.swift
```

Expected: exit code 0 with no warnings.

- [ ] **Step 2: Run tests and package build from a clean build directory**

Run: `./test.sh && ./build.sh && plutil -lint build/Pulse.app/Contents/Info.plist`

Expected: tests pass, build exits 0, and plist reports `OK`.

- [ ] **Step 3: Audit dead and duplicate code**

Run:

```bash
rg -n "extension NSImage|powerSourceState\(|isCharging\(|isPluggedIn\(|NSMenuItem\(\)|mouseDown\(" Pulse
```

Expected: no duplicate image tint extension, no legacy repeated battery queries, and no custom menu-item view or custom popup `mouseDown` path.

### Task 10: Real UI and memory verification

**Files:**
- Record results in: `docs/superpowers/specs/2026-08-01-pulse-native-popover-memory-optimization-design.md`

- [ ] **Step 1: Launch the newly built app and verify the approved interactions**

Start `build/Pulse.app`, then verify:

1. Normal and long 2×2 values are not clipped.
2. Clicking the status item opens a 340 pt transient popover.
3. The refresh control shows arrow-circle normal state and full rounded hover state.
4. All five refresh choices open and update the displayed selection.
5. The launch-at-login switch reflects the system result after each action.
6. Clicking outside closes the popover; `⌘Q` exits Pulse.

- [ ] **Step 2: Capture memory checkpoints**

At minute 5 and minute 20 with the popover closed, run:

```bash
PULSE_PROFILE_PID="$(pgrep -n -f '/Pulse.app/Contents/MacOS/Pulse')"
vmmap -summary "$PULSE_PROFILE_PID"
```

Expected: minute-20 physical footprint grows by no more than 2 MB relative to minute 5 and does not exceed the same-environment 26.4 MB baseline after caches stabilize.

- [ ] **Step 3: Exercise popover lifecycle and check leaks**

Open and close the popover at least 20 times, wait 60 seconds, then run:

```bash
PULSE_PROFILE_PID="$(pgrep -n -f '/Pulse.app/Contents/MacOS/Pulse')"
leaks "$PULSE_PROFILE_PID"
```

Expected: no leaked object path contains a Pulse-owned Swift type. System AppIntents/XPC cycles may remain and must be reported separately rather than attributed to Pulse.

- [ ] **Step 4: Append measured evidence to the design document**

Add a dated `Implementation Verification` section that records the exact assertion count printed by `./test.sh`, the exact minute-5 and minute-20 physical-footprint lines from `vmmap`, the exact count of Pulse-owned leak paths, and the result of each manual UI check. Do not write estimated values or leave empty fields.
