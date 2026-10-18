# NTSD for macOS

Собирает `NTSD.app` — самодостаточное приложение для macOS с игрой
Naruto: The Setting Dawn внутри. Ставить Wine, Homebrew или что-то ещё
в систему не нужно. Используется только open source: Wine 11
([Gcenx/macOS_Wine_builds](https://github.com/Gcenx/macOS_Wine_builds)) и GStreamer.

## Сборка

```sh
./build.sh ~/Downloads/NTSD2.8.3.3.zip
```

Результат:
- `build/NTSD.app` — приложение;
- `build/NTSD-<версия>-macOS.dmg` — образ для раздачи (`NO_DMG=1` пропускает его).

Wine и GStreamer скачиваются в `.cache/` и проверяются по SHA-256.
Нужны Xcode Command Line Tools (`clang`, `codesign`) и `python3`.
Иконка уже лежит в `assets/`. Перегенерировать её: `tools/make_icon.py`
(нужны numpy, Pillow и scipy).

## Как это работает

- **Управление по умолчанию:** игрок 1 — WASD + J/K/L (атака/прыжок/защита),
  игрок 2 — стрелки + `,` `.` `/`. В оригинальном `data/control.txt` действия
  висят на цифровом блоке, `build.sh` это исправляет. Если игрок менял клавиши
  сам, обновление приложения их сохраняет.
- **Первый запуск** (~20–30 с, с окном прогресса): игра копируется
  в `~/Library/Application Support/NTSD/Game`, создаётся Wine-префикс в `…/NTSD/Prefix`.
  На Mac с Apple silicon при отсутствии Rosetta 2 приложение предложит её установить.
- **Следующие запуски** — игра открывается сразу.
- **Option при запуске** — меню: открыть папку игры (моды, `data.txt`, записи боёв)
  или сбросить Wine.
- **Журнал:** `~/Library/Logs/NTSD.log`.
- Музыка игры — WMA/ASF. Её играет урезанный GStreamer внутри бандла
  (`Contents/Resources/gstreamer`, плагины `asf` + `libav`).
- В Dock игра отображается как «NTSD» со своей иконкой: процессу Wine
  передаётся `CFProcessPath`, а бандл помечен `LSUIElement`, чтобы служебные
  процессы Wine не добавляли свои значки.

## Релиз (подпись + нотаризация)

```sh
./release.sh ~/Downloads/NTSD2.8.3.3.zip --publish
```

Скрипт собирает приложение с подписью Developer ID (`build.sh` подписывает
каждый Mach-O с hardened runtime, исполняемым файлам Wine добавляет
`launcher/wine.entitlements`), нотаризует и степлит `.app` и `.dmg`, проверяет их через
`spctl` и с `--publish` выкладывает DMG в GitHub Releases.

Нужно:
- сертификат «Developer ID Application» в связке ключей;
- профиль notarytool (`NOTARY_KEYCHAIN_PROFILE`, по умолчанию `keys-cli-notary`):
  ```sh
  xcrun notarytool store-credentials keys-cli-notary --apple-id <apple-id> --team-id <team-id>
  ```

Микрофон приложение не запрашивает. Все бинарники, в том числе в локальной
ad-hoc сборке, подписаны с hardened runtime без entitlement `audio-input`,
поэтому macOS молча отказывает Wine, когда тот при инициализации звука
опрашивает устройства ввода.

Локальная ad-hoc сборка не нотаризована: на другом Mac её придётся открыть
через System Settings → Privacy & Security → «Open Anyway».

## Удаление

```sh
rm -rf /Applications/NTSD.app ~/Library/Application\ Support/NTSD ~/Library/Logs/NTSD.log
```
