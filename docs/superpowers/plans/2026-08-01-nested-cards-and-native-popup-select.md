# 大框包小框嵌套卡片排版与原厂蓝底勾 PopUp 完美实现计划

> **Review Status:** APPROVED AFTER AUDIT FIXES (子 Agent 架构审核修正通过)

**Goal:** 完全复刻用户提供的 4 张 macOS 系统设置截图：
1. 实现“外层大框 (`MainMenuView`) + 内部小框 (`MetricsCardView` & `SettingsControlCardView`)”的双层嵌套卡片架构，彻底消除小框背景蔓延到外壁的缺陷。
2. 彻底实现原厂 PopUp 下拉选择框 (`PopUpSelectView`)：支持 Hover 悬浮阴影变化（截图 3）以及点击时弹出带蓝底 `✓` 勾号的原场下拉菜单（截图 4）。

---

## User Review Required

> [!IMPORTANT]
> 1. **大框包小框双层嵌套架构 (Nested Shell Architecture)**：
>    - 大框容器 (`MainMenuView`) 满画幅包裹菜单（12pt 圆角，带有独立的浅灰/深灰底层背景）。
>    - 内部小框 (`MetricsCardView` 和 `SettingsControlCardView`) 缩进 10pt 定位在大框内部（10pt 圆角，独立背景色，透明边框），与大框外墙严格隔离，消除蔓延。
> 2. **苹果原厂带勾选 PopUp 下拉框 (Native Checkmark PopUp Menu)**：
>    - 控件平时呈现为带有 `↕` 上下双箭头的灰色圆角按钮，鼠标 Hover 时触发原厂高亮与阴影变化（复刻截图 3）。
>    - 点击按钮时，独立弹出带有白色 `✓` 勾号和蓝底高亮的原厂下拉选择框（复刻截图 4），选择后 0 延迟更新定时器。

---

## Proposed Changes

### Component 1: 大框 Shell 容器组 (MainMenuView)

#### [NEW] [MainMenuView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/MainMenuView.swift)
- 创建 `MainMenuView` 作为大框 Shell 容器（`width: 310, height: 248`），拥有独立的 12pt 圆角底色背景。
- 负责管理 `MetricsCardView` (小框 1) 与 `SettingsControlCardView` (小框 2) 的精准 Frame 缩进与数据更新透传。

#### [MODIFY] [MetricsCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/MetricsCardView.swift)
- 作为内部小框 1，**完全移除原有的清屏代码 `NSColor.windowBackgroundColor.fill()`**，保证小框背景独立透明，不抹掉大框背景色。

#### [MODIFY] [SettingsControlCardView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/SettingsControlCardView.swift)
- 作为内部小框 2，**完全移除原有的清屏代码**，承载原厂 PopUp 选择框与 NSSwitch 蓝色胶囊开关。

---

### Component 2: 原厂带勾选 PopUp 控件组 (PopUpSelectView)

#### [NEW] [PopUpSelectView.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/PopUpSelectView.swift)
- 自定义 `PopUpSelectView`：开启 `NSTrackingArea` 监听 Hover 悬浮高亮与阴影变化（复刻截图 3）。
- 内部包含完整的 `NSMenu` 菜单项（`1 秒`、`2 秒`、`3 秒 (推荐)`、`5 秒`、`10 秒 (省电)`），为当前 `activeInterval` 选项显式设置 `.state = .on` 弹出蓝底 `✓` 勾号框（100% 复刻截图 4）。

#### [MODIFY] [StatusBarController.swift](file:///Users/hlc/Documents/PulseProject/Pulse/UI/StatusBarController.swift)
- 关联 `MainMenuView` 为顶部第一主菜单项，建立数据与开关响应完整链路。

---

## Verification Plan

### Automated Tests
- `./test.sh` 运行包含 `testNestedShellCardLayout` 与 `testCheckmarkPopUpFormatting` 在内的全套 165+ 断言测试。
- `swiftc -warnings-as-errors -typecheck` 全源警告即错误校验。

### Manual Verification
- `./build.sh` 编译打包并重新启动 Pulse.app。
- 使用 `screencapture` 工具抓取实测截屏，验证大框包小框外观以及点击 PopUp 弹出带有蓝底 `✓` 勾号的选择框。
