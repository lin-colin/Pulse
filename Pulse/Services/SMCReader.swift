import Foundation
import IOKit

/// 同一轮 SMC 读取中的整机功率与电池温度。
struct SMCSnapshot {
    let systemPowerWatts: Double?
    let batteryTemperatureCelsius: Double?
}

/// 允许 HardwareMonitor 注入真实或测试 SMC 数据源。
protocol SMCReading {
    func readSnapshot() -> SMCSnapshot
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // C ABI 会在 UInt8 后保留 3 字节；显式声明可防止 Swift 复用尾部填充。
    var reserved: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
    var key: UInt32 = 0
    var version = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

/// 通过 AppleSMC 私有 IOKit 用户客户端只读传感器；不包含任何写命令。
final class SMCReader: SMCReading {
    private static let kernelMethodIndex: UInt32 = 2
    private static let readBytesCommand: UInt8 = 5
    private static let readKeyInfoCommand: UInt8 = 9

    /// 暴露只读 ABI 尺寸供回归测试使用，避免结构体字段调整破坏内核调用。
    static var abiKeyDataStride: Int {
        MemoryLayout<SMCKeyData>.stride
    }

    /// 暴露关键字段偏移供测试核对，单看总长度无法发现所有 ABI 回归。
    static var abiFieldOffsets: [String: Int] {
        [
            "pLimitData": MemoryLayout<SMCKeyData>.offset(of: \.pLimitData) ?? -1,
            "keyInfo": MemoryLayout<SMCKeyData>.offset(of: \.keyInfo) ?? -1,
            "result": MemoryLayout<SMCKeyData>.offset(of: \.result) ?? -1,
            "data8": MemoryLayout<SMCKeyData>.offset(of: \.data8) ?? -1,
            "data32": MemoryLayout<SMCKeyData>.offset(of: \.data32) ?? -1,
            "bytes": MemoryLayout<SMCKeyData>.offset(of: \.bytes) ?? -1
        ]
    }

    /// 同时检查 IOKit 传输、SMC 协议结果和完整 ABI 响应尺寸。
    static func isSuccessfulResponse(
        kernelResult: kern_return_t,
        protocolResult: UInt8,
        outputSize: Int
    ) -> Bool {
        kernelResult == KERN_SUCCESS
            && protocolResult == 0
            && outputSize == abiKeyDataStride
    }

    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var openedConnection: io_connect_t = IO_OBJECT_NULL
        guard IOServiceOpen(service, mach_task_self_, 0, &openedConnection) == KERN_SUCCESS else {
            return nil
        }
        connection = openedConnection
    }

    deinit {
        IOServiceClose(connection)
    }

    /// 连续读取 PSTR 与 TB0T；任一键失败不会阻断另一个键。
    func readSnapshot() -> SMCSnapshot {
        SMCSnapshot(
            systemPowerWatts: readValue(for: "PSTR"),
            batteryTemperatureCelsius: readValue(for: "TB0T")
        )
    }
}

private extension SMCReader {
    /// 查询键元数据后读取载荷，并交给纯解码器处理具体数值类型。
    func readValue(for key: String) -> Double? {
        guard let keyCode = keyCode(for: key),
              let value = readKey(keyCode) else {
            return nil
        }

        let bytes = withUnsafeBytes(of: value.bytes) {
            Array($0.prefix(Int(value.keyInfo.dataSize)))
        }
        return SMCValueDecoder.decode(
            dataType: value.keyInfo.dataType,
            bytes: bytes
        )
    }

    /// AppleSMC 读取需要先查键类型，再使用相同键读取字节。
    func readKey(_ key: UInt32) -> SMCKeyData? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key
        input.data8 = Self.readKeyInfoCommand

        let keyInfoCall = call(input: &input, output: &output)
        guard Self.isSuccessfulResponse(
            kernelResult: keyInfoCall.kernelResult,
            protocolResult: output.result,
            outputSize: keyInfoCall.outputSize
        ) else {
            return nil
        }

        let keyInfo = output.keyInfo
        guard (1...MemoryLayout<SMCBytes>.size).contains(Int(keyInfo.dataSize)) else {
            return nil
        }
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = Self.readBytesCommand
        output = SMCKeyData()
        let bytesCall = call(input: &input, output: &output)
        guard Self.isSuccessfulResponse(
            kernelResult: bytesCall.kernelResult,
            protocolResult: output.result,
            outputSize: bytesCall.outputSize
        ) else {
            return nil
        }

        // 字节读取响应不会重复返回键类型，保留第一次查询的元数据。
        output.keyInfo = keyInfo
        return output
    }

    /// 调用 AppleSMC 的只读用户客户端方法；选择器固定为 2。
    func call(
        input: inout SMCKeyData,
        output: inout SMCKeyData
    ) -> (kernelResult: kern_return_t, outputSize: Int) {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let kernelResult = IOConnectCallStructMethod(
            connection,
            Self.kernelMethodIndex,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
        return (kernelResult, outputSize)
    }

    /// 仅接受恰好四个 UTF-8 字节的 SMC 键。
    func keyCode(for key: String) -> UInt32? {
        let code = SMCValueDecoder.fourCharacterCode(key)
        return code == 0 ? nil : code
    }
}
