# Desarrollo

## Requisitos

| Herramienta | Versión | Notas |
|---|---|---|
| macOS | 14+ | La app usa APIs de macOS 14. |
| Xcode | 16+ | **Imprescindible**: DynamicNotchKit usa el macro `@Entry` de SwiftUI y su plugin viene con Xcode, no con Command Line Tools. |
| Swift | 6.0 | Incluido en Xcode 16. El paquete compila en `swiftLanguageMode(.v6)`. |
| `yt-dlp` | Última | Opcional, solo para YouTube Audio. |
| `ffmpeg` | Última | Opcional, solo para YouTube Audio. |

Comprueba el toolchain:

```bash
xcode-select -p
xcodebuild -version
swift --version
```

Si `xcode-select` apunta a Command Line Tools:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Primer arranque del proyecto

```bash
git clone https://github.com/theroich/notchtambule.git
cd notchtambule
brew install yt-dlp ffmpeg   # opcional
swift build
```

Para ejecutar la app empaquetada:

```bash
./Scripts/build-app.sh
open build/Notchtambule.app
```

`build-app.sh`:

1. selecciona Xcode si está disponible,
2. compila `NotchTubeAudio` en la configuración indicada (`debug` o `release`),
3. crea `build/Notchtambule.app` con `LSUIElement`, icono y recursos,
4. sincroniza `CFBundleExecutable` y la versión,
5. firma en modo ad-hoc para ejecución local.

También puedes abrir `Package.swift` en Xcode, elegir el esquema `NotchTubeAudio` y pulsar Run.

## Tests

```bash
swift test
```

La suite usa **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) y no toca la red ni el portapapeles real. Los tests que necesitan el main actor están marcados con `@MainActor`.

Buenas prácticas:

- Inyecta `UserDefaults(suiteName:)` aislados y limpia con `removePersistentDomain` en un `defer`.
- Usa `MockPasteboard` para el portapapeles y `MockAutoPasteEnvironment` para Accesibilidad/foco.
- Para módulos, usa `FeatureActionContext` y comprueba sus propiedades de inspección (`writtenPayloads`, `lastNotification`, etc.).
- No dependas del orden de ejecución de los tests.

Para ejecutar un subconjunto:

```bash
swift test --filter FeatureRegistryTests
swift test --filter WordCountFeaturePluginTests
```

## Depuración

### Logs

La app usa `os.Logger` con subsistema `com.notchtube.audio`. Para verlos en vivo:

```bash
log stream --predicate 'subsystem == "com.notchtube.audio"' --level debug
```

Categorías disponibles: `app`, `clipboard`, `metadata`, `downloads`, `notch`, `settings`, `features`.

No registres contenido del portapapeles ni rutas de usuario en logs públicos.

### Estado del portapapeles

Desde el menú de la barra puedes forzar una detección del contenido actual. En código, `ClipboardMonitor.captureCurrentPasteboard(force:)` lee el pasteboard sin esperar al timer.

### Notch

Si el panel no reacciona al hover:

1. Comprueba que la app tiene permiso de **Accesibilidad**.
2. Usa el icono de la barra de menús para abrir el panel manualmente.
3. Revisa los logs de la categoría `notch`; verás si el monitor de proximidad arrancó.

### Atajo global (`⌃⌘V`) y permisos

- **Abrir el notch con `⌃⌘V`:** no requiere permiso de Accesibilidad (usa Carbon `RegisterEventHotKey`). Si no responde, comprueba en **Ajustes → Portapapeles y General** si aparece como *Atajo no disponible* por conflicto con otra aplicación.
- **Navegar y pegar con teclado (`↑`/`↓`, `Enter`, `Esc`):** `Enter` reutiliza el flujo de `AutoPasteService`. Sin permiso de **Accesibilidad** —o cuando `SecureEventInput` está activo en un campo de contraseña— degrada de forma segura a **solo copiar** y muestra el aviso correspondiente en el notch.
- La personalización del atajo queda fuera del alcance de esta versión (el modelo `HotKey` está preparado para una fase posterior).

`NotchController` combina monitores global/local con un timer de 250 ms; si el panel se abre y se cierra solo, revisa la geometría de la pantalla y los márgenes de retención.

## Localización

El catálogo es `Sources/NotchTubeAudio/Resources/Localizable.xcstrings`:

- idioma fuente: `es`,
- idiomas soportados: `es` y `en`,
- `extractionState: "manual"` para las claves mantenidas a mano.

Flujo recomendado:

1. Añade la clave nueva al JSON con `es` y `en`.
2. Usa `L10n.string("clave")` o `L10n.format("clave", ...)` en el código.
3. Ejecuta `LocalizationTests`.
4. Comprueba la UI en ambos idiomas desde **Ajustes → Idioma**.

No uses `NSLocalizedString` directamente en código nuevo: el proyecto resuelve las cadenas con `L10n` para poder cambiar de idioma en caliente y para tests deterministas.

### Pseudolocalización

`L10n.isPseudolocalizationEnabled` expande los textos con acentos y delimitadores `⟪…⟫` conservando los especificadores de formato. Sirve para detectar recortes en el notch. Está pensado para tests y depuración, no para producción.

## Convenciones de código

- **Swift 6 estricto.** Cualquier tipo que toque UI, estado global, `NSPasteboard` o `AppKit` debe ser `@MainActor`. Los servicios sin estado pueden ser `Sendable`.
- **`@Observable`** para estado que consume SwiftUI (`AppState`, `SettingsManager`, `FeatureRegistry`, `ClipboardHistoryStore`, `DownloadManager`, módulos con estado).
- **`@ObservationIgnored`** para dependencias que no deben disparar actualizaciones.
- **Sin singletons nuevos.** La composición va en `AppEnvironment`; los tests inyectan dobles.
- **Sin lógica de negocio en las vistas.** Las vistas llaman a `AppState`, al registry o a un servicio.
- **Comentarios en español o inglés, pero consistentes** con el archivo que estás tocando.
- **APIs públicas de módulos:** documenta el contrato con `///` si añades métodos que otros módulos o tests van a usar.

## Versionado y releases

La versión vive en `Info.plist` (`CFBundleShortVersionString`). El workflow `.github/workflows/release.yml` automatiza el resto.

### Publicar una versión (recomendado)

1. GitHub → **Actions** → **Release** → **Run workflow**.
2. Elige `bump`:
   - `patch`: 1.0.0 → 1.0.1
   - `minor`: 1.0.0 → 1.1.0
   - `major`: 1.0.0 → 2.0.0
   - `none`: conserva la versión base
3. Opcionalmente escribe una `version` explícita (`1.4.2`), que tiene prioridad sobre `bump`.
4. El workflow:
   - calcula la versión a partir del último tag `v*` y de `Info.plist`,
   - actualiza `Info.plist` y hace commit `chore(release): vX.Y.Z` en `main`,
   - crea y empuja el tag `vX.Y.Z`,
   - compila en macOS con `Scripts/build-app.sh release`, pasando `APP_VERSION` y `BUILD_NUMBER`,
   - ejecuta `swift test` como puerta previa,
   - publica la GitHub Release con notas, `.dmg`, `.zip` y `SHA256SUMS.txt`.

### Publicar desde un tag existente

```bash
git tag -a v1.2.0 -m "Notchtambule 1.2.0"
git push origin v1.2.0
```

El workflow se dispara con el push del tag. En este camino **no** actualiza `Info.plist` ni hace commit; el camino recomendado sigue siendo **Run workflow**.

### Dry run

**Run workflow** con `dry_run` activo: compila, ejecuta tests y sube los artefactos a la pestaña **Actions** sin crear commit, tag ni release.

### Build local con versión concreta

```bash
APP_VERSION=1.4.0 BUILD_NUMBER=42 ./Scripts/build-app.sh release
```

### Artefactos

- `Notchtambule-X.Y.Z.dmg` (con enlace a `/Applications`),
- `Notchtambule-X.Y.Z.zip`,
- `SHA256SUMS.txt`.

### Firma

Las builds se firman en modo **ad-hoc**. No están notarizadas, así que macOS puede bloquear la primera apertura. En las notas de release se indica:

```bash
xattr -dr com.apple.quarantine "/Applications/Notchtambule.app"
```

o **clic derecho → Abrir**.

## Solución de problemas

### `plugin for module 'SwiftUIMacros' not found`

Estás usando Command Line Tools en lugar de Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### No se encontró `yt-dlp` o `ffmpeg`

Abre **Ajustes → Módulos → YouTube Audio**, revisa las rutas o pulsa **Autodetectar**. Si no necesitas descargar audio, desactiva el módulo.

```bash
brew install yt-dlp ffmpeg
```

### HTTP 403 al descargar de YouTube

YouTube bloquea clientes antiguos de `yt-dlp`. El módulo reintenta una vez con `youtube:player_client=web_embedded`. Si sigue fallando:

```bash
brew upgrade yt-dlp ffmpeg
```

### El notch no reacciona al hover

Concede permiso de **Accesibilidad** o abre el panel desde el icono de la barra de menús. En macOS recientes los monitores globales de ratón pueden requerirlo.

### El pegado automático solo copia

Comprueba en **Ajustes → Portapapeles y General**:

- que «Pegar al hacer click» esté activado,
- que el permiso de Accesibilidad esté concedido,
- que el campo de destino no active `SecureEventInput` (por ejemplo, un campo de contraseña).

La app degrada a solo copiar de forma segura y muestra el motivo.

### La app no aparece en el Dock

Es intencionado: `LSUIElement = true` y `NSApp.setActivationPolicy(.accessory)`. Se controla desde la barra de menús y el notch.

### Tests que fallan por preferencias

Asegúrate de que el test inyecta un `UserDefaults` aislado. Los tests no deben modificar `UserDefaults.standard`.

### La release no se publica

Revisa:

1. Que el tag tenga formato `vX.Y.Z`.
2. Que el workflow tenga permisos `contents: write` (ya están en el YAML).
3. Que `swift test` pase en el runner.
4. Los logs del job `version` si la versión calculada no es la esperada.
