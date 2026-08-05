import Foundation

/// Pulse 跨组件共享的运行参数，避免菜单与实际采集行为不一致。
enum PulseDefaults {
    static let defaultRefreshInterval: TimeInterval = 1.0
    static let allowedRefreshIntervals: [TimeInterval] = [1, 2, 3, 5, 10]

    /// 为什么：UserDefaults 不是可信输入，进入计时器前必须归一化到已支持档位。
    static func validatedRefreshInterval(_ value: TimeInterval) -> TimeInterval {
        allowedRefreshIntervals.contains(value) ? value : defaultRefreshInterval
    }

    /// DispatchSource 负责即时变化；三十秒重读只用于修复唤醒或事件遗漏后的状态。
    static let memoryPressureResyncInterval: TimeInterval = 30.0
}

// MARK: - 可配置阈值

/// 单个指标的橙色警告与红色高危阈值。
/// 为什么：遵从 Equatable 允许在上层通过深度相等判定配置变化，避免无变化时的重绘。
struct MetricThreshold: Equatable {
    var orange: Double
    var red: Double
}

/// 集中管理所有指标的可配置阈值，提供 UserDefaults 持久化。
/// 为什么：遵从 Equatable 允许在 StatusBarController 和 PopoverContentView 之间高效比较，避免重复从 UserDefaults 加载。
struct ThresholdConfig: Equatable {

    var power: MetricThreshold
    var temperature: MetricThreshold
    var cpu: MetricThreshold

    /// 从 UserDefaults 读取用户配置，缺失时使用编译期默认值。
    static func load() -> ThresholdConfig {
        let defaults = UserDefaults.standard
        return ThresholdConfig(
            power: MetricThreshold(
                orange: defaults.object(forKey: Keys.powerOrange) as? Double ?? Defaults.powerOrange,
                red: defaults.object(forKey: Keys.powerRed) as? Double ?? Defaults.powerRed
            ),
            temperature: MetricThreshold(
                orange: defaults.object(forKey: Keys.tempOrange) as? Double ?? Defaults.tempOrange,
                red: defaults.object(forKey: Keys.tempRed) as? Double ?? Defaults.tempRed
            ),
            cpu: MetricThreshold(
                orange: defaults.object(forKey: Keys.cpuOrange) as? Double ?? Defaults.cpuOrange,
                red: defaults.object(forKey: Keys.cpuRed) as? Double ?? Defaults.cpuRed
            )
        )
    }

    /// 将当前阈值写入 UserDefaults。
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(power.orange, forKey: Keys.powerOrange)
        defaults.set(power.red, forKey: Keys.powerRed)
        defaults.set(temperature.orange, forKey: Keys.tempOrange)
        defaults.set(temperature.red, forKey: Keys.tempRed)
        defaults.set(cpu.orange, forKey: Keys.cpuOrange)
        defaults.set(cpu.red, forKey: Keys.cpuRed)
    }

    /// 恢复为编译期默认值。
    static func defaults() -> ThresholdConfig {
        ThresholdConfig(
            power: MetricThreshold(orange: Defaults.powerOrange, red: Defaults.powerRed),
            temperature: MetricThreshold(orange: Defaults.tempOrange, red: Defaults.tempRed),
            cpu: MetricThreshold(orange: Defaults.cpuOrange, red: Defaults.cpuRed)
        )
    }

    // MARK: - 编译期默认值

    private enum Defaults {
        static let powerOrange: Double = 18.0
        static let powerRed: Double = 30.0
        static let tempOrange: Double = 35.0
        static let tempRed: Double = 40.0
        static let cpuOrange: Double = 60.0
        static let cpuRed: Double = 80.0
    }

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let powerOrange = "threshold.power.orange"
        static let powerRed = "threshold.power.red"
        static let tempOrange = "threshold.temperature.orange"
        static let tempRed = "threshold.temperature.red"
        static let cpuOrange = "threshold.cpu.orange"
        static let cpuRed = "threshold.cpu.red"
    }
}
