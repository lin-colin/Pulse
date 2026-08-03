# Pulse 当前项目参考

## 当前实现状态

以下内容是 2026-07-29 的当前实现快照；修改前先重新阅读相关源文件，不要把本参考当成不可变事实。

### 已完成的硬件口径

- 系统功耗：SMC `PSTR` 为主；AppleSmartBattery `PowerTelemetryData.SystemLoad` 只在 `ExternalConnected == false` 时回退。
- 电池温度：SMC `TB0T` 为主；BMS `Temperature / 100` 为回退。
- 内存使用：`hw.memsize`、`host_page_size` 与 `host_statistics64(HOST_VM_INFO64)`；`free_count` 与 `external_page_count` 构成可用/可回收部分。
- 内存压力：启动读取 `kern.memorystatus_vm_pressure_level`，之后用 `DispatchSourceMemoryPressure` 监听状态变化；30 秒低频重同步。

### 内存采集的关键约束

- 压力状态缓存用独立锁保护。
- sysctl 读取、时钟读取、VM 读取都必须在锁外执行。
- 重同步启动时记录事件代次；若其返回前收到了有效压力事件，旧读取结果必须丢弃。
- `MemoryPressureLevel`：normal、warning、critical、unavailable；内核值仅接受 1、2、4。
- 读取失败：首次无有效状态显示 unavailable；已有有效事件时保留最后可信状态，并限制重试频率。

### A1 菜单栏状态

- `StatusItemView` 的内存文字是 `memoryUsagePercentage`。
- `memoryPressureLevel.presentationRole` 决定内存图标和文字颜色。
- `StatusBarController` 的菜单分为 `内存使用` 和 `内存压力`。
- Tooltip 恒为 `已使用 X / Y · 压力：Z`，字段独立显示，不把缺失值变成 0。

## 已知进度与后续边界

- 纯逻辑、采集层和 A1 UI 集成均已完成。
- 最近一次自动测试为 131 项断言；后续修改后以实际测试输出为准。
- 任务 3 只剩最终代码质量审查；不要把实机“活动监视器”对照、启动 UI 检查或其他指标阈值重设计混入任务 3。
- 实机对照属于后续验证任务：比较使用率与活动监视器的“已使用内存 / 物理内存”，并比较压力颜色；不要要求逐字节或每一瞬间完全一致。

## 历史问题与禁止回归

1. 充电时把旧 `SystemLoad` 显示为 83 W：错误，因为该字段在交流供电路径不代表系统负载。
2. 用 `100 - System-wide memory free percentage` 显示“内存压力”：错误，因为它既不是使用率，也不是活动监视器压力。
3. 使用全部 `inactive_count` 当文件缓存：错误，因为其中包含匿名内存。
4. 使用 60% / 80% 内存使用率给压力上色：错误，因为活动监视器压力是独立的系统状态。
5. 在锁内调用可注入或慢的读取闭包：错误，会阻塞 critical 事件或产生可重入死锁。
6. 溢出或异常页统计显示 0%：错误，必须显示不可用。
