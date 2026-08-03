# Pulse 下拉菜单 Mac 极致体验与视觉重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 落地 Pulse 下拉菜单 5 大视觉与交互缺陷重构（拓宽面板留白呼吸感、规范“内存使用 14.07 GB”空格格式、为开机自启增加 `已开启 ✓` 可切换暗示、在刷新间隔子菜单加入 `推荐/省电` 建议提示）。

**Architecture:** 在 `StatusBarController` 中调整 `NSTextTab` 位置至 `235pt`，扩充右对齐字符串格式化逻辑；更新 `StatusBarController` 的开机自启状态描述与刷新间隔子菜单展示；扩充单元测试与 screencapture 验证。

**Tech Stack:** Swift 5.9, AppKit, IOKit, XCTest.

## Global Constraints

- 遵循 A1 菜单展示规则，不侵入改动硬件采样。
- 新增/修改 Swift 逻辑必须附带中文“为什么”注释。
- 不使用 Destructive Git 命令，不破坏用户现有文件。

---

### Task 1: 拓宽制表符留白、规范内存空格与重构开机自启交互暗示

**Files:**
- Modify: `Pulse/UI/StatusBarController.swift`
- Test: `Tests/MetricCalculationsTests.swift`

**Interfaces:**
- Consumes: `StatusBarController.makeTabAlignedAttributedString(label:value:)`
- Produces: 具有 235pt 宽度留白与 `已开启 ✓` 交互暗示的菜单列表

- [ ] **Step 1: Write failing tests in MetricCalculationsTests.swift**

```swift
func testFormattedMemoryUsageText() {
    // 验证内存使用格式化输出必须包含空格: "内存使用 14.07 GB (59%)"
    let formatted = MetricCalculations.formattedMemoryUsage(usedBytes: 14_070_000_000, totalBytes: 24_000_000_000, percentage: 59)
    XCTAssertTrue(formatted.contains("内存使用 14.07 GB"), "内存使用与数值之间必须包含空格分隔")
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `./test.sh`
Expected: FAIL with compilation error for missing `formattedMemoryUsage`.

- [ ] **Step 3: Implement minimal code in MetricCalculations.swift & StatusBarController.swift**

1. 在 `MetricCalculations.swift` 中增加规范内存文本方法：
```swift
// 为什么：解决“内存使用14.07 GB”粘连问题，在汉字与数字间引入呼吸空格
static func formattedMemoryUsage(usedGB: Double?, totalGB: Double?, percentage: Double?) -> String
```

2. 在 `StatusBarController.swift` 中调整 `makeTabAlignedAttributedString`：
```swift
// 为什么：将 tabStops 位置由 190pt 扩至 235pt，为下拉菜单提供 30px 的高级留白呼吸空间
paragraphStyle.tabStops = [NSTextTab(textAlignment: .right, location: 235)]
```

3. 在 `StatusBarController.swift` 的 `updateLaunchAtLoginMenuState` 中：
```swift
// 为什么：使用 "已开启 ✓" / "已关闭" 明确告知用户这是一个可点击切换的开关，避免误以为是只读状态展示
let stateText = isEnabled ? "已开启  ✓" : "已关闭"
```

- [ ] **Step 4: Run tests to verify pass**

Run: `./test.sh`
Expected: PASS all assertions.

---

### Task 2: 在刷新间隔子菜单中加入直观建议提示并完成全套构建验证

**Files:**
- Modify: `Pulse/UI/StatusBarController.swift`

- [ ] **Step 1: Update setupRefreshIntervalSubmenu with intuition suggestions**

```swift
// 为什么：为用户提供明确的 CPU 与续航建议提示，增强选择的直观性
private func suggestionLabel(for interval: TimeInterval) -> String {
    switch interval {
    case 1.0: return "1 秒 (高频)"
    case 3.0: return "3 秒 (推荐)"
    case 10.0: return "10 秒 (省电)"
    default: return "\(Int(interval)) 秒"
    }
}
```

- [ ] **Step 2: Run full verification suite**

Run:
```bash
./test.sh
./build.sh
plutil -lint build/Pulse.app/Contents/Info.plist
```

运行 Swift Warnings-as-Errors Typecheck 确保零警告。

- [ ] **Step 3: screencapture 屏幕物理截图验证**

使用 `screencapture` 截取菜单实拍并进行物理验证。
