# Changelog

Todos los cambios relevantes de **Notchtambule**. El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el versionado [SemVer](https://semver.org/lang/es/).

Las versiones anteriores a la 0.1.6 están documentadas en las [notas de cada release](https://github.com/theroich/notchtambule/releases).

## [0.1.7] - 2026-11-24

### Changed

- **Interfaz: la pill de filtro «Fijados» ya no muestra el emoji 📌**. Conserva el icono de pin del sistema y deja el texto limpio, tanto en inglés («Pinned») como en español («Fijados»).

## [0.1.6] - 2026-11-24

### Fixed

- **File Actions: la app se cerraba inesperadamente al abrir la ruta de un fichero en la terminal** (reproducido con Ghostty; afectaba igual a Terminal, iTerm2, Warp, kitty y Alacritty). El `completionHandler` que se pasa a `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` heredaba el aislamiento `@MainActor` de `SystemFileActionPerformer`, pero AppKit lo invoca en una cola concurrente (`com.apple.launchservices.open-queue`): la comprobación de ejecutor del runtime de Swift 6 fallaba y el proceso moría con `SIGTRAP` (`dispatch_assert_queue`). Ahora el closure se marca `@Sendable`, el nombre localizado de la terminal se resuelve antes de la llamada —en el main actor— y dentro del closure solo se usan valores `Sendable`. ([#24](https://github.com/theroich/notchtambule/issues/24))
