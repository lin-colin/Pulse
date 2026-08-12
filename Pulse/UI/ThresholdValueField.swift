import AppKit

/// 为什么用 NSView 而不是 NSTextField：
/// macOS 对任何使用 NSTextField 的 App Bundle 都会拉起 AutoFill XPC 进程（~10MB），
/// 即使设置 isAutomaticTextCompletionEnabled = false 也无法阻止。
/// 自定义 NSView + keyDown 完全绕开 field editor 机制，从根本上消除 AutoFill 触发源。
final class NumericInputView: NSView {
    var stringValue: String = "" {
        didSet {
            if stringValue != oldValue {
                needsDisplay = true
                superview?.needsLayout = true
            }
        }
    }

    /// 编辑确认回调，等价于 NSTextField 的 action
    var onCommit: (() -> Void)?
    /// 焦点变化回调
    var onFocusChange: ((Bool) -> Void)?
    /// 实时编辑变化回调，等价于 controlTextDidChange
    var onTextChange: (() -> Void)?

    private var isEditing = false
    private var originalValue = ""
    private var cursorVisible = false
    private var cursorTimer: Timer?

    var font: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .medium) {
        didSet { needsDisplay = true }
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let success = super.becomeFirstResponder()
        if success {
            isEditing = true
            originalValue = stringValue
            startCursorBlink()
            onFocusChange?(true)
            needsDisplay = true
        }
        return success
    }

    override func resignFirstResponder() -> Bool {
        let success = super.resignFirstResponder()
        if success {
            commitEditing()
        }
        return success
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let text = stringValue.isEmpty && !isEditing ? "0" : stringValue
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        // 水平居中、垂直居中绘制数字
        let x = max(0, (bounds.width - size.width) / 2)
        let y = max(0, (bounds.height - size.height) / 2)
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

        // 编辑态闪烁光标
        if isEditing && cursorVisible {
            let cursorX = x + size.width + 1
            let cursorY = y + 1
            let cursorHeight = size.height - 2
            NSColor.controlAccentColor.setFill()
            NSRect(x: cursorX, y: cursorY, width: 1, height: cursorHeight).fill()
        }
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        switch chars {
        case _ where chars.allSatisfy({ $0.isNumber }):
            stringValue += chars
            onTextChange?()

        case ".":
            // 只允许一个小数点
            if !stringValue.contains(".") {
                stringValue += "."
                onTextChange?()
            }

        case "\u{7F}": // Delete (backspace)
            if !stringValue.isEmpty {
                stringValue.removeLast()
                onTextChange?()
            }

        case "\r", "\n": // Return / Enter → 确认并提交
            commitEditing()
            onCommit?()

        case "\t": // Tab → 确认并移到下一个
            commitEditing()
            onCommit?()
            window?.selectNextKeyView(self)

        case "\u{19}": // Shift+Tab (backtab)
            commitEditing()
            onCommit?()
            window?.selectPreviousKeyView(self)

        case "\u{1B}": // Escape → 取消编辑，恢复原值
            stringValue = originalValue
            commitEditing()

        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    // MARK: - Accessibility

    override func accessibilityValue() -> Any? { stringValue }
    override func accessibilityRole() -> NSAccessibility.Role? { .textField }
    override func isAccessibilityElement() -> Bool { true }

    private var accessibilityLabelValue: String?
    override func accessibilityLabel() -> String? { accessibilityLabelValue }
    func setAccessibilityLabel(_ label: String) { accessibilityLabelValue = label }

    // MARK: - Private

    private func startCursorBlink() {
        cursorVisible = true
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cursorVisible.toggle()
            self.needsDisplay = true
        }
    }

    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursorVisible = false
    }

    private func commitEditing() {
        guard isEditing else { return }
        isEditing = false
        stopCursorBlink()
        // 空值恢复为原始值
        if stringValue.isEmpty {
            stringValue = originalValue
        }
        onFocusChange?(false)
        needsDisplay = true
    }

    deinit {
        cursorTimer?.invalidate()
    }
}

final class ThresholdValueField: NSView {
    let inputView = NumericInputView()
    private let unitLabel: NSTextField
    private var isFocused = false

    /// 为兼容现有代码而提供的便利属性
    var textField: NumericInputView { inputView }

    init(unit: String) {
        unitLabel = NSTextField(labelWithString: unit)
        super.init(frame: .zero)

        unitLabel.font = .systemFont(ofSize: 9.5)
        unitLabel.textColor = .secondaryLabelColor
        unitLabel.alignment = .left

        addSubview(inputView)
        addSubview(unitLabel)

        inputView.onFocusChange = { [weak self] focused in
            self?.isFocused = focused
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { nil }

    // 扩大点击热区：点击 64x24 卡片内部任意区域（包括单位标签与空白处）均自动聚焦至输入框
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(inputView)
    }

    // 为什么用 draw() 而非 NSBox.fillColor：
    // NSBox.fillColor 在 NSPopover 中外观切换时不会自动重新解析动态颜色，
    // 而 draw() 中使用的动态颜色（controlBackgroundColor、separatorColor）
    // 始终在当前绘制上下文中解析，保证 dark↔light 切换时颜色实时正确。
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)

        // 背景填充
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()

        // 边框
        if isFocused {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
        } else {
            NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
            path.lineWidth = 0.5
        }
        path.stroke()
    }

    // 外观变化时触发重绘，确保 draw() 中的动态颜色在新外观下重新解析
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        inputView.needsDisplay = true
    }

    override func layout() {
        super.layout()

        unitLabel.sizeToFit()
        let unitWidth = ceil(unitLabel.frame.width)

        let font = inputView.font
        let text = inputView.stringValue.isEmpty ? "0" : inputView.stringValue
        let numberWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)

        let spacing: CGFloat = 3
        let totalWidth = numberWidth + spacing + unitWidth
        let startX = max(4, floor((bounds.width - totalWidth) / 2))

        inputView.frame = NSRect(
            x: startX,
            y: (bounds.height - 18) / 2,
            width: numberWidth + 4,
            height: 18
        )
        unitLabel.frame = NSRect(
            x: inputView.frame.maxX + spacing - 2,
            y: 3.5,
            width: unitWidth,
            height: 14
        )
    }
}
