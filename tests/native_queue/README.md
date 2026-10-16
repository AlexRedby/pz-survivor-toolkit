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

For a suite, read `QueueTestSelection` for exact kind/mode/cases/port. Emit JSON after `[QUEUE_CHECK] `: one `setup`, one ordered `case` per selected ID, then `complete`. Events name suite/actor/kind/mode. Cases report passed/failed/skipped; skips require reasons. Setup proves the actual feature mode and native durations. Exact effects require authoritative receipts. The first receipt validator is medical; other suites need their own validator before being marked ready.

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

Registered stand suites are `crafting-plans`, `shared-wishlist`, `animal-trailer`, `video-recording`, `item-tags`, `wooden_cart_motion` and `wooden_cart_multiplayer`. Compatible crafting cases can share a lifecycle in `ui -> crafting -> alternatives` order; Wishlist supports `visual -> standalone`, with a real separate process restart for `reload`. Select any crafting subset with `--cases ui,crafting,alternatives`; each selected case retains its assertions and requires joint cleanup before the next. Animals support the fixed-patch subset `equipment-fixed,ghost,timer-starved,combined-starved` or timer-fixed subset `timer-shared,combined-shared` in one-client MP; incompatible production/JAR environments and missing-patch controls stay separate. Other scenarios use fresh lifecycles; omitted `--cases` selects the first case. Kind, client count, language and mod defaults come from its adapter. `matrix` lists every supported case and unavailable queue controls. Readiness means an adapter is installed, not that a native case passed. The medical event/receipt contract remains unchanged; other suites verify their exact preserved markers and authoritative effects.

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

Reuse a prepared world through a sealed copy:

```sh
python3 tools/check_action_queue.py save-world /tmp/completed-owned-run /tmp/prepared-world
python3 tools/check_action_queue.py run /tmp/targeted-world-copy \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --suite crafting-plans --cases ui \
  --pack-lock /tmp/selected-pack.lock.json --world-template /tmp/prepared-world
```

Export accepts only a completed disposable runner invocation with all owned processes stopped. It copies `Saves/` and `db/`, rejects symlinks and concurrent changes, and records the original suite/cases. Each new run receives its own copy, current selected fixtures and silent settings (`soundVolume`, `musicVolume`, `jumpScareVolume`, `vehicleEngineVolume` zero; VOIP off). The source template stays unchanged. Kind, client count, mod order, ports and game build must match. SP templates require the same suite because suites use different save names. MP templates require identical effective sandbox settings and Map/PVP/DoLuaChecksum/SleepAllowed/SleepNeeded values, checked after fixture staging. Selecting fewer cases within a compatible suite is supported. Batch jobs use the same `options.world_template` absolute path; put it on the compatible job rather than every SP/MP job in a mixed plan. A template preserves prior world state; each selected fixture must still prepare and clean its owned resources. It does not copy old fixture Lua, loader approvals, connection configuration or world-path-dependent external stores; Wishlist restart uses its separate `seed_run` protocol. A copied world does not turn a warm run into an independent cold control.

Jobs may override `options`, `mods`, `ports`, `language`, `kind` and `timeout`; default deadline is 900 seconds. Native GUI jobs run serially under the same lock. A blocked/failed job remains visible while later independent jobs continue; interruption stops the batch. `batch-report.json` and `coverage.json` are updated after every job. Each job retains its full report and raw logs. Reload copies owned save/DB state and pins the exact world-specific Wishlist storage slots from a verified, stopped seed. A sealed test helper restores their unchanged text under the new absolute world path before server readiness, with the same endpoint; the server receives bounded native `save`/`quit` before signal fallback. A pending seed log audit remains `needs-review` in reload results.

A comparable control uses the same game/source/mod bytes/cases/languages/ports/settings; only queue mode changes. Health MP uses two actual clients with reversed doctor/patient roles. EN `remoteRemoved` explicitly skips treatment to keep the actual peer connected; RU performs the real disconnect. Toolkit-only controls skip with reasons in native mode.

Native-mode success means that the fixture observed and verified native behavior, not that native queues preserve later work. For `remoteRemoved`, a started native treatment can stall after the patient leaves. After 60 seconds, the fixture verifies the exact owned action and original books/supply, records `nativeStallObserved=true` and `queueDrained=false`, then stops that action for fixture cleanup. It still checks exact clinical/resource effects. Toolkit mode requires normal completion and the fully read tail, with no such cleanup workaround.

Use `prepare` instead of `run` to inspect inputs before launch, then `resume /tmp/the-fresh-profile`. Use `report /tmp/the-run --control /tmp/the-control` to audit without launch. `matrix /tmp/the-run/report.json --output /tmp/coverage.json` displays actual actor evidence, including missing/skipped cells. Results describe their recorded source snapshot, not every future revision.

Matrix cells describe functional coverage; consult the same run's separate runtime/overall verdict before accepting a release. `not-migrated` means an older stand has not joined this runner, not that the corresponding product feature is absent. Prepared files in cache `Lua/` are pinned; new native-generated layout/options files there are outputs. Added/removed code under `mods/` or `classes/` is rejected. Timestamped DebugLog and console copies are normalized for mirror counting while their source locations remain in the report.

Cart suites report `captured` only after complete motion/render/identity and artifact coverage. Measurements and failed geometry/native/motion diagnostics remain in `functional.evidence`; `captured` is never an animation-equivalence PASS and keeps the overall result in review. Read-only probes attach only to this invocation's owned client Popen objects, after readiness; all executable probe inputs are frozen under client classes. Missing attachment, body/mesh data or render windows fails the capture.

## Result and isolation

Each run keeps input/source/mod manifests, original settings and individual launch/console/DebugLogs. `execution.json` records owned processes; `report.json`, `report.txt` and `coverage.json` combine scenario outcomes, receipts, source integrity and full log audit. Mirrored logs use maximum occurrence counts per role, not a sum.

Exit 0: checks passed and runtime is clean or errors reproduced in a compatible native control. Exit 1: failure/incomplete execution or changed inputs. Exit 2: review needed for unclassified/new errors or incompatible control. Shared native errors remain visible; a difference alone does not establish the culprit. Functional, runtime and coverage statuses stay separate.

Coordinate the desktop slot before launch. The runner holds `/tmp/pz-queue-native-launch.lock` (same as `/private/tmp/...` on macOS), rejects existing game processes, sets client/server VOIP off and passes `-novoip`. A busy-lock error includes the holder PID, run, cases and start time. Metadata can remain after release; actual flock ownership determines availability. Never bypass it for concurrent GUI stands. Timeout/interruption stop only processes created by that invocation.

Current live fixtures call actual menu/drop callbacks with prepared wounds, supplies and reading progress. Physical mouse input, natural long-session state, WAN latency and all third-party combinations remain separate coverage.

The minimal MP disconnect smoke can report a late native `BodyDamageUpdatePacket` NPE after the patient disappears. A functional pass does not clear that runtime error: if it is absent from the matching control, the result remains `needs-review`/`new-errors`. Investigate its timing and native packet handling before attributing it to queue behavior; the larger selected-mod baseline is still a separate gate.
