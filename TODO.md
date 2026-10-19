# Wooden wheelbarrow collisions

- [ ] Finish relative-key manual reverse wall exits: remove small accumulated opposite-yaw corrections and release drift under tight contact, and obtain complete <=500 ms sampling and route edges for all eight scenes. Keep the existing <=.02 rad opposite-yaw and <=.025 rad release budgets; do not relax them to accept the current captures. Extend to female models and MP; preserve manual reverse, natural rolling and native collision, without automatic backing.
- [ ] On the next shared cart-native run, obtain the standard path report with same-tick CancelAction/terminal accounting fixed: the saved 24 routes were checked in separate analysis; leave the original report unchanged. The shared visual gate remains open due to wide-trouser contact with the left handle and unclassified font messages.
- [ ] Check the wooden wheelbarrow's braced stance in the remaining collision scenes: the full bank with a female model and Walk with a full load. Check feet, grip, wheel and absence of jolts; test Run/Sprint and impact in separate scenarios.

# Natural wooden wheelbarrow animation

## Maneuvers and transitions

- [ ] Check the full maneuver matrix: straight travel, ±45°/±90°/±135°, 180° arcing turns in both directions at Run/Sprint, repeated screen-up/down slaloms with different side-switch intervals, exiting a turn and stopping on an arc; for other maneuvers, separately test Walk/Run/Sprint, both sexes, and an empty/full wheelbarrow. The opposite key remains a command to move backward; test a U-turn as a sequential arc, and do not present reverse as a turn.
- [ ] Extend live checks of forward/backward transitions at the reverse 130°/140° boundary and during collision, state reset and cart replacement; the math and hook regressions for these cases already exist. The full visual gate remains open until the pose defects below are resolved.
- [ ] Extend collision checks with the remaining Walk/Run/Sprint combinations for frontal bracing and angled contact, Walk sliding, and the remaining gait/sex/load combinations at a real door. Check load changes, falling/combat/releasing the cart and safe state reset. Do not count scenarios that have not been ported as passing.

## Pickup and put-down

- [ ] Проверить быстрый повтор подхвата/постановки после исправления стыка кистей: complete-chain, pickup-restart и drop-restart с полным грузом. Предыдущая попытка запуска остановлена проверкой свободного места; потребуется не менее 2.3 ГБ плюс резерв других активных стендов. Сохранить хват, груз, колесо и однозначное владение тачкой.

- [ ] In game, check putting down a wooden wheelbarrow via the SaucedCarts hotkey: completion/cancellation and quick repeat, position in the adjacent square, grip, wheel and world/held handoff; separately confirm owner/server/observer in MP. Local checks do not replace the visual and network gate.

- [ ] Extend pickup clearance checks to the remaining approach angles and clothing combinations. Check all skin/pants geometry at Thigh/Calf, not just the pelvis; preserve the agreed shallow crouch, foot support, knee direction and grip.
- [ ] Check wheel phase continuity during an emergency pickup/put-down reset; preserve verified ownership, load and grip recovery.
- [ ] Extend pickup/put-down cancellation checks to Run/Sprint movement, tempo changes and releasing WASD before recovery ends. Preserve limited pose return, grip, arm lengths, wheel phase and repeat action; already checked Walk/CancelAction does not cover these variants.
- [ ] Check pickup from a container and approaches to the handles from the wrong side/across obstacles, including a blocked final alignment step, cancellation/target loss during approach and an independent queued action after it. Preserve native collision, the single authoritative complete and exact itemId/XYZ.
- [ ] For pickup/put-down, extend live checks to cancellation before MP handoff, a late network result, item loss/replacement, cart destruction, stairs, combat/fall/death and restarting after these events. Preserve verified exact IDs/load and world/held handoff; do not delay emergency instant-drop. Lua/hook regressions do not replace the native visual gate and MP owner+observer.

## Known pose defects

- [ ] Remove rare contact between wide jeans and the handles in the original straight pose, near it and at the start of the reverse arc, preserving the preferred hand and torso position. Contact remains in some zero-lean phases and nearby; also check the short Walk -> Cart Idle transition while equipping. Include Walk with a full load alongside a vehicle at 45° to the right: the left handle touches the trousers at about 4.18 s in scene `male-full-vehicle-yaw45-slide-right` in capture `cart-vehicles-20261018/native05`.
- [ ] For the selected turn, check the grip surface and thumb on both hands and both sexes: in the prototype without raising the handles, the hand angle relative to the handle changes from 25° to 35°, while the original palm depth and finger curl are preserved.

# Root fix for the action queue

These are implementation and verification gaps, not evidence that every action using the old completion path is broken. Keep working native behavior while migrating one verified family at a time.

- [ ] Extend live SP/MP gates for the shared lifecycle to the remaining families: unavailable target, late continuation, exact consumption and independent tail, before replacing their local completion intercepts.
- [ ] Check the shared outcome protocol with two real MP clients during reset/death/disconnect, byte ID reuse, late and duplicate responses, and network delays; supplement the already completed boundary checks using native Java/Lua fixtures.
- [ ] Remove the remaining family-specific bypasses after the corresponding SP/MP checks; preserve fallback for unsupported Java/server versions, resource contracts and separate medical/cart sync fixes.

# Further action queue migration

The executor remains `ISTimedActionQueue`. Add new families through Definitions/Policy and a precise adapter, without a general planning graph, second scheduler or reservation of future inventory. Check display and permission to change the queue separately. Only unfinished work is listed below; interfaces are described in the [features guide](docs/FEATURES.md), and check commands are in the [developer guide](docs/DEVELOPMENT.md).

## Known limits of move/cancel controls

These operations can execute normally while some queue controls remain disabled. The work below is to prove safe edits; real shared dependencies and required cleanup must remain protected. Current behavior is described in the [action queue limits](docs/FEATURES.md#supported-actions-and-limits).

- [ ] Vehicle fuel and wreck dismantling: reordering and individual cancellation remain protected because containers/tools are chosen at execution time. Define exact contracts for shared cans, hoses, masks and blowtorches before enabling these controls. Preserve deferred selection, native fuel transactions, wreck removal and the unrelated queue tail.
- [ ] Project Cook evolved recipes: ingredient application and compensating consumed-spice cleanup protect the operation from cancellation. Define which edits, if any, are independent of already-applied ingredients; preserve authoritative consumption and required cleanup rather than dropping the cleanup step.
- [ ] Complex handcraft recipes: identify concrete blocked recipes with Lua callbacks, fluid/energy inputs, unrestricted item selection or replacement/depletion/break effects. Add narrow resource/output contracts where practical; keep actual shared materials and shared crafting UI ordered. Plain-item crafting support is not an unfinished item here.
- [ ] Medical world pickups and unknown treatment producers: add exact item/patient/wound contracts for specific unsupported entry points before allowing edits. Preserve native wound checks, supplies and clothing effects; do not mark all medicine unsupported.
- [ ] Carried-container capacity: MP does not credit space that a previous pending pickup may free; synthetic proximity endpoints and unknown capacity callbacks also remain protected. Prove exact source/destination/ancestor capacity and authoritative transfer effects before relaxing a concrete blocked case.
- [ ] Unknown mod actions and asynchronous continuations: capture the concrete action type, producer, continuation and cleanup when an operation is split into separate rows or becomes an edit barrier. Add scoped grouping/edit contracts for reviewed entry points; unknown or modified callbacks must retain a clear denial reason.

## Shared game sessions and build regression

- [ ] Extend the common scenario contracts beyond equipment and fluid drinking. Map audited cases/outcomes per action, reuse `QueueScenarioChecks`, and keep unimplemented/inapplicable requirements explicit. Prioritize empty initial queue, repeated requests, lost/replaced resources and unavailable return containers; include worn bags and favorite-item variants where relevant. Gate: exact effects and cleanup in selected SP/Host runs with matching native controls and clean log audits.

- [ ] Recheck affected source-pinned queue integrations against the updated Workshop sources. Start with Project Cook’s changed EvoPanel, including new base-item return/retry paths. Compare the explicitly locked working baseline with current callbacks and run the affected SP/Host cases with queue-disabled controls; source changes must not silently inherit old permissions or old test results.
- [ ] Cart chat: integrate the published combined SP cart matrices and collision cases after their native checks are complete. Keep independent cold controls; separately measure an explicit full regression profile (the estimated 17 startup cycles instead of 29 are not yet confirmed).

## Near-term adapters

The medical packet mismatch below is an unresolved runtime observation; its cause has not been attributed to queue scheduling. Cart work remains owned by the cart chat.

Add contracts in Definitions/Policy/Operations for each family. Expose only verified capabilities; leave the rest with an explicit denial reason.

- [ ] SaucedCarts: world/vehicle/floor endpoints and custom callbacks need separate contracts. Add correlated server results with protection against duplicate/late responses before removing protection for active MP transfer and MP returns; check failure/partial batch without predicting success. Separately check replacing/resetting the cart itself while held; generators are currently protected while the cart is held. If needed, extend the capacity proof to deferred installation of upstream hooks and proven effects of the freed space.
- [ ] Native MP medicine: obtain a live reproduction of the rare `SyncVisualsPacket` count mismatch 7/8 from MP10 using the preserved diagnostic setup `tests/native_queue/contributions/visual-sync`. Compare ordered IDs before write and after parse, asset readiness and in-flight old snapshots; establish the cause of the specific failure. Gate for any fix: a positive regression case, correct 8/8 packets, normal treatment effects and comparable MP controls with log audit. Do not bypass the count guard or treat absence of a message as proof of a fix.

Gate for each adapter: primary success; same/different targets; pending cancellation; active stage; item/object loss; changed callback/helper; duplicate/late network result; exact consumption, result and return. Do not suppress native complete/cleanup after a server effect has occurred with a continuation guard.

## Remaining families

These families need contract/coverage audits. Missing verification or continued use of legacy completion does not by itself mean their native actions fail.

- [ ] TidyUpMeister: migrate remaining clothing, hotbar and heavy-item restores only after their SP/Host lifecycle gates. Separately define safe edit contracts for mixed-session floor returns and unknown/dynamic entry points; these remain protected. Preserve required shared cleanup on cancellation.
- [ ] Packaged food: check the remaining opening recipes, including random contents and mod callbacks. Keep their standard commands until a separate contract exists; queue support is limited to verified `OpenCannedFood` and `OpenCannedFood2`.
- [ ] Farming and animals: inventory the specific actions still missing verified edit contracts, then cover target identity, plant/animal state, shared consumables and tools.
- [ ] Mechanics: inventory the specific actions still missing verified edit contracts, then cover vehicle + part, installed/removed items, shared tools and vehicle movement.
- [ ] Fishing/traps, remaining world/building/weapons/rest actions: family contracts for inputs, results, stopping and permitted continuation.
- [ ] Dynamic-resource selection: narrow conflicts to a proven inventory/reachability scope only where safe, starting with concrete blocked cases such as MP washing soap selection. Cover server reselection and newly reachable resources. Do not expand permissions based on a single Type or an empty inspect.

For each migrated family, add an independent positive example and a dangerous example with a shared resource in both directions. When lifecycle changes, run the corresponding live gate. Changing a label/icon must remain a presentation/translation change; changing cancellation/transfer permission requires a separate behavior contract and check.

# Vehicle ownership desync

- [ ] Capture synchronous `[VEHICLE_SYNC]` logs from the original episode with two different vehicle positions: the controlled localhost race confirms ownership loss but does not establish the cause of the user's case. Check real WAN latency/packet loss.
