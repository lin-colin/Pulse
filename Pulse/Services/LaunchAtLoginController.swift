import Foundation
import ServiceManagement

enum LaunchAtLoginError: Error {
    case operationFailed
}

/// 系统开机启动边界；UI 只依赖真实状态与一次设置操作。
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginSettings {
    /// 为什么：设置请求的最终显示值只能来自系统真实状态，不能直接相信用户期望值。
    static func apply(
        requestedState: Bool,
        using controller: LaunchAtLoginControlling,
        onError: (Error) -> Void = { _ in }
    ) -> Bool {
        do {
            try controller.setEnabled(requestedState)
        } catch {
            onError(error)
        }
        return controller.isEnabled
    }
}

/// 为什么：隔离 SMAppService 后，失败时可以重新读取真实状态并确定性验证 UI 回滚。
final class LaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LaunchAtLoginError.operationFailed
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw LaunchAtLoginError.operationFailed
        }
    }
}
