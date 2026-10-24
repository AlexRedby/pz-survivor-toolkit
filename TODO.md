# Retained-item transfer and indicator verification

- [ ] Prepare a fresh `item-retention/trunk` run from current main in isolated macOS B42.21 EN/RU native and CleanUI views when the desktop test slot is available. Verify the final child-gutter lock placement, exact authoritative IDs/retained flags for two manually moved items and their return, automatic distribution exclusion and single-item transfer/release. Require completed functional receipts and inspect the screenshots.
- [ ] Resolve the full selected pack's `PZToolkitJavaPatches` input and repeat the scenario with that pack. Keep current source-backed checks distinct from the outstanding live Host gate.

# Vehicle entry and exit roof clipping

- [ ] Verify entry/exit from a second Host client's view and on low-roof/tall-cab vehicles with the full selected B42.21 pack. Current isolated macOS SP/Host checks cover stationary Base.CarNormal driver/passenger transitions, both cancellations, the local seated animation track and authoritative seat occupancy; screenshots include the native occlusion silhouette.

# Exercise ground storage

- [ ] Check the exercise ground-storage change in disposable B42.21 full-pack SP/Host profiles: multiple worn/held bags (including favourites), contents/IDs, dumbbells borrowed from a bag, natural completion and cancellation during placement/pickup, closed Fitness window with queue controls off, movement away and a second player's competing pickup. Require authoritative conservation and unchanged exercise effects; Lua source-backed doubles do not establish live network ordering or rendering.

# Container editor visual states

- [ ] Agree item-catalog cleanup criteria before hiding native debug/dev entries or changing technical display-name fallbacks. Preserve saved item-name selections; the current catalogue already excludes items marked hidden/obsolete, while the rule preview intentionally includes hidden-but-routable items.

# Vehicle Repair Overhaul verification

- [ ] Resolve both VRO modules from Workshop 2757712197 or explicit sources, then check repairs and whole-vehicle salvage in isolated full-pack macOS B42.21 SP/Host saves. Verify menus with Toolkit/VVA, actual materials/XP and 10-use fuel drain, reload and second-player state. Empty test containers and remove occupants/animals before removal. Recheck the upstream VSO/VRO sandbox-key mismatch before relying on custom controls; source/metadata checks do not establish runtime compatibility.

# Vehicle aim roof fix verification

- [ ] Resolve CarRoofFix through Workshop or an explicit source override, then verify RMB look-around, release, seat switching and armed aiming in isolated macOS B42.21 SP/Host with the full selected pack, including a second player's view. Check the unmodified heavy/spear/chainsaw aim nodes separately; metadata/XML and selection checks do not establish gameplay compatibility.

# Fitness completion verification

- [ ] Run `fitness --cases burpees-30 --kind mp` with the full selected pack in native/toolkit menu Host after the missing `VanillaVehiclesAnimated` source and any further unresolved pack inputs are available. Verify actual thirty-minute burpees, prompt native stop, authoritative settlement, restored equipment and the independent reader. Native-source regressions pass; the game run remains blocked at pack resolution.

# Nick's Turn Off Fridges selection

- [ ] After installation is requested, check unplug/replug, cooling/thawing, generator fuel demand, reload persistence and second-player state in isolated full-pack macOS B42.21 SP/Host saves. Plug all test appliances back in before removing the mod. Author Host support and reported fixes do not establish compatibility with this set.

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

# Root fix for the action queue

These are implementation and verification gaps, not evidence that every action using the old completion path is broken. Keep working native behavior while migrating one verified family at a time.

## General rules for move and cancel

- [ ] Extend the version-1 edit contract to remaining world-container pickup/return (hot cookable food and special containers) and craft inputs. Describe exact identity versus late selector scope, bounded native effects and complete resource domains; retain legacy protection for missing contracts. Do not infer semantics from action names or treat same-item access alone as a dependency.
- [ ] Extend the conservative full-current-weight transfer gate to proven quantity-dependent capacity effects and remaining world-container ancestry. Do not credit uncertain MP releases or reserve future inventory. Add exact native producer/consumer and return-container gates before expanding permissions.
- [ ] Extend persistent prepare/body/cleanup effect records to the remaining legacy pickup and family-owned restoration paths, including fitness preparation. Replace a family proof only after exact native effects and corresponding SP/Host gates are proven. Preserve shared ownership, confirmed explicit equipment intent, earned output and paid costs; never infer an effect from queue disappearance or replay authoritative work.
- [ ] Register interruption capabilities through the same contract: cancel, finish the current atomic step and defer the remainder, or native stop with a validated checkpoint/resume. Generalize existing book/world handling through that interface without inventing arbitrary timer restoration or repeating already-paid work. Unknown active actions keep native cancellation and only supported boundaries may be edited.
- [ ] Extend the generated edit oracle and existing scenario matrix to native partial completion, cleanup, replaced resources and delayed/duplicate outcomes. Gate each additional consumable/transfer adapter on exact conservation and at-most-once effects, without enumerating every pair of action names.
- [ ] Extend the new required-state/resource/capacity/in-flight/unknown denial reasons to remaining legacy adapters and surface the specific prerequisite or missing integration in the UI. Preserve independent edits around genuinely unrelated work.

- [ ] Extend live SP/MP gates for the shared lifecycle to the remaining families: unavailable target, late continuation, exact consumption and independent tail, before replacing their local completion intercepts.
- [ ] Check the shared outcome protocol with two real MP clients during reset/death/disconnect, byte ID reuse, late and duplicate responses, and network delays; supplement the already completed boundary checks using native Java/Lua fixtures.
- [ ] Remove the remaining family-specific bypasses after the corresponding SP/MP checks; preserve fallback for unsupported Java/server versions, resource contracts and separate medical/cart sync fixes.

# Extend cancelled queue recovery

- [ ] Add explicit reconstruction and live validation for untouched consumption, crafting and the remaining queued action families beyond the audited read/walk/radio/media/direct-transfer adapters. Preserve completed effects and required cleanup; do not enable uncertain started operations. Add focused family regressions and corresponding selected-pack SP/Host checks before granting recovery.

# Further action queue migration

The executor remains `ISTimedActionQueue`. Add families through Definitions and the shared dependency/effect contract, keeping any dependency model read-only: it validates edits, never executes game effects, replaces the native scheduler or reserves future inventory. Check display and permission to change the queue separately. Only unfinished work is listed below; interfaces are described in the [features guide](docs/FEATURES.md), and check commands are in the [developer guide](docs/DEVELOPMENT.md).

## Known limits of move/cancel controls

These operations can execute normally while some queue controls remain disabled. The work below is to prove safe edits; real shared dependencies and required cleanup must remain protected. Current behavior is described in the [action queue limits](docs/features/ACTION_QUEUE.md#supported-actions-and-limits).

- [ ] Vehicle fuel and wreck dismantling: reordering and individual cancellation remain protected because containers/tools are chosen at execution time. Define exact contracts for shared cans, hoses, masks and blowtorches before enabling these controls. Preserve deferred selection, native fuel transactions, wreck removal and the unrelated queue tail.
- [ ] Project Cook evolved recipes: ingredient application and compensating consumed-spice cleanup protect the operation from cancellation. Define which edits, if any, are independent of already-applied ingredients; preserve authoritative consumption and required cleanup rather than dropping the cleanup step.
- [ ] Complex handcraft recipes: identify concrete blocked recipes with Lua callbacks, fluid/energy inputs, unrestricted item selection or replacement/depletion/break effects. Add narrow resource/output contracts where practical; keep actual shared materials and shared crafting UI ordered. Plain-item crafting support is not an unfinished item here.
- [ ] Medical world pickups and unknown treatment producers: add exact item/patient/wound contracts for specific unsupported entry points before allowing edits. Preserve native wound checks, supplies and clothing effects; do not mark all medicine unsupported.
- [ ] Carried-container capacity: MP does not credit space that a previous pending pickup may free; synthetic proximity endpoints and unknown capacity callbacks also remain protected. Prove exact source/destination/ancestor capacity and authoritative transfer effects before relaxing a concrete blocked case.
- [ ] Haircuts: define a source-bound waiting-action contract before allowing operation cancellation after scissors preparation. Native `ISCutHair.complete` can choose gel/spray dynamically for some styles, so keep active cancellation/reordering protected until tool, cosmetic-state and consumable effects are described; the confirmed-pickup cancellation gate currently reports `operation_dependent` correctly.
- [ ] Unknown mod actions and asynchronous continuations: capture the concrete action type, producer, continuation and cleanup when an operation is split into separate rows or becomes an edit barrier. Add scoped grouping/edit contracts for reviewed entry points; unknown or modified callbacks must retain a clear denial reason.

## Shared game sessions and build regression

- [ ] Extend the common scenario contracts beyond equipment, verified food/fluid cases and health-panel/direct-inventory bandaging. Map audited cases/outcomes per action, reuse `QueueScenarioChecks`, and keep unimplemented/inapplicable requirements explicit. Prioritize empty initial queue, repeated requests, lost/replaced resources and unavailable return containers; include worn bags and favorite-item variants where relevant. Gate: exact effects and cleanup in selected SP/Host runs with matching native controls and clean log audits.

## Near-term adapters

The medical packet mismatch below is an unresolved runtime observation; its cause has not been attributed to queue scheduling.

Add contracts in Definitions/Policy/Operations for each family. Expose only verified capabilities; leave the rest with an explicit denial reason.

- [ ] SaucedCarts: world/vehicle/floor endpoints and custom callbacks need separate contracts. Add correlated server results with protection against duplicate/late responses before removing protection for active MP transfer and MP returns; check failure/partial batch without predicting success. Separately check replacing/resetting the cart itself while held; generators are currently protected while the cart is held. If needed, extend the capacity proof to deferred installation of upstream hooks and proven effects of the freed space.
- [ ] Native MP medicine: obtain a live reproduction of the rare `SyncVisualsPacket` count mismatch 7/8 from MP10 using the preserved diagnostic setup `tests/native_queue/contributions/visual-sync`. Compare ordered IDs before write and after parse, asset readiness and in-flight old snapshots; establish the cause of the specific failure. Gate for any fix: a positive regression case, correct 8/8 packets, normal treatment effects and comparable MP controls with log audit. Do not bypass the count guard or treat absence of a message as proof of a fix.

Gate for each adapter: primary success; same/different targets; pending cancellation; active stage; item/object loss; changed callback/helper; duplicate/late network result; exact consumption, result and return. Do not suppress native complete/cleanup after a server effect has occurred with a continuation guard.

## Remaining families

These families need contract/coverage audits. Missing verification or continued use of legacy completion does not by itself mean their native actions fail.

- [ ] TidyUpMeister: migrate unverified held/worn combinations and remaining special clothing, including side-conversion outputs, displaced special equipment and multi-item worn slots, radio media and other unverified stateful components, changing providers and displaced attachment models, and native capacity-driven clothing world drops/heavy-item restores only after exact output contracts and their SP/Host lifecycle gates. Separately define safe edit contracts for mixed-session floor returns and unknown/dynamic entry points; these remain protected. Preserve required shared cleanup on cancellation.
- [ ] Deferred food/fluid expansion: revisit only for a concrete bug or explicit request. Remaining variants include hot/state-changing items, custom callbacks, consumption replacements outside the bounded proof for plain and empty-fluid outputs, ingredient states outside the bounded native-food proof and other fluid actions. Preserve protective edit limits until a separate contract is proven.
- [ ] Packaged food: check the remaining opening recipes, including random contents and mod callbacks. Keep their standard commands until a separate contract exists; queue support is limited to verified `OpenCannedFood` and `OpenCannedFood2`.
- [ ] Farming and animals: inventory the specific actions still missing verified edit contracts, then cover target identity, plant/animal state, shared consumables and tools.
- [ ] Mechanics: inventory the specific actions still missing verified edit contracts, then cover vehicle + part, installed/removed items, shared tools and vehicle movement.
- [ ] Fishing/traps, remaining world/building/weapons/rest actions: family contracts for inputs, results, stopping and permitted continuation.
- [ ] Dynamic-resource selection: narrow conflicts to a proven inventory/reachability scope only where safe, starting with concrete blocked cases such as MP washing soap selection. Cover server reselection and newly reachable resources. Do not expand permissions based on a single Type or an empty inspect.

For each migrated family, add an independent positive example and a dangerous example with a shared resource in both directions. When lifecycle changes, run the corresponding live gate. Changing a label/icon must remain a presentation/translation change; changing cancellation/transfer permission requires a separate behavior contract and check.

# Vehicle ownership desync

- [ ] Capture synchronous `[VEHICLE_SYNC]` logs from the original episode with two different vehicle positions: the controlled localhost race confirms ownership loss but does not establish the cause of the user's case. Check real WAN latency/packet loss.

# Full-pack follow-up checks

- [ ] Once the eight missing selected mods are locally available, run the isolated macOS Warehouse, automatic-deposit, Smart Deposit partial-drop and Quartermaster recipe-unit SP/Host scenarios, plus the Host batch-admission case and two-player Wishlist synchronization with the complete 55-Mod-ID pack. Required sources: VanillaVehiclesAnimated, AnimatedVehiclePartsFix, ArcheryNexus, WildernessProgressionArcheryNexusCompanion, EURY_DST, Ivmakk_ForagingTooltipExtended, CustomLightSwitch and NicksTurnOffFridges. The bounded checks used the 45 available Mod IDs.

# Inventory infrastructure proposals

- [ ] Remove the discarded details-selection mapping at the known native/CleanUI restore boundary after agreeing the integration: InventoryFilter invokes upstream restore, then InventoryRows wipes its result and maps the final rows again. Retain external mod hooks, final row ordering and unknown/icon-mode fallback; prove render-capped expanded stacks and selection/Shift-anchor correctness before removing the first pass.

# Warehouse client workload

- [ ] Coalesce movement-triggered loot rebuilds and defer hidden presentation work while keeping reachable-container data fresh for native/mod consumers; verify reopen, remote changes, nesting, transfers and UI-mode switches.
- [ ] Remove avoidable full-item snapshot/selection work in the owned filter pipeline without changing live metadata, filtering or selection behavior.
- [ ] Bound capacity-indicator redraw work without caching transfer admission; preserve fresh item/fluid/nested-container state and clean lifecycle ownership.
- [ ] Add source-backed workload regressions for native/CleanUI/Better Containers, review integration boundaries, run affected checks and update shipped version/changelog. Run isolated native checks if source-backed tests cannot establish the required behavior.
