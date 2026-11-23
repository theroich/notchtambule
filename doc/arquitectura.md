# Arquitectura

## Principios

1. **Un composition root explícito.** `AppEnvironment` crea y conecta todas las dependencias una sola vez en el main actor. No hay singletons dispersos ni inicializaciones perezosas de servicios globales.
2. **El estado manda en la UI.** `AppState` es la máquina de estados observable. `NotchRootView` solo representa el estado; `NotchController` solo lo lleva a la ventana.
3. **Los módulos no tocan el sistema.** Un módulo no escribe en `NSPasteboard`, no abre el notch y no conoce AppKit más allá de SwiftUI. Usa `FeatureActionContext`.
4. **Todo el código de UI y estado vive en el main actor.** Los procesos externos y los handlers de `Pipe` entregan trabajo al main actor mediante `Task { @MainActor ... }`.
5. **Los tests pueden sustituir el sistema.** `PasteboardReading`, `AutoPasteSystemEnvironment` y `YouTubeMetadataFetching` son protocolos inyectables.

## Composition root

`AppEnvironment` es el composition root de producción y el único sitio donde se conectan todos los servicios. El único otro lugar que construye módulos concretos es el inicializador de compatibilidad `SettingsView(settings:)`, pensado para previews y tests; si añades un módulo, mantenlo sincronizado con ambos.

```swift
let settings = SettingsManager()
let downloads = DownloadManager(settings: settings)
let youtube = YouTubeAudioFeaturePlugin(settings: settings, downloadManager: downloads)
let urlCleaner = URLCleanerFeaturePlugin()
let jsonFormatter = JSONFormatterFeaturePlugin()
let colorConverter = ColorConverterFeaturePlugin()
let ocr = OCRFeaturePlugin()

let clipboard = ClipboardMonitor(settings: settings)
let historyStore = ClipboardHistoryStore(settings: settings, clipboardMonitor: clipboard)
let registry = FeatureRegistry(settings: settings, plugins: [
    youtube, urlCleaner, jsonFormatter, colorConverter, ocr
])

let autoPaste = AutoPasteService()
let appState = AppState(
    settings: settings,
    historyStore: historyStore,
    featureRegistry: registry,
    autoPasteService: autoPaste
)
let notch = NotchController(appState: appState, settings: settings)

appState.presenter = notch
clipboard.onCapture = { [weak appState] item in
    appState?.handleCapturedItem(item)
}
```

Consecuencias:

- Añadir un módulo es añadir una línea al array de `FeatureRegistry`.
- Cambiar un servicio por un mock es cambiar la construcción en este archivo.
- Las vistas de producción reciben `AppEnvironment` (o piezas sueltas) por inyección; no leen singletons.

## Ciclo de vida

```
applicationDidFinishLaunching
  └── AppEnvironment.start()
       ├── NSApp.setActivationPolicy(.accessory)   # sin icono en el Dock
       ├── AutoPasteService.startObservingFrontmostApplications()
       ├── FeatureRegistry.startAllEnabled()       # start() de cada módulo habilitado
       ├── NotchController.start()                 # monitores de ratón + timers
       └── ClipboardMonitor.start()                # polling del portapapeles

applicationWillTerminate
  └── AppEnvironment.shutdown()
       ├── ClipboardMonitor.stop()
       ├── NotchController.stop()
       ├── AutoPasteService.stopObservingFrontmostApplications()
       ├── AppState.shutdown()                     # shutdown de módulos + flush del historial
       └── DownloadManager.terminateAllProcesses()
```

`LSUIElement = true` en `Info.plist` hace que la app sea solo de barra de menús. El `AppDelegate` también fija `.accessory` para que `swift run` se comporte igual.

## Flujo de captura del portapapeles

```
NSPasteboard.general
        │  Timer 0.6 s · cambio de changeCount
        ▼
ClipboardMonitor.poll()
        │  ignora: cambio propio, marcador interno, tipos confidenciales
        │  extrae: archivos > imagen PNG/TIFF > URL http(s) > texto
        │  deduplica copias consecutivas por contentHash
        ▼
ClipboardItem
        │  onCapture
        ▼
AppState.handleCapturedItem(item)
        │
        ├── FeatureRegistry.matchingPlugins(for:)      # habilitados + canHandle
        ├── item.detectedFeatureIDs = ids              # anotación para badges y acciones
        ├── ClipboardHistoryStore.record(item)         # dedupe, pin, retención, persistencia
        └── FeatureRegistry.primaryPromptPlugin(for:)  # mayor prioridad con .automaticPrompt
                 │
                 ├── sí: AutoPasteService.rememberFrontmostApp()
                 │       notchMode = .promptingFeature(...)
                 │       presenter.presentPrompt()
                 └── no: el elemento queda en el historial sin abrir el notch
```

Detalles relevantes:

- **Arranque:** `ClipboardMonitor.start()` registra el `changeCount` actual. Lo que ya estaba copiado al abrir la app no se captura.
- **Escrituras propias:** `ClipboardHistoryStore.copyToPasteboard(_:)` llama a `ignoreNextChangeCount()` antes y después de escribir, para que el monitor no vuelva a capturar el elemento y no dispare un prompt.
- **Confidencialidad:** si `settings.ignoreConfidentialPasteboardTypes` está activo, se descartan los tipos `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` y los marcadores habituales de gestores de contraseñas.
- **Deduplicación:** `ClipboardPayload.contentHash` usa SHA-256 del texto, URL normalizada, rutas de archivo o hash de la imagen. Si el mismo contenido se copia dos veces seguidas, no se emite un evento nuevo.

## Enrutamiento de módulos

`FeatureRegistry` mantiene el catálogo y resuelve tres preguntas:

| Pregunta | Método | Regla |
|---|---|---|
| ¿Qué módulos entienden este ítem? | `matchingPlugins(for:)` | Habilitados y `canHandle(item) == true`, ordenados por `priority` descendente y, en empate, por orden de registro. |
| ¿Debe abrirse un prompt solo? | `primaryPromptPlugin(for:context:)` | Primer módulo compatible cuyo `triggerBehavior == .automaticPrompt` y cuyo `makePromptView(...) != nil`. |
| ¿Qué botones muestro en la fila? | `quickActions(for:context:)` | Todas las acciones de todos los módulos compatibles, en el mismo orden de prioridad. |

Prioridades:

| Valor | Uso típico |
|---|---|
| `.high` (100) | Acciones ricas con prompt proactivo, como YouTube Audio. |
| `.normal` (50) | Transformadores específicos: JSON, limpieza de URLs. |
| `.low` (10) | Acciones genéricas o de conveniencia: conversión de color, mayúsculas. |

El modo de disparo se guarda por módulo en `SettingsManager` (`pluginTriggerBehaviors`) y puede ser:

- `.automaticPrompt`: al copiar un ítem compatible, el notch se abre con el prompt del módulo.
- `.historyActionOnly`: no abre nada; solo aparecen sus acciones en la fila del historial.

El usuario puede cambiarlo en **Ajustes → Módulos** si el módulo expone prompt. La UI usa `pluginSupportsPrompt(_:)`, que comprueba `supportsPrompt` o, como respaldo, si `makePromptView` devuelve una vista para un ítem vacío.

## Máquina de estados del notch

`NotchMode` tiene tres estados mutuamente excluyentes:

```
                 ┌──────────────────────────────┐
                 │            .idle             │
                 └──────────────┬───────────────┘
        copia compatible       │        hover / menú / acción
        con .automaticPrompt   │
                 ┌─────────────▼─────────────┐
                 │ .promptingFeature(id,item)│
                 └─────────────┬─────────────┘
       completar/cancelar      │      el módulo pide actividad
                 ┌─────────────▼─────────────┐
                 │  .showingPanel(tab:)      │
                 │  ├─ .clipboardHistory     │
                 │  └─ .pluginActivity(id)   │
                 └───────────────────────────┘
```

Reglas:

- `AppState` es el único que cambia `notchMode`.
- `NotchPresenting` es el contrato con la presentación real. `NotchController` lo implementa; los tests usan un presentador falso.
- `NotchRootView` conmuta la vista según `notchMode`. En `.idle` devuelve un contenido mínimo para que la ventana no parpadee.
- `activeTab` se valida antes de presentar: si el módulo de una pestaña de actividad se desactivó, se cae a `.clipboardHistory`.
- `completePrompt(for:)` pasa a la pestaña de actividad si el módulo tiene `hasActivityPanel`; si no, colapsa el notch.

### Presentación y geometría

`NotchController` usa `DynamicNotchKit` y añade:

- **Zonas de proximidad:** `NotchGeometry` calcula el rectángulo del notch, una zona de disparo con 15 pt de margen y una zona de retención con 25 pt.
- **Doble fuente de eventos:** monitores global y local de `mouseMoved`, más un timer de 250 ms como red de seguridad (los monitores globales pueden no recibir eventos sobre el propio panel).
- **Cola de transiciones:** las animaciones de `DynamicNotch` son asíncronas; `enqueueTransition` serializa `hide`/`expand` para que un “cancelar y abrir otra cosa” no termine con el panel oculto.
- **Timers:** auto-cierre del prompt (`settings.promptAutoDismissSeconds`, entre 3 y 15 s), auto-ocultado del panel y colapso con 220 ms de gracia al salir de la zona.
- **Multipantalla:** los prompts prefieren la pantalla con notch; los paneles usan la pantalla del cursor o la primaria. Si cambia la pantalla, se recrea la ventana.
- **Pegado inmediato:** `hideImmediatelyForAutoPaste()` hace `resignKey()` y `orderOut(nil)` antes del `⌘V` para no esperar la animación de cierre.

### Atajo global y navegación por teclado (`⌃⌘V`)

- **`GlobalHotKeyService`:** registra `⌃⌘V` (`HotKey.clipboardDefault`) mediante Carbon (`RegisterEventHotKey` + `InstallEventHandler` en `CarbonHotKeyRegistrar`) durante `AppEnvironment.start()` y lo desregistra en `shutdown()`. Usar Carbon permite consumir el evento globalmente sin requerir permiso de Accesibilidad solo para abrir el notch. Si otra aplicación ocupa el atajo (`eventHotKeyExistsErr`), registra un warning y deja el resto de la app operativa (la personalización del atajo queda fuera del alcance actual).
- **Estado de selección en `AppState`:** `openClipboardFromHotKey()` recuerda la app frontmost antes de activar el panel, cancela cualquier prompt activo, cambia a `.showingPanel(tab: .clipboardHistory)`, selecciona el primer elemento de `historyStore.filteredItems` (`selectedClipboardItemID`), activa `isKeyboardNavigationActive` y solicita el foco del panel (`focusNotchForKeyboardInput()`). `moveClipboardSelection(_:)` avanza o retrocede sin hacer wrap en los extremos; `reconcileClipboardSelection()` reajusta la selección si cambian la búsqueda, los filtros o la retención; `confirmClipboardSelection(forceCopyOnly:)` reutiliza `autoPaste(item:forceCopyOnly:)` evitando ejecuciones concurrentes.
- **Foco y monitor local de teclas en `NotchController`:** `focusNotchForKeyboardInput()` instala un `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` solo mientras el panel está abierto en modo teclado y hace key el `NSPanel` (`NSApp.activate(ignoringOtherApps: true)` + `window.makeKeyAndOrderFront(nil)`). `NotchController.keyboardCommand(for:)` traduce `↑`/`↓`, `Return`/`Enter` (ignorando `isARepeat`, con `⌥ + Enter` para solo copiar) y `Esc`, dejando pasar el resto de teclas al buscador `TextField`. El monitor se desinstala al ocultar, cerrar o cambiar a un prompt.
- **Claves de localización:** `clipboard.keyboard.hint` (pista visual `↑↓ navegar · ↵ pegar · esc cerrar`), y `settings.clipboard.hotkey.{title,active,conflict,inactive}` para el estado del atajo en Ajustes.

## Pegado automático

`AppState.autoPaste(item:forceCopyOnly:)` sigue este orden:

1. `historyStore.copyToPasteboard(item)` escribe el payload y arma la deduplicación del monitor.
2. Si `forceCopyOnly` (por ejemplo, `⌥ + clic`), termina como `.copiedOnly(reason: .forcedCopyModifier)`.
3. Si `settings.autoPasteOnSelect` está desactivado, termina como `.copiedOnly(reason: .disabledInSettings)`.
4. Si no hay permiso de Accesibilidad, avisa y termina como `.copiedOnly(reason: .accessibilityPermissionMissing)`.
5. Oculta el notch de forma inmediata.
6. `AutoPasteService.paste()`:
   - comprueba de nuevo Accesibilidad,
   - rechaza si `SecureEventInput` está activo (campo de contraseña),
   - resuelve la app destino (la recordada o la que tiene el foco),
   - la activa y espera a que sea la primera aplicación (hasta 4 intentos de 25 ms),
   - vuelve a comprobar `SecureEventInput`,
   - sintetiza `⌘V` con `CGEvent` (`kVK_ANSI_V` + `.maskCommand`) en `.cghidEventTap`.
7. Devuelve `PasteResult` y actualiza el feedback visual de la fila (`Copiado` / `Pegado`).

La app nunca falla en silencio: cualquier degradación a solo copiar produce un `PasteResult.copiedOnly(reason:)` y, cuando aplica, una notificación en el notch.

## Persistencia

### Preferencias

`SettingsManager` escribe cada cambio en `UserDefaults` inmediatamente y publica los valores con `@Observable`. Claves principales:

| Clave | Contenido |
|---|---|
| `notchtube.appLanguage` | Idioma elegido (`system`, `es`, `en`). |
| `notchtube.downloadDirectory` | Carpeta de descargas. |
| `notchtube.defaultFormat` | Formato por defecto (`mp3`, `wav`, `mp4_720p`, `mp4_1080p`). Los valores previos `mp3`/`wav` migran sin cambios y cualquier valor desconocido cae a `mp3`. |
| `notchtube.ytDlpPath` / `notchtube.ffmpegPath` | Rutas de binarios. |
| `notchtube.clipboardMonitoring` | Escucha automática. |
| `notchtube.ignoreConfidentialTypes` | Filtro de privacidad. |
| `notchtube.maxClipboardHistoryItems` | Límite (10…500). |
| `notchtube.persistClipboardHistory` | Persistencia entre reinicios. |
| `notchtube.autoPasteOnSelect` | Pegado al hacer clic. |
| `notchtube.promptDuration` | Auto-cierre del prompt (3…15 s). |
| `notchtube.pluginEnabledStates` | `[pluginID: Bool]`. |
| `notchtube.pluginTriggerBehaviors` | `[pluginID: String]`. |

Los módulos nuevos no necesitan tocar `SettingsManager` para activarse o desactivarse: el registry persiste su estado automáticamente. Solo añaden claves propias si tienen preferencias específicas.

### Historial

`ClipboardStorage` guarda en:

```
~/Library/Application Support/NotchTubeAudio/ClipboardHistory/
├── history.json          # índice de metadatos
└── Images/
    └── <UUID>.png        # blobs de imagen
```

- Las imágenes se externalizan para que `history.json` no crezca con base64.
- La escritura es **debounced** (500 ms por defecto) para no bloquear el main actor con copias rápidas.
- `flushPendingPersistence()` fuerza el volcado al cerrar.
- Cada imagen persistida tiene un límite de 15 MB (`defaultMaxImageBytes`).
- Al purgar por retención, borrar un elemento o limpiar el historial se eliminan también los archivos de imagen asociados.

### Retención

`ClipboardHistoryStore.enforceRetentionLimit()` elimina los elementos **no fijados** más antiguos hasta respetar `maxClipboardHistoryItems`. Los fijados nunca se purgan automáticamente.

## Concurrencia (Swift 6)

- `AppState`, `FeatureRegistry`, `SettingsManager`, `ClipboardHistoryStore`, `ClipboardMonitor`, `NotchController`, `DownloadManager` y los módulos son `@MainActor`.
- Los handlers de `Pipe` y `Process.terminationHandler` se ejecutan fuera del main actor; el código hace `Task { @MainActor ... }` para volver.
- `LineAccumulator` está diseñado para acumular líneas de stdout/stderr de forma segura entre hilos.
- Las tareas de metadatos y los timers se cancelan en `shutdown()` o al cambiar de prompt para evitar actualizaciones tardías.
- `DynamicNotch` se usa desde el main actor; la extensión `@retroactive @unchecked Sendable` documenta esa frontera.

## Privacidad y seguridad

- El contenido del portapapeles no sale del Mac, salvo la URL que el módulo YouTube Audio envía al endpoint oEmbed de YouTube para obtener título, canal y miniatura.
- El módulo **OCR de texto** (`OCRFeaturePlugin`) ejecuta el reconocimiento íntegramente en local con `Vision` (`VNRecognizeTextRequest` sobre `CGImageSourceCreateWithData` fuera del main actor) sin red, sin telemetría y sin registrar el texto reconocido en logs. Sus preferencias se guardan en `OCRSettingsStore` (`notchtube.ocr.*`).
- No hay telemetría, cuentas ni sincronización.
- La app no está sandboxeada (`com.apple.security.app-sandbox = false`) para poder lanzar `yt-dlp`/`ffmpeg` y escribir en la carpeta elegida.
- Los tipos confidenciales se descartan antes de crear el `ClipboardItem`.
- El pegado automático degrada a solo copiar si detecta `SecureEventInput`.

## Límites conocidos

- **Módulos compilados:** no hay carga dinámica de bundles. Un módulo nuevo requiere recompilar la app y registrarlo en `AppEnvironment`.
- **Un solo prompt automático:** si varios módulos de prioridad alta coinciden, gana el primero; el resto sigue disponible como acciones rápidas.
- **Historial en memoria:** el índice se carga completo al arrancar. Está acotado por `maxClipboardHistoryItems` (máximo 500).
- **YouTube Audio y Vídeo (`com.notchclip.plugin.youtube-audio`) depende de binarios externos:** sin `yt-dlp` y `ffmpeg` el módulo detecta enlaces, pero no puede descargar ni combinar vídeo MP4. `DownloadFormat` unifica audio (`mp3`, `wav`) y vídeo (`mp4_720p`, `mp4_1080p`), y `YTDLPCommandBuilder` construye de forma pura los argumentos de extracción de audio o merge MP4 (con fallback `web_embedded` ante HTTP 403). El `pluginID` permanece inalterado para preservar el estado y modo de disparo guardados en `UserDefaults`.
