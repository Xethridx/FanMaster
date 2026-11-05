#!/bin/bash
# FanMaster — Script para generar imagen de disco (.dmg) distribuible
# Uso: ./scripts/create-dmg.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
DMG_STAGING="$SCRIPT_DIR/.dmg_staging"
OUTPUT_DMG="$SCRIPT_DIR/FanMaster-Universal.dmg"
APP_BUNDLE="$SCRIPT_DIR/FanMaster.app"

echo "🎨 Creando imagen de disco DMG para FanMaster..."

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ FanMaster.app no existe. Ejecuta primero ./install.sh para compilarlo."
    exit 1
fi

rm -rf "$DMG_STAGING" "$OUTPUT_DMG"
mkdir -p "$DMG_STAGING"

echo "📦 Copiando FanMaster.app..."
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

echo "🔗 Creando enlace a /Applications..."
ln -s /Applications "$DMG_STAGING/Applications"

echo "💿 Empaquetando DMG con compresión UDZO..."
hdiutil create \
    -volname "FanMaster" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG"

rm -rf "$DMG_STAGING"

echo "✅ DMG creado exitosamente:"
echo "   $OUTPUT_DMG ($(du -h "$OUTPUT_DMG" | awk '{print $1}'))"

