# Estructura del proyecto

## Árbol de carpetas

```
notchtambule/
├── Package.swift                     # Swift Package (macOS 14+, Swift 6)
├── Package.resolved                  # Versión fijada de DynamicNotchKit
├── Info.plist                        # Bundle, LSUIElement, versiones, permisos
├── README.md                         # Definición funcional y descarga
├── Resources/
│   └── AppIcon.icns|svg              # Icono de la app
├── Scripts/
│   └── build-app.sh                  # Compila y crea build/Notchtambule.app
├── .github/workflows/release.yml     # CI de tests, build y publicación
├── Sources/NotchTubeAudio/
│   ├── App/
│   │   ├── NotchTubeAudioApp.swift   # @main, MenuBarExtra + Settings
│   │   ├── AppDelegate.swift         # Ciclo de vida AppKit
│   │   └── AppEnvironment.swift      # Composition root
│   ├── State/
│   │   └── AppState.swift            # Orquestador y máquina de estados
│   ├── Features/
│   │   ├── ClipboardFeaturePlugin.swift
│   │   ├── FeatureModels.swift
│   │   ├── FeatureRegistry.swift
│   │   ├── YouTubeAudio/
│   │   │   ├── YouTubeAudioFeaturePlugin.swift
│   │   │   ├── Models/
│   │   │   ├── Services/
│   │   │   └── Views/
│   │   ├── URLCleaner/
│   │   ├── JSONFormatter/
│   │   └── ColorConverter/
│   ├── Models/
│   │   ├── ClipboardItem.swift
│   │   ├── ClipboardPayload.swift
│   │   └── NotchMode.swift
│   ├── Services/
│   │   ├── AutoPasteService.swift
│   │   ├── BinaryLocator.swift
│   │   ├── ClipboardHistoryStore.swift
│   │   ├── ClipboardMonitor.swift
│   │   ├── ClipboardStorage.swift
│   │   ├── LineAccumulator.swift
│   │   ├── NotchController.swift
│   │   ├── NotchGeometry.swift
│   │   └── PasteboardReader.swift
│   ├── Settings/
│   │   └── SettingsManager.swift
│   ├── Utilities/
│   │   ├── FileActions.swift
│   │   ├── L10n.swift
│   │   └── Logging.swift
│   ├── Views/
│   │   ├── NotchRootView.swift
│   │   ├── NotchHeaderTabsView.swift
│   │   ├── MenuBarContent.swift
│   │   ├── SettingsView.swift
│   │   ├── Clipboard/
│   │   └── Settings/
│   └── Resources/
│       └── Localizable.xcstrings     # Catálogo es/en
├── Tests/NotchTubeAudioTests/        # Swift Testing
└── doc/                              # Esta documentación
```

Las carpetas `build/`, `.build/`, `.swiftpm/` y `dist/` son artefactos generados y están ignoradas por Git.

## Capas y responsabilidades

| Capa | Archivos | Responsabilidad | No debería |
|---|---|---|---|
| **App** | `App/*` | Punto de entrada, ciclo de vida y composición de dependencias. | Contener lógica de negocio. |
| **State** | `State/AppState.swift` | Orquestar captura → historial → módulos → notch. | Conocer detalles de AppKit, SwiftUI o procesos externos. |
| **Features** | `Features/*` | Detectar contenido, producir acciones y vistas de módulo. | Tocar `NSPasteboard` directamente, abrir ventanas o conocer `AppState`. |
| **Models** | `Models/*` | Tipos de dominio compartidos. | Depender de vistas o servicios concretos. |
| **Services** | `Services/*` | Portapapeles, persistencia, pegado automático, notch y procesos. | Conocer módulos concretos. |
| **Settings** | `Settings/SettingsManager.swift` | Preferencias globales y estado por módulo en `UserDefaults`. | Presentar UI. |
| **Views** | `Views/*` | UI del notch, menú y ajustes. | Decidir reglas de negocio. |
| **Utilities** | `Utilities/*` | Localización, logging y acciones de archivos. | Acumular lógica de dominio. |

## Dirección de dependencias

```
App
 └── State ──► Models
      ├─────► Services
      ├─────► Settings
      └─────► Features (solo a través del protocolo y del registry)

Views ──► State / Services / Settings / Models
Features ──► Models + FeatureActionContext
Services ──► Models / Settings (nunca Features)
```

Reglas prácticas:

- Si una vista necesita ejecutar una acción, llama a `AppState` o a un servicio inyectado; no escribas en `NSPasteboard` desde la vista.
- Si un módulo necesita un efecto, pide un `FeatureActionContext`; no importes `NotchController`.
- Si un servicio nuevo necesita avisar a la UI, expón estado observable o un callback y conéctalo en `AppEnvironment`.
- `AppEnvironment` es el único sitio donde se conocen todas las piezas concretas.

## Dónde tocar para cada cambio

| Quiero… | Archivos principales |
|---|---|
| Añadir un módulo | `Features/<Nombre>/`, `AppEnvironment.swift` |
| Añadir una acción rápida a un módulo | `Features/<Nombre>/<Nombre>FeaturePlugin.swift` |
| Abrir un prompt al copiar | `ClipboardFeaturePlugin.makePromptView`, `defaultTriggerBehavior` |
| Añadir una pestaña de actividad | `hasActivityPanel`, `makeActivityPanelView`, `activityPanelTitle`, `activeTasksCount` |
| Añadir ajustes de un módulo | `makeSettingsView()` y una vista propia en `Features/<Nombre>/Views/` |
| Cambiar la ventana de Ajustes | `Views/SettingsView.swift`, `Views/Settings/PluginsSettingsTabView.swift` |
| Cambiar el pegado automático | `Services/AutoPasteService.swift`, `State/AppState.swift` |
| Cambiar la captura del portapapeles | `Services/ClipboardMonitor.swift`, `Services/PasteboardReader.swift` |
| Cambiar el historial o los filtros | `Services/ClipboardHistoryStore.swift`, `Models/ClipboardItem.swift` |
| Cambiar la persistencia | `Services/ClipboardStorage.swift` |
| Cambiar la geometría o timers del notch | `Services/NotchController.swift`, `Services/NotchGeometry.swift` |
| Cambiar textos | `Resources/Localizable.xcstrings` y `Utilities/L10n.swift` |
| Cambiar versión o empaquetado | `Info.plist`, `Scripts/build-app.sh`, `.github/workflows/release.yml` |

## Recursos y bundle

Swift Package procesa `Sources/NotchTubeAudio/Resources` como `Bundle.module`. `L10n` busca `Localizable.xcstrings` primero en ese bundle y, si no existe, en el árbol de fuentes (útil para tests y para ejecutar con SwiftPM).

`Scripts/build-app.sh` copia:

- el ejecutable `NotchTubeAudio` como `Contents/MacOS/Notchtambule`,
- el bundle de recursos `NotchTubeAudio_NotchTubeAudio.bundle`,
- `Resources/AppIcon.icns`,
- `Info.plist` con la versión y el build number inyectados.

## Tests

`Tests/NotchTubeAudioTests` contiene una suite por área:

| Archivo | Cubre |
|---|---|
| `AppStateOrchestrationTests` | Flujo de captura, prompts y pestañas. |
| `AutoPasteServiceTests` | Permisos, foco, `⌘V` y degradación a solo copiar. |
| `BuiltInPluginsTests` | Detección y acciones de los módulos integrados. |
| `ClipboardHistoryStoreTests` | Historial, deduplicación, pin, retención y búsqueda. |
| `ClipboardMonitorTests` | Polling, tipos confidenciales y captura forzada. |
| `ClipboardNotchUITests` | Composición de la UI del notch y ajustes. |
| `DownloadManagerTests` | Cola, concurrencia, reintentos y errores. |
| `FeatureRegistryTests` | Registro, prioridades, lifecycle y trigger behavior. |
| `LocalizationTests` | Catálogo, claves y pseudolocalización. |
| `ProcessOutputParserTests` | Parseo de progreso y errores de `yt-dlp`. |
| `SettingsManagerTests` | Persistencia y límites de preferencias. |
| `YouTubeURLParserTests` | Formatos de URL de YouTube. |
