import AppKit

/// 原生刷新选择控件；NSPopUpButton 负责交互，自定义视图只绘制系统设置式 hover 背景。
final class RefreshIntervalControl: NSView {
    var onIntervalChanged: ((TimeInterval) -> Void)?
    private(set) var isHovered = false

    private let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configurePopUpButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePopUpButton()
    }

    override func layout() {
        super.layout()
        popUpButton.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaReference = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let background = NSColor.labelColor.withAlphaComponent(
            isHovered ? 0.10 : 0.08
        )
        background.setFill()

        if isHovered {
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                xRadius: 8,
                yRadius: 8
            ).fill()
        } else {
            let circleSize = min(bounds.height - 2, 30)
            let circleRect = NSRect(
                x: bounds.maxX - circleSize - 1,
                y: bounds.midY - circleSize / 2,
                width: circleSize,
                height: circleSize
            )
            NSBezierPath(ovalIn: circleRect).fill()
        }
    }

    /// 为什么：鼠标事件和状态同步共用同一入口，避免视觉状态出现双轨逻辑。
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    /// 选择真实菜单项；生产初始化与自动化测试均使用相同路径。
    func select(interval: TimeInterval, notify: Bool) {
        guard let item = popUpButton.itemArray.first(where: {
            ($0.representedObject as? TimeInterval) == interval
        }) else {
            return
        }
        popUpButton.select(item)
        if notify {
            selectionChanged(popUpButton)
        }
    }

    private func configurePopUpButton() {
        popUpButton.removeAllItems()
        for interval in PulseDefaults.allowedRefreshIntervals {
            popUpButton.addItem(withTitle: "\(Int(interval)) 秒")
            popUpButton.lastItem?.representedObject = interval
        }
        popUpButton.isBordered = false
        // 为什么：菜单栏瞬时面板不需要常驻键盘焦点蓝框，但仍保留原生菜单与辅助功能。
        popUpButton.focusRingType = .none
        popUpButton.font = .systemFont(ofSize: 13, weight: .medium)
        popUpButton.target = self
        popUpButton.action = #selector(selectionChanged(_:))
        addSubview(popUpButton)
        select(interval: PulseDefaults.defaultRefreshInterval, notify: false)
    }

    @objc private func selectionChanged(_ sender: NSPopUpButton) {
        guard let interval = sender.selectedItem?.representedObject as? TimeInterval else {
            return
        }
        onIntervalChanged?(interval)
    }
}
