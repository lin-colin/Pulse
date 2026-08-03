# Pulse 内存使用率与系统压力设计规格

日期：2026-07-29  
状态：待用户审阅  
范围：内存指标采集、状态栏展示、下拉菜单说明和相关测试

## 1. 目标

Pulse 必须同时回答两个不同问题：

1. 当前物理内存用了多少：展示为 `0...100%` 的真实内存使用率。
2. macOS 是否正在承受内存压力：展示为正常、警告、严重三档状态，并使用与“活动监视器”一致的绿、黄、红语义。

百分比不得再命名为“内存压力百分比”，压力状态也不得根据单一使用率阈值推断。

## 2. 已确认的界面方案

采用可视化方案 A1：

- 菜单栏继续显示 `memorychip + 百分比`，保持现有 2×2 紧凑布局。
- 百分比表示物理内存使用率，例如 `84%`。
- `memorychip` 图标和百分比文字同时根据系统压力状态着色。
- 正常使用系统绿色，警告使用系统黄色，严重使用系统红色。
- 无法读取压力状态时使用系统次要文字色，不伪装为正常。
- 下拉菜单显示两项独立信息：
  - `内存使用：20.08 GB / 24.00 GB（84%）`
  - `内存压力：警告`
- 菜单栏悬停提示合并展示：
  - `已使用 20.08 / 24.00 GB · 压力：警告`

本次不为内存压力增加橙色等级。Apple 的公开语义只有正常、警告、严重三档；若未来增加橙色，必须明确标记为 Pulse 自定义趋势，不能声称与“活动监视器”一致。

## 3. 当前问题

当前 `SystemMonitor` 每五秒执行一次 `/usr/bin/memory_pressure -Q`，解析：

`System-wide memory free percentage`

随后使用 `100 - freePercentage` 得到当前的 `memPressure`。

这个数值存在三个问题：

1. 它不是“活动监视器”的内存压力等级。
2. 它不是“活动监视器”的已使用物理内存比例。
3. 五秒缓存使状态变化慢于应用的默认一秒刷新间隔。

现有 UI 又使用 60% 和 80% 的固定阈值给该数值着色，因此当前百分比和颜色都不能表达“活动监视器”的真实含义。

## 4. 数据模型

新增明确的领域类型，避免继续用一个 `Double?` 混合两种语义。

```swift
enum MemoryPressureLevel: Equatable {
    case normal
    case warning
    case critical
    case unavailable
}

struct MemorySnapshot: Equatable {
    let usedBytes: UInt64?
    let totalBytes: UInt64?
    let usagePercentage: Double?
    let pressureLevel: MemoryPressureLevel
}
```

约束：

- `usagePercentage` 必须为有限值并限制在 `0...100`。
- 任一底层读取失败时，对应字段使用 `nil` 或 `.unavailable`。
- 不允许用 `0` 代替不可用数据。
- 压力状态与使用率彼此独立；任何一方读取失败都不得伪造另一方。

## 5. 内存使用率采集

### 5.1 数据来源

- 使用 `sysctlbyname("hw.memsize")` 读取物理内存总量。
- 使用 `host_statistics64(..., HOST_VM_INFO64, ...)` 读取 `vm_statistics64_data_t`。
- 使用运行时主机页大小换算页数，禁止假设固定为 4 KB 或 16 KB。

### 5.2 计算口径

目标是尽量接近“活动监视器”的“已使用内存”，同时把可立即回收的文件缓存排除在已使用量之外。

`external_page_count` 对应文件支持页，最接近“活动监视器”单独列出的可回收“缓存的文件”。`speculative_count` 已包含在外部页统计关系中，不能重复相加；`inactive_count` 同时包含匿名内存，不能整体当作可用缓存。

优先计算：

`reclaimableBytes = external_page_count × pageSize`

`usedBytes = clamp(totalBytes - freeBytes - reclaimableBytes, 0...totalBytes)`

`usagePercentage = usedBytes / totalBytes × 100`

实现前必须在当前机器上与“活动监视器”的“已使用内存”进行多组实测对照。如果 `external_page_count` 口径存在持续明显偏差，允许基于实测调整可回收集合，但必须：

- 保留计算注释；
- 添加纯函数测试；
- 不把压缩内存简单当作空闲内存；
- 不根据压力颜色反向修改使用率。

由于 Apple 未公开“活动监视器”全部内部计算细节，本功能承诺语义一致和合理接近，不承诺每个采样点逐字节相同。

## 6. 内存压力采集

### 6.1 启动时读取当前状态

通过 `sysctlbyname("kern.memorystatus_vm_pressure_level")` 读取当前内核状态：

- `0x01` → `.normal`
- `0x02` → `.warning`
- `0x04` → `.critical`
- 其他值或读取失败 → `.unavailable`

当前机器实测在“活动监视器”为黄色时该值为 `2`。

这个 sysctl 名称未被 Apple 作为稳定公开 API 文档化，必须封装在单一读取器中，并提供失败降级路径，禁止让私有接口细节扩散到 UI。

### 6.2 监听后续变化

使用：

```swift
DispatchSource.makeMemoryPressureSource(
    eventMask: [.normal, .warning, .critical],
    queue: monitorQueue
)
```

事件映射到同名 `MemoryPressureLevel`，变化后立即更新缓存。

实测表明 DispatchSource 启动时不会主动发送当前状态，因此它不能替代启动时读取。两者职责如下：

- sysctl：提供启动时的当前快照，并作为低频校验。
- DispatchSource：提供运行期间的即时状态变化。

### 6.3 校验与降级

- 每次常规刷新读取缓存中的压力等级，不启动外部进程。
- 可按较低频率重新读取 sysctl，修复应用休眠、系统唤醒或事件遗漏后的状态。
- 如果 sysctl 不可用：
  - 保留 DispatchSource 监听；
  - 在收到第一个事件前显示 `.unavailable`；
  - 禁止使用内存使用率阈值伪造绿、黄、红状态。
- 删除 `/usr/bin/memory_pressure -Q` 采集路径及五秒缓存逻辑。

## 7. 数据流

1. `AppDelegate` 每次刷新调用 `SystemMonitor.getMemorySnapshot()`。
2. `SystemMonitor` 同步读取使用量统计，并读取线程安全缓存中的压力等级。
3. `AppDelegate` 将完整 `MemorySnapshot` 传给 `StatusBarController`。
4. `StatusBarController`：
   - 把使用率和压力等级传给 `StatusItemView`；
   - 分别更新“内存使用”和“内存压力”菜单项；
   - 更新状态栏悬停提示。
5. `StatusItemView`：
   - 只格式化 `usagePercentage`；
   - 只根据 `pressureLevel` 决定内存图标与文字颜色；
   - 不再使用 60%/80% 阈值推断内存压力。

## 8. 线程安全与生命周期

- `DispatchSourceMemoryPressure` 必须被 `SystemMonitor` 强引用，否则监听器会立即释放。
- 压力状态缓存使用专用串行队列或锁保护。
- 监听器只创建一次，不在每秒刷新中反复创建。
- `SystemMonitor` 释放时取消 DispatchSource。
- UI 更新仍统一回到主线程。
- 采集失败不得阻塞 CPU、电池温度和系统功率更新。

## 9. 颜色语义

本次先统一内存指标的语义：

| 压力状态 | 图标和文字颜色 | 含义 |
|---|---|---|
| normal | `systemGreen` | macOS 正在有效使用内存 |
| warning | `systemYellow` | 内存压力已升高 |
| critical | `systemRed` | 内存压力严重 |
| unavailable | `secondaryLabelColor` | 当前无法判断 |

闪电图标只属于系统功率，不用于内存压力。内存继续使用 `memorychip`，避免把“耗电”和“内存压力”混为同一语义。

其他指标的颜色阈值统一属于下一阶段设计，本规格不顺带修改，以免同时改变多个未经验证的业务口径。

## 10. 测试

### 10.1 纯函数测试

- 压力原始值 `1/2/4` 映射正确。
- 未知值、读取失败映射为 `.unavailable`。
- 使用量计算覆盖：
  - 正常数据；
  - 总量为零；
  - 可用量大于总量；
  - 极大页数不溢出；
  - 结果始终在 `0...100`。
- 字节与 GB、百分比格式化正确。

### 10.2 服务测试

- 初始 sysctl 值进入快照。
- DispatchSource 事件更新缓存。
- 失败时显示 unavailable，不回退到伪造阈值。
- 并发读取不会产生数据竞争。
- 不再启动 `memory_pressure` 子进程。

真实 DispatchSource 难以在单元测试中稳定触发，因此监听器和 sysctl 读取器必须支持依赖注入。

### 10.3 UI 规则测试

- `84% + normal` 显示绿色。
- `84% + warning` 显示黄色。
- `50% + critical` 仍显示红色，证明颜色不依赖使用率。
- 无使用率显示 `—`。
- 无压力状态使用次要文字色。

### 10.4 实机验收

- 同时打开 Pulse 和“活动监视器”。
- 对比 Pulse 使用率与“已使用内存 / 物理内存”。
- 对比 Pulse 颜色与内存压力图颜色。
- 至少观察正常与警告状态；严重状态优先通过受控模拟或注入测试验证，不通过无上限真实内存分配强行制造。
- 验证一秒刷新下 CPU、功率、温度采集不被内存采集阻塞。

## 11. 完成标准

- 菜单栏百分比明确代表真实内存使用率。
- 菜单栏颜色来自 macOS 压力状态，而非百分比阈值。
- 下拉菜单能同时看到使用量和压力状态。
- 当前错误的 `100 - freePercentage` 路径被删除。
- 所有新增或修改逻辑带有解释“为什么”的中文注释。
- 自动测试、警告视为错误的类型检查和应用构建全部通过。
- 不执行 Git 提交。
