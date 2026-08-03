# 消除多余第 2 层灰框，回归纯正苹果原厂双层卡片架构实施计划

**Goal:** 彻底消除界面上多余的手工灰底边框（第 2 层灰框），将视觉层级从累赘生硬的“3 层框套娃”精简为 100% 符合苹果原厂规范的“2 层卡片架构”（系统底色 + 缩进悬浮纯白/深色圆角卡片）。

---

## User Review Required

> [!IMPORTANT]
> 1. **消除第 2 层多余灰框 (Remove Redundant Outer Frame)**：
>    - 撤销 `MainMenuView.swift` 中手工绘制的 `outerPath` 灰色外边框与背景色，使其变为全透明容器。
> 2. **回归纯正原厂 2 层架构 (Pure Two-Layer Layout)**：
>    - **底层 (第 1 层)**：系统 `NSMenu` 原生的精致高斯模糊/系统窗口底色。
>    - **顶层 (第 2 层)**：直接浮在底色上的 `MetricsCardView` 与 `SettingsControlCardView` 2 块 10pt 圆角纯白/深色独立卡片（左右留 10pt 缩进边缝）。
>    - **底部项**：`⊗ 退出 Pulse` 自然脱离卡片包裹，置于菜单底部。

---

## Proposed Changes

### Component 1: 精简 Shell 容器 (MainMenuView)

#### [MODIFY] [MainMenuView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/MainMenuView.swift)
- 移除 `draw(_:)` 中的 `outerPath` 灰色背景绘制与外边框描边，使 `MainMenuView` 作为纯粹的透明 Layout 容器。
- 调整高度与边距，使内部两块卡片与底部“退出 Pulse”项间距自然舒朗。

---

## Verification Plan

### Automated Tests
- 运行 `./test.sh` 确保 165+ 断言 100% 跑通。
- 运行 `swiftc -warnings-as-errors -typecheck` 验证全源类型安全。

### Manual Verification
- `./build.sh` 编译打包，重新拉起 Pulse.app。
- 使用 `screencapture` 抓取屏幕截图，确认 3 层套娃感彻底消失，展现纯正苹果原厂双层卡片美感。
