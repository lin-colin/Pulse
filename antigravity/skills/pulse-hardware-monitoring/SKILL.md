---
name: pulse-hardware-monitoring
description: Use when implementing, diagnosing, reviewing, or validating Pulse macOS system power, battery temperature, memory usage, memory pressure, or status-bar metrics, especially when values differ from AlDente or Activity Monitor, refreshes lag, or color semantics are unclear.
---

# Pulse Hardware Monitoring

先读 [当前项目参考](references/pulse-current-state.md)。把系统指标视为产品语义，而不是“拿到一个数就显示”。先确认该数回答的问题、单位、刷新行为和失效策略，再改代码。

## 不可违反的规则

- 不要提交 Git；仓库可能不是 Git 仓库。
- 不要把不可读取的数据显示成 `0`、绿色或“正常”。使用 `—`、`不可用` 或次要文字色。
- 不要用一个指标冒充另一个指标。例如内存使用率不能冒充内存压力。
- 新增或修改 Swift 逻辑时添加中文注释，解释“为什么”，不只是复述代码。
- 先写能失败的测试，再写实现；完成后运行 `./test.sh` 和 `./build.sh`。
- 保留用户现有改动，除非本次任务明确要求修改；禁止 destructive Git 命令。

## 指标真值表

| 展示指标 | 真正回答的问题 | 主数据源 | 允许的回退 | 禁止做法 |
|---|---|---|---|---|
| 系统负载（W） | 当前整机系统功耗 | Apple SMC `PSTR`，单位 W | 仅明确使用电池且 `ExternalConnected == false` 时，AppleSmartBattery 旧 `SystemLoad`（mW 转 W） | 交流充电时使用旧 `SystemLoad`；它会把适配器/电池路径混入，出现数十 W 假值 |
| 电池温度（°C） | 电池包温度 | Apple SMC `TB0T` | BMS `Temperature / 100` | 直接显示未换算的 centi-degrees；把无效值当 0 |
| 内存使用率（%） | 物理统一内存已经使用多少 | `hw.memsize` + `host_statistics64` | 无；统计失败即不可用 | `100 - memory_pressure -Q` 的 free percentage |
| 内存压力（状态） | macOS 是否高效满足当前内存需求 | 启动时 `kern.memorystatus_vm_pressure_level`，运行时 `DispatchSourceMemoryPressure` | 事件收到前且 sysctl 不可读时 `.unavailable` | 用内存使用率阈值、压缩量或 swap 单独推断绿/黄/红 |

### 系统功耗规则

1. 读取 `PSTR` 时，验证为有限、非负且在合理物理范围内的 W 值。
2. `PSTR` 无效且明确在使用电池时，才可将旧 `SystemLoad` 从 mW 转换为 W。
3. `ExternalConnected == true` 或未知时，旧字段一律不回退。显示 `—` 比显示 83 W 的错误值更诚实。
4. 功耗样本必须来自同一轮硬件读取；不要混合不同刷新周期的电流与电压再相乘。

### 电池温度规则

1. 优先使用 SMC `TB0T`（`sp78`，摄氏度）。
2. `TB0T` 不可用时使用 AppleSmartBattery 的 `Temperature / 100`。
3. 校验物理范围；无效测点保持不可用。

### 内存使用率与内存压力规则

这两个概念必须始终分开：

```text
内存使用率 = 已使用物理内存 / 物理内存 × 100
内存压力   = macOS 的 normal / warning / critical 状态
```

计算已使用内存时：

```text
reclaimableBytes = external_page_count × pageSize
usedBytes = totalBytes - freeBytes - reclaimableBytes
usagePercentage = usedBytes / totalBytes × 100
```

- `external_page_count` 表示文件支持页，最接近“活动监视器”的可回收文件缓存。
- 不要把全部 `inactive_count` 当作可用内存；其中包含匿名内存。
- `freePages + externalPages` 相加或与页大小相乘发生溢出、或可用量大于总量时，使用率必须为 `nil`，不能夹成 0%。
- `kern.memorystatus_vm_pressure_level` 的已知映射：`1 = normal`、`2 = warning`、`4 = critical`。这是未正式文档化的当前状态读取，必须只封装在 `SystemMonitor` 中。
- DispatchSource 监听 `.normal`、`.warning`、`.critical` 的后续变化；它不保证启动时发送当前值，因此不能替代启动 sysctl。
- 重同步读取必须在锁外进行；用事件代次防止较旧的 sysctl 结果覆盖较新的 critical 事件。

## UI 语义

当前已确定的内存方案是 **A1**：

- 菜单栏显示 `memorychip + 使用率百分比`，例如 `84 %`。
- 百分比只表示物理内存使用率。
- 图标和数字颜色只表示 macOS 内存压力：normal 绿色、warning 黄色、critical 红色、unavailable 灰色。
- 下拉菜单必须分两项：`内存使用` 与 `内存压力`。
- Tooltip 格式固定为：`已使用 X / Y · 压力：Z`。`X`、`Y` 各自独立降级成 `—`。
- 闪电 `bolt.fill` 只属于系统功耗；内存继续使用 `memorychip`。
- 不要因为内存使用率高就把它染红；高使用率且绿色压力是正常且常见的 macOS 行为。

其他指标的既有颜色不能因修改内存而被顺带改变。若要重新设计功耗、温度或 CPU 阈值，先单独写规格并取得用户确认。

## 修改流程

1. **定位语义。** 先在 `Pulse/Models`、`Pulse/Services`、`Pulse/UI` 和 `Tests` 中查找指标的来源、单位、格式和颜色阈值。
2. **定义不可用路径。** 为每个新读数说明：读取失败、单位错误、数值越界、并发事件、时间倒退时展示什么。
3. **先写测试。** 纯计算放在 `MetricCalculations` 或独立模型，覆盖正常值、缺失、边界、溢出、并发状态交错。
4. **最小化实现。** 采集层不依赖 AppKit；UI 不自行重新推导硬件状态。
5. **验证分层。** 先 `./test.sh`，再 warnings-as-errors typecheck，再 `./build.sh`，最后实机对照。
6. **报告限制。** 明确区分“已实测一致”“合理接近”“私有接口可能随 macOS 变化”。

## 必跑验证

在项目根目录执行：

```bash
./test.sh
./build.sh
plutil -lint build/Pulse.app/Contents/Info.plist
```

修改 Swift 后还要执行全源警告即错误的检查：

```bash
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/pulse-swift-module-cache" \
SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/pulse-swift-module-cache" \
swiftc -warnings-as-errors -typecheck \
  -framework AppKit -framework IOKit \
  Pulse/App/main.swift Pulse/App/AppDelegate.swift \
  Pulse/Models/MemoryMetrics.swift Pulse/Models/MetricCalculations.swift \
  Pulse/Models/SMCValueDecoder.swift Pulse/Models/PulseDefaults.swift \
  Pulse/UI/StatusBarController.swift Pulse/UI/StatusItemView.swift \
  Pulse/Services/SMCReader.swift Pulse/Services/HardwareMonitor.swift \
  Pulse/Services/SystemMonitor.swift Pulse/Services/BatteryMonitor.swift
```

实机对照“活动监视器”时，比较：

- Pulse 使用率与 `已使用内存 / 物理内存` 的接近程度；允许采样时刻不同造成的小幅差异。
- Pulse 内存颜色与“内存压力”绿/黄/红状态是否一致。
- 内存使用率高、压缩内存高但交换为 0 且压力绿色，不是 bug。

## 文件地图

| 区域 | 主要文件 | 职责 |
|---|---|---|
| 纯计算与格式 | `Pulse/Models/MetricCalculations.swift` | 单位换算、范围校验、内存快照与格式化 |
| 内存领域模型 | `Pulse/Models/MemoryMetrics.swift` | usage、压力状态和展示语义 |
| 硬件读取 | `Pulse/Services/HardwareMonitor.swift`、`SMCReader.swift` | PSTR、TB0T 和安全回退 |
| 系统读取 | `Pulse/Services/SystemMonitor.swift` | CPU、Mach 内存统计、sysctl、Dispatch 压力事件 |
| 刷新编排 | `Pulse/App/AppDelegate.swift` | 后台采集，主线程更新 UI |
| 状态栏 | `Pulse/UI/StatusBarController.swift`、`StatusItemView.swift` | A1 展示、菜单、Tooltip、颜色 |
| 回归测试 | `Tests/MetricCalculationsTests.swift` | 纯逻辑、状态机、并发交错测试 |

## 交付报告模板

交付时报告以下内容：

1. 改了什么，按“采集 / 计算 / UI / 测试”归类。
2. 真实指标定义和数据源。
3. 失败或不可用时的展示行为。
4. `./test.sh` 的实际断言数、typecheck、build、plist 的实际结果。
5. 实机对照结果及仍存在的限制。
6. 明确说明未执行 Git 提交。
