import Foundation

/// 同一时刻读取到的电池与整机硬件指标。
struct HardwareSnapshot {
    let systemLoadWatts: Double?
    let batteryTemperatureCelsius: Double?
}

/// 兼容老测试用例的闭包转接适配器
private final class LegacyBatteryPropertiesAdapter: BatteryRegistryReading {
    private let reader: () -> [String: Any]?

    init(reader: @escaping () -> [String: Any]?) {
        self.reader = reader
    }

    func readMetrics(needs: BatteryRegistryReadNeeds) -> BatteryRegistryMetrics {
        guard let props = reader() else {
            return BatteryRegistryMetrics(systemLoadMilliwatts: nil, externalConnected: nil, temperatureCentiDegrees: nil)
        }
        let telemetry = props["PowerTelemetryData"] as? [String: Any]
        let rawLoad = parseDouble(telemetry?["SystemLoad"])
        let externalConnected = parseBool(props["ExternalConnected"])
        let rawTemp = parseDouble(props["Temperature"])

        return BatteryRegistryMetrics(
            systemLoadMilliwatts: needs.contains(.systemLoad) ? rawLoad : nil,
            externalConnected: needs.contains(.systemLoad) ? externalConnected : nil,
            temperatureCentiDegrees: needs.contains(.temperature) ? rawTemp : nil
        )
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        return nil
    }

    private func parseBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}

/// 硬件传感器读取服务
///
/// 通过只读 AppleSMC 与 AppleSmartBattery 精确提取系统负载和电池温度。
class HardwareMonitor {
    private let smcReader: SMCReading?
    private let batteryRegistryReader: BatteryRegistryReading

    /// 提供兼容老接口与依赖注入的双重构造器。
    init(
        smcReader: SMCReading? = SMCReader(),
        batteryPropertiesReader: (() -> [String: Any]?)? = nil
    ) {
        self.smcReader = smcReader
        if let batteryPropertiesReader {
            self.batteryRegistryReader = LegacyBatteryPropertiesAdapter(reader: batteryPropertiesReader)
        } else {
            self.batteryRegistryReader = AppleSmartBatteryReader()
        }
    }

    init(
        smcReader: SMCReading?,
        batteryRegistryReader: BatteryRegistryReading
    ) {
        self.smcReader = smcReader
        self.batteryRegistryReader = batteryRegistryReader
    }

    /// 保持向前兼容的方法名
    func getSnapshot() -> HardwareSnapshot {
        readSnapshot()
    }

    /// 读取两类硬件源并生成快照，按需发起精确属性读取。
    func readSnapshot() -> HardwareSnapshot {
        let smc = smcReader?.readSnapshot()
        var needs = BatteryRegistryReadNeeds()

        // 为什么：只在 SMC 缺失对应指标时精确定向构造 needs，按需提取 IOKit 属性，消除整体字典复制。
        let initialLoad = MetricCalculations.preferredSystemLoadWatts(
            smcWatts: smc?.systemPowerWatts,
            legacyMilliwatts: nil,
            externalConnected: nil
        )
        if initialLoad == nil {
            needs.insert(.systemLoad)
        }

        let initialTemp = MetricCalculations.preferredBatteryTemperatureCelsius(
            smcCelsius: smc?.batteryTemperatureCelsius,
            bmsCentiDegrees: nil
        )
        if initialTemp == nil {
            needs.insert(.temperature)
        }

        if needs.isEmpty {
            return HardwareSnapshot(
                systemLoadWatts: initialLoad,
                batteryTemperatureCelsius: initialTemp
            )
        }

        let batteryMetrics = batteryRegistryReader.readMetrics(needs: needs)

        let finalLoad = MetricCalculations.preferredSystemLoadWatts(
            smcWatts: smc?.systemPowerWatts,
            legacyMilliwatts: batteryMetrics.systemLoadMilliwatts,
            externalConnected: batteryMetrics.externalConnected
        )
        let finalTemp = MetricCalculations.preferredBatteryTemperatureCelsius(
            smcCelsius: smc?.batteryTemperatureCelsius,
            bmsCentiDegrees: batteryMetrics.temperatureCentiDegrees
        )

        return HardwareSnapshot(
            systemLoadWatts: finalLoad,
            batteryTemperatureCelsius: finalTemp
        )
    }
}
