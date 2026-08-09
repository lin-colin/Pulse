import AppKit

/// 把面板目标状态映射为按钮高亮时序，并拒绝过期的异步打开任务。
final class StatusItemHighlightCoordinator {
    typealias Scheduler = (@escaping () -> Void) -> Void

    private let schedule: Scheduler
    private let apply: (Bool) -> Void
    private(set) var desiredPresented = false

    init(schedule: @escaping Scheduler, apply: @escaping (Bool) -> Void) {
        self.schedule = schedule
        self.apply = apply
    }

    func setPanelPresented(_ presented: Bool) {
        desiredPresented = presented

        if !presented {
            // 为什么：用户发出关闭意图后，菜单栏应立即恢复，不能等待面板动画结束。
            apply(false)
            return
        }

        // 为什么：等待当前 NSButton 鼠标跟踪完成，避免 AppKit 在 action 返回后覆盖持久高亮。
        schedule { [weak self] in
            guard let self, self.desiredPresented else { return }
            self.apply(true)
        }
    }
}

/// 状态栏 host 接口，解耦生产环境 NSStatusItem 与测试假对象。
protocol StatusItemHosting: AnyObject {
    var image: NSImage? { get set }
    var length: CGFloat { get set }
    var isAttachedToWindow: Bool { get }
    var effectiveAppearance: NSAppearance { get }
    var backingScaleFactor: CGFloat { get }
    var anchorButton: NSStatusBarButton? { get }
    var onRenderEnvironmentChanged: (() -> Void)? { get set }

    func setPanelPresented(_ presented: Bool)
    func configure(target: AnyObject, action: Selector, accessibilityLabel: String)
    func remove()
}

/// 生产环境真实 NSStatusItem 适配器
final class SystemStatusItemHost: StatusItemHosting {
    private let statusItem: NSStatusItem
    var onRenderEnvironmentChanged: (() -> Void)?

    init(length: CGFloat = 80) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: length)
    }

    var image: NSImage? {
        get { statusItem.button?.image }
        set { statusItem.button?.image = newValue }
    }

    var length: CGFloat {
        get { statusItem.length }
        set { statusItem.length = newValue }
    }

    var isAttachedToWindow: Bool {
        statusItem.button?.window != nil
    }

    var effectiveAppearance: NSAppearance {
        let hostedAppearance = statusItem.button.flatMap { button in
            button.window == nil ? nil : button.effectiveAppearance
        }
        return Self.resolvedEffectiveAppearance(hostedAppearance: hostedAppearance)
    }

    static func resolvedEffectiveAppearance(hostedAppearance: NSAppearance?) -> NSAppearance {
        // 为什么：若托管窗口的外观包含深色等特化外观则使用；
        // 若启动初期尚未关联窗口或回退为 aqua / vibrantLight，显式保底为 darkAqua，
        // 确保 labelColor 在位图栅格化时绝对求值为白色，杜绝前 3 秒黑字。
        if let hostedAppearance,
           hostedAppearance.name != .aqua,
           hostedAppearance.name != .vibrantLight {
            return hostedAppearance
        }
        return NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()
    }

    var backingScaleFactor: CGFloat {
        statusItem.button?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }

    var anchorButton: NSStatusBarButton? {
        statusItem.button
    }

    private lazy var highlightCoordinator = StatusItemHighlightCoordinator(
        schedule: { work in DispatchQueue.main.async(execute: work) },
        apply: { [weak self] highlighted in
            self?.statusItem.button?.highlight(highlighted)
        }
    )

    func setPanelPresented(_ presented: Bool) {
        highlightCoordinator.setPanelPresented(presented)
    }

    func configure(target: AnyObject, action: Selector, accessibilityLabel: String) {
        guard let button = statusItem.button else { return }
        // 为什么：只使用原生 NSStatusBarButton 显示栅格化位图，不往按钮内部添加 AppKit 子视图。
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = target
        button.action = action
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel(accessibilityLabel)

        // 为什么：监听屏幕参数与系统环境变更的通知，一旦主题/显示参数改变，立即触发环境重绘。
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowAppearanceChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func remove() {
        setPanelPresented(false)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // 为什么：显式从系统状态栏注销 statusItem，释放资源。
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func handleWindowAppearanceChanged(_ notification: Notification) {
        onRenderEnvironmentChanged?()
    }
}

/// 测试环境假状态栏 host 对象
final class FakeStatusItemHost: StatusItemHosting {
    var image: NSImage?
    var length: CGFloat = 80
    var isAttachedToWindow: Bool
    var effectiveAppearance: NSAppearance
    var backingScaleFactor: CGFloat
    var anchorButton: NSStatusBarButton?
    var onRenderEnvironmentChanged: (() -> Void)?

    private(set) var panelPresentationRequests: [Bool] = []
    private(set) var isPanelPresented = false

    func setPanelPresented(_ presented: Bool) {
        panelPresentationRequests.append(presented)
        isPanelPresented = presented
    }

    init(
        isAttachedToWindow: Bool = true,
        effectiveAppearance: NSAppearance = NSAppearance(named: .darkAqua)!,
        backingScaleFactor: CGFloat = 2.0
    ) {
        self.isAttachedToWindow = isAttachedToWindow
        self.effectiveAppearance = effectiveAppearance
        self.backingScaleFactor = backingScaleFactor
    }

    func configure(target: AnyObject, action: Selector, accessibilityLabel: String) {}

    func remove() {}
}
