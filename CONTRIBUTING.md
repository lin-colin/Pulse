# 参与贡献 (Contributing)

感谢你对 Pulse 项目的兴趣！我们非常欢迎来自社区的贡献，无论是报告 Bug、提出新功能建议，还是提交代码。

## 提交 Issue

在提交 Issue 之前，请先搜索已有的 Issue，确认是否已经有人提出过相同的问题。

- **Bug 报告**：请使用 `Bug report` 模板，并尽可能详细地描述复现步骤、系统版本以及预期的行为。
- **功能请求**：请使用 `Feature request` 模板，说明该功能的使用场景和它能带来的价值。

## 提交 Pull Request (PR)

1. Fork 本仓库。
2. 创建一个新的分支 (`git checkout -b feature/your-feature-name`)。
3. 确保你的代码风格与现有项目一致 (Swift)。
4. 如果你添加了新功能或修改了逻辑，请确保相关的测试（如果有）能够通过。可以运行 `./test.sh` 进行验证。
5. 提交你的修改 (`git commit -m 'feat: Add some feature'`)。
6. 推送到分支 (`git push origin feature/your-feature-name`)。
7. 在 GitHub 上发起一个 Pull Request，并清晰地描述你的修改内容。

## 本地开发环境

- **macOS 版本**：macOS 13.0 (Ventura) 及以上。
- **开发工具**：Xcode Command Line Tools 或 Xcode。
- **构建方式**：直接运行仓库根目录的 `./build.sh` 脚本即可。项目目前不依赖任何外部第三方库（Package.swift 或 Cocoapods），所有依赖均为系统原生库 (AppKit, IOKit, ServiceManagement)。

---

再次感谢你的贡献！
