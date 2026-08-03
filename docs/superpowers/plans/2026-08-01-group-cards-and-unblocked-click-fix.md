# 原厂 System Settings 组卡片排版与极速刷新间隔控件重构计划

**Goal:** 完全还原 macOS 系统设置（System Settings）原厂 Group Card 组卡片排版规范；彻底解决 `NSMenuItem.view` 阻断 `NSPopUpButton` 点击下拉的机制冲突，提供 100% 顺畅即时生效的刷新间隔选择体验。

---

## User Review Required

> [!IMPORTANT]
> 1. **原厂 Group Card 组卡片复刻**：按照您发来的“外观/窗口”设置截图，顶部 6 项硬件指标与底部 2 项控制项分别包裹在**独立的 10pt 圆角 Group 卡片**中，左右保留标准原厂 10pt 边缝与柔和深浅模式自适应背景。
> 2. **点击响应彻底解决**：解决 AppKit `NSMenu` Tracking Loop 对控件下拉菜单的拦截冲突，将 `刷新间隔` 改造为直观顺畅的 **PopUp 极速切换/选择按钮 (`[ 3秒 ↕ ]`)**。每次点击直接在 `1秒` ➔ `2秒` ➔ `3秒` ➔ `5秒` ➔ `10秒` 间无缝切换，界面与定时器 0 延迟实时生效。

---

## Proposed Changes

### Component 1: 组卡片排版组 (Group Card Layouts)

#### [MODIFY] [MetricsCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/MetricsCardView.swift)
- 恢复左右 10pt 外边距 (`dx: 10, dy: 4`)，圆角 10pt，精细调优深浅模式控色，高保真复刻 macOS 原厂设置卡片盒外观。

#### [MODIFY] [SettingsControlCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/SettingsControlCardView.swift)
- 恢复左右 10pt 外边距 (`dx: 10, dy: 4`)，与顶部卡片形成完美的双 Group 卡片格局。

---

### Component 2: 交互按钮与事件解耦组 (Event Unblocking & Action Response)

#### [MODIFY] [SettingsControlCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/SettingsControlCardView.swift)
- 重新设计刷新间隔 PopUp 控件（`intervalButton`），支持极其顺畅的鼠标点击响应，避免系统菜单阻断。
- 绑定点击循环/弹出逻辑，并触发 `onIntervalChanged` 闭包与 `UserDefaults` 实时持久化。

---

## Verification Plan

### Automated Tests
- 运行 `./test.sh` 确保 165+ 项测试 100% 跑通。
- 运行 `swiftc -warnings-as-errors -typecheck` 验证类型安全。

### Manual Verification
- 编译打包 `build.sh`，重新拉起 Pulse.app。
- 使用 `screencapture` 工具测试按钮点击、界面更新与双卡片排版。
