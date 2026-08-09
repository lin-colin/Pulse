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
        static let settingsRowHeight: CGFloat = 36
        static let settingsThresholdRowHeight: CGFloat = 36
        static let settingsInputWidth: CGFloat = 40
        static let settingsUnitSlotWidth: CGFloat = 24
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
    private var thresholdInputs: [(orange: NSTextField, red: NSTextField)] = []
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

    @objc private func thresholdValueChanged(_ sender: NSTextField) {
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
        let definitions: [(String, String, Double, Double, String)] = [
            ("bolt.fill", "系统负载", thresholdConfig.power.orange, thresholdConfig.power.red, "W"),
            ("thermometer.medium", "电池温度", thresholdConfig.temperature.orange, thresholdConfig.temperature.red, "°C"),
            ("cpu", "CPU 使用", thresholdConfig.cpu.orange, thresholdConfig.cpu.red, "%"),
        ]

        for (index, def) in definitions.enumerated() {
            let (symbol, title, orangeVal, redVal, unit) = def
            let section = makeThresholdSection(
                symbol: symbol, title: title,
                orangeValue: orangeVal, redValue: redVal,
                unit: unit, index: index
            )
            controlsGroup.contentView?.addSubview(section)
        }

        // 设置说明
        let descLabel = NSTextField(labelWithString: "数值超过阈值时，菜单栏指标颜色会变化")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .tertiaryLabelColor
        descLabel.identifier = NSUserInterfaceItemIdentifier("settings.desc")
        controlsGroup.contentView?.addSubview(descLabel)

        // 内存压力说明
        let memNote = NSView()
        memNote.identifier = NSUserInterfaceItemIdentifier("settings.memNote")
        
        let memIcon = NSImageView()
        memIcon.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: nil)
        memIcon.contentTintColor = .secondaryLabelColor
        
        let memLabel = NSTextField(labelWithString: "内存压力由 macOS 系统内核决定，不可配置")
        memLabel.font = .systemFont(ofSize: 11)
        memLabel.textColor = .secondaryLabelColor
        
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

        updateRow.addSubview(versionLabel)
        updateRow.addSubview(updateButton)
        updateRow.addSubview(updateSpinner)
        controlsGroup.contentView?.addSubview(updateRow)

        // 分隔线（0~2 对应 3 个 thresholdSection 底部，3 对应 memNote 底部与 updateRow 上方）
        for i in 0..<4 {
            let sep = NSBox()
            sep.boxType = .separator
            sep.identifier = NSUserInterfaceItemIdentifier("settings.separator.\(i)")
            controlsGroup.contentView?.addSubview(sep)
        }
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
        unit: String, index: Int
    ) -> NSView {
        let section = NSView()
        section.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index)")

        // 标题行
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        icon.contentTintColor = .labelColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)

        // 输入行
        let orangeLabel = NSTextField(labelWithString: "变橙")
        orangeLabel.font = .systemFont(ofSize: 11)
        orangeLabel.textColor = .systemOrange

        let orangeInput = NSTextField()
        orangeInput.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index).orangeInput")
        orangeInput.stringValue = formatThreshold(orangeValue)
        orangeInput.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        orangeInput.alignment = .center
        orangeInput.focusRingType = .none
        orangeInput.isBordered = true
        orangeInput.bezelStyle = .roundedBezel
        orangeInput.target = self
        orangeInput.action = #selector(thresholdValueChanged(_:))
        orangeInput.delegate = self

        let orangeUnit = NSTextField(labelWithString: unit)
        orangeUnit.font = .systemFont(ofSize: 11)
        orangeUnit.textColor = .secondaryLabelColor

        let redLabel = NSTextField(labelWithString: "变红")
        redLabel.font = .systemFont(ofSize: 11)
        redLabel.textColor = .systemRed

        let redInput = NSTextField()
        redInput.identifier = NSUserInterfaceItemIdentifier("settings.section.\(index).redInput")
        redInput.stringValue = formatThreshold(redValue)
        redInput.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        redInput.alignment = .center
        redInput.focusRingType = .none
        redInput.isBordered = true
        redInput.bezelStyle = .roundedBezel
        redInput.target = self
        redInput.action = #selector(thresholdValueChanged(_:))
        redInput.delegate = self

        let redUnit = NSTextField(labelWithString: unit)
        redUnit.font = .systemFont(ofSize: 11)
        redUnit.textColor = .secondaryLabelColor

        section.addSubview(icon)
        section.addSubview(titleLabel)
        section.addSubview(orangeLabel)
        section.addSubview(orangeInput)
        section.addSubview(orangeUnit)
        section.addSubview(redLabel)
        section.addSubview(redInput)
        section.addSubview(redUnit)

        thresholdInputs.append((orange: orangeInput, red: redInput))
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
        // 为什么：设置内容保持完整几何并随可见高度整体下移，避免在收起途中侵入上方三个固定控制行。
        let yOffset = visibleHeight - settingsHeight
        let sectionHeight = Layout.settingsThresholdRowHeight
        let sections = contentView.subviews.filter { $0.identifier?.rawValue.hasPrefix("settings.section.") == true }

        for (i, section) in sections.enumerated() {
            let y = settingsHeight - 24 - CGFloat(i + 1) * sectionHeight + yOffset
            section.frame = NSRect(x: 0, y: y, width: w, height: sectionHeight)
            layoutThresholdSection(section)
        }

        // 4 条 100% 等距分隔线（y = 144, 108, 72, 36）
        let separators = contentView.subviews.filter { $0.identifier?.rawValue.hasPrefix("settings.separator.") == true }
        for (i, sep) in separators.enumerated() {
            let y = settingsHeight - 24 - CGFloat(i + 1) * sectionHeight + yOffset
            layoutSeparator(sep, y: y, width: w)
        }

        // 设置说明文字
        if let descLabel = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.desc" }) {
            let descY = settingsHeight - 24 + yOffset
            descLabel.frame = NSRect(x: Layout.rowLeadingInset, y: descY, width: w - Layout.rowLeadingInset * 2, height: 16)
        }

        // 行 4：内存说明（统一 36pt 行高，居中置于 36pt 分隔线与 72pt 分隔线正中央）
        if let memNote = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.memNote" }) {
            let memY: CGFloat = 36.0 + yOffset
            memNote.frame = NSRect(x: Layout.rowLeadingInset, y: memY, width: w - Layout.rowLeadingInset * 2, height: sectionHeight)
            
            if memNote.subviews.count >= 2 {
                memNote.subviews[0].frame = NSRect(x: 0, y: 11, width: 14, height: 14) // icon 垂直绝对居中
                memNote.subviews[1].frame = NSRect(x: 26, y: 10, width: memNote.bounds.width - 26, height: 16) // label 全局 x=38 贯穿对齐
            }
        }

        // 行 5：检查更新与版本号底栏（统一 36pt 行高）
        if let updateRow = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.update.row" }) {
            updateRow.frame = NSRect(x: 0, y: yOffset, width: w, height: sectionHeight)
            let buttonW: CGFloat = 78
            let buttonX = w - Layout.trailingInset - buttonW

            if updateRow.subviews.count >= 3 {
                let versionLabel = updateRow.subviews[0]
                let updateButton = updateRow.subviews[1]
                let spinner = updateRow.subviews[2]

                versionLabel.frame = NSRect(x: Layout.titleX, y: 9, width: 120, height: 18)
                updateButton.frame = NSRect(x: buttonX, y: 8, width: buttonW, height: 20)
                spinner.frame = NSRect(x: buttonX - 22, y: 10, width: 16, height: 16)
            }
        }
    }

    private func layoutThresholdSection(_ section: NSView) {
        guard section.subviews.count >= 8 else { return }
        let icon = section.subviews[0]
        let title = section.subviews[1]
        // 1pt 光学对齐微调：图标向上抬 1pt，标题向下沉 1pt，基线与中心相接
        icon.frame = NSRect(x: Layout.rowLeadingInset, y: 10, width: 16, height: 16)
        title.frame = NSRect(x: Layout.titleX, y: 8, width: 68, height: 18)

        let labelW: CGFloat = 26
        let inputW: CGFloat = Layout.settingsInputWidth
        let unitW: CGFloat = Layout.settingsUnitSlotWidth

        let orangeLabel = section.subviews[2]
        let orangeInput = section.subviews[3]
        let orangeUnit = section.subviews[4]
        // 1pt 光学对齐微调：标签与单位下沉 1pt，文字基线与输入框数字平齐
        orangeLabel.frame = NSRect(x: 110, y: 9, width: labelW, height: 16)
        orangeInput.frame = NSRect(x: 138, y: 7, width: inputW, height: 22)
        orangeUnit.frame = NSRect(x: 180, y: 9, width: unitW, height: 16)

        let redLabel = section.subviews[5]
        let redInput = section.subviews[6]
        let redUnit = section.subviews[7]
        redLabel.frame = NSRect(x: 208, y: 9, width: labelW, height: 16)
        redInput.frame = NSRect(x: 236, y: 7, width: inputW, height: 22)
        redUnit.frame = NSRect(x: 278, y: 9, width: unitW, height: 16)
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
        let sectionHeight = Layout.settingsThresholdRowHeight
        return sectionHeight * 5 + 24 // 5 rows * 36pt + 24pt desc = 204pt
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

// MARK: - NSTextFieldDelegate
extension PopoverContentView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            thresholdValueChanged(textField)
        }
    }
}
