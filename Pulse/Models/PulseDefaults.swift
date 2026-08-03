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
