# NotchTubeAudio (NotchClip)

**Gestor del Portapapeles en el Notch para macOS con Arquitectura Modular de Plugins (`ClipboardFeaturePlugin` + `FeatureRegistry`).**

Aplicación nativa de macOS que vive en la barra de menús y convierte el notch de la cámara en un **centro inteligente del portapapeles** con historial persistente, búsqueda instantánea, filtros por tipo, fijado de elementos (*pin*) y un ecosistema extensible de **módulos independientes**.

Cada vez que copias texto, enlaces, archivos, colores, JSON o imágenes:
1. El elemento se registra automáticamente en el historial del portapapeles (con deduplicación SHA-256 y exclusión automática de contraseñas/datos confidenciales).
2. El catálogo central (`FeatureRegistry`) evalúa los plugins habilitados por orden de prioridad.
3. Si un módulo activo está configurado con aviso automático (`.automaticPrompt`, como **YouTube Audio**), el notch se despliega al instante con su interfaz interactiva.
4. Al acercar el cursor al notch aparece el panel con pestañas dinámicas (**Portapapeles** y paneles de actividad como **Descargas**), donde cada fila muestra las **acciones rápidas** (`quickActions`) de todos los módulos compatibles.

```
┌────────────────────────────────── notch ──────────────────────────────────┐
│  [📋 Portapapeles (12)]   [🎵 YouTube Audio · 1]                          │
│  🔍 Buscar en el portapapeles…   [Todo] [Texto] [Enlaces] [Archivos] [📌] │
│  ───────────────────────────────────────────────────────────────────────  │
│  🔗 youtube.com/watch?v=dQw4w9WgXcQ&utm_source=share                      │
│     [⬇️ MP3] [〰️ WAV] [✨ Limpiar URL]                       [📌] [📋] [✕] │
│  { } {"user":"ada","roles":["admin"]}                                     │
│     [{} Prettify JSON] [↘↖ Minify JSON]                      [📌] [📋] [✕] │
│  🎨 #FF5733                                                               │
│     [🎨 RGB] [# HEX] [🐦 SwiftUI Color]                      [📌] [📋] [✕] │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Módulos Integrados (Built-in Plugins)

Todos los módulos implementan el protocolo `ClipboardFeaturePlugin` y pueden activarse, desactivarse o cambiar su modo de disparo (`.automaticPrompt` vs `.historyActionOnly`) desde **Ajustes → Módulos (`⌘,`)**:

| Módulo | ID | Prioridad | Disparo por defecto | Qué hace |
|---|---|---|---|---|
| **YouTube Audio** (`YouTubeAudioFeaturePlugin`) | `com.notchclip.plugin.youtube-audio` | `.high` | `.automaticPrompt` | Detecta enlaces de YouTube (`watch`, `youtu.be`, `shorts`, `music`), resuelve título/canal/miniatura vía oEmbed, muestra prompt MP3/WAV en el notch y gestiona la cola de descargas con `yt-dlp` y `ffmpeg`. |
| **Limpiador de URLs** (`URLCleanerFeaturePlugin`) | `com.notchclip.plugin.url-cleaner` | `.normal` | `.historyActionOnly` | Detecta enlaces con parámetros de rastreo (`utm_*`, `fbclid`, `gclid`, `igshid`, `si`, `mc_eid`, `_hsenc`, `mkt_tok`, etc.) y permite limpiarlos preservando los query params legítimos. |
| **Formateador JSON** (`JSONFormatterFeaturePlugin`) | `com.notchclip.plugin.json-formatter` | `.normal` | `.historyActionOnly` | Detecta documentos JSON válidos (`{...}` o `[...]`) y expone acciones rápidas para **Prettify JSON** (2 espacios, claves ordenadas) y **Minify JSON** (una línea compacta). |
| **Conversor de Color** (`ColorConverterFeaturePlugin`) | `com.notchclip.plugin.color-converter` | `.low` | `.historyActionOnly` | Detecta colores en texto (`#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(r, g, b)`) y los convierte con un clic a **RGB**, **HEX** o **SwiftUI `Color`**. |

---

## Arquitectura

### Diagrama de Flujo del Sistema

```
NSPasteboard.general
        │
        ▼ (Timer 0.6s · changeCount + filtro confidencial)
ClipboardMonitor ──(ClipboardItem)──▶ AppState (Orquestador @MainActor)
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   ▼                                           ▼
        ClipboardHistoryStore                           FeatureRegistry
   (Deduplicación SHA-256, Pinning,              (Catálogo y Router de Plugins)
    Búsqueda, Filtros, Persistencia JSON)                      │
                                                               ▼
                                                 [any ClipboardFeaturePlugin]
                                                 ├── YouTubeAudioFeaturePlugin (.high)
                                                 ├── URLCleanerFeaturePlugin   (.normal)
                                                 ├── JSONFormatterFeaturePlugin(.normal)
                                                 └── ColorConverterFeaturePlugin(.low)
```

### Estructura de Directorios

```
Sources/NotchTubeAudio/
├── App/
│   ├── NotchTubeAudioApp.swift          # @main, MenuBarExtra + Settings scene
│   ├── AppDelegate.swift                # ciclo de vida AppKit, activación accessory
│   └── AppEnvironment.swift             # composition root (registra plugins y servicios)
├── Features/
│   ├── ClipboardFeaturePlugin.swift     # protocolo base de plugins + prioridades + trigger behaviors
│   ├── FeatureModels.swift              # FeatureQuickAction, FeatureActionContext, notificaciones
│   ├── FeatureRegistry.swift            # catálogo observable, ciclo de vida y enrutamiento por prioridad
│   ├── YouTubeAudio/                    # módulo completo de descarga de audio de YouTube
│   ├── URLCleaner/
│   │   └── URLCleanerFeaturePlugin.swift
│   ├── JSONFormatter/
│   │   └── JSONFormatterFeaturePlugin.swift
│   └── ColorConverter/
│       └── ColorConverterFeaturePlugin.swift
├── Models/
│   ├── ClipboardItem.swift              # modelo universal con metadatos, app origen y detectedFeatureIDs
│   ├── ClipboardPayload.swift           # .text, .url, .files, .image + clasificación semántica
│   └── NotchMode.swift                  # .idle | .promptingFeature | .showingPanel(tab:)
├── State/
│   └── AppState.swift                   # orquestador entre historial, plugins y presentación del notch
├── Services/
│   ├── ClipboardMonitor.swift           # monitor universal de NSPasteboard + exclusión confidencial
│   ├── PasteboardReader.swift           # abstracción testeable del portapapeles de macOS
│   ├── ClipboardHistoryStore.swift      # motor de historial en memoria + búsqueda, filtros y fijados
│   ├── ClipboardStorage.swift           # persistencia atómica en Application Support + blobs de imagen
│   ├── NotchController.swift            # DynamicNotchKit + monitor global/local de proximidad del ratón
│   ├── NotchGeometry.swift              # cálculo de trigger zone y retention zone
│   ├── BinaryLocator.swift              # validación y autodetección de yt-dlp y ffmpeg
│   └── LineAccumulator.swift            # acumulador thread-safe de líneas de stdout/stderr
├── Settings/
│   └── SettingsManager.swift            # preferencias globales + estado por plugin en UserDefaults
├── Views/
│   ├── NotchRootView.swift              # contenedor raíz del notch (prompts + pestañas dinámicas)
│   ├── NotchHeaderTabsView.swift        # barra de pestañas en el notch (Portapapeles + Actividad)
│   ├── MenuBarContent.swift             # menú desplegable con últimos ítems copiados y acciones rápidas
│   ├── SettingsView.swift               # ventana de Ajustes modular (Portapapeles y General | Módulos)
│   ├── Clipboard/                       # ClipboardHistoryView, filas, badges de plugins y filtros
│   └── Settings/                        # PluginsSettingsTabView
└── Utilities/
    ├── FileActions.swift
    └── Logging.swift
```

---

## Cómo implementar una nueva funcionalidad (`ClipboardFeaturePlugin`)

La arquitectura está diseñada para que añadir una nueva herramienta al portapapeles **no requiera modificar `AppState`, `ClipboardMonitor`, `ClipboardHistoryView` ni `SettingsView`**.

### Paso 1: Crear el plugin implementando `ClipboardFeaturePlugin`

Crea un archivo en `Sources/NotchTubeAudio/Features/MiPlugin/UppercaseFeaturePlugin.swift` (plantilla mínima de ~40 líneas):

```swift
import Foundation
import SwiftUI

@MainActor
final class UppercaseFeaturePlugin: ClipboardFeaturePlugin {
    let id = "com.notchclip.plugin.uppercase"
    let displayName = "Convertir a Mayúsculas"
    let summary = "Transforma cualquier texto copiado a mayúsculas con un clic desde el historial."
    let iconSystemName = "textformat.abc"
    let priority: FeaturePriority = .low
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly

    func canHandle(_ item: ClipboardItem) -> Bool {
        guard case .text(let text) = item.payload else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != trimmed.uppercased()
    }

    func quickActions(for item: ClipboardItem, context: FeatureActionContext) -> [FeatureQuickAction] {
        guard case .text(let text) = item.payload else { return [] }
        return [
            FeatureQuickAction(
                id: "\(id).upper.\(item.id.uuidString)",
                pluginID: id,
                title: "MAYÚSCULAS",
                iconSystemName: "textformat.abc"
            ) {
                context.writeToClipboard(.text(text.uppercased()))
                context.notifyUser(message: "Texto en mayúsculas copiado", icon: "textformat.abc")
            }
        ]
    }
}
```

### Paso 2: Registrarlo en `AppEnvironment.swift` en 1 línea

En `Sources/NotchTubeAudio/App/AppEnvironment.swift`, registra tu nuevo módulo en `featureRegistry`:

```swift
featureRegistry.register(UppercaseFeaturePlugin())
```

¡Listo! Al registrarlo:
- Aparecerá automáticamente en **Ajustes → Módulos** con su interruptor de activación.
- Cuando el usuario copie un ítem compatible (`canHandle(_:) == true`), la fila del historial en el notch mostrará su badge y sus botones de `quickActions`.
- Si además implementas `makePromptView(for:context:onComplete:onDismiss:)`, el usuario podrá elegir en Ajustes si desea abrir un prompt automático en el notch al copiar.
- Si el plugin gestiona tareas en segundo plano (`hasActivityPanel = true` y `makeActivityPanelView(context:)`), el notch añadirá automáticamente una pestaña de actividad con contador en tiempo real.
- Si necesita preferencias propias, implementa `makeSettingsView()` y se incrustará dinámicamente en la tarjeta del módulo dentro de Ajustes.

---

## Requisitos

| Componente | Versión / notas |
|---|---|
| macOS | 14.0 Sonoma o superior |
| Xcode | 16 o superior. **No basta con Command Line Tools**: DynamicNotchKit usa el macro `@Entry` de SwiftUI y su plugin se instala con Xcode. |
| Swift | 6.0 (incluido en Xcode 16, strict concurrency checking habilitado) |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | `brew install yt-dlp` *(opcional, requerido solo por el módulo YouTube Audio)* |
| [ffmpeg](https://ffmpeg.org) | `brew install ffmpeg` *(opcional, requerido solo por el módulo YouTube Audio)* |

La app no está sandboxeada (`com.apple.security.app-sandbox = false`) para que el módulo de YouTube Audio pueda lanzar `Process` con `yt-dlp`/`ffmpeg` y escribir en la carpeta de descargas seleccionada.

---

## Compilar y ejecutar

### 1. Script de build (recomendado)

```bash
git clone <este-repositorio> notch-mtube
cd notch-mtube

brew install yt-dlp ffmpeg
chmod +x Scripts/build-app.sh
./Scripts/build-app.sh

open build/NotchTubeAudio.app
```

El script compila el ejecutable, crea `build/NotchTubeAudio.app` con el `Info.plist` (incluido `LSUIElement = YES`, sin icono en el Dock) y lo firma en modo ad-hoc para ejecutarlo localmente.

### 2. Abrir `Package.swift` en Xcode

1. `File > Open…` y selecciona `Package.swift`.
2. Elige el esquema **NotchTubeAudio** y pulsa Run.

### Tests

```bash
swift test
```

La suite de tests unitarios verifica sin tocar la red:
- Captura multimodal del portapapeles y filtrado de tipos confidenciales (`org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`, gestores de contraseñas).
- Historial del portapapeles (`ClipboardHistoryStore`), deduplicación, elementos fijados (*pinned*), límites de retención y persistencia en disco (`ClipboardStorage`).
- Registro, prioridades, activación/desactivación y modos de disparo en `FeatureRegistry`.
- Orquestación de `AppState` entre historial, prompts proactivos y pestañas del notch.
- Plugins integrados (`BuiltInPluginsTests`, `YouTubeURLParserTests`, `DownloadManagerTests`, `ProcessOutputParserTests`).
- Ventana de ajustes modular y menú de barra (`SettingsManagerTests`, `ClipboardNotchUITests`).

---

## Solución de problemas

**«No se encontró yt-dlp/ffmpeg»**
Abre **Ajustes → Módulos → YouTube Audio** y comprueba las rutas, o pulsa **Autodetectar**. Si no necesitas descargar audio de YouTube, puedes desactivar el módulo YouTube Audio en la misma pestaña.

**«HTTP 403: Forbidden» al descargar de YouTube**
YouTube suele bloquear clientes antiguos de `yt-dlp`. El módulo YouTube Audio reintenta automáticamente una vez con `youtube:player_client=web_embedded`. Si el reintento también falla, actualiza las herramientas:

```bash
brew upgrade yt-dlp ffmpeg
```

**El notch no reacciona al hover**
En algunas versiones de macOS los monitores globales de ratón requieren permiso de **Accesibilidad** (Ajustes del Sistema > Privacidad y seguridad > Accesibilidad). Siempre puedes abrir el panel desde el icono de la barra de menús.

**Error al compilar: `plugin for module 'SwiftUIMacros' not found`**
Estás usando Command Line Tools en lugar de Xcode. Ejecuta:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```
