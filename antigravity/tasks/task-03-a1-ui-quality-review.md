# Task 03 — A1 内存菜单栏集成的最终质量审查

## 先决条件

先完整阅读并同时遵循：

1. `antigravity/skills/pulse-disciplined-engineering/SKILL.md`
2. `antigravity/skills/pulse-hardware-monitoring/SKILL.md`
3. `antigravity/skills/pulse-hardware-monitoring/references/pulse-current-state.md`

项目根目录：`/Users/hlc/Documents/PulseProject`

## 目标

对已完成的 A1 内存菜单栏集成进行最后一轮代码质量审查；如发现 Critical 或 Important 问题，仅做最小修复并验证。不要重做内存采集、不要改变其他指标的颜色阈值、不要做活动监视器实机对照（那属于下一任务）。

## 背景

Pulse 已将菜单栏内存指标改为：

- 数字：真实物理内存使用率。
- 颜色：macOS 内存压力 normal / warning / critical / unavailable。
- 菜单：分开显示“内存使用”和“内存压力”。

这轮任务的代码集中在：

- `Pulse/App/AppDelegate.swift`
- `Pulse/UI/StatusBarController.swift`
- `Pulse/UI/StatusItemView.swift`

## 必须核查的要求

1. `AppDelegate.collectAndDisplayMetrics()` 每个刷新周期只调用一次 `systemMonitor.getMemorySnapshot()`，并将完整 `MemorySnapshot` 传给状态栏；UI 更新保持在主线程。
2. `StatusItemView`：
   - 数字只来自 `memoryUsagePercentage`；
   - 颜色只来自 `memoryPressureLevel.presentationRole`；
   - normal 为 `systemGreen`、warning 为 `systemYellow`、critical 为 `systemRed`、unavailable 为 `secondaryLabelColor`；
   - `memorychip` 图标与数字同色；
   - 不存在 60% / 80% 等内存百分比阈值；
   - 不改动功耗、温度、CPU 的既有颜色规则。
3. `StatusBarController`：
   - 菜单有独立的“内存使用”和“内存压力”项；
   - 内存使用文案为 `已使用 / 总量 (百分比)`，压力文案为正常、警告、严重或不可用；
   - `usedBytes`、`totalBytes`、`usagePercentage` 的缺失值独立处理：百分比缺失时菜单显示 `—`；如果百分比存在，则容量两端即使有一侧缺失也保留另一侧；
   - Tooltip 必须始终遵循 `已使用 X / Y · 压力：Z`，初始状态应为 `已使用 — / — · 压力：不可用`；
   - 长菜单详情不会参与 `StatusItemView` 的 2×2 宽度计算；
   - `gauge.with.dots.needle.33percent` 不可用时菜单可无图，但不得崩溃。
4. 不得重新引入 `getMemoryPressure`、`memPressure`、`normalizedMemoryPressure`、`/usr/bin/memory_pressure`。
5. 新增或修改 Swift 代码要有中文“为什么”注释。
6. 不提交 Git，不使用 destructive Git 命令。

## 工作方式

在任何代码修改前，先按 `pulse-disciplined-engineering` 输出需求理解、事实/假设/未知项、影响分析和验证计划。只有发现 Critical 或 Important 问题并有失败证据时才修改代码；Minor 问题只记录，不扩大范围。

1. 先只读审查以上三个文件和与其调用相关的 `MemorySnapshot`、`MemoryPressureLevel` 定义。
2. 写下发现的问题，按 Critical / Important / Minor 分级，附文件和行号。
3. 若没有 Critical 或 Important 问题，不改代码，直接验证并报告 Approved。
4. 若有 Critical 或 Important 问题：
   - 先增加或调整能失败的测试；若问题属于 AppKit 绘制且不适合单测，先让完整 typecheck/build 体现接口红灯；
   - 实施最小修复；
   - 不扩大到其他指标、阈值或底层采集；
   - 再次审查自己的改动。

## 必跑验证

在项目根目录运行：

```bash
./test.sh
./build.sh
plutil -lint build/Pulse.app/Contents/Info.plist
rg -n "getMemoryPressure|memPressure|normalizedMemoryPressure|/usr/bin/memory_pressure" Pulse Tests
```

再运行 `pulse-hardware-monitoring` 技能中的全源 `swiftc -warnings-as-errors -typecheck` 命令。

## 验收标准

- 所有命令成功；`rg` 对旧符号无匹配。
- A1 的“数字 = 使用率、颜色 = 压力”在代码路径中没有混用。
- 缺失值不被显示成 0 或正常状态。
- 没有 Critical 或 Important 质量问题；Minor 问题仅记录，不阻止任务完成。
- 不得以“代码已改好”作为结论；必须附上实际运行的测试、typecheck、build 与 lint 输出摘要。任何无法执行的验证必须明确说明原因和风险。
- 最终报告包括：审查结论、实际断言数、构建和 typecheck 结果、是否改代码、是否执行 Git 提交（应为否）。

## 不在本任务范围内

- 启动 Pulse 或与活动监视器现场比对。
- 重新调整功耗、温度、CPU 的颜色阈值。
- 修改 PSTR、TB0T、Mach 内存采集或 Dispatch 压力状态机。
- 提交、推送或创建 Git 分支。
