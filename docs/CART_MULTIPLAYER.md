# План движения и анимации тележек в multiplayer

[Разработка](DEVELOPMENT.md) · [Невыполненные шаги](../TODO.md#cart-multiplayer-presentation)

Статус на 23 октября 2026 года: baseline-инструменты и коррекция выбранного observer inventory-equip перехода внедрены в ветке `codex/cart-animation-cleanup` (Java Patches 0.1.47, B42.21). Изменения протокола и source-time playback ниже ещё не реализованы. Цель — близкое к владельцу, плавное изображение у наблюдателя при нынешнем порядке трафика. Абсолютное совпадение в один физический момент времени невозможно при сетевой задержке; сравнивать нужно один момент движения с отдельно измеренной задержкой показа.

## Что работает сейчас

| Слой | Текущее поведение |
| --- | --- |
| Положение и оборудование | Native PZ реплицирует игрока и его экипировку. Мод записывает направление тележки в уже существующий `PlayerPacket.prediction.direction`. Обычная motion-посылка тележки не содержит world XY. |
| Дополнительная поза | Lua регистрирует `ToolkitCartPose` и `ToolkitCartActionPose`; Java меняет animation variable, native `VariableSyncPacket` передаёт её через сервер. Собственного cart Lua command relay нет. |
| Motion | Version, cart ID, serial, flags и девять чисел: step X/Y, pace, speed, brake rate, lean, pressure, side clearance, fast weight. Step X/Y — параметры blend, не мировые координаты. Округление — 0.001. |
| Частота | Изменённое motion-состояние — не чаще раза в 100 мс; неизменное — heartbeat раз в секунду. Первый snapshot и смена item identity обходят ограничение. Смена motion flags сама по себе его не обходит. |
| Ground actions | Отдельное состояние с action generation, progress/cancel progress и placement. Смена action generation/flags отправляется сразу. Оно не является общим подтверждением всех native inventory actions. |
| Приём | Хранится последнее значение; числовые параметры и native heading отдельно догоняются экспонентой с tau 60 мс. Истории snapshots и playback clock нет. Serial проверяется на положительность, но не на монотонность. |
| Свежесть | До трёх секунд от наблюдения нового raw value на получателе. Это не возраст исходного снимка владельца: старый пакет из очереди может выглядеть только что полученным. |
| Доставка | В проверенном B42.21 `VariableSyncPacket` использует `RELIABLE_ORDERED`, channel 0. Сервер пересылает другим соединениям, relevant к положению владельца. |

Источники реализации: [CartMotionSync](../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartMotionSync.kt), [CartActionSync](../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartActionSync.kt), [регистрация переменных](../PZSurvivorToolkit/42/media/lua/client/000ToolkitCartMotion.lua), [native hooks](../JavaPatches/src/net/alexredby/pztoolkitjavapatches/Main.java). Transport, framing, native prediction и часы проверены по bytecode установленного `projectzomboid.jar`; файлы игры в репозиторий не копируются.

Порядок TCP здесь не обсуждается: фактическая доставка идёт через RakNet/UDP с надёжностью и упорядочением. Потеря раннего сообщения может задерживать последующие сообщения этого канала; размер такой задержки в текущем Host пока не измерен. Замена на Lua commands не является готовым улучшением: native `ClientCommand` использует reliable unordered delivery, а текущий receiver не отбрасывает старые serial.

## Результат первого baseline

На macOS B42.21 выполнены новые изолированные menu Host проверки с доступными 43 Mod ID и неизменённым Java JAR `7ae3ec60…` (0.1.46): inventory male/full и 26-секундное движение с Walk/Run/Sprint, поворотами, остановками и reverse. Native lifecycle, source/snapshot provenance и логи проверены; это выбранные сценарии, а не полная матрица совместимости.

Близкая камера вновь зафиксировала четыре observer draw с контактом после inventory equip; у владельца контактов нет. Проверка простого следования Spine на свежих позах показала, что его недостаточно: конфигурация Thigh/Calf меняется независимо от бокового смещения Spine. В 0.1.47 внедрена коррекция по двустороннему коридору ног и ручек; её выбранные проверки и ограничения описаны ниже.

Человеческий remote путь вызывает `Prediction.update()`, а `updateLerp()` относится к отдельной animal-ветке. Исходного времени native движения по-прежнему нет. Практический безопасный fallback для текущей коррекции: использовать одну фактическую native render-позу тела, тележки, рук и камеры без дополнительной задержки тележки и без изменения root-motion catch-up. Это не доказательство готовности source-time playback.

В новом trace измерены исходные timestamps TimeSync и applied offset. В выбранном inventory запуске получены обмены с RTT 15.11 и 11.81 мс, без отставания applied offset от midpoint в этих обменах. Offset-интервал `[s-t1,s-t0]` условен для одного exchange; между exchange нет доказанной границы дрейфа. Признак синхронизации и порог 10 мс в native фильтре не дают гарантии точности 10 мс.

В motion baseline первое получение уникального состояния наблюдателем имеет p95 около 42.10 мс по оценкам native server clock. Возраст всех наблюдений имеет p95 около 858.90 мс: сервер также повторно отправляет ранее опубликованное raw value. Эти метрики разделены, cached repeats не выдаются за задержку новой публикации. Полный возраст изображения не измерен.

## Трафик: что известно и чего ещё нет

Native сериализация motion занимает `23 + длина ASCII payload` байт; action — `29 + длина payload`. Дополнительно есть три байта заголовка engine packet, UDP/RakNet framing и возможные повторы доставки. Parser caps 240/300 символов — ограничения входа, не обычный размер пакета.

В сохранённой fast-motion Host-сцене `host08` счётчик владельца вырос на 104 записи и 8845 сериализованных байт за 25.434 секунды: около 4.09 записей/с и 348 байт/с. Выборочно наблюдаемые motion payload имели 54–67 ASCII байт. Это исторический ориентир: JAR сцены `1376d0b6…` отличается от текущего `7ae3ec60…`. Это также счётчик `VariableSync.write`, а не фактический расход сети. Он не учитывает входящий трафик, заголовки, повторы и стоимость всех получателей.

Приблизительная модель серверной стоимости: `средний размер * частота * число relevant соединений`, плюс доставка и повторы. Для нескольких видимых тележек считаются все потоки. Среднее по долгому idle нельзя использовать как бюджет активного манёвра.

Новый baseline 0.1.46: в 26-секундном motion окне владелец имеет 109 serialized writes / 9255 байт (355.96 байт/с), сервер 154 writes / 12942 байт (497.77 байт/с). Серверные записи включают 109 уникальных identities и 45 повторных; адресат каждой записи пока не записан, поэтому повторы и fan-out не разделяются. Native actualBytes server -> observer составляют около 76.5 кбайт/с за 25.514 секунды реально покрытого интервала, включая прочие native данные; 350/135 мс по краям исключены. Наблюдаемый resend delta равен 0 в этом localhost запуске. Это не cart-only wire budget и не проверка WAN/loss.

Начальное предложение бюджета: сохранить обычный потолок 10 Гц и heartbeat 1 Гц; целиться в текущие байт/с на сопоставимом манёвре. Допуск до 10% для необходимых timing/identity metadata — предложение для проверки, не измеренный результат и не повод повысить частоту. Отдельно ограничить burst редких событий и совокупный motion/action трафик. Если формат не помещается, сначала подобрать представление полей на реальных traces, сохраняя точность и диапазоны.

## Внедрённая коррекция и выбранные проверки

`CartLegClearance` использует фактические body/поддерживаемые trouser palettes того же immutable render slot. По точной source-геометрии обеих ног и ручек он выбирает ближайшее боковое смещение в ограниченном коридоре с запасом 1 мм. Ненулевой fit принимается только после проверки source-вершин всей тележки относительно Walk footprint, повторного IK рук и clearance recheck. Native ноги, root budget, action duration и settled stance сохраняются; Blender forward envelope остаётся прежним. Калибровка привязана к хешам исходных assets. Неподдерживаемая одежда не получает гарантии clearance; недоступная или отказанная коррекция оставляет исходную позу. [Повторная калибровка](DEVELOPMENT.md#recalibrating-the-held-leg-clearance-cage) и generated data доступны в репозитории.

На macOS B42.21 с доступными 43 Mod ID завершены чистые isolated menu Host inventory male/full и female/empty, соответствующие SP controls и 26 секунд held Walk/Run/Sprint, поворотов, остановок и reverse. Это выбранное покрытие. В двух новых male/full Host captures исходный контакт обнаруживается при сбросе только cart X в тех же записанных позах и исчезает с fit; максимальная наблюдаемая коррекция 8.131 мм. Это контрфактическое сравнение одной позы, а не два синхронных игровых запуска. В inventory-парах матрицы native ног не изменились; grip и опора колеса сохранены. Более тяжёлая коррекция 22.498 мм проверена source replay и настоящим Java IK на записанных позах; такой максимум ещё не получен в новом live candidate.

В held motion проверено 1177 consumed snapshots owner/observer: пересечений выбранного source body и reference trousers cage с ручками нет, минимальный зазор 2.669 мм. Существенного бокового fit в этом запуске не было. Outfit в motion не выбирался: trousers здесь являются контрольной геометрией, а не доказательством actual worn/GPU cloth. Все проверенные source-вершины тележки внутри Fast footprint; это не проверка native collision целиком. Для SP сохраняются непокрытые границы lifecycle длиной 3–8 мс. Покадровая GPU-геометрия одежды, остальные варианты и эстетическая оценка переходов остаются открыты.

Дополнительная проверка pickup/setdown/cancel/repeat handoffs не завершена: оба свежих запуска остановлены ownership gate до native readiness после исчезновения owned окна из AeroSpace. Эти переходы остаются открытым gate; успешный held-motion capture их не включает.

Протокол и send rate не изменены: bytecode motion/action/heading классов в baseline и candidate совпадает. В активных 26-секундных окнах владелец отправил 109 / 9255 и 107 / 9199 serialized writes/bytes, то есть 355.96 и 353.81 байт/с. Server — 12942 и 13031 байт, включая cached repeats. Это сериализация, не cart-only IP/UDP wire. Сравнение описательное: baseline female с heap 2560 MiB, candidate male с 2048 MiB. Оно не доказывает причинное изменение трафика или стоимости CPU.

Observer first-receipt age p95 составил 41.91/42.39 мс, capture-to-body-draw p95 owner/observer — 1.871/1.840 и 2.829/3.135 мс. Последняя метрика включает fit, IK, инструментацию, планирование и rendering; отдельную стоимость fit не выделяет. Изолированный тёплый source/SAT replay дал mean 1.133 мс, p95 1.681 мс; он не включает live slot, footprint gate, IK и GPU upload. Один startup TimeSync exchange на роль не ограничивает последующий clock drift. Поэтому отдельная cart delay не добавлена, а source-time playback остаётся за native-time alignment gate.

## Основное ограничение PZ

Native remote movement использует извлечённое движение корневой кости анимации — root motion — для догоняния позиции. В [CartMotionSync.applyLocomotion](../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartMotionSync.kt) поэтому сохранён свежий предыдущий moving budget. Принудительная поза остановившегося владельца может лишить наблюдателя этого budget и остановить догоняние. Этот механизм нельзя удалять ради совпадения картинки.

Известный успешный male/full inventory-equip Host capture показывает контакт левых брюк с ручкой на четырёх draw-bound снимках через 344–394 мс после первого held snapshot; два также пересекают нижнюю часть исходного body mesh. В этот момент у наблюдателя ещё живы Walk/WalkSlow/CartWalk и CartIdle, Loot уже отсутствует, владелец не пересекает ручки. Это доказывает несовпадение текущей presentation на выбранном переходе. Оно не доказывает, что причина — недостаточная частота сети. Это source meshes с измеренными bones; точная GPU-палитра одежды и все отрисованные кадры остаются отдельной проверкой.

Нужны два явно разделённых потребителя: native locomotion budget для движения и единое согласованное состояние для отрисовки body/cart/hands/camera. Разделение не означает, что native skeleton уже можно независимо перемотать: его root motion всё ещё используется игрой. Сначала нужно доказать безопасную границу. Для текущего clipping первым кандидатом остаётся presentation относительно фактически измеренных native bones при неизменной частоте сети.

Уже существующие [CartObserverRender](../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartObserverRender.kt) и [CartObserverPose](../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartObserverPose.kt) связывают cosmetic correction с producer camera и worker model slot. Их immutable pair и collision/reachability checks следует расширять согласованно. Другая поза камеры, тела и тележки в одном draw недопустима.

## Предлагаемая архитектура

### 1. Измерить и связать временные шкалы

Записывать source sample time, получение native движения и cart state, animation update, camera/slot capture и consumed draw. Сопоставлять по owner, cart, session/action epoch и точному draw identity; ближайший wall timestamp сам по себе недостаточен.

В игре есть `GameTime.getServerTime()` / `getServerTimeMills()` и признак `getServerTimeShiftIsSet()`. Клиентский `getServerTime()` возвращает ноль до синхронизации. Это возможная общая шкала, но её погрешность, корректировки и startup требуют измерения. В проверенном `Prediction` wire layout нет исходного timestamp владельца; `predictionTimeRemaining` вычисляется на приёме из distance/speed. Поэтому добавления timestamp только в cart packet недостаточно для точного совмещения с native player presentation.

Первый технический gate — показать, как измеряется время отображаемого native движения и его связь со снимком владельца. Если точная связь недоступна, явно ограничить погрешность и выбрать безопасный fallback. Не приписывать `System.nanoTime()` разных машин общую эпоху. Не вводить отдельную задержку только тележке: она рассогласует её с телом.

### 2. Сделать компактный контракт presentation

Предложение следующей версии: cart identity, session/presentation epoch, monotonic sequence, source sample time, semantic movement/action mode и минимальные управляющие параметры. Для циклической анимации phase anchor добавлять только если измерен значимый дрейф; для одноразового действия использовать generation, start/anchor time, duration/rate и cancel/recovery anchor. Wheel phase сначала восстанавливать из фактического движения; отдельную коррекцию передавать лишь при доказанной необходимости.

Один и тот же контракт должен описывать состояние для владельца и наблюдателя, хотя native locomotion потребляет его по-разному. Кости и готовые per-frame матрицы передавать не нужно: они вычисляются из общих локальных assets, параметров и IK. Blender остаётся инструментом авторинга клипов и кривых; сетевой контракт описывает их время и параметры.

Session epoch отделяет reconnect, новый action, повторное использование online ID и замену тележки. Receiver отбрасывает старые/повторные snapshots; release и protected states имеют определённый порядок. Обработка переполнения компактных sequence/time, несинхронизированных часов и смены версии — часть контракта. Смешанные версии не должны молча трактовать новый формат как v1.

Release, stale timeout, death/protected state, потеря/замена item, disconnect, повторное использование actor ID и выход в меню инвалидируют историю playback и phase/action anchors. Нужен lifecycle fence по epoch/sequence/source time: queued или позднее старое состояние не может заново включить позу; повторный вход требует свежего допустимого состояния по контракту новой lease. Отдельный тест: buffered moving/action state -> immediate release -> delayed old state не возвращает presentation. Уже сформированную immutable camera/slot пару нельзя разрывать посередине worker draw: она завершается согласованно до postRender, а fence запрещает следующие захваты старого состояния.

Native оборудование, cargo, ActionManager transaction и игровые эффекты сохраняют свою authority. Cosmetic progress=1 не подтверждает получение предмета. Обычный inventory equip нужно связывать с его настоящим native lifecycle; ground-pickup clip нельзя использовать вместо inventory Loot.

### 3. Воспроизводить историю во времени

После gate временного совмещения ввести маленькую ограниченную историю snapshots и монотонное время playback. Непрерывные параметры интерполировать между снимками; bool/mode/cart/action identity переключать в момент события. Циклическую фазу интерполировать с учётом перехода 1 -> 0. Не добавлять поверх буфера прежнее полное сглаживание tau 60 мс: суммарную задержку всех слоёв нужно измерять.

Начать с линейной интерполяции параметров и shortest-arc для yaw. Hermite имеет смысл только при необходимости интерполировать position и наличии согласованных velocity; в текущем motion payload position нет, а native XY уже ведёт игра. Это не основание добавлять второй поток координат.

Буфер сглаживает нерегулярные приходы ценой задержки; размер выбирается по измеренным jitter/underrun и native presentation age. [Snapshot Interpolation, Glenn Fiedler](https://gafferongames.com/post/snapshot_interpolation/) объясняет этот компромисс; его демонстрационные миллисекунды не являются настройкой PZ. При underrun допускается только ограниченное продолжение безопасных непрерывных параметров, затем удержание/fallback. Нельзя предсказывать владение предметом, успешное действие или проход через стену. Late start/stop/brace/cancel требуют отдельной политики, а не длинного плавного догоняния неправильного режима.

### 4. Уложиться в бюджет и менять transport только по данным

Сначала сохранить существующий `VariableSync`, квантование, релевантность и частоты. Сравнить компактные integer/bit flags и исходный CSV на записанных данных; ошибка представления должна укладываться в геометрические/фазовые допуски. Редкие важные переходы могут идти сразу, но их burst должен быть ограничен. Каждый непрерывный snapshot должен быть самодостаточным; цепочка deltas потребует подтверждений и resync, которые пока не оправданы.

Приоритет свежих snapshots и разделение доставки событий/непрерывного состояния — полезная практика; [Reliable Ordered Messages, Glenn Fiedler](https://gafferongames.com/post/reliable_ordered_messages/) рассматривает стоимость различных моделей надёжности. Для этого проекта переход на unreliable/sequenced transport — условный следующий этап, только если измерен мешающий backlog. Нельзя менять reliability общего `VariableSync` для других переменных. Public custom packet registration в проверенном API не найден: отдельный bounded prototype обязан доказать registration, sender validation, relay/AOI, malformed input handling и client/server installation. Public `startPacket/endPacket` сами по себе не дают безопасного receive handler.

Отдельные роли владельца и simulated proxy — стандартный принцип; пример есть в [Unreal Character Movement](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine). Это ориентир для разделения ответственности, а не описание PZ или предложение переносить Unreal replication целиком.

## Проверка и порядок внедрения

Использовать [существующий Host fixture](../tests/native_queue/contributions/wooden_cart_multiplayer/README.md), `ClearanceProbe`, consumed body/cart/camera receipts, `CartMotionSyncTest` / `CartActionSyncTest`, Blender replay и native geometry checks. Opt-in `cart_timeline` уже пишет publication/native/render traces, отдельные first-delivery и repeated-value ages, TimeSync exchanges и native per-connection actualBytes/resend counters. Полный IP/UDP wire scope, точный recipient fan-out и общий source presentation time остаются открыты. Готового cart delay/loss playback harness в просмотренных этих файлах нет.

1. Baseline и native-time alignment spike. До результата не выбирать размер буфера и не переписывать транспорт.
2. Воспроизводимый observer inventory-equip defect и безопасная presentation correction при прежней частоте. Сохранить положительный контроль residual Walk/CartWalk и исходные записи.
3. Versioned state/epoch/time contract и codec/replay tests. Сравнить размеры и ошибки на одинаковых traces.
4. Timeline playback с проверенным native-time bridge; затем тот же Host и сетевые условия.
5. Оптимизация payload; transport prototype только при доказанной необходимости. Удалять заменяемых consumers вместе с миграцией, не оставлять два активных способа управления позой.

Два уровня сетевых тестов: deterministic receiver replay для задержек/потерь/перестановок и отдельный реальный Host с impairment только его disposable соединений. В проверенном установленном macOS B42.21 работающего native per-owned-client delay/jitter/loss API не найдено: Java/JNI setter отсутствует, экспортированные C++ `ApplyNetworkSimulator` на arm64/x86_64 являются no-op. Отключение client main loop не создаёт очередь отложенной доставки. Для настоящего impairment нужен отдельный ограниченный test-only packet scheduler с проверкой владения буферами и lifecycle; он ещё не реализован. Replay после доставки не проверяет RakNet retransmission или head-of-line blocking. Профили эксперимента: чистая сеть; RTT 50/100/200 мс; jitter до 20/50 мс; loss 1/3/5%, burst loss, duplicates/reorder и пауза кадров клиента. Это выбранные условия испытания, не заявленная поддержка уже сейчас. Начать с малой матрицы, расширять по выявленным рискам. Системные network/firewall settings и пользовательский игровой профиль не менять.

Измерять p50/p95/p99 полного возраста изображения, время и число buffer underrun, ошибку позы на одном playback time, root-motion catch-up/stalls, grip/floor/foot slip, source/actual garment clearance, отсутствие snap на switch/release и bytes/s в активных окнах. Скорость камеры и плавный график сами по себе не означают верную анимацию. Численные пороги phase/foot-slip выбрать и записать после калибровки baseline; до этого не выдавать PASS по произвольным допускам.

Гейты: выбранный contact reproduction больше не пересекается; ноги, native collision/manual reverse и action duration сохранены; inventory/cargo IDs и native completion верны на сервере, owner и observer; чистые логи и полностью сохранённые записи; трафик в согласованном бюджете; задержка и ухудшение при loss показаны отдельно. Если нет actual garment GPU evidence или покадрового покрытия, это остаётся явным ограничением. Проверять macOS SP и menu Host с изолированными настройками/сейвами и доступным набором модов. Отдельный dedicated server и Windows стенд не являются гейтами этой задачи.
