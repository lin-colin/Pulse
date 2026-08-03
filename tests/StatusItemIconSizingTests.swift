import AppKit
import Darwin

/// 只验证本轮菜单栏图标尺寸，不触发 Pulse 的完整功能回归测试。
@main
struct StatusItemIconSizingTests {
    private static var failures = 0

    static func main() {
        let view = StatusItemView(frame: NSRect(x: 0, y: 0, width: 1, height: 22))
        let width = view.update(
            power: 3.7,
            memoryUsagePercentage: 70,
            memoryPressureLevel: .normal,
            temperature: 34,
            cpuUsage: 9,
            isCharging: false,
            isPluggedIn: true
        )
        view.frame.size = NSSize(width: width, height: 22)
        view.layoutSubtreeIfNeeded()

        // StatusItemView 按功率、温度、内存、CPU 的固定顺序创建四个常驻图标。
        let icons = view.subviews.compactMap { $0 as? NSImageView }
        expect(icons.count == 4, "expected four production status icons")
        guard icons.count == 4 else { finish() }

        expect(
            icons.allSatisfy { $0.frame.width == 12 && $0.frame.height == 12 },
            "every status icon should use a uniform 12 by 12 pt frame"
        )
        expect(
            icons.allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY <= 22 },
            "larger icons must remain inside the 22 pt menu bar"
        )
        expect(
            icons[1].frame.maxY - icons[0].frame.minY == 2
                && icons[3].frame.maxY - icons[2].frame.minY == 2,
            "twelve-point rows should have the documented two-point frame overlap"
        )

        let labels = view.subviews.compactMap { $0 as? NSTextField }
        expect(
            labels.count == 4
                && labels[0].frame.minX == labels[1].frame.minX
                && labels[2].frame.minX == labels[3].frame.minX,
            "larger icon slots must preserve vertical label alignment"
        )
        finish()
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
