import Foundation

/// 集中定义 Pulse 指标的单位换算、有效性校验和文本格式。
///
/// 这些函数不访问硬件或 UI，确保同一指标在采集层与展示层使用一致规则。
enum MetricCalculations {

    /// 根据页统计计算真实内存使用率，并保留与容量无关的内核压力状态。
    static func memorySnapshot(
        statistics: MemoryPageStatistics?,
        pressureLevel: MemoryPressureLevel
    ) -> MemorySnapshot {
        guard let statistics, statistics.totalBytes > 0 else {
            // 缺失或为零的总容量不能作为有效硬件读数，但仍必须把压力告警传递给展示层。
            return MemorySnapshot(
                usedBytes: nil,
                totalBytes: nil,
                usagePercentage: nil,
                pressureLevel: pressureLevel
            )
        }

        guard statistics.pageSize > 0 else {
            // 页大小无效不影响 hw.memsize 的可信容量，因此只拒绝依赖页大小的使用率计算。
            return MemorySnapshot(
                usedBytes: nil,
                totalBytes: statistics.totalBytes,
                usagePercentage: nil,
                pressureLevel: pressureLevel
            )
        }

        let (availablePages, pageAdditionOverflow) = statistics.freePages.addingReportingOverflow(
            statistics.externalPages
        )
        let (availableBytes, byteMultiplicationOverflow) = availablePages.multipliedReportingOverflow(
            by: statistics.pageSize
        )
        guard !pageAdditionOverflow,
              !byteMultiplicationOverflow,
              availableBytes <= statistics.totalBytes else {
            // 溢出或可用量超过总量代表页统计失真，必须标记不可用而不能伪装为零使用率。
            return MemorySnapshot(
                usedBytes: nil,
                totalBytes: statistics.totalBytes,
                usagePercentage: nil,
                pressureLevel: pressureLevel
            )
        }

        // 仅精确等于总量才表示合法零使用率；其余已验证的输入可安全相减。
        let usedBytes = statistics.totalBytes - availableBytes

        let rawPercentage = Double(usedBytes) / Double(statistics.totalBytes) * 100.0
        // 再次夹紧派生百分比，保证未来数值表示调整也不会突破展示边界。
        let usagePercentage = min(max(rawPercentage, 0.0), 100.0)
        return MemorySnapshot(
            usedBytes: usedBytes,
            totalBytes: statistics.totalBytes,
            usagePercentage: usagePercentage,
            pressureLevel: pressureLevel
        )
    }

    /// 将 AppleSmartBattery 的系统负载从毫瓦转换为瓦。
    static func systemLoadWatts(fromMilliwatts rawValue: Double?) -> Double? {
        guard let rawValue, rawValue.isFinite, rawValue >= 0 else {
            return nil
        }
        return rawValue / 1_000.0
    }

    /// 选择可信的整机功率：PSTR 优先，旧字段仅允许在明确使用电池时回退。
    static func preferredSystemLoadWatts(
        smcWatts: Double?,
        legacyMilliwatts: Double?,
        externalConnected: Bool?
    ) -> Double? {
        if let smcWatts = validatedPowerWatts(smcWatts) {
            return smcWatts
        }

        guard externalConnected == false,
              let legacyMilliwatts,
              legacyMilliwatts.isFinite else {
            return nil
        }
        return validatedPowerWatts(legacyMilliwatts / 1_000.0)
    }

    /// 将 AppleSmartBattery 的物理温度从百分之一摄氏度转换为摄氏度。
    static func batteryTemperatureCelsius(fromCentiDegrees rawValue: Double?) -> Double? {
        guard let rawValue, rawValue.isFinite else {
            return nil
        }

        return validatedTemperatureCelsius(rawValue / 100.0)
    }

    /// 选择可信的电池温度：TB0T 优先，BMS Temperature 作为真实测点回退。
    static func preferredBatteryTemperatureCelsius(
        smcCelsius: Double?,
        bmsCentiDegrees: Double?
    ) -> Double? {
        if let smcCelsius = validatedTemperatureCelsius(smcCelsius) {
            return smcCelsius
        }
        return batteryTemperatureCelsius(fromCentiDegrees: bmsCentiDegrees)
    }

    /// 用二进制 GiB 基数格式化字节数，令内存容量与 macOS 常见读数保持一致。
    static func formattedGigabytes(_ bytes: UInt64?) -> String {
        guard let bytes else {
            return "—"
        }
        return formatted(Double(bytes) / 1_073_741_824.0, decimals: 2, suffix: "GB")
    }

    /// 将可选指标格式化；无值必须明确显示为不可用，而不是伪装成零。
    /// 百分号 (%) 按照方案 B 紧贴数值展示（如 68%），物理单位符号（如 W、°C、GB）与数值间保留单空格（如 5.3 W）。
    static func formatted(_ value: Double?, decimals: Int, suffix: String) -> String {
        guard let value, value.isFinite else {
            return "—"
        }

        let safeDecimals = min(max(decimals, 0), 6)
        let number = String(
            format: "%.\(safeDecimals)f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        if suffix.isEmpty {
            return number
        } else if suffix == "%" {
            // 按照贴合用户阅读习惯的方案 B，百分号紧贴数字展示，不插入多余空格。
            return "\(number)%"
        } else {
            return "\(number) \(suffix)"
        }
    }

    /// 为什么：解决下拉菜单“内存使用 17.40 GB / 24.00 GB (73%)”文案过长导致的向左严重突出问题。
    /// 在同时包含使用量与总容量时，省去首个重复的 GB 单位，输出精简对齐格式 "17.40 / 24.00 GB (73%)"。
    static func formattedMemoryUsageDetail(usedGB: Double?, totalGB: Double? = nil, percentage: Double?) -> String {
        guard let usedGB, usedGB.isFinite else {
            return "—"
        }
        let usedNumStr = formatted(usedGB, decimals: 2, suffix: "")
        guard let percentage, percentage.isFinite else {
            if let totalGB, totalGB.isFinite {
                let totalStr = formatted(totalGB, decimals: 2, suffix: "GB")
                return "\(usedNumStr) / \(totalStr)"
            }
            let usedStr = formatted(usedGB, decimals: 2, suffix: "GB")
            return usedStr
        }
        let percentageStr = formatted(percentage, decimals: 0, suffix: "%")
        if let totalGB, totalGB.isFinite {
            let totalStr = formatted(totalGB, decimals: 2, suffix: "GB")
            return "\(usedNumStr) / \(totalStr) (\(percentageStr))"
        } else {
            let usedStr = formatted(usedGB, decimals: 2, suffix: "GB")
            return "\(usedStr) (\(percentageStr))"
        }
    }

    /// 拒绝损坏或单位错误的系统功率，不对合法值做截断。
    private static func validatedPowerWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0.0...500.0).contains(value) else {
            return nil
        }
        return value
    }

    /// 共用电池温度的有限值与物理范围校验。
    private static func validatedTemperatureCelsius(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (-20.0...100.0).contains(value) else {
            return nil
        }
        return value
    }
}

/// 定义 UI 渲染时的颜色角色分类
enum ColorRole {
    case normal
    case chargingGreen
    case orangeWarning
    case redWarning
}

/// 包含功耗图标名称、图标颜色角色与文本颜色角色的显示配置模型
struct PowerDisplayConfig {
    let symbolName: String
    let iconColorRole: ColorRole
    let textColorRole: ColorRole
}

extension MetricCalculations {
    /// 计算功耗图标与颜色的纯函数，解决充电指示与高功耗告警的色彩解耦
    static func powerDisplayConfiguration(
        power: Double?,
        isCharging: Bool,
        isPluggedIn: Bool
    ) -> PowerDisplayConfig {
        let valueRole: ColorRole
        if let power, power >= 30.0 {
            valueRole = .redWarning
        } else if let power, power >= 18.0 {
            valueRole = .orangeWarning
        } else {
            valueRole = .normal
        }

        if isCharging {
            // 为什么：充电时图标必须恒为绿色以明确表达充电状态，不被高功耗红字混淆
            return PowerDisplayConfig(symbolName: "bolt.fill", iconColorRole: .chargingGreen, textColorRole: valueRole)
        } else if isPluggedIn {
            // 为什么：插电直供/停充时切换为插头图标，表达外接交流电无电池电流
            return PowerDisplayConfig(symbolName: "powerplug.fill", iconColorRole: .normal, textColorRole: valueRole)
        } else {
            // 为什么：电池放电时高耗电需图标与数值同时变色，警示剧烈掉电
            return PowerDisplayConfig(symbolName: "bolt.fill", iconColorRole: valueRole, textColorRole: valueRole)
        }
    }
}

