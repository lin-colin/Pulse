import AppKit

typealias PanelSessionFactory = (PanelSessionConfiguration) -> PanelSessionControlling

/// 管理原生菜单栏状态项并根据需要创建或释放详情面板 Session。
final class StatusBarController: NSObject {
    private struct StatusItemRenderKey: Equatable {
        let model: StatusItemRenderModel
        let appearanceName: String
        let backingScaleFactor: CGFloat
    }

    private let statusItemHost: StatusItemHosting
    private let launchController: LaunchAtLoginControlling
    private let statusRenderer: StatusItemRendering
    private let panelSessionFactory: PanelSessionFactory
    private var panelSession: PanelSessionControlling?
    private var thresholdConfig: ThresholdConfig
    private var currentRefreshInterval: TimeInterval = PulseDefaults.defaultRefreshInterval
    private var latestSnapshot: PulseSnapshot?
    private var lastRenderKey: StatusItemRenderKey?
    private var lastRenderedWidth: CGFloat?

    var onRefreshIntervalChanged: ((TimeInterval) -> Void)?

    init(
        statusItemHost: StatusItemHosting = SystemStatusItemHost(),
        launchController: LaunchAtLoginControlling = LaunchAtLoginController(),
        statusRenderer: StatusItemRendering = StatusItemRenderer(),
        panelSessionFactory: @escaping PanelSessionFactory = PanelSession.make,
        thresholdConfig: ThresholdConfig = .load()
    ) {
        self.statusItemHost = statusItemHost
        self.launchController = launchController
        self.statusRenderer = statusRenderer
        self.panelSessionFactory = panelSessionFactory
        // 为什么：初始化阶段只加载一次 ThresholdConfig，作为控制器的内存单一真相来源，禁止在刷新热路径每次读取 UserDefaults。
        self.thresholdConfig = thresholdConfig
        super.init()
        configureStatusHost()
        self.statusItemHost.onRenderEnvironmentChanged = { [weak self] in
            self?.renderLatestSnapshot(force: true)
        }
    }

    deinit {
        // 为什么：析构时显式关闭 session 并注销 statusItemHost，确保环境彻底干净。
        panelSession?.close()
        panelSession = nil
        statusItemHost.remove()
    }

    /// 为什么：根据当前快照构造纯模型并对比上次 Key。只有模型、外观或 scale 改变时才生成新位图；
    /// 仅当面板存在且可见时才更新详情内容，消除面板隐藏时的无效界面渲染。
    func update(snapshot: PulseSnapshot) {
        latestSnapshot = snapshot
        renderLatestSnapshot()

        // 为什么：仅在 PanelSession 存在且可见时更新详情面板；关闭时零更新开销。
        if panelSession?.isVisible == true {
            panelSession?.update(snapshot: snapshot)
        }
    }

    private func renderLatestSnapshot(force: Bool = false) {
        // 为什么：只在 statusItemHost 已真实挂接至托管窗口时才生成位图。
        // 避免在冷启动阶段使用缺省/未绑定的浅色外观生成黑字 bitmap。
        guard let snapshot = latestSnapshot,
              statusItemHost.isAttachedToWindow else {
            return
        }

        let model = StatusItemRenderModel.make(snapshot: snapshot, thresholds: thresholdConfig)
        let appearance = statusItemHost.effectiveAppearance
        let appearanceName = appearance.name.rawValue
        let scale = statusItemHost.backingScaleFactor
        let renderKey = StatusItemRenderKey(
            model: model,
            appearanceName: appearanceName,
            backingScaleFactor: scale
        )

        // 去重逻辑：强刷新或渲染 Key 变化时重新调用 CoreGraphics 栅格化绘制
        if force || renderKey != lastRenderKey {
            if let rendered = statusRenderer.render(
                model: model,
                appearance: appearance,
                backingScaleFactor: scale
            ) {
                statusItemHost.image = rendered.image

                let newWidth = rendered.geometry.canvasSize.width
                if let lastWidth = lastRenderedWidth {
                    if abs(newWidth - lastWidth) > 0.5 {
                        statusItemHost.length = newWidth
                        lastRenderedWidth = newWidth
                    }
                } else {
                    statusItemHost.length = newWidth
                    lastRenderedWidth = newWidth
                }
                lastRenderKey = renderKey
            }
        }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        currentRefreshInterval = interval
    }

    /// 为什么：无论系统操作成功或失败，都以服务重新报告的真实状态覆盖用户期望状态。
    func handleLaunchAtLoginRequest(_ requestedState: Bool) {
        let actualState = LaunchAtLoginSettings.apply(
            requestedState: requestedState,
            using: launchController,
            onError: { error in
                NSLog("Pulse 开机启动设置失败: %@", String(describing: error))
            }
        )
        panelSession?.setLaunchAtLoginEnabled(actualState)
    }

    func togglePanelForTesting() {
        togglePanel(self)
    }

    private func configureStatusHost() {
        statusItemHost.configure(
            target: self,
            action: #selector(togglePanel(_:)),
            accessibilityLabel: "Pulse 硬件心跳"
        )
    }

    @objc private func togglePanel(_ sender: Any) {
        if let session = panelSession {
            session.close()
            return
        }

        let configuration = PanelSessionConfiguration(
            anchorButtonProvider: { [weak self] in
                self?.statusItemHost.anchorButton
            },
            refreshInterval: currentRefreshInterval,
            thresholdConfig: thresholdConfig,
            launchAtLoginEnabled: launchController.isEnabled,
            onRefreshIntervalChanged: { [weak self] interval in
                self?.currentRefreshInterval = interval
                self?.onRefreshIntervalChanged?(interval)
            },
            onThresholdConfigChanged: { [weak self] newConfig in
                guard let self else { return }
                self.thresholdConfig = newConfig
                if let latestSnapshot = self.latestSnapshot {
                    self.update(snapshot: latestSnapshot)
                }
            },
            onLaunchAtLoginToggled: { [weak self] requestedState in
                self?.handleLaunchAtLoginRequest(requestedState)
            },
            onCheckForUpdates: {
                UpdateChecker.checkForUpdate { result in
                    UpdateChecker.showUpdateAlert(result: result)
                }
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            },
            onClose: { [weak self] in
                // 为什么：面板关闭回调触发时恢复按钮非高亮状态，并将 session 强引用置空，完成 UI 资源完全释放。
                self?.statusItemHost.isHighlighted = false
                self?.panelSession = nil
            }
        )

        let session = panelSessionFactory(configuration)
        panelSession = session
        statusItemHost.isHighlighted = true
        session.show()
        if let latestSnapshot {
            session.update(snapshot: latestSnapshot)
        }
    }
}
