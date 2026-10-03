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
    var updateTimer: Timer?
    
    init(monitor: SystemMonitor, config: AppConfig, isRoot: Bool) {
        self.monitor = monitor
        self.config = config
        self.isRoot = isRoot
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        updateStatus()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.openDashboard(nil)
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
                ?? monitor.temperatures.first
        }
        
        let tempVal = primarySensor?.currentTemp ?? 0
        let fan = monitor.fans.first
        let fanRPM = Int(round(fan?.currentRPM ?? 0))
        let tempInt = Int(round(tempVal))
        
        let displayTemp = tempInt > 0 ? "\(tempInt)°C" : "--°C"
        let displayRPM = fanRPM > 0 ? "\(fanRPM) RPM" : "---- RPM"
        
        if config.menuBarDisplayMode == "tempOnly" {
            statusItem.button?.title = displayTemp
        } else if config.menuBarDisplayMode == "rpmOnly" {
            statusItem.button?.title = displayRPM
        } else {
            statusItem.button?.title = "\(displayTemp)  \(displayRPM)"
        }
        
        statusMenuItem.title = "\(primarySensor?.name ?? "CPU Die"): \(displayTemp)"
        fanMenuItem.title = "Ventilador: \(displayRPM)"
        
        let activeId = monitor.controller.isRunning ? (monitor.controller.activeProfile?.id ?? "") : "apple"
        for (id, item) in profileMenuItems {
            item.state = (id == activeId) ? .on : .off
        }
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
            let rect = NSRect(x: 0, y: 0, width: 1100, height: 750)
            let win = NSWindow(
                contentRect: rect,
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "FanMaster — Control de Ventiladores y Temperatura"
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            
            let config = WKWebViewConfiguration()
            let web = WKWebView(frame: win.contentView!.bounds, configuration: config)
            web.autoresizingMask = [.width, .height]
            if let url = URL(string: "http://localhost:\(self.config.port)") {
                web.load(URLRequest(url: url))
            }
            win.contentView = web
            self.window = win
            self.webView = web
        } else {
            if let url = URL(string: "http://localhost:\(self.config.port)") {
                webView?.load(URLRequest(url: url))
            }
        }
        
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
