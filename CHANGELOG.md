# Release notes

## 0.1.2 — Paste and recording feedback

- Automatic paste now preserves materialized custom clipboard formats instead of rejecting every unfamiliar type. File promises, unavailable providers, and oversized snapshots still leave the original clipboard untouched, with a specific explanation.
- An unreadable clipboard is never treated as empty. A system clipboard-access denial has its own explanation and settings action.
- Storage is optional. Dictation and insertion continue when Keychain access needs reconnecting after an update. Previous saving preferences and encrypted data are retained; saving, vocabulary, and crash recovery pause until access returns. New installations start without persistent storage.
- The recording bars respond together to the current microphone level instead of scrolling recent history. Rendering still uses one native layer and no animation timer.
- Permission actions restore their originating window after confirmation. Closing that window cancels the return.
- An installed copy tries to eject its exact matching read-only DMG after launch. Other images, writable volumes, and a copy running from the image are excluded.

### По-русски

Автовставка сохраняет дополнительные форматы буфера, из-за которых обычные диктовки могли уходить в Copy. Для слишком большого буфера, ещё не готовых данных и обещаний будущих файлов остаётся безопасное ручное копирование с отдельным объяснением.

Ошибка чтения буфера не считается его пустым содержимым. Системный запрет доступа показан отдельно, с переходом к настройкам.

Хранилище стало необязательным. Если после обновления нужно снова подтвердить доступ, диктовка и вставка работают, а сохранение, словарь и восстановление приостанавливаются. Прежние настройки и зашифрованные данные остаются на месте. Новая установка начинает работу без постоянного хранилища.

Полоски записи одновременно реагируют на текущую громкость, без бегущего следа. После системного подтверждения возвращается окно, из которого был запрошен доступ. Установленная копия также пробует извлечь свой DMG с той же сборкой; посторонние диски не затрагиваются.

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
