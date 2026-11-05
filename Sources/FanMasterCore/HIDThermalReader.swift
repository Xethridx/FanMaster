import Foundation
import IOKit

// MARK: - Apple Silicon HID Thermal Reader
// Uses IOHIDEventSystemClient to query native M1/M2/M3/M4 thermal sensors

public class HIDThermalReader {
    private typealias IOHIDEventSystemClientCreateFunc = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias IOHIDEventSystemClientSetMatchingFunc = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias IOHIDEventSystemClientCopyServicesFunc = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias IOHIDServiceClientCopyPropertyFunc = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias IOHIDServiceClientCopyEventFunc = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias IOHIDEventGetFloatValueFunc = @convention(c) (AnyObject, Int32) -> Double
    
    private var clientCreate: IOHIDEventSystemClientCreateFunc?
    private var clientSetMatching: IOHIDEventSystemClientSetMatchingFunc?
    private var clientCopyServices: IOHIDEventSystemClientCopyServicesFunc?
    private var serviceCopyProperty: IOHIDServiceClientCopyPropertyFunc?
    private var serviceCopyEvent: IOHIDServiceClientCopyEventFunc?
    private var eventGetFloatValue: IOHIDEventGetFloatValueFunc?
    
    public private(set) var isAvailable: Bool = false
    
    public init() {
        let handle = dlopen(nil, RTLD_NOW)
        guard let handle = handle else { return }
        
        if let symCreate = dlsym(handle, "IOHIDEventSystemClientCreate"),
           let symSetMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
           let symCopyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
           let symCopyProp = dlsym(handle, "IOHIDServiceClientCopyProperty"),
           let symCopyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
           let symGetFloat = dlsym(handle, "IOHIDEventGetFloatValue") {
            
            clientCreate = unsafeBitCast(symCreate, to: IOHIDEventSystemClientCreateFunc.self)
            clientSetMatching = unsafeBitCast(symSetMatching, to: IOHIDEventSystemClientSetMatchingFunc.self)
            clientCopyServices = unsafeBitCast(symCopyServices, to: IOHIDEventSystemClientCopyServicesFunc.self)
            serviceCopyProperty = unsafeBitCast(symCopyProp, to: IOHIDServiceClientCopyPropertyFunc.self)
            serviceCopyEvent = unsafeBitCast(symCopyEvent, to: IOHIDServiceClientCopyEventFunc.self)
            eventGetFloatValue = unsafeBitCast(symGetFloat, to: IOHIDEventGetFloatValueFunc.self)
            isAvailable = true
        }
    }
    
    /// Reads all temperature sensors exposed via Apple Silicon IOHID
    public func readTemperatures() -> [TemperatureSensor] {
        guard isAvailable,
              let clientCreate = clientCreate,
              let clientSetMatching = clientSetMatching,
              let clientCopyServices = clientCopyServices,
              let serviceCopyProperty = serviceCopyProperty,
              let serviceCopyEvent = serviceCopyEvent,
              let eventGetFloatValue = eventGetFloatValue else {
            return []
        }
        
        guard let unmanagedClient = clientCreate(kCFAllocatorDefault) else { return [] }
        let client = unmanagedClient.takeRetainedValue()
        
        // Match AppleVendor page (0xff00) and TemperatureSensor usage (0x0005)
        let matchingDict: [String: Any] = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 0x0005
        ]
        clientSetMatching(client, matchingDict as CFDictionary)
        
        guard let unmanagedServices = clientCopyServices(client) else { return [] }
        let services = unmanagedServices.takeRetainedValue() as [AnyObject]
        
        var results: [TemperatureSensor] = []
        // IOHIDEventTypeTemperature = 15
        let eventTypeTemperature: Int64 = 15
        // (15 << 16) | 0 represents the temperature in Celsius
        let temperatureField: Int32 = (15 << 16)
        
        for service in services {
            var rawName = ""
            if let unmanagedProp = serviceCopyProperty(service, "Product" as CFString) {
                let prop = unmanagedProp.takeRetainedValue()
                if let str = prop as? String {
                    rawName = str
                }
            }
            
            if rawName.isEmpty {
                if let unmanagedLoc = serviceCopyProperty(service, "LocationID" as CFString) {
                    let loc = unmanagedLoc.takeRetainedValue()
                    rawName = "Sensor_\(loc)"
                } else {
                    continue
                }
            }
            
            if let unmanagedEvent = serviceCopyEvent(service, eventTypeTemperature, 0, 0) {
                let event = unmanagedEvent.takeRetainedValue()
                let temp = eventGetFloatValue(event, temperatureField)
                
                // Validate plausible range (10°C – 125°C)
                if temp > 10.0 && temp < 125.0 {
                    let friendlyName = formatSensorName(rawName)
                    results.append(TemperatureSensor(key: rawName, name: friendlyName, currentTemp: temp))
                }
            }
        }
        
        return results
    }
    
    private func formatSensorName(_ raw: String) -> String {
        // Human-friendly mapping for common Apple Silicon keys
        if raw.lowercased().contains("pcore") {
            return "CPU Performance Core (\(raw))"
        }
        if raw.lowercased().contains("ecore") {
            return "CPU Efficiency Core (\(raw))"
        }
        if raw.lowercased().contains("gpu") {
            return "GPU Core (\(raw))"
        }
        if raw.lowercased().contains("ane") {
            return "Apple Neural Engine (\(raw))"
        }
        if raw.lowercased().contains("soc") {
            return "SoC Die (\(raw))"
        }
        if raw.lowercased().contains("pmu") {
            return "Power Management (\(raw))"
        }
        if raw.lowercased().contains("nand") {
            return "Almacenamiento NAND (\(raw))"
        }
        if raw.lowercased().contains("gas gauge") || raw.lowercased().contains("batt") {
            return "Batería (\(raw))"
        }
        return raw
    }
}

