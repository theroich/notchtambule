# Referencia de la API de módulos

Todos los tipos de esta página están en el target `NotchTubeAudio` y se importan con `@testable import NotchTubeAudio` en los tests.

## `ClipboardFeaturePlugin`

Protocolo principal. Es `@MainActor`, `AnyObject` e `Identifiable` (el `id` es `String`).

```swift
@MainActor
protocol ClipboardFeaturePlugin: AnyObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var summary: String { get }
    var iconSystemName: String { get }
    var priority: FeaturePriority { get }
    var defaultTriggerBehavior: FeatureTriggerBehavior { get }
    var supportsPrompt: Bool { get }

    func start()
    func shutdown()

    func canHandle(_ item: ClipboardItem) -> Bool

    func quickActions(
        for item: ClipboardItem,
        context: FeatureActionContext
    ) -> [FeatureQuickAction]

    func makePromptView(
        for item: ClipboardItem,
        context: FeatureActionContext,
        onComplete: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView?

    var hasActivityPanel: Bool { get }
    var activityPanelTitle: String { get }
    var activeTasksCount: Int { get }
    func makeActivityPanelView(context: FeatureActionContext) -> AnyView?

    func makeSettingsView() -> AnyView?
}
```

### Requisitos y valores por defecto

| Miembro | Obligatorio | Valor por defecto | Contrato |
|---|---|---|---|
| `id` | Sí | — | Único, estable, con prefijo `com.notchclip.plugin.`. |
| `displayName` | Sí | — | Nombre visible; puede usar `L10n`. |
| `summary` | Sí | — | Descripción de una o dos líneas para Ajustes. |
| `iconSystemName` | Sí | — | SF Symbol válido. |
| `priority` | No | `.normal` | Ordena prompts y acciones. |
| `defaultTriggerBehavior` | No | `.historyActionOnly` | Comportamiento inicial si el usuario no lo cambia. |
| `supportsPrompt` | No | `defaultTriggerBehavior == .automaticPrompt` | Declara que hay prompt. |
| `start()` | No | vacío | Se llama al registrar si está habilitado y al reactivar. |
| `shutdown()` | No | vacío | Se llama al desactivar, reemplazar o cerrar la app. |
| `canHandle` | Sí | — | Síncrono, rápido, sin red ni E/S. |
| `quickActions` | No | `[]` | Acciones de la fila; se llaman solo si `canHandle` es `true`. |
| `makePromptView` | No | `nil` | Vista del prompt contextual. |
| `hasActivityPanel` | No | `false` | Añade pestaña de actividad. |
| `activityPanelTitle` | No | `displayName` | Título de la pestaña. |
| `activeTasksCount` | No | `0` | Badge de la pestaña; `0` lo oculta. |
| `makeActivityPanelView` | No | `nil` | Contenido de la pestaña. |
| `makeSettingsView` | No | `nil` | Vista incrustada en Ajustes. |

### Orden de llamadas

```
register(plugin)
  ├── si ya existe otro con el mismo id → shutdown() del anterior
  ├── si está habilitado → start()
  └── guarda el plugin en el catálogo

captura de un ítem
  ├── matchingPlugins → canHandle(item)
  ├── primaryPromptPlugin → makePromptView(...) (sondeo)
  ├── quickActions(for:context:)
  └── makePromptView(...) (presentación real, si aplica)

desactivar
  └── shutdown()

reactivar
  └── start()
```

`makePromptView` puede invocarse varias veces para el mismo ítem, incluso antes de presentar nada. Debe ser barato e idempotente.

## `FeaturePriority`

```swift
enum FeaturePriority: Int, Comparable, Sendable {
    case low = 10
    case normal = 50
    case high = 100
}
```

`matchingPlugins(for:)` ordena de mayor a menor. En empate se respeta el orden de registro.

## `FeatureTriggerBehavior`

```swift
enum FeatureTriggerBehavior: String, Codable, Sendable, CaseIterable {
    case automaticPrompt
    case historyActionOnly
}
```

| Caso | Efecto |
|---|---|
| `.automaticPrompt` | Abre el prompt del módulo al copiar un ítem compatible. |
| `.historyActionOnly` | No abre nada; solo muestra acciones en el historial. |

El valor efectivo se lee con `FeatureRegistry.triggerBehavior(for:)` y se persiste con `setTriggerBehavior(_:for:)`.

## `FeatureQuickAction`

```swift
struct FeatureQuickAction: Identifiable {
    let id: String
    let pluginID: String
    let title: String
    let iconSystemName: String
    let handler: @MainActor () -> Void
}
```

- `id`: único por acción y por ítem. El patrón habitual es `"\(pluginID).<accion>.\(item.id.uuidString)"`.
- `pluginID`: ID del módulo que la crea.
- `title`: tooltip y etiqueta de accesibilidad. Localízalo.
- `iconSystemName`: icono del botón circular.
- `handler`: se ejecuta en el main actor al pulsar.

Las acciones se muestran en el orden devuelto por `matchingPlugins` (prioridad descendente). Si hay muchas, la fila puede quedar apretada; sé selectivo.

## `FeatureActionContext`

Objeto `@MainActor` que da al módulo acceso controlado al sistema. También registra lo ocurrido para tests.

```swift
@MainActor
final class FeatureActionContext {
    static var noop: FeatureActionContext { get }

    private(set) var writtenPayloads: [ClipboardPayload]
    private(set) var lastPresentedPrompt: (pluginID: String, item: ClipboardItem)?
    private(set) var lastSwitchedActivityPluginID: String?
    private(set) var hideNotchCallCount: Int
    private(set) var lastNotification: FeatureUserNotification?

    func writeToClipboard(_ payload: ClipboardPayload)
    func presentPluginPrompt(pluginID: String, for item: ClipboardItem)
    func switchToPluginActivity(pluginID: String)
    func hideNotch()
    func notifyUser(message: String, icon: String)
}
```

| Método | Efecto real | Uso típico |
|---|---|---|
| `writeToClipboard` | Escribe en `NSPasteboard`, registra el resultado en el historial y reanota los módulos detectados, sin duplicar ni disparar prompts. | Copiar el resultado de una transformación. |
| `presentPluginPrompt` | Abre el prompt del módulo para el ítem. | Abrir un prompt desde una acción rápida. |
| `switchToPluginActivity` | Cambia a la pestaña de actividad del módulo. | Tras encolar una tarea. |
| `hideNotch` | Colapsa el notch. | Cerrar tras una acción. |
| `notifyUser` | Muestra un aviso breve con icono. | Confirmaciones y errores. |

`FeatureActionContext.noop` es un contexto sin efectos secundarios, útil para evaluar vistas o comprobar si un módulo produce acciones.

## `FeatureUserNotification`

```swift
struct FeatureUserNotification: Equatable, Sendable {
    let message: String
    let icon: String
}
```

Se muestra temporalmente en el notch y se expone en `AppState.activeNotification`.

## `FeatureRegistry`

Catálogo observable y router. Es `@MainActor @Observable`.

```swift
@MainActor
@Observable
final class FeatureRegistry {
    private(set) var plugins: [any ClipboardFeaturePlugin]

    init(settings: SettingsManager, plugins: [any ClipboardFeaturePlugin] = [])

    func register(_ plugin: any ClipboardFeaturePlugin)
    func unregister(id: String)
    func plugin(withID id: String) -> (any ClipboardFeaturePlugin)?

    func isPluginEnabled(_ id: String) -> Bool
    func setPluginEnabled(_ id: String, _ enabled: Bool)
    func triggerBehavior(for id: String) -> FeatureTriggerBehavior
    func setTriggerBehavior(_ behavior: FeatureTriggerBehavior, for id: String)
    func pluginSupportsPrompt(_ plugin: any ClipboardFeaturePlugin) -> Bool

    func matchingPlugins(for item: ClipboardItem) -> [any ClipboardFeaturePlugin]
    func primaryPromptPlugin(
        for item: ClipboardItem,
        context: FeatureActionContext = .noop
    ) -> (any ClipboardFeaturePlugin)?
    func quickActions(
        for item: ClipboardItem,
        context: FeatureActionContext
    ) -> [FeatureQuickAction]

    var activityPanelPlugins: [any ClipboardFeaturePlugin] { get }
    var totalActiveTasksCount: Int { get }

    func startAllEnabled()
    func shutdownAll()
}
```

Comportamiento destacado:

- `register` reemplaza un módulo con el mismo `id` y llama a `shutdown()` del anterior.
- Un módulo sin preferencia guardada está **habilitado** por defecto.
- `setPluginEnabled` persiste en `SettingsManager` y llama a `start()`/`shutdown()`.
- `primaryPromptPlugin` ignora módulos deshabilitados, no compatibles, con trigger `.historyActionOnly` o cuyo `makePromptView` devuelve `nil`.
- `totalActiveTasksCount` suma `activeTasksCount` de los módulos habilitados y se usa para el icono de la barra de menús.

## Modelos del portapapeles

### `ClipboardItem`

```swift
struct ClipboardItem: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let capturedAt: Date
    let changeCount: Int
    let payload: ClipboardPayload
    let sourceApp: ClipboardSourceApp?
    var isPinned: Bool
    var detectedFeatureIDs: [String]

    var contentType: ClipboardContentType { get }
    var contentHash: String { get }
    var previewTitle: String { get }
    var previewSubtitle: String? { get }
}
```

- `detectedFeatureIDs`: lo rellena `AppState` antes de guardar; sirve para badges y para persistir qué módulos entendían el ítem.
- `contentHash`: deduplicación estable.
- `previewTitle` / `previewSubtitle`: texto listo para la fila, ya localizado.

### `ClipboardPayload`

```swift
enum ClipboardPayload: Equatable, Sendable, Codable {
    case text(String)
    case url(URL, rawText: String)
    case files([URL])
    case image(ImagePayload)
}
```

Propiedades útiles:

- `contentType`: `.plainText`, `.url`, `.image`, `.fileURLs`, `.colorHex`, `.codeSnippet`.
- `contentHash`: prefijo por tipo + SHA-256.
- `stringValue`: representación textual para texto, URL o rutas de archivo; `nil` para imágenes.

### `ClipboardContentType`

```swift
enum ClipboardContentType: String, Codable, Sendable, CaseIterable {
    case plainText
    case url
    case image
    case fileURLs
    case colorHex
    case codeSnippet
}
```

`colorHex` y `codeSnippet` son heurísticas de `ClipboardPayload.contentType` para texto.

### `ImagePayload`

```swift
struct ImagePayload: Equatable, Sendable, Codable {
    let width: Double
    let height: Double
    let tiffOrPngData: Data
    let sha256Hash: String

    var size: CGSize { get }
    init?(data: Data)
    static func computeSHA256(for data: Data) -> String
}
```

### `ClipboardSourceApp`

```swift
struct ClipboardSourceApp: Equatable, Sendable, Codable {
    let bundleIdentifier: String?
    let localizedName: String?
}
```

## Estado del notch

### `NotchMode`

```swift
enum NotchMode: Equatable, Sendable {
    case idle
    case promptingFeature(pluginID: String, item: ClipboardItem)
    case showingPanel(tab: NotchPanelTab)

    var isPrompting: Bool { get }
    var isShowingPanel: Bool { get }
}
```

### `NotchPanelTab`

```swift
enum NotchPanelTab: Equatable, Hashable, Sendable {
    case clipboardHistory
    case pluginActivity(pluginID: String)
}
```

### `NotchPresenting`

```swift
@MainActor
protocol NotchPresenting: AnyObject {
    func presentPrompt()
    func presentPanel(autoHideAfter seconds: TimeInterval?)
    func hide()
    func hideImmediatelyForAutoPaste() async
}
```

`AppState.presenter` es `weak`, así que el `NotchController` debe mantener la referencia viva (lo hace `AppEnvironment`).

## Resultado del pegado automático

### `PasteResult`

```swift
enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly(reason: AutoPasteSkipReason)

    var didPaste: Bool { get }
}
```

### `AutoPasteSkipReason`

```swift
enum AutoPasteSkipReason: Equatable, Sendable {
    case disabledInSettings
    case forcedCopyModifier
    case accessibilityPermissionMissing
    case secureEventInputActive
    case noTargetApplication
    case eventSynthesisFailed

    var userFacingMessage: String? { get }
}
```

## `SettingsManager` y módulos

`SettingsManager` es `@MainActor @Observable` y persiste cada cambio en `UserDefaults`.

Métodos que usa el sistema de módulos:

```swift
func isPluginEnabled(_ pluginID: String) -> Bool
func setPluginEnabled(_ pluginID: String, _ enabled: Bool)
func triggerBehavior(
    for pluginID: String,
    defaultBehavior: FeatureTriggerBehavior = .historyActionOnly
) -> FeatureTriggerBehavior
func setTriggerBehavior(_ behavior: FeatureTriggerBehavior, for pluginID: String)
```

Propiedades globales relevantes:

| Propiedad | Tipo | Rango / valor |
|---|---|---|
| `appLanguage` | `AppLanguage` | `.system`, `.spanish`, `.english` |
| `downloadDirectory` | `URL` | Carpeta de descargas |
| `defaultFormat` | `AudioFormat` | `.mp3`, `.wav` |
| `ytDlpPath` / `ffmpegPath` | `String` | Rutas absolutas |
| `isClipboardMonitoringEnabled` | `Bool` | — |
| `ignoreConfidentialPasteboardTypes` | `Bool` | — |
| `maxClipboardHistoryItems` | `Int` | 10…500 |
| `persistClipboardHistory` | `Bool` | — |
| `autoPasteOnSelect` | `Bool` | — |
| `promptAutoDismissSeconds` | `Double` | 3…15 |

## Localización

```swift
enum L10n {
    static var effectiveLanguageCode: String { get }
    static var currentLocale: Locale { get }

    static func string(_ key: String, languageCode: String? = nil) -> String
    static func string(_ key: String, locale: Locale) -> String
    static func format(
        _ key: String,
        languageCode: String? = nil,
        _ arguments: CVarArg...
    ) -> String
    static func formatByteCount(_ bytes: Int, locale: Locale? = nil) -> String
}
```

- `L10n.string("clave")` resuelve en el idioma activo.
- `L10n.format("clave", arg1, arg2)` aplica el locale y los especificadores.
- Si falta una clave, cae a español y, si tampoco existe, devuelve la propia clave. Añade siempre `es` y `en`.

## Protocolos inyectables para tests

### `PasteboardReading`

Abstracción del portapapeles usada por `ClipboardMonitor`, `ClipboardHistoryStore` y sus tests.

```swift
@MainActor
protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType] { get }

    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
    func readFileURLs() -> [URL]
    func frontmostSourceApp() -> ClipboardSourceApp?
    @discardableResult func write(_ payload: ClipboardPayload) -> Int
}
```

`SystemPasteboardReader` es la implementación real. Consulta `ClipboardMonitorTests` para ver un `MockPasteboard`.

### `AutoPasteSystemEnvironment`

Permite simular Accesibilidad, `SecureEventInput`, foco y síntesis de teclas en `AutoPasteServiceTests`.

### `YouTubeMetadataFetching`

Permite sustituir el servicio oEmbed en `YouTubeAudioFeaturePlugin`.

## `Logging`

```swift
enum Log {
    static let app: Logger
    static let clipboard: Logger
    static let metadata: Logger
    static let downloads: Logger
    static let notch: Logger
    static let settings: Logger
    static let features: Logger
}
```

Usa `Log.<categoría>.info/debug/warning/error` con `privacy: .public` solo para datos no sensibles. No registres contenido del portapapeles.
