import Darwin
import Foundation
import AppKit
import IOKit.ps

/// 为采集层测试提供确定的部分或完整 SMC 快照。
private final class StubSMCReader: SMCReading {
    private let snapshot: SMCSnapshot

    init(systemPowerWatts: Double?, batteryTemperatureCelsius: Double?) {
        snapshot = SMCSnapshot(
            systemPowerWatts: systemPowerWatts,
            batteryTemperatureCelsius: batteryTemperatureCelsius
        )
    }

    func readSnapshot() -> SMCSnapshot {
        snapshot
    }
}

/// Pulse 指标纯函数测试入口，不依赖 AppKit 或真实硬件状态。
@main
struct MetricCalculationsTests {
    private static var passed = 0
    private static var failed = 0

    static func main() {
        _ = NSApplication.shared
        testSystemLoadConversion()
        testBatteryTemperatureConversion()
        testPreferredSystemLoad()
        testPreferredBatteryTemperature()
        testSMCValueDecoding()
        testSMCABILayout()
        testSMCResponseValidation()
        testHardwareMonitorSourceIntegration()
        // 以内核压力级别替代伪造的“压力百分比”，避免继续把可用内存比例误报为压力。
        testMemoryPressureLevelMapping()
        // 单独验证内存使用率的页统计计算，确保其与压力状态解耦。
        testMemoryUsageCalculation()
        // 以可控时钟和读取器锁定采集层的初始化、事件更新与低频重同步语义。
        testMemoryMonitorInitialSnapshotAndResync()
        // 单调时间倒退时必须主动校验，避免未来时间戳让旧状态长期失效。
        testMemoryMonitorClockRollback()
        // 首次读取失败后仍允许系统事件恢复为可信状态。
        testMemoryMonitorInitialFailureAndEventRecovery()
        // 短暂重同步失败不得清除已经由内核事件确认的压力状态。
        testMemoryMonitorResyncFailureRetention()
        // VM 页统计失败与压力状态彼此独立，避免部分故障污染另一指标。
        testMemoryMonitorStatisticsFailurePreservesPressure()
        // 无效及合并事件必须遵循忽略未知值和最严重状态优先的规则。
        testMemoryMonitorEventValidation()
        // 阻塞重同步期间事件与后续快照都必须保持响应，并防止旧结果覆盖新事件。
        testMemoryMonitorConcurrentResyncPreservesNewerEvent()
        // reader 可重入事件入口用于证明任何注入 closure 都不会在状态锁内执行。
        testMemoryMonitorReentrantPressureReader()
        // 默认事件时钟也允许同步回调监控器，证明时钟读取发生在加锁之前。
        testMemoryMonitorReentrantEventUptimeReader()
        testMetricFormatting()
        testFormattedMemoryUsageText()
        // 为什么：CPU 每秒读取必须平衡 host port 发送权，否则长期运行会累积引用。
        testCPUUsageBalancesHostPortSendRight()
        // 为什么：标称频率是稳定硬件属性，不应在每次刷新重复 sysctl。
        testCPUFrequencyReaderRunsOnce()
        // 为什么：状态栏展示模型必须准确表达指标与阈值，且 Icon 与 Value 颜色保持独立。
        testStatusItemRenderModelUsesSnapshotAndThresholds()
        testChargingPowerIconAndValueKeepIndependentColors()
        testStatusItemRenderModelEqualitySupportsDeduplication()
        // 为什么：完全相同的显示状态不得重复调用 CoreGraphics 栅格化绘制。
        testStatusBarControllerDeduplicatesIdenticalSnapshots()
        // 为什么：阈值配置只在有效解析时通过回调更新，禁止热路径频繁查询 UserDefaults。
        testThresholdConfigCallbackUpdatesMemoryAndRerenders()
        // 为什么：详情面板按需创建并在关闭后销毁，离线不更新面板以降低常驻开销。
        testStatusBarControllerPanelSessionLifecycle()
        // 为什么：折叠面板必须完整容纳第三个控制行与退出行，禁止再次被错误固定高度裁切。
        testPanelSessionShowsAllCollapsedRows()
        // 为什么：高级设置行只在第一次展开时创建，避免面板初始化构建全量隐藏视图。
        testPopoverContentViewLazySettingsRows()
        // 为什么：折叠动画期间内部卡片必须由窗口当前高度驱动，不能先于外框跳到终点。
        testPopoverSettingsCollapseTracksAnimatedHeight()
        // 为什么：只在 SMC 缺失具体指标时精确读取电池对应属性，禁止无条件复制完整 IOKit 字典。
        testHardwareMonitorPreciseBatteryReadNeeds()
        testDefaultRefreshInterval()
        testRefreshIntervalValidation()
        // 验证展示语义，让颜色/可用性只由真实压力状态决定。
        testMemoryPresentationRole()
        // 验证电源指示与功耗告警的色彩与图标解耦。
        testPowerDisplayConfigurationCharging()
        testPowerDisplayConfigurationPluggedInPassThrough()
        testPowerDisplayConfigurationDischarging()
        // 为什么：电源状态精准文案映射与快照推导断言。
        testPowerSourceStateDescription()
        testPowerSourceSnapshotDerivation()
        // 为什么：控制器必须使用抽象的 StatusItemHosting 运行在测试环境。
        testStatusBarControllerUsesStatusItemHost()
        // 为什么：未挂接状态项时绝不生成错色位图，等到挂接至托管窗口才触发真实渲染。
        testFirstVisibleRenderWaitsForHostedAppearance()
        // 为什么：本地点击过滤排查状态栏锚点窗口，连续四击严格交替 open/closed。
        testPanelSessionLocalClickFiltering()
        testStatusBarControllerFourClicksAlternatingToggle()
        testPulseSnapshotKeepsOneRefreshState()
        testRefreshControlUsesNativeSelectionAndHoverState()
        testPopoverContentUpdatesExistingMetricLabels()
        testPopoverGroupsAndRowsShareHorizontalGeometry()
        testPopoverUsesSystemWindowAndSharedGroupColors()
        testPopoverLaunchSwitchReflectsActualState()
        testPopoverQuitButtonForwardsAction()
        testLaunchAtLoginFailureRestoresDisplayedState()
        // 为什么：开机启动失败更新开关真实状态，阈值配置使用注入单一来源。
        testLaunchAtLoginFailureUpdatesPanelSwitchState()
        testPanelSessionInjectsThresholdConfigWithoutUserDefaultLoad()
        // 为什么：初始化阶段系统状态项外观必须首帧保底为 darkAqua，防止黑字。
        testSystemStatusItemHostDarkAquaFallback()
        // 为什么：打开高亮必须等按钮跟踪周期结束，关闭则必须立即恢复。
        testStatusItemHighlightCoordinatorDefersOpeningAndClosesImmediately()
        // 为什么：快速关闭后，排队中的旧打开任务不得重新点亮状态栏按钮。
        testStatusItemHighlightCoordinatorRejectsStaleOpening()
        // 为什么：面板显示失败必须完整回滚状态栏高亮与期望状态。
        testStatusBarControllerRollsBackFailedPanelShow()
        // 为什么：关闭点击必须在动画完成前立即移除高亮。
        testStatusBarControllerUnhighlightsBeforeCloseAnimationCompletes()
        // 为什么：外部关闭必须统一经过期望状态控制。
        testStatusBarControllerRoutesExternalDismissThroughDesiredState()
        // 为什么：过期的 Session 关闭完成回调不得销毁新的打开状态。
        testStatusBarControllerIgnoresStaleSessionCompletion()
        // 为什么：状态栏图标左右内边距必须保持 5.0 pt 100% 对称，消除右侧过宽留白。
        testStatusItemRendererLeftAndRightInsetsAreSymmetrical()
        // 为什么：更多设置必须收拢为 188pt 矩阵结构，包含 1 个 Header、3 个指标配置行、1 个内存说明行与 1 个更新行。
        testPopoverThresholdMatrixStructure()
        // 为什么：更多设置必须遵循精确的 188pt 几何布局与绝对位置。
        testPopoverThresholdMatrixGeometry()
        // 为什么：所有 6 个阈值输入框必须具备完整的 Accessibility 语义标签与 Matrix Tab Order 链条。
        testPopoverThresholdMatrixAccessibilityAndKeyboardOrder()
        // 为什么：配置行必须进行 1pt 光学基线平齐微调，底部分割线必须隔离配置区，检查更新具备 Loading 状态。
        testPopoverOpticalAlignmentAndUpdateLoadingState()
        // 为什么：面板 Session 必须在多次 toggle 循环中被常驻复用，封顶内存占用，消除对象频繁销毁与重复创建开销。
        testPanelSessionReusedAcrossToggleCycles()
        // 为什么：系统内存压力到达且面板隐藏时，必须销毁 Session 协助系统回落至极低内存。
        testMemoryPressureDestroysHiddenPanelSession()
        // 为什么：连续 100 次面板打开/关闭压测，物理内存 (RSS) 增量必须低于 1.0 MB，实证无累积泄露。
        testPanelSessionMemoryLeakBenchmark()
        // 为什么：顶部 6 项指标必须以 2x3 网格矩阵展现，且所有 6 个卡片统一固定为 58.0 pt 100% 绝对等高。
        testPopoverMetricCardGridGeometry()
        // 为什么：检查更新取消外部弹窗，全在底栏内无缝呈现内嵌交互状态。
        testPopoverInlineUpdateStateTransitions()
        testPopoverMetricValuesUseLabelColor()
        // 运行全功能与 A1 硬件口径回归测试断言集。
        testFullFeatureAndRegressionSuite()

        if failed > 0 {
            fputs("FAILED: \(failed) failed, \(passed) passed\n", stderr)
            exit(1)
        }

        print("PASSED: \(passed) assertions")
    }

    /// 验证系统负载只接受非负有限毫瓦值。
    private static func testSystemLoadConversion() {
        expectEqual(
            MetricCalculations.systemLoadWatts(fromMilliwatts: 5_270),
            5.27,
            "5270mW should convert to 5.27W"
        )
        expectEqual(
            MetricCalculations.systemLoadWatts(fromMilliwatts: 0),
            0,
            "zero system load should remain valid"
        )
        expectNil(
            MetricCalculations.systemLoadWatts(fromMilliwatts: -1),
            "negative system load should be invalid"
        )
        expectNil(
            MetricCalculations.systemLoadWatts(fromMilliwatts: .infinity),
            "infinite system load should be invalid"
        )
        expectNil(
            MetricCalculations.systemLoadWatts(fromMilliwatts: nil),
            "missing system load should remain unavailable"
        )
    }

    /// 验证物理电池温度单位和合理范围。
    private static func testBatteryTemperatureConversion() {
        expectEqual(
            MetricCalculations.batteryTemperatureCelsius(fromCentiDegrees: 3_100),
            31,
            "3100 centi-degrees should convert to 31C"
        )
        expectEqual(
            MetricCalculations.batteryTemperatureCelsius(fromCentiDegrees: -2_000),
            -20,
            "lower temperature boundary should be valid"
        )
        expectEqual(
            MetricCalculations.batteryTemperatureCelsius(fromCentiDegrees: 10_000),
            100,
            "upper temperature boundary should be valid"
        )
        expectNil(
            MetricCalculations.batteryTemperatureCelsius(fromCentiDegrees: -2_001),
            "temperature below the physical range should be invalid"
        )
        expectNil(
            MetricCalculations.batteryTemperatureCelsius(fromCentiDegrees: 10_001),
            "temperature above the physical range should be invalid"
        )
        expectNil(
            MetricCalculations.batteryTemperatureCelsius(fromCentiDegrees: .nan),
            "NaN temperature should be invalid"
        )
    }

    /// 验证系统负载始终优先使用 PSTR，并禁止充电状态回退到错误的旧字段。
    private static func testPreferredSystemLoad() {
        expectEqual(
            MetricCalculations.preferredSystemLoadWatts(
                smcWatts: 9.148,
                legacyMilliwatts: 79_283,
                externalConnected: true
            ),
            9.148,
            "PSTR should override the charging-invalid legacy SystemLoad"
        )
        expectNil(
            MetricCalculations.preferredSystemLoadWatts(
                smcWatts: nil,
                legacyMilliwatts: 79_283,
                externalConnected: true
            ),
            "external power must not fall back to the legacy SystemLoad"
        )
        expectEqual(
            MetricCalculations.preferredSystemLoadWatts(
                smcWatts: nil,
                legacyMilliwatts: 6_349,
                externalConnected: false
            ),
            6.349,
            "battery power may use the validated legacy fallback"
        )
        expectNil(
            MetricCalculations.preferredSystemLoadWatts(
                smcWatts: nil,
                legacyMilliwatts: 6_349,
                externalConnected: nil
            ),
            "unknown power state must not guess from the legacy field"
        )
        expectNil(
            MetricCalculations.preferredSystemLoadWatts(
                smcWatts: 501,
                legacyMilliwatts: 6_349,
                externalConnected: true
            ),
            "an invalid PSTR value must not unlock the AC fallback"
        )
        for invalidPower in [Double.nan, Double.infinity, -0.1] {
            expectNil(
                MetricCalculations.preferredSystemLoadWatts(
                    smcWatts: invalidPower,
                    legacyMilliwatts: 6_349,
                    externalConnected: true
                ),
                "non-finite and negative PSTR values must be rejected"
            )
        }
    }

    /// 验证电池温度优先采用 TB0T，并在其不可用时回退到 BMS 物理温度。
    private static func testPreferredBatteryTemperature() {
        expectEqual(
            MetricCalculations.preferredBatteryTemperatureCelsius(
                smcCelsius: 32.8,
                bmsCentiDegrees: 3_060
            ),
            32.8,
            "TB0T should be the primary battery temperature"
        )
        expectEqual(
            MetricCalculations.preferredBatteryTemperatureCelsius(
                smcCelsius: nil,
                bmsCentiDegrees: 3_060
            ),
            30.6,
            "BMS temperature should remain a truthful fallback"
        )
        expectEqual(
            MetricCalculations.preferredBatteryTemperatureCelsius(
                smcCelsius: 101,
                bmsCentiDegrees: 3_060
            ),
            30.6,
            "an invalid TB0T value should use the BMS fallback"
        )
        expectNil(
            MetricCalculations.preferredBatteryTemperatureCelsius(
                smcCelsius: .nan,
                bmsCentiDegrees: nil
            ),
            "invalid and missing temperature sources should remain unavailable"
        )
    }

    /// 验证 PSTR 的 flt 与 TB0T 的 sp78 按各自字节序正确解码。
    private static func testSMCValueDecoding() {
        expectEqual(
            SMCValueDecoder.decode(
                dataType: SMCValueDecoder.floatDataType,
                bytes: [0x00, 0x00, 0xF4, 0x40]
            ),
            7.625,
            "little-endian flt bytes should decode to watts"
        )
        expectEqual(
            SMCValueDecoder.decode(
                dataType: SMCValueDecoder.sp78DataType,
                bytes: [0x20, 0xC0]
            ),
            32.75,
            "big-endian sp78 bytes should decode to Celsius"
        )
        expectEqual(
            SMCValueDecoder.decode(
                dataType: SMCValueDecoder.sp78DataType,
                bytes: [0xFE, 0x80]
            ),
            -1.5,
            "signed sp78 bytes should preserve negative values"
        )
        expectNil(
            SMCValueDecoder.decode(
                dataType: SMCValueDecoder.floatDataType,
                bytes: [0x00, 0x00]
            ),
            "short flt payloads should be rejected"
        )
        expectNil(
            SMCValueDecoder.decode(dataType: 0, bytes: [0, 0, 0, 0]),
            "unknown SMC data types should be rejected"
        )
        expectNil(
            SMCValueDecoder.decode(
                dataType: SMCValueDecoder.floatDataType,
                bytes: [0x00, 0x00, 0xF4, 0x40, 0x00]
            ),
            "oversized flt payloads should be rejected"
        )
        expectNil(
            SMCValueDecoder.decode(
                dataType: SMCValueDecoder.sp78DataType,
                bytes: [0x20, 0xC0, 0x00]
            ),
            "oversized sp78 payloads should be rejected"
        )
    }

    /// 防止 Swift 复用 C 结构尾部填充，导致 AppleSMC 用户客户端拒绝请求。
    private static func testSMCABILayout() {
        expectEqual(
            Double(SMCReader.abiKeyDataStride),
            80,
            "SMCKeyData must retain the 80-byte C ABI layout"
        )
        let offsets = SMCReader.abiFieldOffsets
        expectEqual(Double(offsets["pLimitData"] ?? -1), 12, "pLimitData offset must match C")
        expectEqual(Double(offsets["keyInfo"] ?? -1), 28, "keyInfo offset must match C")
        expectEqual(Double(offsets["result"] ?? -1), 40, "result offset must match C")
        expectEqual(Double(offsets["data8"] ?? -1), 42, "data8 offset must match C")
        expectEqual(Double(offsets["data32"] ?? -1), 44, "data32 offset must match C")
        expectEqual(Double(offsets["bytes"] ?? -1), 48, "bytes offset must match C")
    }

    /// 区分 IOKit 外层成功与 SMC 命令级成功，避免失败载荷被解码为零。
    private static func testSMCResponseValidation() {
        expectTrue(
            SMCReader.isSuccessfulResponse(
                kernelResult: KERN_SUCCESS,
                protocolResult: 0,
                outputSize: 80
            ),
            "a complete successful SMC response should be accepted"
        )
        expectFalse(
            SMCReader.isSuccessfulResponse(
                kernelResult: KERN_SUCCESS,
                protocolResult: 1,
                outputSize: 80
            ),
            "an SMC protocol error must be rejected even when IOKit succeeds"
        )
        expectFalse(
            SMCReader.isSuccessfulResponse(
                kernelResult: KERN_SUCCESS,
                protocolResult: 0,
                outputSize: 79
            ),
            "a truncated SMC response must be rejected"
        )
        expectFalse(
            SMCReader.isSuccessfulResponse(
                kernelResult: KERN_FAILURE,
                protocolResult: 0,
                outputSize: 80
            ),
            "an IOKit transport failure must be rejected"
        )
    }

    /// 验证采集层在完整、部分和失败数据源下执行相同的安全降级策略。
    private static func testHardwareMonitorSourceIntegration() {
        let chargingProperties: [String: Any] = [
            "ExternalConnected": true,
            "Temperature": 3_060,
            "PowerTelemetryData": ["SystemLoad": 79_283]
        ]
        var primaryBatteryReadCount = 0
        let primaryMonitor = HardwareMonitor(
            smcReader: StubSMCReader(
                systemPowerWatts: 9.148,
                batteryTemperatureCelsius: 32.8
            ),
            batteryPropertiesReader: {
                primaryBatteryReadCount += 1
                return chargingProperties
            }
        )
        let primary = primaryMonitor.getSnapshot()
        expectEqual(primary.systemLoadWatts, 9.148, "HardwareMonitor should select PSTR")
        expectEqual(
            primary.batteryTemperatureCelsius,
            32.8,
            "HardwareMonitor should select TB0T"
        )
        expectEqual(
            Double(primaryBatteryReadCount),
            0,
            "valid SMC metrics should skip the AppleSmartBattery dictionary read"
        )

        let temperatureOnlyMonitor = HardwareMonitor(
            smcReader: StubSMCReader(
                systemPowerWatts: nil,
                batteryTemperatureCelsius: 32.8
            ),
            batteryPropertiesReader: { chargingProperties }
        )
        let temperatureOnly = temperatureOnlyMonitor.getSnapshot()
        expectNil(
            temperatureOnly.systemLoadWatts,
            "a failed PSTR read on AC must not expose legacy SystemLoad"
        )
        expectEqual(
            temperatureOnly.batteryTemperatureCelsius,
            32.8,
            "a valid TB0T value should survive a PSTR failure"
        )

        let powerOnlyMonitor = HardwareMonitor(
            smcReader: StubSMCReader(
                systemPowerWatts: 8.5,
                batteryTemperatureCelsius: nil
            ),
            batteryPropertiesReader: { chargingProperties }
        )
        let powerOnly = powerOnlyMonitor.getSnapshot()
        expectEqual(
            powerOnly.systemLoadWatts,
            8.5,
            "a valid PSTR value should survive a TB0T failure"
        )
        expectEqual(
            powerOnly.batteryTemperatureCelsius,
            30.6,
            "a failed TB0T read should use the BMS temperature"
        )

        let unavailableSMCMonitor = HardwareMonitor(
            smcReader: nil,
            batteryPropertiesReader: { chargingProperties }
        )
        let unavailableSMC = unavailableSMCMonitor.getSnapshot()
        expectNil(
            unavailableSMC.systemLoadWatts,
            "an unavailable SMC connection on AC must remain unavailable"
        )
        expectEqual(
            unavailableSMC.batteryTemperatureCelsius,
            30.6,
            "an unavailable SMC connection should retain the BMS temperature"
        )

        let batteryMonitor = HardwareMonitor(
            smcReader: nil,
            batteryPropertiesReader: {
                [
                    "ExternalConnected": false,
                    "PowerTelemetryData": ["SystemLoad": 6_349]
                ]
            }
        )
        expectEqual(
            batteryMonitor.getSnapshot().systemLoadWatts,
            6.349,
            "battery power should retain the validated legacy fallback"
        )

        let malformedMonitor = HardwareMonitor(
            smcReader: nil,
            batteryPropertiesReader: {
                [
                    "ExternalConnected": "unknown",
                    "Temperature": "invalid",
                    "PowerTelemetryData": ["SystemLoad": "invalid"]
                ]
            }
        )
        let malformed = malformedMonitor.getSnapshot()
        expectNil(malformed.systemLoadWatts, "malformed power properties should be unavailable")
        expectNil(
            malformed.batteryTemperatureCelsius,
            "malformed temperature properties should be unavailable"
        )
    }

    /// 验证内核返回值只映射已知压力级别，防止未知协议值被误判为健康状态。
    private static func testMemoryPressureLevelMapping() {
        expectTrue(
            MemoryPressureLevel(rawKernelValue: 1) == .normal,
            "kernel value 1 should map to normal memory pressure"
        )
        expectTrue(
            MemoryPressureLevel(rawKernelValue: 2) == .warning,
            "kernel value 2 should map to warning memory pressure"
        )
        expectTrue(
            MemoryPressureLevel(rawKernelValue: 4) == .critical,
            "kernel value 4 should map to critical memory pressure"
        )
        expectTrue(
            MemoryPressureLevel(rawKernelValue: 3) == .unavailable,
            "unknown kernel values should remain unavailable"
        )
        expectTrue(
            MemoryPressureLevel(rawKernelValue: nil) == .unavailable,
            "missing kernel values should remain unavailable"
        )
    }

    /// 验证页统计计算与压力状态独立，并将无效页统计明确标记为不可用而非零使用率。
    private static func testMemoryUsageCalculation() {
        let snapshot = MetricCalculations.memorySnapshot(
            statistics: MemoryPageStatistics(
                totalBytes: 24 * 1_073_741_824,
                pageSize: 16_384,
                freePages: 6_554,
                externalPages: 262_144
            ),
            pressureLevel: .normal
        )
        expectEqual(
            snapshot.usagePercentage,
            82.92,
            "24GiB page statistics should produce about 82.92 percent usage",
            tolerance: 0.01
        )
        expectTrue(
            snapshot.usedBytes != nil && snapshot.usedBytes! <= 24 * 1_073_741_824,
            "used bytes should not exceed total memory"
        )
        expectTrue(snapshot.pressureLevel == .normal, "usage calculation should retain pressure")

        let additionOverflowSnapshot = MetricCalculations.memorySnapshot(
            statistics: MemoryPageStatistics(
                totalBytes: 24 * 1_073_741_824,
                pageSize: 16_384,
                freePages: UInt64.max,
                externalPages: 1
            ),
            pressureLevel: .warning
        )
        expectTrue(
            additionOverflowSnapshot.usedBytes == nil,
            "overflowing available page addition should leave used bytes unavailable"
        )
        expectNil(
            additionOverflowSnapshot.usagePercentage,
            "overflowing available page addition should leave usage unavailable"
        )
        expectTrue(
            additionOverflowSnapshot.totalBytes == 24 * 1_073_741_824,
            "invalid page counts should retain the valid hardware memory total"
        )
        expectTrue(
            additionOverflowSnapshot.pressureLevel == .warning,
            "invalid page counts should retain the independent pressure state"
        )

        let multiplicationOverflowSnapshot = MetricCalculations.memorySnapshot(
            statistics: MemoryPageStatistics(
                totalBytes: 24 * 1_073_741_824,
                pageSize: UInt64.max,
                freePages: 2,
                externalPages: 0
            ),
            pressureLevel: .warning
        )
        expectTrue(
            multiplicationOverflowSnapshot.usedBytes == nil,
            "overflowing available byte conversion should leave used bytes unavailable"
        )
        expectNil(
            multiplicationOverflowSnapshot.usagePercentage,
            "overflowing available byte conversion should leave usage unavailable"
        )

        let exceedsTotalSnapshot = MetricCalculations.memorySnapshot(
            statistics: MemoryPageStatistics(
                totalBytes: 100,
                pageSize: 10,
                freePages: 11,
                externalPages: 0
            ),
            pressureLevel: .warning
        )
        expectTrue(
            exceedsTotalSnapshot.usedBytes == nil,
            "available bytes above total memory should leave used bytes unavailable"
        )
        expectNil(
            exceedsTotalSnapshot.usagePercentage,
            "available bytes above total memory should leave usage unavailable"
        )

        let fullyAvailableSnapshot = MetricCalculations.memorySnapshot(
            statistics: MemoryPageStatistics(
                totalBytes: 100,
                pageSize: 10,
                freePages: 10,
                externalPages: 0
            ),
            pressureLevel: .normal
        )
        expectEqual(
            fullyAvailableSnapshot.usedBytes.map(Double.init),
            0,
            "available bytes equal to total memory should be a valid zero usage value"
        )
        expectEqual(
            fullyAvailableSnapshot.usagePercentage,
            0,
            "available bytes equal to total memory should be a valid zero percentage"
        )

        let zeroTotalSnapshot = MetricCalculations.memorySnapshot(
            statistics: MemoryPageStatistics(
                totalBytes: 0,
                pageSize: 10,
                freePages: 0,
                externalPages: 0
            ),
            pressureLevel: .critical
        )
        expectTrue(
            zeroTotalSnapshot.totalBytes == nil && zeroTotalSnapshot.usedBytes == nil,
            "a zero memory total should not be exposed as a valid capacity or usage"
        )
        expectNil(
            zeroTotalSnapshot.usagePercentage,
            "a zero memory total should leave usage unavailable"
        )

        let zeroPageSizeSnapshot = MetricCalculations.memorySnapshot(
            statistics: MemoryPageStatistics(
                totalBytes: 100,
                pageSize: 0,
                freePages: 0,
                externalPages: 0
            ),
            pressureLevel: .critical
        )
        expectTrue(
            zeroPageSizeSnapshot.totalBytes == 100,
            "an invalid page size should retain the valid hardware memory total"
        )
        expectTrue(
            zeroPageSizeSnapshot.usedBytes == nil,
            "an invalid page size should leave used bytes unavailable"
        )
        expectNil(
            zeroPageSizeSnapshot.usagePercentage,
            "an invalid page size should leave usage unavailable"
        )
        expectTrue(
            zeroPageSizeSnapshot.pressureLevel == .critical,
            "an invalid page size should retain the independent pressure state"
        )

        let unavailableUsage = MetricCalculations.memorySnapshot(
            statistics: nil,
            pressureLevel: .critical
        )
        expectNil(
            unavailableUsage.usagePercentage,
            "missing page statistics should leave usage unavailable"
        )
        expectTrue(
            unavailableUsage.pressureLevel == .critical,
            "missing page statistics should retain a critical pressure state"
        )
        expectEqual(
            MetricCalculations.formattedGigabytes(2 * 1_073_741_824),
            "2.00 GB",
            "gigabyte formatting should use binary units with two decimals"
        )
        expectEqual(
            MetricCalculations.formattedGigabytes(nil),
            "—",
            "missing gigabytes should remain unavailable"
        )
    }

    /// 验证初始 sysctl、逐次 VM 读取、即时事件和三十秒边界重同步能协同工作。
    private static func testMemoryMonitorInitialSnapshotAndResync() {
        var statisticsReads = 0
        var pressureReads = 0
        let baseUptime: TimeInterval = 1_000
        let monitor = SystemMonitor(
            memoryStatisticsReader: {
                // 统计读取次数是为了证明每个快照都采集 VM 数据，而不是复用旧使用率。
                statisticsReads += 1
                return MemoryPageStatistics(
                    totalBytes: 1_000,
                    pageSize: 1,
                    freePages: 100,
                    externalPages: 200
                )
            },
            pressureLevelReader: {
                // 第一次提供初始化告警，第二次提供重同步后的正常状态。
                pressureReads += 1
                return pressureReads == 1 ? 0x02 : 0x01
            },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        let initial = monitor.getMemorySnapshot(nowUptime: baseUptime)
        expectEqual(initial.usagePercentage, 70, "usage should come from VM statistics")
        expectTrue(initial.pressureLevel == .warning, "initial sysctl state should be warning")
        expectEqual(Double(pressureReads), 1, "initialization should read sysctl exactly once")

        let oneSecondLater = monitor.getMemorySnapshot(nowUptime: baseUptime + 1)
        expectTrue(
            oneSecondLater.pressureLevel == .warning,
            "a fresh pressure cache should retain the initial warning"
        )
        expectEqual(Double(pressureReads), 1, "one-second refreshes should not repoll sysctl")

        monitor.recordMemoryPressureEvent(rawValue: 0x04, nowUptime: baseUptime + 1)
        let eventUpdated = monitor.getMemorySnapshot(nowUptime: baseUptime + 1)
        expectTrue(
            eventUpdated.pressureLevel == .critical,
            "a critical event should update the cached level immediately"
        )
        expectEqual(Double(pressureReads), 1, "an event update should not invoke sysctl")

        let resynchronized = monitor.getMemorySnapshot(
            nowUptime: baseUptime + 1 + PulseDefaults.memoryPressureResyncInterval
        )
        expectTrue(
            resynchronized.pressureLevel == .normal,
            "the exact resync boundary should repair a missed normal event"
        )
        expectEqual(Double(pressureReads), 2, "the resync boundary should reread sysctl")
        expectEqual(Double(statisticsReads), 4, "every snapshot should reread VM statistics")
    }

    /// 验证时钟倒退会触发安全重读，而不是把负时间差误判成仍在缓存期内。
    private static func testMemoryMonitorClockRollback() {
        var pressureReads = 0
        let baseUptime: TimeInterval = 2_000
        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: {
                // 倒退前返回警告，倒退后的安全重读返回正常以便观察行为。
                pressureReads += 1
                return pressureReads == 1 ? 0x02 : 0x01
            },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        let rolledBack = monitor.getMemorySnapshot(nowUptime: baseUptime - 1)
        expectTrue(
            rolledBack.pressureLevel == .normal,
            "a negative elapsed time should force a safe pressure reread"
        )
        expectEqual(Double(pressureReads), 2, "clock rollback should trigger exactly one reread")
    }

    /// 验证首次 sysctl 失败诚实显示不可用，同时后续 Dispatch 事件可以恢复状态。
    private static func testMemoryMonitorInitialFailureAndEventRecovery() {
        var pressureReads = 0
        let baseUptime: TimeInterval = 3_000
        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: {
                // 持续失败用于证明恢复只来自事件，而不是隐藏的再次轮询。
                pressureReads += 1
                return nil
            },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        let unavailable = monitor.getMemorySnapshot(nowUptime: baseUptime)
        expectTrue(
            unavailable.pressureLevel == .unavailable,
            "a first sysctl failure should remain explicitly unavailable"
        )
        monitor.recordMemoryPressureEvent(rawValue: 0x02, nowUptime: baseUptime + 1)
        let recovered = monitor.getMemorySnapshot(nowUptime: baseUptime + 1)
        expectTrue(
            recovered.pressureLevel == .warning,
            "a valid event should recover an initially unavailable state"
        )
        expectEqual(Double(pressureReads), 1, "event recovery should not cause an early sysctl retry")
    }

    /// 验证定期 sysctl 暂时失败时仍保留最近的有效事件，避免告警闪回不可用。
    private static func testMemoryMonitorResyncFailureRetention() {
        var pressureReads = 0
        let baseUptime: TimeInterval = 4_000
        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: {
                // 初始化正常，边界重同步失败，用于验证最后可信值的保留策略。
                pressureReads += 1
                return pressureReads == 1 ? 0x01 : nil
            },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        monitor.recordMemoryPressureEvent(rawValue: 0x04, nowUptime: baseUptime + 1)
        let retained = monitor.getMemorySnapshot(
            nowUptime: baseUptime + 1 + PulseDefaults.memoryPressureResyncInterval
        )
        expectTrue(
            retained.pressureLevel == .critical,
            "a failed resync should retain the last trusted event"
        )
        expectEqual(Double(pressureReads), 2, "a failed boundary read should still count as a resync")

        let shortlyAfterFailure = monitor.getMemorySnapshot(
            nowUptime: baseUptime + 2 + PulseDefaults.memoryPressureResyncInterval
        )
        expectTrue(
            shortlyAfterFailure.pressureLevel == .critical,
            "a retained trusted event should survive until the next resync window"
        )
        expectEqual(
            Double(pressureReads),
            2,
            "a failed resync should advance its timestamp to prevent one-second polling"
        )
    }

    /// 验证 VM 统计缺失只让使用量不可用，不会抹掉独立取得的压力告警。
    private static func testMemoryMonitorStatisticsFailurePreservesPressure() {
        let baseUptime: TimeInterval = 5_000
        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: { 0x02 },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        let snapshot = monitor.getMemorySnapshot(nowUptime: baseUptime)
        expectNil(snapshot.usagePercentage, "missing VM statistics should leave usage unavailable")
        expectTrue(snapshot.totalBytes == nil, "missing VM statistics should leave total unavailable")
        expectTrue(
            snapshot.pressureLevel == .warning,
            "missing VM statistics should preserve the independent warning level"
        )
    }

    /// 验证未知事件不改变状态，并让多位合并事件始终选择最严重的有效级别。
    private static func testMemoryMonitorEventValidation() {
        let baseUptime: TimeInterval = 6_000
        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: { 0x01 },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        monitor.recordMemoryPressureEvent(rawValue: 0x08, nowUptime: baseUptime + 1)
        let unchanged = monitor.getMemorySnapshot(nowUptime: baseUptime + 1)
        expectTrue(
            unchanged.pressureLevel == .normal,
            "an event without known pressure bits should not change cached state"
        )

        monitor.recordMemoryPressureEvent(rawValue: 0x01 | 0x02, nowUptime: baseUptime + 2)
        let warningWins = monitor.getMemorySnapshot(nowUptime: baseUptime + 2)
        expectTrue(
            warningWins.pressureLevel == .warning,
            "warning should outrank normal in a merged event"
        )

        monitor.recordMemoryPressureEvent(rawValue: 0x01 | 0x02 | 0x04, nowUptime: baseUptime + 3)
        let criticalWins = monitor.getMemorySnapshot(nowUptime: baseUptime + 3)
        expectTrue(
            criticalWins.pressureLevel == .critical,
            "critical should outrank warning and normal in a merged event"
        )
    }

    /// 验证单次阻塞重同步不会阻塞事件或重复启动读取，旧结果也不能覆盖较新事件。
    private static func testMemoryMonitorConcurrentResyncPreservesNewerEvent() {
        let baseUptime: TimeInterval = 7_000
        let readerStarted = DispatchSemaphore(value: 0)
        let releaseReader = DispatchSemaphore(value: 0)
        let resyncFinished = DispatchSemaphore(value: 0)
        let followerStarted = DispatchSemaphore(value: 0)
        let followerFinished = DispatchSemaphore(value: 0)
        let eventStarted = DispatchSemaphore(value: 0)
        let eventFinished = DispatchSemaphore(value: 0)
        let readCountLock = NSLock()
        var pressureReads = 0

        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: {
                // 只阻塞第二次读取，让初始化正常完成并精确控制重同步竞争窗口。
                readCountLock.lock()
                pressureReads += 1
                let currentRead = pressureReads
                readCountLock.unlock()
                if currentRead == 2 {
                    readerStarted.signal()
                    // 兜底上限必须长于主线程的锁阻塞判定窗口，避免错误实现自行解锁后假通过。
                    _ = releaseReader.wait(timeout: .now() + .seconds(10))
                    return 0x01
                }
                return 0x02
            },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        let queue = DispatchQueue(
            label: "com.hlc.pulse.tests.memory-resync",
            attributes: .concurrent
        )
        var resynchronizedLevel: MemoryPressureLevel = .unavailable
        var followerLevel: MemoryPressureLevel = .unavailable

        queue.async {
            // 第一个到期快照负责启动唯一一次受控重同步。
            resynchronizedLevel = monitor.getMemorySnapshot(
                nowUptime: baseUptime + PulseDefaults.memoryPressureResyncInterval
            ).pressureLevel
            resyncFinished.signal()
        }
        let didStartReader = readerStarted.wait(timeout: .now() + .seconds(1)) == .success
        expectTrue(didStartReader, "the boundary snapshot should start the blocked resync reader")

        queue.async {
            // 先确认任务已获调度，再单独计时 API 完成，避免把线程池繁忙误判成锁阻塞。
            followerStarted.signal()
            // 跟随快照必须直接使用缓存，不能等待或再启动一个 reader。
            followerLevel = monitor.getMemorySnapshot(
                nowUptime: baseUptime + PulseDefaults.memoryPressureResyncInterval
            ).pressureLevel
            followerFinished.signal()
        }
        let followerDidStart =
            followerStarted.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(followerDidStart, "the follower task should start within the timeout")
        let followerWasImmediate = followerDidStart
            && followerFinished.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(
            followerWasImmediate,
            "a concurrent snapshot should not wait for an in-flight resync"
        )
        if followerWasImmediate {
            // semaphore 完成信号建立 happens-before，读取结果不与后台写入竞争。
            expectTrue(
                followerLevel == .warning,
                "an in-flight follower should return the last cached warning"
            )
        }

        queue.async {
            // started 信号把队列调度时间排除在事件锁阻塞断言之外。
            eventStarted.signal()
            // critical 事件必须在 reader 仍阻塞时立即写入缓存。
            monitor.recordMemoryPressureEvent(
                rawValue: 0x04,
                nowUptime: baseUptime + PulseDefaults.memoryPressureResyncInterval
            )
            eventFinished.signal()
        }
        let eventDidStart =
            eventStarted.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(eventDidStart, "the critical event task should start within the timeout")
        let eventWasImmediate = eventDidStart
            && eventFinished.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(
            eventWasImmediate,
            "a critical event should not wait for the blocked resync reader"
        )

        // 无论红灯实现是否阻塞跟随任务，都释放 reader，确保测试进程能在有限时间收敛。
        releaseReader.signal()
        let resyncDidFinish = resyncFinished.wait(timeout: .now() + .seconds(2)) == .success
        let followerDidFinish = followerWasImmediate
            || followerFinished.wait(timeout: .now() + .seconds(2)) == .success
        let eventDidFinish = eventWasImmediate
            || eventFinished.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(resyncDidFinish, "the released resync should complete within the timeout")
        expectTrue(followerDidFinish, "the follower snapshot should complete within the timeout")
        expectTrue(eventDidFinish, "the critical event should complete within the timeout")

        if resyncDidFinish {
            // reader 启动后的事件代次更高，所以旧 normal 结果必须被丢弃。
            expectTrue(
                resynchronizedLevel == .critical,
                "a stale normal resync must not overwrite a newer critical event"
            )
        }
        readCountLock.lock()
        let finalPressureReads = pressureReads
        readCountLock.unlock()
        expectEqual(
            Double(finalPressureReads),
            2,
            "concurrent snapshots should share one in-flight resync"
        )
    }

    /// 验证 pressure reader 同步回调事件入口不会死锁，且回调状态优先于旧读取结果。
    private static func testMemoryMonitorReentrantPressureReader() {
        let baseUptime: TimeInterval = 8_000
        let reentrantReaderStarted = DispatchSemaphore(value: 0)
        let snapshotFinished = DispatchSemaphore(value: 0)
        let readCountLock = NSLock()
        var pressureReads = 0
        var monitor: SystemMonitor!
        var snapshotLevel: MemoryPressureLevel = .unavailable

        monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: {
                readCountLock.lock()
                pressureReads += 1
                let currentRead = pressureReads
                readCountLock.unlock()
                if currentRead == 2 {
                    // 主线程先观察到已进入重入点，完成超时才真正代表同步回调死锁。
                    reentrantReaderStarted.signal()
                    // 同步回调会重新进入同一状态锁，只有 reader 在锁外执行才不会死锁。
                    monitor.recordMemoryPressureEvent(
                        rawValue: 0x04,
                        nowUptime: baseUptime + PulseDefaults.memoryPressureResyncInterval
                    )
                    return 0x01
                }
                return 0x02
            },
            startPressureEvents: false,
            uptimeReader: { baseUptime }
        )

        DispatchQueue.global(qos: .userInitiated).async {
            snapshotLevel = monitor.getMemorySnapshot(
                nowUptime: baseUptime + PulseDefaults.memoryPressureResyncInterval
            ).pressureLevel
            snapshotFinished.signal()
        }
        let didEnterReader =
            reentrantReaderStarted.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(didEnterReader, "the resync reader should reach its reentrant callback")
        let didFinish = didEnterReader
            && snapshotFinished.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(didFinish, "a reentrant pressure reader should not deadlock")
        if didFinish {
            // 同步事件发生在 reader 返回前，代次保护必须让 critical 保持为最终结果。
            expectTrue(
                snapshotLevel == .critical,
                "a reentrant critical event should outrank the stale normal result"
            )
        }
    }

    /// 验证事件默认 uptime reader 可同步重入状态更新，而不会在持锁调用时死锁。
    private static func testMemoryMonitorReentrantEventUptimeReader() {
        let baseUptime: TimeInterval = 9_000
        let reentrantUptimeReaderStarted = DispatchSemaphore(value: 0)
        let eventFinished = DispatchSemaphore(value: 0)
        let uptimeReadLock = NSLock()
        var uptimeReads = 0
        var monitor: SystemMonitor!

        monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: { 0x01 },
            startPressureEvents: false,
            uptimeReader: {
                uptimeReadLock.lock()
                uptimeReads += 1
                let currentRead = uptimeReads
                uptimeReadLock.unlock()
                if currentRead == 2 {
                    // 明确标记已进入时钟 closure，随后完成超时才用于判断是否持锁重入。
                    reentrantUptimeReaderStarted.signal()
                    // 显式时间避免递归读取时钟，并同步重入同一压力状态锁。
                    monitor.recordMemoryPressureEvent(
                        rawValue: 0x02,
                        nowUptime: baseUptime + 1
                    )
                }
                return baseUptime + 1
            }
        )

        DispatchQueue.global(qos: .userInitiated).async {
            // 省略时间会调用注入时钟，只有锁外调用才能允许其同步重入。
            monitor.recordMemoryPressureEvent(rawValue: 0x04)
            eventFinished.signal()
        }
        let didEnterUptimeReader =
            reentrantUptimeReaderStarted.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(
            didEnterUptimeReader,
            "the event uptime reader should reach its reentrant callback"
        )
        let didFinish = didEnterUptimeReader
            && eventFinished.wait(timeout: .now() + .seconds(2)) == .success
        expectTrue(didFinish, "a reentrant event uptime reader should not deadlock")
        if didFinish {
            let snapshot = monitor.getMemorySnapshot(nowUptime: baseUptime + 1)
            expectTrue(
                snapshot.pressureLevel == .critical,
                "the outer critical event should commit after the reentrant warning"
            )
        }
    }

    /// 验证 UI 不会把无值伪装为零。
    private static func testMetricFormatting() {
        expectEqual(
            MetricCalculations.formatted(nil, decimals: 1, suffix: "W"),
            "—",
            "missing values should render as an em dash"
        )
        expectEqual(
            MetricCalculations.formatted(5.27, decimals: 1, suffix: "W"),
            "5.3 W",
            "formatted power should use fixed precision and a unit"
        )
        expectEqual(
            MetricCalculations.formatted(9, decimals: 0, suffix: "%"),
            "9%",
            "formatted percentage should produce a tight percentage symbol without spaces"
        )
    }

    /// 验证内存使用格式化输出：无总容量时包含单位，带总容量时精简首个重复单位 "14.07 / 24.00 GB (59%)"
    private static func testFormattedMemoryUsageText() {
        let formattedDetailSingle = MetricCalculations.formattedMemoryUsageDetail(
            usedGB: 14.07,
            totalGB: nil,
            percentage: 59
        )
        expectEqual(
            formattedDetailSingle,
            "14.07 GB (59%)",
            "无总容量时应带独立 GB 单位"
        )

        let formattedDetailBoth = MetricCalculations.formattedMemoryUsageDetail(
            usedGB: 14.07,
            totalGB: 24.00,
            percentage: 59
        )
        expectEqual(
            formattedDetailBoth,
            "14.07 / 24.00 GB (59%)",
            "带总容量时应精简首个重复的 GB 单位"
        )
    }

    /// 防止应用定时器和菜单对默认刷新间隔产生不同理解。
    private static func testDefaultRefreshInterval() {
        expectEqual(
            PulseDefaults.defaultRefreshInterval,
            1,
            "the shared default refresh interval should be one second"
        )
        // 三十秒仅用于修复可能漏掉的事件，不能退化成每秒 sysctl 轮询。
        expectEqual(
            PulseDefaults.memoryPressureResyncInterval,
            30,
            "the memory-pressure resync interval should be thirty seconds"
        )
    }

    /// 为什么：偏好数据可能损坏，菜单和计时器必须共享同一套合法刷新档位。
    private static func testRefreshIntervalValidation() {
        expectEqual(
            Double(PulseDefaults.allowedRefreshIntervals.count),
            5,
            "refresh interval should expose five choices"
        )
        expectEqual(
            PulseDefaults.validatedRefreshInterval(2),
            2,
            "two seconds should remain valid"
        )
        expectEqual(
            PulseDefaults.validatedRefreshInterval(0),
            PulseDefaults.defaultRefreshInterval,
            "zero should fall back to the shared default"
        )
        expectEqual(
            PulseDefaults.validatedRefreshInterval(4),
            PulseDefaults.defaultRefreshInterval,
            "unsupported values should fall back to the shared default"
        )
        expectEqual(
            PulseDefaults.validatedRefreshInterval(.nan),
            PulseDefaults.defaultRefreshInterval,
            "non-finite values should fall back to the shared default"
        )
    }

    /// 验证压力级别到展示角色的映射，使 UI 无需从使用率猜测系统压力。
    private static func testMemoryPresentationRole() {
        expectTrue(
            MemoryPressureLevel.normal.presentationRole == .healthy,
            "normal pressure should use the healthy presentation role"
        )
        expectTrue(
            MemoryPressureLevel.warning.presentationRole == .warning,
            "warning pressure should use the warning presentation role"
        )
        expectTrue(
            MemoryPressureLevel.critical.presentationRole == .critical,
            "critical pressure should use the critical presentation role"
        )
        expectTrue(
            MemoryPressureLevel.unavailable.presentationRole == .unavailable,
            "unavailable pressure should use the unavailable presentation role"
        )
    }

    /// 验证充电时：图标为 bolt.fill，颜色恒为绿色；数值高负载时变橙/红
    private static func testPowerDisplayConfigurationCharging() {
        let configNormal = MetricCalculations.powerDisplayConfiguration(power: 10.0, isCharging: true, isPluggedIn: true)
        expectEqual(configNormal.symbolName, "bolt.fill", "charging normal symbol should be bolt.fill")
        expectTrue(configNormal.iconColorRole == .chargingGreen, "charging normal icon color should be chargingGreen")
        expectTrue(configNormal.textColorRole == .normal, "charging normal text color should be normal")

        let configHigh = MetricCalculations.powerDisplayConfiguration(power: 35.0, isCharging: true, isPluggedIn: true)
        expectEqual(configHigh.symbolName, "bolt.fill", "charging high symbol should be bolt.fill")
        expectTrue(configHigh.iconColorRole == .chargingGreen, "charging high icon color should be chargingGreen")
        expectTrue(configHigh.textColorRole == .redWarning, "charging high text color should be redWarning")
    }

    /// 验证插电直供（未充）时：图标为 powerplug.fill，颜色为默认；数值高负载变橙/红
    private static func testPowerDisplayConfigurationPluggedInPassThrough() {
        let configHigh = MetricCalculations.powerDisplayConfiguration(power: 35.0, isCharging: false, isPluggedIn: true)
        expectEqual(configHigh.symbolName, "powerplug.fill", "plugged in pass-through high symbol should be powerplug.fill")
        expectTrue(configHigh.iconColorRole == .normal, "plugged in pass-through high icon color should be normal")
        expectTrue(configHigh.textColorRole == .redWarning, "plugged in pass-through high text color should be redWarning")
    }

    /// 验证电池放电时：图标为 bolt.fill；高负载时图标与数值同时变橙/红
    private static func testPowerDisplayConfigurationDischarging() {
        let configHigh = MetricCalculations.powerDisplayConfiguration(power: 35.0, isCharging: false, isPluggedIn: false)
        expectEqual(configHigh.symbolName, "bolt.fill", "discharging high symbol should be bolt.fill")
        expectTrue(configHigh.iconColorRole == .redWarning, "discharging high icon color should be redWarning")
        expectTrue(configHigh.textColorRole == .redWarning, "discharging high text color should be redWarning")
    }

    /// 验证方案 1 措辞：充电中、已连接电源 (未充电)、使用电池
    private static func testPowerSourceStateDescription() {
        expectEqual(
            BatteryMonitor.powerSourceStateDescription(isCharging: true, isPluggedIn: true),
            "正在充电",
            "isCharging=true, isPluggedIn=true 应返回 正在充电"
        )
        expectEqual(
            BatteryMonitor.powerSourceStateDescription(isCharging: false, isPluggedIn: true),
            "已连接电源 (未充电)",
            "isCharging=false, isPluggedIn=true 应返回 已连接电源 (未充电)"
        )
        expectEqual(
            BatteryMonitor.powerSourceStateDescription(isCharging: false, isPluggedIn: false),
            "使用电池",
            "isCharging=false, isPluggedIn=false 应返回 使用电池"
        )
    }

    /// 为什么：单次 IOKit 结果必须派生全部状态，防止一轮刷新重复创建三份系统快照。
    private static func testPowerSourceSnapshotDerivation() {
        let charging = BatteryMonitor.snapshot(from: [[
            kIOPSIsChargingKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue
        ]])
        expectTrue(charging.isCharging, "charging flag should be preserved")
        expectTrue(charging.isPluggedIn, "charging source should be plugged in")
        expectEqual(charging.description, "正在充电", "charging description should be concise")

        let battery = BatteryMonitor.snapshot(from: [[
            kIOPSIsChargingKey: false,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue
        ]])
        expectFalse(battery.isCharging, "battery power should not be charging")
        expectFalse(battery.isPluggedIn, "battery power should not be plugged in")
        expectEqual(battery.description, "使用电池", "battery description should remain truthful")

        let unknown = BatteryMonitor.snapshot(from: [])
        expectEqual(unknown.description, "未知", "an empty source list should remain unknown")
    }

    /// 为什么：两个展示入口必须消费同一个不可变快照，而不是分别读取实时状态。
    private static func testPulseSnapshotKeepsOneRefreshState() {
        let memory = MemorySnapshot(
            usedBytes: 8,
            totalBytes: 16,
            usagePercentage: 50,
            pressureLevel: .normal
        )
        let powerSource = PowerSourceSnapshot(
            isCharging: false,
            isPluggedIn: true,
            description: "已连接电源 (未充电)"
        )
        let snapshot = PulseSnapshot(
            power: 7.1,
            memory: memory,
            temperature: 32.4,
            cpuUsage: 14,
            cpuFrequency: 2.4,
            powerSource: powerSource
        )
        expectEqual(snapshot.power, 7.1, "snapshot should preserve system load")
        expectEqual(snapshot.memory.usagePercentage, 50, "snapshot should preserve memory state")
        expectEqual(snapshot.powerSource.description, powerSource.description, "snapshot should preserve power state")
    }

    /// 为什么：刷新选择必须走真实 NSPopUpButton 状态，hover 只能改变表现而不能接管点击。
    private static func testRefreshControlUsesNativeSelectionAndHoverState() {
        let control = RefreshIntervalControl(
            frame: NSRect(x: 0, y: 0, width: 92, height: 32)
        )
        var received: TimeInterval?
        control.onIntervalChanged = { received = $0 }
        control.select(interval: 5, notify: true)
        expectEqual(
            received,
            5,
            "native popup selection should forward the represented interval"
        )
        expectFalse(control.isHovered, "refresh control should start unhovered")
        control.setHovered(true)
        expectTrue(control.isHovered, "hover entry should update presentation state")
        control.setHovered(false)
        expectFalse(control.isHovered, "hover exit should restore normal state")

        let popup = control.subviews.compactMap { $0 as? NSPopUpButton }.first
        expectTrue(
            popup?.focusRingType == NSFocusRingType.none,
            "refresh popup should not show a persistent blue focus ring"
        )
        expectEqual(
            Double(popup?.numberOfItems ?? 0),
            5,
            "focus styling must not replace the native five-item popup"
        )
    }

    /// 为什么：刷新只应修改已经存在的原生标签，不能每秒重建详情视图树。
    private static func testPopoverContentUpdatesExistingMetricLabels() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 320)
        )
        let memory = MemorySnapshot(
            usedBytes: 8_589_934_592,
            totalBytes: 17_179_869_184,
            usagePercentage: 50,
            pressureLevel: .normal
        )
        let snapshot = PulseSnapshot(
            power: 7.1,
            memory: memory,
            temperature: 32.4,
            cpuUsage: 14,
            cpuFrequency: 2.4,
            powerSource: PowerSourceSnapshot(
                isCharging: false,
                isPluggedIn: true,
                description: "已连接电源 (未充电)"
            )
        )
        view.update(snapshot: snapshot)

        let powerLabel: NSTextField? = descendant(
            in: view,
            identifier: "metric.power.value"
        )
        let memoryLabel: NSTextField? = descendant(
            in: view,
            identifier: "metric.memoryUsage.value"
        )
        let memorySubLabel: NSTextField? = descendant(
            in: view,
            identifier: "metric.memoryUsage.sub"
        )
        let cpuLabel: NSTextField? = descendant(
            in: view,
            identifier: "metric.cpu.value"
        )
        let powerSourceLabel: NSTextField? = descendant(
            in: view,
            identifier: "metric.powerSource.value"
        )
        let powerSourceSubLabel: NSTextField? = descendant(
            in: view,
            identifier: "metric.powerSource.sub"
        )
        expectEqual(powerLabel?.stringValue ?? "", "7.1 W", "power label should use the shared formatter")
        expectEqual(
            memoryLabel?.stringValue ?? "",
            "8.00 / 16.00 GB (50%)",
            "memory must remain one complete value"
        )
        expectTrue(memorySubLabel == nil, "memory must not be split into a secondary label")
        expectEqual(
            cpuLabel?.stringValue ?? "",
            "14% (2.4 GHz)",
            "CPU must retain its optional frequency detail"
        )
        expectEqual(
            powerSourceLabel?.stringValue ?? "",
            "已连接电源 (未充电)",
            "power source must use the snapshot description"
        )
        expectTrue(
            powerSourceSubLabel == nil,
            "power source must not be split into a secondary label"
        )
    }

    /// 为什么：系统设置式分组必须共享同一横向坐标，不能让指标与设置各自维护一套魔法数字。
    private static func testPopoverGroupsAndRowsShareHorizontalGeometry() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 320)
        )
        view.layoutSubtreeIfNeeded()

        let groupIDs = ["group.metrics", "group.controls", "group.quit"]
        let groups: [NSBox] = groupIDs.compactMap {
            descendant(in: view, identifier: $0)
        }
        expectEqual(Double(groups.count), 3, "popover should expose three visual groups")
        expectTrue(
            groups.count == 3 && Set(groups.map { Int($0.frame.minX.rounded()) }).count == 1,
            "all groups should share the same leading edge"
        )
        expectTrue(
            groups.count == 3 && Set(groups.map { Int($0.frame.width.rounded()) }).count == 1,
            "all groups should share the same width"
        )

        let titleIDs = [
            "control.refresh.title",
            "control.more.title",
            "control.quit.title",
        ]
        let titleXs = titleIDs.compactMap { identifier -> Int? in
            let label: NSTextField? = descendant(in: view, identifier: identifier)
            return rootX(of: label, in: view)
        }
        expectTrue(
            titleXs.count == 3 && Set(titleXs).count == 1,
            "metric, setting, and quit titles should share one leading coordinate"
        )

        let powerSourceIcon: NSImageView? = descendant(
            in: view,
            identifier: "metric.powerSource.icon"
        )
        let cpuIcon: NSImageView? = descendant(in: view, identifier: "metric.cpu.icon")
        expectTrue(
            (powerSourceIcon?.frame.width ?? 0) == (cpuIcon?.frame.width ?? 0),
            "all metric icons should share the same uniform width"
        )

        let separators = allDescendants(in: view).compactMap { child -> NSBox? in
            guard let box = child as? NSBox,
                box.identifier?.rawValue.hasPrefix("control.separator.") == true
            else {
                return nil
            }
            return box
        }
        let separatorEdges = separators.compactMap { separator -> String? in
            guard let superview = separator.superview else { return nil }
            let origin = superview.convert(separator.frame.origin, to: view)
            return "\(Int(origin.x.rounded())):\(Int((origin.x + separator.frame.width).rounded()))"
        }
        expectTrue(
            separatorEdges.count == 2 && Set(separatorEdges).count == 1,
            "all metric and setting separators should share one horizontal span"
        )
    }

    /// 为什么：外层墙纸材质会产生偏色，系统设置式面板应使用窗口语义色和统一分组色。
    private static func testPopoverUsesSystemWindowAndSharedGroupColors() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 320)
        )
        let rootView: NSView = view
        expectFalse(
            rootView is NSVisualEffectView,
            "outer surface should use the system window color instead of wallpaper-tinted material"
        )

        let groups: [NSBox] = ["group.metrics", "group.controls", "group.quit"].compactMap {
            descendant(in: view, identifier: $0)
        }
        let fills = groups.map(\.fillColor)
        expectTrue(
            fills.count == 3 && fills.dropFirst().allSatisfy { $0.isEqual(fills[0]) },
            "all groups should share one semantic grouped fill"
        )
    }

    /// 为什么：开关显示必须由系统实际状态驱动，不能保留上一次用户期望值。
    private static func testPopoverLaunchSwitchReflectsActualState() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 320)
        )
        view.setLaunchAtLoginEnabled(true)
        let launchSwitch: NSSwitch? = descendant(
            in: view,
            identifier: "control.launch.switch"
        )
        expectTrue(launchSwitch?.state == .on, "launch switch should display the actual enabled state")
    }

    /// 为什么：退出行必须转发真实按钮动作，快捷键和鼠标点击才能共享同一条路径。
    private static func testPopoverQuitButtonForwardsAction() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 320)
        )
        var didRequestQuit = false
        view.onQuit = { didRequestQuit = true }
        let quitButton: NSButton? = descendant(
            in: view,
            identifier: "control.quit.button"
        )
        quitButton?.performClick(nil)
        expectTrue(didRequestQuit, "quit button should forward one action")
    }

    /// 为什么：系统注册失败时，真实控制器必须把开关恢复为服务报告的实际状态。
    private static func testLaunchAtLoginFailureRestoresDisplayedState() {
        final class FailingLaunchController: LaunchAtLoginControlling {
            var isEnabled = false

            func setEnabled(_ enabled: Bool) throws {
                throw LaunchAtLoginError.operationFailed
            }
        }

        let launchController = FailingLaunchController()
        let displayedState = LaunchAtLoginSettings.apply(
            requestedState: true,
            using: launchController
        )
        expectFalse(
            displayedState,
            "failed registration must restore the actual disabled state"
        )
    }

    /// 测试辅助仅遍历真实 AppKit 视图，不向生产类型添加测试专用接口。
    private static func descendant<T: NSView>(
        in root: NSView,
        identifier: String
    ) -> T? {
        if root.identifier?.rawValue == identifier, let match = root as? T {
            return match
        }
        for child in root.subviews {
            if let match: T = descendant(in: child, identifier: identifier) {
                return match
            }
        }
        return nil
    }

    /// 返回整棵真实 AppKit 子视图树，供几何一致性测试使用。
    private static func allDescendants(in root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + allDescendants(in: $0) }
    }

    /// 将标签横坐标转换到详情根视图，避免比较不同分组的局部坐标。
    private static func rootX(of view: NSView?, in root: NSView) -> Int? {
        guard let view, let superview = view.superview else { return nil }
        return Int(superview.convert(view.frame.origin, to: root).x.rounded())
    }

    /// 为什么：TDD 全功能与回归测试断言，验证 PopUp 档位切换、开机自启逻辑与 A1 硬件口径 100% 稳定
    private static func testFullFeatureAndRegressionSuite() {
        // 1. 回归验证：物理内存口径 (A1 规范)
        let memory = MemorySnapshot(
            usedBytes: 17_400_000_000,
            totalBytes: 24_000_000_000,
            usagePercentage: 72.5,
            pressureLevel: .normal
        )
        expectEqual(memory.usagePercentage, 72.5, "物理内存使用率百分比解耦为 72.5")
        expectEqual(memory.pressureLevel.displayName, "正常", "内核压力正常状态名应为 正常")

        // 2. 功能测试：刷新间隔建议与档位切换
        let validIntervals: [TimeInterval] = [1.0, 2.0, 3.0, 5.0, 10.0]
        for interval in validIntervals {
            let label = BatteryMonitor.powerSourceStateDescription(isCharging: false, isPluggedIn: true)
            expectTrue(!label.isEmpty, "电源状态格式化不可为空")
            expectTrue(interval > 0, "刷新间隔必须大于 0")
        }

        // 3. 规范测试：已连接电源 (未充电)
        let pluggedInText = BatteryMonitor.powerSourceStateDescription(isCharging: false, isPluggedIn: true)
        expectEqual(pluggedInText, "已连接电源 (未充电)", "插电未充电描述需为 已连接电源 (未充电)")
    }

    private static func expectEqual(
        _ actual: Double?,
        _ expected: Double,
        _ message: String,
        tolerance: Double = 0.000_001
    ) {
        guard let actual, abs(actual - expected) <= tolerance else {
            recordFailure("\(message); expected \(expected), got \(String(describing: actual))")
            return
        }
        recordSuccess()
    }

    private static func expectEqual(
        _ actual: String,
        _ expected: String,
        _ message: String
    ) {
        guard actual == expected else {
            recordFailure("\(message); expected \(expected), got \(actual)")
            return
        }
        recordSuccess()
    }

    private static func expectNil(_ actual: Double?, _ message: String) {
        guard actual == nil else {
            recordFailure("\(message); got \(String(describing: actual))")
            return
        }
        recordSuccess()
    }

    private static func expectTrue(_ actual: Bool, _ message: String) {
        guard actual else {
            recordFailure(message)
            return
        }
        recordSuccess()
    }

    private static func hostSendRightReferences(
        for port: mach_port_t
    ) -> mach_port_urefs_t? {
        var references: mach_port_urefs_t = 0
        guard mach_port_get_refs(
            mach_task_self_,
            port,
            MACH_PORT_RIGHT_SEND,
            &references
        ) == KERN_SUCCESS else {
            return nil
        }
        return references
    }

    private static func testCPUUsageBalancesHostPortSendRight() {
        let observedHostPort = mach_host_self()
        guard observedHostPort != mach_port_t(MACH_PORT_NULL) else {
            expectTrue(false, "test must obtain a host port")
            return
        }
        defer {
            mach_port_deallocate(mach_task_self_, observedHostPort)
        }

        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: { 1 },
            startPressureEvents: false,
            uptimeReader: { 0 },
            cpuFrequencyReader: { 0 }
        )
        let before = hostSendRightReferences(for: observedHostPort)
        for _ in 0..<100 {
            _ = monitor.getCPUUsage()
        }
        let after = hostSendRightReferences(for: observedHostPort)
        expectTrue(
            before != nil && after == before,
            "one hundred CPU reads must not increase host send-right references"
        )
    }

    private static func testCPUFrequencyReaderRunsOnce() {
        var reads = 0
        let monitor = SystemMonitor(
            memoryStatisticsReader: { nil },
            pressureLevelReader: { 1 },
            startPressureEvents: false,
            uptimeReader: { 0 },
            cpuFrequencyReader: {
                reads += 1
                return 3.2
            }
        )

        expectEqual(monitor.getCPUFrequency(), 3.2, "cached frequency should be returned")
        expectEqual(monitor.getCPUFrequency(), 3.2, "cached frequency should remain stable")
        expectEqual(Double(reads), 1, "frequency reader should run once per monitor")
    }

    private static func makePulseSnapshot(
        power: Double? = 7.1,
        memoryUsagePercentage: Double? = 41,
        pressureLevel: MemoryPressureLevel = .normal,
        temperature: Double? = 30.6,
        cpuUsage: Double = 10,
        isCharging: Bool = false,
        isPluggedIn: Bool = false
    ) -> PulseSnapshot {
        let totalBytes: UInt64 = 24 * 1_073_741_824
        let usedBytes = memoryUsagePercentage.map {
            UInt64((Double(totalBytes) * $0 / 100.0).rounded())
        }
        return PulseSnapshot(
            power: power,
            memory: MemorySnapshot(
                usedBytes: usedBytes,
                totalBytes: totalBytes,
                usagePercentage: memoryUsagePercentage,
                pressureLevel: pressureLevel
            ),
            temperature: temperature,
            cpuUsage: cpuUsage,
            cpuFrequency: 0,
            powerSource: PowerSourceSnapshot(
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                description: isCharging ? "充电中" : (isPluggedIn ? "已连接电源" : "使用电池")
            )
        )
    }

    private static func testStatusItemRenderModelUsesSnapshotAndThresholds() {
        let snapshot = makePulseSnapshot(
            power: 31,
            memoryUsagePercentage: 41,
            pressureLevel: .normal,
            temperature: 30.6,
            cpuUsage: 10,
            isCharging: false,
            isPluggedIn: false
        )
        let model = StatusItemRenderModel.make(
            snapshot: snapshot,
            thresholds: .defaults()
        )

        expectEqual(model.powerText, "31.0 W", "power text should preserve one decimal")
        expectEqual(model.temperatureText, "30.6 °C", "temperature text should preserve one decimal")
        expectEqual(model.memoryText, "41%", "memory text should be an integer percentage")
        expectEqual(model.cpuText, "10%", "CPU text should be an integer percentage")
        expectTrue(model.powerIconColor == .red, "discharging power icon should use the configured red threshold")
        expectTrue(model.powerTextColor == .red, "power text should use the configured red threshold")
        expectTrue(model.memoryColor == .green, "normal memory pressure should remain green")
    }

    private static func testChargingPowerIconAndValueKeepIndependentColors() {
        let snapshot = makePulseSnapshot(
            power: 31,
            isCharging: true,
            isPluggedIn: true
        )
        let model = StatusItemRenderModel.make(snapshot: snapshot, thresholds: .defaults())

        expectTrue(model.powerIconColor == .green,
                   "charging state must keep the bolt green")
        expectTrue(model.powerTextColor == .red,
                   "high power must still warn through the value color")
    }

    private static func testStatusItemRenderModelEqualitySupportsDeduplication() {
        let snapshot = makePulseSnapshot()
        let first = StatusItemRenderModel.make(snapshot: snapshot, thresholds: .defaults())
        let second = StatusItemRenderModel.make(snapshot: snapshot, thresholds: .defaults())
        expectTrue(first == second, "identical display state should compare equal")
    }

    private final class StubLaunchController: LaunchAtLoginControlling {
        var isEnabled: Bool = false
        var shouldThrow: Bool = false
        func setEnabled(_ enabled: Bool) throws {
            if shouldThrow {
                struct TestError: Error {}
                throw TestError()
            }
            isEnabled = enabled
        }
    }

    private final class SpyStatusItemRenderer: StatusItemRendering {
        private(set) var renderCount = 0
        let rendered: RenderedStatusItem

        init(rendered: RenderedStatusItem) {
            self.rendered = rendered
        }

        func render(
            model: StatusItemRenderModel,
            appearance: NSAppearance,
            backingScaleFactor: CGFloat
        ) -> RenderedStatusItem? {
            renderCount += 1
            return rendered
        }
    }

    private static func testStatusBarControllerDeduplicatesIdenticalSnapshots() {
        let dummyImage = NSImage(size: NSSize(width: 100, height: 22))
        let geometry = StatusItemGeometry(
            canvasSize: NSSize(width: 100, height: 22),
            powerIconFrame: .zero,
            temperatureIconFrame: .zero,
            memoryIconFrame: .zero,
            cpuIconFrame: .zero,
            powerTextOrigin: .zero,
            temperatureTextOrigin: .zero,
            memoryTextOrigin: .zero,
            cpuTextOrigin: .zero
        )
        let spy = SpyStatusItemRenderer(
            rendered: RenderedStatusItem(image: dummyImage, geometry: geometry)
        )
        let controller = StatusBarController(
            statusItemHost: FakeStatusItemHost(),
            launchController: StubLaunchController(),
            statusRenderer: spy
        )

        let snapshot1 = makePulseSnapshot(cpuUsage: 10)
        controller.update(snapshot: snapshot1)
        expectEqual(Double(spy.renderCount), 1, "first snapshot should render")

        // 相同快照重复更新不应触发再次渲染
        controller.update(snapshot: snapshot1)
        expectEqual(Double(spy.renderCount), 1, "identical snapshot should be deduplicated")

        // 指标变化触发渲染
        let snapshot2 = makePulseSnapshot(cpuUsage: 20)
        controller.update(snapshot: snapshot2)
        expectEqual(Double(spy.renderCount), 2, "changed snapshot should trigger new render")
    }

    private static func testThresholdConfigCallbackUpdatesMemoryAndRerenders() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 320)
        )
        var callbackCount = 0
        var receivedConfig: ThresholdConfig?
        view.onThresholdConfigChanged = { config in
            callbackCount += 1
            receivedConfig = config
        }

        // 为什么：高级设置只在展开后创建，先点击展开按钮
        if let moreButton: NSButton = descendant(in: view, identifier: "control.more.button"),
           let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton)
        }

        // 尝试更改所有阈值输入框为有效数值
        let orangeInputs = allDescendants(in: view).compactMap { $0 as? NumericInputView }
            .filter { $0.identifier?.rawValue.hasSuffix(".orangeInput") == true }
        let redInputs = allDescendants(in: view).compactMap { $0 as? NumericInputView }
            .filter { $0.identifier?.rawValue.hasSuffix(".redInput") == true }

        expectEqual(Double(orangeInputs.count), 3, "should find three orange input fields")
        expectEqual(Double(redInputs.count), 3, "should find three red input fields")

        for input in orangeInputs + redInputs {
            input.stringValue = "50"
            input.onTextChange?()
        }

        expectEqual(Double(callbackCount), 6, "every valid field edit should trigger threshold config update")
        expectEqual(receivedConfig?.cpu.red, 50, "received config should hold updated threshold")

        // 设置无效输入清空文本框不应触发回调
        if let firstInput = orangeInputs.first {
            firstInput.stringValue = ""
            firstInput.onTextChange?()
            expectEqual(Double(callbackCount), 6, "invalid incomplete input must not trigger callback")
        }
    }

    private final class SpyPanelSession: PanelSessionControlling {
        var isVisible = false
        var showResult = true
        private(set) var showCount = 0
        private(set) var updateCount = 0
        private(set) var closeCount = 0
        private(set) var lastUpdatedSnapshot: PulseSnapshot?
        private(set) var lastSetLaunchAtLoginState: Bool?
        let configuration: PanelSessionConfiguration

        init(configuration: PanelSessionConfiguration) {
            self.configuration = configuration
        }

        @discardableResult
        func show() -> Bool {
            showCount += 1
            isVisible = showResult
            return showResult
        }

        func close() {
            closeCount += 1
            isVisible = false
        }

        func completeClose() {
            configuration.onDidClose(configuration.identity)
        }

        func requestDismiss(_ reason: PanelDismissReason) {
            configuration.onDismissRequested(reason)
        }

        func update(snapshot: PulseSnapshot) {
            updateCount += 1
            lastUpdatedSnapshot = snapshot
        }

        func setLaunchAtLoginEnabled(_ enabled: Bool) {
            lastSetLaunchAtLoginState = enabled
        }
    }

    private static func testStatusBarControllerPanelSessionLifecycle() {
        var createdSessionCount = 0
        weak var weakSession: SpyPanelSession?

        let dummyImage = NSImage(size: NSSize(width: 100, height: 22))
        let geometry = StatusItemGeometry(
            canvasSize: NSSize(width: 100, height: 22),
            powerIconFrame: .zero,
            temperatureIconFrame: .zero,
            memoryIconFrame: .zero,
            cpuIconFrame: .zero,
            powerTextOrigin: .zero,
            temperatureTextOrigin: .zero,
            memoryTextOrigin: .zero,
            cpuTextOrigin: .zero
        )
        let dummyRenderer = SpyStatusItemRenderer(
            rendered: RenderedStatusItem(image: dummyImage, geometry: geometry)
        )

        let controller = StatusBarController(
            statusItemHost: FakeStatusItemHost(),
            launchController: StubLaunchController(),
            statusRenderer: dummyRenderer,
            panelSessionFactory: { config in
                createdSessionCount += 1
                let session = SpyPanelSession(configuration: config)
                weakSession = session
                return session
            }
        )

        expectEqual(Double(createdSessionCount), 0, "constructing controller must not eagerly create panel session")

        let snapshot1 = makePulseSnapshot(cpuUsage: 15)
        controller.update(snapshot: snapshot1)
        expectEqual(Double(createdSessionCount), 0, "closed panel must not create panel session on update")

        // 模拟打开面板
        controller.togglePanelForTesting()
        expectEqual(Double(createdSessionCount), 1, "opening panel must create exactly one session")
        expectEqual(Double(weakSession?.showCount ?? 0), 1, "session should be shown")
        expectEqual(Double(weakSession?.updateCount ?? 0), 1, "opening session must consume latest snapshot")
        expectEqual(weakSession?.lastUpdatedSnapshot?.cpuUsage, 15, "snapshot content must match")

        // 面板打开期间收到新快照更新 session
        let snapshot2 = makePulseSnapshot(cpuUsage: 35)
        controller.update(snapshot: snapshot2)
        expectEqual(Double(weakSession?.updateCount ?? 0), 2, "visible session must receive new updates")

        // 模拟关闭面板
        controller.togglePanelForTesting()
        expectTrue(weakSession != nil, "session must remain retained while close transition is pending")
        weakSession?.completeClose()
        expectTrue(weakSession != nil, "matching close completion retains session for instance reuse")

        // 面板关闭后后续更新不增加已关 session 的 updateCount
        controller.update(snapshot: makePulseSnapshot(cpuUsage: 50))
        expectEqual(Double(createdSessionCount), 1, "updating while closed must not recreate session")
    }

    private static func testPopoverContentViewLazySettingsRows() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 320)
        )

        // 初始化完成后不应创建任何 settings. 前缀的元素
        let initialSettingsViews = allDescendants(in: view).filter {
            $0.identifier?.rawValue.hasPrefix("settings.") == true
        }
        expectEqual(Double(initialSettingsViews.count), 0, "initial view must not create settings subviews")

        // 触发展开按钮点击
        let moreButton: NSButton? = descendant(in: view, identifier: "control.more.button")
        expectTrue(moreButton != nil, "more button should exist")
        if let moreButton, let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton)
        }

        let expandedSections = allDescendants(in: view).filter {
            guard let id = $0.identifier?.rawValue else { return false }
            return id.hasPrefix("settings.section.") && id.split(separator: ".").count == 3
        }
        expectEqual(Double(expandedSections.count), 3, "expanding must create exactly three settings sections")

        // 折叠再展开，数量应保持为 3，不发生二次重复创建
        if let moreButton, let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton) // 折叠
            NSApp.sendAction(action, to: target, from: moreButton) // 再次展开
        }

        let reexpandedSections = allDescendants(in: view).filter {
            guard let id = $0.identifier?.rawValue else { return false }
            return id.hasPrefix("settings.section.") && id.split(separator: ".").count == 3
        }
        expectEqual(Double(reexpandedSections.count), 3, "re-expanding must reuse created settings sections")
    }

    private static func testPopoverSettingsCollapseTracksAnimatedHeight() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: PopoverContentView.collapsedHeight)
        )
        var requestedHeight: CGFloat?
        view.onPanelHeightChanged = { requestedHeight = $0 }

        guard let moreButton: NSButton = descendant(in: view, identifier: "control.more.button"),
              let action = moreButton.action,
              let target = moreButton.target else {
            recordFailure("more settings button must exist")
            return
        }

        NSApp.sendAction(action, to: target, from: moreButton)
        expectEqual(Double(requestedHeight ?? -1), 594.0, "expansion must request the full panel height")
        view.frame.size.height = 594
        view.layoutSubtreeIfNeeded()

        NSApp.sendAction(action, to: target, from: moreButton)
        expectEqual(Double(requestedHeight ?? -1), 398.0, "collapse must request the collapsed panel height")
        view.layoutSubtreeIfNeeded()

        let controlsGroup: NSView? = descendant(in: view, identifier: "group.controls")
        let updateRow: NSView? = descendant(in: view, identifier: "settings.update.row")
        expectEqual(
            Double(controlsGroup?.frame.height ?? -1),
            316.0,
            "controls card must remain expanded before the outer frame starts shrinking"
        )
        expectFalse(updateRow?.isHidden ?? true, "settings must remain visible at the start of collapse")

        view.frame.size.height = 492
        view.layoutSubtreeIfNeeded()

        let quitGroup: NSView? = descendant(in: view, identifier: "group.quit")
        let header: NSView? = descendant(in: view, identifier: "settings.threshold.header")
        expectEqual(
            Double(controlsGroup?.frame.height ?? -1),
            214.0,
            "controls card must use the panel's intermediate height"
        )
        expectTrue(
            (controlsGroup as? NSBox)?.contentView?.layer?.masksToBounds == true,
            "controls card must clip settings rows that move below its animated bounds"
        )
        expectEqual(Double(quitGroup?.frame.minY ?? -1), 8.0, "quit card must follow the outer bottom edge")
        expectFalse(updateRow?.isHidden ?? true, "settings must stay visible while part of the settings region remains")
        expectTrue(
            (header?.frame.maxY ?? .greatestFiniteMagnitude) <= 94.0,
            "settings content must stay below the three fixed control rows during collapse"
        )

        view.frame.size.height = PopoverContentView.collapsedHeight
        view.layoutSubtreeIfNeeded()
        expectEqual(Double(controlsGroup?.frame.height ?? -1), 120.0, "controls card must end at its collapsed height")
        expectTrue(updateRow?.isHidden ?? false, "settings must hide at the fully collapsed frame")
    }

    private final class SpyBatteryRegistryReader: BatteryRegistryReading {
        private(set) var recordedNeeds: [BatteryRegistryReadNeeds] = []

        func readMetrics(needs: BatteryRegistryReadNeeds) -> BatteryRegistryMetrics {
            recordedNeeds.append(needs)
            return BatteryRegistryMetrics(
                systemLoadMilliwatts: needs.contains(.systemLoad) ? 15000 : nil,
                externalConnected: needs.contains(.systemLoad) ? false : nil,
                temperatureCentiDegrees: needs.contains(.temperature) ? 3500 : nil
            )
        }
    }

    private static func testHardwareMonitorPreciseBatteryReadNeeds() {
        let spy = SpyBatteryRegistryReader()

        // 1. PSTR 和 TB0T 均有效：必须不发起任何 IOKit 读取
        let fullSMC = StubSMCReader(systemPowerWatts: 12.5, batteryTemperatureCelsius: 32.0)
        let fullMonitor = HardwareMonitor(smcReader: fullSMC, batteryRegistryReader: spy)
        let fullSnapshot = fullMonitor.readSnapshot()
        expectEqual(fullSnapshot.systemLoadWatts, 12.5, "valid SMC power should be used")
        expectEqual(fullSnapshot.batteryTemperatureCelsius, 32.0, "valid SMC temp should be used")
        expectEqual(Double(spy.recordedNeeds.count), 0, "no battery registry read needed when SMC complete")

        // 2. 仅缺失 PSTR：只能指定读取 .systemLoad
        let missingPowerSMC = StubSMCReader(systemPowerWatts: nil, batteryTemperatureCelsius: 32.0)
        let powerMonitor = HardwareMonitor(smcReader: missingPowerSMC, batteryRegistryReader: spy)
        let powerSnapshot = powerMonitor.readSnapshot()
        expectEqual(powerSnapshot.systemLoadWatts, 15.0, "fallback battery power should be used")
        expectEqual(powerSnapshot.batteryTemperatureCelsius, 32.0, "valid SMC temp should be preserved")
        expectEqual(Double(spy.recordedNeeds.count), 1, "exactly one registry read performed")
        expectTrue(spy.recordedNeeds.last == [.systemLoad], "must request only systemLoad when power missing")

        // 3. 仅缺失 TB0T：只能指定读取 .temperature
        let missingTempSMC = StubSMCReader(systemPowerWatts: 12.5, batteryTemperatureCelsius: nil)
        let tempMonitor = HardwareMonitor(smcReader: missingTempSMC, batteryRegistryReader: spy)
        let tempSnapshot = tempMonitor.readSnapshot()
        expectEqual(tempSnapshot.systemLoadWatts, 12.5, "valid SMC power should be preserved")
        expectEqual(tempSnapshot.batteryTemperatureCelsius, 35.0, "fallback battery temp should be used")
        expectEqual(Double(spy.recordedNeeds.count), 2, "exactly two registry reads performed")
        expectTrue(spy.recordedNeeds.last == [.temperature], "must request only temperature when temp missing")

        // 4. 两者均缺失：指定读取 [.systemLoad, .temperature]
        let emptySMC = StubSMCReader(systemPowerWatts: nil, batteryTemperatureCelsius: nil)
        let emptyMonitor = HardwareMonitor(smcReader: emptySMC, batteryRegistryReader: spy)
        let emptySnapshot = emptyMonitor.readSnapshot()
        expectEqual(emptySnapshot.systemLoadWatts, 15.0, "fallback battery power should be used")
        expectEqual(emptySnapshot.batteryTemperatureCelsius, 35.0, "fallback battery temp should be used")
        expectEqual(Double(spy.recordedNeeds.count), 3, "exactly three registry reads performed")
        expectTrue(spy.recordedNeeds.last == [.systemLoad, .temperature], "must request both when SMC empty")
    }

    private static func testStatusBarControllerUsesStatusItemHost() {
        let fakeHost = FakeStatusItemHost(isAttachedToWindow: true, effectiveAppearance: NSAppearance(named: .darkAqua)!, backingScaleFactor: 2.0)
        let controller = StatusBarController(
            statusItemHost: fakeHost,
            launchController: StubLaunchController()
        )
        let snapshot = makePulseSnapshot(cpuUsage: 25)
        controller.update(snapshot: snapshot)
        expectTrue(fakeHost.image != nil, "fake status item host should receive rendered image")
    }

    private static func testFirstVisibleRenderWaitsForHostedAppearance() {
        let host = FakeStatusItemHost(isAttachedToWindow: false, effectiveAppearance: NSAppearance(named: .aqua)!, backingScaleFactor: 2.0)
        let dummyImage = NSImage(size: NSSize(width: 100, height: 22))
        let geometry = StatusItemGeometry(
            canvasSize: NSSize(width: 100, height: 22),
            powerIconFrame: .zero,
            temperatureIconFrame: .zero,
            memoryIconFrame: .zero,
            cpuIconFrame: .zero,
            powerTextOrigin: .zero,
            temperatureTextOrigin: .zero,
            memoryTextOrigin: .zero,
            cpuTextOrigin: .zero
        )
        let spyRenderer = SpyStatusItemRenderer(rendered: RenderedStatusItem(image: dummyImage, geometry: geometry))
        let controller = StatusBarController(
            statusItemHost: host,
            launchController: StubLaunchController(),
            statusRenderer: spyRenderer
        )

        controller.update(snapshot: makePulseSnapshot())
        expectEqual(Double(spyRenderer.renderCount), 0, "unattached status item must only cache snapshot")
        expectTrue(host.image == nil, "unattached item must not expose a wrongly colored bitmap")

        host.isAttachedToWindow = true
        host.effectiveAppearance = NSAppearance(named: .darkAqua)!
        host.onRenderEnvironmentChanged?()

        expectEqual(Double(spyRenderer.renderCount), 1, "hosted appearance must trigger the first render")
    }

    private static func testPanelSessionLocalClickFiltering() {
        let panelWindow = NSWindow()
        let anchorWindow = NSWindow()
        let thirdPartyWindow = NSWindow()

        expectFalse(
            PanelSession.shouldCloseForLocalClick(eventWindow: panelWindow, panelWindow: panelWindow, anchorWindow: anchorWindow),
            "click inside panel window must not close panel"
        )
        expectFalse(
            PanelSession.shouldCloseForLocalClick(eventWindow: anchorWindow, panelWindow: panelWindow, anchorWindow: anchorWindow),
            "click inside status item anchor window must not close panel via local monitor"
        )
        expectTrue(
            PanelSession.shouldCloseForLocalClick(eventWindow: thirdPartyWindow, panelWindow: panelWindow, anchorWindow: anchorWindow),
            "click inside third party window must close panel"
        )
        expectTrue(
            PanelSession.shouldCloseForLocalClick(eventWindow: nil, panelWindow: panelWindow, anchorWindow: anchorWindow),
            "click outside window system must close panel"
        )
    }

    private static func testStatusBarControllerFourClicksAlternatingToggle() {
        let fakeHost = FakeStatusItemHost(isAttachedToWindow: true, effectiveAppearance: NSAppearance(named: .darkAqua)!, backingScaleFactor: 2.0)
        var sessions: [SpyPanelSession] = []

        let controller = makeStatusBarControllerForPanelTests(host: fakeHost) { config in
            let session = SpyPanelSession(configuration: config)
            sessions.append(session)
            return session
        }

        // 模拟连续 4 次点击状态栏并模拟动画完成
        controller.togglePanelForTesting() // 第 1 次：open
        expectEqual(Double(sessions.count), 1, "first click must create one session")

        controller.togglePanelForTesting() // 第 2 次：close
        sessions[0].completeClose()

        controller.togglePanelForTesting() // 第 3 次：open
        expectEqual(Double(sessions.count), 1, "third click after close completion must REUSE the existing session")

        controller.togglePanelForTesting() // 第 4 次：close
        sessions[0].completeClose()

        expectEqual(Double(sessions.count), 1, "four completed toggle transitions must reuse single session")
        expectTrue(
            fakeHost.panelPresentationRequests == [true, false, true, false],
            "four clicks must alternate presentation intent exactly"
        )
    }

    private static func testLaunchAtLoginFailureUpdatesPanelSwitchState() {
        var createdSpy: SpyPanelSession?
        let stubLaunch = StubLaunchController()
        stubLaunch.shouldThrow = true // 模拟操作失败
        stubLaunch.isEnabled = false

        let fakeHost = FakeStatusItemHost(isAttachedToWindow: true, effectiveAppearance: NSAppearance(named: .darkAqua)!, backingScaleFactor: 2.0)
        let dummyImage = NSImage(size: NSSize(width: 100, height: 22))
        let geometry = StatusItemGeometry(
            canvasSize: NSSize(width: 100, height: 22),
            powerIconFrame: .zero,
            temperatureIconFrame: .zero,
            memoryIconFrame: .zero,
            cpuIconFrame: .zero,
            powerTextOrigin: .zero,
            temperatureTextOrigin: .zero,
            memoryTextOrigin: .zero,
            cpuTextOrigin: .zero
        )
        let spyRenderer = SpyStatusItemRenderer(rendered: RenderedStatusItem(image: dummyImage, geometry: geometry))

        let controller = StatusBarController(
            statusItemHost: fakeHost,
            launchController: stubLaunch,
            statusRenderer: spyRenderer,
            panelSessionFactory: { config in
                let spy = SpyPanelSession(configuration: config)
                createdSpy = spy
                return spy
            }
        )

        controller.togglePanelForTesting()
        // 模拟触发开机自启申请
        controller.handleLaunchAtLoginRequest(true)
        expectTrue(createdSpy?.lastSetLaunchAtLoginState == false, "failed launch-at-login enable must restore false switch state")
    }

    private static func testPanelSessionInjectsThresholdConfigWithoutUserDefaultLoad() {
        let injectedConfig = ThresholdConfig(
            power: MetricThreshold(orange: 99, red: 100),
            temperature: MetricThreshold(orange: 77, red: 88),
            cpu: MetricThreshold(orange: 55, red: 66)
        )

        let sessionConfig = PanelSessionConfiguration(
            identity: UUID(),
            anchorButtonProvider: { nil },
            refreshInterval: 1.0,
            thresholdConfig: injectedConfig,
            launchAtLoginEnabled: false,
            onRefreshIntervalChanged: { _ in },
            onThresholdConfigChanged: { _ in },
            onLaunchAtLoginToggled: { _ in },
            onCheckForUpdates: { $0(.upToDate) },
            onQuit: {},
            onDismissRequested: { _ in },
            onDidClose: { _ in }
        )

        let session = PanelSession(configuration: sessionConfig)
        expectTrue(session.isVisible == false, "session initial state should be closed")
    }

    private static func testPanelSessionShowsAllCollapsedRows() {
        let configuration = PanelSessionConfiguration(
            identity: UUID(),
            anchorButtonProvider: { nil },
            refreshInterval: 1.0,
            thresholdConfig: .defaults(),
            launchAtLoginEnabled: false,
            onRefreshIntervalChanged: { _ in },
            onThresholdConfigChanged: { _ in },
            onLaunchAtLoginToggled: { _ in },
            onCheckForUpdates: { $0(.upToDate) },
            onQuit: {},
            onDismissRequested: { _ in },
            onDidClose: { _ in }
        )
        let session = PanelSession(configuration: configuration)
        let panel = Mirror(reflecting: session).children
            .first(where: { $0.label == "panel" })?.value as? NSPanel
        let root = panel?.contentView
        root?.layoutSubtreeIfNeeded()

        expectEqual(
            Double(panel?.frame.height ?? -1),
            398.0,
            "collapsed panel must fit all rows"
        )

        let moreRow: NSView? = root.flatMap {
            descendant(in: $0, identifier: "control.more.row")
        }
        let quitRow: NSView? = root.flatMap {
            descendant(in: $0, identifier: "control.quit.button")
        }
        for (name, row) in [("more", moreRow), ("quit", quitRow)] {
            guard let root, let row, let superview = row.superview else {
                recordFailure("\(name) row must exist")
                continue
            }
            let origin = superview.convert(row.frame.origin, to: root)
            expectTrue(origin.y >= 0, "\(name) row must not be clipped below the panel")
            expectTrue(
                origin.y + row.frame.height <= root.bounds.height,
                "\(name) row must fit inside the panel"
            )
        }
    }

    private static func testSystemStatusItemHostDarkAquaFallback() {
        let appearance = SystemStatusItemHost.resolvedEffectiveAppearance(hostedAppearance: nil)
        expectEqual(appearance.name.rawValue, NSAppearance.Name.darkAqua.rawValue, "initial status item host appearance must fallback to darkAqua to prevent black text")
    }

    private static func testStatusItemHighlightCoordinatorDefersOpeningAndClosesImmediately() {
        var scheduled: [() -> Void] = []
        var applied: [Bool] = []
        let coordinator = StatusItemHighlightCoordinator(
            schedule: { scheduled.append($0) },
            apply: { applied.append($0) }
        )

        coordinator.setPanelPresented(true)
        expectEqual(Double(applied.count), 0, "opening highlight must be deferred until button tracking ends")
        expectEqual(Double(scheduled.count), 1, "opening must schedule exactly one next-run-loop application")

        scheduled.removeFirst()()
        expectTrue(applied == [true], "scheduled opening must apply native highlight once")

        coordinator.setPanelPresented(false)
        expectTrue(applied == [true, false], "closing must remove highlight synchronously")
    }

    private static func testStatusItemHighlightCoordinatorRejectsStaleOpening() {
        var scheduled: [() -> Void] = []
        var applied: [Bool] = []
        let coordinator = StatusItemHighlightCoordinator(
            schedule: { scheduled.append($0) },
            apply: { applied.append($0) }
        )

        coordinator.setPanelPresented(true)
        coordinator.setPanelPresented(false)
        scheduled.removeFirst()()

        expectTrue(applied == [false], "stale opening task must not re-highlight after a close request")
        expectFalse(coordinator.desiredPresented, "latest desired presentation must remain closed")
    }

    private static func makeStatusBarControllerForPanelTests(
        host: FakeStatusItemHost,
        panelSessionFactory: @escaping PanelSessionFactory
    ) -> StatusBarController {
        let image = NSImage(size: NSSize(width: 100, height: 22))
        let geometry = StatusItemGeometry(
            canvasSize: NSSize(width: 100, height: 22),
            powerIconFrame: .zero,
            temperatureIconFrame: .zero,
            memoryIconFrame: .zero,
            cpuIconFrame: .zero,
            powerTextOrigin: .zero,
            temperatureTextOrigin: .zero,
            memoryTextOrigin: .zero,
            cpuTextOrigin: .zero
        )
        let renderer = SpyStatusItemRenderer(
            rendered: RenderedStatusItem(image: image, geometry: geometry)
        )
        return StatusBarController(
            statusItemHost: host,
            launchController: StubLaunchController(),
            statusRenderer: renderer,
            panelSessionFactory: panelSessionFactory
        )
    }

    private static func testStatusBarControllerRollsBackFailedPanelShow() {
        let host = FakeStatusItemHost()
        var spy: SpyPanelSession?
        let controller = makeStatusBarControllerForPanelTests(host: host) { config in
            let session = SpyPanelSession(configuration: config)
            session.showResult = false
            spy = session
            return session
        }

        controller.togglePanelForTesting()

        expectTrue(host.panelPresentationRequests == [false], "failed show must explicitly restore unhighlighted state")
        expectFalse(host.isPanelPresented, "failed show must not leave status item highlighted")
        expectFalse(controller.desiredPanelVisibleForTesting, "failed show must roll desired state back to closed")
        expectTrue(controller.hasPanelSessionForTesting == false, "failed show must release the unusable session")
        expectEqual(Double(spy?.showCount ?? 0), 1, "failed session must be attempted exactly once")
    }

    private static func testStatusBarControllerUnhighlightsBeforeCloseAnimationCompletes() {
        let host = FakeStatusItemHost()
        var spy: SpyPanelSession?
        let controller = makeStatusBarControllerForPanelTests(host: host) { config in
            let session = SpyPanelSession(configuration: config)
            spy = session
            return session
        }

        controller.togglePanelForTesting()
        expectTrue(host.isPanelPresented, "successful open must request persistent highlight")

        controller.togglePanelForTesting()
        expectFalse(host.isPanelPresented, "close click must remove highlight before animation completion")
        expectEqual(Double(spy?.closeCount ?? 0), 1, "close transition must start exactly once")
        expectTrue(controller.hasPanelSessionForTesting, "session may remain retained until close animation completes")

        spy?.completeClose()
        expectTrue(controller.hasPanelSessionForTesting, "matching close completion retains session for reuse")
    }

    private static func testStatusBarControllerRoutesExternalDismissThroughDesiredState() {
        let host = FakeStatusItemHost()
        var spy: SpyPanelSession?
        let controller = makeStatusBarControllerForPanelTests(host: host) { config in
            let session = SpyPanelSession(configuration: config)
            spy = session
            return session
        }

        controller.togglePanelForTesting()
        spy?.requestDismiss(.outsideClick)

        expectFalse(controller.desiredPanelVisibleForTesting, "outside click must update the controller source of truth")
        expectFalse(host.isPanelPresented, "outside click must restore status item immediately")
        expectEqual(Double(spy?.closeCount ?? 0), 1, "outside click must enter the unified close path")
    }

    private static func testStatusBarControllerIgnoresStaleSessionCompletion() {
        let host = FakeStatusItemHost()
        var sessions: [SpyPanelSession] = []
        let controller = makeStatusBarControllerForPanelTests(host: host) { config in
            let session = SpyPanelSession(configuration: config)
            sessions.append(session)
            return session
        }

        controller.togglePanelForTesting() // open
        let first = sessions[0]
        controller.togglePanelForTesting() // start close
        controller.togglePanelForTesting() // reopen the same desired interaction
        first.completeClose()              // simulate an obsolete completion racing afterward

        expectTrue(controller.desiredPanelVisibleForTesting, "latest click must still require an open panel")
        expectTrue(host.isPanelPresented, "obsolete close completion must not remove current highlight")
        expectTrue(controller.hasPanelSessionForTesting, "obsolete completion must not clear the current session")
    }

    private static func testStatusItemRendererLeftAndRightInsetsAreSymmetrical() {
        let renderer = StatusItemRenderer()
        let snapshot = makePulseSnapshot(cpuUsage: 7)
        let thresholds = ThresholdConfig(
            power: MetricThreshold(orange: 20, red: 50),
            temperature: MetricThreshold(orange: 35, red: 40),
            cpu: MetricThreshold(orange: 60, red: 80)
        )
        let model = StatusItemRenderModel.make(snapshot: snapshot, thresholds: thresholds)
        let geometry = renderer.layout(for: model)

        let leftMargin = geometry.powerIconFrame.minX
        let font: NSFont = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let maxRightTextWidth = max(
            (model.memoryText as NSString).size(withAttributes: [.font: font]).width,
            (model.cpuText as NSString).size(withAttributes: [.font: font]).width
        )
        let rightMargin = geometry.canvasSize.width - (geometry.memoryTextOrigin.x + maxRightTextWidth)

        expectEqual(Double(leftMargin), 5.0, "status item left inset must be exactly 5.0 pt")
        expectTrue(abs(rightMargin - 5.0) < 0.2, "status item right inset must be approximately 5.0 pt (symmetrical with left inset)")
    }

    private static func testPopoverThresholdMatrixStructure() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: PopoverContentView.collapsedHeight)
        )
        let moreButton: NSButton? = descendant(in: view, identifier: "control.more.button")
        if let moreButton, let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton)
        }
        view.frame.size.height = view.computeTotalHeight()
        view.layoutSubtreeIfNeeded()

        let header: NSView? = descendant(in: view, identifier: "settings.threshold.header")
        expectTrue(header != nil, "threshold matrix must expose one semantic header")

        let sections = allDescendants(in: view).filter {
            guard let id = $0.identifier?.rawValue else { return false }
            return id.hasPrefix("settings.section.") && id.split(separator: ".").count == 3
        }
        expectEqual(Double(sections.count), 3, "threshold matrix must contain exactly three metric rows")

        let fieldContainers = allDescendants(in: view).filter {
            let id = $0.identifier?.rawValue ?? ""
            return id.hasSuffix(".orangeField") || id.hasSuffix(".redField")
        }
        expectEqual(Double(fieldContainers.count), 6, "each threshold must use one value-plus-unit field")

        let inputs = allDescendants(in: view).compactMap { $0 as? NumericInputView }.filter {
            let id = $0.identifier?.rawValue ?? ""
            return id.hasSuffix(".orangeInput") || id.hasSuffix(".redInput")
        }
        expectEqual(Double(inputs.count), 6, "all six numeric inputs must remain available")

        let visibleText = allDescendants(in: view).compactMap { ($0 as? NSTextField)?.stringValue }
        expectFalse(visibleText.contains("变橙"), "matrix must remove repeated orange labels")
        expectFalse(visibleText.contains("变红"), "matrix must remove repeated red labels")
        expectTrue(visibleText.contains("告警阈值"), "matrix header must name the edited values")
        expectTrue(visibleText.contains(where: { $0.contains("提醒") }), "matrix header must name the reminder column")
        expectTrue(visibleText.contains(where: { $0.contains("严重") }), "matrix header must name the critical column")
        expectTrue(
            visibleText.contains("内存压力由 macOS 系统管理，无需设置阈值"),
            "memory pressure must be concise non-editable information"
        )
        let updateRow: NSView? = descendant(in: view, identifier: "settings.update.row")
        expectTrue(updateRow != nil, "version and update controls must remain in the footer")
    }

    private static func testPopoverThresholdMatrixGeometry() {
        let view = PopoverContentView(frame: NSRect(x: 0, y: 0, width: 340, height: 398))
        let moreButton: NSButton? = descendant(in: view, identifier: "control.more.button")
        if let moreButton, let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton)
        }
        expectEqual(Double(view.computeTotalHeight() - 398), 196.0, "settings contribution must be 196pt")
        view.frame.size.height = view.computeTotalHeight()
        view.layoutSubtreeIfNeeded()

        let header: NSView? = descendant(in: view, identifier: "settings.threshold.header")
        let memoryNote: NSView? = descendant(in: view, identifier: "settings.memNote")
        let updateRow: NSView? = descendant(in: view, identifier: "settings.update.row")
        expectEqual(Double(header?.frame.minY ?? -1), 172.0, "header Y must be 172pt")
        expectEqual(Double(header?.frame.height ?? -1), 24.0, "header height must be 24pt")
        expectEqual(Double(memoryNote?.frame.minY ?? -1), 44.0, "memory note Y must be 44pt")
        expectEqual(Double(memoryNote?.frame.height ?? -1), 32.0, "memory note height must be 32pt")
        expectEqual(Double(updateRow?.frame.minY ?? -1), 0.0, "update row Y must be 0pt")
        expectEqual(Double(updateRow?.frame.height ?? -1), 36.0, "update row height must be 36pt")

        for (index, expectedY) in [140.0, 108.0, 76.0].enumerated() {
            let section: NSView? = descendant(in: view, identifier: "settings.section.\(index)")
            let orangeField: NSView? = descendant(in: view, identifier: "settings.section.\(index).orangeField")
            let redField: NSView? = descendant(in: view, identifier: "settings.section.\(index).redField")
            expectEqual(Double(section?.frame.minY ?? -1), expectedY, "threshold row Y must match order")
            expectEqual(Double(section?.frame.height ?? -1), 32.0, "threshold row height must be 32pt")
            expectEqual(Double(orangeField?.frame.minX ?? -1), 152.0, "reminder field X must be 152pt")
            expectEqual(Double(redField?.frame.minX ?? -1), 236.0, "critical field X must be 236pt")
            expectEqual(Double(orangeField?.frame.width ?? -1), 72.0, "reminder field width must be 72pt")
            expectEqual(Double(redField?.frame.width ?? -1), 72.0, "critical field width must be 72pt")
            expectEqual(Double(orangeField?.frame.height ?? -1), 24.0, "reminder field height must be 24pt")
            expectEqual(Double(redField?.frame.height ?? -1), 24.0, "critical field height must be 24pt")
        }
    }

    private static func testPopoverThresholdMatrixAccessibilityAndKeyboardOrder() {
        let view = PopoverContentView(frame: NSRect(x: 0, y: 0, width: 340, height: 398))
        let moreButton: NSButton? = descendant(in: view, identifier: "control.more.button")
        if let moreButton, let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton)
        }

        let ids = [
            "settings.section.0.orangeInput", "settings.section.0.redInput",
            "settings.section.1.orangeInput", "settings.section.1.redInput",
            "settings.section.2.orangeInput", "settings.section.2.redInput",
        ]
        let inputs: [NumericInputView] = ids.compactMap { descendant(in: view, identifier: $0) }
        expectEqual(Double(inputs.count), 6, "all threshold inputs must be keyboard reachable")

        let expectedLabels = [
            "系统负载提醒阈值，单位瓦", "系统负载严重阈值，单位瓦",
            "电池温度提醒阈值，单位摄氏度", "电池温度严重阈值，单位摄氏度",
            "CPU 使用提醒阈值，单位百分比", "CPU 使用严重阈值，单位百分比",
        ]
        for (input, expectedLabel) in zip(inputs, expectedLabels) {
            expectEqual(input.accessibilityLabel() ?? "", expectedLabel, "input semantics must be complete")
        }
        for index in 0..<(inputs.count - 1) {
            expectTrue(inputs[index].nextKeyView === inputs[index + 1], "Tab order must follow matrix order")
        }
        expectTrue(inputs.last?.nextKeyView === inputs.first, "Tab order must loop from last field back to first field")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 594),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.frame.size.height = view.computeTotalHeight()
        view.layoutSubtreeIfNeeded()

        window.makeFirstResponder(inputs[0])
        expectTrue(window.firstResponder === inputs[0], "field 0 must accept focus")

        window.makeFirstResponder(inputs[1])
        expectTrue(window.firstResponder === inputs[1], "field 1 must accept focus")

        window.makeFirstResponder(nil)
        expectTrue(window.firstResponder === window, "focus must clear cleanly when requested")

        let firstFieldContainer: NSView? = descendant(in: view, identifier: "settings.section.0.orangeField")
        firstFieldContainer?.mouseDown(with: NSEvent())
        expectTrue(window.firstResponder === inputs[0] || window.fieldEditor(false, for: inputs[0]) === window.firstResponder, "clicking anywhere on card container must focus numeric input")
    }

    private static func testPopoverOpticalAlignmentAndUpdateLoadingState() {
        let view = PopoverContentView(frame: NSRect(x: 0, y: 0, width: 340, height: 398))
        let moreButton: NSButton? = descendant(in: view, identifier: "control.more.button")
        if let moreButton, let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton)
        }
        view.frame.size.height = view.computeTotalHeight()
        view.layoutSubtreeIfNeeded()

        let separators = allDescendants(in: view).filter {
            $0.identifier?.rawValue.hasPrefix("settings.separator.") == true
        }
        expectEqual(Double(separators.count), 5, "there must be exactly 5 settings separators")

        let separatorXs = separators.map(\.frame.minX)
        expectTrue(separatorXs.filter { $0 == 16.0 }.count == 4 && separatorXs.contains(0.0), "4 inset separators at 16pt X and 1 main separator at 0pt X")

        let separatorYs = separators.map(\.frame.minY).sorted(by: >)
        expectEqual(Double(separatorYs.count), 5, "5 separators count")
        if separatorYs.count == 5 {
            expectEqual(Double(separatorYs[0]), 172.0, "separator 0 Y must be 172pt")
            expectEqual(Double(separatorYs[1]), 140.0, "separator 1 Y must be 140pt")
            expectEqual(Double(separatorYs[2]), 108.0, "separator 2 Y must be 108pt")
            expectEqual(Double(separatorYs[3]), 76.0, "separator 3 Y must be 76pt")
            expectEqual(Double(separatorYs[4]), 44.0, "separator 4 Y must be 44pt")
        }

        let memNote: NSView? = descendant(in: view, identifier: "settings.memNote")
        expectTrue(memNote != nil, "settings memNote should exist")
        if let memNote {
            expectEqual(Double(memNote.frame.height), 32.0, "memNote row height must be 32pt")
            let memLabel: NSView? = descendant(in: memNote, identifier: "settings.memNote.label")
            expectEqual(Double(memLabel?.frame.minX ?? -1), 38.0, "memLabel X must align with 38pt baseline")
        }

        let updateRow: NSView? = descendant(in: view, identifier: "settings.update.row")
        expectTrue(updateRow != nil, "settings update row should exist")
        if let updateRow {
            expectEqual(Double(updateRow.frame.height), 36.0, "update row height must be 36pt")
        }

        let versionLabel: NSTextField? = descendant(in: view, identifier: "settings.version.label")
        expectTrue(versionLabel != nil, "settings version label should exist")
        expectTrue(versionLabel?.stringValue.hasPrefix("Pulse v") == true, "version label text should start with 'Pulse v'")

        let updateButton: NSButton? = descendant(in: view, identifier: "settings.update.button")
        expectTrue(updateButton != nil, "settings update button should exist")

        view.setUpdateChecking(true)
        expectEqual(updateButton?.title ?? "", "正在检查...", "update button title must change to loading text while checking")
        expectFalse(updateButton?.isEnabled ?? true, "update button must be disabled while checking")

        view.setUpdateChecking(false)
        expectEqual(updateButton?.title ?? "", "检查更新", "update button title must restore default text after checking")
        expectTrue(updateButton?.isEnabled ?? false, "update button must be enabled after checking")

        if let updateRow {
            view.setUpdateResult(.upToDate)
            view.layoutSubtreeIfNeeded()
            let upToDateLabel: NSView? = descendant(in: updateRow, identifier: "update.state.upToDate")
            expectTrue(upToDateLabel != nil, "upToDate label must be present")
            if let label = upToDateLabel {
                expectTrue(updateRow.bounds.contains(label.frame), "upToDate label must lie within update row bounds")
            }

            view.setUpdateResult(.updateAvailable("2.0.0"))
            view.layoutSubtreeIfNeeded()
            let availLabel: NSView? = descendant(in: updateRow, identifier: "update.state.available")
            let dlBtn: NSView? = descendant(in: updateRow, identifier: "update.state.downloadButton")
            expectTrue(availLabel != nil && dlBtn != nil, "available update views must be present")
            if let availLabel, let dlBtn {
                expectTrue(updateRow.bounds.contains(availLabel.frame), "available label must lie within update row bounds")
                expectTrue(updateRow.bounds.contains(dlBtn.frame), "download button must lie within update row bounds")
            }
        }
    }

    private static func testPanelSessionReusedAcrossToggleCycles() {
        let host = FakeStatusItemHost()
        var createdCount = 0

        let controller = makeStatusBarControllerForPanelTests(host: host) { config in
            createdCount += 1
            return SpyPanelSession(configuration: config)
        }

        // 第一次展开面板
        controller.togglePanelForTesting()
        expectTrue(controller.hasPanelSessionForTesting, "first panel session should exist")
        expectEqual(Double(createdCount), 1.0, "panelSession should be created once on first show")

        // 关闭面板
        controller.togglePanelForTesting()

        // 第二次展开面板：必须复用已有 Session，绝对不能再次调用 makePanelSession()！
        controller.togglePanelForTesting()
        expectTrue(controller.hasPanelSessionForTesting, "panel session should still exist on reuse")
        expectEqual(Double(createdCount), 1.0, "panelSession must be REUSED without invoking factory again")
    }

    private static func testMemoryPressureDestroysHiddenPanelSession() {
        let host = FakeStatusItemHost()
        let controller = makeStatusBarControllerForPanelTests(host: host) { config in
            SpyPanelSession(configuration: config)
        }

        controller.togglePanelForTesting()
        expectTrue(controller.hasPanelSessionForTesting, "session should exist when visible")

        controller.togglePanelForTesting()

        // 模拟内存压力通知触发清理
        controller.handleMemoryPressureWarning()
        expectFalse(controller.hasPanelSessionForTesting, "hidden panelSession must be destroyed on memory pressure warning")
    }

    private static func getProcessMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }

    private static func testPanelSessionMemoryLeakBenchmark() {
        let host = FakeStatusItemHost()
        let controller = makeStatusBarControllerForPanelTests(host: host) { config in
            SpyPanelSession(configuration: config)
        }

        // 第一次打开与关闭，确立常驻基础工作集
        controller.togglePanelForTesting()
        controller.togglePanelForTesting()
        let baselineMB = getProcessMemoryMB()

        // 连续模拟 100 次打开/关闭循环压测
        for _ in 1...100 {
            controller.togglePanelForTesting()
            controller.update(snapshot: makePulseSnapshot(cpuUsage: 25))
            controller.togglePanelForTesting()
        }

        let afterCyclesMB = getProcessMemoryMB()
        let memoryDeltaMB = afterCyclesMB - baselineMB

        // 断言 100 次循环后物理内存 RSS 增量必须低于 1.0 MB
        expectTrue(memoryDeltaMB < 1.0, "memory delta after 100 open/close cycles must be under 1.0 MB (got \(memoryDeltaMB) MB)")
    }

    private static func testPopoverMetricCardGridGeometry() {
        let view = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: 340, height: 398)
        )
        view.layoutSubtreeIfNeeded()

        let pairFrames = (0..<3).compactMap { index -> NSRect? in
            let pair: NSView? = descendant(in: view, identifier: "metric.pair.\(index)")
            return pair?.frame
        }
        expectEqual(Double(pairFrames.count), 3.0, "metrics must render as exactly three shared pair cards")
        for frame in pairFrames {
            expectEqual(Double(frame.height), 58.0, "each shared pair card must be 58.0 pt high")
        }
        if pairFrames.count == 3 {
            expectTrue(
                pairFrames[0].minY > pairFrames[1].maxY
                    && pairFrames[1].minY > pairFrames[2].maxY,
                "shared pair cards must descend with visible gaps and no overlap"
            )
            expectTrue(
                Set(pairFrames.map { Int($0.width.rounded()) }).count == 1,
                "all three shared pair cards must use the same full width"
            )
        }

        let orderedRows = [
            ["power", "cpu"],
            ["memoryUsage", "memoryPressure"],
            ["temperature", "powerSource"],
        ]
        let cardFrames = orderedRows.map { keys in
            keys.compactMap { key -> NSRect? in
                let card: NSView? = descendant(in: view, identifier: "metric.\(key).row")
                return card?.frame
            }
        }

        expectTrue(
            cardFrames.allSatisfy { $0.count == 2 },
            "every metric grid row must contain exactly two cards"
        )
        for frames in cardFrames where frames.count == 2 {
            expectEqual(Double(frames[0].minY), Double(frames[1].minY), "paired cards must share one row")
            expectTrue(frames[0].minX < frames[1].minX, "the first metric in each pair must occupy the left column")
            expectEqual(Double(frames[0].height), 58.0, "left metric card height must be 58.0 pt")
            expectEqual(Double(frames[1].height), 58.0, "right metric card height must be 58.0 pt")
            expectEqual(Double(frames[0].width), Double(frames[1].width), "grid columns must have equal widths")
            expectEqual(
                Double(frames[0].maxX),
                Double(frames[1].minX),
                "paired metric cells must meet at one shared central divider"
            )
        }
        if cardFrames.allSatisfy({ $0.count == 2 }) {
            expectTrue(
                cardFrames[0][0].minY > cardFrames[1][0].maxY
                    && cardFrames[1][0].minY > cardFrames[2][0].maxY,
                "metric card rows must descend with visible gaps and no overlap"
            )
        }
    }

    private static func testPopoverInlineUpdateStateTransitions() {
        let view = PopoverContentView(frame: NSRect(x: 0, y: 0, width: 340, height: 416))
        let moreButton: NSButton? = descendant(in: view, identifier: "control.more.button")
        if let moreButton, let action = moreButton.action, let target = moreButton.target {
            NSApp.sendAction(action, to: target, from: moreButton)
        }
        view.layoutSubtreeIfNeeded()

        view.setUpdateResult(.upToDate)
        let upToDateLabel = descendant(in: view, identifier: "update.state.upToDate")
        expectTrue(upToDateLabel != nil, "inline upToDate indicator must be visible on upToDate result")

        view.setUpdateResult(.updateAvailable("1.1.0"))
        let updateAvailableLabel = descendant(in: view, identifier: "update.state.available")
        expectTrue(updateAvailableLabel != nil, "inline updateAvailable indicator must be visible on updateAvailable result")
    }

    private static func testPopoverMetricValuesUseLabelColor() {
        let view = PopoverContentView(frame: NSRect(x: 0, y: 0, width: 340, height: 432))
        view.update(snapshot: makePulseSnapshot(
            power: 25.0,
            memoryUsagePercentage: 80.0,
            pressureLevel: .warning,
            temperature: 38.0,
            cpuUsage: 70.0
        ))

        for key in ["power", "temperature", "memoryUsage", "memoryPressure", "cpu", "powerSource"] {
            let label: NSTextField? = descendant(in: view, identifier: "metric.\(key).value")
            expectTrue(
                label?.textColor?.isEqual(NSColor.labelColor) == true,
                "detail value \(key) must use labelColor"
            )
        }
    }

    private static func expectFalse(_ actual: Bool, _ message: String) {
        expectTrue(!actual, message)
    }

    private static func recordSuccess() {
        passed += 1
    }

    private static func recordFailure(_ message: String) {
        failed += 1
        fputs("FAIL: \(message)\n", stderr)
    }
}
