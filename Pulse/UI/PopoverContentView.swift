import AppKit

/// macOS 系统设置式详情内容；控件只创建一次，刷新时仅更新既有标签。
final class PopoverContentView: NSView {
    var onRefreshIntervalChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggled: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    private enum MetricKey: String {
        case power
        case temperature
        case memoryUsage
        case memoryPressure
        case cpu
        case powerSource
    }

    /// 所有分组共用一套横向几何，避免指标、设置和操作行各自漂移。
    private enum Layout {
        static let outerInset: CGFloat = 10
        static let groupCornerRadius: CGFloat = 12
        static let rowLeadingInset: CGFloat = 12
        static let iconSlotWidth: CGFloat = 18
        static let titleX: CGFloat = 38
        static let trailingInset: CGFloat = 12
        static let metricRowHeight: CGFloat = 40
        static let controlRowHeight: CGFloat = 40
    }

    private let metricsGroup = NSBox()
    private let controlsGroup = NSBox()
    private let quitGroup = NSBox()
    private let refreshControl = RefreshIntervalControl(frame: .zero)
    private let launchSwitch = NSSwitch(frame: .zero)
    private let quitButton = NSButton()
    private let quitIcon = NSImageView()
    private let quitTitle = NSTextField(labelWithString: "退出 Pulse")
    private var valueLabels: [MetricKey: NSTextField] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func layout() {
        super.layout()
        let contentWidth = bounds.width - Layout.outerInset * 2
        quitGroup.frame = NSRect(x: Layout.outerInset, y: 8, width: contentWidth, height: 40)
        controlsGroup.frame = NSRect(x: Layout.outerInset, y: 56, width: contentWidth, height: 80)
        metricsGroup.frame = NSRect(x: Layout.outerInset, y: 144, width: contentWidth, height: 240)
        layoutMetricRows()
        layoutControlRows()
        layoutQuitRow()
    }

    override func draw(_ dirtyRect: NSRect) {
        // 背景由 NSPanel 的 NSVisualEffectView 提供，内容视图保持透明。
    }

    func update(snapshot: PulseSnapshot) {
        valueLabels[.power]?.stringValue = MetricCalculations.formatted(
            snapshot.power,
            decimals: 1,
            suffix: "W"
        )
        valueLabels[.temperature]?.stringValue = MetricCalculations.formatted(
            snapshot.temperature,
            decimals: 1,
            suffix: "°C"
        )
        let usedGB = snapshot.memory.usedBytes.map {
            Double($0) / 1_073_741_824
        }
        let totalGB = snapshot.memory.totalBytes.map {
            Double($0) / 1_073_741_824
        }
        valueLabels[.memoryUsage]?.stringValue = MetricCalculations.formattedMemoryUsageDetail(
            usedGB: usedGB,
            totalGB: totalGB,
            percentage: snapshot.memory.usagePercentage
        )
        valueLabels[.memoryPressure]?.stringValue = snapshot.memory.pressureLevel.displayName
        let cpuUsage = String(format: "%.0f%%", snapshot.cpuUsage)
        valueLabels[.cpu]?.stringValue = snapshot.cpuFrequency > 0
            ? "\(cpuUsage) (\(String(format: "%.1f", snapshot.cpuFrequency)) GHz)"
            : cpuUsage
        valueLabels[.powerSource]?.stringValue = snapshot.powerSource.description
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshControl.select(
            interval: PulseDefaults.validatedRefreshInterval(interval),
            notify: false
        )
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchSwitch.state = enabled ? .on : .off
    }

    private func configureView() {
        configureGroup(metricsGroup)
        configureGroup(controlsGroup)
        configureGroup(quitGroup)
        metricsGroup.identifier = NSUserInterfaceItemIdentifier("group.metrics")
        controlsGroup.identifier = NSUserInterfaceItemIdentifier("group.controls")
        quitGroup.identifier = NSUserInterfaceItemIdentifier("group.quit")
        buildMetricRows()
        buildControlRows()
        configureQuitButton()

        addSubview(metricsGroup)
        addSubview(controlsGroup)
        addSubview(quitGroup)
    }

    private func configureGroup(_ box: NSBox) {
        box.boxType = .custom
        // 系统设置分组依靠材质层级而不是硬描边，避免再次出现“框中框”。
        box.borderWidth = 0
        box.cornerRadius = Layout.groupCornerRadius
        box.fillColor = NSColor.labelColor.withAlphaComponent(0.045)
        box.contentViewMargins = .zero
    }

    private func buildMetricRows() {
        let definitions: [(MetricKey, String, String)] = [
            (.power, "bolt.fill", "系统负载"),
            (.temperature, "thermometer.medium", "电池温度"),
            (.memoryUsage, "memorychip", "内存使用"),
            (.memoryPressure, "gauge.with.dots.needle.33percent", "内存压力"),
            (.cpu, "cpu", "CPU 使用"),
            (.powerSource, "powerplug.fill", "电源状态"),
        ]
        for (key, symbol, title) in definitions {
            metricsGroup.contentView?.addSubview(
                makeMetricRow(symbol: symbol, title: title, key: key)
            )
        }
        for _ in 0..<5 {
            let separator = NSBox()
            separator.boxType = .separator
            separator.identifier = NSUserInterfaceItemIdentifier("metric.separator")
            metricsGroup.contentView?.addSubview(separator)
        }
    }

    private func makeMetricRow(
        symbol: String,
        title: String,
        key: MetricKey
    ) -> NSView {
        let row = NSView()
        row.identifier = NSUserInterfaceItemIdentifier("metric.\(key.rawValue).row")

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon.contentTintColor = .labelColor
        icon.identifier = NSUserInterfaceItemIdentifier("metric.\(key.rawValue).icon")

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.identifier = NSUserInterfaceItemIdentifier("metric.\(key.rawValue).title")

        let valueLabel = NSTextField(labelWithString: "—")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byClipping
        valueLabel.identifier = NSUserInterfaceItemIdentifier("metric.\(key.rawValue).value")
        valueLabels[key] = valueLabel

        row.addSubview(icon)
        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        return row
    }

    private func buildControlRows() {
        let refreshRow = makeControlRow(
            symbol: "timer",
            title: "刷新间隔",
            identifierPrefix: "control.refresh"
        )
        refreshRow.identifier = NSUserInterfaceItemIdentifier("control.refresh.row")
        refreshControl.onIntervalChanged = { [weak self] interval in
            self?.onRefreshIntervalChanged?(interval)
        }
        refreshRow.addSubview(refreshControl)

        let launchRow = makeControlRow(
            symbol: "power",
            title: "开机自动启动",
            identifierPrefix: "control.launch"
        )
        launchRow.identifier = NSUserInterfaceItemIdentifier("control.launch.row")
        launchSwitch.identifier = NSUserInterfaceItemIdentifier("control.launch.switch")
        launchSwitch.target = self
        launchSwitch.action = #selector(launchSwitchChanged(_:))
        launchRow.addSubview(launchSwitch)

        controlsGroup.contentView?.addSubview(refreshRow)
        controlsGroup.contentView?.addSubview(launchRow)

        let separator = NSBox()
        separator.boxType = .separator
        separator.identifier = NSUserInterfaceItemIdentifier("control.separator")
        controlsGroup.contentView?.addSubview(separator)
    }

    private func makeControlRow(
        symbol: String,
        title: String,
        identifierPrefix: String
    ) -> NSView {
        let row = NSView()
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        icon.contentTintColor = .labelColor
        icon.identifier = NSUserInterfaceItemIdentifier("\(identifierPrefix).icon")

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.identifier = NSUserInterfaceItemIdentifier("\(identifierPrefix).title")
        row.addSubview(icon)
        row.addSubview(titleLabel)
        return row
    }

    private func configureQuitButton() {
        quitIcon.image = NSImage(
            systemSymbolName: "xmark.circle",
            accessibilityDescription: "退出"
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        quitIcon.contentTintColor = .labelColor
        quitIcon.identifier = NSUserInterfaceItemIdentifier("control.quit.icon")

        quitTitle.font = .systemFont(ofSize: 13)
        quitTitle.identifier = NSUserInterfaceItemIdentifier("control.quit.title")

        // 空标题按钮覆盖整行，既保留清晰布局，也让分组的全部区域都可以点击。
        quitButton.title = ""
        quitButton.isBordered = false
        quitButton.focusRingType = .none
        quitButton.target = self
        quitButton.action = #selector(quitRequested(_:))
        quitButton.keyEquivalent = "q"
        quitButton.keyEquivalentModifierMask = [.command]
        quitButton.identifier = NSUserInterfaceItemIdentifier("control.quit.button")
        quitButton.setAccessibilityLabel("退出 Pulse")

        quitGroup.contentView?.addSubview(quitIcon)
        quitGroup.contentView?.addSubview(quitTitle)
        quitGroup.contentView?.addSubview(quitButton)
    }

    private func layoutMetricRows() {
        let rows = metricsGroup.contentView?.subviews.filter {
            $0.identifier?.rawValue.hasSuffix(".row") == true
        } ?? []
        for (index, row) in rows.enumerated() {
            let y = metricsGroup.bounds.height - CGFloat(index + 1) * Layout.metricRowHeight
            row.frame = NSRect(
                x: 0,
                y: y,
                width: metricsGroup.bounds.width,
                height: Layout.metricRowHeight
            )
            layoutStandardRowSubviews(row, trailingWidth: metricsGroup.bounds.width - 137)
        }

        let separators = metricsGroup.contentView?.subviews.filter {
            $0.identifier?.rawValue == "metric.separator"
        } ?? []
        for (index, separator) in separators.enumerated() {
            let y = metricsGroup.bounds.height - CGFloat(index + 1) * Layout.metricRowHeight
            layoutSeparator(separator, y: y, width: metricsGroup.bounds.width)
        }
    }

    private func layoutControlRows() {
        guard let contentView = controlsGroup.contentView else { return }
        let refreshRow = contentView.subviews.first {
            $0.identifier?.rawValue == "control.refresh.row"
        }
        let launchRow = contentView.subviews.first {
            $0.identifier?.rawValue == "control.launch.row"
        }
        refreshRow?.frame = NSRect(
            x: 0,
            y: Layout.controlRowHeight,
            width: controlsGroup.bounds.width,
            height: Layout.controlRowHeight
        )
        launchRow?.frame = NSRect(
            x: 0,
            y: 0,
            width: controlsGroup.bounds.width,
            height: Layout.controlRowHeight
        )
        if let refreshRow {
            layoutStandardRowSubviews(refreshRow, trailingWidth: 92)
            refreshControl.frame = NSRect(
                x: refreshRow.bounds.width - 104,
                y: (refreshRow.bounds.height - 32) / 2,
                width: 92,
                height: 32
            )
        }
        if let launchRow {
            layoutStandardRowSubviews(launchRow, trailingWidth: 44)
            launchSwitch.sizeToFit()
            launchSwitch.frame.origin = NSPoint(
                x: launchRow.bounds.width - launchSwitch.frame.width - 12,
                y: (launchRow.bounds.height - launchSwitch.frame.height) / 2
            )
        }
        contentView.subviews.first {
            $0.identifier?.rawValue == "control.separator"
        }.map {
            layoutSeparator($0, y: Layout.controlRowHeight, width: controlsGroup.bounds.width)
        }
    }

    private func layoutStandardRowSubviews(_ row: NSView, trailingWidth: CGFloat) {
        guard row.subviews.count >= 3 else { return }
        let icon = row.subviews[0]
        let title = row.subviews[1]
        let value = row.subviews[2]
        icon.frame = NSRect(
            x: Layout.rowLeadingInset,
            y: (row.bounds.height - Layout.iconSlotWidth) / 2,
            width: Layout.iconSlotWidth,
            height: Layout.iconSlotWidth
        )
        title.frame = NSRect(
            x: Layout.titleX,
            y: (row.bounds.height - 18) / 2,
            width: 98,
            height: 18
        )
        value.frame = NSRect(
            x: row.bounds.width - trailingWidth - Layout.trailingInset,
            y: (row.bounds.height - 20) / 2,
            width: trailingWidth,
            height: 20
        )
    }

    private func layoutQuitRow() {
        guard let contentView = quitGroup.contentView else { return }
        quitButton.frame = contentView.bounds
        quitIcon.frame = NSRect(
            x: Layout.rowLeadingInset,
            y: (contentView.bounds.height - Layout.iconSlotWidth) / 2,
            width: Layout.iconSlotWidth,
            height: Layout.iconSlotWidth
        )
        quitTitle.frame = NSRect(
            x: Layout.titleX,
            y: (contentView.bounds.height - 18) / 2,
            width: contentView.bounds.width - Layout.titleX - Layout.trailingInset,
            height: 18
        )
    }

    private func layoutSeparator(_ separator: NSView, y: CGFloat, width: CGFloat) {
        separator.frame = NSRect(
            x: Layout.titleX,
            y: y,
            width: width - Layout.titleX - Layout.trailingInset,
            height: 1
        )
    }

    @objc private func launchSwitchChanged(_ sender: NSSwitch) {
        onLaunchAtLoginToggled?(sender.state == .on)
    }

    @objc private func quitRequested(_ sender: NSButton) {
        onQuit?()
    }
}
