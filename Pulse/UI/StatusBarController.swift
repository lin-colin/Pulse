import AppKit

/// 无边框面板子类；覆盖 canBecomeKey 使内部 NSSwitch 等控件渲染激活态蓝色。
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 管理一个动态宽度状态项与一个无边框原生面板。
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let customView: StatusItemView
    private let panel: StatusPanel
    private let contentView: PopoverContentView
    private let launchController: LaunchAtLoginControlling
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    private static let panelWidth: CGFloat = 340
    private static let panelHeight: CGFloat = 392

    var onRefreshIntervalChanged: ((TimeInterval) -> Void)?

    init(launchController: LaunchAtLoginControlling = LaunchAtLoginController()) {
        self.launchController = launchController
        statusItem = NSStatusBar.system.statusItem(withLength: 80)
        customView = StatusItemView(
            frame: NSRect(x: 0, y: 0, width: 80, height: 22)
        )
        contentView = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight)
        )
        panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        super.init()
        configurePanel()
        configureStatusButton()
        bindActions()
    }

    deinit {
        removeClickMonitors()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// 同一快照同时更新菜单栏与详情，并先同步父状态项宽度防止裁切。
    func update(snapshot: PulseSnapshot) {
        let requiredWidth = customView.update(
            power: snapshot.power,
            memoryUsagePercentage: snapshot.memory.usagePercentage,
            memoryPressureLevel: snapshot.memory.pressureLevel,
            temperature: snapshot.temperature,
            cpuUsage: snapshot.cpuUsage,
            isCharging: snapshot.powerSource.isCharging,
            isPluggedIn: snapshot.powerSource.isPluggedIn
        )
        statusItem.length = requiredWidth
        contentView.update(snapshot: snapshot)
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        contentView.setRefreshInterval(interval)
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
        contentView.setLaunchAtLoginEnabled(actualState)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight)
        )
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.state = .active
        // maskImage 对 NSVisualEffectView 的材质效果做圆角裁切，
        // 避免 layer.masksToBounds 无法裁切底层 compositing 导致的白色直角。
        visualEffect.maskImage = Self.roundedRectMask(cornerRadius: 12)

        contentView.frame = visualEffect.bounds
        contentView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(contentView)

        panel.contentView = visualEffect
    }

    /// 生成可拉伸的九宫格圆角蒙版，用于 NSVisualEffectView.maskImage。
    private static func roundedRectMask(cornerRadius: CGFloat) -> NSImage {
        let edgeLength = cornerRadius * 2 + 1
        let size = NSSize(width: edgeLength, height: edgeLength)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        customView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(customView)
        NSLayoutConstraint.activate([
            customView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            customView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            customView.topAnchor.constraint(equalTo: button.topAnchor),
            customView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func bindActions() {
        contentView.onRefreshIntervalChanged = { [weak self] interval in
            self?.onRefreshIntervalChanged?(interval)
        }
        contentView.onLaunchAtLoginToggled = { [weak self] requestedState in
            self?.handleLaunchAtLoginRequest(requestedState)
        }
        contentView.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        contentView.setLaunchAtLoginEnabled(launchController.isEnabled)
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if panel.isVisible {
            hidePanel()
            return
        }
        contentView.setLaunchAtLoginEnabled(launchController.isEnabled)
        showPanel(relativeTo: sender)
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        // 面板顶部紧贴菜单栏底部，水平居中于状态项。
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        var x = screenRect.midX - panelWidth / 2
        let y = screenRect.minY - panelHeight - 4

        // 确保面板不超出屏幕可见区域。
        let visibleFrame = screen.visibleFrame
        x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - panelWidth - 4))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        // 激活应用并设为 key window，使 NSSwitch 等控件渲染蓝色激活态。
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        addClickMonitors()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        removeClickMonitors()
    }

    private func addClickMonitors() {
        // 全局监控：用户点击了应用之外的区域时关闭面板。
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hidePanel()
        }
        // 本地监控：用户在应用窗口中点击了面板和状态项按钮之外的区域。
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window != self.panel,
               event.window != self.statusItem.button?.window {
                self.hidePanel()
            }
            return event
        }
        // 应用失去激活状态时（如 Cmd+Tab 切换）关闭面板。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    private func removeClickMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidResignActive() {
        hidePanel()
    }
}
