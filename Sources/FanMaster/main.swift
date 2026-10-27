import Foundation
import AppKit

// MARK: - Configuration persistence

struct AppConfig: Codable {
    var activeProfileId: String
    var profiles: [FanProfile]
    var updateInterval: Double
    var port: Int
    var alertTempThreshold: Double
    var menuBarSensorKey: String = "TC0D"
    var menuBarDisplayMode: String = "tempAndRpm"
    var launchAtLogin: Bool = true
    var startMinimized: Bool = true
    var appearanceMode: String = "system"
    
    enum CodingKeys: String, CodingKey {
        case activeProfileId, profiles, updateInterval, port, alertTempThreshold, menuBarSensorKey, menuBarDisplayMode, launchAtLogin, startMinimized, appearanceMode
    }
    
    init(activeProfileId: String = "balanced",
         profiles: [FanProfile] = [.silent, .balanced, .performance, .max],
         updateInterval: Double = 3.0,
         port: Int = 7474,
         alertTempThreshold: Double = 85.0,
         menuBarSensorKey: String = "TC0D",
         menuBarDisplayMode: String = "tempAndRpm",
         launchAtLogin: Bool = true,
         startMinimized: Bool = true,
         appearanceMode: String = "system") {
        self.activeProfileId = activeProfileId
        self.profiles = profiles
        self.updateInterval = updateInterval
        self.port = port
        self.alertTempThreshold = alertTempThreshold
        self.menuBarSensorKey = menuBarSensorKey
        self.menuBarDisplayMode = menuBarDisplayMode
        self.launchAtLogin = launchAtLogin
        self.startMinimized = startMinimized
        self.appearanceMode = appearanceMode
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProfileId = try container.decodeIfPresent(String.self, forKey: .activeProfileId) ?? "balanced"
        profiles = try container.decodeIfPresent([FanProfile].self, forKey: .profiles) ?? [.silent, .balanced, .performance, .max]
        updateInterval = try container.decodeIfPresent(Double.self, forKey: .updateInterval) ?? 3.0
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 7474
        alertTempThreshold = try container.decodeIfPresent(Double.self, forKey: .alertTempThreshold) ?? 85.0
        menuBarSensorKey = try container.decodeIfPresent(String.self, forKey: .menuBarSensorKey) ?? "TC0D"
        menuBarDisplayMode = try container.decodeIfPresent(String.self, forKey: .menuBarDisplayMode) ?? "tempAndRpm"
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        startMinimized = try container.decodeIfPresent(Bool.self, forKey: .startMinimized) ?? true
        appearanceMode = try container.decodeIfPresent(String.self, forKey: .appearanceMode) ?? "system"
    }
    
    static var `default`: AppConfig {
        AppConfig()
    }
}

func getConsoleUserHome() -> URL {
    var statBuf = stat()
    if stat("/dev/console", &statBuf) == 0 {
        if let pw = getpwuid(statBuf.st_uid), let home = pw.pointee.pw_dir {
            let consoleHome = String(cString: home)
            if !consoleHome.isEmpty && consoleHome != "/var/root" {
                return URL(fileURLWithPath: consoleHome)
            }
        }
    }
    if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
        let homeStr = String(cString: home)
        if !homeStr.isEmpty && homeStr != "/var/root" {
            return URL(fileURLWithPath: homeStr)
        }
    }
    return FileManager.default.homeDirectoryForCurrentUser
}

func getConfigDir() -> URL {
    let sharedDir = URL(fileURLWithPath: "/Library/Application Support/FanMaster")
    if FileManager.default.fileExists(atPath: sharedDir.appendingPathComponent("config.json").path) {
        return sharedDir
    }
    return getConsoleUserHome().appendingPathComponent(".config/fanmaster")
}

func loadConfig() -> AppConfig {
    let dir = getConfigDir()
    let configPath = dir.appendingPathComponent("config.json")
    guard let data = try? Data(contentsOf: configPath),
          let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
        return .default
    }
    return config
}

func saveConfig(_ config: AppConfig) {
    let dir = getConfigDir()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("config.json")
    if let data = try? JSONEncoder().encode(config) {
        try? data.write(to: path)
        chmod(path.path, 0o666)
        var statBuf = stat()
        if stat("/dev/console", &statBuf) == 0 && getuid() == 0 {
            chown(path.path, statBuf.st_uid, statBuf.st_gid)
            chown(dir.path, statBuf.st_uid, statBuf.st_gid)
        }
    }
}

func configureLaunchAtLogin(enabled: Bool, startMinimized: Bool) {
    let home = getConsoleUserHome()
    let launchAgentDir = home.appendingPathComponent("Library/LaunchAgents")
    let plistURL = launchAgentDir.appendingPathComponent("com.fanmaster.app.plist")
    
    if enabled {
        try? FileManager.default.createDirectory(at: launchAgentDir, withIntermediateDirectories: true)
        let minFlag = startMinimized ? "\n        <string>--minimized</string>" : ""
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.fanmaster.app</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Applications/FanMaster.app/Contents/MacOS/FanMaster</string>\(minFlag)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
        try? plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        chmod(plistURL.path, 0o644)
        var statBuf = stat()
        if stat("/dev/console", &statBuf) == 0 && getuid() == 0 {
            chown(plistURL.path, statBuf.st_uid, statBuf.st_gid)
        }
    } else {
        try? FileManager.default.removeItem(at: plistURL)
    }
}

// MARK: - Main entry point

func main() {
    let isCliMode = CommandLine.arguments.contains("--cli")
    
    if isCliMode {
        print("""
        ╔═══════════════════════════════════════════════════════════╗
        ║     🌡️  FanMaster — \(SystemInfo.marketingModelName)
        ║     Arquitectura: \(SystemInfo.architecture) • \(SystemInfo.modelIdentifier)
        ╚═══════════════════════════════════════════════════════════╝
        """)
    }
    
    // Open SMC
    let smc: SMCConnection
    do {
        smc = try SMCConnection()
        if isCliMode { print("✅ Conexión SMC establecida") }
    } catch {
        print("❌ Error al conectar con SMC: \(error.localizedDescription)")
        print("   Asegúrate de ejecutar con privilegios suficientes.")
        exit(1)
    }
    
    var config = loadConfig()
    let monitor = SystemMonitor(smc: smc)
    monitor.updateInterval = config.updateInterval
    
    // Detect fans & temps
    let initialFans = monitor.reader.readAllFans()
    if isCliMode {
        if initialFans.isEmpty {
            print("⚠️  No se detectaron ventiladores. Continuando en modo solo lectura.")
        } else {
            print("✅ \(initialFans.count) ventilador(es) detectado(s)")
        }
        let initialTemps = monitor.reader.readAllTemperatures()
        print("✅ \(initialTemps.count) sensor(es) de temperatura detectado(s)")
    }
    
    // Start monitoring
    monitor.startMonitoring()
    
    // Apply saved profile
    if let profile = config.profiles.first(where: { $0.id == config.activeProfileId }) {
        monitor.controller.applyProfile(profile)
        if isCliMode { print("✅ Perfil aplicado: \(profile.emoji) \(profile.name)") }
    }
    
    // Check root / effective root
    let isRoot = (geteuid() == 0) || (getuid() == 0)
    if isCliMode && !isRoot {
        print("\n⚠️  Ejecutándose sin root. El control de ventiladores estará deshabilitado.")
        print("   Para control completo: sudo fanmaster\n")
    }
    
    // HTTP Server
    let server = HTTPServer(port: UInt16(config.port))
    
    server.onRequest { method, rawPath in
        let pathOnly = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        
        switch (method, pathOnly) {
        case ("GET", "/"):
            let html = getIndexHTML()
            return (200, "text/html", html)
            
        case ("GET", "/api/status"):
            let temps = monitor.temperatures.map { sensor -> [String: Any] in
                [
                    "key": sensor.key,
                    "name": sensor.name,
                    "temp": sensor.currentTemp,
                    "history": monitor.temperatureHistory[sensor.key]?.points.map { ["t": $0.timestamp.timeIntervalSince1970, "v": $0.value] } ?? []
                ]
            }
            let fans = monitor.fans.map { fan -> [String: Any] in
                [
                    "index": fan.index,
                    "name": fan.name,
                    "currentRPM": fan.currentRPM,
                    "minimumRPM": fan.minimumRPM,
                    "maximumRPM": fan.maximumRPM,
                    "targetRPM": fan.targetRPM,
                    "history": monitor.fanHistory[fan.index]?.points.map { ["t": $0.timestamp.timeIntervalSince1970, "v": $0.value] } ?? []
                ]
            }
            let data: [String: Any] = [
                "temperatures": temps,
                "fans": fans,
                "cpuUsage": monitor.cpuUsage,
                "activeProfile": monitor.controller.activeProfile?.id ?? "none",
                "isRoot": isRoot,
                "alertThreshold": config.alertTempThreshold,
                "system": [
                    "modelIdentifier": SystemInfo.modelIdentifier,
                    "modelName": SystemInfo.marketingModelName,
                    "processor": SystemInfo.cpuBrand,
                    "architecture": SystemInfo.architecture,
                    "osVersion": SystemInfo.osVersion
                ],
                "timestamp": Date().timeIntervalSince1970
            ]
            return (200, "application/json", jsonString(data))
            
        case ("GET", "/api/profiles"):
            let profilesData = config.profiles.map { p -> [String: Any] in
                [
                    "id": p.id,
                    "name": p.name,
                    "emoji": p.emoji,
                    "sensorKey": p.sensorKey,
                    "isAutomatic": p.isAutomatic,
                    "isActive": monitor.controller.activeProfile?.id == p.id,
                    "curvePoints": p.curvePoints.map { ["temperature": $0.temperature, "fanSpeed": $0.fanSpeed] }
                ]
            }
            return (200, "application/json", jsonString(profilesData))
            
        case ("POST", "/api/profile/apply"):
            guard isRoot else {
                return (403, "application/json", jsonString(["error": "Se requiere root para controlar los ventiladores"]))
            }
            let components = rawPath.split(separator: "?")
            var profileId = ""
            if components.count > 1 {
                let query = String(components[1])
                for param in query.split(separator: "&") {
                    let kv = param.split(separator: "=")
                    if kv.first == "id", let v = kv.last {
                        profileId = String(v)
                    }
                }
            }
            guard let profile = config.profiles.first(where: { $0.id == profileId }) else {
                return (404, "application/json", jsonString(["error": "Perfil no encontrado"]))
            }
            monitor.controller.applyProfile(profile)
            config.activeProfileId = profileId
            saveConfig(config)
            return (200, "application/json", jsonString(["ok": true, "profile": profile.name] as [String: Any]))
            
        case ("POST", "/api/control/auto"):
            guard isRoot else {
                return (403, "application/json", jsonString(["error": "Se requiere root"]))
            }
            monitor.controller.stopControl()
            config.activeProfileId = "apple"
            saveConfig(config)
            return (200, "application/json", jsonString(["ok": true]))
            
        case ("GET", "/api/config"):
            let c: [String: Any] = [
                "alertTempThreshold": config.alertTempThreshold,
                "updateInterval": config.updateInterval,
                "port": config.port,
                "menuBarSensorKey": config.menuBarSensorKey,
                "menuBarDisplayMode": config.menuBarDisplayMode,
                "launchAtLogin": config.launchAtLogin,
                "startMinimized": config.startMinimized,
                "appearanceMode": config.appearanceMode
            ]
            return (200, "application/json", jsonString(c))
            
        case ("POST", "/api/config"):
            let components = rawPath.split(separator: "?")
            if components.count > 1 {
                let query = String(components[1])
                for param in query.split(separator: "&") {
                    let kv = param.split(separator: "=")
                    guard kv.count == 2 else { continue }
                    let k = String(kv[0])
                    let v = String(kv[1])
                    if k == "alertThreshold", let d = Double(v) {
                        config.alertTempThreshold = d
                    }
                    if k == "interval", let d = Double(v) {
                        config.updateInterval = max(1, min(60, d))
                        monitor.updateInterval = config.updateInterval
                    }
                    if k == "menuBarSensorKey" {
                        config.menuBarSensorKey = v
                    }
                    if k == "menuBarDisplayMode" {
                        config.menuBarDisplayMode = v
                    }
                    if k == "appearanceMode" {
                        config.appearanceMode = v
                    }
                    if k == "launchAtLogin" {
                        config.launchAtLogin = (v == "true" || v == "1")
                        configureLaunchAtLogin(enabled: config.launchAtLogin, startMinimized: config.startMinimized)
                    }
                    if k == "startMinimized" {
                        config.startMinimized = (v == "true" || v == "1")
                        configureLaunchAtLogin(enabled: config.launchAtLogin, startMinimized: config.startMinimized)
                    }
                }
            }
            saveConfig(config)
            return (200, "application/json", jsonString(["ok": true]))
            
        default:
            return (404, "text/plain", "Not Found")
        }
    }
    
    do {
        try server.start()
    } catch {
        if !isCliMode {
            print("ℹ️ Conectado a servicio existente en puerto \(config.port)")
        } else {
            print("❌ Error iniciando servidor HTTP: \(error.localizedDescription)")
            exit(1)
        }
    }
    
    if isCliMode {
        print("\n🌐 Dashboard disponible en: \u{1B}[4mhttp://localhost:\(config.port)\u{1B}[0m")
        print("   Presiona Ctrl+C para salir\n")
        
        signal(SIGINT) { _ in
            print("\n👋 Restaurando control automático de ventiladores...")
            exit(0)
        }
        
        RunLoop.main.run()
    } else {
        // Native macOS Menu Bar App
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        
        let delegate = AppDelegate(monitor: monitor, config: config, isRoot: isRoot)
        app.delegate = delegate
        app.run()
    }
}

main()
