import Foundation

/// 状态栏颜色角色枚举
/// 为什么：使用纯枚举隔离 AppKit NSColor 对象，便于在后台线程和单元测试中快速进行 Equatable 比较去重。
enum StatusItemColorRole: Equatable {
    case label
    case secondaryLabel
    case green
    case yellow
    case orange
    case red
}

/// 纯状态栏渲染模型
/// 为什么：封装所有显示文案、符号名与独立颜色角色。实现 Equatable 后，当前后快照在语义和显示效果上完全一致时，
/// StatusBarController 可直接跳过 CoreGraphics 位图重绘与 NSStatusBarButton 赋值，彻底消除无谓 CPU 开销。
struct StatusItemRenderModel: Equatable {
    let powerText: String
    let temperatureText: String
    let memoryText: String
    let cpuText: String
    let powerSymbolName: String
    let powerIconColor: StatusItemColorRole
    let powerTextColor: StatusItemColorRole
    let temperatureColor: StatusItemColorRole
    let memoryColor: StatusItemColorRole
    let cpuColor: StatusItemColorRole

    static func make(
        snapshot: PulseSnapshot,
        thresholds: ThresholdConfig
    ) -> StatusItemRenderModel {
        let powerConfiguration = MetricCalculations.powerDisplayConfiguration(
            power: snapshot.power,
            isCharging: snapshot.powerSource.isCharging,
            isPluggedIn: snapshot.powerSource.isPluggedIn,
            orangeThreshold: thresholds.power.orange,
            redThreshold: thresholds.power.red
        )

        func statusRole(from role: ColorRole) -> StatusItemColorRole {
            switch role {
            case .normal: return .label
            case .chargingGreen: return .green
            case .orangeWarning: return .orange
            case .redWarning: return .red
            }
        }

        let temperatureColor: StatusItemColorRole
        if let temperature = snapshot.temperature,
           temperature >= thresholds.temperature.red {
            temperatureColor = .red
        } else if let temperature = snapshot.temperature,
                  temperature >= thresholds.temperature.orange {
            temperatureColor = .orange
        } else {
            temperatureColor = .label
        }

        let memoryColor: StatusItemColorRole
        switch snapshot.memory.pressureLevel.presentationRole {
        case .healthy: memoryColor = .green
        case .warning: memoryColor = .yellow
        case .critical: memoryColor = .red
        case .unavailable: memoryColor = .secondaryLabel
        }

        let cpuColor: StatusItemColorRole
        if snapshot.cpuUsage >= thresholds.cpu.red {
            cpuColor = .red
        } else if snapshot.cpuUsage >= thresholds.cpu.orange {
            cpuColor = .orange
        } else {
            cpuColor = .label
        }

        return StatusItemRenderModel(
            powerText: MetricCalculations.formatted(snapshot.power, decimals: 1, suffix: "W"),
            temperatureText: MetricCalculations.formatted(snapshot.temperature, decimals: 1, suffix: "°C"),
            memoryText: MetricCalculations.formatted(snapshot.memory.usagePercentage, decimals: 0, suffix: "%"),
            cpuText: MetricCalculations.formatted(snapshot.cpuUsage, decimals: 0, suffix: "%"),
            powerSymbolName: powerConfiguration.symbolName,
            powerIconColor: statusRole(from: powerConfiguration.iconColorRole),
            powerTextColor: statusRole(from: powerConfiguration.textColorRole),
            temperatureColor: temperatureColor,
            memoryColor: memoryColor,
            cpuColor: cpuColor
        )
    }
}
