# Guía de Contribución a FanMaster 🤝

¡Gracias por tu interés en contribuir a **FanMaster**! FanMaster es una herramienta de código abierto diseñada para proporcionar monitoreo y control térmico eficiente, universal y elegante para cualquier Mac (Intel y Apple Silicon).

---

## 🛠️ Entorno de Desarrollo y Requisitos

Para compilar y probar FanMaster en tu Mac necesitas:
- macOS 12.0 (Monterey) o superior.
- Xcode Command Line Tools o Xcode instalado (`xcode-select --install`).
- Terminal estándar con `bash` o `zsh`.

### Compilación Local Universal 2

Para compilar y empaquetar la aplicación localmente:
```bash
git clone https://github.com/tu-usuario/FanMaster.git
cd FanMaster
./install.sh
```

El script `install.sh` compila automáticamente un binario **Universal 2** (`x86_64` + `arm64`), crea el paquete `/Applications/FanMaster.app` y registra la herramienta CLI en `/usr/local/bin/fanmaster`.

---

## 📋 ¿Cómo Puedes Contribuir?

### 1. Probar en Modelos de Mac no Validados
Poseemos acceso limitado a modelos de hardware físicos. Si tienes un Mac diferente (ej. iMac con GPU Radeon, Mac Pro, Mac Studio M-Series, MacBook Air M1/M2/M3), puedes generar un reporte de compatibilidad ejecutando:
```bash
fanmaster --diagnostics
```
O desde la pestaña de **Configuración** de la aplicación web, haciendo clic en **"Copiar Reporte de Compatibilidad"** y pegándolo en un nuevo Issue en GitHub.

### 2. Proponer Nuevas Claves de Sensores SMC
Si descubres que tu modelo tiene sensores que no aparecen en la lista:
1. Revisa `Sources/FanMasterCore/SMCReaderWriter.swift`.
2. Añade la tupla de clave de 4 caracteres y nombre descriptivo a `knownTemperatureKeys`.
3. Abre un Pull Request con el nombre del modelo y el resultado de la prueba.

### 3. Crear o Ajustar Perfiles de Ventilación
Los perfiles de ventilación se definen en `Sources/FanMasterCore/Models.swift` con curvas porcentuales relativas (0% a 100%):
```swift
public static var miPerfil: FanProfile {
    FanProfile(
        id: "miPerfil",
        name: "Mi Perfil Personalizado",
        emoji: "⚡️",
        sensorKey: "TC0D",
        curvePoints: [
            CurvePoint(temperature: 40, fanSpeed: 10),
            CurvePoint(temperature: 60, fanSpeed: 35),
            CurvePoint(temperature: 75, fanSpeed: 70),
            CurvePoint(temperature: 85, fanSpeed: 100),
        ]
    )
}
```

### 4. Mejoras en la Interfaz (Frontend)
La interfaz de usuario es una Single-Page Application (SPA) nativa alojada en `Sources/FanMaster/index.html`. Sigue estrictamente las directrices del **Apple Human Interface Guidelines (HIG)**:
- Soporte para Tema Claro, Oscuro y Automático según el sistema.
- Elementos translúcidos con `backdrop-filter: blur()`.
- Fuentes del sistema (`-apple-system`, `SF Pro Display`, `SF Mono`).

---

## 🔀 Flujo de Pull Requests

1. Haz un Fork del repositorio en GitHub.
2. Crea una rama descriptiva para tu cambio:
   ```bash
   git checkout -b feature/soporte-macbook-pro-16
   ```
3. Realiza tus cambios y verifica que compilen sin errores con `./install.sh`.
4. Haz commit siguiendo buenas prácticas:
   ```bash
   git commit -m "feat(smc): agregar claves de sensor térmico para GPU Radeon 5500M"
   ```
5. Haz push a tu fork y abre un Pull Request hacia la rama `main`.

---

## ⚖️ Licencia
Al contribuir a FanMaster, aceptas que tus contribuciones se licencien bajo los términos de la Licencia **MIT**.

