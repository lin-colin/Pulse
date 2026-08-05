import Foundation
import IOKit

/// 声明缺少的电池指标需求位掩码
struct BatteryRegistryReadNeeds: OptionSet, Equatable {
    let rawValue: Int
    static let systemLoad = BatteryRegistryReadNeeds(rawValue: 1 << 0)
    static let temperature = BatteryRegistryReadNeeds(rawValue: 1 << 1)
}

/// 电池 Registry 提取的底层数值模型
struct BatteryRegistryMetrics {
    let systemLoadMilliwatts: Double?
    let externalConnected: Bool?
    let temperatureCentiDegrees: Double?
}

/// 电池属性读取器接口
protocol BatteryRegistryReading: AnyObject {
    func readMetrics(needs: BatteryRegistryReadNeeds) -> BatteryRegistryMetrics
}

/// IOKit AppleSmartBattery 属性精读取器
/// 为什么：懒获取并缓存 AppleSmartBattery 服务的 io_service_t 句柄，仅在 SMC 对应 Key 缺失时
/// 显式按需调用 IORegistryEntryCreateCFProperty 提取指定 key（ExternalConnected / PowerTelemetryData / Temperature），
/// 绝对禁止使用 IORegistryEntryCreateCFProperties 复制整份几十 KB 的 IOKit 属性大字典，大幅降低每秒 IOKit 操作开销。
final class AppleSmartBatteryReader: BatteryRegistryReading {
    private var service: io_service_t = IO_OBJECT_NULL

    deinit {
        // 为什么：析构时显式释放 IOKit service 句柄，避免端口引用泄漏。
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            service = IO_OBJECT_NULL
        }
    }

    func readMetrics(needs: BatteryRegistryReadNeeds) -> BatteryRegistryMetrics {
        guard !needs.isEmpty else {
            return BatteryRegistryMetrics(systemLoadMilliwatts: nil, externalConnected: nil, temperatureCentiDegrees: nil)
        }

        var metrics = fetchMetrics(needs: needs)
        if metrics.systemLoadMilliwatts == nil && metrics.temperatureCentiDegrees == nil {
            // service 可能失效，重连重试一次
            resetService()
            metrics = fetchMetrics(needs: needs)
        }
        return metrics
    }

    private func fetchMetrics(needs: BatteryRegistryReadNeeds) -> BatteryRegistryMetrics {
        var systemLoad: Double?
        var externalConnected: Bool?
        var temperature: Double?

        if needs.contains(.systemLoad) {
            if let connected = property(forKey: "ExternalConnected") as? Bool {
                externalConnected = connected
            }
            if let telemetry = property(forKey: "PowerTelemetryData") as? [String: Any],
               let rawLoad = telemetry["SystemLoad"] as? NSNumber {
                systemLoad = rawLoad.doubleValue
            }
        }

        if needs.contains(.temperature) {
            if let rawTemp = property(forKey: "Temperature") as? NSNumber {
                temperature = rawTemp.doubleValue
            }
        }

        return BatteryRegistryMetrics(
            systemLoadMilliwatts: systemLoad,
            externalConnected: externalConnected,
            temperatureCentiDegrees: temperature
        )
    }

    private func property(forKey key: String) -> Any? {
        guard ensureService() else { return nil }
        return IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }

    private func ensureService() -> Bool {
        if service != IO_OBJECT_NULL {
            return true
        }
        service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        return service != IO_OBJECT_NULL
    }

    private func resetService() {
        if service != IO_OBJECT_NULL {
            IOObjectRelease(service)
            service = IO_OBJECT_NULL
        }
    }
}
