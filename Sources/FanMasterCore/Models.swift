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
    public var fanSpeed: Double     // Potencia en % (0–100) o RPM legado (>100)
    
    public init(temperature: Double, fanSpeed: Double) {
        self.temperature = temperature
        self.fanSpeed = fanSpeed
    }
    
    /// Normaliza el valor a un porcentaje relativo de 0% a 100%
    public var percentage: Double {
        if fanSpeed <= 100.0 {
            return max(0.0, min(100.0, fanSpeed))
        }
        // Retrocompatibilidad: Si viene como RPM absoluto legado (ej. 1,800 - 5,500 RPM)
        let normalized = ((fanSpeed - 1800.0) / (5500.0 - 1800.0)) * 100.0
        return max(0.0, min(100.0, normalized))
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
    
    /// Calcula el porcentaje de potencia relativo (0% - 100%) para una temperatura dada
    public func targetPercentage(for temperature: Double) -> Double {
        let sorted = curvePoints.sorted { $0.temperature < $1.temperature }
        guard !sorted.isEmpty else { return 0.0 }
        
        if temperature <= sorted.first!.temperature { return sorted.first!.percentage }
        if temperature >= sorted.last!.temperature  { return sorted.last!.percentage  }
        
        for i in 0..<(sorted.count - 1) {
            let lo = sorted[i]
            let hi = sorted[i + 1]
            if temperature >= lo.temperature && temperature <= hi.temperature {
                guard hi.temperature > lo.temperature else { return lo.percentage }
                let t = (temperature - lo.temperature) / (hi.temperature - lo.temperature)
                return lo.percentage + t * (hi.percentage - lo.percentage)
            }
        }
        return sorted.last!.percentage
    }
    
    /// Calcula el RPM objetivo para una temperatura adaptándose a los límites físicos del ventilador
    public func targetRPM(for temperature: Double, minRPM: Double, maxRPM: Double) -> Double {
        let pct = targetPercentage(for: temperature)
        let target = minRPM + (maxRPM - minRPM) * (pct / 100.0)
        return Swift.max(minRPM, Swift.min(maxRPM, target))
    }
    
    /// Sobrecarga retrocompatible con límites por defecto (1200 - 5500 RPM)
    public func targetRPM(for temperature: Double) -> Double {
        targetRPM(for: temperature, minRPM: 1200, maxRPM: 5500)
    }
    
    // MARK: - Built-in profiles (Relativos en % de potencia)
    
    public static var silent: FanProfile {
        FanProfile(
            id: "silent",
            name: "Silencioso",
            emoji: "🤫",
            sensorKey: "TC0D",
            curvePoints: [
                CurvePoint(temperature: 45, fanSpeed: 0),     // minRPM (0%)
                CurvePoint(temperature: 65, fanSpeed: 18),    // 18%
                CurvePoint(temperature: 80, fanSpeed: 50),    // 50%
                CurvePoint(temperature: 90, fanSpeed: 100),   // maxRPM (100%)
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
                CurvePoint(temperature: 40, fanSpeed: 5),     // 5%
                CurvePoint(temperature: 55, fanSpeed: 25),    // 25%
                CurvePoint(temperature: 70, fanSpeed: 60),    // 60%
                CurvePoint(temperature: 85, fanSpeed: 100),   // 100%
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
                CurvePoint(temperature: 35, fanSpeed: 20),    // 20%
                CurvePoint(temperature: 50, fanSpeed: 45),    // 45%
                CurvePoint(temperature: 65, fanSpeed: 75),    // 75%
                CurvePoint(temperature: 75, fanSpeed: 100),   // 100%
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
                CurvePoint(temperature: 0, fanSpeed: 100),
                CurvePoint(temperature: 100, fanSpeed: 100),
            ]
        )
    }
}
