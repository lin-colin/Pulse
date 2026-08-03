import Foundation

/// 同一刷新时刻的完整展示数据，确保菜单栏与详情面板不会混用不同时刻的值。
struct PulseSnapshot {
    let power: Double?
    let memory: MemorySnapshot
    let temperature: Double?
    let cpuUsage: Double
    let cpuFrequency: Double
    let powerSource: PowerSourceSnapshot
}
