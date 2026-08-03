# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-03

### Added
- 首次发布 (Initial Release)
- ⚡ **系统负载监控**：读取 Apple SMC `PSTR` 获取整机功率。
- 🌡 **电池温度监控**：读取 Apple SMC `TB0T` 获取电池温度。
- 📊 **内存压力监控**：根据 macOS 内存页面状态计算真实的内存压力。
- 🖥 **CPU 使用率与频率监控**：实时查看 CPU 负载。
- 极致省空间的 2x2 菜单栏排版（双行微型文本），仅占用 1 个菜单栏宽度。
- 现代化的原生无边框面板 (NSPanel)，支持系统毛玻璃效果，完美取代旧版 NSPopover。
- 开机自动启动开关，基于 macOS 13+ 最新 `SMAppService` API。
- 自定义刷新间隔（1-10 秒）。
- 焦点管理优化：点击应用外部自动隐藏详情面板。
