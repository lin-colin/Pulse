import AppKit

// Pulse - macOS 菜单栏系统监控工具
// 纯代码启动，无 Storyboard / NIB

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
