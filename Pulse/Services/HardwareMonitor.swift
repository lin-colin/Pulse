import Foundation
import IOKit

/// 同一时刻读取到的电池与整机硬件指标。
struct HardwareSnapshot {
    let systemLoadWatts: Double?
    let batteryTemperatureCelsius: Double?
}

/// 硬件传感器读取服务
///
/// 通过只读 AppleSMC 与 AppleSmartBattery 提取系统负载和电池温度。
class HardwareMonitor {
    private let smcReader: SMCReading?
    private let batteryPropertiesReader: () -> [String: Any]?

    /// 默认使用真实硬件源；两个注入点让部分失败与降级策略可独立验证。
    init(
        smcReader: SMCReading? = SMCReader(),
        batteryPropertiesReader: (() -> [String: Any]?)? = nil
    ) {
        self.smcReader = smcReader
        self.batteryPropertiesReader = batteryPropertiesReader
            ?? HardwareMonitor.readBatteryProperties
    }

    /// 读取两类硬件源并生成快照，不在不同更新时间的数据之间执行功率运算。
    func getSnapshot() -> HardwareSnapshot {
        let smc = smcReader?.readSnapshot()
        let smcOnlySnapshot = snapshotFromSMCOnly(smc)

        // 两个 SMC 指标均有效时，AppleSmartBattery 不会提供更优结果；跳过整份
        // IOKit 属性字典可减少每次刷新产生的临时对象与系统调用。
        if smcOnlySnapshot.systemLoadWatts != nil,
            smcOnlySnapshot.batteryTemperatureCelsius != nil
        {
            return smcOnlySnapshot
        }

        guard let props = batteryPropertiesReader() else {
            return smcOnlySnapshot
        }

        // PSTR 是整机主板当前功率；旧 SystemLoad 仅在明确使用电池时安全回退。
        let telemetry = props["PowerTelemetryData"] as? [String: Any]
        let rawSystemLoad = parseDouble(telemetry?["SystemLoad"])
        let externalConnected = parseBool(props["ExternalConnected"])
        let systemLoad = MetricCalculations.preferredSystemLoadWatts(
            smcWatts: smc?.systemPowerWatts,
            legacyMilliwatts: rawSystemLoad,
            externalConnected: externalConnected
        )

        // TB0T 与 AlDente 的电池温度测点一致，BMS Temperature 仅作真实值回退。
        let rawTemperature = parseDouble(props["Temperature"])
        let temperature = MetricCalculations.preferredBatteryTemperatureCelsius(
            smcCelsius: smc?.batteryTemperatureCelsius,
            bmsCentiDegrees: rawTemperature
        )

        return HardwareSnapshot(
            systemLoadWatts: systemLoad,
            batteryTemperatureCelsius: temperature
        )
    }

    // MARK: - Helper

    /// 一次性读取 AppleSmartBattery 属性，失败时交给上层使用 SMC-only 快照。
    private static func readBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer { IOObjectRelease(service) }

        var propsUnmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service,
            &propsUnmanaged,
            kCFAllocatorDefault,
            0
        ) == kIOReturnSuccess else {
            return nil
        }
        return propsUnmanaged?.takeRetainedValue() as? [String: Any]
    }

    /// 电池注册表不可用时仍保留经过范围校验的 SMC 实测值。
    private func snapshotFromSMCOnly(_ smc: SMCSnapshot?) -> HardwareSnapshot {
        HardwareSnapshot(
            systemLoadWatts: MetricCalculations.preferredSystemLoadWatts(
                smcWatts: smc?.systemPowerWatts,
                legacyMilliwatts: nil,
                externalConnected: nil
            ),
            batteryTemperatureCelsius: MetricCalculations.preferredBatteryTemperatureCelsius(
                smcCelsius: smc?.batteryTemperatureCelsius,
                bmsCentiDegrees: nil
            )
        )
    }

    /// 安全解析数字，兼容 NSNumber, Int, Double 等多种 IOKit 数据类型
    private func parseDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        return nil
    }

    /// 安全解析 IOKit 布尔值，避免把未知状态误判为未连接电源。
    private func parseBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}
