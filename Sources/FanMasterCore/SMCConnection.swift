import Foundation
import IOKit

// MARK: - SMC Data Types

public struct FourCharCode {
    public let rawValue: UInt32
    
    public init(_ string: String) {
        var code: UInt32 = 0
        for char in string.unicodeScalars {
            code = (code << 8) | char.value
        }
        self.rawValue = code
    }
    
    public var string: String {
        var result = ""
        for shift in stride(from: 24, through: 0, by: -8) {
            let byte = UInt8((rawValue >> shift) & 0xFF)
            if byte != 0 {
                result.append(Character(UnicodeScalar(byte)))
            }
        }
        return result
    }
}

// MARK: - SMC Data Structures (mirrors C structs used by AppleSMC)

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCKeyData {
    struct Vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    
    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    var key: UInt32 = 0
    var vers = Vers()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
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

// MARK: - SMC Connection

public enum SMCError: Error, LocalizedError {
    case failedToOpen
    case failedToConnect
    case keyNotFound(String)
    case writeError(String)
    case permissionDenied
    case unknownDataType(String)
    
    public var errorDescription: String? {
        switch self {
        case .failedToOpen: return "Failed to open AppleSMC service"
        case .failedToConnect: return "Failed to connect to AppleSMC"
        case .keyNotFound(let k): return "SMC key not found: \(k)"
        case .writeError(let msg): return "SMC write error: \(msg)"
        case .permissionDenied: return "Permission denied — run with sudo to control fans"
        case .unknownDataType(let t): return "Unknown data type: \(t)"
        }
    }
}

// SMC user client type
private let kSMCUserClientOpen: UInt32  = 0
private let kSMCUserClientClose: UInt32 = 1
private let kSMCHandleYPCEvent: UInt32  = 2
private let kSMCReadKey: UInt8   = 5
private let kSMCWriteKey: UInt8  = 6
private let kSMCGetKeyCount: UInt8 = 7
private let kSMCGetKeyFromIndex: UInt8 = 8
private let kSMCGetKeyInfo: UInt8  = 9

public class SMCConnection {
    private var connection: io_connect_t = 0
    
    public init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != IO_OBJECT_NULL else {
            throw SMCError.failedToOpen
        }
        defer { IOObjectRelease(service) }
        
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else {
            throw SMCError.failedToConnect
        }
    }
    
    deinit {
        IOServiceClose(connection)
    }
    
    // MARK: - Low Level Read/Write
    
    private func callSMC(_ inputStruct: inout SMCKeyData) throws -> SMCKeyData {
        var outputStruct = SMCKeyData()
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        
        let result = withUnsafeMutablePointer(to: &inputStruct) { inputPtr in
            withUnsafeMutablePointer(to: &outputStruct) { outputPtr in
                IOConnectCallStructMethod(
                    connection,
                    UInt32(kSMCHandleYPCEvent),
                    inputPtr,
                    inputSize,
                    outputPtr,
                    &outputSize
                )
            }
        }
        
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPrivileged {
                throw SMCError.permissionDenied
            }
            throw SMCError.writeError("IOKit result: \(result)")
        }
        return outputStruct
    }
    
    private func getKeyInfo(_ key: FourCharCode) throws -> SMCKeyData.KeyInfo {
        var input = SMCKeyData()
        input.key = key.rawValue
        input.data8 = kSMCGetKeyInfo
        let output = try callSMC(&input)
        return output.keyInfo
    }
    
    public func readKey(_ key: FourCharCode) throws -> [UInt8] {
        let keyInfo = try getKeyInfo(key)
        
        var input = SMCKeyData()
        input.key = key.rawValue
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = kSMCReadKey
        
        let output = try callSMC(&input)
        
        var bytes = [UInt8](repeating: 0, count: Int(keyInfo.dataSize))
        let mirror = Mirror(reflecting: output.bytes)
        for (i, child) in mirror.children.enumerated() {
            if i < bytes.count {
                bytes[i] = child.value as! UInt8
            }
        }
        return bytes
    }
    
    public func writeKey(_ key: FourCharCode, bytes: [UInt8]) throws {
        let keyInfo = try getKeyInfo(key)
        
        var input = SMCKeyData()
        input.key = key.rawValue
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = kSMCWriteKey
        
        // Copy bytes into the SMCKeyData bytes tuple
        var byteArray = [UInt8](repeating: 0, count: 32)
        for (i, b) in bytes.prefix(32).enumerated() {
            byteArray[i] = b
        }
        input.bytes = (
            byteArray[0],  byteArray[1],  byteArray[2],  byteArray[3],
            byteArray[4],  byteArray[5],  byteArray[6],  byteArray[7],
            byteArray[8],  byteArray[9],  byteArray[10], byteArray[11],
            byteArray[12], byteArray[13], byteArray[14], byteArray[15],
            byteArray[16], byteArray[17], byteArray[18], byteArray[19],
            byteArray[20], byteArray[21], byteArray[22], byteArray[23],
            byteArray[24], byteArray[25], byteArray[26], byteArray[27],
            byteArray[28], byteArray[29], byteArray[30], byteArray[31]
        )
        
        _ = try callSMC(&input)
    }
    
    // MARK: - Key Count & Discovery
    
    public func keyCount() throws -> Int {
        var input = SMCKeyData()
        input.data8 = kSMCGetKeyCount
        let output = try callSMC(&input)
        return Int(output.data32)
    }
    
    public func keyAtIndex(_ index: Int) throws -> String {
        var input = SMCKeyData()
        input.data8 = kSMCGetKeyFromIndex
        input.data32 = UInt32(index)
        let output = try callSMC(&input)
        let code = FourCharCode(rawValue: output.key)
        return code.string
    }
}

// MARK: - FourCharCode from raw UInt32

extension FourCharCode {
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
