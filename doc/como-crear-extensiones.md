# Cómo crear una extensión (módulo)

En Notchtambule, una **extensión** o **módulo** es un tipo Swift que implementa `ClipboardFeaturePlugin` y se registra en la app al compilar. No es un bundle que se cargue en caliente: el módulo forma parte del ejecutable y se activa o desactiva desde Ajustes.

Un módulo puede aportar, de forma independiente:

- **detección** de un tipo de contenido (`canHandle`),
- **acciones rápidas** en la fila del historial (`quickActions`),
- un **prompt** contextual en el notch (`makePromptView`),
- una **pestaña de actividad** con contador (`hasActivityPanel`, `makeActivityPanelView`),
- una **vista de ajustes** propia (`makeSettingsView`).

## 1. Elegir el nombre y el identificador

Convenciones:

- Carpeta: `Sources/NotchTubeAudio/Features/WordCount/`
- Clase: `WordCountFeaturePlugin`
- ID: `com.notchclip.plugin.word-count`
- Icono: un SF Symbol válido, por ejemplo `textformat.abc`
- Acciones: IDs únicos, por ejemplo `com.notchclip.plugin.word-count.count.<uuid>`

El ID debe ser estable: se usa para persistir si el módulo está activo, su modo de disparo, la pestaña de actividad y los badges del historial. **No lo cambies** una vez publicado.

## 2. Implementar el módulo mínimo

Crea `Sources/NotchTubeAudio/Features/WordCount/WordCountFeaturePlugin.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
final class WordCountFeaturePlugin: ClipboardFeaturePlugin {
    static let pluginID = "com.notchclip.plugin.word-count"

    let id: String = WordCountFeaturePlugin.pluginID
    // Simplificado: en producción usa L10n para todos los textos visibles.
    let displayName = "Contador de palabras"
    let summary = "Cuenta palabras y caracteres del texto copiado y copia el resultado."
    let iconSystemName = "textformat.abc"
    let priority: FeaturePriority = .low
    let defaultTriggerBehavior: FeatureTriggerBehavior = .historyActionOnly

    func canHandle(_ item: ClipboardItem) -> Bool {
        guard case .text(let text) = item.payload else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func quickActions(
        for item: ClipboardItem,
        context: FeatureActionContext
    ) -> [FeatureQuickAction] {
        guard case .text(let text) = item.payload, canHandle(item) else { return [] }

        let words = text.split(whereSeparator: \.isWhitespace).count
        let characters = text.count
        let result = "\(words) palabras · \(characters) caracteres"

        return [
            FeatureQuickAction(
                id: "\(id).count.\(item.id.uuidString)",
                pluginID: id,
                title: "Contar: \(result)",
                iconSystemName: "textformat.abc"
            ) {
                context.writeToClipboard(.text(result))
                context.notifyUser(message: result, icon: "textformat.abc")
            }
        ]
    }
}
```

Qué hace cada pieza:

| Miembro | Obligatorio | Notas |
|---|---|---|
| `id` | Sí | Único y estable. |
| `displayName` | Sí | Se muestra en Ajustes, tabs y badges. |
| `summary` | Sí | Descripción corta en Ajustes. |
| `iconSystemName` | Sí | SF Symbol. |
| `priority` | No | Por defecto `.normal`. |
| `defaultTriggerBehavior` | No | Por defecto `.historyActionOnly`. |
| `canHandle` | Sí | Síncrono, rápido, sin red ni E/S. |
| `quickActions` | No | Se muestran en la fila si `canHandle` es `true`. |

Para textos visibles, usa `L10n` en lugar de literales. Lo vemos en el [apartado de localización](#8-localización).

## 3. Registrar el módulo

Abre `Sources/NotchTubeAudio/App/AppEnvironment.swift` y añade el módulo al array de `FeatureRegistry`:

```swift
let wordCountPlugin = WordCountFeaturePlugin()

let featureRegistry = FeatureRegistry(
    settings: settings,
    plugins: [
        youtubePlugin,
        urlCleanerPlugin,
        jsonFormatterPlugin,
        colorConverterPlugin,
        wordCountPlugin          // ← nuevo
    ]
)
```

Añade también la propiedad si necesitas acceder a él desde `AppEnvironment`:

```swift
let wordCountPlugin: WordCountFeaturePlugin
```

Y asígnala en el bloque final del inicializador.

Hay un segundo sitio que construye un registry por compatibilidad: el inicializador `SettingsView(settings:)`. Solo se usa en previews/tests o si alguien instancia la vista a mano. Si quieres que ese camino también incluya el módulo, añádelo allí:

```swift
// Sources/NotchTubeAudio/Views/SettingsView.swift
FeatureRegistry(
    settings: settings,
    plugins: [
        YouTubeAudioFeaturePlugin(settings: settings),
        URLCleanerFeaturePlugin(),
        JSONFormatterFeaturePlugin(),
        ColorConverterFeaturePlugin(),
        WordCountFeaturePlugin()          // ← coherencia con AppEnvironment
    ]
)
```

La ruta de producción es `AppEnvironment`; el segundo registro evita que la UI de previews se comporte distinto.

### Qué ocurre automáticamente al registrar

- El módulo aparece en **Ajustes → Módulos** con interruptor.
- Si está habilitado (por defecto), se llama a `start()`.
- Al deshabilitarlo se llama a `shutdown()`.
- Sus `quickActions` aparecen en las filas compatibles.
- Su badge aparece en la fila usando el primer módulo compatible por prioridad.
- Si `hasActivityPanel == true`, aparece una pestaña en el notch.
- Si `makeSettingsView()` devuelve una vista, se incrusta en su tarjeta de Ajustes.

## 4. Probar el módulo

```bash
swift build
./Scripts/build-app.sh
open build/Notchtambule.app
```

Prueba manual:

1. Copia un texto.
2. Abre el notch y comprueba que la fila muestra el badge y el botón de acción.
3. Pulsa la acción y verifica que el resultado se copia y aparece el aviso.
4. En Ajustes → Módulos, desactiva el módulo y comprueba que desaparecen badge y botones.
5. Vuelve a activarlo y comprueba que `start()` se ejecuta de nuevo.

## 5. Añadir un prompt contextual

Un prompt sirve para pedir confirmación o parámetros antes de ejecutar una acción. Se muestra en el notch al copiar si el módulo está en `.automaticPrompt`, o cuando el usuario lo invoca desde una acción.

### 5.1 Implementar `makePromptView`

```swift
func makePromptView(
    for item: ClipboardItem,
    context: FeatureActionContext,
    onComplete: @escaping () -> Void,
    onDismiss: @escaping () -> Void
) -> AnyView? {
    guard case .text(let text) = item.payload, canHandle(item) else {
        return nil
    }

    return AnyView(
        WordCountPrompt(
            text: text,
            onConfirm: {
                let words = text.split(whereSeparator: \.isWhitespace).count
                context.writeToClipboard(.text("\(words) palabras"))
                onComplete()
            },
            onCancel: onDismiss
        )
    )
}
```

```swift
private struct WordCountPrompt: View {
    let text: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contar palabras")
                .font(.system(size: 12, weight: .semibold))

            Text("Se analizará el texto copiado (\(text.count) caracteres).")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.65))

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button("Cancelar", action: onCancel)
                    .buttonStyle(.plain)

                Button("Contar", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
        .padding(4)
    }
}
```

### 5.2 Activar el prompt

Para que el módulo pueda disparar el prompt al copiar:

```swift
let defaultTriggerBehavior: FeatureTriggerBehavior = .automaticPrompt
let supportsPrompt: Bool = true
```

`supportsPrompt` tiene un valor por defecto calculado (`defaultTriggerBehavior == .automaticPrompt`), pero es buena idea declararlo explícitamente cuando hay una implementación real. La UI de Ajustes comprueba `pluginSupportsPrompt(_:)`, que también prueba `makePromptView` con un ítem vacío como respaldo.

### 5.3 Reglas de `makePromptView`

- **No hagas trabajo pesado** dentro: el registry puede llamarlo para comprobar si el módulo soporta prompt. Devuelve la vista y, si necesitas cargar datos, lánzalo desde el ciclo de vida de la vista o desde un método del módulo con control de tareas.
- **Sé idempotente:** puede llamarse varias veces para el mismo ítem.
- **No retengas el contexto más de lo necesario**; las acciones de la vista deben usarlo y olvidarlo.
- **Llama a `onComplete()`** cuando la acción termine correctamente y a `onDismiss()` al cancelar.
- Si el módulo tiene panel de actividad, `onComplete()` hará que `AppState` cambie a esa pestaña automáticamente.

### 5.4 Pedir el prompt desde una acción rápida

Si el módulo solo debe abrir el prompt a demanda:

```swift
FeatureQuickAction(
    id: "\(id).open-prompt.\(item.id.uuidString)",
    pluginID: id,
    title: "Abrir contador",
    iconSystemName: "textformat.abc"
) {
    context.presentPluginPrompt(pluginID: id, for: item)
}
```

## 6. Añadir una pestaña de actividad

Ideal para tareas en segundo plano: descargas, conversiones, indexación, etc.

### 6.1 Implementar las propiedades

```swift
var hasActivityPanel: Bool { true }
var activityPanelTitle: String { "Contador" }

var activeTasksCount: Int {
    runningTasks.count
}

func makeActivityPanelView(context: FeatureActionContext) -> AnyView? {
    AnyView(WordCountActivityView(plugin: self))
}
```

- `hasActivityPanel`: activa la pestaña.
- `activityPanelTitle`: texto de la pestaña.
- `activeTasksCount`: badge numérico; `0` lo oculta.
- `makeActivityPanelView`: vista del panel.

### 6.2 Cambiar a la pestaña

```swift
context.switchToPluginActivity(pluginID: id)
```

Se usa, por ejemplo, al confirmar un prompt o al encolar una tarea. `AppState` valida que el módulo siga habilitado y que tenga panel antes de mostrar la pestaña.

### 6.3 Mantener el contador actualizado

El badge se calcula a partir de `activeTasksCount` en cada actualización observable. Si el módulo es `@Observable` y `activeTasksCount` depende de propiedades observables, la UI se actualiza sola. Si el estado vive en un servicio inyectado, haz que ese servicio también sea observable o expón un `var` observable en el módulo.

## 7. Añadir ajustes propios

```swift
func makeSettingsView() -> AnyView? {
    AnyView(
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Incluir caracteres", isOn: Binding(
                get: { self.includeCharacters },
                set: { self.includeCharacters = $0 }
            ))
        }
        .padding(.vertical, 4)
    )
}
```

La vista se incrusta dentro de la tarjeta del módulo en **Ajustes → Módulos** y se deshabilita automáticamente cuando el módulo está apagado.

Recomendaciones:

- Usa un `@State`/`@Bindable` sobre el módulo o sobre un objeto de preferencias inyectado.
- Persiste las preferencias en `UserDefaults` con claves propias, por ejemplo `notchtube.word-count.include-characters`.
- No dupliques las preferencias globales de `SettingsManager`; si son globales, viven allí.
- Usa `L10n` para todas las etiquetas.

## 8. Localización

El catálogo está en `Sources/NotchTubeAudio/Resources/Localizable.xcstrings` (`sourceLanguage: "es"`). Añade una entrada por clave con `es` y `en`:

```json
"plugin.word_count.name" : {
  "extractionState" : "manual",
  "localizations" : {
    "en" : {
      "stringUnit" : { "state" : "translated", "value" : "Word Count" }
    },
    "es" : {
      "stringUnit" : { "state" : "translated", "value" : "Contador de palabras" }
    }
  }
}
```

Uso en el módulo:

```swift
var displayName: String { L10n.string("plugin.word_count.name") }
var summary: String { L10n.string("plugin.word_count.summary") }

let title = L10n.string("plugin.word_count.action.count")
let message = L10n.format("plugin.word_count.notify.result", Int64(words), Int64(characters))
```

Reglas:

- No uses literales visibles en la UI.
- Los formatos deben usar especificadores compatibles (`%lld`, `%@`, `%1$@`, etc.) y `L10n.format` para aplicar el locale.
- Si añades una clave nueva, añade **español e inglés**. `LocalizationTests` comprueba el catálogo.
- Para textos de depuración o logs, usa `Log.*` y literales en inglés; no pasan por el catálogo.

## 9. Tests

### 9.1 Test unitario del módulo

Crea `Tests/NotchTubeAudioTests/WordCountFeaturePluginTests.swift`:

```swift
import Foundation
import Testing
@testable import NotchTubeAudio

@MainActor
struct WordCountFeaturePluginTests {
    private func makeItem(_ text: String) -> ClipboardItem {
        ClipboardItem(changeCount: 1, payload: .text(text))
    }

    @Test func detectsOnlyNonEmptyText() {
        let plugin = WordCountFeaturePlugin()

        #expect(plugin.canHandle(makeItem("hola mundo")))
        #expect(!plugin.canHandle(makeItem("   ")))
        #expect(!plugin.canHandle(
            ClipboardItem(changeCount: 1, payload: .url(URL(string: "https://example.com")!, rawText: ""))
        ))
    }

    @Test func quickActionWritesResultToContext() throws {
        let plugin = WordCountFeaturePlugin()
        let item = makeItem("uno dos tres")
        let context = FeatureActionContext()

        let action = try #require(plugin.quickActions(for: item, context: context).first)
        action.handler()

        #expect(context.writtenPayloads == [.text("3 palabras · 12 caracteres")])
        #expect(context.lastNotification?.message == "3 palabras · 12 caracteres")
    }
}
```

`FeatureActionContext` registra las llamadas en `writtenPayloads`, `lastPresentedPrompt`, `lastSwitchedActivityPluginID`, `hideNotchCallCount` y `lastNotification`. Es la forma más sencilla de testear un módulo sin abrir el notch.

### 9.2 Test de registro y prioridad

Si el módulo compite con otros, añade un test en `FeatureRegistryTests` o crea el tuyo con un `SettingsManager` aislado:

```swift
let suiteName = "notchtube.word-count.tests.\(UUID().uuidString)"
let defaults = try #require(UserDefaults(suiteName: suiteName))
defer { defaults.removePersistentDomain(forName: suiteName) }

let settings = SettingsManager(defaults: defaults)
let registry = FeatureRegistry(settings: settings, plugins: [WordCountFeaturePlugin()])
```

Así no contaminas las preferencias reales del usuario.

### 9.3 Test de la vista de ajustes

Si el módulo tiene ajustes, comprueba que `makeSettingsView()` no es `nil` y que el registro lo incluye. Para vistas complejas, sigue el patrón de `ClipboardNotchUITests`.

### 9.4 Ejemplo de acciones sobre archivos (`FileActionsFeaturePlugin`)

Cuando un módulo interactúa con `NSWorkspace` o `FileManager` (como [`FileActionsFeaturePlugin`](../Sources/NotchTubeAudio/Features/FileActions/FileActionsFeaturePlugin.swift) para `ClipboardPayload.files`), encapsula las operaciones del sistema detrás de un protocolo `@MainActor` inyectable (por ejemplo `FileActionPerforming`) para que los tests unitarios puedan verificar las rutas POSIX, el deduplicado y el manejo de archivos ausentes sin abrir Finder ni lanzar aplicaciones externas.

## 10. Errores frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| El módulo no aparece en Ajustes | No está registrado en `AppEnvironment`. | Añádelo al array de `FeatureRegistry`. |
| Aparece en Ajustes pero nunca actúa | `canHandle` devuelve `false` para ese payload. | Revisa el `switch` de `ClipboardPayload`. |
| El prompt no se abre solo | `defaultTriggerBehavior` es `.historyActionOnly` o el usuario lo cambió. | Declara `.automaticPrompt` y `supportsPrompt = true`. |
| El prompt no aparece aunque el modo es automático | `makePromptView` devuelve `nil`. | Comprueba el `guard` y que la vista se construya. |
| El badge no cambia | `activeTasksCount` no depende de estado observable. | Usa `@Observable` o actualiza una propiedad observada. |
| Los botones no se actualizan | El módulo no es `@Observable` o el estado vive fuera. | Marca la clase como `@Observable` si publica estado. |
| El resultado no se copia | Se escribe directamente en `NSPasteboard` en lugar del contexto. | Usa `context.writeToClipboard(...)`. |
| Se duplica el elemento en el historial | Se escribe en el pasteboard sin avisar al monitor. | Usa siempre `context.writeToClipboard` o `historyStore.copyToPasteboard`. |
| Tests contaminados entre ejecuciones | Se usa `UserDefaults.standard`. | Inyecta una suite aislada. |
| Warning de concurrencia | El módulo o sus closures no están en el main actor. | `@MainActor` en la clase y en las closures que toquen UI/estado. |

## 11. Checklist antes de abrir un PR

- [ ] ID único y estable con el prefijo `com.notchclip.plugin.`.
- [ ] Carpeta propia en `Features/`.
- [ ] `@MainActor final class` y, si publica estado, `@Observable`.
- [ ] `canHandle` rápido, sin red, sin E/S y sin efectos secundarios.
- [ ] Acciones con IDs únicos y títulos localizados.
- [ ] Escrituras al portapapeles solo mediante `FeatureActionContext`.
- [ ] `onComplete`/`onDismiss` llamados en el prompt.
- [ ] Si hay panel de actividad, `activeTasksCount` refleja tareas reales.
- [ ] Preferencias propias persistidas con claves propias.
- [ ] Claves nuevas en `Localizable.xcstrings` para `es` y `en`.
- [ ] Registro en `AppEnvironment` (y en el inicializador de compatibilidad de `SettingsView` si aplica).
- [ ] Tests unitarios del módulo y de sus acciones.
- [ ] `swift test` pasa.
- [ ] `./Scripts/build-app.sh` genera la app y se prueba manualmente el flujo completo.
