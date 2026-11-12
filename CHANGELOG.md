# Release notes

## 0.1.1 — Indicator controls

- Choose a camera-cutout indicator or a compact capsule in Appearance. Place the compact indicator at the top or bottom of a selected display; its controls open toward the screen.
- Camera detection accepts different menu-bar heights. A menu backdrop no longer disables cutout attachment. Side extensions still require room beside the camera so they do not cover menu items.
- Settings explain when macOS does not report a cutout. Existing shortcuts, models, and history settings are retained.
- GitHub builds use Intel hosts to avoid the congested ARM runner pool and cross-compile the app for Apple silicon. Shortcut labels also compile with Swift 6.2.

This remains a personally signed preview without Apple notarization or automatic updates. The revised cutout placement needs confirmation on a physical MacBook; automated geometry tests do not replace that check.

### По-русски

В «Оформлении» появились два вида индикатора: «У чёлки» и «Компактный». Компактную капсулу можно разместить сверху или снизу выбранного экрана; её кнопки открываются внутрь экрана.

Исправлено определение выреза при разной высоте строки меню. Фон меню больше не мешает индикатору примыкать к чёлке, а боковые расширения по-прежнему появляются только на свободном месте. Если macOS не сообщает геометрию выреза, настройки объясняют переход к компактной капсуле. Назначенные клавиши, модели и настройки истории сохраняются.

Проверки GitHub перенесены на Intel-серверы из-за очереди ARM; приложение по-прежнему собирается для Mac с M-чипом. Упрощено формирование подписей клавиш для совместимости со Swift 6.2.

Это предварительная версия с личной подписью, без нотариализации Apple и автоматического обновления. Новый вариант размещения нужно подтвердить на настоящем MacBook: проверки координат не заменяют аппаратный тест.

## 0.1.0 — Preview

Local dictation for Apple silicon Macs, with automatic Parakeet V3 setup, separate hold and toggle shortcuts, safe insertion, and a copyable last result. Includes a compact menu-bar interface, a camera-cutout indicator with a continuous contour, and English, Russian, Spanish, and French interface languages.

This preview is personally signed and not notarized by Apple. Automatic updates are not configured. Camera-cutout placement, older macOS versions, and destination-app behavior may need further testing.

### По-русски

Первая предварительная версия: локальная диктовка на Mac с M-чипом, автоматическая подготовка Parakeet V3, отдельные клавиши удержания и переключения, безопасная вставка и доступный для копирования последний результат. Компактное меню, цельный контур индикатора у камеры и четыре языка интерфейса.

Пока используется личная подпись без нотариализации Apple. Автоматический канал обновлений не настроен. Размещение у камеры, ранние версии macOS и работа отдельных полей требуют дальнейшей проверки.
