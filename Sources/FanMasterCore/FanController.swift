import Foundation

// MARK: - Fan Controller (Profile-based automatic control)

public class FanController {
    private let reader: SMCReader
    private let writer: SMCWriter
    
    public private(set) var activeProfile: FanProfile?
    public private(set) var isRunning = false
    private var controlTask: Task<Void, Never>?
    
    /// How often (in seconds) the controller re-evaluates temperatures and adjusts fans
    public var updateInterval: TimeInterval = 5.0
    
    /// Hysteresis: only change fan speed if the target differs by this many RPM
    private let hysteresis: Double = 100
    
    /// Last set RPM per fan index
    private var lastSetRPM: [Int: Double] = [:]
    
    public init(reader: SMCReader, writer: SMCWriter) {
        self.reader = reader
        self.writer = writer
    }
    
    // MARK: - Control
    
    /// Apply a profile and start the automatic control loop
    public func applyProfile(_ profile: FanProfile) {
        stopControl()
        activeProfile = profile
        isRunning = true
        
        controlTask = Task {
            while !Task.isCancelled {
                applyProfileTick(profile)
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            }
        }
    }
    
    /// Stop automatic control and restore SMC auto management
    public func stopControl() {
        controlTask?.cancel()
        controlTask = nil
        isRunning = false
        activeProfile = nil
        lastSetRPM.removeAll()
        
        // Try to restore auto control (best effort)
        try? writer.restoreAutoControl()
    }
    
    /// Set a fixed RPM for a specific fan or all fans (manual override)
    public func setFixed(rpm: Double, fanIndex: Int? = nil) throws {
        stopControl()
        let fans = reader.readAllFans()
        for fan in fans {
            if fanIndex == nil || fan.index == fanIndex {
                let clamped = max(fan.minimumRPM, min(fan.maximumRPM, rpm))
                try writer.setFanManualControl(fan.index, enabled: true)
                try writer.setFanTargetRPM(fan.index, rpm: clamped)
                lastSetRPM[fan.index] = clamped
            }
        }
    }
    
    /// Set a fixed percentage (0% – 100%) for a specific fan or all fans (manual override)
    public func setFixed(percentage: Double, fanIndex: Int? = nil) throws {
        stopControl()
        let fans = reader.readAllFans()
        for fan in fans {
            if fanIndex == nil || fan.index == fanIndex {
                let targetRPM = fan.minimumRPM + (fan.maximumRPM - fan.minimumRPM) * (max(0, min(100, percentage)) / 100.0)
                let clamped = max(fan.minimumRPM, min(fan.maximumRPM, targetRPM))
                try writer.setFanManualControl(fan.index, enabled: true)
                try writer.setFanTargetRPM(fan.index, rpm: clamped)
                lastSetRPM[fan.index] = clamped
            }
        }
    }
    
    // MARK: - Private
    
    private func applyProfileTick(_ profile: FanProfile) {
        guard let temp = reader.temperature(for: profile.sensorKey) else { return }
        let fans = reader.readAllFans()
        
        for fan in fans {
            let targetRPM = profile.targetRPM(for: temp, minRPM: fan.minimumRPM, maxRPM: fan.maximumRPM)
            let last = lastSetRPM[fan.index] ?? -1
            
            // Apply hysteresis — only update if change is significant
            if abs(targetRPM - last) > hysteresis {
                let clamped = max(fan.minimumRPM, min(fan.maximumRPM, targetRPM))
                do {
                    try writer.setFanManualControl(fan.index, enabled: true)
                    try writer.setFanTargetRPM(fan.index, rpm: clamped)
                    lastSetRPM[fan.index] = clamped
                } catch {
                    // Permission error — stop trying
                }
            }
        }
    }
}

// MARK: - History Ring Buffer

public struct DataPoint: Codable, Sendable {
    public let timestamp: Date
    public let value: Double
    
    public init(timestamp: Date = Date(), value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

public class HistoryBuffer {
    private(set) public var points: [DataPoint] = []
    private let capacity: Int
    
    public init(capacity: Int = 120) {
        self.capacity = capacity
    }
    
    public func append(_ value: Double) {
        points.append(DataPoint(value: value))
        if points.count > capacity {
            points.removeFirst()
        }
    }
    
    public var latest: Double { points.last?.value ?? 0 }
    public var min: Double { points.map(\.value).min() ?? 0 }
    public var max: Double { points.map(\.value).max() ?? 0 }
    public var avg: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }
}

// MARK: - Monitor (main state aggregator)

public class SystemMonitor: @unchecked Sendable {
    public let reader: SMCReader
    public let writer: SMCWriter
    public let controller: FanController
    
    public private(set) var temperatures: [TemperatureSensor] = []
    public private(set) var fans: [FanSensor] = []
    public private(set) var cpuUsage: Double = 0
    
    /// Per-sensor temperature history
    public private(set) var temperatureHistory: [String: HistoryBuffer] = [:]
    /// Per-fan RPM history
    public private(set) var fanHistory: [Int: HistoryBuffer] = [:]
    
    private var updateTask: Task<Void, Never>?
    public var updateInterval: TimeInterval = 3.0
    
    /// Called whenever the state updates
    public var onUpdate: (@Sendable () -> Void)?
    
    public init(smc: SMCConnection) {
        self.reader = SMCReader(smc: smc)
        self.writer = SMCWriter(smc: smc)
        self.controller = FanController(reader: reader, writer: writer)
    }
    
    public func startMonitoring() {
        updateTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            }
        }
    }
    
    public func stopMonitoring() {
        updateTask?.cancel()
        updateTask = nil
    }
    
    @MainActor
    private func refresh() {
        temperatures = reader.readAllTemperatures()
        fans = reader.readAllFans()
        cpuUsage = reader.cpuUsage()
        
        // Update history buffers
        for sensor in temperatures {
            if temperatureHistory[sensor.key] == nil {
                temperatureHistory[sensor.key] = HistoryBuffer(capacity: 120)
            }
            temperatureHistory[sensor.key]?.append(sensor.currentTemp)
        }
        for fan in fans {
            if fanHistory[fan.index] == nil {
                fanHistory[fan.index] = HistoryBuffer(capacity: 120)
            }
            fanHistory[fan.index]?.append(fan.currentRPM)
        }
        
        onUpdate?()
    }
}
