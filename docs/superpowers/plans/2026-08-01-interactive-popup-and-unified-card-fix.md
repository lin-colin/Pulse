# NSPopUpButton 点击响应与全贯通原厂面板重构实现计划

**Goal:** 彻底解决下拉菜单中 `NSPopUpButton`（刷新间隔）在 `NSMenuItem.view` 内部鼠标点击被拦截无法展开的问题；重构下拉菜单样式为左右完全贯通的 macOS 原厂统一连续面板（Full-Width Continuous Panel），彻底消除左右两条硬生生的灰色边槽（生硬盒中盒感）。

---

## User Review Required

> [!IMPORTANT]
> **两大核心修复点**：
> 1. **点击交互彻底修复**：解决 AppKit 原生 `NSMenu` 跟踪循环拦截 `NSMenuItem.view` 内子控件事件的问题，使 `NSPopUpButton` 点击时能 100% 顺畅展开原厂下拉选择框。
> 2. **视觉面板全贯通**：消除卡片左右空出 10pt 暴露外层灰底的“盒中盒”硬边槽，将背景升级为完全贯通左右、符合 macOS 原厂系统设置规范的统一高质感半透明面板（中间使用淡线分隔）。

---

## Proposed Changes

### Component 1: 事件透传与控件交互组 (Interactive Event Forwarding)

#### [MODIFY] [SettingsControlCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/SettingsControlCardView.swift)
- 实现事件响应透传机制（重写 `hitTest(_:)` / 鼠标按下透传处理），确保落入 `NSPopUpButton` 区域的点击事件不被外层 `NSMenu` 阻断。
- 在点击时通过 `popUpButton.popUpMenu(popUpButton.menu!)` 显式弹出原生选择列表，确保点击 100% 触发展开。

---

### Component 2: 界面全贯通与原厂面板重构 (Unified Full-Width Panel UI)

#### [MODIFY] [MetricsCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/MetricsCardView.swift)
- 将自绘制卡片调整为左右完全贯通（Full-Width Layout），移除两侧硬生的 10pt 外空白，使面板最左/最右直接与菜单边缘无缝衔接。
- 调优深浅模式背景配色，实现柔和高保真的苹果原厂面板背景。

#### [MODIFY] [SettingsControlCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/SettingsControlCardView.swift)
- 同样调整为左右全贯通结构，顶部与 `MetricsCardView` 保持统一的贯通风格。
- 左侧图标（`x: 16pt`）与右侧控件（`rightMargin: 16pt`）维持绝对物理齐平。

#### [MODIFY] [StatusBarController.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/StatusBarController.swift)
- 调优菜单视图编排与高度，使整体圆角与阴影由外层 `NSMenu` 优雅包裹。

---

## Verification Plan

### Automated Tests
- 运行 `./test.sh` 确保 160+ 项断言 100% 跑通。
- 运行 `swiftc -warnings-as-errors -typecheck` 确保全源 0 警告 0 错误。

### Manual Verification
- 使用 `screencapture` 工具抓取更新后的整屏截图。
- 实机验证 `NSPopUpButton` 点击弹出选择框与 `NSSwitch` 开关切换。
