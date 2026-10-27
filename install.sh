#!/bin/bash
# FanMaster — Build & Install Script
# Compila FanMaster como App Nativa (.app) y Servicio Daemon de Fondo con Root
# Uso: ./install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP_NAME="FanMaster.app"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
CLI_TARGET="/usr/local/bin/fanmaster"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     🌡️  FanMaster — Compilador de App Nativa macOS         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 1. Encontrar SDK disponible
SDK=""
for candidate in \
    "$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" \
    "/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk" \
    "/Library/Developer/CommandLineTools/SDKs/MacOSX13.1.sdk" \
    "/Library/Developer/CommandLineTools/SDKs/MacOSX13.sdk" \
    "/Library/Developer/CommandLineTools/SDKs/MacOSX12.3.sdk" \
    "/Library/Developer/CommandLineTools/SDKs/MacOSX12.sdk"; do
    if [ -d "$candidate" ]; then
        SDK="$candidate"
        break
    fi
done

if [ -z "$SDK" ]; then
    echo "❌ No se encontró el macOS SDK."
    echo "   Instala Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

echo "📦 SDK: $SDK"
mkdir -p "$BUILD_DIR"

# 2. Compilar binario nativo (AppKit + WebKit + IOKit + Foundation)
echo "🔨 Compilando binario nativo (Swift + AppKit + WebKit)…"

swiftc \
  -sdk "$SDK" \
  -target x86_64-apple-macos12.0 \
  -O \
  -framework IOKit \
  -framework Foundation \
  -framework AppKit \
  -framework WebKit \
  "$SCRIPT_DIR/Sources/FanMasterCore/SMCConnection.swift" \
  "$SCRIPT_DIR/Sources/FanMasterCore/Models.swift" \
  "$SCRIPT_DIR/Sources/FanMasterCore/SMCReaderWriter.swift" \
  "$SCRIPT_DIR/Sources/FanMasterCore/FanController.swift" \
  "$SCRIPT_DIR/Sources/FanMasterCore/HTTPServer.swift" \
  "$SCRIPT_DIR/Sources/FanMaster/HTML.swift" \
  "$SCRIPT_DIR/Sources/FanMaster/AppDelegate.swift" \
  "$SCRIPT_DIR/Sources/FanMaster/main.swift" \
  -o "$BUILD_DIR/FanMaster"

echo "✅ Binario compilado: $BUILD_DIR/FanMaster"

# 3. Construir FanMaster.app Bundle
echo "📦 Creando $APP_NAME…"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/FanMaster" "$APP_BUNDLE/Contents/MacOS/FanMaster"
chmod 755 "$APP_BUNDLE/Contents/MacOS/FanMaster"

cp "$SCRIPT_DIR/Sources/FanMaster/index.html" "$APP_BUNDLE/Contents/Resources/index.html"
cp "$SCRIPT_DIR/Sources/FanMaster/index.html" "$APP_BUNDLE/Contents/MacOS/index.html"

if [ -f "$SCRIPT_DIR/Resources/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

cat << 'PLIST' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FanMaster</string>
    <key>CFBundleIdentifier</key>
    <string>com.fanmaster.FanMaster</string>
    <key>CFBundleName</key>
    <string>FanMaster</string>
    <key>CFBundleDisplayName</key>
    <string>FanMaster</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

# Firmar bundle ad-hoc
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

# 4. Instalar en /Applications
echo "📲 Instalando en $TARGET_APP…"
rm -rf "$TARGET_APP"
cp -R "$APP_BUNDLE" "$TARGET_APP"
codesign --force --deep --sign - "$TARGET_APP" 2>/dev/null || true

# 5. Instalar herramienta de terminal en /usr/local/bin y ~/.local/bin
mkdir -p "$HOME/.local/bin"
cp "$BUILD_DIR/FanMaster" "$HOME/.local/bin/fanmaster"
cp "$BUILD_DIR/FanMaster" "$CLI_TARGET" 2>/dev/null || sudo cp "$BUILD_DIR/FanMaster" "$CLI_TARGET"
chmod 755 "$CLI_TARGET" 2>/dev/null || true

# 6. Configurar auto-inicio minimizado en la barra de menús (LaunchAgent)
echo "🚀 Configurando auto-inicio minimizado en la barra superior…"
mkdir -p "$HOME/Library/LaunchAgents"
cat << 'AGENT_PLIST' > "$HOME/Library/LaunchAgents/com.fanmaster.app.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.fanmaster.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/FanMaster.app/Contents/MacOS/FanMaster</string>
        <string>--minimized</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
AGENT_PLIST
chmod 644 "$HOME/Library/LaunchAgents/com.fanmaster.app.plist"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║  🎉 ¡INSTALACIÓN COMPLETADA!                              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Auto-inicio minimizado configurado en ~/Library/LaunchAgents/com.fanmaster.app.plist"
echo ""
echo "🚀 Para activar el control automático de ventilador permanente con Root:"
echo ""
echo "   sudo cp \"$SCRIPT_DIR/Resources/com.fanmaster.daemon.plist\" /Library/LaunchDaemons/"
echo "   sudo launchctl load -w /Library/LaunchDaemons/com.fanmaster.daemon.plist"
echo ""
