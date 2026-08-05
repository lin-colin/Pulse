import AppKit
import Darwin

/// 验证状态栏位图渲染器的尺寸、图标绘制框、透明轮廓及无重合像素。
@main
struct StatusItemIconSizingTests {
    private static var failures = 0

    static func main() {
        let renderer = StatusItemRenderer()
        let model = StatusItemRenderModel.make(
            snapshot: makePulseSnapshot(),
            thresholds: .defaults()
        )
        let geometry = renderer.layout(for: model)

        expect(geometry.canvasSize.height == 22, "menu bar image must remain 22 pt high")
        expect(geometry.powerIconFrame.size == NSSize(width: 12, height: 10.5),
               "power icon must keep width and compress only height")
        expect(geometry.temperatureIconFrame.size == NSSize(width: 12, height: 10.5),
               "temperature icon must keep width and compress only height")
        expect(geometry.memoryIconFrame.size == NSSize(width: 12, height: 12),
               "memory icon must remain 12x12 pt")
        expect(geometry.cpuIconFrame.size == NSSize(width: 12, height: 12),
               "CPU icon must remain 12x12 pt")
        expect(geometry.powerTextOrigin.x == geometry.temperatureTextOrigin.x,
               "left-column text alignment must not move")
        expect(geometry.memoryTextOrigin.x == geometry.cpuTextOrigin.x,
               "right-column text alignment must not move")

        expect(geometry.powerIconFrame.midY == 16, "power icon center must be 16 pt")
        expect(geometry.temperatureIconFrame.midY == 6, "temperature icon center must be 6 pt")

        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let lineHeight = font.ascender - font.descender
        let powerTextCenterY = geometry.powerTextOrigin.y + lineHeight / 2.0
        expect(abs(powerTextCenterY - 16.0) < 0.1, "power text must be vertically centered with top row center 16pt")
        let tempTextCenterY = geometry.temperatureTextOrigin.y + lineHeight / 2.0
        expect(abs(tempTextCenterY - 6.0) < 0.1, "temperature text must be vertically centered with bottom row center 6pt")

        let rendered = renderer.render(
            model: model,
            appearance: NSAppearance(named: .darkAqua)!,
            backingScaleFactor: 2
        )
        expect(rendered != nil, "renderer should produce an image")
        expect(rendered?.image.representations.allSatisfy { !($0 is NSCustomImageRep) } == true,
               "status image must not contain lazy custom drawing representations")
        expect(rendered?.image.size == geometry.canvasSize,
               "bitmap logical size must match layout")

        if let renderedImage = rendered?.image,
           let cgImage = renderedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            let memoryPixels = countVisibleAlphaPixels(in: geometry.memoryIconFrame, rep: bitmapRep, scale: 2)
            let totalMemoryPixels = geometry.memoryIconFrame.width * 2 * geometry.memoryIconFrame.height * 2
            let memoryCoverage = Double(memoryPixels) / Double(totalMemoryPixels)

            expect(memoryCoverage > 0.05, "memory icon must contain visible pixels")
            expect(memoryCoverage < 0.75, "memory icon must preserve transparent outline, not a solid block")

            let hasVerticalOverlap = checkVerticalOverlapBetweenMemoryAndCpu(
                memoryFrame: geometry.memoryIconFrame,
                cpuFrame: geometry.cpuIconFrame,
                rep: bitmapRep,
                scale: 2
            )
            expect(!hasVerticalOverlap, "memory and CPU visible pixels must not overlap vertically")
        }

        finish()
    }

    private static func countVisibleAlphaPixels(in frame: NSRect, rep: NSBitmapImageRep, scale: CGFloat) -> Int {
        let minX = Int(frame.minX * scale)
        let maxX = Int(frame.maxX * scale)
        let minY = Int(frame.minY * scale)
        let maxY = Int(frame.maxY * scale)

        var count = 0
        for x in minX..<maxX {
            for y in minY..<maxY {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    count += 1
                }
            }
        }
        return count
    }

    private static func checkVerticalOverlapBetweenMemoryAndCpu(
        memoryFrame: NSRect,
        cpuFrame: NSRect,
        rep: NSBitmapImageRep,
        scale: CGFloat
    ) -> Bool {
        let minX = Int(memoryFrame.minX * scale)
        let maxX = Int(memoryFrame.maxX * scale)

        let memoryMinY = Int(memoryFrame.minY * scale)
        let memoryMaxY = Int(memoryFrame.maxY * scale)

        let cpuMinY = Int(cpuFrame.minY * scale)
        let cpuMaxY = Int(cpuFrame.maxY * scale)

        var memoryActiveY = Set<Int>()
        var cpuActiveY = Set<Int>()

        for x in minX..<maxX {
            for y in memoryMinY..<memoryMaxY {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    memoryActiveY.insert(y)
                }
            }
            for y in cpuMinY..<cpuMaxY {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    cpuActiveY.insert(y)
                }
            }
        }

        return !memoryActiveY.intersection(cpuActiveY).isEmpty
    }

    private static func makePulseSnapshot() -> PulseSnapshot {
        let totalBytes: UInt64 = 24 * 1_073_741_824
        return PulseSnapshot(
            power: 7.1,
            memory: MemorySnapshot(
                usedBytes: UInt64(Double(totalBytes) * 0.41),
                totalBytes: totalBytes,
                usagePercentage: 41,
                pressureLevel: .normal
            ),
            temperature: 30.6,
            cpuUsage: 10,
            cpuFrequency: 0,
            powerSource: PowerSourceSnapshot(
                isCharging: false,
                isPluggedIn: false,
                description: "使用电池"
            )
        )
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }

    private static func finish() -> Never {
        if failures > 0 {
            fputs("FAILED: \(failures) focused assertions\n", stderr)
            exit(1)
        }
        print("PASSED: focused status icon sizing")
        exit(0)
    }
}
