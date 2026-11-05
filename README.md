<div align="center">

# 🌡️ FanMaster
### Control Inteligente de Ventiladores y Monitoreo Térmico Universal para macOS

[![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue?logo=apple&logoColor=white)](https://apple.com/macos)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%202%20(Intel%20%2B%20Apple%20Silicon)-brightgreen)](#compatibilidad)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift&logoColor=white)](https://swift.org)
[![Build Status](https://img.shields.io/badge/Build-Passing-success)](.github/workflows/build-and-release.yml)

**FanMaster** es una aplicación nativa, ligera y moderna para macOS diseñada para reemplazar soluciones obsoletas o de pago. Ofrece monitoreo en tiempo real de temperaturas y control inteligente de curvas de ventilación mediante **AppleSMC** y **Apple Silicon IOHID**, adaptándose con precisión matemática a las características físicas de cualquier Mac.

[Descargar Última Versión (.dmg)](../../releases) • [Reportar Hardware](.github/ISSUE_TEMPLATE/sensor_report.yml) • [Guía de Contribución](CONTRIBUTING.md)

</div>

---

## ✨ Características Principales

* 📌 **Residente en la Barra de Menús**: Visualiza en tiempo real la temperatura del núcleo y las RPM sin ocupar espacio en el Dock (`LSUIElement`).
* 🚀 **Binario Nativo Universal 2**: Compilado nativamente tanto para **Intel (`x86_64`)** como para **Apple Silicon (`arm64`)** sin capas de emulación.
* 🌪️ **Abstracción Universal de Ventiladores**:
  * **0 Ventiladores (Fanless)**: Detección inteligente de MacBook Air M-Series, mostrando telemetría térmica en modo pasivo silencioso (0 dB).
  * **1 Ventilador**: Control gradual y suave con histéresis anti-ruido (Mac mini, MacBook Pro 13").
  * **N Ventiladores (Multi-fan)**: Gestión simultánea o independiente de ventiladores CPU y GPU (MacBook Pro 15"/16", iMac, Mac Studio).
* 📈 **Curvas Térmicas Relativas (0% – 100%)**: En lugar de valores fijos en RPM, las curvas modulan un porcentaje relativo que se escala automáticamente a los límites físicos (`minRPM` a `maxRPM`) de cada modelo.
* 🌡️ **Motor Térmico Dual**:
  * **Intel AppleSMC**: Catálogo extendido con más de 75 claves de sensores (CPU Die, Cores 0–9, GPU dedicada/integrada, RAM, PCH, Thunderbolt, Batería, etc.).
  * **Apple Silicon IOHID**: Acceso nativo a los clústeres térmicos de Rendimiento (P-Cores), Eficiencia (E-Cores), GPU, ANE y SoC en procesadores M1/M2/M3/M4.
* 🎨 **Diseño Apple Human Interface (HIG)**:
  * Soporte completo para **Tema Claro, Tema Oscuro y Automático**.
  * Gráfico Bezier interactivo en tiempo real con indicador luminoso dinámico (`Live Dot`).
  * Interfaz translúcida ultraligera construida con WebKit nativo.
* 🛡️ **Servicio Daemon de Fondo**: Incluye `LaunchDaemon` opcional con permisos de Root para mantener las curvas activas incluso con la sesión cerrada o la pantalla bloqueada.
* 📋 **Herramienta de Diagnóstico Comunitario**: Genera un informe Markdown completo con un solo clic o comando (`fanmaster --diagnostics`).

---

## 🖥️ Matriz de Compatibilidad

| Familia de Mac | Arquitectura | Topología de Ventiladores | Soporte FanMaster |
| :--- | :---: | :---: | :---: |
| **Mac mini** (2012 – 2018) | Intel x86_64 | 1 Ventilador | ✅ Completo |
| **Mac mini** (M1 / M2 / Pro) | Apple Silicon arm64 | 1 Ventilador | ✅ Completo |
| **MacBook Air** (Intel) | Intel x86_64 | 1 Ventilador | ✅ Completo |
| **MacBook Air** (M1 / M2 / M3) | Apple Silicon arm64 | **0 Ventiladores (Pasivo)** | ✅ Modo Fanless (0 dB) |
| **MacBook Pro** (13", 14", 15", 16") | Intel & Apple Silicon | 1 o 2 Ventiladores (CPU + GPU) | ✅ Control Enlazado / Dual |
| **iMac & iMac Pro** (21.5", 24", 27") | Intel & Apple Silicon | 1 a 3 Ventiladores | ✅ Completo |
| **Mac Studio & Mac Pro** | Intel & Apple Silicon | 2+ Ventiladores de alto flujo | ✅ Completo |

---

## 📲 Instalación

### Opción 1: Descargar Imagen de Disco (.dmg) — Recomendado
1. Descarga el archivo **`FanMaster-Universal.dmg`** desde la sección de [Releases](../../releases).
2. Abre la imagen de disco y arrastra `FanMaster.app` a tu carpeta `/Applications`.
3. *(Opcional)* Si Gatekeeper te advierte sobre una aplicación de un desarrollador no identificado, ejecuta en tu terminal:
   ```bash
   xattr -cr /Applications/FanMaster.app
   ```

### Opción 2: Compilación Local desde el Código Fuente
Requiere tener instalado Xcode Command Line Tools (`xcode-select --install`):
```bash
git clone https://github.com/tu-usuario/FanMaster.git
cd FanMaster
./install.sh
```

El instalador compila el binario Universal 2, instala la app en `/Applications`, la utilidad en `/usr/local/bin/fanmaster` y configura el auto-inicio minimizado en la barra de menús.

---

## 🔐 Privilegios de Control de Ventiladores (Root / Daemon)

En macOS, cualquier aplicación puede **leer** temperaturas sin permisos especiales. Sin embargo, **escribir velocidades objetivo en el SMC o IOKit requiere privilegios de Root**.

* **Sin Root (Modo Monitor)**: FanMaster funciona inmediatamente mostrando todas las temperaturas, el uso de CPU y las RPM actuales sin alterar los ventiladores de macOS.
* **Con Root (Control Pleno)**: Para que FanMaster regule las velocidades y aplique tus curvas personalizadas de forma desatendida y segura, activa el daemon de fondo permanente:

```bash
sudo cp /Applications/FanMaster.app/Contents/Resources/com.fanmaster.daemon.plist /Library/LaunchDaemons/ 2>/dev/null || \
sudo cp Resources/com.fanmaster.daemon.plist /Library/LaunchDaemons/
sudo launchctl load -w /Library/LaunchDaemons/com.fanmaster.daemon.plist
```

---

## ⌨️ Uso desde Terminal (CLI)

FanMaster incluye un potente ejecutable de línea de comandos en `/usr/local/bin/fanmaster`:

```bash
# Iniciar FanMaster en modo demonio / servidor web local:
fanmaster --cli

# Generar un reporte completo de diagnóstico y compatibilidad de tu hardware:
fanmaster --diagnostics

# Iniciar la app nativa minimizada en la barra de menús:
fanmaster --minimized
```

---

## 📋 Reporte de Compatibilidad y Diagnóstico

¿Estás usando FanMaster en un modelo de Mac nuevo o diferente? Puedes ayudarnos a validar la compatibilidad en segundos:

1. Ejecuta `fanmaster --diagnostics` en tu terminal, o haz clic en **"📋 Copiar Reporte"** en la pestaña de **Configuración** de la aplicación.
2. Abre un nuevo issue en GitHub utilizando la plantilla [Reporte de Compatibilidad](.github/ISSUE_TEMPLATE/sensor_report.yml) y pega el resultado.

---

## 🤝 Contribuciones

Las contribuciones son bienvenidas y muy apreciadas. Por favor lee [CONTRIBUTING.md](CONTRIBUTING.md) para conocer las pautas de desarrollo, estilos de código y el flujo de trabajo para enviar Pull Requests.

---

## ⚖️ Licencia

Distribuido bajo la Licencia **MIT**. Consulta [`LICENSE`](LICENSE) para obtener más detalles.
