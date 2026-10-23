# Cart multiplayer presentation design

[Development](../DEVELOPMENT.md) · [Current player behavior](../features/VEHICLES.md#saucedcarts) · [Open implementation gates](../../TODO.md#cart-multiplayer-presentation)

This is an engineering proposal, not a guide to features already available. Production uses the native replication and render correction described below. A versioned presentation protocol, source-time playback and a bounded network-impairment harness are still proposals. Implementation steps and remaining gates live in TODO.

Цель — близкое к владельцу, плавное изображение у наблюдателя при нынешнем порядке трафика. При сетевой задержке сравнивать нужно один момент движения с отдельно измеренной задержкой показа.

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

Источники реализации: [CartMotionSync](../../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartMotionSync.kt), [CartActionSync](../../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartActionSync.kt), [регистрация переменных](../../PZSurvivorToolkit/42/media/lua/client/000ToolkitCartMotion.lua), [native hooks](../../JavaPatches/src/net/alexredby/pztoolkitjavapatches/Main.java). Transport, framing, native prediction и часы проверены по bytecode установленного `projectzomboid.jar`; файлы игры в репозиторий не копируются.

Порядок TCP здесь не обсуждается: фактическая доставка идёт через RakNet/UDP с надёжностью и упорядочением. Потеря раннего сообщения может задерживать последующие сообщения этого канала; размер такой задержки в текущем Host пока не измерен. Замена на Lua commands не является готовым улучшением: native `ClientCommand` использует reliable unordered delivery, а текущий receiver не отбрасывает старые serial.

## Измерения и ограничения

Разделять задержку первого получения нового состояния, возраст cached repeats и полный возраст изображения. Повторная серверная отправка старого raw value не является новой публикацией. `VariableSync.write` считает сериализацию, а не полный IP/UDP расход: нужны framing, повторы и recipient fan-out. Приблизительная стоимость сервера — средний размер * частота * число relevant соединений, плюс delivery overhead. Idle-среднее не задаёт бюджет активного манёвра.

Native motion сериализуется как `23 + длина ASCII payload` байт, action — `29 + длина payload`, до заголовка engine packet и UDP/RakNet framing. Parser caps 240/300 символов не описывают обычный размер пакета. Начальный бюджет для сравнения: сохранить motion ceiling 10 Гц и heartbeat 1 Гц; до 10% на необходимые timing/identity metadata — предложение для проверки. Учитывать motion, action, control messages, resync и редкие bursts вместе.

`CartLegClearance` использует body и поддерживаемые trouser palettes одного immutable render slot. Коррекция выбирает ближайший боковой коридор с source-margin 1 мм, повторно проверяет IK и Walk footprint; asset hashes ограничивают калибровку. Неподдерживаемая одежда и недоступная коррекция оставляют исходную позу. [Повторная калибровка](../development/ANIMATION.md#recalibrating-the-held-leg-clearance-cage). Измеренные source meshes и записанные matrices не доказывают actual GPU cloth или каждый отрисованный кадр.

Native human remote path использует `Prediction.update()`, а `updateLerp()` относится к animal-ветке. Native root motion участвует в догонянии позиции; нельзя останавливать его ради совпадения картинки. До доказанного native-time bridge безопасная граница — фактическая общая render-поза тела, тележки, рук и камеры без отдельной задержки тележки.

TimeSync exchange даёт условный offset-интервал `[s-t1,s-t0]`, но не границу дрейфа между обменами. Одинаковые exact body bytes могут соответствовать нескольким source generations. Accepted-input association не означает единственный источник stateful skeleton. Признак синхронизации и порог native фильтра не гарантируют заданную точность часов.



## Основное ограничение PZ

Native remote movement использует извлечённое движение корневой кости анимации — root motion — для догоняния позиции. В [CartMotionSync.applyLocomotion](../../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartMotionSync.kt) поэтому сохранён свежий предыдущий moving budget. Принудительная поза остановившегося владельца может лишить наблюдателя этого budget и остановить догоняние. Этот механизм нельзя удалять ради совпадения картинки.

Нужны два явно разделённых потребителя: native locomotion budget для движения и единое согласованное состояние для отрисовки body/cart/hands/camera. Разделение не означает, что native skeleton уже можно независимо перемотать: его root motion всё ещё используется игрой. Сначала нужно доказать безопасную границу. Для текущего clipping первым кандидатом остаётся presentation относительно фактически измеренных native bones при неизменной частоте сети.

Уже существующие [CartObserverRender](../../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartObserverRender.kt) и [CartObserverPose](../../JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartObserverPose.kt) связывают cosmetic correction с producer camera и worker model slot. Их immutable pair и collision/reachability checks следует расширять согласованно. Другая поза камеры, тела и тележки в одном draw недопустима.

## Предлагаемая архитектура

### 1. Измерить и связать временные шкалы

Записывать source sample time, получение native движения и cart state, animation update, camera/slot capture и consumed draw. Сопоставлять по owner, cart, session/action epoch и точному draw identity; ближайший wall timestamp сам по себе недостаточен.

В игре есть `GameTime.getServerTime()` / `getServerTimeMills()` и признак `getServerTimeShiftIsSet()`. Клиентский `getServerTime()` возвращает ноль до синхронизации. Это возможная общая шкала, но её погрешность, корректировки и startup требуют измерения. В проверенном `Prediction` wire layout нет исходного timestamp владельца; `predictionTimeRemaining` вычисляется на приёме из distance/speed. Поэтому добавления timestamp только в cart packet недостаточно для точного совмещения с native player presentation.

Первый технический gate — показать, как измеряется время отображаемого native движения и его связь со снимком владельца. Если точная связь недоступна, явно ограничить погрешность и выбрать безопасный fallback. Не приписывать `System.nanoTime()` разных машин общую эпоху. Не вводить отдельную задержку только тележке: она рассогласует её с телом.

### 2. Сделать компактный контракт presentation

Предложение следующей версии: cart identity, session/presentation epoch, monotonic sequence, source sample time, semantic movement/action mode и минимальные управляющие параметры. Для циклической анимации phase anchor добавлять только если измерен значимый дрейф; для одноразового действия использовать generation, start/anchor time, duration/rate и cancel/recovery anchor. Wheel phase сначала восстанавливать из фактического движения; отдельную коррекцию передавать лишь при доказанной необходимости.

Один и тот же контракт должен описывать состояние для владельца и наблюдателя, хотя native locomotion потребляет его по-разному. Кости и готовые per-frame матрицы передавать не нужно: они вычисляются из общих локальных assets, параметров и IK. Blender остаётся инструментом авторинга клипов и кривых; сетевой контракт описывает их время и параметры.

Для v2 сначала нужна независимая admission authority: server-owned actor grant, связанный с фактическим native соединением и lifetime игрока, плюс общая для motion/action монотонная presentation lease и sequence. OPEN/UPDATE/END должны иметь порядок; END окончательно закрывает lease. Счётчики и high-water fence живут отдельно от визуальных Sender/Remote: сейчас reset/end удаляют Sender и начинают serial заново, а пустая строка не является упорядоченным tombstone. Reconnect, respawn/online ID reuse и замена тележки требуют подтверждённой новой привязки. Случайный UUID сам по себе не доказывает, что неизвестное состояние новое; маленький TTL/list retired UUID тоже этого не гарантирует.

В проверенном native пути VariableSync сохраняет raw value на сервере до relay, а ConnectedPlayer сопровождается повторной отправкой cached custom variables. Поэтому нельзя просто подписать текущим grant старую строку при сериализации. Нужна проверка до storage/relay и защищённый server control key; источник обязан вернуть выданный ему grant. Ordered bind/retire barrier требует отдельного доказательства всей цепочки native dispatch; одинаковые reliability/channel у пакетов не доказывают её сами. Если barrier не подтверждён, нужен fresh challenge/reply с точным текущим actor/lease binding. До этого неизвестный grant/lease не принимается. Rejected duplicates/old/unknown state не обновляют freshness, smoothing или native locomotion budget. Source time с неизвестной погрешностью не заменяет lifecycle authority.

Обработка переполнения compact sequence/time, несинхронизированных часов и смены версии — часть контракта; при исчерпании счётчика нужна авторизованная новая привязка, без silent wrap. Смешанные версии не должны молча трактовать новый формат как v1. Cosmetic END/progress никогда не подтверждает native equipment или успех действия.

Проверка размера на двух сохранённых motion traces показала: 13-byte packing тех же девяти scalar с шагом 0.001 не меняет значений; кандидат envelope с grant/lease/sequence/time и native string framing занимает примерно на 10–12% меньше текущего. Резерв ещё 12 bytes под пока не определённый native-time anchor даёт около +7–8.4% serialized bytes. Это sizing experiment, не реализованный codec/контракт и не измерение wire overhead; action envelope, control messages и burst/resync ещё входят в будущий общий бюджет.

Release, stale timeout, death/protected state, потеря/замена item, disconnect, повторное использование actor ID и выход в меню инвалидируют историю playback и phase/action anchors. Нужен lifecycle fence по epoch/sequence/source time: queued или позднее старое состояние не может заново включить позу; повторный вход требует свежего допустимого состояния по контракту новой lease. Отдельный тест: buffered moving/action state -> immediate release -> delayed old state не возвращает presentation. Уже сформированную immutable camera/slot пару нельзя разрывать посередине worker draw: она завершается согласованно до postRender, а fence запрещает следующие захваты старого состояния.

Native оборудование, cargo, ActionManager transaction и игровые эффекты сохраняют свою authority. Cosmetic progress=1 не подтверждает получение предмета. Обычный inventory equip нужно связывать с его настоящим native lifecycle; ground-pickup clip нельзя использовать вместо inventory Loot.

### Проверенный прототип admission и следующий гейт

Reference-контроллер `grant/lease/sequence` реализован в [test-only Lua](../../tests/native_queue/contributions/wooden_cart_multiplayer/lease-protocol.lua). Он принимает authority из native adapter, запрещает самопринятие неизвестного grant/lease, сохраняет сравнимые fences отдельно от видимости, окончательно закрывает sequenced END и останавливается при исчерпании counters/cap. Детерминированные LuaJIT сценарии проверяют duplicates/late state, END-before-OPEN, пропущенную lease, одинаковые ID с новыми native объектами, смену режима, reconnect и отсутствие обновления freshness от отклонённого пакета. Это проверка модели, не доказательство всех входов native adapter.

Held-only эксперимент проверяет привязку текущей удерживаемой тележки и источник сообщения. Release/reacquire, reconnect и authority action lifetime требуют отдельных сценариев; [контракт фикстуры](../../tests/native_queue/contributions/wooden_cart_multiplayer/README.md#fresh-lease-admission-experiment) описывает границы.

Для действий следующий кандидат — фактически принятый сервером `NetTimedAction` с его native Lua action table, source connection/actor и resolved item/world binding. Уже существующие [ActionAcknowledgements](../../JavaPatches/src/net/alexredby/pztoolkitjavapatches/ActionAcknowledgements.java) дают token по точному серверному объекту и owner receipts; наличие точного соответствия для выбранных cart actions нужно проверить в новом native сценарии. `ActionManager.start` вызывается до выставления Accept; terminal поля могут меняться напрямую при update, а byte transaction ID переиспользуется. Ненулевой observer `getAction()` также сохраняется после `stopAction()`. Поэтому grant нельзя выдавать по одному start/getAction/byte-ID lookup. Связь принятой серверной транзакции с конкретным observer BaseAction/StatePacket и его presentation проверяется отдельно; owner receipt не доказывает её автоматически.

### 3. Воспроизводить историю во времени

После gate временного совмещения ввести маленькую ограниченную историю snapshots и монотонное время playback. Непрерывные параметры интерполировать между снимками; bool/mode/cart/action identity переключать в момент события. Циклическую фазу интерполировать с учётом перехода 1 -> 0. Не добавлять поверх буфера прежнее полное сглаживание tau 60 мс: суммарную задержку всех слоёв нужно измерять.

Начать с линейной интерполяции параметров и shortest-arc для yaw. Hermite имеет смысл только при необходимости интерполировать position и наличии согласованных velocity; в текущем motion payload position нет, а native XY уже ведёт игра. Это не основание добавлять второй поток координат.

Буфер сглаживает нерегулярные приходы ценой задержки; размер выбирается по измеренным jitter/underrun и native presentation age. [Snapshot Interpolation, Glenn Fiedler](https://gafferongames.com/post/snapshot_interpolation/) объясняет этот компромисс; его демонстрационные миллисекунды не являются настройкой PZ. При underrun допускается только ограниченное продолжение безопасных непрерывных параметров, затем удержание/fallback. Нельзя предсказывать владение предметом, успешное действие или проход через стену. Late start/stop/brace/cancel требуют отдельной политики, а не длинного плавного догоняния неправильного режима.

### 4. Уложиться в бюджет и менять transport только по данным

Сначала сохранить существующий `VariableSync`, квантование, релевантность и частоты. Сравнить компактные integer/bit flags и исходный CSV на записанных данных; ошибка представления должна укладываться в геометрические/фазовые допуски. Редкие важные переходы могут идти сразу, но их burst должен быть ограничен. Каждый непрерывный snapshot должен быть самодостаточным; цепочка deltas потребует подтверждений и resync, которые пока не оправданы.

Приоритет свежих snapshots и разделение доставки событий/непрерывного состояния — полезная практика; [Reliable Ordered Messages, Glenn Fiedler](https://gafferongames.com/post/reliable_ordered_messages/) рассматривает стоимость различных моделей надёжности. Для этого проекта переход на unreliable/sequenced transport — условный следующий этап, только если измерен мешающий backlog. Нельзя менять reliability общего `VariableSync` для других переменных. Public custom packet registration в проверенном API не найден: отдельный bounded prototype обязан доказать registration, sender validation, relay/AOI, malformed input handling и client/server installation. Public `startPacket/endPacket` сами по себе не дают безопасного receive handler.

Отдельные роли владельца и simulated proxy — стандартный принцип; пример есть в [Unreal Character Movement](https://dev.epicgames.com/documentation/en-us/unreal-engine/understanding-networked-movement-in-the-character-movement-component-for-unreal-engine). Это ориентир для разделения ответственности, а не описание PZ или предложение переносить Unreal replication целиком.

## Проверка и порядок внедрения

Следующий timing-инструмент теперь записывает точные body bytes native PlayerPacket, локальные epochs и поколения source/ingress/accepted input, включая отдельные submit/cancel и server fan-out. Анализ одинаковых source samples остаётся неоднозначным; accepted input не является единственным источником stateful skeleton. Отдельный `cart_time_alignment` включает ограниченные повторные native TimeSync requests только в disposable Host, а пассивный `cart_timeline` сам запросов не добавляет. [Контракт эксперимента](../../tests/native_queue/contributions/wooden_cart_multiplayer/README.md#exact-native-input-timing-experiment) описывает пределы и воспроизведение. Exact accepted-input/draw association может быть неоднозначной; общий native-time bridge остаётся открытым. Production протокол и playback не менялись.

Использовать [существующий Host fixture](../../tests/native_queue/contributions/wooden_cart_multiplayer/README.md), `ClearanceProbe`, consumed body/cart/camera receipts, `CartMotionSyncTest` / `CartActionSyncTest`, Blender replay и native geometry checks. Opt-in `cart_timeline` уже пишет publication/native/render traces, отдельные first-delivery и repeated-value ages, TimeSync exchanges и native per-connection actualBytes/resend counters. Полный IP/UDP wire scope, точный recipient fan-out и общий source presentation time остаются открыты. Готового cart delay/loss playback harness в просмотренных этих файлах нет.

1. Baseline и native-time alignment spike. До результата не выбирать размер буфера и не переписывать транспорт.
2. Воспроизводимый observer inventory-equip defect и безопасная presentation correction при прежней частоте. Сохранить положительный контроль residual Walk/CartWalk и исходные записи.
3. Versioned state/epoch/time contract и codec/replay tests. Сравнить размеры и ошибки на одинаковых traces.
4. Timeline playback с проверенным native-time bridge; затем тот же Host и сетевые условия.
5. Оптимизация payload; transport prototype только при доказанной необходимости. Удалять заменяемых consumers вместе с миграцией, не оставлять два активных способа управления позой.

Два уровня сетевых тестов: deterministic receiver replay для задержек/потерь/перестановок и отдельный реальный Host с impairment только его disposable соединений. В проверенном установленном macOS B42.21 работающего native per-owned-client delay/jitter/loss API не найдено: Java/JNI setter отсутствует, экспортированные C++ `ApplyNetworkSimulator` на arm64/x86_64 являются no-op. Отключение client main loop не создаёт очередь отложенной доставки. Для настоящего impairment нужен отдельный ограниченный test-only packet scheduler с проверкой владения буферами и lifecycle; он ещё не реализован. Replay после доставки не проверяет RakNet retransmission или head-of-line blocking. Профили эксперимента: чистая сеть; RTT 50/100/200 мс; jitter до 20/50 мс; loss 1/3/5%, burst loss, duplicates/reorder и пауза кадров клиента. Это выбранные условия испытания, не заявленная поддержка уже сейчас. Начать с малой матрицы, расширять по выявленным рискам. Системные network/firewall settings и пользовательский игровой профиль не менять.

Измерять p50/p95/p99 полного возраста изображения, время и число buffer underrun, ошибку позы на одном playback time, root-motion catch-up/stalls, grip/floor/foot slip, source/actual garment clearance, отсутствие snap на switch/release и bytes/s в активных окнах. Скорость камеры и плавный график сами по себе не означают верную анимацию. Численные пороги phase/foot-slip выбрать и записать после калибровки baseline; до этого не выдавать PASS по произвольным допускам.

Гейты: выбранный contact reproduction больше не пересекается; ноги, native collision/manual reverse и action duration сохранены; inventory/cargo IDs и native completion верны на сервере, owner и observer; чистые логи и полностью сохранённые записи; трафик в согласованном бюджете; задержка и ухудшение при loss показаны отдельно. Если нет actual garment GPU evidence или покадрового покрытия, это остаётся явным ограничением. Проверять macOS SP и menu Host с изолированными настройками/сейвами и доступным набором модов. Отдельный dedicated server и Windows стенд не являются гейтами этой задачи.
