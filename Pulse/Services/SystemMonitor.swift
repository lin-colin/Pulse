import Foundation
import Darwin

/// 系统监控模块
public class SystemMonitor {
    
    // 用于保存上一次的 CPU ticks 快照
    private var previousCPUInfo: [processor_cpu_load_info_data_t] = []
    
    // CPU 快照线程安全锁
    private let lock = NSLock()

    // 内存压力由事件和低频 sysctl 共同更新，因此必须用独立锁保护跨线程状态。
    private let memoryPressureLock = NSLock()
    // 注入 VM 读取器是为了让使用率测试不依赖当前机器的实时页统计。
    private let memoryStatisticsReader: () -> MemoryPageStatistics?
    // 当前压力的 sysctl 被封装为单一依赖，避免测试制造真实内存压力。
    private let pressureLevelReader: () -> Int32?
    // 单调时钟同样可注入，才能确定性覆盖重同步边界和时间倒退。
    private let uptimeReader: () -> TimeInterval
    // 缓存只保存离散内核状态，不再把空闲百分比伪装成压力百分比。
    private var cachedPressureLevel: MemoryPressureLevel
    // 记录最近一次 sysctl 或有效事件时间，用于限制低频校验频率。
    private var pressureLevelReadAtUptime: TimeInterval
    // 每个有效事件递增代次，使较早启动的 sysctl 结果不能覆盖更新事件。
    private var pressureStateGeneration: UInt64 = 0
    // 单次飞行标记让并发快照共用一次重同步，避免同时重复调用 sysctl。
    private var isPressureResyncInFlight = false
    // 必须强引用 DispatchSource，否则初始化结束后事件监听会立即失效。
    private var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    // 为什么：CPU 标称频率不会按刷新周期变化，初始化一次可避免稳定失败的 sysctl 热路径。
    private let cachedCPUFrequency: Double

    /// 默认采集器直接使用 Mach、sysctl 和常驻 DispatchSource，不创建外部进程。
    public convenience init() {
        self.init(
            memoryStatisticsReader: SystemMonitor.readMemoryStatistics,
            pressureLevelReader: SystemMonitor.readKernelMemoryPressureLevel,
            startPressureEvents: true,
            uptimeReader: { ProcessInfo.processInfo.systemUptime },
            cpuFrequencyReader: SystemMonitor.readCPUFrequency
        )
    }

    /// 注入只读来源，使压力变化和失败降级无需制造真实内存压力即可测试。
    init(
        memoryStatisticsReader: @escaping () -> MemoryPageStatistics?,
        pressureLevelReader: @escaping () -> Int32?,
        startPressureEvents: Bool,
        uptimeReader: @escaping () -> TimeInterval,
        cpuFrequencyReader: () -> Double = SystemMonitor.readCPUFrequency
    ) {
        self.memoryStatisticsReader = memoryStatisticsReader
        self.pressureLevelReader = pressureLevelReader
        self.uptimeReader = uptimeReader
        // 为什么：CPU 标称硬件频率仅在初始化时提取一次并进行缓存，不再按每秒刷新重复发起 sysctl 调用。
        cachedCPUFrequency = cpuFrequencyReader()
        // DispatchSource 不保证启动即发送当前状态，所以初始化 sysctl 读取不可省略。
        cachedPressureLevel = MemoryPressureLevel(rawKernelValue: pressureLevelReader())
        pressureLevelReadAtUptime = uptimeReader()

        if startPressureEvents {
            // 生产路径开启常驻监听；测试关闭它以排除真实系统事件造成的不确定性。
            startMemoryPressureEvents()
        }
    }

    deinit {
        // 取消事件源可及时释放 GCD 资源，并避免对象生命周期结束后仍有回调。
        memoryPressureSource?.cancel()
    }
    
    /// 获取 CPU 使用率
    /// - Returns: 返回总 CPU 使用率百分比 (0-100)
    public func getCPUUsage() -> Double {
        lock.lock()
        defer { lock.unlock() }
        
        var processorMsgCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        
        let hostPort = mach_host_self()
        guard hostPort != mach_port_t(MACH_PORT_NULL) else {
            return 0.0
        }
        defer {
            // 为什么：mach_host_self 每次调用都会递增当前 task 的发送权引用计数（send-right reference），
            // 必须使用 mach_port_deallocate 进行显式平衡归还，避免长期运行导致端口引用泄漏。
            mach_port_deallocate(mach_task_self_, hostPort)
        }

        // 使用 Mach 内核 API 获取处理器信息
        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )
        
        guard result == KERN_SUCCESS, let processorInfo = processorInfo else {
            return 0.0
        }
        
        // 必须调用 vm_deallocate 释放内存
        defer {
            let infoSize = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: processorInfo), infoSize)
        }
        
        let cpuLoadInfo = processorInfo.withMemoryRebound(to: processor_cpu_load_info_data_t.self, capacity: Int(processorCount)) { $0 }
        
        var totalUserDiff: UInt32 = 0
        var totalSystemDiff: UInt32 = 0
        var totalIdleDiff: UInt32 = 0
        var totalNiceDiff: UInt32 = 0
        
        let isFirstRun = previousCPUInfo.count != Int(processorCount)
        var currentCPUInfo: [processor_cpu_load_info_data_t] = []
        
        for i in 0..<Int(processorCount) {
            let info = cpuLoadInfo[i]
            currentCPUInfo.append(info)
            
            // 获取各状态的 ticks
            let user = info.cpu_ticks.0     // CPU_STATE_USER
            let system = info.cpu_ticks.1   // CPU_STATE_SYSTEM
            let idle = info.cpu_ticks.2     // CPU_STATE_IDLE
            let nice = info.cpu_ticks.3     // CPU_STATE_NICE
            
            if !isFirstRun {
                let prevInfo = previousCPUInfo[i]
                
                let prevUser = prevInfo.cpu_ticks.0
                let prevSystem = prevInfo.cpu_ticks.1
                let prevIdle = prevInfo.cpu_ticks.2
                let prevNice = prevInfo.cpu_ticks.3
                
                // 计算增量
                totalUserDiff &+= (user >= prevUser) ? (user - prevUser) : 0
                totalSystemDiff &+= (system >= prevSystem) ? (system - prevSystem) : 0
                totalIdleDiff &+= (idle >= prevIdle) ? (idle - prevIdle) : 0
                totalNiceDiff &+= (nice >= prevNice) ? (nice - prevNice) : 0
            } else {
                totalUserDiff &+= user
                totalSystemDiff &+= system
                totalIdleDiff &+= idle
                totalNiceDiff &+= nice
            }
        }
        
        // 保存当前的 ticks 快照
        previousCPUInfo = currentCPUInfo
        
        let totalDiff = totalUserDiff + totalSystemDiff + totalIdleDiff + totalNiceDiff
        if totalDiff == 0 {
            return 0.0
        }
        
        // 计算使用率 = (user + system + nice) / total * 100
        let usage = Double(totalUserDiff + totalSystemDiff + totalNiceDiff) / Double(totalDiff) * 100.0
        return min(max(usage, 0.0), 100.0)
    }
    
    /// 获取 CPU 频率
    /// - Returns: 返回 CPU 频率 (GHz)
    public func getCPUFrequency() -> Double {
        // 为什么：返回已在初始化阶段完成读取的缓存标称频率，避免热路径频繁 sysctl 查询。
        cachedCPUFrequency
    }

    private static func readCPUFrequency() -> Double {
        for key in ["hw.cpufrequency", "hw.cpufrequency_max"] {
            var frequency: UInt64 = 0
            var size = MemoryLayout<UInt64>.size
            if sysctlbyname(key, &frequency, &size, nil, 0) == 0,
               size == MemoryLayout<UInt64>.size,
               frequency > 0 {
                return Double(frequency) / 1_000_000_000.0
            }
        }
        return 0.0
    }
    
    /// 读取同一刷新周期的真实使用率与独立压力状态；压力仅做低频 sysctl 校验。
    func getMemorySnapshot(nowUptime: TimeInterval? = nil) -> MemorySnapshot {
        let now = nowUptime ?? uptimeReader()
        let pressureLevel = currentPressureLevel(nowUptime: now)
        // VM 统计每次刷新都重新读取，避免把压力缓存策略误用于使用率。
        return MetricCalculations.memorySnapshot(
            statistics: memoryStatisticsReader(),
            pressureLevel: pressureLevel
        )
    }

    /// 在三十秒边界或时间倒退时重读；一次失败不能抹掉最后可信状态。
    private func currentPressureLevel(nowUptime: TimeInterval) -> MemoryPressureLevel {
        memoryPressureLock.lock()
        let elapsed = nowUptime - pressureLevelReadAtUptime
        let shouldResynchronize =
            elapsed < 0 || elapsed >= PulseDefaults.memoryPressureResyncInterval
        guard shouldResynchronize, !isPressureResyncInFlight else {
            // 已有读取进行中时立即返回缓存，不能让每秒快照排队等待 sysctl。
            let level = cachedPressureLevel
            memoryPressureLock.unlock()
            return level
        }

        isPressureResyncInFlight = true
        // 保存启动代次用于提交时识别读取期间是否发生了更新事件。
        let startingGeneration = pressureStateGeneration
        memoryPressureLock.unlock()

        // 注入 reader 可能阻塞或同步回调监控器，必须完全在状态锁外执行。
        let measuredLevel = MemoryPressureLevel(rawKernelValue: pressureLevelReader())

        memoryPressureLock.lock()
        isPressureResyncInFlight = false
        if pressureStateGeneration == startingGeneration {
            if measuredLevel != .unavailable {
                // 只有未过期的已知内核值才有资格覆盖上一次可信状态。
                cachedPressureLevel = measuredLevel
            }
            // 失败也推进尝试时间，防止每秒刷新退化成高频 sysctl 轮询。
            pressureLevelReadAtUptime = nowUptime
        }
        // 若代次已变化，事件同时更新了状态和时间戳，旧读取必须完整丢弃。
        let level = cachedPressureLevel
        memoryPressureLock.unlock()
        return level
    }

    /// Dispatch 可能合并多个事件位，所以始终按 critical、warning、normal 取最严重值。
    func recordMemoryPressureEvent(
        rawValue: UInt,
        nowUptime: TimeInterval? = nil
    ) {
        let event = DispatchSource.MemoryPressureEvent(rawValue: rawValue)
        let level: MemoryPressureLevel
        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else if event.contains(.normal) {
            level = .normal
        } else {
            // 未知位不代表健康状态，必须保持现有缓存而不是擅自降级。
            return
        }

        // 注入时钟也可能阻塞或回调监控器，所以必须在取得状态锁之前读取。
        let eventUptime = nowUptime ?? uptimeReader()
        memoryPressureLock.lock()
        cachedPressureLevel = level
        // 有效事件是最新可信状态，从事件时刻重新计算低频校验窗口。
        pressureLevelReadAtUptime = eventUptime
        // 代次变化使所有更早启动、尚未返回的 sysctl 结果自动失效。
        pressureStateGeneration &+= 1
        memoryPressureLock.unlock()
    }

    /// 创建并持有系统压力事件源，使 normal、warning、critical 变化可即时进入缓存。
    private func startMemoryPressureEvents() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: DispatchQueue(label: "com.hlc.pulse.memory-pressure", qos: .utility)
        )
        memoryPressureSource = source
        source.setEventHandler { [weak self] in
            // 通过弱引用打破 source-handler-monitor 的生命周期环。
            guard let self, let activeSource = self.memoryPressureSource else {
                return
            }
            self.recordMemoryPressureEvent(rawValue: activeSource.data.rawValue)
        }
        source.resume()
    }

    /// 直接读取 Mach 页统计，避免每次刷新创建外部进程或阻塞等待命令。
    private static func readMemoryStatistics() -> MemoryPageStatistics? {
        var totalBytes: UInt64 = 0
        var totalSize = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &totalBytes, &totalSize, nil, 0) == 0,
              totalSize == MemoryLayout<UInt64>.size else {
            return nil
        }

        let hostPort = mach_host_self()
        guard hostPort != mach_port_t(MACH_PORT_NULL) else {
            return nil
        }
        defer {
            // mach_host_self 增加一个发送权引用，采集结束必须显式归还。
            mach_port_deallocate(mach_task_self_, hostPort)
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(hostPort, &pageSize) == KERN_SUCCESS else {
            return nil
        }

        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }

        return MemoryPageStatistics(
            totalBytes: totalBytes,
            pageSize: UInt64(pageSize),
            freePages: UInt64(statistics.free_count),
            externalPages: UInt64(statistics.external_page_count)
        )
    }

    /// 未公开的当前压力级别只封装在此处；读取失败由上层保留最后可信状态。
    private static func readKernelMemoryPressureLevel() -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &value,
            &size,
            nil,
            0
        ) == 0,
        size == MemoryLayout<Int32>.size else {
            return nil
        }
        return value
    }
}
