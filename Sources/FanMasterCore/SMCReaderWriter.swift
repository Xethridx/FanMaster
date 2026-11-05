import Foundation

import Foundation

// MARK: - Known SMC Keys (Catálogo Extendido ~80 Claves Intel)

/// Temperature sensor keys covering Intel Macs (Mac mini, MacBook Air/Pro, iMac, Mac Pro)
public let knownTemperatureKeys: [(key: String, name: String)] = [
    // CPU Cores & Die
    ("TC0D", "CPU Die"),
    ("TC0E", "CPU Die Virtual 1"),
    ("TC0F", "CPU Die Virtual 2"),
    ("TC0P", "CPU Proximity"),
    ("TC0H", "CPU Heatsink"),
    ("TC0C", "CPU Core 0"),
    ("TC1C", "CPU Core 1"),
    ("TC2C", "CPU Core 2"),
    ("TC3C", "CPU Core 3"),
    ("TC4C", "CPU Core 4"),
    ("TC5C", "CPU Core 5"),
    ("TC6C", "CPU Core 6"),
    ("TC7C", "CPU Core 7"),
    ("TC8C", "CPU Core 8"),
    ("TC9C", "CPU Core 9"),
    ("TCAD", "CPU Core A"),
    ("TCBD", "CPU Core B"),
    ("TCCD", "CPU Core C"),
    ("TCDD", "CPU Core D"),
    ("TCPC", "CPU Package"),
    ("TCSA", "CPU System Agent"),
    ("TCTD", "CPU Die Temp"),
    ("TCAH", "CPU Heatsink A"),
    ("TCBH", "CPU Heatsink B"),
    
    // GPU (Integrated & Discrete)
    ("TG0D", "GPU Die"),
    ("TG1D", "GPU 2 Die (Discreta)"),
    ("TG0P", "GPU Proximity"),
    ("TG1P", "GPU 2 Proximity"),
    ("TG0H", "GPU Heatsink"),
    ("TG1H", "GPU 2 Heatsink"),
    ("TCGC", "Intel HD Graphics"),
    ("TGDD", "GPU Die Digital"),
    ("TGVP", "GPU VRAM Proximity"),
    ("TG0M", "GPU Memory"),
    ("TG1M", "GPU 2 Memory"),
    
    // PCH, Chipset & Thunderbolt
    ("TP0P", "PCH Proximity"),
    ("TPCD", "PCH Die"),
    ("TP0D", "PCH Die Temp"),
    ("TI0P", "Thunderbolt 1 Proximity"),
    ("TI1P", "Thunderbolt 2 Proximity"),
    ("TI2P", "Thunderbolt 3 Proximity"),
    ("TI3P", "Thunderbolt 4 Proximity"),
    ("TN0D", "Northbridge Die"),
    ("TN0P", "Northbridge Proximity"),
    ("TN0H", "Northbridge Heatsink"),
    ("Ts0P", "Platform Controller"),
    ("Ts0S", "Platform Controller Sensor"),
    
    // Memory (RAM)
    ("TM0P", "Memory Bank A"),
    ("TM1P", "Memory Bank B"),
    ("TM2P", "Memory Bank C"),
    ("TM3P", "Memory Bank D"),
    ("TM0S", "Memory Slot 1"),
    ("TM1S", "Memory Slot 2"),
    ("TM2S", "Memory Slot 3"),
    ("TM3S", "Memory Slot 4"),
    ("TM4S", "Memory Slot 5"),
    ("TM5S", "Memory Slot 6"),
    ("TM6S", "Memory Slot 7"),
    ("TM7S", "Memory Slot 8"),
    ("TMA1", "Memory Module A1"),
    ("TMA2", "Memory Module A2"),
    ("TMB1", "Memory Module B1"),
    ("TMB2", "Memory Module B2"),
    
    // Ambient, Battery, Enclosure & Heatsinks
    ("TA0P", "Ambient Air Proximity"),
    ("TA1P", "Ambient Air Proximity 2"),
    ("TW0P", "Airport / Wi-Fi"),
    ("TB0T", "Battery TS_MAX"),
    ("TB1T", "Battery Cell 1"),
    ("TB2T", "Battery Cell 2"),
    ("TB3T", "Battery Cell 3"),
    ("TL0P", "LCD Panel Proximity"),
    ("Tm0P", "Mainboard Proximity"),
    ("Th1H", "Heatsink 1"),
    ("Th2H", "Heatsink 2"),
    ("Th3H", "Heatsink 3"),
    ("THSP", "Heatsink Proximity"),
    ("Tp0C", "Fuente de Alimentación"),
    ("Te0t", "Ranura PCIe Ambient"),
]

// MARK: - SMC Reader

public class SMCReader {
    private let smc: SMCConnection
    private let hidReader = HIDThermalReader()
    
    public init(smc: SMCConnection) {
        self.smc = smc
    }
    
    // MARK: - Temperature
    
    /// Read temperature from a specific SMC key
    public func rawSMCTemperature(for key: String) -> Double? {
        let fcc = FourCharCode(key)
        guard let bytes = try? smc.readKey(fcc), bytes.count >= 2 else { return nil }
        let temp = bytes.sp78Value
        // Sanity check: valid temperature range (5°C to 125°C)
        guard temp > 5.0 && temp < 125.0 else { return nil }
        return temp
    }
    
    /// Read temperature with smart resolution and fallback support
    public func temperature(for key: String) -> Double? {
        let allSensors = readAllTemperatures()
        guard !allSensors.isEmpty else { return nil }
        
        // 1. Si se solicita "MAX", retornar la temperatura máxima
        if key == "MAX" {
            return allSensors.filter { $0.key != "TC0G" }.map(\.currentTemp).max()
        }
        
        // 2. Coincidencia directa por clave
        if let direct = allSensors.first(where: { $0.key == key }) {
            return direct.currentTemp
        }
        
        // 3. Fallback inteligente: buscar el sensor principal de CPU/SoC
        let cpuFallbacks = ["TC0D", "TC0P", "TC0E", "TC0C", "TCAD", "TC0H"]
        for fb in cpuFallbacks {
            if let found = allSensors.first(where: { $0.key == fb }) {
                return found.currentTemp
            }
        }
        
        // 4. Si es Apple Silicon, buscar pCore, eCore o SoC
        if let appleSiliconCPU = allSensors.first(where: {
            let k = $0.key.lowercased()
            return k.contains("pcore") || k.contains("ecore") || k.contains("soc")
        }) {
            return appleSiliconCPU.currentTemp
        }
        
        // 5. Último recurso: primer sensor disponible
        return allSensors.first?.currentTemp
    }
    
    /// Discover and read all available temperature sensors (AppleSMC + Apple Silicon IOHID)
    public func readAllTemperatures() -> [TemperatureSensor] {
        var sensors: [TemperatureSensor] = []
        var seenKeys = Set<String>()
        
        // 1. Leer sensores estándar Intel / AppleSMC
        for entry in knownTemperatureKeys {
            if let temp = rawSMCTemperature(for: entry.key) {
                sensors.append(TemperatureSensor(key: entry.key, name: entry.name, currentTemp: temp))
                seenKeys.insert(entry.key)
            }
        }
        
        // 2. Leer sensores Apple Silicon IOHID (M1/M2/M3/M4)
        let hidSensors = hidReader.readTemperatures()
        for hid in hidSensors {
            if !seenKeys.contains(hid.key) {
                sensors.append(hid)
                seenKeys.insert(hid.key)
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
