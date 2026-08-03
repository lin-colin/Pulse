# 电源状态与功耗表现矩阵 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Pulse 菜单栏电源模式与功耗高负载视觉解耦（充电绿闪电、直供插头、放电高耗电双重变色）。

**Architecture:** 扩充 `MetricCalculations` 提供图标形态与解耦颜色计算的纯函数；在 `StatusItemView` 中引入电源连接状态，并依规则自绘制图标与文本。

**Tech Stack:** Swift 5.9, AppKit, IOKit, XCTest.

## Global Constraints

- 严禁把不可用状态伪装为 `0` 或绿色。
- 新增/修改 Swift 逻辑必须附带中文“为什么”注释。
- 不使用 Destructive Git 命令，不破坏用户现有文件。

---

### Task 1: 扩充功耗色彩与图标形态纯函数模型及单元测试

**Files:**
- Modify: `Pulse/Models/MetricCalculations.swift`
- Test: `Tests/MetricCalculationsTests.swift`

**Interfaces:**
- Produces: `MetricCalculations.powerDisplayConfiguration(power:isCharging:isPluggedIn:) -> (symbolName: String, iconColorRole: ColorRole, textColorRole: ColorRole)`

- [ ] **Step 1: Write failing tests in MetricCalculationsTests.swift**

```swift
func testPowerDisplayConfigurationCharging() {
    // 验证充电时：图标为 bolt.fill，颜色恒为绿色；数值高负载时变橙/红
    let configNormal = MetricCalculations.powerDisplayConfiguration(power: 10.0, isCharging: true, isPluggedIn: true)
    XCTAssertEqual(configNormal.symbolName, "bolt.fill")
    XCTAssertEqual(configNormal.iconColorRole, .chargingGreen)
    XCTAssertEqual(configNormal.textColorRole, .normal)

    let configHigh = MetricCalculations.powerDisplayConfiguration(power: 35.0, isCharging: true, isPluggedIn: true)
    XCTAssertEqual(configHigh.symbolName, "bolt.fill")
    XCTAssertEqual(configHigh.iconColorRole, .chargingGreen)
    XCTAssertEqual(configHigh.textColorRole, .redWarning)
}

func testPowerDisplayConfigurationPluggedInPassThrough() {
    // 验证插电直供（未充）时：图标为 powerplug.fill，颜色为默认；数值高负载变橙/红
    let configHigh = MetricCalculations.powerDisplayConfiguration(power: 35.0, isCharging: false, isPluggedIn: true)
    XCTAssertEqual(configHigh.symbolName, "powerplug.fill")
    XCTAssertEqual(configHigh.iconColorRole, .normal)
    XCTAssertEqual(configHigh.textColorRole, .redWarning)
}

func testPowerDisplayConfigurationDischarging() {
    // 验证电池放电时：图标为 bolt.fill；高负载时图标与数值同时变橙/红
    let configHigh = MetricCalculations.powerDisplayConfiguration(power: 35.0, isCharging: false, isPluggedIn: false)
    XCTAssertEqual(configHigh.symbolName, "bolt.fill")
    XCTAssertEqual(configHigh.iconColorRole, .redWarning)
    XCTAssertEqual(configHigh.textColorRole, .redWarning)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `./test.sh`
Expected: FAIL with compilation error for missing `powerDisplayConfiguration`.

- [ ] **Step 3: Implement minimal code in MetricCalculations.swift**

```swift
enum ColorRole {
    case normal
    case chargingGreen
    case orangeWarning
    case redWarning
}

struct PowerDisplayConfig {
    let symbolName: String
    let iconColorRole: ColorRole
    let textColorRole: ColorRole
}

extension MetricCalculations {
    /// 计算功耗图标与颜色的纯函数，解决充电指示与高功耗告警的色彩解耦
    static func powerDisplayConfiguration(
        power: Double?,
        isCharging: Bool,
        isPluggedIn: Bool
    ) -> PowerDisplayConfig {
        let valueRole: ColorRole
        if let power, power >= 30.0 {
            valueRole = .redWarning
        } else if let power, power >= 18.0 {
            valueRole = .orangeWarning
        } else {
            valueRole = .normal
        }

        if isCharging {
            // 为什么：充电时图标必须恒为绿色以明确表达充电状态，不被高功耗红字混淆
            return PowerDisplayConfig(symbolName: "bolt.fill", iconColorRole: .chargingGreen, textColorRole: valueRole)
        } else if isPluggedIn {
            // 为什么：插电直供/停充时切换为插头图标，表达外接交流电无电池电流
            return PowerDisplayConfig(symbolName: "powerplug.fill", iconColorRole: .normal, textColorRole: valueRole)
        } else {
            // 为什么：电池放电时高耗电需图标与数值同时变色，警示剧烈掉电
            return PowerDisplayConfig(symbolName: "bolt.fill", iconColorRole: valueRole, textColorRole: valueRole)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./test.sh`
Expected: PASS all assertions.

---

### Task 2: 在 StatusItemView 与 StatusBarController 中应用电源表现矩阵

**Files:**
- Modify: `Pulse/UI/StatusItemView.swift`
- Modify: `Pulse/UI/StatusBarController.swift`

- [ ] **Step 1: 在 StatusItemView 中引入 isPluggedIn 属性并应用配置**

```swift
// 为什么：需要同时传入 isPluggedIn 以区分插电直供与电池纯放电模式
var isPluggedIn: Bool = false
```

使用 `MetricCalculations.powerDisplayConfiguration` 自绘制第一列功耗图标与文本。

- [ ] **Step 2: 在 StatusBarController 中同步更新 updateDisplay 参数**

```swift
let isPluggedIn = chargeState.contains("已连接电源") || isCharging
customView.isPluggedIn = isPluggedIn
```

- [ ] **Step 3: 执行全套验证**

Run:
```bash
./test.sh
./build.sh
plutil -lint build/Pulse.app/Contents/Info.plist
```

运行 Swift Warnings-as-Errors Typecheck 命令确保零类型警告。
