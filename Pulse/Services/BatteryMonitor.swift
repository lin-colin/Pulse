import Foundation
import IOKit
import IOKit.ps

/// 同一刷新周期共享的电源状态，避免 UI 再从本地化字符串反推物理布尔值。
struct PowerSourceSnapshot {
    let isCharging: Bool
    let isPluggedIn: Bool
    let description: String
}

/// 电池监控类
///
/// 负责通过 IOKit 的 IOPowerSources API 获取当前设备的电池及电源连接状态。
public class BatteryMonitor {

    public init() {}

    /// 获取电源信息字典列表
    ///
    /// - Returns: 包含每个电源设备属性字典的数组
    private func fetchPowerSourceDescriptions() -> [[String: Any]] {
        // 1. 获取电源信息快照
        guard let snapshotUnmanaged = IOPSCopyPowerSourcesInfo() else {
            return []
        }
        let snapshot = snapshotUnmanaged.takeRetainedValue()

        // 2. 获取电源列表
        guard let listUnmanaged = IOPSCopyPowerSourcesList(snapshot) else {
            return []
        }
        let sourcesList = listUnmanaged.takeRetainedValue() as [CFTypeRef]

        // 3. 遍历电源列表获取详情字典
        var descriptions: [[String: Any]] = []
        for source in sourcesList {
            if let descriptionUnmanaged = IOPSGetPowerSourceDescription(snapshot, source) {
                let dict = descriptionUnmanaged.takeUnretainedValue() as? [String: Any]
                if let dict = dict {
                    descriptions.append(dict)
                }
            }
        }

        return descriptions
    }

    /// 一次读取并派生全部状态，同一刷新周期不得重复查询 IOKit。
    func getSnapshot() -> PowerSourceSnapshot {
        Self.snapshot(from: fetchPowerSourceDescriptions())
    }

    /// 为什么：纯函数让真实 IOKit 只负责取数，状态矩阵可以无硬件依赖地完整测试。
    static func snapshot(from descriptions: [[String: Any]]) -> PowerSourceSnapshot {
        guard !descriptions.isEmpty else {
            return PowerSourceSnapshot(
                isCharging: false,
                isPluggedIn: false,
                description: "未知"
            )
        }

        let isCharging = descriptions.contains { source in
            (source[kIOPSIsChargingKey] as? Bool)
                ?? (source[kIOPSIsChargingKey] as? NSNumber)?.boolValue
                ?? false
        }
        let isPluggedIn = isCharging || descriptions.contains { source in
            guard let state = source[kIOPSPowerSourceStateKey] as? String else {
                return false
            }
            return state == kIOPSACPowerValue || state == "AC Power"
        }
        let isBatteryPower = descriptions.contains { source in
            guard let state = source[kIOPSPowerSourceStateKey] as? String else {
                return false
            }
            return state == kIOPSBatteryPowerValue || state == "Battery Power"
        }

        let description = isCharging || isPluggedIn || isBatteryPower
            ? powerSourceStateDescription(
                isCharging: isCharging,
                isPluggedIn: isPluggedIn
            )
            : "未知"

        return PowerSourceSnapshot(
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            description: description
        )
    }

}

extension BatteryMonitor {
    /// 为什么：精简电源状态文案为“已连接电源 (未充电)”，减少不必要的“在”字助词，使下拉菜单文本更短更清爽。
    static func powerSourceStateDescription(isCharging: Bool, isPluggedIn: Bool) -> String {
        if isCharging {
            return "正在充电"
        } else if isPluggedIn {
            return "已连接电源 (未充电)"
        } else {
            return "使用电池"
        }
    }
}
