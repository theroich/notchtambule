# Documentación técnica de Notchtambule

Esta carpeta describe cómo está construida la aplicación y cómo extenderla sin romper sus contratos internos. La documentación está pensada para quien va a mantener el proyecto o añadir un módulo nuevo.

## Punto de entrada

- **Producto:** `NotchTubeAudio` (ejecutable Swift Package).
- **Nombre visible:** `Notchtambule`.
- **Bundle ID:** `com.notchtube.audio`.
- **Plataforma:** macOS 14+.
- **Lenguaje:** Swift 6 con `swiftLanguageMode(.v6)`.
- **UI:** SwiftUI + AppKit, con `DynamicNotchKit` para la ventana del notch.
- **Persistencia:** `UserDefaults` para preferencias e `history.json` + imágenes en disco para el historial.
- **Red:** solo la usa el módulo YouTube Audio para resolver metadatos mediante oEmbed. El resto funciona en local.

## Índice

| Documento | Para qué sirve |
|---|---|
| [`estructura.md`](estructura.md) | Árbol de carpetas, capas y dónde tocar cada cosa. |
| [`arquitectura.md`](arquitectura.md) | Composition root, flujo del portapapeles, estado del notch, persistencia y concurrencia. |
| [`como-crear-extensiones.md`](como-crear-extensiones.md) | Guía completa para crear un módulo: acciones rápidas, prompt, panel de actividad, ajustes, localización y tests. |
| [`api-plugins.md`](api-plugins.md) | Referencia del protocolo `ClipboardFeaturePlugin`, `FeatureActionContext`, `FeatureRegistry` y modelos. |
| [`desarrollo.md`](desarrollo.md) | Compilación, tests, localización, versionado, releases y solución de problemas. |

## Las tres ideas que explican el diseño

1. **Un único orquestador.** `AppState` recibe cada elemento capturado, lo registra en el historial y decide qué módulo debe responder. Ni las vistas ni los módulos deciden por su cuenta cuándo abrir el notch.
2. **Los módulos son cajas negras.** Un módulo implementa `ClipboardFeaturePlugin`, recibe un `ClipboardItem` y devuelve acciones o vistas. No conoce `NotchController`, `NSPasteboard` ni el resto de módulos.
3. **El contexto es la única salida.** Para escribir en el portapapeles, pedir un prompt, cambiar de pestaña, ocultar el notch o mostrar un aviso, el módulo usa `FeatureActionContext`. Eso mantiene el flujo testeable y evita efectos secundarios escondidos.

## Convenciones rápidas

- **ID de módulo:** `com.notchclip.plugin.<slug>` (por ejemplo, `com.notchclip.plugin.word-count`).
- **Carpeta del módulo:** `Sources/NotchTubeAudio/Features/<Nombre>/`.
- **Clase principal:** `<Nombre>FeaturePlugin`, `@MainActor final class`.
- **Registro:** en `Sources/NotchTubeAudio/App/AppEnvironment.swift`.
- **Texto visible:** siempre mediante `L10n`, con claves nuevas en `Sources/NotchTubeAudio/Resources/Localizable.xcstrings` (`es` y `en`).
- **Tests:** Swift Testing (`import Testing`), con `@MainActor` cuando se toca UI o estado global.

## Mapa mental del proyecto

```
AppEnvironment (composition root)
├── SettingsManager          preferencias persistentes
├── ClipboardMonitor         polling de NSPasteboard
├── ClipboardHistoryStore    historial, filtros, deduplicación, persistencia
├── FeatureRegistry          catálogo y router de módulos
├── AppState                 orquestador y máquina de estados del notch
├── NotchController          ventana DynamicNotch y geometría del ratón
├── AutoPasteService         foco, Accesibilidad y ⌘V
└── módulos                  YouTube Audio, URL Cleaner, JSON Formatter, Color Converter, ...
```

## Estado del proyecto

La suite de tests cubre, entre otras cosas:

- captura multimodal del portapapeles y filtrado de tipos confidenciales,
- historial, deduplicación, fijados, retención y persistencia,
- registro, prioridades, activación/desactivación y modos de disparo de módulos,
- orquestación de `AppState` y presentación del notch,
- plugins integrados, parser de URLs de YouTube y cola de descargas,
- localización y ajustes.

Consulta [`desarrollo.md`](desarrollo.md) para ejecutarlos.
