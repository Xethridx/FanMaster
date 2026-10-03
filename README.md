# 🌡️ FanMaster — Mac mini 2012 (Native Menu Bar & Fan Control)

**FanMaster** es una aplicación nativa para macOS diseñada específicamente para monitorear temperaturas de hardware y controlar de forma inteligente el ventilador de tu Mac mini (Late 2012, Intel Core i7/i5).

Se ejecuta exactamente como **Macs Fan Control**:
- 📌 **Residente en la Barra de Menús**: Muestra lectura en tiempo real de temperatura máxima y RPM (`🔥 85°C  🌀 2100`).
- ⚡ **Sin Ventanas Molestas ni Dock**: Se ejecuta en segundo plano sin ocupar espacio en el Dock (`LSUIElement`).
- 🎛️ **Menú Rápido**: Cambia entre perfiles (*Silencioso, Equilibrado, Rendimiento, Máximo, Apple Auto*) directamente desde la barra superior.
- 📊 **Panel de Control Nativo**: Ventana flotante con gráficos interactivos en tiempo real, velocímetro de RPM, tabla de sensores y editor visual de curvas térmicas.

---

## 🚀 Instalación y Compilación

Desde la carpeta del proyecto en `/Users/mac/Documents/FanMaster/`:

```bash
cd /Users/mac/Documents/FanMaster
./install.sh
```

El script compilará el código Swift nativo contra el SDK de macOS, creará el paquete `/Applications/FanMaster.app` y la utilidad de terminal `~/.local/bin/fanmaster`.

---

## 🔐 Permisos de Hardware (Control de Ventiladores)

En macOS, la lectura de temperaturas es pública, pero **escribir velocidades en el SMC requiere privilegios de administrador**.

Para que la app en la barra de menús pueda ajustar los ventiladores automáticamente sin pedir contraseña cada vez:

```bash
sudo chown root:wheel /Applications/FanMaster.app/Contents/MacOS/FanMaster
sudo chmod 4755 /Applications/FanMaster.app/Contents/MacOS/FanMaster
```

*(El bit SUID `4755` permite que `FanMaster.app` se comunique con el AppleSMC con permisos de root directamente al hacer doble clic o al iniciar sesión).*

---

## 💡 Cómo Usarlo

### 1. Como App Nativa de Barra de Menús
- Abre **Spotlight** (`Cmd + Espacio`) y escribe `FanMaster`.
- O desde la terminal:
  ```bash
  open /Applications/FanMaster.app
  ```
- Verás el icono en la barra superior derecha con la temperatura y velocidad actual.
- Haz clic en él para seleccionar perfiles o pulsa **"Abrir Panel de Control…"** para ver el panel completo.

### 2. Iniciar Automáticamente al Encender el Mac
1. Abre **Ajustes del Sistema** > **General** > **Ítems de inicio**.
2. Haz clic en **+** y selecciona `/Applications/FanMaster.app`.

### 3. Modo Terminal (CLI)
Si prefieres ver la consola en una terminal:
```bash
sudo fanmaster --cli
```

---

## 🛠️ Arquitectura Técnica

- **Lenguaje**: Swift 5.8+ (compilado directamente con `swiftc` sin necesidad de la pesada suite Xcode.app).
- **Control Hardware**: IOKit (`AppleSMC` driver, decodificación exacta `sp78` para temperaturas y `fpe2` de 14 bits para RPM de ventiladores).
- **Interfaz Nativa**: `AppKit` (`NSStatusItem`, `NSMenu`, `NSWindow`) + `WebKit` (`WKWebView`).
- **Servidor Interno**: Servidor POSIX sockets HTTP ultra liviano en `localhost:7474` para comunicación bidireccional reactiva.
