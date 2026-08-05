import AppKit

/// macOS 系统设置式详情内容；控件只创建一次，刷新时仅更新既有标签。
final class PopoverContentView: NSView {
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
        static let metricRowHeight: CGFloat = 40
        static let controlRowHeight: CGFloat = 40
        static let settingsRowHeight: CGFloat = 32
        static let settingsInputRowHeight: CGFloat = 36
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
    private let moreChevron = NSImageView()
    private var thresholdInputs: [(orange: NSTextField, red: NSTextField)] = []
    private var thresholdConfig: ThresholdConfig

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
        let settingsHeight = settingsExpanded ? computeSettingsHeight() : 0
        let controlsHeight: CGFloat = 120 + settingsHeight

        // 从顶部向下定位：metricsGroup 始终紧贴顶部，展开时只有下方内容向下延伸
        let metricsY = bounds.height - 8 - 240
        let controlsY = metricsY - 8 - controlsHeight
        let quitY = controlsY - 8 - 40

        metricsGroup.frame = NSRect(x: Layout.outerInset, y: metricsY, width: contentWidth, height: 240)
        controlsGroup.frame = NSRect(x: Layout.outerInset, y: controlsY, width: contentWidth, height: controlsHeight)
        quitGroup.frame = NSRect(x: Layout.outerInset, y: quitY, width: contentWidth, height: 40)

        layoutMetricRows()
        layoutControlRows()
        if settingsExpanded { layoutSettingsRows() }
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

        // 检查更新按钮
        let updateRow = NSView()
        updateRow.identifier = NSUserInterfaceItemIdentifier("settings.update.row")
        let updateIcon = NSImageView()
        updateIcon.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "检查更新"
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        updateIcon.contentTintColor = .labelColor
        let updateLabel = NSTextField(labelWithString: "检查更新")
        updateLabel.font = .systemFont(ofSize: 13)
        let updateButton = NSButton()
        updateButton.title = ""
        updateButton.isBordered = false
        updateButton.focusRingType = .none
        updateButton.target = self
        updateButton.action = #selector(checkUpdateTapped(_:))
        updateRow.addSubview(updateIcon)
        updateRow.addSubview(updateLabel)
        updateRow.addSubview(updateButton)
        controlsGroup.contentView?.addSubview(updateRow)

        // 分隔线
        for i in 0..<3 {
            let sep = NSBox()
            sep.boxType = .separator
            sep.identifier = NSUserInterfaceItemIdentifier("settings.separator.\(i)")
            controlsGroup.contentView?.addSubview(sep)
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

    private func layoutSettingsRows() {
        guard settingsExpanded, let contentView = controlsGroup.contentView else { return }
        let w = controlsGroup.bounds.width
        let settingsHeight = computeSettingsHeight()
        let sectionHeight = Layout.settingsRowHeight + Layout.settingsInputRowHeight
        let sections = contentView.subviews.filter { $0.identifier?.rawValue.hasPrefix("settings.section.") == true }

        for (i, section) in sections.enumerated() {
            let y = settingsHeight - 24 - CGFloat(i + 1) * sectionHeight
            section.frame = NSRect(x: 0, y: y, width: w, height: sectionHeight)
            section.isHidden = false
            layoutThresholdSection(section)
        }

        // 分隔线
        let separators = contentView.subviews.filter { $0.identifier?.rawValue.hasPrefix("settings.separator.") == true }
        for (i, sep) in separators.enumerated() {
            let y = settingsHeight - 24 - CGFloat(i + 1) * sectionHeight
            layoutSeparator(sep, y: y, width: w)
            sep.isHidden = false
        }

        // 设置说明文字
        if let descLabel = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.desc" }) {
            let descY = settingsHeight - 24
            descLabel.frame = NSRect(x: Layout.rowLeadingInset, y: descY, width: w - Layout.rowLeadingInset * 2, height: 16)
            descLabel.isHidden = false
        }

        // 内存说明
        if let memNote = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.memNote" }) {
            let memY = settingsHeight - 24 - CGFloat(sections.count) * sectionHeight - 24
            memNote.frame = NSRect(x: Layout.rowLeadingInset, y: memY, width: w - Layout.rowLeadingInset * 2, height: 16)
            memNote.isHidden = false
            
            if memNote.subviews.count >= 2 {
                memNote.subviews[0].frame = NSRect(x: 0, y: 2, width: 14, height: 14) // icon
                memNote.subviews[1].frame = NSRect(x: 20, y: 0, width: memNote.bounds.width - 20, height: 16) // label
            }
        }

        // 检查更新行
        if let updateRow = contentView.subviews.first(where: { $0.identifier?.rawValue == "settings.update.row" }) {
            updateRow.frame = NSRect(x: 0, y: 0, width: w, height: Layout.controlRowHeight)
            if updateRow.subviews.count >= 3 {
                updateRow.subviews[0].frame = NSRect(x: Layout.rowLeadingInset, y: 10, width: Layout.iconSlotWidth, height: Layout.iconSlotWidth)
                updateRow.subviews[1].frame = NSRect(x: Layout.titleX, y: 11, width: 120, height: 18)
                updateRow.subviews[2].frame = updateRow.bounds
            }
            updateRow.isHidden = false
        }
    }

    private func layoutThresholdSection(_ section: NSView) {
        guard section.subviews.count >= 8 else { return }
        let w = section.bounds.width
        let topY = Layout.settingsInputRowHeight
        let icon = section.subviews[0]
        let title = section.subviews[1]
        icon.frame = NSRect(x: Layout.rowLeadingInset, y: topY + 7, width: 16, height: 16)
        title.frame = NSRect(x: Layout.titleX, y: topY + 6, width: 80, height: 18)

        let inputY: CGFloat = 6
        let inputW: CGFloat = 48
        let labelW: CGFloat = 28
        let unitW: CGFloat = 22
        let leftX = Layout.rowLeadingInset + 4
        let orangeLabel = section.subviews[2]
        let orangeInput = section.subviews[3]
        let orangeUnit = section.subviews[4]
        orangeLabel.frame = NSRect(x: leftX, y: inputY + 2, width: labelW, height: 16)
        orangeInput.frame = NSRect(x: leftX + labelW + 4, y: inputY, width: inputW, height: 22)
        orangeUnit.frame = NSRect(x: leftX + labelW + inputW + 8, y: inputY + 2, width: unitW, height: 16)

        let rightX = w / 2 + 8
        let redLabel = section.subviews[5]
        let redInput = section.subviews[6]
        let redUnit = section.subviews[7]
        redLabel.frame = NSRect(x: rightX, y: inputY + 2, width: labelW, height: 16)
        redInput.frame = NSRect(x: rightX + labelW + 4, y: inputY, width: inputW, height: 22)
        redUnit.frame = NSRect(x: rightX + labelW + inputW + 8, y: inputY + 2, width: unitW, height: 16)
    }

    // MARK: - Control Rows Layout (updated for 3 rows)

    private func layoutControlRows() {
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

        // Hide/show settings elements based on expanded state
        let settingsViews = contentView.subviews.filter {
            let id = $0.identifier?.rawValue ?? ""
            return id.hasPrefix("settings.")
        }
        for v in settingsViews {
            v.isHidden = !settingsExpanded
        }
    }

    // MARK: - Height Calculation

    private func computeSettingsHeight() -> CGFloat {
        let sectionHeight = Layout.settingsRowHeight + Layout.settingsInputRowHeight
        return sectionHeight * 3 + 48 + Layout.controlRowHeight // 3 sections + desc + mem note + update row
    }

    func computeTotalHeight() -> CGFloat {
        let settingsHeight = settingsExpanded ? computeSettingsHeight() : 0
        let controlsHeight: CGFloat = 120 + settingsHeight
        return 8 + 240 + 8 + controlsHeight + 8 + 40 + 8
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
