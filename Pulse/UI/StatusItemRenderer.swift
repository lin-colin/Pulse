import AppKit

/// 状态栏布局几何数据
struct StatusItemGeometry: Equatable {
    let canvasSize: NSSize
    let powerIconFrame: NSRect
    let temperatureIconFrame: NSRect
    let memoryIconFrame: NSRect
    let cpuIconFrame: NSRect
    let powerTextOrigin: NSPoint
    let temperatureTextOrigin: NSPoint
    let memoryTextOrigin: NSPoint
    let cpuTextOrigin: NSPoint
}

/// 渲染完成的状态栏位图图像及关联几何
struct RenderedStatusItem {
    let image: NSImage
    let geometry: StatusItemGeometry
}

/// 状态栏渲染器接口
protocol StatusItemRendering {
    func render(
        model: StatusItemRenderModel,
        appearance: NSAppearance,
        backingScaleFactor: CGFloat
    ) -> RenderedStatusItem?
}

/// 即时位图状态栏渲染器
/// 为什么：使用纯 CGContext + NSBitmapImageRep 立即生成像素点阵，替代由 NSTextField/NSImageView 组成的 AppKit 子视图树。
/// 彻底消除 AppKit 自动布局、NSStatusItemReplicantShadowView 副本重绘以及底层 CA::Transaction::commit 导致的 50%+ CPU 开销。
final class StatusItemRenderer: StatusItemRendering {

    private let font: NSFont = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

    func layout(for model: StatusItemRenderModel) -> StatusItemGeometry {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let powerTextWidth = (model.powerText as NSString).size(withAttributes: attributes).width
        let tempTextWidth = (model.temperatureText as NSString).size(withAttributes: attributes).width
        let memoryTextWidth = (model.memoryText as NSString).size(withAttributes: attributes).width
        let cpuTextWidth = (model.cpuText as NSString).size(withAttributes: attributes).width

        let leftColumnTextWidth = max(powerTextWidth, tempTextWidth)
        let rightColumnTextWidth = max(memoryTextWidth, cpuTextWidth)

        let leftInset: CGFloat = 5.0
        let iconSlotWidth: CGFloat = 12.0
        let iconTextSpacing: CGFloat = 2.5
        let columnSpacing: CGFloat = 4.5
        let rightInset: CGFloat = 5.0

        let leftTextX = leftInset + iconSlotWidth + iconTextSpacing
        let leftColumnWidth = iconSlotWidth + iconTextSpacing + leftColumnTextWidth

        let rightIconX = leftInset + leftColumnWidth + columnSpacing
        let rightTextX = rightIconX + iconSlotWidth + iconTextSpacing

        let totalWidth = rightTextX + rightColumnTextWidth + rightInset

        // 左列图标功耗与温度绘制框压矮至 12 × 10.5 pt，中心定位分别在 16 pt 与 6 pt 行中心
        let powerIconFrame = NSRect(x: leftInset, y: 16.0 - 10.5 / 2.0, width: 12.0, height: 10.5)
        let tempIconFrame = NSRect(x: leftInset, y: 6.0 - 10.5 / 2.0, width: 12.0, height: 10.5)

        // 右列图标内存与 CPU 保持 12 × 12 pt
        let memoryIconFrame = NSRect(x: rightIconX, y: 16.0 - 12.0 / 2.0, width: 12.0, height: 12.0)
        let cpuIconFrame = NSRect(x: rightIconX, y: 6.0 - 12.0 / 2.0, width: 12.0, height: 12.0)

        // 文字居中调整：使用 9 pt 数字字体的完整行高 (ascender - descender) 在 16 pt 与 6 pt 行中心线垂直居中
        let lineHeight = font.ascender - font.descender
        let powerTextOrigin = NSPoint(x: leftTextX, y: 16.0 - lineHeight / 2.0)
        let tempTextOrigin = NSPoint(x: leftTextX, y: 6.0 - lineHeight / 2.0)
        let memoryTextOrigin = NSPoint(x: rightTextX, y: 16.0 - lineHeight / 2.0)
        let cpuTextOrigin = NSPoint(x: rightTextX, y: 6.0 - lineHeight / 2.0)

        return StatusItemGeometry(
            canvasSize: NSSize(width: ceil(totalWidth), height: 22.0),
            powerIconFrame: powerIconFrame,
            temperatureIconFrame: tempIconFrame,
            memoryIconFrame: memoryIconFrame,
            cpuIconFrame: cpuIconFrame,
            powerTextOrigin: powerTextOrigin,
            temperatureTextOrigin: tempTextOrigin,
            memoryTextOrigin: memoryTextOrigin,
            cpuTextOrigin: cpuTextOrigin
        )
    }

    func render(
        model: StatusItemRenderModel,
        appearance: NSAppearance,
        backingScaleFactor: CGFloat
    ) -> RenderedStatusItem? {
        let geometry = layout(for: model)
        let scale = max(1.0, backingScaleFactor)
        let pixelsWide = Int(ceil(geometry.canvasSize.width * scale))
        let pixelsHigh = Int(ceil(geometry.canvasSize.height * scale))

        // 为什么：直接构造 NSBitmapImageRep 并在 CGContext 中即时栅格化绘制。
        // 绝对禁止返回带 NSCustomImageRep/drawingHandler 的 NSImage，防止系统菜单栏副本反复二次调用闭包绘制。
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmapRep.size = geometry.canvasSize

        var renderedItem: RenderedStatusItem?
        appearance.performAsCurrentDrawingAppearance {
            guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
                return
            }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            let cgContext = graphicsContext.cgContext
            cgContext.clear(NSRect(origin: .zero, size: geometry.canvasSize))

            // 绘制功耗图标（压矮至 12 × 10.5 pt）
            drawSymbol(
                name: model.powerSymbolName,
                colorRole: model.powerIconColor,
                in: geometry.powerIconFrame,
                appearance: appearance
            )

            // 绘制功耗数值
            drawText(
                model.powerText,
                colorRole: model.powerTextColor,
                at: geometry.powerTextOrigin,
                appearance: appearance
            )

            // 绘制温度图标（压矮至 12 × 10.5 pt）
            drawSymbol(
                name: "thermometer.medium",
                colorRole: model.temperatureColor,
                in: geometry.temperatureIconFrame,
                appearance: appearance
            )

            // 绘制温度数值
            drawText(
                model.temperatureText,
                colorRole: model.temperatureColor,
                at: geometry.temperatureTextOrigin,
                appearance: appearance
            )

            // 绘制内存图标 (12 × 12 pt)
            drawSymbol(
                name: "memorychip",
                colorRole: model.memoryColor,
                in: geometry.memoryIconFrame,
                appearance: appearance
            )

            // 绘制内存数值
            drawText(
                model.memoryText,
                colorRole: model.memoryColor,
                at: geometry.memoryTextOrigin,
                appearance: appearance
            )

            // 绘制 CPU 图标 (12 × 12 pt)
            drawSymbol(
                name: "cpu",
                colorRole: model.cpuColor,
                in: geometry.cpuIconFrame,
                appearance: appearance
            )

            // 绘制 CPU 数值
            drawText(
                model.cpuText,
                colorRole: model.cpuColor,
                at: geometry.cpuTextOrigin,
                appearance: appearance
            )

            NSGraphicsContext.restoreGraphicsState()

            let image = NSImage(size: geometry.canvasSize)
            image.addRepresentation(bitmapRep)
            image.isTemplate = false

            renderedItem = RenderedStatusItem(image: image, geometry: geometry)
        }

        return renderedItem
    }

    private func drawSymbol(
        name: String,
        colorRole: StatusItemColorRole,
        in frame: NSRect,
        appearance: NSAppearance
    ) {
        let weight: NSFont.Weight = (name == "powerplug.fill" ? .bold : .semibold)
        let resolvedColor = color(for: colorRole, appearance: appearance)

        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 12.0, weight: weight)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [resolvedColor])
        let configuration = sizeConfig.applying(colorConfig)

        guard let symbolImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return
        }

        // 为什么：SF Symbol 恢复 12 pt 属性，右列在 12x12 pt 槽内保持原比例居中绘制，
        // 左列在其 12x10.5 pt 框架中精准绘制，彻底消除实心矩形块与右列像素重合。
        let symbolSize = symbolImage.size
        let targetRect: NSRect
        if abs(frame.height - 12.0) < 0.1 && symbolSize.width > 0 && symbolSize.height > 0 {
            let scale = min(frame.width / symbolSize.width, frame.height / symbolSize.height)
            let drawWidth = symbolSize.width * scale
            let drawHeight = symbolSize.height * scale
            let drawX = frame.minX + (frame.width - drawWidth) / 2.0
            let drawY = frame.minY + (frame.height - drawHeight) / 2.0
            targetRect = NSRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight)
        } else {
            targetRect = frame
        }

        symbolImage.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    private func drawText(
        _ text: String,
        colorRole: StatusItemColorRole,
        at origin: NSPoint,
        appearance: NSAppearance
    ) {
        let textColor = color(for: colorRole, appearance: appearance)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func color(for role: StatusItemColorRole, appearance: NSAppearance) -> NSColor {
        switch role {
        case .label:
            return .labelColor
        case .secondaryLabel:
            return .secondaryLabelColor
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .orange:
            return .systemOrange
        case .red:
            return .systemRed
        }
    }
}
