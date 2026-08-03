import AppKit

/// 应用代理 - 管理生命周期与动态定时刷新
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController!
    private let hardwareMonitor = HardwareMonitor()
    private let systemMonitor = SystemMonitor()
    private let batteryMonitor = BatteryMonitor()

    private var refreshTimer: Timer?
    private let refreshQueue = DispatchQueue(
        label: "com.hlc.pulse.metrics-refresh",
        qos: .utility
    )

    // 仅在主线程读写，防止慢采集造成任务排队和重复系统进程。
    private var isRefreshInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()

        statusBar.onRefreshIntervalChanged = { [weak self] requestedInterval in
            let interval = PulseDefaults.validatedRefreshInterval(requestedInterval)
            UserDefaults.standard.set(interval, forKey: "refreshInterval")
            self?.startTimer(interval: interval)
        }

        refreshData()

        let savedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        let activeInterval = PulseDefaults.validatedRefreshInterval(savedInterval)
        statusBar.setRefreshInterval(activeInterval)
        startTimer(interval: activeInterval)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
    }

    private func startTimer(interval: TimeInterval) {
        stopTimer()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.refreshData()
        }

        if let timer = refreshTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func refreshData() {
        guard !isRefreshInProgress else {
            return
        }
        isRefreshInProgress = true

        refreshQueue.async { [weak self] in
            self?.collectAndDisplayMetrics()
        }
    }

    /// 在后台串行采集所有指标，仅将最终 UI 更新切回主线程。
    private func collectAndDisplayMetrics() {
        let hardware = hardwareMonitor.getSnapshot()
        // 同一轮刷新只读取一次内存快照，确保使用率与压力状态来自一致的数据流。
        let memory = systemMonitor.getMemorySnapshot()
        let cpuUsage = systemMonitor.getCPUUsage()
        let cpuFrequency = systemMonitor.getCPUFrequency()
        // 单轮只生成一份 IOKit 电源快照，供菜单栏和详情共同消费。
        let powerSource = batteryMonitor.getSnapshot()
        let snapshot = PulseSnapshot(
            power: hardware.systemLoadWatts,
            memory: memory,
            temperature: hardware.batteryTemperatureCelsius,
            cpuUsage: cpuUsage,
            cpuFrequency: cpuFrequency,
            powerSource: powerSource
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.statusBar.update(snapshot: snapshot)
            self.isRefreshInProgress = false
        }
    }
}
