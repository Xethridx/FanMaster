import Foundation

// MARK: - Data Type Conversions

extension [UInt8] {
    /// Interpret bytes as a big-endian float (sp78 format used by SMC for temperatures)
    public var sp78Value: Double {
        guard count >= 2 else { return 0 }
        let rawValue = Int16(bitPattern: (UInt16(self[0]) << 8) | UInt16(self[1]))
        return Double(rawValue) / 256.0
    }
    
    /// Interpret bytes as fpe2 format (14-bit integer, 2-bit fraction used by AppleSMC for fan RPM)
    public var fpeValue: Double {
        guard count >= 2 else { return 0 }
        let raw = (UInt16(self[0]) << 8) | UInt16(self[1])
        return Double(raw >> 2) + Double(raw & 0x03) * 0.25
    }
    
    /// Interpret as standard big-endian UInt16
    public var uint16Value: UInt16 {
        guard count >= 2 else { return 0 }
        return (UInt16(self[0]) << 8) | UInt16(self[1])
    }
    
    /// Interpret as standard big-endian UInt32
    public var uint32Value: UInt32 {
        guard count >= 4 else { return 0 }
        return (UInt32(self[0]) << 24) | (UInt32(self[1]) << 16) | (UInt32(self[2]) << 8) | UInt32(self[3])
    }
}

/// Encode a Double into FPE2 format (2-byte big endian fixed point: 14-bit integer, 2-bit fraction)
public func encodeFPE2(_ value: Double) -> [UInt8] {
    let raw = UInt16(max(0, min(65535, round(value * 4.0))))
    return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
}

// MARK: - Sensor Models

public struct TemperatureSensor: Identifiable, Codable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    public var currentTemp: Double
    
    public init(key: String, name: String, currentTemp: Double = 0) {
        self.key = key
        self.name = name
        self.currentTemp = currentTemp
    }
}

public struct FanSensor: Identifiable, Codable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let name: String
    public var currentRPM: Double
    public var minimumRPM: Double
    public var maximumRPM: Double
    public var targetRPM: Double
    
    public init(index: Int, name: String, currentRPM: Double = 0,
                minimumRPM: Double = 1200, maximumRPM: Double = 5500,
                targetRPM: Double = 1200) {
        self.index = index
        self.name = name
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
    }
}

// MARK: - Fan Curve

public struct CurvePoint: Codable, Sendable {
    public var temperature: Double  // °C
    public var fanSpeed: Double     // RPM
    
    public init(temperature: Double, fanSpeed: Double) {
        self.temperature = temperature
        self.fanSpeed = fanSpeed
    }
}

public struct FanProfile: Identifiable, Codable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var sensorKey: String
    public var curvePoints: [CurvePoint]
    public var isAutomatic: Bool
    
    public init(id: String = UUID().uuidString, name: String, emoji: String,
                sensorKey: String, curvePoints: [CurvePoint], isAutomatic: Bool = true) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.sensorKey = sensorKey
        self.curvePoints = curvePoints
        self.isAutomatic = isAutomatic
    }
    
    /// Compute target RPM for a given temperature using linear interpolation between curve points
    public func targetRPM(for temperature: Double) -> Double {
        let sorted = curvePoints.sorted { $0.temperature < $1.temperature }
        guard !sorted.isEmpty else { return 1200 }
        
        if temperature <= sorted.first!.temperature { return sorted.first!.fanSpeed }
        if temperature >= sorted.last!.temperature  { return sorted.last!.fanSpeed  }
        
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i]
            let hi = sorted[i + 1]
            if temperature >= lo.temperature && temperature <= hi.temperature {
                let t = (temperature - lo.temperature) / (hi.temperature - lo.temperature)
                return lo.fanSpeed + t * (hi.fanSpeed - lo.fanSpeed)
            }
        }
        return sorted.last!.fanSpeed
    }
    
    // MARK: - Built-in profiles
    
    public static var silent: FanProfile {
        FanProfile(
            id: "silent",
            name: "Silencioso",
            emoji: "🤫",
            sensorKey: "TC0D",
            curvePoints: [
                CurvePoint(temperature: 45, fanSpeed: 1200),
                CurvePoint(temperature: 65, fanSpeed: 2000),
                CurvePoint(temperature: 80, fanSpeed: 3500),
                CurvePoint(temperature: 90, fanSpeed: 5500),
            ]
        )
    }
    
    public static var balanced: FanProfile {
        FanProfile(
            id: "balanced",
            name: "Balanceado",
            emoji: "⚖️",
            sensorKey: "TC0D",
            curvePoints: [
                CurvePoint(temperature: 40, fanSpeed: 1500),
                CurvePoint(temperature: 55, fanSpeed: 2500),
                CurvePoint(temperature: 70, fanSpeed: 3800),
                CurvePoint(temperature: 85, fanSpeed: 5500),
            ]
        )
    }
    
    public static var performance: FanProfile {
        FanProfile(
            id: "performance",
            name: "Rendimiento",
            emoji: "🚀",
            sensorKey: "TC0D",
            curvePoints: [
                CurvePoint(temperature: 35, fanSpeed: 2000),
                CurvePoint(temperature: 50, fanSpeed: 3000),
                CurvePoint(temperature: 65, fanSpeed: 4500),
                CurvePoint(temperature: 75, fanSpeed: 5500),
            ]
        )
    }
    
    public static var max: FanProfile {
        FanProfile(
            id: "max",
            name: "Máximo",
            emoji: "🌪️",
            sensorKey: "TC0D",
            curvePoints: [
                CurvePoint(temperature: 0, fanSpeed: 5500),
                CurvePoint(temperature: 100, fanSpeed: 5500),
            ]
        )
    }
}
