# NotchTubeAudio

Aplicación nativa de macOS que vive en la barra de menús y utiliza el notch de la cámara para descargar el audio de enlaces de YouTube.

Copia un enlace (`youtube.com/watch`, `youtu.be`, `shorts`, `music.youtube.com`…) y el notch mostrará al instante la miniatura, el título y el canal, con la opción de guardarlo como **MP3** o **WAV**. Al acercar el cursor al notch aparece la cola de descargas con el progreso en tiempo real y un acceso directo al archivo en Finder.

```
┌────────────────────────────── notch ──────────────────────────────┐
│  [miniatura]  Título del vídeo                                    │
│               Canal · 24,3 s                                      │
│  ( MP3 ) ( WAV )                              ( X )  Guardar audio │
└───────────────────────────────────────────────────────────────────┘
```

---

## Requisitos

| Componente | Versión / notas |
|---|---|
| macOS | 14.0 Sonoma o superior |
| Xcode | 16 o superior. **No basta con Command Line Tools**: DynamicNotchKit usa el macro `@Entry` de SwiftUI y su plugin se instala con Xcode. |
| Swift | 6.0 (incluido en Xcode 16) |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | `brew install yt-dlp` |
| [ffmpeg](https://ffmpeg.org) | `brew install ffmpeg` |

La app no está sandboxeada (`com.apple.security.app-sandbox = false`) para poder lanzar `Process` con yt-dlp/ffmpeg y escribir directamente en el sistema de archivos.

---

## Compilar y ejecutar

Hay dos caminos equivalentes.

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

Al ejecutar desde Xcode el binario no va dentro de un `.app` bundle, por lo que `LSUIElement` no se aplica; la app fuerza igualmente `NSApp.setActivationPolicy(.accessory)` al arrancar. Para distribuirla o para que aparezca correctamente en Ajustes del Sistema, usa el script y el bundle.

La dependencia está fijada a DynamicNotchKit `1.1.x` (`Package.resolved` incluido) para que una futura versión no rompa la API.

### Tests

```bash
swift test
```

La suite no toca la red: sustituye `yt-dlp` por un script temporal y verifica la validación de URLs, el parseo de `stdout` (incluido el formato real de progreso `45.3%`), la acumulación de líneas del `Pipe`, la cola de descargas, la cancelación y la persistencia de ajustes.

### Configurar un target de app en Xcode (alternativa)

Si prefieres un proyecto `.xcodeproj` clásico:

1. Crea una app macOS 14+ con SwiftUI.
2. Borra el `@main` generado y añade todo `Sources/NotchTubeAudio` al target.
3. Añade el paquete `https://github.com/MrKai77/DynamicNotchKit` (`from: 1.1.0`).
4. En *Signing & Capabilities* elimina **App Sandbox**.
5. En *Info*, establece `Application is agent (UIElement)` = `YES` (`LSUIElement = YES`).
6. Copia las claves del `Info.plist` de este repositorio.

---

## Uso

1. Al arrancar aparece el icono `waveform.badge.mic` en la barra de menús.
2. Copia cualquier enlace de YouTube. El notch se expande con el prompt de descarga.
3. Elige **MP3** o **WAV** y pulsa **Guardar audio**.
4. Acerca el cursor a la parte superior central de la pantalla para ver la cola y el progreso.
5. Al terminar, pulsa la lupa de la fila para revelar el archivo en Finder.

Menú de la barra:

- **Mostrar descargas en el notch / Ocultar panel del notch**
- **Descargar enlace del portapapeles** (fuerza la detección, incluso con el monitor desactivado)
- **Abrir carpeta de descargas**
- **Configuración…** (`⌘,`)
- **Salir de NotchTubeAudio** (`⌘Q`)

### Ajustes

- Carpeta de destino (`~/Downloads` por defecto) con `NSOpenPanel`.
- Formato por defecto: MP3 o WAV.
- Rutas de `yt-dlp` y `ffmpeg` con validación visual (verde = ejecutable, rojo = no existe) y botón **Autodetectar** (busca en `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` y `PATH`).
- Activar o desactivar la escucha automática del portapapeles.
- Tiempo de auto-ocultación del prompt: 3–15 s (8 s por defecto).

---

## Arquitectura

```
Sources/NotchTubeAudio/
├── App/
│   ├── NotchTubeAudioApp.swift     # @main, MenuBarExtra + Settings scene
│   ├── AppDelegate.swift           # ciclo de vida AppKit, activación accessory
│   └── AppEnvironment.swift        # composition root (singleton @MainActor)
├── State/
│   └── AppState.swift              # @Observable: notchMode, prompt, metadata, acciones
├── Models/
│   ├── AudioFormat.swift           # mp3 / wav
│   ├── DownloadStatus.swift        # queued, downloading, converting, completed, failed, cancelled
│   ├── DownloadItem.swift          # item observable con progreso y estado
│   ├── DetectedVideo.swift         # metadatos del prompt
│   ├── NotchMode.swift             # idle / promptingURL / showingDownloads
│   └── YouTubeLink.swift           # URL validada + canonical + oEmbed
├── Services/
│   ├── ClipboardMonitor.swift      # Timer 0.6 s sobre changeCount
│   ├── YouTubeURLParser.swift      # Regex estricta de URLs de YouTube
│   ├── YouTubeMetadataService.swift# oEmbed por URLSession
│   ├── DownloadManager.swift       # cola, Process, progreso, cancelación
│   ├── ProcessOutputParser.swift   # parseo puro de stdout de yt-dlp
│   ├── LineAccumulator.swift       # chunks del Pipe → líneas completas
│   ├── NotchController.swift       # DynamicNotchKit + monitor global del ratón
│   ├── NotchGeometry.swift         # notch, trigger zone y retention zone
│   └── BinaryLocator.swift         # validación/autodetección de binarios
├── Settings/
│   └── SettingsManager.swift       # UserDefaults observable
├── Views/
│   ├── NotchRootView.swift
│   ├── NotchPromptView.swift
│   ├── DownloadQueueView.swift
│   ├── DownloadRowView.swift
│   ├── FormatPills.swift
│   ├── ThumbnailView.swift
│   ├── MenuBarContent.swift
│   └── SettingsView.swift
└── Utilities/
    ├── FileActions.swift
    └── Logging.swift
```

### Flujo de estados

```
idle ──(URL copiada)──▶ promptingURL ──(Guardar)──▶ showingDownloads
 ▲                           │                            │
 │                    (X / timeout)                 (hover fuera)
 └───────────────────────────┴────────────────────────────┘
```

`AppState` no toca AppKit: notifica al `NotchController` mediante el protocolo `NotchPresenting`. Así el estado es testeable y el controlador concentra la presentación.

---

## Detalles de implementación

### Portapapeles

- `Timer` de 0,6 s sobre `NSPasteboard.general.changeCount`.
- El contenido inicial se ignora: al arrancar solo se guarda el `changeCount` actual.
- Regex anclada, sin prosa ni varias URLs:
  - `youtube.com/watch?v=…`, `youtu.be/…`, `/shorts/…`, `music.youtube.com/watch?v=…`, además de `/live/…` y `/embed/…`.
- Deduplicación: se guarda el último texto visto. Copiar dos veces el mismo enlace sin copiar otra cosa entre medias no reabre el notch; copiar otra cosa y volver al enlace sí.

### Metadatos

`YouTubeMetadataService` consulta `https://www.youtube.com/oembed?url=…&format=json` con una `URLSession` efímera (timeout 3 s). El prompt se muestra de inmediato con la URL limpia y la miniatura `i.ytimg.com`; cuando llega oEmbed (normalmente < 200 ms) se sustituyen título y canal. Si falla, el fallback es la propia URL.

### Notch y detección de proximidad

`NotchController` usa `DynamicNotch` con fondo negro de la propia librería y calcula dos zonas en coordenadas de pantalla:

- **trigger**: rectángulo del notch + 15 pt. Entrar abre la cola.
- **retention**: notch expandido + 25 pt. Salir la colapsa (con 220 ms de debounce) o reinicia el temporizador del prompt.

El rectángulo del notch se obtiene de `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` y `safeAreaInsets.top`; en pantallas sin notch se usa un fallback centrado de 220 × 36 pt. Se registran `addGlobalMonitorForEvents` y `addLocalMonitorForEvents` para `mouseMoved`, y se recalcula todo con `NSApplication.didChangeScreenParametersNotification`. Un temporizador de seguridad a 4 Hz relee `NSEvent.mouseLocation` para que las zonas sigan funcionando cuando el cursor está sobre el propio panel transparente de la app.

La pantalla de destino prioriza la que tiene notch; en su defecto, la primaria (barra de menús) o la que contiene el cursor. Los prompts se muestran en el notch integrado; el hover respeta la pantalla bajo el cursor.

### Descarga

Cada trabajo ejecuta:

```bash
yt-dlp \
  --newline \
  --no-playlist \
  --print after_move:filepath \
  --no-quiet \
  --progress \
  --no-colors \
  -x \
  --audio-format mp3|wav \
  --audio-quality 0 \
  --ffmpeg-location <ffmpeg> \
  --progress-template "download:%(progress._percent_str)s" \
  -o "<carpeta>/%(title)s.%(ext)s" \
  "<url>"
```

Detalles relevantes:

- `--print` implica `--quiet`; `--no-quiet` restaura el log para poder detectar `[ExtractAudio]`, y `--progress` fuerza las líneas de progreso.
- En yt-dlp, `download:` dentro de `--progress-template` es el **tipo** de plantilla, así que la salida real es ` 45.3%`. El parser acepta tanto `download:45.3%` como `45.3%` y `[download] 45.3%`.
- `after_move:filepath` imprime la ruta final; también se reconoce `[ExtractAudio] Destination: …`. Si no se pudiera capturar, se busca el archivo más reciente con la extensión y el título correspondientes.
- Si el primer intento falla con **HTTP 403** (YouTube bloquea el cliente por defecto en algunos vídeos), la descarga se reencola automáticamente **una vez** con `--extractor-args "youtube:player_client=web_embedded"`. Si ese reintento también falla, la fila muestra un error accionable recomendando actualizar yt-dlp.
- Máximo 2 descargas simultáneas; el resto queda en `queued`.
- `SIGTERM` al cancelar y `SIGKILL` a los 2 s si el proceso sigue vivo.
- Al cerrar la app (`NSApplication.willTerminateNotification` + `applicationWillTerminate`) se termina **todos** los procesos hijos.

### Concurrencia

- `AppState`, `SettingsManager`, `DownloadManager`, `NotchController`, `DownloadItem` y los monitores son `@MainActor` y usan `@Observable`.
- La red (`URLSession`) y los procesos (`Process` + `Pipe`) son asíncronos; la lectura de los pipes ocurre en colas privadas y cada actualización se reenvía a `@MainActor`.
- `LineAccumulator` protege el buffer con `NSLock` y es `Sendable`.
- El proyecto compila en **Swift 6 language mode** (concurrency checking estricto).

---

## Solución de problemas

**«No se encontró yt-dlp/ffmpeg»**
Abre Ajustes y comprueba las rutas, o pulsa Autodetectar. Si usas Mac Intel, las rutas suelen ser `/usr/local/bin/...`.

**El progreso no aparece**
Comprueba que la versión de yt-dlp está actualizada (`brew upgrade yt-dlp`). La salida de errores de cada descarga se muestra en la fila (`Error` + mensaje).

**«HTTP 403: Forbidden» al descargar**
YouTube suele bloquear clientes antiguos de yt-dlp. La app ya reintenta una vez con el cliente `web_embedded`, que no necesita PO token GVS. Si el reintento también falla, actualiza las herramientas:

```bash
brew upgrade yt-dlp ffmpeg
```

Puedes comprobar la versión con `yt-dlp --version`. En la prueba que motivó este fallback, `2026.07.04` daba 403 en un vídeo real y `2026.10.26` lo descargaba directamente sin reintento.

**El notch no reacciona al hover**
En algunas versiones de macOS los monitores globales de ratón requieren permiso de **Accesibilidad** (Ajustes del Sistema > Privacidad y seguridad > Accesibilidad). La app funciona igualmente con el ratón sobre su propio panel mediante el monitor local.

**No puede escribir en la carpeta**
macOS protege Descargas/Escritorio/Documentos. La primera vez hay que conceder acceso cuando el sistema lo pida, o elegir otra carpeta en Ajustes.

**La app aparece en el Dock**
Estás ejecutando el binario de SwiftPM/Xcode sin bundle. Usa `Scripts/build-app.sh`, que aplica `LSUIElement`.

**Error al compilar: `plugin for module 'SwiftUIMacros' not found`**
Estás usando Command Line Tools en lugar de Xcode. Ejecuta:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

---

## Limitaciones conocidas

- Requiere conexión a Internet y una instalación funcional de yt-dlp; YouTube puede pedir autenticación o limitar descargas según la región/vídeo.
- La cola de descargas vive en memoria y no se restaura al reiniciar la app.
- El proyecto está pensado para uso local; para distribuir la app fuera de tu Mac necesitarás firmarla con tu Developer ID y notarizarla.
