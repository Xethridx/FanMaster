import Foundation

// MARK: - Known SMC Keys

/// Temperature sensor keys for Mac mini 2012 (Intel Core i5/i7)
public let knownTemperatureKeys: [(key: String, name: String)] = [
    ("TC0D", "CPU Die"),
    ("TC0E", "CPU Die 2"),
    ("TC0F", "CPU Die 3"),
    ("TC0H", "CPU PECI"),
    ("TC0P", "CPU Proximity"),
    ("TCAD", "CPU Core A"),
    ("TCBD", "CPU Core B"),
    ("TGDD", "GPU Die"),
    ("TG0D", "GPU Die 2"),
    ("TG0P", "GPU Proximity"),
    ("THSP", "Heatsink Proximity"),
    ("TM0P", "Memory Bank A"),
    ("TM1P", "Memory Bank B"),
    ("Th1H", "Heatsink 1"),
    ("Th2H", "Heatsink 2"),
    ("TP0P", "PCH Proximity"),
    ("TPCD", "PCH Die"),
    ("TW0P", "Airport Proximity"),
    ("Tm0P", "Mainboard Proximity"),
    ("Ts0P", "Platform Controller"),
]

// MARK: - SMC Reader

public class SMCReader {
    private let smc: SMCConnection
    
    public init(smc: SMCConnection) {
        self.smc = smc
    }
    
    // MARK: - Temperature
    
    /// Read temperature from a specific key
    public func temperature(for key: String) -> Double? {
        let fcc = FourCharCode(key)
        guard let bytes = try? smc.readKey(fcc), bytes.count >= 2 else { return nil }
        let temp = bytes.sp78Value
        // Sanity check: valid temperature range
        guard temp > 0 && temp < 125 else { return nil }
        return temp
    }
    
    /// Discover and read all available temperature sensors
    public func readAllTemperatures() -> [TemperatureSensor] {
        var sensors: [TemperatureSensor] = []
        for entry in knownTemperatureKeys {
            if let temp = temperature(for: entry.key) {
                sensors.append(TemperatureSensor(key: entry.key, name: entry.name, currentTemp: temp))
            }
        }
        return sensors.sorted { $0.name < $1.name }
    }
    
    // MARK: - Fan
    
    /// Read number of fans
    public func fanCount() -> Int {
        guard let bytes = try? smc.readKey(FourCharCode("FNum")), !bytes.isEmpty else { return 0 }
        return Int(bytes[0])
    }
    
    /// Read current RPM for a fan
    public func fanCurrentRPM(_ index: Int) -> Double {
        let key = FourCharCode("F\(index)Ac")
        guard let bytes = try? smc.readKey(key) else { return 0 }
        return bytes.fpeValue
    }
    
    /// Read minimum RPM for a fan
    public func fanMinRPM(_ index: Int) -> Double {
        let key = FourCharCode("F\(index)Mn")
        guard let bytes = try? smc.readKey(key) else { return 1200 }
        return bytes.fpeValue
    }
    
    /// Read maximum RPM for a fan
    public func fanMaxRPM(_ index: Int) -> Double {
        let key = FourCharCode("F\(index)Mx")
        guard let bytes = try? smc.readKey(key) else { return 5500 }
        return bytes.fpeValue
    }
    
    /// Read target RPM for a fan
    public func fanTargetRPM(_ index: Int) -> Double {
        let key = FourCharCode("F\(index)Tg")
        guard let bytes = try? smc.readKey(key) else { return 0 }
        return bytes.fpeValue
    }
    
    /// Read all fans
    public func readAllFans() -> [FanSensor] {
        let count = fanCount()
        var fans: [FanSensor] = []
        for i in 0..<count {
            let fanName: String
            if count == 1 {
                fanName = "Ventilador Principal"
            } else if count == 2 {
                fanName = (i == 0) ? "Ventilador Izquierdo (CPU)" : "Ventilador Derecho (GPU)"
            } else {
                if i == 0 {
                    fanName = "Ventilador 1 (CPU)"
                } else if i == 1 {
                    fanName = "Ventilador 2 (GPU)"
                } else {
                    fanName = "Ventilador \(i + 1)"
                }
            }
            
            let fan = FanSensor(
                index: i,
                name: fanName,
                currentRPM: fanCurrentRPM(i),
                minimumRPM: fanMinRPM(i),
                maximumRPM: fanMaxRPM(i),
                targetRPM: fanTargetRPM(i)
            )
            fans.append(fan)
        }
        return fans
    }
    
    // MARK: - CPU Load
    
    /// Returns approximate CPU usage (0.0 – 1.0) using host_statistics
    public func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0.0 }
        
        let userTicks   = Double(info.cpu_ticks.0)
        let systemTicks = Double(info.cpu_ticks.1)
        let idleTicks   = Double(info.cpu_ticks.2)
        let niceTicks   = Double(info.cpu_ticks.3)
        
        let totalTicks = userTicks + systemTicks + idleTicks + niceTicks
        guard totalTicks > 0 else { return 0.0 }
        
        return (userTicks + systemTicks + niceTicks) / totalTicks
    }
}

// MARK: - SMC Writer

public class SMCWriter {
    private let smc: SMCConnection
    
    public init(smc: SMCConnection) {
        self.smc = smc
    }
    
    /// Set fan minimum speed (requires root)
    public func setFanMinRPM(_ index: Int, rpm: Double) throws {
        let key = FourCharCode("F\(index)Mn")
        let bytes = encodeFPE2(rpm)
        try smc.writeKey(key, bytes: bytes)
    }
    
    /// Set fan target speed (requires root)
    public func setFanTargetRPM(_ index: Int, rpm: Double) throws {
        let key = FourCharCode("F\(index)Tg")
        let bytes = encodeFPE2(rpm)
        try smc.writeKey(key, bytes: bytes)
    }
    
    /// Force manual fan control mode
    public func setFanManualControl(_ index: Int, enabled: Bool) throws {
        let key = FourCharCode("FS! ")
        // Read current bitmask
        if let current = try? smc.readKey(key) {
            var mask = current.uint16Value
            if enabled {
                mask |= (1 << index)
            } else {
                mask &= ~(1 << index)
            }
            let bytes = [UInt8(mask >> 8), UInt8(mask & 0xFF)]
            try smc.writeKey(key, bytes: bytes)
        }
    }
    
    /// Restore automatic fan control for all fans
    public func restoreAutoControl() throws {
        let key = FourCharCode("FS! ")
        try smc.writeKey(key, bytes: [0x00, 0x00])
    }
}
