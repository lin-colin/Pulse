/// 定义内核内存压力的离散状态，避免将可用内存比例误当成压力指标。
enum MemoryPressureLevel: Equatable {
    case normal
    case warning
    case critical
    case unavailable

    /// 仅接受已知的内核枚举值，以免协议变更或读数缺失被误展示为正常。
    init(rawKernelValue: Int32?) {
        switch rawKernelValue {
        case 1:
            self = .normal
        case 2:
            self = .warning
        case 4:
            self = .critical
        default:
            self = .unavailable
        }
    }

    /// 为中文界面提供稳定文案，使采集层不需要携带展示文字。
    var displayName: String {
        switch self {
        case .normal:
            return "正常"
        case .warning:
            return "警告"
        case .critical:
            return "严重"
        case .unavailable:
            return "不可用"
        }
    }

    /// 将业务状态映射为展示语义，避免 UI 根据使用率自行猜测压力颜色。
    var presentationRole: MemoryPresentationRole {
        switch self {
        case .normal:
            return .healthy
        case .warning:
            return .warning
        case .critical:
            return .critical
        case .unavailable:
            return .unavailable
        }
    }
}

/// 定义内存状态的展示语义，使不同界面能一致处理健康、告警和不可用状态。
enum MemoryPresentationRole: Equatable {
    case healthy
    case warning
    case critical
    case unavailable
}

/// 保存计算使用率所需的原始页统计，保持采集数据与派生指标可区分。
struct MemoryPageStatistics: Equatable {
    /// 总内存以字节保存，避免在计算前损失系统报告的精度。
    let totalBytes: UInt64
    /// 页大小以字节保存，因为页计数必须先转换为可比较的字节数。
    let pageSize: UInt64
    /// 空闲页计数用于计算可立即分配的内存。
    let freePages: UInt64
    /// 文件缓存页可被回收，因此需与空闲页共同视为可用内存。
    let externalPages: UInt64
}

/// 汇总真实内存使用率和独立压力状态，防止两种不同概念混为一个百分比。
struct MemorySnapshot: Equatable {
    /// 使用字节数可缺失，以诚实表达页统计未取得或无效的情况。
    let usedBytes: UInt64?
    /// 总字节数只在总容量本身无效时缺失，避免丢失仍可信的硬件容量读数。
    let totalBytes: UInt64?
    /// 使用率可缺失，并且只在可信页统计存在时计算。
    let usagePercentage: Double?
    /// 压力状态始终单独保留，即使使用率不可计算也不能丢失告警信息。
    let pressureLevel: MemoryPressureLevel
}
