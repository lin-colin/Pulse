# 下拉菜单电源文案与开机自启对齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 精细化下拉菜单电源状态展示文案（包含“已连接电源 (未在充电)”），并重构“开机自动启动”菜单项采用右侧 `已开启 / 已关闭` 状态展示，消除勾选 `✓` 对图标左对齐列的破坏。

**Architecture:** 在 `BatteryMonitor` 中提供纯文案格式化映射；在 `StatusBarController` 中统一配置右对齐制表符（`NSTextTab`），将开机自启的勾选改为右侧文字渲染。

**Tech Stack:** Swift 5.9, AppKit, IOKit, XCTest.

## Global Constraints

- 遵循 A1 菜单展示规则，不侵入改动硬件采样。
- 新增/修改 Swift 逻辑必须附带中文“为什么”注释。
- 不使用 Destructive Git 命令，不破坏用户现有文件。

---

### Task 1: 扩充电源状态精准文案格式化函数与单元测试

**Files:**
- Modify: `Pulse/Services/BatteryMonitor.swift`
- Test: `Tests/MetricCalculationsTests.swift`

**Interfaces:**
- Produces: `BatteryMonitor.powerSourceStateDescription(isCharging:isPluggedIn:) -> String`

- [ ] **Step 1: Write failing tests in MetricCalculationsTests.swift**

```swift
func testPowerSourceStateDescription() {
    // 验证方案 1 措辞：充电中、已连接电源 (未在充电)、使用电池
    XCTAssertEqual(BatteryMonitor.powerSourceStateDescription(isCharging: true, isPluggedIn: true), "正在充电")
    XCTAssertEqual(BatteryMonitor.powerSourceStateDescription(isCharging: false, isPluggedIn: true), "已连接电源 (未在充电)")
    XCTAssertEqual(BatteryMonitor.powerSourceStateDescription(isCharging: false, isPluggedIn: false), "使用电池")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `./test.sh`
Expected: FAIL with compilation error for missing `powerSourceStateDescription`.

- [ ] **Step 3: Implement minimal code in BatteryMonitor.swift**

```swift
extension BatteryMonitor {
    /// 为什么：方案 1 规则要求精细区分外接电源时电池是否正在充电，避免“已连接电源”文案模糊
    public static func powerSourceStateDescription(isCharging: Bool, isPluggedIn: Bool) -> String {
        if isCharging {
            return "正在充电"
        } else if isPluggedIn {
            return "已连接电源 (未在充电)"
        } else {
            return "使用电池"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./test.sh`
Expected: PASS all assertions.

---

### Task 2: 在 StatusBarController 中更新电源文案与开机自启右侧对齐

**Files:**
- Modify: `Pulse/UI/StatusBarController.swift`

- [ ] **Step 1: Update launchAtLoginMenuItem to use tab-aligned text right state instead of left checkmark**

```swift
// 为什么：移除系统 left checkmark 放置 (state = .off)，改为右侧 tab 填充 "已开启/已关闭"，保持所有菜单项 SF Symbols 图标 100% 绝对垂直左对齐
launchAtLoginMenuItem.state = .off
let stateText = isEnabled ? "已开启" : "已关闭"
launchAtLoginMenuItem.attributedTitle = makeTabAlignedAttributedString(
    label: "开机自动启动",
    value: stateText
)
```

- [ ] **Step 2: Update chargeMenuItem in updateDisplay using BatteryMonitor.powerSourceStateDescription**

```swift
let cleanChargeState = BatteryMonitor.powerSourceStateDescription(
    isCharging: isCharging,
    isPluggedIn: isPluggedIn
)
chargeMenuItem.attributedTitle = makeTabAlignedAttributedString(label: "电源状态", value: cleanChargeState)
```

- [ ] **Step 3: Run full verification**

Run:
```bash
./test.sh
./build.sh
plutil -lint build/Pulse.app/Contents/Info.plist
```

运行 Swift Warnings-as-Errors Typecheck 确保零警告。
