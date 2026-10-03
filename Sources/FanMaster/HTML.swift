import Foundation

// MARK: - Embedded HTML Dashboard Loader

func getIndexHTML() -> String {
    var candidates: [URL] = []
    
    // 1. App Bundle resources (Standard macOS .app)
    if let bundleURL = Bundle.main.url(forResource: "index", withExtension: "html") {
        candidates.append(bundleURL)
    }
    
    // 2. Relative to executable inside .app (Contents/MacOS/../Resources/index.html or Contents/MacOS/index.html)
    let exePath = CommandLine.arguments[0]
    let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
    candidates.append(exeDir.appendingPathComponent("../Resources/index.html"))
    candidates.append(exeDir.appendingPathComponent("index.html"))
    
    // 3. Project directory
    candidates.append(URL(fileURLWithPath: "/Users/mac/Documents/FanMaster/Sources/FanMaster/index.html"))
    candidates.append(URL(fileURLWithPath: "/Users/mac/Documents/FanMaster/FanMaster.app/Contents/Resources/index.html"))
    
    // 4. CLI installation directory ~/.local/bin/index.html
    let home = FileManager.default.homeDirectoryForCurrentUser
    candidates.append(home.appendingPathComponent(".local/bin/index.html"))
    
    for url in candidates {
        if let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty {
            return content
        }
    }
    
    // Fallback: minimal placeholder
    return """
    <!DOCTYPE html>
    <html><head><meta charset="UTF-8"><title>FanMaster</title>
    <style>body{background:#0a0a12;color:#e8e6f0;font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;flex-direction:column;gap:16px;}</style>
    </head><body>
    <h1>🌡️ FanMaster</h1>
    <p>Cargando panel de control...</p>
    </body></html>
    """
}
