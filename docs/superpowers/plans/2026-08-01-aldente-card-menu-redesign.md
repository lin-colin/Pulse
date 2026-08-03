# AlDente 风格圆角卡片面板与原生 NSSwitch 开关重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 参考 AlDente 将 Pulse 下拉菜单的 6 项硬件指标重构为独立的暗色圆角卡片面板（Metrics Card View），并为“开机自动启动”引入 macOS 原生蓝色胶囊滑块开关 (`NSSwitch`)，彻底消除右侧大片留白与左侧对齐错位。

**Architecture:** 创建自定义 AppKit 视图组件 `MetricsCardView` 统一承载 6 项硬件指标的图标、标签与右对齐数值；为“开机自动启动”创建包含 `NSSwitch` 的 `NSView` 菜单项视图；硬件指标保持现有的 A1 硬件数据源与压力状态逻辑。

**Tech Stack:** Swift, AppKit, Cocoa (NSView, NSMenu, NSMenuItem, NSSwitch, NSFont, NSColor)

## Global Constraints

- 不提交 Git，不使用 destructive Git 命令；
- 保持 A1 内存口径：数字为物理内存使用率、颜色为 macOS 内核内存压力；
- 新增或修改的 Swift 逻辑必须添加解释“为什么”的中文注释；
- 完成后必须执行全套验证：`./test.sh`、`./build.sh`、`plutil -lint` 和 `swiftc -warnings-as-errors -typecheck`。

---

### Task 1: 创建 AlDente 风格圆角卡片视图 MetricsCardView

**Files:**
- Create: `Pulse/UI/MetricsCardView.swift`
- Modify: `Pulse/UI/StatusBarController.swift`
- Test: `Tests/MetricCalculationsTests.swift`

**Interfaces:**
- Consumes: `MemorySnapshot`, `power`, `temperature`, `cpuUsage`, `cpuFrequency`, `chargeState`
- Produces: `MetricsCardView` (自定义 NSView，包含圆角卡片背景、暗色边框与 6 项带冒号对齐指标)

- [ ] **Step 1: 编写测试确认 MetricsCardView 的结构与接口**
- [ ] **Step 2: 创建 MetricsCardView.swift**
- [ ] **Step 3: 运行并验证单元测试**

---

### Task 2: 为“开机自动启动”实现 macOS 原生 NSSwitch 胶囊开关视图

**Files:**
- Modify: `Pulse/UI/StatusBarController.swift`
- Test: `Tests/MetricCalculationsTests.swift`

**Interfaces:**
- Consumes: `SMAppService.mainApp.status`
- Produces: `launchAtLoginSwitchView` 包含标签与原生 `NSSwitch` 控件

- [ ] **Step 1: 编写测试验证 NSSwitch 联动逻辑**
- [ ] **Step 2: 在 StatusBarController 中构建 NSSwitch 自定义菜单项视图**
- [ ] **Step 3: 运行验证**

---

### Task 3: 整合下拉菜单布局并消除右侧留白空坑

**Files:**
- Modify: `Pulse/UI/StatusBarController.swift`

**Interfaces:**
- Consumes: `MetricsCardView`, `launchAtLoginSwitchView`
- Produces: 齐平右对齐且无尴尬空白的完整 NSMenu 菜单面板

- [ ] **Step 1: 将 MetricsCardView 嵌入菜单顶部第一项**
- [ ] **Step 2: 调整菜单宽度与全域右对齐线**
- [ ] **Step 3: 执行全套验证命令**

---

### Task 4: 诚实交付与实机测试

- [ ] **Step 1: 执行全源警告即错误类型检查**
- [ ] **Step 2: 重启 Pulse 并在实机呈现最终效果**
