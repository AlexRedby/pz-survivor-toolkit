# Development

[Overview](../README.md) · [Player guide](FEATURES.md) · [Open work](../TODO.md)

Run commands from the repository root. Use Python 3.10+ for preparation and ordinary tooling; the native scenario runner requires Python 3.11+. Game files and Workshop sources are external inputs, not repository contents.

| Task | Start here |
|---|---|
| Check Lua behavior or prepare distributable mods | [Checks and packaging](#checks-and-packaging) |
| Reproduce a game or Host issue in isolated profiles | [Native scenarios](#native-scenarios) |
| Build engine patches, run JVM checks or capture test video | [Java development](development/JAVA.md) |
| Extend a shared Toolkit mechanism | [Architecture and extension contracts](development/ARCHITECTURE.md) |
| Implement shared queue resource/capacity decisions | [Performance-gated implementation plan](design/QUEUE_RESOURCE_CAPACITY.md) |
| Edit cart clips, replay captured motion or recalibrate clearance | [Animation authoring](development/ANIMATION.md) |
| Review the proposed cart multiplayer protocol | [Cart multiplayer design](design/CART_MULTIPLAYER.md) |

## Checks and packaging

Behavioural checks run with Lua 5.1 through Lupa. They use world/UI doubles; they are not visual in-game tests. Choose checks related to the change; the commands below are independent examples, not a mandatory full checklist.

Exercise storage uses `FitnessEquipment` for ground placement and exact-ID recovery in both the native Fitness UI and `ActionQueueFitness`. Run `tools/run_tests.py --game "$PZ_GAME" --test test_action_queue_fitness` for native placement/completion, worn/held bags, favourite flags, borrowed props, missing/distant storage, fresh item replicas, cancellation and queue-disabled/window-closed restoration. These source-backed checks do not establish live Host transport or full-pack gameplay; use the [native Fitness scenarios](../tests/native_queue/fitness/README.md) for separate SP/Host checks, including walking away and a second player picking up the storage.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install lupa
.venv/bin/python tools/run_tests.py --test test_tv_controls
python3 tools/package_mod.py --check
python3 tools/package_mod.py --output dist/PZSurvivorToolkit.zip
python3 -m unittest discover -s tests -p 'test_prepare_install.py'
python3 -m unittest discover -s JavaPatches/tests
python3 tools/prepare_install.py --check
```

List Lua tests with `.venv/bin/python tools/run_tests.py --list`. Select one or several with repeatable `--test NAME` (relative to `tests/`, with or without `.lua`). For example, `--test test_tv_controls --test test_vhs_ownership` runs only those tests and their associated variants, without scanning all mod files. Omit `--test` for the existing full Lua checks, including the syntax scan. Quartermaster checks always use the owned `PZSurvivorToolkit/42/media/lua` sources. Explicitly selecting its craft UI or the native tag transfer/placement checks also requires native game sources through `--game` or `--native-action-root`. Other checks retain their existing source-dependent SKIP behavior; a skipped integration check does not validate that integration.

Add `--game "$PZ_GAME"` (the directory containing `projectzomboid.jar`) to supply native Lua inputs from one installation. For example, `.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --test test_inventory_tags --test test_vehicle_ground` reads the selected tests' native inventory and vehicle sources. This also supplies Mod Options, radio, action and Wishlist paths when their checks are selected. Individual source-path options override these defaults; locked integration checks retain their source-consistency requirements. Only selected tests read their inputs, and a missing required file fails instead of silently skipping it. Third-party source paths remain explicit or come from `--pack-lock`.

VHS menu, sorting, drop validation and live toggle checks run by default; add `--tv-source /path/to/RWMMergedTV.lua --game "$PZ_GAME"` to also exercise the upstream window and native media actions and drag parser.

The TV video source check runs the upstream catalog and original initialization without a separate video list. `python3 JavaPatches/build.py --test TVVideoPathChecks` checks the macOS path correction before native cache lookup, including failed-cache precedence and close/eviction keys; it does not decode video or prove GPU playback.

Independent medicine checks can use the installed framework with `--medicine-framework-source /path/to/MF_ISMoodle.lua`.

Warehouse checks are selected with `--test test_manifest_authority --test test_manifest_client --test test_manifest_view --test test_manifest_presentation`. `python3 JavaPatches/build.py --test ManifestModelChecks` executes the same text-boundary vectors against native Kahlua's UTF-16 strings. Use the native `warehouse-manifest/snapshot` suite for the SP/Host/UI boundary; its declared scope and screenshots are described in the [runner guide](../tests/native_queue/README.md).

The read-only Java global `toolkitMedicineCooldown(character)` returns the native food-sickness treatment cooldown, or `nil` for unsupported bytecode, unavailable data or multiplayer clients. `MedicineEffects.capture` sends this as `LemonGrassCooldown` (`false` when unavailable); the old `LemonGrass` estimate is never displayed as exact. Use `python3 JavaPatches/build.py --test MedicineCooldownChecks` for native field, loader exposure and Kahlua checks.

`--mpff-source /path/to/MPFastForward/media/lua` and `--bc-filter-source /path/to/CategoryFilters.lua` exercise the upstream modules and early compatibility gates; without these paths, those source checks report SKIP.

With `--game`, vehicle ground-placement regressions exercise the installed game's removal completion and item collection, including failure, callbacks and its existing ground fallback. Quantity-transfer checks use the actual inventory callbacks and sibling text-box constructor/callback; run `.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --test test_quantity_transfers --test test_item_retention` to check original selection intent through Toolkit's live transfer wrapper and authoritative retention admission.

Action queue and native Wishlist menu checks use `--game`. Add `--wishlist-workshop-root /path/to/steamapps/workshop/content/108600` for the Wishlist checks against installed adapters.

`python3 tools/package_mod.py --check` validates the Toolkit mod structure without creating an archive. To create a developer-only archive, run `python3 tools/package_mod.py --output dist/PZSurvivorToolkit.zip`; Wishlist Lua sources are included automatically.

Use `tools/prepare_install.py` to prepare only the two owned mods, `PZSurvivorToolkit` and `PZToolkitJavaPatches`; it creates no archive and requires no third-party source directories. All third-party mods, including CleanUI, NewMusic and that DAMN Library, come from Workshop. Their downloaded files are not copied, patched or repackaged by preparation.

Toolkit owns the runtime NewMusic compatibility that disables vanilla CD/player conversion and its associated inventory observer, while preserving normal music loot. Run `python3 -m unittest discover -s tests -p 'test_prepare_install.py'` for the two-folder preparation contract and `PZ_NEWMUSIC_SOURCE="/path/to/mods/NewMusic" .venv/bin/python -m unittest tests.test_newmusic_runtime` for the source-backed Lua compatibility checks with Lupa installed. These checks do not establish live multiplayer performance.

The earlier CleanUI food-age and DAMN Library duplicate battery-recipe source-preparation experiments are no longer shipped. Their standalone source tools and checks remain available for investigation; delivering either correction through Toolkit or Java Patches requires a separate runtime integration and validation.

To run the same checks against your installed game's native Mod Options implementation:

```sh
.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --test test_highlighter
```

The independent CleanUI food-age investigation is not part of the prepared distribution and does not ship a CleanUI correction. Its opt-in native regression compiles only its Java fixture against the installed game and runs original/prepared CleanUI helpers in real Kahlua. Run `PZ_NATIVE_FOOD_AGE_CHECK=1 PZ_GAME="/path/to/game/Java" PZ_JDK="/path/to/jdk" PZ_CLEANUI_SOURCE="/path/to/mods/CleanUI" python3 -m unittest tests.test_cleanui_food_age_native`. It checks native ageing, freshness events, cooling controls and clock handling; it does not establish live UI or Host transport. The default test run skips this external-input check.

## Queue resource performance prototype

`tools/benchmark_queue_resources.py` runs production queue Policy, EditModel and weight code with explicit state doubles in the installed game's native Kahlua. It compiles only a development Kotlin host, starts no game/UI/Host, installs nothing and grants no new queue permissions. The worklist and its adaptive source instrumentation remain test-only. Reports include source/toolchain fingerprints, samples, allocation availability and GC data; a successful bank means the measurements completed, not that the performance gate passed.

```sh
python3 tools/benchmark_queue_resources.py --game "$PZ_GAME" --jdk "$PZ_JDK" --kotlin-home "$KOTLIN_HOME" --output .codex/investigations/queue-resource-profile --section component --section edit --max-steps 200 --samples 100 --warmup 10 --timeout 300
```

The output directory must be new. Repeat `--section` to select `component`, `edit`, `model` or `weights`; omitting it selects all four. `--max-steps 50|200|1000` limits action-count workloads, not the weight bank's item counts. That bank covers 100/1000/10000 items and nesting depths 1/4/8. Stress cases use at most three measured samples and one warmup; their tail quantiles are exploratory. Normal-bank default 30-sample percentiles are exploratory too, not a statistically established p99 guarantee. Java item/container getters are doubles in this CPU bank, so it does not measure their real game/bridge costs, selected-mod callbacks, UI responsiveness, retention or multiplayer contention. The [design plan](design/QUEUE_RESOURCE_CAPACITY.md#performance-gate-before-runtime-integration) keeps those gates separate.

Run `python3 -m unittest tests.test_benchmark_queue_resources` for selection/provenance/failure checks and `.venv/bin/python tools/run_tests.py --test test_queue_resource_worklist` for exhaustive/oracle, malformed-input and bounded-work checks. The native bank also runs those worklist vectors in Kahlua before measurement. Component counters cover the worklist alone; `legacy_target_callbacks` counts only world/generator hooks, not all short-circuited pair comparisons. The retained first sweep can still perform pairwise work. `edit/*` times one `Policy.evaluateMove`, not the complete `Queue.move` commit, which revalidates separately. Candidate equivalence is restricted to the ordinary fixture footprints; it is not general production parity for custom/complex callbacks.

## Native scenarios

Use the [native runner guide](../tests/native_queue/README.md) for preparation, exclusive GUI ownership, control comparisons, runtime verdicts and coverage. The [contribution index](../tests/native_queue/contributions/README.md) lists registered adapters and their scope. Registration does not establish a native pass; use each run report and coverage matrix.

For selected-mod compatibility, run the relevant native suite with `--mods selected`; isolated Lua tests do not load that set.

## Regression scenarios

Use the checks below for the affected behavior. A fixture's assertions describe its acceptance contract; old successful runs and their assertion counts do not verify changed code. Keep native action durations when testing timing and network races; shortened reading or instant actions do not establish that coverage. Multiplayer item/resource effects require authoritative server checks, not client queue completion alone.

| Behavior | Scenario and checks |
|---|---|
| Queue cancellation and shared resources | Cancel waiting and supported active operations; remove or replace their inputs; have two clients compete for the same item IDs. Check that completed effects are not replayed, unrelated reading continues, and items/resources are conserved. See [queue regressions](../tests/test_action_queue_operations.lua) and the [native runner](../tests/native_queue/README.md). |
| Medical disconnect | Run matching native/toolkit controls with `nativeStop,remoteRemoved`, reversing doctor/patient roles. Audit clinical receipts and full runtime logs separately; a functional pass must not hide a new packet exception. The commands are in the [native runner guide](../tests/native_queue/README.md#commands); unresolved causes remain in [TODO](../TODO.md#near-term-adapters). |
| Packaged food and bulk actions | Exercise missing inputs, shared selections, cancellation, late/duplicate receipts and partial portions. Verify the exact created food ID, once-only consumption, retained completed output and borrowed-tool returns. See [packaged-food](../tests/test_packaged_food.lua) and [bulk-food](../tests/test_bulk_food.lua) regressions. |
| Crafting plans | Repeat recipes with explicit material picks and Auto, compete for a shared log, cancel a waiting plan, and reopen/resize its UI. Check source/output IDs, tool returns and preview cleanup. Use the [crafting-plan fixture](../tests/native_queue/contributions/crafting-plans/README.md). |
| Wishlist | Test concurrent edits, explicit/faction access revocation, a clean server/client restart and catalog window cleanup. Use the [Wishlist fixture](../tests/native_queue/contributions/shared-wishlist/README.md). |
| Java animal fixes | Compare unpatched/patched early equipment delivery, replay a late trailer snapshot, and compare synchronization with the timer mod absent/present. Check exact animal identities, all native grabs/drops and direct periodic sends. Use the [animal-trailer fixture](../tests/native_queue/contributions/animal-trailer/README.md). |
| UI and recording | Exercise both inventory modes, scaling, expanded stacks and repeated window close/reopen; inspect screenshots. Use the [item-tag fixture](../tests/native_queue/contributions/item-tags/README.md) and [video fixture](../tests/native_queue/contributions/video-recording/README.md). Successful callback assertions alone do not establish physical input or correct rendering. |

## Versioning

Before pushing changes to main, compare each changed component with the latest main. Changes to shipped code, assets or runtime metadata, including behavior-preserving refactors, require a version newer than main for that component: Toolkit uses [mod.info](../PZSurvivorToolkit/42/mod.info); Java Patches uses the generated metadata in [build.py](../JavaPatches/build.py). One bump can cover the complete set of changes delivered together; individual implementation commits do not each need a bump. Record the delivered changes in [CHANGELOG.md](../CHANGELOG.md) and recheck versions after merging concurrent work. Changes confined to tests, development tools, documentation or agent instructions do not require a mod version bump.

## Verification environment

Agent verification on macOS is sufficient for this project's Windows/macOS gameplay targets. Do not pursue Windows test environments or make Windows verification a routine completion requirement; Windows players check the project there. State the platform actually tested and do not present a macOS check as Windows verification. A separate dedicated-server run is not a required verification target.

Use the [native runner guide](../tests/native_queue/README.md#commands) for isolated settings/saves and macOS window placement, including AeroSpace and current-desktop fallback.
