import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var webView: WKWebView?
    
    var monitor: SystemMonitor
    var config: AppConfig
    var isRoot: Bool
    
    var statusMenuItem: NSMenuItem!
    var fanMenuItem: NSMenuItem!
    var profileMenuItems: [String: NSMenuItem] = [:]
    var autostartMenuItem: NSMenuItem?
    var startMinimizedMenuItem: NSMenuItem?
    var updateTimer: Timer?
    var currentTimerInterval: Double = 2.0
    
    init(monitor: SystemMonitor, config: AppConfig, isRoot: Bool) {
        self.monitor = monitor
        self.config = config
        self.isRoot = isRoot
        self.currentTimerInterval = max(1.0, config.updateInterval)
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        
        currentTimerInterval = max(1.0, config.updateInterval)
        updateTimer = Timer.scheduledTimer(withTimeInterval: currentTimerInterval, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
        
        // Minimize to menu bar on launch if requested (e.g. at login or configured)
        let isMinimized = CommandLine.arguments.contains("--minimized") ||
                          CommandLine.arguments.contains("-m") ||
                          config.startMinimized
        if !isMinimized {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.openDashboard(nil)
            }
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "--°C  ---- RPM"
            button.toolTip = "FanMaster — Control de Ventiladores"
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let headerItem = NSMenuItem(title: "FanMaster", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        statusMenuItem = NSMenuItem(title: "CPU Die: --°C", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        fanMenuItem = NSMenuItem(title: "Ventilador: ---- RPM", action: nil, keyEquivalent: "")
        fanMenuItem.isEnabled = false
        menu.addItem(fanMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let profileSubmenu = NSMenu()
        let profileHeader = NSMenuItem(title: "Perfiles de Control", action: nil, keyEquivalent: "")
        profileHeader.submenu = profileSubmenu
        menu.addItem(profileHeader)
        
        for profile in config.profiles {
            let item = NSMenuItem(title: "Perfil \(profile.name)", action: #selector(profileSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            profileSubmenu.addItem(item)
            profileMenuItems[profile.id] = item
        }
        
        profileSubmenu.addItem(NSMenuItem.separator())
        let appleAutoItem = NSMenuItem(title: "Control Automático (Apple)", action: #selector(appleAutoSelected(_:)), keyEquivalent: "")
        appleAutoItem.target = self
        appleAutoItem.representedObject = "apple"
        profileSubmenu.addItem(appleAutoItem)
        profileMenuItems["apple"] = appleAutoItem
        
        menu.addItem(NSMenuItem.separator())
        
        let autostartItem = NSMenuItem(title: "Iniciar con macOS", action: #selector(toggleAutostart(_:)), keyEquivalent: "")
        autostartItem.target = self
        autostartItem.state = config.launchAtLogin ? .on : .off
        menu.addItem(autostartItem)
        self.autostartMenuItem = autostartItem
        
        let startMinItem = NSMenuItem(title: "Iniciar Minimizado en Barra", action: #selector(toggleStartMinimized(_:)), keyEquivalent: "")
        startMinItem.target = self
        startMinItem.state = config.startMinimized ? .on : .off
        menu.addItem(startMinItem)
        self.startMinimizedMenuItem = startMinItem
        
        menu.addItem(NSMenuItem.separator())
        
        let dashItem = NSMenuItem(title: "Abrir Panel de Control…", action: #selector(openDashboard(_:)), keyEquivalent: "o")
        dashItem.target = self
        menu.addItem(dashItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Salir de FanMaster", action: #selector(quitApp(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func updateStatus() {
        config = loadConfig()
        
        // Dynamically update timer interval if configuration changed
        if abs(config.updateInterval - currentTimerInterval) > 0.1 && config.updateInterval >= 1.0 {
            currentTimerInterval = config.updateInterval
            updateTimer?.invalidate()
            updateTimer = Timer.scheduledTimer(withTimeInterval: currentTimerInterval, repeats: true) { [weak self] _ in
                self?.updateStatus()
            }
        }
        
        let targetKey = config.menuBarSensorKey.isEmpty ? "TC0D" : config.menuBarSensorKey
        let primarySensor: TemperatureSensor?
        
        if targetKey == "MAX" {
            primarySensor = monitor.temperatures
                .filter { $0.key != "TC0G" && $0.currentTemp < 110 }
                .max(by: { $0.currentTemp < $1.currentTemp })
        } else {
            primarySensor = monitor.temperatures.first(where: { $0.key == targetKey })
                ?? monitor.temperatures.first(where: { $0.key == "TC0D" })
                ?? monitor.temperatures.first(where: { $0.key == "TC0P" })
                ?? monitor.temperatures.first(where: { $0.name.lowercased().contains("die") || $0.name.lowercased().contains("core") })
                ?? monitor.temperatures.first
        }
        
        let tempVal = primarySensor?.currentTemp ?? 0
        let tempInt = Int(round(tempVal))
        let displayTemp = tempInt > 0 ? "\(tempInt)°C" : "--°C"
        let isFanless = monitor.fans.isEmpty
        
        let alertPrefix = (tempVal >= config.alertTempThreshold && tempVal > 0) ? "⚠️ " : ""
        
        if isFanless {
            if config.menuBarDisplayMode == "rpmOnly" {
                statusItem.button?.title = "\(alertPrefix)Pasivo"
            } else {
                statusItem.button?.title = "\(alertPrefix)\(displayTemp)"
            }
            statusMenuItem.title = "\(primarySensor?.name ?? "CPU Die"): \(displayTemp)"
            fanMenuItem.title = "Enfriamiento: Disipación Pasiva"
        } else {
            let primaryFan = monitor.fans.first
            let fanRPM = Int(round(primaryFan?.currentRPM ?? 0))
            let displayRPM = fanRPM > 0 ? "\(fanRPM) RPM" : "---- RPM"
            
            if monitor.fans.count > 1 {
                let avgRPM = Int(round(monitor.fans.map(\.currentRPM).reduce(0, +) / Double(monitor.fans.count)))
                let multiRPM = avgRPM > 0 ? "\(avgRPM) RPM" : "---- RPM"
                if config.menuBarDisplayMode == "tempOnly" {
                    statusItem.button?.title = "\(alertPrefix)\(displayTemp)"
                } else if config.menuBarDisplayMode == "rpmOnly" {
                    statusItem.button?.title = "\(alertPrefix)\(multiRPM)"
                } else {
                    statusItem.button?.title = "\(alertPrefix)\(displayTemp)  \(multiRPM)"
                }
                statusMenuItem.title = "\(primarySensor?.name ?? "CPU Die"): \(displayTemp)"
                fanMenuItem.title = "\(monitor.fans.count) Ventiladores (\(displayRPM) CPU)"
            } else {
                if config.menuBarDisplayMode == "tempOnly" {
                    statusItem.button?.title = "\(alertPrefix)\(displayTemp)"
                } else if config.menuBarDisplayMode == "rpmOnly" {
                    statusItem.button?.title = "\(alertPrefix)\(displayRPM)"
                } else {
                    statusItem.button?.title = "\(alertPrefix)\(displayTemp)  \(displayRPM)"
                }
                statusMenuItem.title = "\(primarySensor?.name ?? "CPU Die"): \(displayTemp)"
                fanMenuItem.title = "\(primaryFan?.name ?? "Ventilador"): \(displayRPM)"
            }
        }
        
        let activeId: String
        if isRoot {
            activeId = monitor.controller.isRunning ? (monitor.controller.activeProfile?.id ?? "apple") : "apple"
        } else {
            activeId = config.activeProfileId.isEmpty ? "apple" : config.activeProfileId
        }
        
        for (id, item) in profileMenuItems {
            item.state = (id == activeId) ? .on : .off
        }
        
        autostartMenuItem?.state = config.launchAtLogin ? .on : .off
        startMinimizedMenuItem?.state = config.startMinimized ? .on : .off
        applyWindowAppearance()
    }
    
    @objc func toggleAutostart(_ sender: NSMenuItem) {
        config.launchAtLogin.toggle()
        sender.state = config.launchAtLogin ? .on : .off
        configureLaunchAtLogin(enabled: config.launchAtLogin, startMinimized: config.startMinimized)
        saveConfig(config)
    }
    
    @objc func toggleStartMinimized(_ sender: NSMenuItem) {
        config.startMinimized.toggle()
        sender.state = config.startMinimized ? .on : .off
        configureLaunchAtLogin(enabled: config.launchAtLogin, startMinimized: config.startMinimized)
        saveConfig(config)
    }
    
    @objc func profileSelected(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if isRoot, let profile = config.profiles.first(where: { $0.id == id }) {
            monitor.controller.applyProfile(profile)
        }
        if let url = URL(string: "http://localhost:\(config.port)/api/profile/apply?id=\(id)") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req).resume()
        }
        config.activeProfileId = id
        saveConfig(config)
        updateStatus()
    }
    
    @objc func appleAutoSelected(_ sender: NSMenuItem) {
        if isRoot {
            monitor.controller.stopControl()
        }
        if let url = URL(string: "http://localhost:\(config.port)/api/control/auto") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req).resume()
        }
        config.activeProfileId = "apple"
        saveConfig(config)
        updateStatus()
    }
    
    @objc func openDashboard(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        
        if window == nil {
            let rect = NSRect(x: 0, y: 0, width: 620, height: 600)
            let win = NSWindow(
                contentRect: rect,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.minSize = NSSize(width: 520, height: 480)
            win.title = "FanMaster — Control de Ventiladores y Temperatura"
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            
            let config = WKWebViewConfiguration()
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
            let web = WKWebView(frame: win.contentView!.bounds, configuration: config)
            web.autoresizingMask = [.width, .height]
            if let url = URL(string: "http://localhost:\(self.config.port)") {
                web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10))
            }
            win.contentView = web
            self.window = win
            self.webView = web
            applyWindowAppearance()
        } else {
            if let url = URL(string: "http://localhost:\(self.config.port)") {
                webView?.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10))
            }
            applyWindowAppearance()
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applyWindowAppearance() {
        guard let win = window else { return }
        if config.appearanceMode == "dark" {
            win.appearance = NSAppearance(named: .darkAqua)
        } else if config.appearanceMode == "light" {
            win.appearance = NSAppearance(named: .aqua)
        } else {
            win.appearance = nil
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
    
    @objc func quitApp(_ sender: Any?) {
        monitor.controller.stopControl()
        NSApp.terminate(nil)
    }
}
