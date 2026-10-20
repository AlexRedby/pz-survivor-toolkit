# In-cabin vehicle door control

- [ ] Recheck the restored early red-aperture icon in the real radial menu with sufficient margins to both sector edges. The user selected the pre-angle-correction artwork; a historical in-game capture exists, but the current 64x64 export has not been captured again.
- [ ] Inspect passenger expanded/retracted controls and dashboard scaling in game; the current live scenario covers the stationary driver and programmatic callbacks.

# Wooden wheelbarrow collisions

- [ ] Validate the prepared observer-only wooden-cart correction in both full-load Walk Host wall exits with the selected mod pack. Unlock the Mac before launching: AeroSpace cannot route the test windows while the desktop is locked. Require clear owner and observer meshes/wheel support, matched actual camera/slot/depth, preserved hands/feet/rolling, bounded correction/release without jumps, exact cart/cargo identity, unchanged native coordinates/targets/pathfinding and the existing pose sender budget. Inspect short recordings and frame pacing before merging; passing headless geometry/render checks alone does not complete this gate.
- [ ] After the observer wall gate, extend relative-key manual reverse Host wall exits to Run/Sprint approaches, the male model and empty carts. Preserve the <=.02 rad opposite-yaw, <=.025 rad release and <=500 ms owner sampling budgets, manual reverse, natural rolling and native collision, without automatic backing.
- [ ] On the next shared cart-native run, obtain the standard path report with same-tick CancelAction/terminal accounting fixed: the saved 24 routes were checked in separate analysis; leave the original report unchanged. The shared visual gate remains open due to wide-trouser contact with the left handle and unclassified font messages.

# Natural wooden wheelbarrow animation

## Maneuvers and transitions

- [ ] Verify the current vanilla conditions for a natural sprint collision/fall with the wooden cart and expose a short impact/get-up recording for user review. The existing `native-impact` fixture injects `collideWithWall`; it checks emergency release/recovery, not the natural trigger or probability. Keep stock impact/get-up clips and exact cart/cargo identity; add a real collision control before claiming natural fall coverage.
- [ ] Extend live checks of forward/backward transitions at the reverse 130°/140° boundary and during collision, state reset and cart replacement; the math and hook regressions for these cases already exist. The full visual gate remains open until the pose defects below are resolved.
- [ ] Extend collision checks to load changes, falling/combat/releasing the cart and safe state reset. Preserve exact cart/cargo identity, native collision and manual reverse. The movement/doorway matrix does not verify these interruption paths or the known Host observer defect.

## Pickup and put-down

- [ ] Extend pickup clearance checks to the remaining approach angles and clothing combinations. Check all skin/pants geometry at Thigh/Calf, not just the pelvis; preserve the agreed shallow crouch, foot support, knee direction and grip.
- [ ] Check wheel phase continuity during an emergency pickup/put-down reset; preserve verified ownership, load and grip recovery.
- [ ] Extend pickup/put-down cancellation checks to Run/Sprint movement, tempo changes and releasing WASD before recovery ends. Preserve limited pose return, grip, arm lengths, wheel phase and repeat action; already checked Walk/CancelAction does not cover these variants.
- [ ] Check pickup from a container and approaches to the handles from the wrong side/across obstacles, including a blocked final alignment step, cancellation/target loss during approach and an independent queued action after it. Preserve native collision, the single authoritative complete and exact itemId/XYZ.
- [ ] For pickup/put-down, extend live checks to cancellation before MP handoff, a late network result, item loss/replacement, cart destruction, stairs, combat/fall/death and restarting after these events. Preserve verified exact IDs/load and world/held handoff; do not delay emergency instant-drop. Lua/hook regressions do not replace the native visual gate and MP owner+observer.

## Known pose defects

- [ ] Review rapid left/right steering response with the user before changing the established angular inertia: at Run/Sprint, a 300 ms opposite press can still produce net yaw in the previous direction. Keep measured response latency separate from unexpected stuck/wrong-way steering; preserve smooth bank transitions and wheel rolling if retuning is agreed.
- [ ] Remove rendered fore-aft cart jumps during Walk side-clearance acquisition, Run/Sprint entry, rapid slaloms and stopping. Preserve native leg motion, the preferred straight pose and minimum hand/body clearance. Check monotonic-time wheel/handle trajectories and recordings, including startup and release; a clearance-only change or passing grip probes is insufficient.
- [ ] Remove rare contact between wide jeans and the handles in the original straight pose, near it and at the start of the reverse arc, preserving the preferred hand and torso position. Contact remains in some zero-lean phases and nearby; also check the short Walk -> Cart Idle transition while equipping. Include Walk with a full load alongside a vehicle at 45° to the right: the left handle touches the trousers at about 4.18 s in scene `male-full-vehicle-yaw45-slide-right` in capture `cart-vehicles-20261018/native05`.
- [ ] For the selected turn, check the grip surface and thumb on both hands and both sexes: in the prototype without raising the handles, the hand angle relative to the handle changes from 25° to 35°, while the original palm depth and finger curl are preserved.

# Root fix for the action queue

These are implementation and verification gaps, not evidence that every action using the old completion path is broken. Keep working native behavior while migrating one verified family at a time.

## General rules for move and cancel

- [ ] Extend the version-1 edit contract to remaining food variants (cookable items, custom callbacks, utensils and nonstandard portions), other fluid actions, world-container pickup/return and craft inputs. Describe exact identity versus late selector scope, bounded native effects and complete resource domains; retain legacy protection for missing contracts. Do not infer semantics from action names or treat same-item access alone as a dependency.
- [ ] Extend the conservative full-current-weight transfer gate to proven quantity-dependent capacity effects and world-container ancestry. Do not credit uncertain MP releases or reserve future inventory. Add exact native producer/consumer and return-container gates before expanding permissions.
- [ ] Extend operation records with prepare/body/cleanup phases and obligations activated by confirmed effects. Migrate pickup returns, mask/equipment restoration and cancellation of the remaining batch to the shared settlement path. Keep earned output, paid costs and necessary cleanup after cancellation; never recreate or roll back authoritative results. Allow independent tails only after isolation from an uncertain in-flight result is proven.
- [ ] Register interruption capabilities through the same contract: cancel, finish the current atomic step and defer the remainder, or native stop with a validated checkpoint/resume. Generalize existing book/world handling through that interface without inventing arbitrary timer restoration or repeating already-paid work. Unknown active actions keep native cancellation and only supported boundaries may be edited.
- [ ] Extend the generated edit oracle and existing scenario matrix to native partial completion, cleanup, replaced resources and delayed/duplicate outcomes. Add selected-pack SP/Host pending radio-setting reorder/cancel cases with queue-off execution controls and server-state receipts; current setter coverage executes actual native Lua with simulated Java state. Gate each additional consumable/transfer adapter on exact conservation and at-most-once effects, without enumerating every pair of action names.
- [ ] Extend the new required-state/resource/capacity/in-flight/unknown denial reasons to remaining legacy adapters and surface the specific prerequisite or missing integration in the UI. Preserve independent edits around genuinely unrelated work.

- [ ] Extend live SP/MP gates for the shared lifecycle to the remaining families: unavailable target, late continuation, exact consumption and independent tail, before replacing their local completion intercepts.
- [ ] Check the shared outcome protocol with two real MP clients during reset/death/disconnect, byte ID reuse, late and duplicate responses, and network delays; supplement the already completed boundary checks using native Java/Lua fixtures.
- [ ] Remove the remaining family-specific bypasses after the corresponding SP/MP checks; preserve fallback for unsupported Java/server versions, resource contracts and separate medical/cart sync fixes.

# Further action queue migration

The executor remains `ISTimedActionQueue`. Add families through Definitions and the shared dependency/effect contract, keeping any dependency model read-only: it validates edits, never executes game effects, replaces the native scheduler or reserves future inventory. Check display and permission to change the queue separately. Only unfinished work is listed below; interfaces are described in the [features guide](docs/FEATURES.md), and check commands are in the [developer guide](docs/DEVELOPMENT.md).

## Active shelf reading below TV commands

- [ ] Extend the combined shelf-book/TV live scenario to a VHS taken from a worn bag: native pickup, grouped insertion, active reading moved below power/insert/play, exact tape debit and one book return. Run selected-pack SP/Host with matching queue-off controls and log audits. The inventory-VHS path is verified live; bag preparation/capacity, missing tape/TV/return destination, changed callbacks and same-TV conflicts currently have focused local regression coverage.
- [ ] Diagnose the selected-pack Host control with the Toolkit queue disabled: native power and insertion finish, the exact VHS is debited and present in the TV, but the queue becomes empty before playback starts. This also reproduced before the media-order fix; distinguish native engine behavior from selected-mod interaction before changing queue-off behavior. Keep the failed native control visible in paired reports.

## Known limits of move/cancel controls

These operations can execute normally while some queue controls remain disabled. The work below is to prove safe edits; real shared dependencies and required cleanup must remain protected. Current behavior is described in the [action queue limits](docs/FEATURES.md#supported-actions-and-limits).

- [ ] Vehicle fuel and wreck dismantling: reordering and individual cancellation remain protected because containers/tools are chosen at execution time. Define exact contracts for shared cans, hoses, masks and blowtorches before enabling these controls. Preserve deferred selection, native fuel transactions, wreck removal and the unrelated queue tail.
- [ ] Project Cook evolved recipes: ingredient application and compensating consumed-spice cleanup protect the operation from cancellation. Define which edits, if any, are independent of already-applied ingredients; preserve authoritative consumption and required cleanup rather than dropping the cleanup step.
- [ ] Complex handcraft recipes: identify concrete blocked recipes with Lua callbacks, fluid/energy inputs, unrestricted item selection or replacement/depletion/break effects. Add narrow resource/output contracts where practical; keep actual shared materials and shared crafting UI ordered. Plain-item crafting support is not an unfinished item here.
- [ ] Medical world pickups and unknown treatment producers: add exact item/patient/wound contracts for specific unsupported entry points before allowing edits. Preserve native wound checks, supplies and clothing effects; do not mark all medicine unsupported.
- [ ] Carried-container capacity: MP does not credit space that a previous pending pickup may free; synthetic proximity endpoints and unknown capacity callbacks also remain protected. Prove exact source/destination/ancestor capacity and authoritative transfer effects before relaxing a concrete blocked case.
- [ ] Unknown mod actions and asynchronous continuations: capture the concrete action type, producer, continuation and cleanup when an operation is split into separate rows or becomes an edit barrier. Add scoped grouping/edit contracts for reviewed entry points; unknown or modified callbacks must retain a clear denial reason.

## Shared game sessions and build regression

- [ ] Extend the common scenario contracts beyond equipment, fluid drinking and health-panel/direct-inventory bandaging. Map audited cases/outcomes per action, reuse `QueueScenarioChecks`, and keep unimplemented/inapplicable requirements explicit. Prioritize empty initial queue, repeated requests, lost/replaced resources and unavailable return containers; include worn bags and favorite-item variants where relevant. Gate: exact effects and cleanup in selected SP/Host runs with matching native controls and clean log audits.

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
