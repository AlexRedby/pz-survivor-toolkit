# Injured cart locomotion

- [ ] Repeat the injury checks with the complete selected mod set once its missing Workshop mods are available.

# Shopping cart animation port

- [ ] Cover partial/flashlight shopping-cart meshes in native direct rendering and action handoffs. Empty/full direct support, its renderer-specific world-Z compensation and original native wheel-index partition are verified; source geometry regressions for all six models do not replace the remaining native variants.
- [ ] Extend shopping-cart cancellation/retry beyond the two selected restart scenes to moving recovery and the remaining interruption routes. Close the shared analyzer's selected-retry grip-phase coverage gap; exact native lifecycle/ownership and clock evidence do not replace that gate.
- [ ] Extend shopping-cart wheel/caster presentation to the remaining load/sex/speed/obstacle combinations. Four independent tire phases, smoothed front caster direction, tire support and held/world continuity are checked in selected light/full SP recordings; this is not the full matrix or a collision check.
- [ ] Review shopping-cart tight pivots before changing handling: the preserved nose-pivot path can slide the fixed rear tires sideways. Agree on the desired steering path before changing it; retain grip, natural stepping, collision and manual reverse.
- [ ] Verify Host owner/observer shopping-cart transition presentation, exact ownership/cargo and bounded synchronization before treating the shopping-cart port as Host-verified. Extend the Host fixture action gate first; current shopping native coverage supports selected SP interaction/repeat and wheel captures only.

# Metal wheelbarrow animation port

- [ ] Close the selected immediate-retry grip-phase coverage gap in the shared analyzer; retain per-action cancelled/successful boundaries and do not infer a full matrix pass from the two-scene lifecycle/ownership audit.
- [ ] Complete an isolated Host owner/observer run for the metal wheelbarrow with the installed mod set and at least 2048 MiB Java heap per process. Check motion, pickup/setdown, cancellation/retry, exact cart/cargo identity and both clients' presentation; review short recordings. A startup failure is not functional coverage.

# Selected QoL additions

- [ ] After installation is requested, check all three in isolated full-pack macOS B42.21 SP/Host saves: skill and recipe tooltips alongside the selected trait-description mod; foraging modifiers/radius; switch construction, bulb insertion/removal, grid/generator lighting, dismantling and second-player synchronization. Author claims do not establish compatibility with this selected set.

# Auto-drink after multiplayer respawn

- [ ] Verify death and new-character creation as a client in an isolated full-pack Host session on macOS B42.21, with auto-drink disabled and enabled. Pick up a water bottle and compare the menu preference, character flag and server water/thirst effects after the connection reply. Native reply ordering and the one-shot repair are covered by source inspection and focused Lua regressions; this live network scenario remains unverified.

# Sport headlight push-button cycle

- [ ] Run the isolated sport push-button SP/Host checks when the shared desktop test slot is available. Inspect off/low/high/off releases, held/released appearance at all four scales and server power acknowledgements. Current focused regressions cover the cycle and ACK guards; native launch was blocked at admission. Keep the VVA-pair coexistence gate below separate from the available 45-mod test subset.

# Vanilla vehicle visuals

- [ ] After installation is requested, check the selected VVA/Animated Vehicle Parts Fix pair on macOS B42.21 in isolated full-pack SP/Host saves: removed hood/door interiors, running-engine unload/reload, Toolkit door controls and headlight/reverse-light alignment, plus a second Host player’s animation visibility. The fix rebuilds the native light list and VVA replaces vehicle models; static source review does not establish visual compatibility or MP animation synchronization.

# Approved truck headlight rocker

- [ ] Complete the isolated Host truck-rocker run and inspect its server power acknowledgements. The focused regressions and full-mod-set single-player visual check already cover the off/low/high sequence, all four scales, complete pull-knob/legend removal and unchanged standard/sport controls.

# In-cabin vehicle door control

- [ ] Recheck the restored early red-aperture icon in the real radial menu with sufficient margins to both sector edges. The user selected the pre-angle-correction artwork; a historical in-game capture exists, but the current 64x64 export has not been captured again.
- [ ] Inspect passenger expanded/retracted controls and dashboard scaling in game; the current live scenario covers the stationary driver and programmatic callbacks.

# Wooden wheelbarrow collisions

- [ ] Extend relative-key manual reverse Host wall exits to Run/Sprint approaches and the remaining sex/load combinations, including empty carts. Preserve the <=.02 rad opposite-yaw, <=.025 rad release and <=500 ms owner sampling budgets, manual reverse, natural rolling and native collision, without automatic backing.
- [ ] On the next shared cart-native run, obtain the standard path report with same-tick CancelAction/terminal accounting fixed: the saved 24 routes were checked in separate analysis; leave the original report unchanged. The shared visual gate remains open due to wide-trouser contact with the left handle and unclassified font messages.

# Natural wooden wheelbarrow animation

## Maneuvers and transitions

- [ ] Extend live checks of forward/backward transitions at the reverse 130°/140° boundary and during collision, state reset and cart replacement; the math and hook regressions for these cases already exist. The full visual gate remains open until the pose defects below are resolved.
- [ ] Extend collision interruption checks to load changes, combat/releasing the cart, Host fall/recovery and safe state reset. Preserve exact cart/cargo identity, native collision and manual reverse. The movement/doorway matrix does not verify these interruption paths or Run/Sprint observer clearance.

## Pickup and put-down

- [ ] After the newly selected VanillaVehiclesAnimated/AnimatedVehiclePartsFix pair is installed, recheck the blocked-handle approach against its vehicle geometry. The current SP checks use the installed 45-mod set; these two unavailable mods are excluded explicitly.

- [ ] Extend moving cancellation to steering input/nonzero bank: blend the captured grip policy and torso into the moving endpoint before adopting its lean; verify the first recovery frame and final handoff.
- [ ] Extend pickup clearance checks to the remaining approach angles and clothing combinations. Check all skin/pants geometry at Thigh/Calf, not just the pelvis; preserve the agreed shallow crouch, foot support, knee direction and grip.
- [ ] For pickup/put-down, extend live checks to cancellation before MP handoff, a late network result, item loss/replacement, cart destruction, stairs, combat/fall/death and restarting after these events. Preserve verified exact IDs/load and world/held handoff; do not delay emergency instant-drop. Lua/hook regressions do not replace the native visual gate and MP owner+observer.

## Known pose defects

- [ ] Review rapid left/right steering response with the user before changing the established angular inertia: at Run/Sprint, a 300 ms opposite press can still produce net yaw in the previous direction. Keep measured response latency separate from unexpected stuck/wrong-way steering; preserve smooth bank transitions and wheel rolling if retuning is agreed.
- [ ] Remove rendered fore-aft cart jumps during Walk side-clearance acquisition, Run/Sprint entry, rapid slaloms and stopping. Preserve native leg motion, the preferred straight pose and minimum hand/body clearance. Check monotonic-time wheel/handle trajectories and recordings, including startup and release; a clearance-only change or passing grip probes is insufficient.
- [ ] For the selected turn, check the grip surface and thumb on both hands and both sexes: in the prototype without raising the handles, the hand angle relative to the handle changes from 25° to 35°, while the original palm depth and finger curl are preserved.

# Root fix for the action queue

These are implementation and verification gaps, not evidence that every action using the old completion path is broken. Keep working native behavior while migrating one verified family at a time.

## General rules for move and cancel

- [ ] Extend the version-1 edit contract to remaining food variants (hot/state-changing items, custom callbacks, complete consumption that creates replacement items and ingredient states outside the bounded native-food proof), other fluid actions, remaining world-container pickup/return (cookable food and special containers) and craft inputs. Describe exact identity versus late selector scope, bounded native effects and complete resource domains; retain legacy protection for missing contracts. Do not infer semantics from action names or treat same-item access alone as a dependency.
- [ ] Extend the conservative full-current-weight transfer gate to proven quantity-dependent capacity effects and remaining world-container ancestry. Do not credit uncertain MP releases or reserve future inventory. Add exact native producer/consumer and return-container gates before expanding permissions.
- [ ] Extend operation records with prepare/body/cleanup phases and obligations activated by confirmed effects. Migrate pickup returns, mask/equipment restoration and cancellation of the remaining batch to the shared settlement path. Keep earned output, paid costs and necessary cleanup after cancellation; never recreate or roll back authoritative results. Allow independent tails only after isolation from an uncertain in-flight result is proven.
- [ ] Register interruption capabilities through the same contract: cancel, finish the current atomic step and defer the remainder, or native stop with a validated checkpoint/resume. Generalize existing book/world handling through that interface without inventing arbitrary timer restoration or repeating already-paid work. Unknown active actions keep native cancellation and only supported boundaries may be edited.
- [ ] Extend the generated edit oracle and existing scenario matrix to native partial completion, cleanup, replaced resources and delayed/duplicate outcomes. Gate each additional consumable/transfer adapter on exact conservation and at-most-once effects, without enumerating every pair of action names.
- [ ] Extend the new required-state/resource/capacity/in-flight/unknown denial reasons to remaining legacy adapters and surface the specific prerequisite or missing integration in the UI. Preserve independent edits around genuinely unrelated work.

- [ ] Extend live SP/MP gates for the shared lifecycle to the remaining families: unavailable target, late continuation, exact consumption and independent tail, before replacing their local completion intercepts.
- [ ] Check the shared outcome protocol with two real MP clients during reset/death/disconnect, byte ID reuse, late and duplicate responses, and network delays; supplement the already completed boundary checks using native Java/Lua fixtures.
- [ ] Remove the remaining family-specific bypasses after the corresponding SP/MP checks; preserve fallback for unsupported Java/server versions, resource contracts and separate medical/cart sync fixes.

# Further action queue migration

The executor remains `ISTimedActionQueue`. Add families through Definitions and the shared dependency/effect contract, keeping any dependency model read-only: it validates edits, never executes game effects, replaces the native scheduler or reserves future inventory. Check display and permission to change the queue separately. Only unfinished work is listed below; interfaces are described in the [features guide](docs/FEATURES.md), and check commands are in the [developer guide](docs/DEVELOPMENT.md).

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
