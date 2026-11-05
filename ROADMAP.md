# 🗺️ Plan de Análisis y Hoja de Ruta (Roadmap) — FanMaster Universal para macOS

> **Documento de Arquitectura y Planificación de Ingeniería**  
> **Objetivo:** Transformar FanMaster de una herramienta calibrada para Mac mini 2012 en una suite abierta, universal y moderna para cualquier Mac (Intel y Apple Silicon M1/M2/M3/M4), lista para publicación comunitaria en GitHub.

---

## 1. Resumen Ejecutivo y Visión del Proyecto

**FanMaster** nació como una solución ligera, nativa y de alto rendimiento en Swift + WebKit para regular ventiladores y monitorear temperaturas vía SMC. Para convertirse en un referente open-source (alternativa nativa y moderna a *Macs Fan Control*), la aplicación debe abstraerse completamente del modelo de hardware subyacente y operar sin fricción en:
1. **Macs Intel legacy (2010–2017):** SMC clásico de 1 o 2 ventiladores.
2. **Macs Intel con chip T2 (2018–2020):** SMC intermediado por bridgeOS.
3. **Macs Apple Silicon (M1, M2, M3, M4):** Arquitectura ARM64, sensores térmicos IOHID y modelos con ventilación activa (Pro, Max, Studio) o pasiva/fanless (MacBook Air).

```
                      ┌────────────────────────────────────────┐
                      │          FanMaster Universal           │
                      └───────────────────┬────────────────────┘
                                          │
            ┌─────────────────────────────┼─────────────────────────────┐
            ▼                             ▼                             ▼
   ┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
   │   Macs Intel     │          │    Macs con T2   │          │  Apple Silicon   │
   │  (2010 – 2017)   │          │  (2018 – 2020)   │          │  (M1 – M4 Pro)   │
   ├──────────────────┤          ├──────────────────┤          ├──────────────────┤
   │ • AppleSMC puro  │          │ • BridgeOS SMC   │          │ • IOHID Events   │
   │ • Claves fijas   │          │ • Permisos T2    │          │ • ARM64 nativo   │
   │ • 1 a 2 fans     │          │ • Fallback seguro│          │ • 0 a 2 fans     │
   └──────────────────┘          └──────────────────┘          └──────────────────┘
```

---

## 2. Diagnóstico del Estado Actual vs. Estado Objetivo

| Componente | Estado Actual (Mac mini 2012) | Estado Objetivo (Universal) |
| :--- | :--- | :--- |
| **Arquitectura de Compilación** | `x86_64` estricto en `install.sh`. | **Universal 2** (`x86_64` + `arm64`) empaquetado vía `lipo`. |
| **Identificación de Hardware** | Texto estático en HTML y consola (`Macmini6,1/6,2`). | Detección dinámica vía `sysctl` (`hw.model`) y resolución de modelo comercial. |
| **Topología de Ventiladores** | Asume 1 ventilador fijo (`fans[0]`). | Dinámico: **0 ventiladores** (modo pasivo), **1 ventilador** o **N ventiladores** (independientes o enlazados). |
| **Curvas y Regulación de RPM** | Rangos fijos de 1,800 a 5,500 RPM. | Curvas relativas por **porcentaje (0% – 100%)** adaptadas al `minRPM` y `maxRPM` de cada máquina. |
| **Catálogo de Sensores** | 20 claves SMC de CPU/PCH Ivy Bridge. | Detección dinámica con catálogo ampliado (~80 claves Intel) + motor térmico `IOHIDEventSystemClient` para Apple Silicon. |
| **Distribución y GitHub** | Script local manual sin releases. | Pipeline CI/CD en GitHub Actions con releases automáticos de `.dmg` firmados *ad-hoc*. |

---

## 3. Roadmap de Implementación Dividido en Sprints

```
Sprint 1: Cimientos de Universalidad y Binario Universal 2
   ├── Compilación lipo (x86_64 + arm64)
   └── Detección dinámica de hardware y API
Sprint 2: Abstracción de Ventiladores y Curvas Relativas
   ├── Soporte 0, 1 y N ventiladores (UI Fanless / Multi-fan)
   └── Curvas de ventilación en porcentaje (0% - 100%)
Sprint 3: Motor Térmico Ampliado (Intel + Apple Silicon)
   ├── Diccionario extendido de sensores Intel
   └── Integración IOHID para Apple Silicon
Sprint 4: Empaquetado Open Source, CI/CD y Documentación
   ├── Licencia MIT y Guías de Contribución
   └── Workflow de GitHub Actions y generador de DMG
Sprint 5: Robustez, Hardening y Pruebas en Hardware Real
   ├── Tolerancia a fallos en chips T2 / M-Series
   └── Telemetría de diagnóstico y reportes de compatibilidad
```

---

### 🏃 Sprint 1: Cimientos de Universalidad y Binario Universal 2 (✅ COMPLETADO)
**Objetivo:** Permitir que el código se compile y ejecute nativamente en cualquier arquitectura de Mac y detecte el equipo real del usuario sin textos fijos.

* **Tarea 1.1 — Compilación Universal 2 en `install.sh` (✅):**
  - Configuración de compilación dual con `swiftc`:
    - Slice Intel: `-target x86_64-apple-macos12.0`
    - Slice Apple Silicon: `-target arm64-apple-macos12.0`
  - Unificación con `lipo -create -output FanMaster`.
  - Validación de arquitectura: `Mach-O universal binary with 2 architectures: [x86_64] [arm64]`.
* **Tarea 1.2 — Proveedor de Información de Hardware (`SystemInfo.swift`) (✅):**
  - Módulo que lee `sysctlbyname("hw.model")` y `sysctlbyname("machdep.cpu.brand_string")`.
  - Mapeo completo a nombres comerciales (Mac mini, MacBook Pro/Air, iMac, Mac Studio, Mac Pro).
* **Tarea 1.3 — Actualización de la API `/api/status` (✅):**
  - Expone el objeto `system` con `modelIdentifier`, `modelName`, `architecture`, `processor` y `osVersion`.
* **Tarea 1.4 — Frontend Reactivo en `index.html` (✅):**
  - Encabezado y panel de configuración actualizan automáticamente el modelo y arquitectura detectados.
* **Tarea 1.5 — Universalización de Rutas en `HTML.swift` (✅):**
  - Eliminación de rutas fijas de usuario, incorporando búsqueda en runtime en CWD, Bundle de app y `/usr/local/share/fanmaster/`.

---

### 🏃 Sprint 2: Abstracción de Ventiladores y Curvas Relativas (✅ COMPLETADO)
**Objetivo:** Adaptar el control y visualización para cualquier número de ventiladores (incluyendo portátiles pasivos) y evitar sobre-revolucionar o forzar valores inválidos de RPM.

* **Tarea 2.1 — Normalización de Curvas Térmicas por Porcentaje (✅):**
  - Reestructurado el cálculo en `FanProfile` y `CurvePoint`: puntos definidos por porcentaje de potencia (0% – 100%).
  - Cálculo adaptativo dinámico en tiempo de ejecución:
    $$\text{Target RPM} = \text{MinRPM} + (\text{MaxRPM} - \text{MinRPM}) \times \frac{\%}{100}$$
  - Clamping estricto con `Swift.max(minRPM, Swift.min(maxRPM, target))` y retrocompatibilidad total con valores legados en RPM absoluto (> 100).
* **Tarea 2.2 — Soporte para Portátiles Fanless (0 Ventiladores) (✅):**
  - Detección reactiva de equipos pasivos (`fans.isEmpty` / `state.fans.length === 0`).
  - Tarjeta estilizada informativa *"Refrigeración Pasiva (Fanless) — 0 dB"* en la interfaz.
  - Adaptación del menú de barra superior (`AppDelegate`) para mostrar `Pasivo` o solo temperatura sin placeholders vacíos.
* **Tarea 2.3 — Soporte Multi-Ventilador (2 o más Ventiladores) (✅):**
  - Nombrado contextual de ventiladores en `SMCReaderWriter`: *Ventilador Principal*, *Ventilador Izquierdo (CPU)* y *Ventilador Derecho (GPU)*.
  - Selector por pestañas `[Todos (Sync)]` y ventiladores individuales en la interfaz.
  - Desglose dinámico con velocímetros individuales y RPM promedio sincronizado.
* **Tarea 2.4 — Adaptación del Canvas de Curvas (✅):**
  - Eje Y normalizado al 0% – 100% de potencia con marcas de escala y cálculo de RPMs físicos en los puntos de control.
  - Punto de operación en tiempo real (`Live Dot`) ajustado dinámicamente al porcentaje de potencia del ventilador.

---

### 🏃 Sprint 3: Motor Térmico Extendido (Intel + Apple Silicon) (✅ COMPLETADO)
**Objetivo:** Permitir la lectura de sensores de temperatura en cualquier familia de procesadores Mac.

* **Tarea 3.1 — Catálogo Extendido de Claves SMC para Intel (✅):**
  - Se extendió `knownTemperatureKeys` con más de 75 claves estándar de la comunidad:
    - Cores y Dies de CPU: `TC0D`, `TC0E`, `TC0F`, `TC0P`, `TC0H`, `TC0C`..`TC9C`, `TCAD`..`TCDD`, `TCPC`, `TCSA`, `TCTD`, etc.
    - Gráficos integrados y dedicados: `TG0D`, `TG1D`, `TG0P`, `TG1P`, `TG0H`, `TG1H`, `TCGC`, `TGDD`, `TGVP`, `TG0M`, `TG1M`.
    - Chipset, PCH y Thunderbolt: `TP0P`, `TPCD`, `TP0D`, `TI0P`..`TI3P`, `TN0D`, `TN0P`, `Ts0P`, `Ts0S`.
    - Memoria RAM: `TM0P`..`TM3P`, `TM0S`..`TM7S`, `TMA1`..`TMB2`.
    - Chasis, Batería y Disipadores: `TA0P`, `TA1P`, `TW0P`, `TB0T`..`TB3T`, `TL0P`, `Tm0P`, `Th1H`..`Th3H`, `THSP`, `Tp0C`, `Te0t`.
* **Tarea 3.2 — Detección y Lectura Térmica en Apple Silicon (`IOHIDEventSystemClient`) (✅):**
  - Implementado `Sources/FanMasterCore/HIDThermalReader.swift` utilizando carga dinámica con `dlsym` contra `IOKit.framework`.
  - Mapeo automático de `kHIDPage_AppleVendor` (`0xff00`) y `kHIDUsage_AppleVendor_TemperatureSensor` (`0x0005`) para leer núcleos P-Cores, E-Cores, GPU, ANE, SoC y PMU.
  - Formateador humano para nombres amigables de sensores de silicio de Apple.
* **Tarea 3.3 — Selección Inteligente de Sensor Principal (✅):**
  - Soporte para modo `"MAX"` (sensor dinámico más caliente).
  - Algoritmo de fallback multinivel en `SMCReader`:
    1. Coincidencia directa por clave configurada.
    2. Fallbacks de CPU estándar (`TC0D`, `TC0P`, `TC0E`, `TC0C`, `TCAD`, `TC0H`).
    3. Búsqueda por silicio Apple (`pCore`, `eCore`, `SoC`).
    4. Detección por nombre que contenga `die` o `core`.
  - Evita por completo lecturas en blanco o errores `--°C`.

---

### 🏃 Sprint 4: Empaquetado Open Source, CI/CD y Documentación (✅ COMPLETADO)
**Objetivo:** Dejar el repositorio impecable, atractivo y completamente automatizado para la comunidad de GitHub.

* **Tarea 4.1 — Licencia y Archivos de Comunidad (✅):**
  - Añadido archivo `LICENSE` bajo licencia libre **MIT**.
  - Creado `CONTRIBUTING.md` con guías claras para forks, compilación, creación de perfiles y pull requests.
  - Creadas plantillas de GitHub (`.github/ISSUE_TEMPLATE/`):
    - `bug_report.yml`: Reporte estandarizado de errores con modelo y versión de macOS.
    - `sensor_report.yml`: Envío de compatibilidad de hardware por la comunidad.
    - `feature_request.yml`: Propuestas y mejoras.
* **Tarea 4.2 — GitHub Actions CI/CD (`.github/workflows/build-and-release.yml`) (✅):**
  - Pipeline automatizado en máquinas virtuales `macos-14` de GitHub.
  - Compilación dual nativa (`x86_64` + `arm64`) y unificación con `lipo`.
  - Empaquetado automático de `.dmg` y `.zip` adjuntados directamente a cada Release de GitHub (`v*`).
* **Tarea 4.3 — Generador de Imagen de Disco DMG (`scripts/create-dmg.sh`) (✅):**
  - Script independiente que genera `FanMaster-Universal.dmg` comprimido con enlace directo a `/Applications`.
* **Tarea 4.4 — README.md Profesional para GitHub (✅):**
  - Insignias dinámicas de estado (macOS 12+, Universal 2, Licencia MIT, Swift 5.9+, Build Passing).
  - Matriz de compatibilidad detallada (Mac mini, MacBook Air/Pro, iMac, Mac Studio, Mac Pro).
  - Instrucciones de instalación por descarga directa de DMG y compilación local.
  - Explicación de permisos, Gatekeeper (`xattr -cr`) y comandos CLI.

---

### 🏃 Sprint 5: Robustez, Hardening y Diagnóstico Comunitario (✅ COMPLETADO)
**Objetivo:** Garantizar estabilidad impecable, seguridad de permisos, tolerancia a fallos y herramientas de auto-diagnóstico.

* **Tarea 5.1 — Degradación Elegante y Modo Solo Lectura (✅):**
  - Cuando se ejecuta sin privilegios de root o en entornos restringidos (ej. chip Apple T2), la aplicación opera de forma transparente en **Modo Monitor**.
  - Indicador visual adaptativo en la barra superior y en el panel web (`#root-pill`) informando del estado de lectura sin bloquear la telemetría.
  - Detección reactiva de restricciones de escritura (`isWriteRestricted`) en `FanController`.
* **Tarea 5.2 — Generador de Informe de Diagnóstico (`--diagnostics`) (✅):**
  - Comando de terminal implementado: `fanmaster --diagnostics`.
  - Muestra un informe estructurado en Markdown con especificaciones del equipo, procesador, arquitectura, estado de permisos, ventiladores detectados y catálogo completo de sensores térmicos activos.
  - Endpoint `/api/diagnostics` incorporado en el servidor HTTP.
  - Botón interactivo en la pestaña de Configuración: **"📋 Copiar Reporte"** para copiar el informe al portapapeles con un clic.
* **Tarea 5.3 — Manejo de Gatekeeper y Firma Ad-hoc (✅):**
  - Firma profunda ad-hoc integrada en `install.sh`, en el empaquetador DMG y en el flujo de CI/CD.
  - Documentada la resolución de advertencias de Gatekeeper (`xattr -cr /Applications/FanMaster.app`) en el `README.md`.

---

## 4. Matriz de Riesgos y Estrategias de Mitigación

| Riesgo Técnico | Impacto | Probabilidad | Mitigación |
| :--- | :---: | :---: | :--- |
| **Incompatibilidad de escritura en Apple Silicon** | Alto | Media | Utilizar degradación elegante: monitorización completa y control en los modelos con soporte comprobado. |
| **Puntos de RPM fuera de límites en modelos no probados** | Alto | Baja | Normalizar a porcentajes (0–100%) y aplicar clamp estricto con `max(minRPM, min(maxRPM, target))`. |
| **Falta de hardware físico diverso para pruebas** | Medio | Alta | Crear el generador de reportes de diagnóstico en Sprint 5 para que la comunidad de GitHub valide sus modelos. |
| **Rechazo de ejecución por Gatekeeper (sin Developer ID de pago)** | Medio | Alta | Firmar con firma ad-hoc (`codesign -s -`) e incluir instrucción clara de `xattr -cr /Applications/FanMaster.app` en el README. |

---

## 5. Criterios de Aceptación Globales (Definition of Done)

1. **Binario:** La salida de `lipo -info` confirma arquitecturas `x86_64` y `arm64`.
2. **Arranque en cualquier Mac:** La app inicia correctamente en Macs de 0, 1 y 2 ventiladores sin crasheos por índices fuera de rango.
3. **Escalabilidad de Curvas:** Un perfil personalizado al 50% entrega 3,650 RPM en un Mac mini (1800-5500) y 1,950 RPM en un iMac (1200-2700).
4. **Presentación en GitHub:** Repositorio con README ilustrado, licencia MIT y workflow de compilación verde en GitHub Actions.
