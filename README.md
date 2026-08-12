# Pulse 💓

> 极致轻量、免 sudo 特权、零广告的 macOS 菜单栏系统实时监控工具。
> A lightning-fast, sudo-free, ad-free macOS menu bar system monitor.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](#)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![RAM](https://img.shields.io/badge/RAM_Usage-~15MB-brightgreen.svg)](#)

<!-- 请在此处放置应用截图 (Please insert app screenshot here) -->
<!-- ![Pulse Screenshot](docs/screenshot.png) -->

---

## 🌟 特性 (Features)

- ⚡ **系统负载遥测 (System Load)**：优先展示 Apple SMC `PSTR` 整机主板功率 (W)。
- 🌡 **电池温度监控 (Battery Temp)**：优先展示 Apple SMC `TB0T` 电池包温度 (°C)。
- 📊 **真实内存压力 (Memory Pressure)**：根据 macOS 系统可用页面百分比展示内存紧张程度 (%)，而非简单的已用内存。
- 🖥 **CPU 使用率与频率 (CPU Usage & Freq)**：实时查看 CPU 负载 (%) 与运行主频 (GHz)。
- 🎨 **原生优雅 UI (Native UI)**：使用最新的 `NSPanel` 与系统级毛玻璃特效 (VisualEffectView) 打造无缝体验。
- 🚀 **开机自动启动 (Launch at Login)**：基于 macOS 13+ 最新 `SMAppService` API，一键无缝开启/关闭开机自启。
- 🔒 **免 Sudo 特权 (Sudo-Free)**：只读访问 `AppleSMC` 与 `AppleSmartBattery`，不写入硬件控制键，安全可靠。
- 🪶 **极致省空间与低内存 (Lightweight)**：采用 **2x2 上下双行微型文本**画风，仅占用 1 个菜单栏宽度；内存占用仅 **~15MB**，CPU 消耗极低。

---

## 🚦 智能动态状态 (Dynamic States)

为了让你在第一时间感知到系统异常，Pulse 的图标和颜色会根据实时数据自动变化：

- **⚡ 系统负载与电源 (Power)**
  - **充电中**：显示绿色闪电图标 `⚡`。
  - **已插电 (未充电/满电)**：显示插头图标 `🔌`。
  - **使用电池放电**：显示闪电图标 `⚡`，且图标和数值的颜色会随功耗变色：
    - 功耗 ≥ **18 W**：变为 🟠 橙色警告。
    - 功耗 ≥ **30 W**：变为 🔴 红色高危。
- **🌡 电池温度 (Temperature)**
  - ≥ **35 °C**：变为 🟠 橙色警告。
  - ≥ **40 °C**：变为 🔴 红色高危。
- **📊 内存压力 (Memory Pressure)**
  - 直接反映 macOS 系统底层的真实内存压力：🟢 绿色 (健康)、🟡 黄色 (警告)、🔴 红色 (危急)。
- **🖥 CPU 使用率 (CPU Usage)**
  - ≥ **60%**：变为 🟠 橙色警告。
  - ≥ **80%**：变为 🔴 红色高危。

---

## 🖥 界面概览 (UI Overview)

### 2x2 上下双行极致省空间排版 (Compact Menu Bar View)

```text
⚡ 5.3 W  📊 9 %
🌡 30.3 °C 🖥 38%
```
<img width="129" height="41" alt="image" src="https://github.com/user-attachments/assets/034e4075-4509-4d59-a5a6-cc001f4bef0a" />



### 原生详情面板 (Native Detail Panel)

点击菜单栏图标即可展开详情面板：

<img width="350" height="403" alt="image" src="https://github.com/user-attachments/assets/eef137fb-6912-4d77-803d-0f73c67a334b" />
<img width="348" height="603" alt="image" src="https://github.com/user-attachments/assets/a95084c1-2a61-441a-b27f-95c0b5b7bc73" />
<img width="351" height="598" alt="image" src="https://github.com/user-attachments/assets/55e9a825-1c16-4088-a272-42c47b765192" />


*详情面板支持点击外部自动隐藏、深色/浅色模式无缝切换。*

---

## 📦 安装 (Installation)

### 方式一：下载预编译包 (Download Release)
你可以直接在 [Releases](../../releases) 页面下载最新版本的 `Pulse_macOS.zip`。
解压后将 `Pulse.app` 拖入**应用程序 (Applications)** 文件夹即可。

### 方式二：本地编译 (Build from Source)
1. 克隆仓库：
   ```bash
   git clone https://github.com/lin-colin/Pulse.git
   cd Pulse
   ```
2. 运行一键构建脚本：
   ```bash
   ./build.sh
   ```
3. 打开构建好的应用：
   ```bash
   open build/Pulse.app
   ```
   *如果你需要自行打包分发，可以使用 `./release.sh` 脚本。*

---

## 🤝 参与贡献 (Contributing)

欢迎任何形式的贡献！请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解如何提交 Issue 或 Pull Request。
- **Bug 报告**：如果你发现了任何问题，请提交 Issue。
- **功能请求**：欢迎提出新的想法和建议。
- **代码贡献**：随时欢迎提交 PR，我们期待你的代码！

---

## 📄 开源协议 (License)

本项目基于 [MIT License](LICENSE) 协议开源。
