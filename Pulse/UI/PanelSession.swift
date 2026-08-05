import AppKit
import QuartzCore

/// 面板 Session 配置闭包与属性集合
struct PanelSessionConfiguration {
    let anchorButtonProvider: () -> NSStatusBarButton?
    let refreshInterval: TimeInterval
    let thresholdConfig: ThresholdConfig
    let launchAtLoginEnabled: Bool
    let onRefreshIntervalChanged: (TimeInterval) -> Void
    let onThresholdConfigChanged: (ThresholdConfig) -> Void
    let onLaunchAtLoginToggled: (Bool) -> Void
    let onCheckForUpdates: () -> Void
    let onQuit: () -> Void
    let onClose: () -> Void
}

/// 详情面板 Session 接口
protocol PanelSessionControlling: AnyObject {
    var isVisible: Bool { get }
    func show()
    func update(snapshot: PulseSnapshot)
    func setLaunchAtLoginEnabled(_ enabled: Bool)
    func close()
}

/// 无边框面板子类；覆盖 canBecomeKey 使内部 NSSwitch 等控件渲染激活态蓝色。
private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 详情面板打开周期管理类
/// 为什么：把 NSPanel、NSVisualEffectView、PopoverContentView 及其点击/焦点监听器的生命周期完整封装在 Session 中。
/// 只有当用户点击菜单栏图标时才按需创建；面板关闭时立即注销所有监听器并 orderOut，释放全量详情视图树及渲染 backing store。
final class PanelSession: PanelSessionControlling {

    private static let panelWidth: CGFloat = 340
    private static let collapsedHeight: CGFloat = 432

    private let panel: StatusPanel
    private let contentView: PopoverContentView
    private let configuration: PanelSessionConfiguration
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var isClosing = false

    var isVisible: Bool {
        panel.isVisible
    }

    static func make(configuration: PanelSessionConfiguration) -> PanelSessionControlling {
        PanelSession(configuration: configuration)
    }

    init(configuration: PanelSessionConfiguration) {
        self.configuration = configuration

        contentView = PopoverContentView(
            frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.collapsedHeight),
            thresholdConfig: configuration.thresholdConfig
        )
        panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.collapsedHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        configurePanel()
        bindActions()
    }

    deinit {
        // 为什么：deinit 防御性移除监听器，确保对象释放后绝不留存全局 Event Monitor 闭包。
        removeClickMonitors()
    }

    func show() {
        guard let button = configuration.anchorButtonProvider(),
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        var x = screenRect.midX - panelWidth / 2.0
        let y = screenRect.minY - panelHeight - 4.0

        let visibleFrame = screen.visibleFrame
        x = max(visibleFrame.minX + 4.0, min(x, visibleFrame.maxX - panelWidth - 4.0))

        let targetOrigin = NSPoint(x: x, y: y)
        let startOrigin = NSPoint(x: x, y: y + 4.0)

        panel.alphaValue = 0.0
        panel.setFrameOrigin(startOrigin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        addClickMonitors()

        // 为什么：使用 0.15 秒 CAMediaTimingFunction(name: .easeOut) 实现 macOS 原生淡入与轻微位移动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(targetOrigin)
        }
    }

    func update(snapshot: PulseSnapshot) {
        contentView.update(snapshot: snapshot)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        contentView.setLaunchAtLoginEnabled(enabled)
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true

        removeClickMonitors()

        // 为什么：使用 0.12 秒淡出动画渐隐，动画完成后 orderOut 窗口并触发 onClose 回调销毁 session。
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.configuration.onClose()
        })
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
            frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.collapsedHeight)
        )
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.maskImage = Self.roundedRectMask(cornerRadius: 12)

        contentView.frame = visualEffect.bounds
        contentView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(contentView)

        panel.contentView = visualEffect
    }

    private func bindActions() {
        contentView.setRefreshInterval(configuration.refreshInterval)
        contentView.setLaunchAtLoginEnabled(configuration.launchAtLoginEnabled)

        contentView.onRefreshIntervalChanged = { [weak self] interval in
            self?.configuration.onRefreshIntervalChanged(interval)
        }
        contentView.onThresholdConfigChanged = { [weak self] config in
            self?.configuration.onThresholdConfigChanged(config)
        }
        contentView.onLaunchAtLoginToggled = { [weak self] enabled in
            self?.configuration.onLaunchAtLoginToggled(enabled)
        }
        contentView.onQuit = { [weak self] in
            self?.configuration.onQuit()
        }
        contentView.onCheckUpdate = { [weak self] in
            self?.configuration.onCheckForUpdates()
        }
        contentView.onPanelHeightChanged = { [weak self] newHeight in
            self?.updatePanelHeight(newHeight)
        }
    }

    private func updatePanelHeight(_ newHeight: CGFloat) {
        var frame = panel.frame
        let delta = newHeight - frame.height
        frame.origin.y -= delta
        frame.size.height = newHeight
        panel.setFrame(frame, display: true, animate: true)
    }

    static func shouldCloseForLocalClick(
        eventWindow: NSWindow?,
        panelWindow: NSWindow,
        anchorWindow: NSWindow?
    ) -> Bool {
        // 为什么：本地事件监听器必须排除详情面板窗口和状态栏锚点按钮窗口。
        // 避免在用户再次点击状态栏图标时由本地监听器抢先关闭 session，导致后续 togglePanel 重复创建弹开。
        if let eventWindow {
            if eventWindow === panelWindow { return false }
            if let anchorWindow, eventWindow === anchorWindow { return false }
        }
        return true
    }

    private func addClickMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.close()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            let anchorWindow = self.configuration.anchorButtonProvider()?.window
            if Self.shouldCloseForLocalClick(
                eventWindow: event.window,
                panelWindow: self.panel,
                anchorWindow: anchorWindow
            ) {
                self.close()
            }
            return event
        }
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
        close()
    }

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
}
