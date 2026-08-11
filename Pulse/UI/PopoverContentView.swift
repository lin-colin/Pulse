import AppKit

private final class MetricPairView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSRect(x: bounds.midX - 0.5, y: 8, width: 1, height: bounds.height - 16).fill()
    }
}

/// macOS 系统设置式详情内容；控件只创建一次，刷新时仅更新既有标签。
final class PopoverContentView: NSView {
    private static let metricsHeight: CGFloat = 206
    static let collapsedHeight: CGFloat = 8 + metricsHeight + 8 + 120 + 8 + 40 + 8

    var onRefreshIntervalChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggled: ((Bool) -> Void)?
    var onQuit: (() -> Void)?
    var onPanelHeightChanged: ((CGFloat) -> Void)?
    var onCheckUpdate: (() -> Void)?

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
        static let metricGridInset: CGFloat = 8
        static let metricRowGap: CGFloat = 8
        static let metricCardHeight: CGFloat = 58
        static let controlRowHeight: CGFloat = 40
        static let settingsHeaderHeight: CGFloat = 24
        static let settingsThresholdRowHeight: CGFloat = 32
        static let settingsMemoryNoteHeight: CGFloat = 32
        static let settingsUpdateRowHeight: CGFloat = 36
        static let settingsFieldSize = NSSize(width: 72, height: 24)
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

    private var settingsExpanded = false
    private var settingsHeightTracksBounds = false
    private let moreChevron = NSImageView()
    private var thresholdInputs: [(orange: NumericInputView, red: NumericInputView)] = []
    private var thresholdConfig: ThresholdConfig
    private let updateSpinner = NSProgressIndicator()
    private var isCheckingUpdate = false

    var onThresholdConfigChanged: ((ThresholdConfig) -> Void)?

    init(frame frameRect: NSRect = .zero, thresholdConfig: ThresholdConfig = .load()) {
        self.thresholdConfig = thresholdConfig
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        self.thresholdConfig = .load()
        super.init(coder: coder)
        configureView()
    }

    override func layout() {
        super.layout()
        let contentWidth = bounds.width - Layout.outerInset * 2
        let settingsHeight = visibleSettingsHeight()
        let controlsHeight: CGFloat = 120 + settingsHeight
        let metricsHeight = Self.metricsHeight

        // 从顶部向下定位：metricsGroup 始终紧贴顶部，展开时只有下方内容向下延伸
        let metricsY = bounds.height - 8 - metricsHeight
        let controlsY = metricsY - 8 - controlsHeight
        let quitY = controlsY - 8 - 40

        metricsGroup.frame = NSRect(x: Layout.outerInset, y: metricsY, width: contentWidth, height: metricsHeight)
        controlsGroup.frame = NSRect(x: Layout.outerInset, y: controlsY, width: contentWidth, height: controlsHeight)
        quitGroup.frame = NSRect(x: Layout.outerInset, y: quitY, width: contentWidth, height: 40)

        layoutMetricRows()
        layoutControlRows(settingsVisible: settingsExpanded || settingsHeight > 0)
        if settingsExpanded || settingsHeightTracksBounds {
            layoutSettingsRows(visibleHeight: settingsHeight)
        }
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
        let usedGB = snapshot.memory.usedBytes.map { Double($0) / 1_073_741_824 }
        let totalGB = snapshot.memory.totalBytes.map { Double($0) / 1_073_741_824 }
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
        // 为什么：折叠动画会把设置行逐步移出内容区，必须裁剪，避免漏绘到下方退出卡片。
        controlsGroup.contentView?.wantsLayer = true
        controlsGroup.contentView?.layer?.masksToBounds = true
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
        box.borderWidth = 0
        box.cornerRadius = Layout.groupCornerRadius
        box.fillColor = NSColor.labelColor.withAlphaComponent(0.045)
        box.contentViewMargins = .zero
    }

    private func buildMetricRows() {
        guard let contentView = metricsGroup.contentView else { return }
        for index in 0..<3 {
            let pair = MetricPairView()
            pair.identifier = NSUserInterfaceItemIdentifier("metric.pair.\(index)")
            contentView.addSubview(pair)
        }

        let definitions: [(MetricKey, String, String)] = [
            (.power, "bolt.fill", "系统负载"),
            (.cpu, "cpu", "CPU 使用"),
            (.memoryUsage, "memorychip", "内存使用"),
            (.memoryPressure, "gauge.with.dots.needle.33percent", "内存压力"),
            (.temperature, "thermometer.medium", "电池温度"),
            (.powerSource, "powerplug.fill", "电源状态"),
        ]
        for (key, symbol, title) in definitions {
            contentView.addSubview(
                makeMetricRow(symbol: symbol, title: title, key: key)
            )
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
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        icon.contentTintColor = .secondaryLabelColor
        icon.identifier = NSUserInterfaceItemIdentifier("metric.\(key.rawValue).icon")

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.identifier = NSUserInterfaceItemIdentifier("metric.\(key.rawValue).title")

        let valueLabel = NSTextField(labelWithString: "—")
        valueLabel.font = metricValueFont(for: key)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .left
        valueLabel.lineBreakMode = .byClipping
        valueLabel.allowsDefaultTighteningForTruncation = true
        valueLabel.identifier = NSUserInterfaceItemIdentifier("metric.\(key.rawValue).value")
        valueLabels[key] = valueLabel

        row.addSubview(icon)
        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        return row
    }

    private func layoutMetricRows() {
        guard let contentView = metricsGroup.contentView else { return }
        let rows = contentView.subviews.filter {
            $0.identifier?.rawValue.hasSuffix(".row") == true
        }
        let pairs = contentView.subviews.filter {
            $0.identifier?.rawValue.hasPrefix("metric.pair.") == true
        }
        let pairWidth = contentView.bounds.width - Layout.metricGridInset * 2
        let cardWidth = pairWidth / 2

        for (index, pair) in pairs.enumerated() {
            let y = contentView.bounds.height
                - Layout.metricGridInset
                - CGFloat(index + 1) * Layout.metricCardHeight
                - CGFloat(index) * Layout.metricRowGap
            pair.frame = NSRect(
                x: Layout.metricGridInset,
                y: y,
                width: pairWidth,
                height: Layout.metricCardHeight
            )
        }

        for (index, row) in rows.enumerated() {
            let gridRow = index / 2
            let gridColumn = index % 2
            let x = Layout.metricGridInset
                + CGFloat(gridColumn) * cardWidth
            let y = contentView.bounds.height
                - Layout.metricGridInset
                - CGFloat(gridRow + 1) * Layout.metricCardHeight
                - CGFloat(gridRow) * Layout.metricRowGap
            row.frame = NSRect(
                x: x,
                y: y,
                width: cardWidth,
                height: Layout.metricCardHeight
            )
            layoutMetricCardSubviews(row)
        }
    }

    private func metricValueFont(for key: MetricKey) -> NSFont {
        let pointSize: CGFloat
        switch key {
        case .memoryUsage:
            pointSize = 10.5
        case .cpu:
            pointSize = 13
        case .powerSource:
            pointSize = 11
        case .power, .temperature, .memoryPressure:
            pointSize = 16
        }
        return .monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold)
    }

    private func layoutMetricCardSubviews(_ card: NSView) {
        guard card.subviews.count >= 3 else { return }
        let icon = card.subviews[0]
        let title = card.subviews[1]
        let value = card.subviews[2]
        icon.frame = NSRect(x: 10, y: 34, width: 16, height: 16)
        title.frame = NSRect(x: 32, y: 33, width: card.bounds.width - 42, height: 17)
        value.frame = NSRect(x: 10, y: 8, width: card.bounds.width - 20, height: 20)
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
            title: "开机自启",
            identifierPrefix: "control.launch"
        )
        launchRow.identifier = NSUserInterfaceItemIdentifier("control.launch.row")
        launchSwitch.identifier = NSUserInterfaceItemIdentifier("control.launch.switch")
        launchSwitch.target = self
        launchSwitch.action = #selector(launchSwitchChanged(_:))
        launchRow.addSubview(launchSwitch)

        // 更多设置行
        let moreRow = makeControlRow(
            symbol: "gearshape",
            title: "更多设置",
            identifierPrefix: "control.more"
        )
        moreRow.identifier = NSUserInterfaceItemIdentifier("control.more.row")
        moreChevron.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: "展开"
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        moreChevron.contentTintColor = .secondaryLabelColor
        moreChevron.identifier = NSUserInterfaceItemIdentifier("control.more.chevron")
        moreRow.addSubview(moreChevron)
        let moreButton = NSButton()
        moreButton.title = ""
        moreButton.isBordered = false
        moreButton.focusRingType = .none
        moreButton.target = self
        moreButton.action = #selector(toggleSettings(_:))
        moreButton.identifier = NSUserInterfaceItemIdentifier("control.more.button")
        moreRow.addSubview(moreButton)

        controlsGroup.contentView?.addSubview(refreshRow)
        controlsGroup.contentView?.addSubview(launchRow)
        controlsGroup.contentView?.addSubview(moreRow)

        // 分隔线
        for i in 0..<2 {
            let separator = NSBox()
            separator.boxType = .separator
            separator.identifier = NSUserInterfaceItemIdentifier("control.separator.\(i)")
            controlsGroup.contentView?.addSubview(separator)
        }
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

    private var settingsRowsBuilt = false

    private func ensureSettingsRowsBuilt() {
        guard !settingsRowsBuilt else { return }
        // 为什么：高级设置只在用户明确展开时创建，避免隐藏视图占用冷启动内存。
        buildSettingsRows()
        settingsRowsBuilt = true
    }

    @objc private func toggleSettings(_ sender: Any) {
        if !settingsExpanded {
            ensureSettingsRowsBuilt()
        } else {
            window?.makeFirstResponder(nil)
        }
        // 为什么：只有真实面板会通过回调逐帧改变 bounds；独立视图继续使用确定性的即时布局。
        settingsHeightTracksBounds = onPanelHeightChanged != nil
        settingsExpanded.toggle()
        let symbolName = settingsExpanded ? "chevron.up" : "chevron.down"
        moreChevron.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: settingsExpanded ? "收起" : "展开"
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        needsLayout = true
        onPanelHeightChanged?(computeTotalHeight())
    }

    @objc private func checkUpdateTapped(_ sender: Any) {
        guard !isCheckingUpdate else { return }
        setUpdateChecking(true)
        onCheckUpdate?()
    }

    private func thresholdValueChanged() {
        guard thresholdInputs.count >= 3 else { return }

        let powerOrangeStr = thresholdInputs[0].orange.stringValue
        let powerRedStr = thresholdInputs[0].red.stringValue
        let tempOrangeStr = thresholdInputs[1].orange.stringValue
        let tempRedStr = thresholdInputs[1].red.stringValue
        let cpuOrangeStr = thresholdInputs[2].orange.stringValue
        let cpuRedStr = thresholdInputs[2].red.stringValue

        guard let powerOrange = Double(powerOrangeStr), powerOrange.isFinite,
              let powerRed = Double(powerRedStr), powerRed.isFinite,
              let tempOrange = Double(tempOrangeStr), tempOrange.isFinite,
              let tempRed = Double(tempRedStr), tempRed.isFinite,
              let cpuOrange = Double(cpuOrangeStr), cpuOrange.isFinite,
              let cpuRed = Double(cpuRedStr), cpuRed.isFinite else {
            return
        }

        let newConfig = ThresholdConfig(
            power: MetricThreshold(orange: powerOrange, red: powerRed),
            temperature: MetricThreshold(orange: tempOrange, red: tempRed),
            cpu: MetricThreshold(orange: cpuOrange, red: cpuRed)
        )

        thresholdConfig = newConfig
        newConfig.save()
        // 为什么：阈值有效解析并更新保存后，回调通知控制器更新内存缓存，避免刷新热路径重复从 UserDefaults 加载。
        onThresholdConfigChanged?(newConfig)
    }

    // MARK: - Settings Panel

    private func buildSettingsRows() {
        let thresholdHeader = makeThresholdHeader()
        controlsGroup.contentView?.addSubview(thresholdHeader)

        let definitions: [(String, String, Double, Double, String, String)] = [
            ("bolt.fill", "系统负载", thresholdConfig.power.orange, thresholdConfig.power.red, "W", "瓦"),
            ("thermometer.medium", "电池温度", thresholdConfig.temperature.orange, thresholdConfig.temperature.red, "°C", "摄氏度"),
            ("cpu", "CPU 使用", thresholdConfig.cpu.orange, thresholdConfig.cpu.red, "%", "百分比"),
        ]

        for (index, def) in definitions.enumerated() {
            let (symbol, title, orangeVal, redVal, unit, spokenUnit) = def
            let section = makeThresholdSection(
                symbol: symbol, title: title,
                orangeValue: orangeVal, redValue: redVal,
                unit: unit, spokenUnit: spokenUnit, index: index
            )
            controlsGroup.contentView?.addSubview(section)
        }

        let orderedInputs = thresholdInputs.flatMap { [$0.orange, $0.red] }
        for (current, next) in zip(orderedInputs, orderedInputs.dropFirst()) {
            current.nextKeyView = next
        }
        orderedInputs.last?.nextKeyView = orderedInputs.first

        // 内存压力说明
        let memNote = NSView()
        memNote.identifier = NSUserInterfaceItemIdentifier("settings.memNote")

        let memoryBackground = NSBox()
        memoryBackground.boxType = .custom
        memoryBackground.borderWidth = 0
        memoryBackground.fillColor = NSColor.systemBlue.withAlphaComponent(0.05)
        memoryBackground.identifier = NSUserInterfaceItemIdentifier("settings.memNote.background")

        let memIcon = NSImageView()
        memIcon.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: nil)
        memIcon.contentTintColor = .secondaryLabelColor
        memIcon.identifier = NSUserInterfaceItemIdentifier("settings.memNote.icon")

        let memLabel = NSTextField(labelWithString: "内存压力由 macOS 系统管理，无需设置阈值")
        memLabel.font = .systemFont(ofSize: 11)
        memLabel.textColor = .secondaryLabelColor
        memLabel.identifier = NSUserInterfaceItemIdentifier("settings.memNote.label")

        memNote.addSubview(memoryBackground)
        memNote.addSubview(memIcon)
        memNote.addSubview(memLabel)
        controlsGroup.contentView?.addSubview(memNote)

        // 检查更新与版本号底栏
        let updateRow = NSView()
        updateRow.identifier = NSUserInterfaceItemIdentifier("settings.update.row")

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: "Pulse v\(version)")
        versionLabel.identifier = NSUserInterfaceItemIdentifier("settings.version.label")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor

        let updateButton = NSButton(title: "检查更新", target: self, action: #selector(checkUpdateTapped(_:)))
        updateButton.identifier = NSUserInterfaceItemIdentifier("settings.update.button")
        updateButton.bezelStyle = .rounded
        updateButton.controlSize = .small
        updateButton.font = .systemFont(ofSize: 11)

        updateSpinner.style = .spinning
        updateSpinner.controlSize = .small
        updateSpinner.sizeToFit()
        updateSpinner.isHidden = true

        let updateIcon = NSImageView()
        updateIcon.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        updateIcon.contentTintColor = .secondaryLabelColor
        updateIcon.identifier = NSUserInterfaceItemIdentifier("settings.update.icon")

        updateRow.addSubview(updateIcon)
        updateRow.addSubview(versionLabel)
        updateRow.addSubview(updateButton)
        updateRow.addSubview(updateSpinner)
        controlsGroup.contentView?.addSubview(updateRow)

        // 内凹浅色底板（用于将【告警阈值】分组归类包裹）
        let insetCard = NSBox()
        insetCard.boxType = .custom
        insetCard.borderWidth = 0
        insetCard.cornerRadius = 10
        insetCard.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
        insetCard.identifier = NSUserInterfaceItemIdentifier("settings.insetCard")
        controlsGroup.contentView?.addSubview(insetCard, positioned: .below, relativeTo: nil)

        // 分隔线（5 条分隔线）
        for i in 0..<5 {
            let sep = NSBox()
            sep.boxType = .separator
            sep.identifier = NSUserInterfaceItemIdentifier("settings.separator.\(i)")
            controlsGroup.contentView?.addSubview(sep)
        }
    }

    private func makeThresholdHeader() -> NSView {
        let header = NSView()
        header.identifier = NSUserInterfaceItemIdentifier("settings.threshold.header")

        let title = NSTextField(labelWithString: "告警阈值")
        title.identifier = NSUserInterfaceItemIdentifier("settings.threshold.header.title")
        title.font = .systemFont(ofSize: 10, weight: .medium)
        title.textColor = .labelColor

        // 为什么用 NSAttributedString 而不是单独的 NSBox 圆点：
        // 将圆点字符 ● 与文字放在同一个 NSTextField 中，
        // 共享同一 baseline，天然垂直居中对齐，无需手动调 y 值。
        let orangeLabel = NSTextField(labelWithAttributedString: Self.makeHeaderDotText(dot: .systemOrange, text: "提醒"))
        orangeLabel.identifier = NSUserInterfaceItemIdentifier("settings.threshold.header.orangeLabel")

        let redLabel = NSTextField(labelWithAttributedString: Self.makeHeaderDotText(dot: .systemRed, text: "严重"))
        redLabel.identifier = NSUserInterfaceItemIdentifier("settings.threshold.header.redLabel")

        [title, orangeLabel, redLabel].forEach(header.addSubview)
        return header
    }

    private static func makeHeaderDotText(dot color: NSColor, text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // 用较小字号的圆点字符，使其视觉大小接近原始 6×6 圆点
        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: color,
            .baselineOffset: 1.0
        ]
        result.append(NSAttributedString(string: "\u{25CF} ", attributes: dotAttrs))
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        result.append(NSAttributedString(string: text, attributes: textAttrs))
        return result
    }

    private let upToDateLabel = NSTextField(labelWithString: "✅ 已是最新版本")
    private let updateAvailableLabel = NSTextField(labelWithString: "")
    private let downloadButton = NSButton()

    func setUpdateChecking(_ checking: Bool) {
        isCheckingUpdate = checking
        let updateRow = controlsGroup.contentView?.subviews.first(where: { $0.identifier?.rawValue == "settings.update.row" })
        if let updateButton = updateRow?.subviews.first(where: { $0.identifier?.rawValue == "settings.update.button" }) as? NSButton {
            updateButton.title = checking ? "正在检查..." : "检查更新"
            updateButton.isEnabled = !checking
        }
        if checking {
            updateSpinner.startAnimation(nil)
            updateSpinner.isHidden = false
        } else {
            updateSpinner.stopAnimation(nil)
            updateSpinner.isHidden = true
        }
    }

    func setUpdateResult(_ result: UpdateChecker.UpdateResult) {
        setUpdateChecking(false)
        let updateRow = controlsGroup.contentView?.subviews.first(where: { $0.identifier?.rawValue == "settings.update.row" })
        guard let updateRow else { return }

        upToDateLabel.removeFromSuperview()
        updateAvailableLabel.removeFromSuperview()
        downloadButton.removeFromSuperview()

        switch result {
        case .upToDate:
            upToDateLabel.stringValue = "✅ 已是最新版本"
            upToDateLabel.textColor = .systemGreen
            upToDateLabel.font = .systemFont(ofSize: 11, weight: .medium)
            upToDateLabel.identifier = NSUserInterfaceItemIdentifier("update.state.upToDate")
            upToDateLabel.frame = NSRect(x: updateRow.bounds.width - 120, y: 9, width: 110, height: 18)
            updateRow.addSubview(upToDateLabel)

            if let updateButton = updateRow.subviews.first(where: { $0.identifier?.rawValue == "settings.update.button" }) {
                updateButton.isHidden = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self, weak updateRow] in
                guard let self, let updateRow else { return }
                self.upToDateLabel.removeFromSuperview()
                if let updateButton = updateRow.subviews.first(where: { $0.identifier?.rawValue == "settings.update.button" }) {
                    updateButton.isHidden = false
                }
            }

        case .updateAvailable(let version):
            updateAvailableLabel.stringValue = "🎉 发现 v\(version)"
            updateAvailableLabel.textColor = .systemOrange
            updateAvailableLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            updateAvailableLabel.identifier = NSUserInterfaceItemIdentifier("update.state.available")
            updateAvailableLabel.frame = NSRect(x: updateRow.bounds.width - 180, y: 9, width: 90, height: 18)
            updateRow.addSubview(updateAvailableLabel)

            downloadButton.title = "前往下载"
            downloadButton.bezelStyle = .inline
            downloadButton.controlSize = .small
            downloadButton.font = .systemFont(ofSize: 11, weight: .medium)
            downloadButton.identifier = NSUserInterfaceItemIdentifier("update.state.downloadButton")
            downloadButton.frame = NSRect(x: updateRow.bounds.width - 85, y: 8, width: 75, height: 20)
            downloadButton.target = self
            downloadButton.action = #selector(openReleasePage)
            updateRow.addSubview(downloadButton)

            if let updateButton = updateRow.subviews.first(where: { $0.identifier?.rawValue == "settings.update.button" }) {
                updateButton.isHidden = true
            }

        case .error(let msg):
            upToDateLabel.stringValue = "⚠️ \(msg)"
            upToDateLabel.textColor = .systemRed
            upToDateLabel.font = .systemFont(ofSize: 11)
            upToDateLabel.identifier = NSUserInterfaceItemIdentifier("update.state.error")
            upToDateLabel.frame = NSRect(x: updateRow.bounds.width - 150, y: 9, width: 140, height: 18)
            updateRow.addSubview(upToDateLabel)

            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self, weak updateRow] in
                guard let self, let updateRow else { return }
                self.upToDateLabel.removeFromSuperview()
                if let updateButton = updateRow.subviews.first(where: { $0.identifier?.rawValue == "settings.update.button" }) {
                    updateButton.isHidden = false
                }
            }
        }
    }

    @objc private func openReleasePage() {
        if let url = URL(string: "https://github.com/lin-colin/Pulse/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }

    private func makeThresholdSection(
        symbol: String, title: String,
        orangeValue: Double, redValue: Double,
        unit: String, spokenUnit: String, index: Int
    ) -> NSView {
        let section = NSView()
        section.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index)")

        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        icon.contentTintColor = .labelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        let orangeField = ThresholdValueField(unit: unit)
        orangeField.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index).orangeField")
        orangeField.inputView.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index).orangeInput")
        orangeField.inputView.stringValue = formatThreshold(orangeValue)
        orangeField.inputView.setAccessibilityLabel("\(title)提醒阈值，单位\(spokenUnit)")
        orangeField.inputView.onCommit = { [weak self] in self?.thresholdValueChanged() }
        orangeField.inputView.onTextChange = { [weak self] in self?.thresholdValueChanged() }

        let redField = ThresholdValueField(unit: unit)
        redField.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index).redField")
        redField.inputView.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index).redInput")
        redField.inputView.stringValue = formatThreshold(redValue)
        redField.inputView.setAccessibilityLabel("\(title)严重阈值，单位\(spokenUnit)")
        redField.inputView.onCommit = { [weak self] in self?.thresholdValueChanged() }
        redField.inputView.onTextChange = { [weak self] in self?.thresholdValueChanged() }

        section.addSubview(icon)
        section.addSubview(titleLabel)
        section.addSubview(orangeField)
        section.addSubview(redField)

        thresholdInputs.append((orange: orangeField.inputView, red: redField.inputView))
        return section
    }

    private func formatThreshold(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    // MARK: - Settings Layout

    private func layoutSettingsRows(visibleHeight: CGFloat) {
        guard let contentView = controlsGroup.contentView else { return }
        let w = controlsGroup.bounds.width
        let settingsHeight = computeSettingsHeight()
        let yOffset = visibleHeight - settingsHeight

        // 内凹卡片面板：包住【告警阈值】5 个设置视图
        if let insetCard = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.insetCard" }) {
            insetCard.frame = NSRect(x: 8, y: 44 + yOffset, width: w - 16, height: 156)
        }

        if let header = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.threshold.header" }) {
            header.frame = NSRect(x: 0, y: 172 + yOffset, width: w, height: Layout.settingsHeaderHeight)
            layoutThresholdHeader(header)
        }

        let sectionYPositions: [CGFloat] = [140, 108, 76]
        let sections = contentView.subviews.filter {
            guard let id = $0.identifier?.rawValue else { return false }
            return id.hasPrefix("settings.section.") && id.split(separator: ".").count == 3
        }

        for (i, section) in sections.enumerated() {
            guard i < sectionYPositions.count else { break }
            let y = sectionYPositions[i] + yOffset
            section.frame = NSRect(x: 0, y: y, width: w, height: Layout.settingsThresholdRowHeight)
            layoutThresholdSection(section)
        }

        let separatorYPositions: [CGFloat] = [172, 140, 108, 76, 44]
        let separators = contentView.subviews.filter { $0.identifier?.rawValue.hasPrefix("settings.separator.") == true }
        for (i, sep) in separators.enumerated() {
            guard i < separatorYPositions.count else { break }
            let y = separatorYPositions[i] + yOffset
            // 内凹内部的分隔线收窄，底部主分隔线拉满
            let sepWidth = (i == 4) ? w : w - 32
            let sepX = (i == 4) ? 0 : CGFloat(16)
            sep.frame = NSRect(x: sepX, y: y, width: sepWidth, height: 1)
        }

        if let memNote = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.memNote" }) {
            memNote.frame = NSRect(x: 0, y: 44 + yOffset, width: w, height: Layout.settingsMemoryNoteHeight)
            layoutMemoryNote(memNote)
        }

        if let updateRow = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.update.row" }) {
            updateRow.frame = NSRect(x: 0, y: yOffset, width: w, height: Layout.settingsUpdateRowHeight)
            layoutUpdateRow(updateRow)
        }
    }

    private func layoutThresholdHeader(_ header: NSView) {
        if let title = header.subviews.first(where: { $0.identifier?.rawValue == "settings.threshold.header.title" }) {
            title.frame = NSRect(x: Layout.titleX, y: 3, width: 88, height: 18)
        }
        // “● 提醒” 居中对齐到 orangeField 列（midX=188）
        if let orangeLabel = header.subviews.first(where: { $0.identifier?.rawValue == "settings.threshold.header.orangeLabel" }) as? NSTextField {
            orangeLabel.sizeToFit()
            let labelW = ceil(orangeLabel.frame.width)
            orangeLabel.frame = NSRect(x: 188 - labelW / 2, y: 3, width: labelW, height: 18)
        }
        // “● 严重” 居中对齐到 redField 列（midX=272）
        if let redLabel = header.subviews.first(where: { $0.identifier?.rawValue == "settings.threshold.header.redLabel" }) as? NSTextField {
            redLabel.sizeToFit()
            let labelW = ceil(redLabel.frame.width)
            redLabel.frame = NSRect(x: 272 - labelW / 2, y: 3, width: labelW, height: 18)
        }
    }

    private func layoutThresholdSection(_ section: NSView) {
        guard section.subviews.count >= 4 else { return }
        let icon = section.subviews[0]
        let title = section.subviews[1]
        let orangeField = section.subviews[2]
        let redField = section.subviews[3]

        icon.frame = NSRect(x: 12, y: 8, width: 16, height: 16)
        title.frame = NSRect(x: 38, y: 7, width: 88, height: 18)
        // 放大宽度为 72pt，与上方右边距 12pt 精准水平对齐
        orangeField.frame = NSRect(x: 152, y: 4, width: Layout.settingsFieldSize.width, height: Layout.settingsFieldSize.height)
        redField.frame = NSRect(x: 236, y: 4, width: Layout.settingsFieldSize.width, height: Layout.settingsFieldSize.height)
    }

    private func layoutMemoryNote(_ memNote: NSView) {
        let w = memNote.bounds.width
        if let bg = memNote.subviews.first(where: { $0.identifier?.rawValue == "settings.memNote.background" }) {
            bg.frame = memNote.bounds
        }
        if let icon = memNote.subviews.first(where: { $0.identifier?.rawValue == "settings.memNote.icon" }) {
            icon.frame = NSRect(x: 12, y: 8, width: 16, height: 16)
        }
        if let label = memNote.subviews.first(where: { $0.identifier?.rawValue == "settings.memNote.label" }) {
            label.frame = NSRect(x: 38, y: 7, width: max(0, w - 50), height: 18)
        }
    }

    private func layoutUpdateRow(_ updateRow: NSView) {
        let w = updateRow.bounds.width
        let buttonW: CGFloat = 78
        let buttonX = w - Layout.trailingInset - buttonW

        if let icon = updateRow.subviews.first(where: { $0.identifier?.rawValue == "settings.update.icon" }) {
            icon.frame = NSRect(x: 12, y: 11.5, width: 16, height: 16)
        }
        if let versionLabel = updateRow.subviews.first(where: { $0.identifier?.rawValue == "settings.version.label" }) {
            versionLabel.frame = NSRect(x: 38, y: 9, width: 120, height: 18)
        }
        if let updateButton = updateRow.subviews.first(where: { $0.identifier?.rawValue == "settings.update.button" }) {
            updateButton.frame = NSRect(x: buttonX, y: 8, width: buttonW, height: 20)
        }
        updateSpinner.frame = NSRect(x: buttonX - 22, y: 10, width: 16, height: 16)
    }

    // MARK: - Control Rows Layout (updated for 3 rows)

    private func layoutControlRows(settingsVisible: Bool) {
        guard let contentView = controlsGroup.contentView else { return }
        let h = controlsGroup.bounds.height
        let w = controlsGroup.bounds.width
        let refreshRow = contentView.subviews.first { $0.identifier?.rawValue == "control.refresh.row" }
        let launchRow = contentView.subviews.first { $0.identifier?.rawValue == "control.launch.row" }
        let moreRow = contentView.subviews.first { $0.identifier?.rawValue == "control.more.row" }

        // 3 rows pinned to top of controlsGroup
        refreshRow?.frame = NSRect(x: 0, y: h - Layout.controlRowHeight, width: w, height: Layout.controlRowHeight)
        launchRow?.frame = NSRect(x: 0, y: h - Layout.controlRowHeight * 2, width: w, height: Layout.controlRowHeight)
        moreRow?.frame = NSRect(x: 0, y: h - Layout.controlRowHeight * 3, width: w, height: Layout.controlRowHeight)

        if let refreshRow {
            layoutStandardRowSubviews(refreshRow, trailingWidth: 68)
            let controlHeight: CGFloat = 26
            refreshControl.frame = NSRect(
                x: refreshRow.bounds.width - 68 - Layout.trailingInset,
                y: (refreshRow.bounds.height - controlHeight) / 2,
                width: 68,
                height: controlHeight
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
        if let moreRow {
            layoutStandardRowSubviews(moreRow, trailingWidth: 20)
            moreChevron.frame = NSRect(
                x: moreRow.bounds.width - 24 - Layout.trailingInset,
                y: (moreRow.bounds.height - 14) / 2,
                width: 14,
                height: 14
            )
            if let btn = moreRow.subviews.first(where: { $0.identifier?.rawValue == "control.more.button" }) {
                btn.frame = moreRow.bounds
            }
        }

        let separators = contentView.subviews.filter { $0.identifier?.rawValue.hasPrefix("control.separator.") == true }
        for (i, sep) in separators.enumerated() {
            let y = h - Layout.controlRowHeight * CGFloat(i + 1)
            layoutSeparator(sep, y: y, width: w)
        }

        // 折叠途中设置区仍需参与同一帧布局，到可见高度归零后才隐藏。
        let settingsViews = contentView.subviews.filter {
            let id = $0.identifier?.rawValue ?? ""
            return id.hasPrefix("settings.")
        }
        for v in settingsViews {
            v.isHidden = !settingsVisible
        }
    }

    // MARK: - Height Calculation

    private func computeSettingsHeight() -> CGFloat {
        Layout.settingsHeaderHeight
            + Layout.settingsThresholdRowHeight * 3
            + Layout.settingsMemoryNoteHeight
            + 8 // 内凹面板与底部更新行的逻辑间距
            + Layout.settingsUpdateRowHeight
    }

    private func visibleSettingsHeight() -> CGFloat {
        guard settingsHeightTracksBounds else {
            return settingsExpanded ? computeSettingsHeight() : 0
        }
        return min(
            computeSettingsHeight(),
            max(0, bounds.height - Self.collapsedHeight)
        )
    }

    func computeTotalHeight() -> CGFloat {
        let settingsHeight = settingsExpanded ? computeSettingsHeight() : 0
        return Self.collapsedHeight + settingsHeight
    }
}

