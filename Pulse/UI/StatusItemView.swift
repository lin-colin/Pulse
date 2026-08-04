import AppKit

/// 菜单栏 2×2 指标视图；复用原生子视图并在绘制前报告完整固有宽度。
final class StatusItemView: NSView {

    private let powerIcon = NSImageView()
    private let temperatureIcon = NSImageView()
    private let memoryIcon = NSImageView()
    private let cpuIcon = NSImageView()

    private let powerLabel = NSTextField(labelWithString: "—")
    private let temperatureLabel = NSTextField(labelWithString: "—")
    private let memoryLabel = NSTextField(labelWithString: "—")
    private let cpuLabel = NSTextField(labelWithString: "—")

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private let iconSlotWidth: CGFloat = 12
    private let iconSize = NSSize(width: 12, height: 12)
    private let leftPadding: CGFloat = 5
    private let rightPadding: CGFloat = 9
    private let labelSafetyWidth: CGFloat = 2
    private let iconTextGap: CGFloat = 2.5
    private let columnGap: CGFloat = 4.5
    private var symbolCache: [String: NSImage] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureSubviews()
    }

    /// 为什么：内容视图只展示数据，点击必须由父 NSStatusBarButton 统一切换 Popover。
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let firstColumnWidth = max(
            powerLabel.intrinsicContentSize.width,
            temperatureLabel.intrinsicContentSize.width
        ) + labelSafetyWidth
        let secondColumnWidth = max(
            memoryLabel.intrinsicContentSize.width,
            cpuLabel.intrinsicContentSize.width
        ) + labelSafetyWidth
        let width = leftPadding + rightPadding
            + iconSlotWidth + iconTextGap + firstColumnWidth
            + columnGap
            + iconSlotWidth + iconTextGap + secondColumnWidth
        return NSSize(width: ceil(width), height: 22)
    }

    /// 更新既有控件并返回父 NSStatusItem 必须采用的完整宽度。
    @discardableResult
    func update(
        power: Double?,
        memoryUsagePercentage: Double?,
        memoryPressureLevel: MemoryPressureLevel,
        temperature: Double?,
        cpuUsage: Double,
        isCharging: Bool,
        isPluggedIn: Bool
    ) -> CGFloat {
        powerLabel.stringValue = MetricCalculations.formatted(
            power,
            decimals: 1,
            suffix: "W"
        )
        temperatureLabel.stringValue = MetricCalculations.formatted(
            temperature,
            decimals: 1,
            suffix: "°C"
        )
        memoryLabel.stringValue = MetricCalculations.formatted(
            memoryUsagePercentage,
            decimals: 0,
            suffix: "%"
        )
        cpuLabel.stringValue = MetricCalculations.formatted(
            cpuUsage,
            decimals: 0,
            suffix: "%"
        )

        updateColors(
            power: power,
            memoryPressureLevel: memoryPressureLevel,
            temperature: temperature,
            cpuUsage: cpuUsage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn
        )
        invalidateIntrinsicContentSize()
        needsLayout = true
        return intrinsicContentSize.width
    }

    override func layout() {
        super.layout()

        let firstColumnWidth = max(
            powerLabel.intrinsicContentSize.width,
            temperatureLabel.intrinsicContentSize.width
        ) + labelSafetyWidth
        let secondColumnX = leftPadding
            + iconSlotWidth + iconTextGap + firstColumnWidth + columnGap
        // 两排 12 pt 图标在 22 pt 总高内交叠 2 pt；以行中心点对齐图标与文字。
        let topRowCenterY: CGFloat = 16
        let bottomRowCenterY: CGFloat = 6

        layoutPair(
            icon: powerIcon,
            label: powerLabel,
            x: leftPadding,
            rowCenterY: topRowCenterY
        )
        layoutPair(
            icon: temperatureIcon,
            label: temperatureLabel,
            x: leftPadding,
            rowCenterY: bottomRowCenterY
        )
        layoutPair(
            icon: memoryIcon,
            label: memoryLabel,
            x: secondColumnX,
            rowCenterY: topRowCenterY
        )
        layoutPair(
            icon: cpuIcon,
            label: cpuLabel,
            x: secondColumnX,
            rowCenterY: bottomRowCenterY
        )
    }

    private func configureSubviews() {
        for label in [powerLabel, temperatureLabel, memoryLabel, cpuLabel] {
            label.font = font
            label.lineBreakMode = .byClipping
            label.maximumNumberOfLines = 1
            addSubview(label)
        }

        configureIcon(powerIcon, symbolName: "powerplug.fill")
        configureIcon(temperatureIcon, symbolName: "thermometer.medium")
        configureIcon(memoryIcon, symbolName: "memorychip")
        configureIcon(cpuIcon, symbolName: "cpu")
    }

    private func configureIcon(_ imageView: NSImageView, symbolName: String) {
        imageView.image = symbolImage(named: symbolName)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        addSubview(imageView)
    }

    private func layoutPair(
        icon: NSImageView,
        label: NSTextField,
        x: CGFloat,
        rowCenterY: CGFloat
    ) {
        // 图标与标签以行中心点做垂直居中，确保上下严格对齐。
        icon.frame = NSRect(
            x: x,
            y: rowCenterY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        let labelSize = label.intrinsicContentSize
        label.frame = NSRect(
            x: x + iconSlotWidth + iconTextGap,
            y: rowCenterY - labelSize.height / 2,
            width: labelSize.width + labelSafetyWidth,
            height: labelSize.height
        )
    }

    private func symbolImage(named name: String) -> NSImage? {
        if let cached = symbolCache[name] {
            return cached
        }
        // 为什么：插头符号自身的可见边界较窄，略增字号和字重才能与其他指标图标等视。
        let isPlugSymbol = name == "powerplug.fill"
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 12,
            weight: isPlugSymbol ? .bold : .semibold
        )
        guard let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else {
            return nil
        }
        image.isTemplate = true
        symbolCache[name] = image
        return image
    }

    private func updateColors(
        power: Double?,
        memoryPressureLevel: MemoryPressureLevel,
        temperature: Double?,
        cpuUsage: Double,
        isCharging: Bool,
        isPluggedIn: Bool
    ) {
        let baseColor = NSColor.labelColor
        let thresholds = ThresholdConfig.load()

        let powerConfiguration = MetricCalculations.powerDisplayConfiguration(
            power: power,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            orangeThreshold: thresholds.power.orange,
            redThreshold: thresholds.power.red
        )
        powerIcon.image = symbolImage(named: powerConfiguration.symbolName)
        powerIcon.contentTintColor = powerConfiguration.iconColorRole.toNSColor(
            baseColor: baseColor
        )
        powerLabel.textColor = powerConfiguration.textColorRole.toNSColor(
            baseColor: baseColor
        )

        let temperatureColor: NSColor
        if let temperature, temperature >= thresholds.temperature.red {
            temperatureColor = .systemRed
        } else if let temperature, temperature >= thresholds.temperature.orange {
            temperatureColor = .systemOrange
        } else {
            temperatureColor = baseColor
        }
        temperatureIcon.contentTintColor = temperatureColor
        temperatureLabel.textColor = temperatureColor

        let memoryColor: NSColor
        switch memoryPressureLevel.presentationRole {
        case .healthy: memoryColor = .systemGreen
        case .warning: memoryColor = .systemYellow
        case .critical: memoryColor = .systemRed
        case .unavailable: memoryColor = .secondaryLabelColor
        }
        memoryIcon.contentTintColor = memoryColor
        memoryLabel.textColor = memoryColor

        let cpuColor: NSColor
        if cpuUsage >= thresholds.cpu.red {
            cpuColor = .systemRed
        } else if cpuUsage >= thresholds.cpu.orange {
            cpuColor = .systemOrange
        } else {
            cpuColor = baseColor
        }
        cpuIcon.contentTintColor = cpuColor
        cpuLabel.textColor = cpuColor
    }
}

extension ColorRole {
    /// 将纯逻辑颜色角色映射为 AppKit 动态颜色。
    fileprivate func toNSColor(baseColor: NSColor) -> NSColor {
        switch self {
        case .normal: return baseColor
        case .chargingGreen: return .systemGreen
        case .orangeWarning: return .systemOrange
        case .redWarning: return .systemRed
        }
    }
}
