# Native test scenarios

[Development](../../docs/DEVELOPMENT.md#native-scenarios)

One preparation/launch/report tool, independent suites, and a fresh profile for every run. No shared mutable save. The product still uses the native `ISTimedActionQueue` executor.

## Files and contributions

- `tools/check_action_queue.py` and `tools/queue_checks/`: shared CLI, snapshots, process lifecycle and reports.
- `support/`: Java launcher, preflight and native fixture placement.
- `<suite>/{client,server,shared}/`: each suite's test-only Lua mod.
- `catalog.json` plus `tools/queue_checks/adapters/*.py`: declared cases, producers, capabilities, SP/MP and modes. Declarations are not passing tests.
- [`contributions/<topic>/`](contributions/README.md): preserved stand sources and their historical evidence/limitations. Adapters stage these sources; original intake metadata alone is not current run coverage.

Commit fixtures, parameters, assertions and reproduced limitations. Do not commit game/Workshop copies, compiled JARs/classes, profiles, saves, credentials, logs or videos. Outputs go outside the checkout or in ignored `dist/`. Delivered stands must not import `.codex/investigations` or hardcode a developer's directories.

For a suite, read `QueueTestSelection` for exact kind/mode/cases/port. Emit JSON after `[QUEUE_CHECK] `: one `setup`, one ordered `case` per selected ID, then `complete`. Events name suite/actor/kind/mode. Cases report passed/failed/skipped; skips require reasons. Setup proves the actual feature mode and native durations. Exact effects require authoritative receipts. Each MP suite must validate its own authoritative effects before being marked ready.

## Commands

Preparation needs Python 3.11+, JDK 25+ and installed B42.21 game files. Native GUI launch currently supports macOS. The core runner needs no Python packages; the SP cart mesh analyzers additionally require NumPy, as declared in their contribution. Health fixture selfchecks use `luajit` on PATH; existing product Lua regressions separately use `lupa`.

```sh
python3 -m unittest discover -s tests -p 'test_queue_*.py'
python3 tests/native_queue/health/check.py
python3 tools/check_action_queue.py matrix
```

Set local `PZ_GAME` to the directory containing `projectzomboid.jar`, and `PZ_JDK` to a JDK root. Use the same queue-independent selection in both modes:

```sh
python3 tools/check_action_queue.py run /tmp/pz-control-fresh \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --kind mp \
  --mode native --cases nativeStop,remoteRemoved
python3 tools/check_action_queue.py run /tmp/pz-toolkit-fresh \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --kind mp \
  --mode toolkit --cases nativeStop,remoteRemoved --control /tmp/pz-control-fresh
```

The default suite is health and default mod set is only `PZSurvivorToolkit`. Use `--mods selected --workshop /path/to/workshop/content/108600` for the project INI; repeat `--workshop` for other explicit installed roots. Missing/ambiguous Mod IDs fail. Required Java patch artifacts must already be built using `tools/prepare_install.py`.

For startup diagnostics, use `--suite startup --cases loaded --kind sp|mp`. This one-client smoke stops after native game start and a living player on a loaded square, without gameplay fixtures or animal/trailer actions. It retains the shared microphone/display preflight, source/snapshot checks, full log audit and owned-process cleanup. A functional load pass does not accept engine errors. MP supports compatible `--world-template` copies; SP currently requires a fresh world and rejects templates explicitly.

For actual in-game Host, use `--kind mp` with `{"mp_host":true}` in config/job options. Suites using the common startup bootstrap launch native `CoopServer` from `client1`; a second client, when selected, joins after server readiness. This requires a fresh world and the fixture identities. The child inherits the selected ZombieBuddy agent/approvals, shares its owner's isolated cache, and has `VoiceEnable=false`; clients retain `-novoip` and silent settings. Both JVMs count toward admission. The report preserves the full child console/server DebugLogs and archived client logs, verifies the child belongs to the owned launcher, and audits cleanup. Omitting this option retains the independent GameServer route.

Craft uses `--suite craft --cases borrowed-tools,cancel-pickup,missing-input`, or an ordered subset, in one fresh SP/Host session. `borrowed-tools` retains its synthetic late-callback stress hook, which adds real native returns after base.perform; it does not claim physical crafting UI coverage. The two abort cases use native manual selections and pickup/craft/return/read actions without changing their callbacks or durations. `cancel-pickup` requests operation cancellation during the second real pickup, after the first tool arrived. `missing-input` removes the exact unspent Plank on the authority while a normal reading action between pickups and craft runs, allowing replication before the native manual start. Receipts distinguish that removal from recipe consumption and require zero outputs, conserved exact tool IDs/condition/uses, committed container endpoints and an independent completed reader in Toolkit mode. Native controls keep their actual lost-reader or late-return failures. Input-loss preservation is limited to queued manual crafts before native action allocation; later input changes follow the native recipe lifecycle.

For active checks use `--suite craft --cases borrowed-tools,cancel-craft,late-input`. `cancel-craft` and `late-input` select active-stage checks: they wait for native craft progress (and a matching server started receipt in Host), then request cancellation or remove the exact still-unspent Plank on the authority. Receipts record the removed input separately from the recipe's input count on each new output, preserve spare Planks and prior outputs, and correlate real started/terminal State messages; completed means the native action settled, not that a recipe necessarily produced an output. In the B42.21 fixed manual fixture, removing the Plank after start still produces one native output from the retained selected object; the same result is verified with the queue disabled. This does not authorize skipping or replaying an already started craft. All cases wait for real native queue quiescence before final authority verification; the sources remain sealed while the session runs.

Fire uses `--suite fire --cases fuel,missing-target-after-expansion` (or either case alone) for SP/MP, native/toolkit. Both cases share one fresh session and use real campfire, adjacent borrowed Log, transfers and reading durations. The source crate is created before the campfire so removing the target cannot shift the pickup source's network object index. The missing target is removed during native pickup, after expansion. Toolkit must return the exact unspent Log before reading. Native controls retain their actual failures: missing target remains red with its stock exception and unread tail; MP fuel also fails if its independent reader is lost, even when fuel consumption succeeds. These are reproduction evidence, not passing controls for waiving runtime errors. Native missing-target controls intentionally leave the stock queue failed: run that case alone or after `fuel` in its own fresh session, and run ignition controls separately.

Additional selectable Fire cases are `literature,petrol,last-match,bbq-fuel,bbq-literature,bbq-petrol,kindle-retry`; they can share the same session with the fuel cases. Receipts correlate exact consumed/returned IDs, starter uses, petrol debit, first ignition fuel, native charcoal BBQ state and the independent reader. Read-only OnTick and OnTickEvenPaused observers capture the effect before the next native fuel burn, including MP completion after OnTick. Petrol stays in the player's inventory through the independent reader according to the native callback. Before taking the final receipt, the fixture observes P4TidyUpMeister's unchanged diagnostic log through a forwarding print observer and waits for native OnPlayerUpdate quiescence and restore completion. The public P4 table contains registration methods; its session tables are private. A later petrol return is accepted only with exact original-container/session provenance, real native transfer progress after the reader, unchanged operation ownership, committed client location and a matching authoritative endpoint; it is recorded separately from the native callback returns. `kindle-retry` samples up to eight valid, naturally randomized trials within one session until a real retry runs before returns; missing retry evidence fails coverage. Exhausting every tracked stick can finish unlit with unchanged fuel. Native durations retain their normal moodle adjustment, sound/VOIP remain disabled, and runtime errors remain visible.

`bbq-kindle,fireplace-fuel,fireplace-literature,fireplace-petrol,fireplace-kindle` extend the same selectable session. Receipts identify actual campfire, charcoal BBQ or fireplace classes. The fireplace uses native `IsoFireplace` and `ISBBQ*` callbacks; its petrol case consumes the last match. BBQ/fireplace Kindle uses one borrowed plank and stick with native duration and RNG. It has no automatic retry: lighting, breaking the stick, or finishing unlit with an intact stick are native terminal outcomes. An unlit outcome must leave fuel unchanged, surviving tools must return before reading, and MP still requires a valid completed operation. SP can stop normally after lighting/breaking; this is distinct from the campfire `kindle-retry` contract, which still requires real retries and may finish unlit only after exhausting every tracked stick.

```sh
python3 tools/check_action_queue.py run /tmp/startup-vanilla-fresh \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --suite startup --kind sp \
  --mode native --mods vanilla
python3 tools/check_action_queue.py run /tmp/startup-pack-fresh \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --suite startup --kind mp \
  --pack-lock /tmp/selected-pack.lock.json --world-template /tmp/prepared-world
```

For the trusted local Java Patches font candidate, add `"preload_toolkit_fonts": true` to config/job options. This explicitly appends the documented `patches_jar=<sealed selected fonts JAR>:net.alexredby.pztoolkitbootstrap` option to the client's existing single ZombieBuddy agent; both mods must be selected and ordinary mod metadata and the separate font bootstrap manifest must match. It does not write an unsigned entry into the signed preload cache. Omit it for the ordinary-load control. Use a new prepared snapshot when changing this option.

`--mods vanilla` is restricted to startup/native and enables only the test helper, with no production mods or ZombieBuddy agent. Omitting `--mods` retains suite defaults. The pack plan's `startup` set runs only this load check; its gameplay sets remain independent.

Prepared MP worlds retain their original whitelist. Startup defaults to `client1` / `smoke-local-only`; supply the fixture's existing credentials through `--config` or job options as `{"startup_connection":{"username":"client1","password":"isolated-native-only"}}` for a world created by the grouped animal fixture. A single-case animal fixture instead uses username `animal-fixture`. This changes the test connection only; it does not reset the saved whitelist or character.

Registered stand suites are `crafting-plans`, `shared-wishlist`, `animal-trailer`, `video-recording`, `item-tags`, `quartermaster-presets`, `quartermaster-transfers`, `wooden_cart_motion` and `wooden_cart_multiplayer`. Compatible crafting cases can share a lifecycle in `ui -> crafting -> alternatives` order; Wishlist supports `visual -> standalone`, with a real separate process restart for `reload`. Select any crafting subset with `--cases ui,crafting,alternatives`; each selected case retains its assertions and requires joint cleanup before the next. Animals support the fixed-patch subset `equipment-fixed,ghost,timer-starved,combined-starved` or timer-fixed subset `timer-shared,combined-shared` in one-client MP; incompatible production/JAR environments and missing-patch controls stay separate. Other scenarios use fresh lifecycles; omitted `--cases` selects the first case. Kind, client count, language and mod defaults come from its adapter. `matrix` lists every supported case and unavailable queue controls. Readiness means an adapter is installed, not that a native case passed. The medical event/receipt contract remains unchanged; other suites verify their exact preserved markers and authoritative effects.

`quartermaster-presets` has two SP cases: `seed` creates two global presets and saves their all/any tag rules through the native editor's Save callback; `reload` requires `options.seed_run` (or a batch `seed_job`) pointing to that completed, stopped, clean seed. Reload copies only `Lua/QuartermasterPresets.txt` and `Lua/PZSTQuartermasterTagRules.txt` into its fresh cache, pins the seed evidence and files, and checks unchanged generations, include/exclude rules, category resolution and byte-identical stores after a separate game process. It creates a fresh world because these SP stores are global to the cache. World templates and Host are unsupported for these cases; programmatic UI callbacks do not certify physical input.

Pass suite resources as a JSON object with `--config FILE`: video needs absolute `ffmpeg`/`ffprobe`; animals need `patch_jar`; cart captures need those three plus explicit candidate `mod_sources` and SP `mesh_fbx`. Item tags need Toolkit with the documented ItemTags/TagVisuals APIs (now present in main); use an explicit candidate when testing another revision. `--mod-source MOD_ID=/absolute/mod/root` explicitly selects one candidate instead of the checkout/Workshop. These paths and bytes are recorded; no installed-profile or old temporary-cache fallback is used. Third-party timer cases require the exact declared timer JAR. Candidate tests do not verify the corresponding released/main feature.

For sequential runs, `batch` accepts a JSON plan and a new output directory:

```json
{
  "game": "/path/to/game/Java",
  "jdk": "/path/to/jdk",
  "workshop": ["/path/to/explicit/mod/root"],
  "options": {"ffmpeg": "/path/to/ffmpeg", "ffprobe": "/path/to/ffprobe"},
  "jobs": [
    {"id": "video-control", "suite": "video-recording", "case": "captures", "mode": "native"},
    {"id": "video-toolkit", "suite": "video-recording", "case": "captures", "control_job": "video-control"},
    {"id": "wishlist-seed", "suite": "shared-wishlist", "case": "standalone"},
    {"id": "wishlist-reload", "suite": "shared-wishlist", "case": "reload", "seed_job": "wishlist-seed"}
  ]
}
```

```sh
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/native-stands-fresh
```

For feature development, select only the relevant jobs or a named plan set:

```sh
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/craft-fresh --set craft
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/targeted-fresh --jobs wishlist,tags
```

Plans define `sets` as names mapped to job ID lists. Required `control_job` and `seed_job` dependencies are included automatically, in plan order. `--skip-jobs` disables jobs, but disabling a required dependency is an error before preparation. Unselected jobs are not prepared and their fixtures are not installed. [The pack plan example](plans/pack-regression.example.json) includes targeted sets and a separate `full` set; replace its local paths before use. The full set is explicit regression scope, not evidence that every loaded mod has behavioral coverage.

Lock the actual selected pack once its local sources are available:

```sh
python3 tools/check_action_queue.py lock-pack /tmp/selected-pack.lock.json \
  --game "$PZ_GAME" --workshop /path/to/workshop/content/108600 \
  --mod-source Quartermaster=/path/to/Quartermaster
```

Repeat `--mod-source` for explicit local sources. The lock records the INI settings, ordered Mod IDs, Workshop IDs, versions when supplied by the mod, every source file hash and the game build. Use `--pack-lock /tmp/selected-pack.lock.json` with `prepare`/`run`, or `options.pack_lock` in a plan; suite defaults then use the locked pack. Missing sources or changes block preparation and resume. MP runs apply the selected pack’s Map, PVP, DoLuaChecksum, SleepAllowed and SleepNeeded settings; checksums stay enabled. Public listing, UPnP and automatic Workshop downloads stay disabled in disposable local stands. After changing a mod, create a new lock explicitly and keep the previous lock for comparison.

For a modpack change, retain the baseline lock and reports, create a new candidate lock, and run the same selected set against it. Functional case assertions expose regressions in the candidate. A changed pack is not a matching queue-disabled control: use a separate native/toolkit pair inside each pack when that comparison is needed; cross-pack runtime messages remain reviewable rather than being silently accepted as baseline errors.

Reuse a prepared world through a sealed copy:

```sh
python3 tools/check_action_queue.py save-world /tmp/completed-owned-run /tmp/prepared-world
python3 tools/check_action_queue.py run /tmp/targeted-world-copy \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --suite crafting-plans --cases ui \
  --pack-lock /tmp/selected-pack.lock.json --world-template /tmp/prepared-world
```

Export accepts only a completed disposable runner invocation with all owned processes stopped. It copies `Saves/` and `db/`, rejects symlinks and concurrent changes, and records the original suite/cases. Each new run receives its own copy, current selected fixtures and silent settings (`soundVolume`, `musicVolume`, `jumpScareVolume`, `vehicleEngineVolume` zero; VOIP off). The source template stays unchanged. Kind, client count, mod order, ports and game build must match. Omitted ports reuse the template endpoint; conflicting explicit ports are rejected. SP templates require the same suite because suites use different save names. MP templates require identical effective sandbox settings and Map/PVP/DoLuaChecksum/SleepAllowed/SleepNeeded values, checked after fixture staging. Selecting fewer cases within a compatible suite is supported. Batch jobs use the same `options.world_template` absolute path; put it on the compatible job rather than every SP/MP job in a mixed plan. A template preserves prior world state; each selected fixture must still prepare and clean its owned resources. It does not copy old fixture Lua, loader approvals, connection configuration or world-path-dependent external stores; Wishlist restart uses its separate `seed_run` protocol. A copied world does not turn a warm run into an independent cold control.

Jobs may override `options`, `mods`, `ports`, `language`, `kind`, `resources`, `resource_wait` and `timeout`; default deadline is 900 seconds. Jobs within a batch run sequentially; independent commands or batches may run concurrently through shared resource admission. A blocked/failed job remains visible while later independent jobs continue; interruption stops the batch. `batch-report.json` and `coverage.json` are updated after every job. Each job retains its full report and raw logs. Reload copies owned save/DB state and pins the exact world-specific Wishlist storage slots from a verified, stopped seed. A sealed test helper restores their unchanged text under the new absolute world path before server readiness, with the same endpoint; the server receives bounded native `save`/`quit` before signal fallback. A pending seed log audit remains `needs-review` in reload results.

A comparable control uses the same game/source/mod bytes/cases/languages/settings and explicit ports (automatic transport endpoints are normalized); only queue mode changes. Health MP uses two actual clients with reversed doctor/patient roles. EN `remoteRemoved` explicitly skips treatment to keep the actual peer connected; RU performs the real disconnect. Toolkit-only controls skip with reasons in native mode.

Native-mode success means that the fixture observed and verified native behavior, not that native queues preserve later work. For `remoteRemoved`, a started native treatment can stall after the patient leaves. After 60 seconds, the fixture verifies the exact owned action and original books/supply, records `nativeStallObserved=true` and `queueDrained=false`, then stops that action for fixture cleanup. It still checks exact clinical/resource effects. Toolkit mode requires normal completion and the fully read tail, with no such cleanup workaround.

Use `prepare` instead of `run` to inspect inputs before launch, then `resume /tmp/the-fresh-profile`. Use `report /tmp/the-run --control /tmp/the-control` to audit without launch. `matrix /tmp/the-run/report.json --output /tmp/coverage.json` displays actual actor evidence, including missing/skipped cells. Results describe their recorded source snapshot, not every future revision.

Matrix cells describe functional coverage; consult the same run's separate runtime/overall verdict before accepting a release. `not-migrated` means an older stand has not joined this runner, not that the corresponding product feature is absent. Prepared files in cache `Lua/` are pinned; new native-generated layout/options files there are outputs. Added/removed code under `mods/` or `classes/` is rejected. Timestamped DebugLog and console copies are normalized for mirror counting while their source locations remain in the report.

Cart suites report `captured` only after complete motion/render/identity and artifact coverage. Measurements and failed geometry/native/motion diagnostics remain in `functional.evidence`; `captured` is never an animation-equivalence PASS and keeps the overall result in review. Read-only probes attach only to this invocation's owned client Popen objects, after readiness; all executable probe inputs are frozen under client classes. Missing attachment, body/mesh data or render windows fails the capture.

### Craft UI callbacks

Use `--suite craft-ui --cases context,vanilla-batch,neat-batch,cook-batch` for an ordered subset in one fresh SP/Host session. The context case selects the real menu option; batch cases use actual vanilla, Neat and Project Cook controls and their button dispatch. Batch cases pin explicit material selections and execute two native crafts with unchanged durations. The fixture dispatches the installed completion/cancellation callbacks without replacing them. Automatic batch selection is a separate scope: B42.21 can pass `manualInputs=false` into a Java path expecting a table.

The fixture equips its tool bags with native actions and verifies they appear in the real UI source list. Authority receipts check consumed IDs, new outputs, exact tools and endpoints, and an independent reader. Client telemetry separately checks unchanged callbacks, real craft progress, shared completion ownership, return order and the owner's final busy/batch state. An output alone does not prove that the owner is idle. Native control failures remain visible. This is programmatic UI dispatch, not physical mouse or controller coverage; cancellation, input loss and unknown callbacks remain separate gates before removing the family fallback.

## Result and isolation

New preparations also seal the full file lists and hashes under the live game's `media/lua` and `media/scripts` trees in `game-inputs.json`. Added, removed or changed files invalidate preparation, launch and reports. This guard covers Lua, translations and script inputs; it does not seal every native library or asset directory. Older prepared runs without this seal require fresh preparation.

Each run keeps input/source/mod manifests, original settings and individual launch/console/DebugLogs. `execution.json` records owned processes; `report.json`, `report.txt` and `coverage.json` combine scenario outcomes, receipts, source integrity and full log audit. Mirrored logs use maximum occurrence counts per role, not a sum.

Exit 0: checks passed and runtime is `clean` or `background-only`. Exit 1: runtime failures, failed/incomplete execution or changed inputs. Exit 2: review needed for unclassified/new errors or incompatible control. A matching native control never clears runtime failures or unknown errors; it only records reproduction. Functional, runtime and coverage statuses stay separate.

Every runtime issue retains its message, location, fingerprint and occurrence count, plus `fatal`, `unclassified` or `background` severity. The inspected B42.21 engine JAR and source-verified single-client EN MP animal `equipment-fixed`/`equipment-missing` profiles permit only exact startup fluid-name normalization, fence sound defaults, Piano icon fallback and property-name fallback. Caller/stack, tile/property identities, readiness boundaries and per-message counts are checked; different profiles/builds, late messages and extra occurrences do not receive an automatic background verdict. Font page failures, skipped mannequin zones and other room-ID errors remain visible and require review. The exact `Basements.mergeRoomsOntoMetaCell` diagnostic `duplicate RoomDef.metaID for room at 10707,9484,0` is accepted for the verified B42.21 engine by the [explicit project decision](../../JavaPatches/README.md#map-data-and-cross-cell-basement-rooms); its raw messages and counts stay visible. The user approved the guarded split-key experiment and its save dependency; its gameplay fixture must prove actual key separation rather than rely on this background exception. The exception still covers native controls and unsupported-source fallback. Other coordinates, builds, methods and attached exceptions retain ordinary auditing.

Independent commands can run concurrently; there is no runner-count limit. Each launch atomically reserves an estimated memory/CPU budget in the per-user temporary `pz-native-<uid>` registry. The default per game process is 2048 MiB maximum Java heap, 1024 MiB estimated native/graphics/encoder memory and 1 logical CPU. MP normally reserves three processes, including its server. Configure `--heap-mib`, `--native-mib` and `--cpu-per-instance` during preparation; the heap setting also controls the actual JVM `-Xmx`. Batch plans accept the corresponding `resources` object (`heap_mib`, `native_mib`, `cpu_per_instance`, `exclusive`) at plan/job level.

Admission samples current host memory and process CPU, leaves the larger of 1 GiB or 10% physical RAM for the host, and subtracts the unconsumed portion of existing reservations. Resident memory is not charged twice. Startup reserves exist before the first child starts. `--resource-wait SECONDS` on run/resume bounds waiting (default 300, 0 refuses immediately); batch plans use `resource_wait` at plan/job level. Sampling failures stop admission. These are estimates, not OS memory/CPU/GPU limits: `ps` CPU values are averages, and mods/graphics/encoders can exceed the native estimate. Size it for the tested workload. Running processes are not killed when unrelated host load changes.

Omitting `--ports` reserves a unique adjacent UDP pair before freezing an MP profile. Resume preserves it; explicit ports wait until available at launch. Prepared automatic endpoints remain reserved until their output is removed or their run stops. Wishlist reload preserves its stopped seed endpoint. Port probes and reservations coordinate cooperating runners; an unrelated program may still bind between the probe and the game's bind, which causes a startup failure rather than reassignment of frozen inputs.

The old `/tmp/pz-queue-native-launch.lock` is held shared for the entire lifecycle, excluding legacy runners that require it exclusively. Use `--exclusive` during preparation for physical mouse/keyboard automation or timing/performance comparisons; it requests exclusive desktop admission. An unrelated game in a different profile is accounted as host load. A game already using the requested cachedir blocks that profile. Keep the shared game installation unchanged; Java/native mods writing outside cachedir require their own isolation. Background clients use `pauseOnFocusLoss=false`. Client/server VOIP stays off and every launch passes `-novoip`.

Timeout/interruption stop only processes created by that invocation. A crashed runner's reservation remains while its cachedir still has live game processes, including a crash between Popen and PID reporting. Stale owner PIDs alone never release it. Reservations disappear after the remaining games stop; discovery never kills another run's processes. `execution.json` records the admitted budget and host capacity snapshot.

Current live fixtures call actual menu/drop callbacks with prepared wounds, supplies and reading progress. Physical mouse input, natural long-session state, WAN latency and all third-party combinations remain separate coverage.

The minimal MP disconnect smoke can report a late native `BodyDamageUpdatePacket` NPE after the patient disappears. This runtime exception fails the run even when functional assertions pass or a matching control reproduces it. Investigate its timing and native packet handling before attributing it to queue behavior; the larger selected-mod baseline is still a separate gate.

`quartermaster-transfers` runs SP `manifest` in queue-disabled (`native`) and `toolkit` modes. Two designated world crates exercise successful, capacity-limited partial and rejected native transfers; a crate-to-player withdrawal changes the open Manifest aggregate. Assertions follow exact item IDs, per-square snapshots, dirty deferral until queue drain, live window totals, and denial reasons for real opaque Walk/Deposit/CraftTrigger actions without changing the queue. Cleanup respects the native designation grace period. Use the same pack lock for both modes; this covers programmatic callbacks and engine actions, not physical input or Host.
