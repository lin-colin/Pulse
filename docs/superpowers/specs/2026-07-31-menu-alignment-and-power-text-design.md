# Pulse 下拉菜单电源状态文案与开机自启对齐优化 Design Spec

## 1. 背景与目标

根据用户反馈与截图分析，目前 Pulse 下拉菜单存在以下两个影响体验的细节问题：

1. **电源状态文案表达不明确**：当前仅显示`已连接电源`，用户无法直接获知外接电源时电池**到底有没有在充电**。
2. **开机自启打钩导致菜单缩进防错位**：当“开机自动启动”勾选（`state = .on`）时，macOS 系统的 `✓` 勾选图标插在菜单项最左侧，导致 `✓` 与 SF Symbols `power` 图标挤压或推挤整行文本，破坏了所有菜单项图标的垂直左对齐。

## 2. 问题一：电源状态精准措辞定义 (锁定方案 1)

在 `BatteryMonitor.swift` 和 `StatusBarController.swift` 中，对“电源状态”这一行的右侧文字进行精准定义：

- **当电池处于净充电状态 (`isCharging == true`)**：
  - 展示文案：`正在充电`
- **当处于外接交流电源，但电池未在充电 (`isPluggedIn == true && isCharging == false`)**：
  - 展示文案：`已连接电源 (未在充电)`
- **当完全处于电池放电供电状态 (`isPluggedIn == false`)**：
  - 展示文案：`使用电池`

---

## 3. 问题二：开机自启与菜单对齐升级设计

### 方案 A：标题右侧状态文本对齐 (锁定)

- 取消最左侧的系统 `✓` 勾选框（设置 `state = .off`）。
- 将“开机自动启动”这一行的标题与右侧文本统一采用右对齐制表符（`NSTextTab`）渲染：
  - 未开启时：`开机自动启动        已关闭`
  - 已开启时：`开机自动启动        已开启`
- **效果**：彻底移除了最左侧系统 `✓` 插入带来的破坏，使得所有 8 个菜单项最左侧的 SF Symbols 矢量图标在一条垂直线上 **100% 绝对垂直对齐**，且右侧状态清晰干净！

---

## 4. 影响范围与验证计划

- **影响文件**：
  - `Pulse/Services/BatteryMonitor.swift` (实现 `powerSourceState(isCharging:isPluggedIn:)` 精准文案)
  - `Pulse/UI/StatusBarController.swift` (更新菜单标题与开机自启右侧对齐逻辑)
  - `Tests/MetricCalculationsTests.swift` (增加文案格式与对齐回归测试)
- **验证流程**：
  1. `./test.sh` 单元测试通过
  2. warnings-as-errors typecheck 零警告
  3. `./build.sh` 编译打包成功
  4. 截屏实测下拉菜单的对齐与文案展现。
