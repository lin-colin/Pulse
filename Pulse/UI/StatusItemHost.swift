import AppKit

/// 状态栏 host 接口，解耦生产环境 NSStatusItem 与测试假对象。
protocol StatusItemHosting: AnyObject {
    var image: NSImage? { get set }
    var length: CGFloat { get set }
    var isAttachedToWindow: Bool { get }
    var effectiveAppearance: NSAppearance { get }
    var backingScaleFactor: CGFloat { get }
    var anchorButton: NSStatusBarButton? { get }
    var onRenderEnvironmentChanged: (() -> Void)? { get set }

    var isHighlighted: Bool { get set }
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
        if let button = statusItem.button, button.window != nil {
            let appearance = button.effectiveAppearance
            // 为什么：若托管窗口的外观包含深色等特化外观则使用；
            // 若启动初期由于窗口层级尚未完全关联到系统深色菜单栏宿主而回退为 aqua / vibrantLight，
            // 显式保底为 darkAqua，确保 labelColor 在位图栅格化时绝对求值为白色，杜绝前 3 秒黑字。
            if appearance.name != .aqua && appearance.name != .vibrantLight {
                return appearance
            }
        }
        return NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()
    }

    var backingScaleFactor: CGFloat {
        statusItem.button?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
    }

    var anchorButton: NSStatusBarButton? {
        statusItem.button
    }

    var isHighlighted: Bool {
        get { statusItem.button?.isHighlighted ?? false }
        set { statusItem.button?.highlight(newValue) }
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
    var isHighlighted: Bool = false

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
