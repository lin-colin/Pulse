import AppKit

/// 轻量级 GitHub Release 更新检查器，不依赖 Sparkle，不需要付费签名。
enum UpdateChecker {

    private static let repoOwner = "lin-colin"
    private static let repoName = "Pulse"
    private static let releasesURL = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    private static let releasePageURL = "https://github.com/\(repoOwner)/\(repoName)/releases/latest"

    /// 当前应用版本号（从 Info.plist 读取）。
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 检查 GitHub 最新 Release，与当前版本比对后回调结果。
    static func checkForUpdate(completion: @escaping (UpdateResult) -> Void) {
        guard let url = URL(string: releasesURL) else {
            completion(.error("无效的请求地址"))
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async {
                    completion(.error("网络请求失败：\(error.localizedDescription)"))
                }
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                DispatchQueue.main.async {
                    completion(.error("无法解析版本信息"))
                }
                return
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            URLCache.shared.removeAllCachedResponses()
            DispatchQueue.main.async {
                if isNewerVersion(latestVersion, than: currentVersion) {
                    completion(.updateAvailable(latestVersion))
                } else {
                    completion(.upToDate)
                }
            }
        }.resume()
    }

    /// 显示更新结果弹窗。
    static func showUpdateAlert(result: UpdateResult) {
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch result {
        case .upToDate:
            alert.messageText = "✅ 当前已是最新版本"
            alert.informativeText = "当前版本：v\(currentVersion)"
            alert.addButton(withTitle: "好的")

        case .updateAvailable(let version):
            alert.messageText = "🎉 发现新版本 v\(version)"
            alert.informativeText = "当前版本：v\(currentVersion)\n最新版本：v\(version)\n\n是否前往下载？"
            alert.addButton(withTitle: "前往下载")
            alert.addButton(withTitle: "稍后再说")

        case .error(let message):
            alert.alertStyle = .warning
            alert.messageText = "⚠️ 检查更新失败"
            alert.informativeText = message
            alert.addButton(withTitle: "好的")
        }

        let response = alert.runModal()
        if case .updateAvailable = result, response == .alertFirstButtonReturn {
            if let url = URL(string: releasePageURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 语义化版本比较：latestVersion 是否比 currentVersion 新。
    private static func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(latestParts.count, currentParts.count) {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }

    enum UpdateResult {
        case upToDate
        case updateAvailable(String)
        case error(String)
    }
}
