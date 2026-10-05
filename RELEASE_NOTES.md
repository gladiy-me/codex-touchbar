# v1.2.1 — Touch Bar tap fix

The compact indicator now uses a native macOS button so taps can open the
expanded Touch Bar. Its two-row layout remains unchanged. English and Russian UI languages can now
be selected from the CX menu; quotas refresh every 30 seconds.


Codex quota indicators for the MacBook Pro Touch Bar, with independent
five-hour and weekly percentages, a compact Control Strip indicator, expandable
colored progress bars, compact and ring styles, reset countdowns,
30-second refresh and login autostart.

Download `CodexTouchBar-v1.2.1-universal.zip`, extract it, and run `Install.command`.
Requires a physical Touch Bar, macOS 13+, and a ChatGPT-backed Codex CLI login.
Both Apple silicon and Intel binaries are included. The app is locally signed,
not Apple-notarized.

Quota fetching and autostart have been verified on an M1 MacBook Pro with macOS
26.5. The compact indicator was confirmed on the physical panel; the updated tap action
still requires a hardware check;
Intel hardware has not been tested. The widget uses private macOS APIs and may need
changes across macOS versions. The menu-bar indicator is the fallback.

No account credentials or personal configuration are included in the download.

---

Предварительная версия: компактный индикатор лимитов в Control Strip, широкие
полоски по нажатию, три оформления и автозапуск. Распакуйте архив и запустите
`Install.command`. Компактный виджет проверен на физической панели; обработчик тапа из v1.2.1
требует отдельной проверки. Добавлены английский язык и обновление каждые 30 секунд.
