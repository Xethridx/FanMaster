import Foundation

// MARK: - Hardware & System Information

public struct SystemHardwareInfo: Codable, Sendable {
    public let modelIdentifier: String
    public let modelName: String
    public let processor: String
    public let architecture: String
    public let osVersion: String
    
    public init(
        modelIdentifier: String = SystemInfo.modelIdentifier,
        modelName: String = SystemInfo.marketingModelName,
        processor: String = SystemInfo.cpuBrand,
        architecture: String = SystemInfo.architecture,
        osVersion: String = SystemInfo.osVersion
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.processor = processor
        self.architecture = architecture
        self.osVersion = osVersion
    }
}

public enum SystemInfo {
    
    /// Reads hardware model identifier via sysctl (e.g. "Macmini6,2", "MacBookPro16,1", "Mac14,2")
    public static var modelIdentifier: String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Reads processor brand string via sysctl
    public static var cpuBrand: String {
        var size: Int = 0
        if sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0 && size > 0 {
            var brand = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
            let s = String(cString: brand).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel Core"
        #endif
    }
    
    /// Host CPU architecture
    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    
    /// macOS operating system version string
    public static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    
    /// Human-friendly marketing model name
    public static var marketingModelName: String {
        let id = modelIdentifier
        if let name = modelDatabase[id] {
            return name
        }
        
        // Intelligent fallback parser for unknown/future models
        if id.hasPrefix("MacBookAir") {
            return "MacBook Air (\(id))"
        } else if id.hasPrefix("MacBookPro") {
            return "MacBook Pro (\(id))"
        } else if id.hasPrefix("MacBook") {
            return "MacBook (\(id))"
        } else if id.hasPrefix("Macmini") {
            return "Mac mini (\(id))"
        } else if id.hasPrefix("iMacPro") {
            return "iMac Pro (\(id))"
        } else if id.hasPrefix("iMac") {
            return "iMac (\(id))"
        } else if id.hasPrefix("MacPro") {
            return "Mac Pro (\(id))"
        } else if id.hasPrefix("MacStudio") {
            return "Mac Studio (\(id))"
        } else if id.hasPrefix("Mac") {
            return "Mac (\(id))"
        }
        return id
    }
    
    // Comprehensive dictionary mapping technical model IDs to commercial names
    private static let modelDatabase: [String: String] = [
        // Mac mini (Intel & Apple Silicon)
        "Macmini4,1": "Mac mini (Mid 2010)",
        "Macmini5,1": "Mac mini (Mid 2011)",
        "Macmini5,2": "Mac mini (Mid 2011)",
        "Macmini5,3": "Mac mini Server (Mid 2011)",
        "Macmini6,1": "Mac mini (Late 2012)",
        "Macmini6,2": "Mac mini (Late 2012)",
        "Macmini7,1": "Mac mini (Late 2014)",
        "Macmini8,1": "Mac mini (2018)",
        "Macmini9,1": "Mac mini (M1, 2020)",
        "Mac14,3":   "Mac mini (M2, 2023)",
        "Mac14,12":  "Mac mini (M2 Pro, 2023)",
        "Mac16,10":  "Mac mini (M4, 2024)",
        "Mac16,11":  "Mac mini (M4 Pro, 2024)",
        
        // MacBook Air (Intel & Apple Silicon)
        "MacBookAir4,1": "MacBook Air 11\" (Mid 2011)",
        "MacBookAir4,2": "MacBook Air 13\" (Mid 2011)",
        "MacBookAir5,1": "MacBook Air 11\" (Mid 2012)",
        "MacBookAir5,2": "MacBook Air 13\" (Mid 2012)",
        "MacBookAir6,1": "MacBook Air 11\" (Mid 2013 / Early 2014)",
        "MacBookAir6,2": "MacBook Air 13\" (Mid 2013 / Early 2014)",
        "MacBookAir7,1": "MacBook Air 11\" (Early 2015)",
        "MacBookAir7,2": "MacBook Air 13\" (Early 2015 / 2017)",
        "MacBookAir8,1": "MacBook Air 13\" (Retina, 2018)",
        "MacBookAir8,2": "MacBook Air 13\" (Retina, 2019)",
        "MacBookAir9,1": "MacBook Air 13\" (Retina, 2020)",
        "MacBookAir10,1": "MacBook Air (M1, 2020)",
        "Mac14,2":   "MacBook Air 13\" (M2, 2022)",
        "Mac14,15":  "MacBook Air 15\" (M2, 2023)",
        "Mac15,12":  "MacBook Air 13\" (M3, 2024)",
        "Mac15,13":  "MacBook Air 15\" (M3, 2024)",
        
        // MacBook Pro (Intel & Apple Silicon)
        "MacBookPro8,1": "MacBook Pro 13\" (Early/Late 2011)",
        "MacBookPro8,2": "MacBook Pro 15\" (Early/Late 2011)",
        "MacBookPro8,3": "MacBook Pro 17\" (Early/Late 2011)",
        "MacBookPro9,1": "MacBook Pro 15\" (Mid 2012)",
        "MacBookPro9,2": "MacBook Pro 13\" (Mid 2012)",
        "MacBookPro10,1": "MacBook Pro 15\" (Retina, 2012 / Early 2013)",
        "MacBookPro10,2": "MacBook Pro 13\" (Retina, 2012 / Early 2013)",
        "MacBookPro11,1": "MacBook Pro 13\" (Retina, Late 2013 / Mid 2014)",
        "MacBookPro11,2": "MacBook Pro 15\" (Retina, Late 2013 / Mid 2014)",
        "MacBookPro11,3": "MacBook Pro 15\" (Retina, Late 2013 / Mid 2014)",
        "MacBookPro11,4": "MacBook Pro 15\" (Retina, Mid 2015)",
        "MacBookPro11,5": "MacBook Pro 15\" (Retina, Mid 2015)",
        "MacBookPro12,1": "MacBook Pro 13\" (Retina, Early 2015)",
        "MacBookPro13,1": "MacBook Pro 13\" (2016, Two Ports)",
        "MacBookPro13,2": "MacBook Pro 13\" (2016, Four Ports)",
        "MacBookPro13,3": "MacBook Pro 15\" (2016)",
        "MacBookPro14,1": "MacBook Pro 13\" (2017, Two Ports)",
        "MacBookPro14,2": "MacBook Pro 13\" (2017, Four Ports)",
        "MacBookPro14,3": "MacBook Pro 15\" (2017)",
        "MacBookPro15,1": "MacBook Pro 15\" (2018 / 2019)",
        "MacBookPro15,2": "MacBook Pro 13\" (2018 / 2019, Four Ports)",
        "MacBookPro15,3": "MacBook Pro 15\" (2019)",
        "MacBookPro15,4": "MacBook Pro 13\" (2019, Two Ports)",
        "MacBookPro16,1": "MacBook Pro 16\" (2019)",
        "MacBookPro16,2": "MacBook Pro 13\" (2020, Four Ports)",
        "MacBookPro16,3": "MacBook Pro 13\" (2020, Two Ports)",
        "MacBookPro16,4": "MacBook Pro 16\" (2019, AMD 5600M)",
        "MacBookPro17,1": "MacBook Pro 13\" (M1, 2020)",
        "MacBookPro18,1": "MacBook Pro 16\" (M1 Pro, 2021)",
        "MacBookPro18,2": "MacBook Pro 16\" (M1 Max, 2021)",
        "MacBookPro18,3": "MacBook Pro 14\" (M1 Pro, 2021)",
        "MacBookPro18,4": "MacBook Pro 14\" (M1 Max, 2021)",
        "Mac14,7":   "MacBook Pro 13\" (M2, 2022)",
        "Mac14,9":   "MacBook Pro 14\" (M2 Pro, 2023)",
        "Mac14,10":  "MacBook Pro 16\" (M2 Pro, 2023)",
        "Mac15,3":   "MacBook Pro 14\" (M3, 2023)",
        "Mac15,6":   "MacBook Pro 14\" (M3 Pro, 2023)",
        "Mac15,8":   "MacBook Pro 16\" (M3 Pro, 2023)",
        "Mac16,1":   "MacBook Pro 14\" (M4, 2024)",
        "Mac16,6":   "MacBook Pro 14\" (M4 Pro, 2024)",
        "Mac16,8":   "MacBook Pro 16\" (M4 Pro, 2024)",
        
        // iMac (Intel & Apple Silicon)
        "iMac12,1":  "iMac 21.5\" (Mid 2011)",
        "iMac12,2":  "iMac 27\" (Mid 2011)",
        "iMac13,1":  "iMac 21.5\" (Late 2012)",
        "iMac13,2":  "iMac 27\" (Late 2012)",
        "iMac14,1":  "iMac 21.5\" (Late 2013)",
        "iMac14,2":  "iMac 27\" (Late 2013)",
        "iMac14,4":  "iMac 21.5\" (Mid 2014)",
        "iMac15,1":  "iMac 27\" (Retina 5K, Late 2014 / Mid 2015)",
        "iMac16,1":  "iMac 21.5\" (Late 2015)",
        "iMac16,2":  "iMac 21.5\" (Retina 4K, Late 2015)",
        "iMac17,1":  "iMac 27\" (Retina 5K, Late 2015)",
        "iMac18,1":  "iMac 21.5\" (2017)",
        "iMac18,2":  "iMac 21.5\" (Retina 4K, 2017)",
        "iMac18,3":  "iMac 27\" (Retina 5K, 2017)",
        "iMac19,1":  "iMac 27\" (Retina 5K, 2019)",
        "iMac19,2":  "iMac 21.5\" (Retina 4K, 2019)",
        "iMac20,1":  "iMac 27\" (Retina 5K, 2020)",
        "iMac20,2":  "iMac 27\" (Retina 5K, 2020, Nano-texture)",
        "iMac21,1":  "iMac 24\" (M1, 2021, Two Ports)",
        "iMac21,2":  "iMac 24\" (M1, 2021, Four Ports)",
        "Mac15,4":   "iMac 24\" (M3, 2023, Two Ports)",
        "Mac15,5":   "iMac 24\" (M3, 2023, Four Ports)",
        "Mac16,2":   "iMac 24\" (M4, 2024, Two Ports)",
        "Mac16,3":   "iMac 24\" (M4, 2024, Four Ports)",
        
        // iMac Pro & Mac Pro & Mac Studio
        "iMacPro1,1": "iMac Pro (2017)",
        "MacPro6,1":  "Mac Pro (Late 2013)",
        "MacPro7,1":  "Mac Pro (2019)",
        "Mac13,1":    "Mac Studio (M1 Max, 2022)",
        "Mac13,2":    "Mac Studio (M1 Ultra, 2022)",
        "Mac14,13":   "Mac Studio (M2 Max, 2023)",
        "Mac14,14":   "Mac Studio (M2 Ultra, 2023)",
        "Mac14,8":    "Mac Pro (M2 Ultra, 2023)"
    ]
}
