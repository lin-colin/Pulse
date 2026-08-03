import Foundation

/// 只负责把 Apple SMC 原始载荷解码为数值，不访问硬件或选择数据源。
enum SMCValueDecoder {
    static let floatDataType = fourCharacterCode("flt ")
    static let sp78DataType = fourCharacterCode("sp78")

    /// 解码功率使用的原生小端 Float，或温度使用的大端 signed 7.8 定点数。
    static func decode(dataType: UInt32, bytes: [UInt8]) -> Double? {
        switch dataType {
        case floatDataType:
            guard bytes.count == 4 else { return nil }
            let bits = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))

        case sp78DataType:
            guard bytes.count == 2 else { return nil }
            let bits = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: bits)) / 256.0

        default:
            return nil
        }
    }

    /// 将四字符 SMC 类型编码成内核接口使用的 UInt32。
    static func fourCharacterCode(_ string: String) -> UInt32 {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { return 0 }
        return (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])
    }
}
