# Native test scenarios

[Development](../../docs/DEVELOPMENT.md#native-scenarios)

One preparation/launch/report tool, independent suites, and a fresh profile for every run, without changing the user's current settings or saves. No shared mutable save. The product still uses the native `ISTimedActionQueue` executor.

## Files and contributions

- `tools/check_action_queue.py` and `tools/queue_checks/`: shared CLI, snapshots, process lifecycle and reports.
- `support/`: Java launcher, preflight and native fixture placement.
- `<suite>/{client,server,shared}/`: each suite's test-only Lua mod.
- `catalog.json` plus `tools/queue_checks/adapters/*.py`: declared cases, producers, capabilities, SP/MP and modes. Declarations are not passing tests.
- [`contributions/<topic>/`](contributions/README.md): fixture sources, acceptance contracts and limitations. Adapters stage these sources; registration alone is not current run coverage.

Commit fixtures, parameters, assertions and reproduced limitations. Do not commit game/Workshop copies, compiled JARs/classes, profiles, saves, credentials, logs or videos. Outputs go outside the checkout or in ignored `dist/`. Delivered stands must not import `.codex/investigations` or hardcode a developer's directories.

Read [commands](#commands) for a first run, [batch plans](#batch-plans) and [pack locks](#selected-pack-locks) for comparisons, and [results and isolation](#result-and-isolation) for acceptance. Suite commands and behavior contracts live in the [scenario cookbook](SCENARIOS.md); specialized fixtures are indexed under [contributions](contributions/README.md).

## Commands

Preparation needs Python 3.11+, JDK 25+ and installed B42.21 game files. The macOS runner supports the catalogued suites. Windows has a bounded one-client Host launch path for `startup` and `forge`, using the game's bundled Java runtime, explicit ports, isolated loader approvals and a Windows Job Object that owns only the test client and its descendants. A named lease serializes this initial Windows launch path; available-memory and disk guards run before launch. Other Windows suites and physical input automation are not supported by that path. The core runner needs no Python packages; the SP cart mesh analyzers additionally require NumPy, as declared in their contribution. Health fixture selfchecks use `luajit` on PATH; existing product Lua regressions separately use `lupa`.

Mod snapshots prefer macOS copy-on-write file clones where the filesystem supports them. Each role has independent file identities and private subsequent writes; unsupported or cross-filesystem copies use ordinary copying. File metadata and source/snapshot hash checks remain in place. Disk admission still budgets for ordinary copies and later private writes, without reducing runtime or peer reserves. Saves, settings and logs keep their existing separate paths.

### Desktop launch

Use the normal command outside the sandbox in the logged-in macOS session. No desktop strategy flag or awake-screen preparation is needed:

```sh
python3 tools/check_action_queue.py run /tmp/startup-fresh \
  --suite startup --kind sp --mode native --mods vanilla \
  --game "$PZ_GAME" --jdk "$PZ_JDK"
```

The default is `auto`. It first uses AeroSpace to move each owned game window to `PZ-TEST` before revealing it. Choose another workspace with `{"test_workspace":"NAME"}` in `--config`. The runner never switches the user's workspace or focuses a test window. You may visit the test workspace and observe its windows. Physical monitors and AeroSpace workspaces are different: sleeping the one physical screen can make GLFW lose its primary monitor even though virtual workspaces still exist.

Fresh macOS preparations extract a private GLFW copy from the sealed B42.21 game JAR. Only the exact reviewed ARM64/x64 library fingerprints are accepted. One reviewed enumeration branch is changed so connected displays remain available to GLFW while asleep; the copy is ad-hoc signed and sealed in `native/`. The installed game, physical display state and CoreGraphics observations are unchanged. Every client uses this copy through `org.lwjgl.glfw.libname`; servers retain their normal launch. `execution.json.desktop.glfw` records the source/native hashes and compatibility rule. Missing, changed or unreviewed input requires fresh preparation or compatibility review, never silently selecting another library.

After a valid owned PID/GLFW handshake, AeroSpace has 30 seconds to discover the window. Java startup has a separate 120-second bound. If that client was observed with sleeping displays and they are awake at discovery expiry, one additional 15-second AeroSpace-only grace permits discovery after wake; it never authorizes current-desktop fallback on an awake screen. The Java acknowledgement gate allows 90 seconds for discovery, the bounded wake grace and owned routing. If no owned window has ever been discovered and a fresh CoreGraphics probe confirms that every online physical display is asleep, `auto` may admit current-desktop fallback. Empty/failed/inconsistent display enumeration is `unknown`, not proof of sleep. GUI access is checked before launching; if it is unavailable, repeat the same command outside the sandbox rather than asking the user to wake the display. A screen lock alone does not establish display sleep. The runner's `caffeinate -i` prevents ordinary system idle sleep while allowing display sleep; full system sleep, logout and power-off cannot provide a running GUI test session.

Fallback clients are checked again during the run. When AeroSpace discovers their owned windows, the runner moves them into the test workspace and resumes strict placement/identity checks without reusing the initial acknowledgement. Recovery occurs at the next client check; sequential startup or Host readiness can delay it. Until placement is confirmed, the fallback window remains fully transparent while the game continues rendering. An atomic, PID/GLFW-bound visibility acknowledgement then lets the Java event thread reveal it on the test workspace; waking the physical screen alone cannot reveal it. Physical screen captures cannot establish current-fallback visual coverage; in-engine framebuffer checks are separate. Focus/fullscreen suppression remains active in both modes. Missing/malformed AeroSpace, CLI failures, foreign/malformed identities, dead clients, observed-then-missing windows, failed routing or escaped/replaced routed windows remain errors. Reports retain requested/actual mode, per-client modes, window/GLFW identities, fallback reason and per-PID sleep probes.

Window failures also write `desktop-incident.json` before probe shutdown and client termination. It distinguishes missing discovery, changed window identity, an observed wrong workspace, process exit and CLI failure, and retains the last verified placement plus timestamped CLI output (capped at 4 KiB per stream, with truncation flags; unverified/foreign window rows are redacted and counted). An isolated helper has 1.5 seconds to collect display/session state and CoreGraphics metadata for that owned PID; missing data remains unknown. No window titles or images are collected. The incident is also retained in `execution.json.desktop.incidents`; diagnostic/persistence failures do not replace the original error or authorize recovery. Native window existence alone does not prove AeroSpace workspace placement.

Use explicit policy flags only when necessary:

- `--desktop-mode aerospace`: require successful workspace placement, including when the physical display is asleep.
- `--desktop-mode auto`: explicitly override a JSON/plan policy with normal automatic behavior.
- `--desktop-mode current`: legacy compatibility alias for the same guarded automatic policy; it cannot force an awake-desktop launch or bypass AeroSpace errors.

The flags work for `prepare`, `run` and `batch`, and override `options.desktop_mode` in JSON. An omitted flag preserves an explicit config/plan policy, otherwise it defaults to `auto`. `resume` uses the sealed policy; prepare a fresh snapshot to change it. Automated fixture callbacks can run without physical input; mouse/keyboard automation needs an interactive session. A locked-session result does not prove a physically asleep-display result.


For a no-game native regression, run outside the sandbox with `PZ_GAME` and `PZ_JDK` exported:

```sh
PZ_NATIVE_GLFW_CHECK=1 python3 -B -m unittest discover -s tests -p test_queue_glfw_native.py -v
```

It checks the original GLFW against a child-process-only simulated sleep answer, then validates real NSGL framebuffer pixels with the private copy in ordinary and simulated-sleep conditions. It never changes the physical display and prints its real state separately. Passing this regression does not replace a physically asleep-display SP/Host run.

Test windows default to a logical windowed size of 1600 by 900, independent of the monitor's physical resolution. An adapter may declare a suite default; `item-tags` uses 1280 by 900. Set `window_size` in the JSON passed to `--config` to override either default:

```json
{
  "test_workspace": "PZ-TEST",
  "window_size": [1280, 900]
}
```

Batch plans use the same value in `options.window_size`. The value must be a JSON array of two integers: width 640..7680 and height 480..4320, inclusive. Booleans, fractional values and strings are rejected before profile copying or compilation. Preparation writes the resolved size into each disposable profile's `options.ini` before UI creation and records the expected size as `window_size` in `selection.json` and `runtime.json`. A suite cannot silently change it during staging. At game start, the common preflight records the actual Core logical size before readiness; a missing or mismatched observation fails the run. `report.json.window_size` keeps expected and observed sizes for each client; `report.txt` shows the same comparison. The OS may cap a window larger than its available working area; that is a mismatch, not a passing run. Choose a supported explicit size if the default does not fit. Framebuffer pixels may differ from this logical size. A large frame alone does not prove that every control is visible. Choose the required size before launch and prepare a fresh run when it changes. Manual resizing after startup is possible, but invalidates comparisons that depend on a fixed viewport and cannot establish UI coverage for the prepared size.

```sh
python3 -m unittest discover -s tests -p 'test_queue_*.py'
python3 tests/native_queue/health/check.py
python3 tools/check_action_queue.py matrix
python3 tools/check_action_queue.py matrix --suite startup --kind mp --mode toolkit
```

Use repeatable `--suite`, plus optional `--kind` and `--mode`, to limit scenario discovery and existing-report views to the task. The same filters apply to `--output` JSON; unsupported controls, missing runs and failed evidence retain their original statuses.

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

For actual in-game Host, use `--kind mp` with `{"mp_host":true}` in config/job options. Suites using the common startup bootstrap launch native `CoopServer` from `client1`; a second client, when selected, joins after server readiness. Use a fresh world or a compatible sealed menu-Host template with the original fixture identities. The child inherits the selected ZombieBuddy agent/approvals, shares its owner's isolated cache, and has `VoiceEnable=false`; clients retain `-novoip` and silent settings. Both JVMs count toward admission. The report preserves the full child console/server DebugLogs and archived client logs, verifies the child belongs to the owned launcher, and audits cleanup. Omitting this option retains the independent GameServer route.

Pass suite resources as a JSON object with `--config FILE`: video needs absolute `ffmpeg`/`ffprobe`; animals need `patch_jar`; cart captures need those three plus explicit candidate `mod_sources` and SP `mesh_fbx`. Item tags need Toolkit with the documented ItemTags/TagVisuals APIs (now present in main); use an explicit candidate when testing another revision. `--mod-source MOD_ID=/absolute/mod/root` explicitly selects one candidate instead of the checkout/Workshop. These paths and bytes are recorded; no installed-profile or old temporary-cache fallback is used. Third-party timer cases require the exact declared timer JAR. Candidate tests do not verify the corresponding released/main feature.

## Batch plans

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

### Sharing one game session

Give consecutive jobs the same `"session"` label to execute their cases in one game lifecycle. This is opt-in and currently supported by `torch-refill`: its three cases can share one SP launch and one menu-Host launch, instead of six separate launches. The [shared-session example](plans/shared-session.example.json) keeps the six selectable job IDs and groups them into two sessions. Set its game/JDK and current complete pack-lock paths before use. A direct `run --suite torch-refill --cases trunk-retained,root-retained,trunk-unmarked` also uses one session.

Every selected member must use the same suite with a declared `shared_session` contract, exact sources/options/mod order, mode, topology, language, ports and resource settings. Cases must be unique; member timeouts must match and are summed for the combined deadline. Mixed or unsupported groups fail before any profile is prepared. Groups cannot provide or consume control/seed dependencies or reuse a world template; those lifecycles remain separate. The label must be contiguous in the plan. `--jobs`, `--set` and `--skip-jobs` still select individual jobs; omitted cases are not run.

`storage-profile` also supports one ordered SP group, `inventory-work,inventory-freshness`. The workload capture runs first in a fresh world; exact inventory, player, UI and observer cleanup precedes the functional freshness case. `walk` and `inventory-food-age` retain separate timing baselines. Workload results remain captures, not automatic performance passes. Vehicle lights combines `dashboard`, `push` and `rocker` options within one SP or menu-Host `road` lifecycle, keeping its night/video environment separate from inventory and food-age tests.

### Outstanding in-game campaign

The [campaign plan](plans/in-game-campaign.example.json) maps the outstanding TODO blocks and reusable regression scenarios to executable jobs and explicit remaining acceptance gates. Make a local copy and supply the game/JDK, current complete pack lock, prepared Toolkit/Java source paths, patch JAR, FFmpeg/FFprobe and exact mesh inputs for cart injury analysis. Cart sets require a Python runtime with NumPy; confirm `python3 -c 'import numpy'` in the runtime used for the command. Campaign preflight checks these game, source, media and NumPy inputs before any game profile is prepared. This is still followed by the normal source/hash/runtime guards during preparation and execution.

Cart probe compilation also requires the matching Kotlin 2.4.21 distribution through `KOTLIN_HOME` or `kotlinc` on `PATH`; campaign preflight does not yet validate that compiler. The complete-pack example assigns a 4096 MiB heap to SP cart jobs, 2304 MiB per JVM to the extended shopping Host job and 3072 MiB per JVM to other Host cart jobs. The default 2048 MiB heap exhausted native region-buffer allocation during the 96x96 SP setup; the smaller 63x63 Host injury pad qualified separately with 3072 MiB. The extended shopping bank qualified with 2304 MiB on the 66-mod lock used on October 28, including both clients, all native actions, ordinary movement control and cleanup. That capture predates removal of three New Music packs and does not qualify the resulting 63-mod selection. Keep the native-memory estimate and admission guards: the Host selection reserves three JVMs, not one. These are qualified test budgets, not minimum-memory requirements or permission to accept runtime errors.

Use `--set qualification` for changed storage, dashboard and warehouse fixtures; `--set inventory`, `--set vehicles` or `--set carts` for the corresponding block, and `--set full` for all currently executable jobs. `--set sp`, `--set host` and individual `--jobs` selections remain available. Always inspect `--dry-run` first. Each separate launch has a `boundary` explaining its world, control, topology or timing requirement. Existing multi-stage scenarios stay inside their original lifecycle; this plan does not assert a cross-suite reset contract.

Workload and cart injury/speed jobs reserve exclusive runner admission, so other native runs cannot contaminate their timing captures. This preserves the shared desktop queue; it never changes the user's display or focus.

The plan's `campaign` blocks keep job IDs, a work reference in `todo` and unresolved `gates`. After a TODO is closed, point the reference to its scenario documentation so the runnable regression remains available. Dry runs and `batch-report.json` retain every block, including unselected jobs and checks still needing fixtures, inputs, installation decisions, manual visual/audio review, another platform or a real peer. The batch verdict describes the selected executions; `campaign.status` cannot pass until all mapped jobs pass and no acceptance gate remains. A partial selection or successful video capture cannot close the campaign. Update a gate only after its evidence is actually accepted. Seed/reload, queue-disabled controls, natural-time and injury baselines remain real separate lifecycles.

`batch --dry-run` shows each original job, the combined `sessions` selections and the number of planned session launches (`launches`, not JVM process count). Grouped jobs point to the first selected member's run directory. One complete report/log audit covers that run; `coverage.json` and the fixture receipts keep individual case outcomes. Each grouped job inherits the shared run verdict, so a cleanup/runtime failure cannot produce an accepted partial session. The fixture drains actions and requests, restores its baseline, removes only owned resources and waits for client/server cleanup acknowledgement before advancing. Uncertain effects quarantine the session. Other suites remain separate until their fixtures implement and qualify this contract; a `session` label alone cannot make them compatible.

For feature development, select only the relevant jobs or a named plan set:

```sh
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/craft-fresh --set craft
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/targeted-fresh --jobs wishlist,tags
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/craft-fresh --set craft --dry-run
```

`--dry-run` prints JSON with the selected jobs in execution order, their control/seed paths and effective scenarios, mods, options and resources. It uses the same selection as execution and creates no output directories, profiles or processes. Ordinary plans validate selections; campaign plans also check available game/JDK, source locks/overrides and world-template inputs. Future seed artifacts are validated once produced. Runtime readiness and automatic port assignment still belong to preparation/launch. Remove `--dry-run` to execute that selection. A campaign requires a passed, clean control/seed report before preparing a dependent job; failed or unreviewed dependencies remain blocked while independent jobs may continue.

Plans define `sets` as names mapped to job ID lists. Required `control_job` and `seed_job` dependencies are included automatically, in plan order. `--skip-jobs` disables jobs, but disabling a required dependency is an error before preparation. Unselected jobs are not prepared and their fixtures are not installed. [The pack plan example](plans/pack-regression.example.json) includes targeted sets and a separate `full` set; replace its local paths before use. The full set is explicit regression scope, not evidence that every loaded mod has behavioral coverage.

Jobs may override `options`, `mods`, `ports`, `language`, `kind`, `resources`, `resource_wait` and `timeout`; default deadline is 900 seconds. Within `options.mod_sources`, nonempty job maps override plan paths per Mod ID; other plan pins remain. An explicit job `"mod_sources": {}` clears all plan source overrides, for example for a vanilla control. Launch groups within a batch run sequentially; independent commands or batches may run concurrently through shared resource admission. A blocked/failed job remains visible while later independent jobs continue; interruption stops the batch. `batch-report.json` and `coverage.json` are updated after every job. Each launch group retains its full report and raw logs; grouped jobs reference that shared evidence. Reload copies owned save/DB state and pins the exact world-specific Wishlist storage slots from a verified, stopped seed. A sealed test helper restores their unchanged text under the new absolute world path before server readiness, with the same endpoint; the server receives bounded native `save`/`quit` before signal fallback. A pending seed log audit remains `needs-review` in reload results.

## Selected pack locks

Lock the actual selected pack once its local sources are available:

```sh
python3 tools/check_action_queue.py lock-pack /tmp/selected-pack.lock.json \
  --game "$PZ_GAME" --workshop /path/to/workshop/content/108600
```

Repeat `--mod-source` for explicit local sources. The lock records the INI settings, ordered Mod IDs, Workshop IDs, versions when supplied by the mod, every source file hash and the game build. Use `--pack-lock /tmp/selected-pack.lock.json` with `prepare`/`run`, or `options.pack_lock` in a plan; suite defaults then use the locked pack. Missing sources or changes block preparation and resume. MP runs apply the selected pack’s Map, PVP, DoLuaChecksum, SleepAllowed and SleepNeeded settings; checksums stay enabled. Public listing, UPnP and automatic Workshop downloads stay disabled in disposable local stands. After changing a mod, create a new lock explicitly and keep the previous lock for comparison.

For a modpack change, retain the baseline lock and reports, create a new candidate lock, and run the same selected set against it. Functional case assertions expose regressions in the candidate. A changed pack is not a matching queue-disabled control: use a separate native/toolkit pair inside each pack when that comparison is needed; cross-pack runtime messages remain reviewable rather than being silently accepted as baseline errors.

## Reusing saved worlds

Reuse a prepared world through a sealed copy:

```sh
python3 tools/check_action_queue.py save-world /tmp/completed-owned-run /tmp/prepared-world
python3 tools/check_action_queue.py run /tmp/targeted-world-copy \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --suite crafting-plans --cases ui \
  --pack-lock /tmp/selected-pack.lock.json --world-template /tmp/prepared-world
```

Export accepts only a completed disposable runner invocation with all owned processes stopped. It copies `Saves/` and `db/`, rejects symlinks and concurrent changes, and records the original suite/cases. Each new run receives its own copy, current selected fixtures and silent settings (`soundVolume`, `musicVolume`, `jumpScareVolume`, `vehicleEngineVolume` zero; VOIP off). The source template stays unchanged. Kind, client count, mod order, ports and game build must match. Omitted ports reuse the template endpoint; conflicting explicit ports are rejected. SP templates require the same suite because suites use different save names. MP templates require identical effective sandbox settings and Map/PVP/DoLuaChecksum/SleepAllowed/SleepNeeded values, checked after fixture staging. Selecting fewer cases within a compatible suite is supported. Batch jobs use the same `options.world_template` absolute path; put it on the compatible job rather than every SP/MP job in a mixed plan. A template preserves prior world state; each selected fixture must still prepare and clean its owned resources. It does not copy old fixture Lua, loader approvals, connection configuration or world-path-dependent external stores; Wishlist restart uses its separate `seed_run` protocol. A copied world does not turn a warm run into an independent cold control.

Menu-Host saved-world copies use the same `save-world` / `--world-template` mechanism on macOS. Keep `{"mp_host":true}` in the config for both runs; Host and independent GameServer templates are not interchangeable. The native child owns `client1/Saves/Multiplayer/<server-name>/` and `client1/db/<server-name>.db`. Export retains these paths and every selected client's `Saves/` and `db/` files, including native world/item identities and authentication rows; restore copies their sealed bytes into a new owned cache. It does not mirror authoritative saves into `server/Saves/`. The current common Host bootstrap keeps the server name `queue-smoke` and the original `client1`/`client2` fixture identities. `seed_run` and `startup_connection` overrides remain unsupported in Host.

Host cleanup first asks the owned launcher to send native `save` and `quit` to its original `CoopMaster.serverProcess`. The launcher must prove the same child PID and native parent relationship, wait for that child to exit successfully, and emit exactly one `HOST_SAVED_EXIT pid=... exit=0`. The runner records `host_save` and the child's exit code in `execution.json`, then stops the remaining owned process group and audits that no owned Host process survived. An absent acknowledgement, unsuccessful child exit, or surviving child fails cleanup. Export requires this successful save/quit evidence, stopped source PIDs, the original Host cache route and authentication database, and unchanged source/template seals. A forced stop cannot substitute for graceful save evidence.

## Compare and report

A comparable control uses the same game/source/mod bytes/cases/languages/settings and explicit ports (automatic transport endpoints are normalized); only queue mode changes. Health MP uses two actual clients with reversed doctor/patient roles. EN `remoteRemoved` explicitly skips treatment to keep the actual peer connected; RU performs the real disconnect. Toolkit-only controls skip with reasons in native mode.

Use `prepare` instead of `run` to inspect inputs before launch, then `resume /tmp/the-fresh-profile`. Use `report /tmp/the-run --control /tmp/the-control` to audit without launch. `matrix /tmp/the-run/report.json --output /tmp/coverage.json` displays actual actor evidence, including missing/skipped cells. Results describe their recorded source snapshot, not every future revision.

Matrix cells describe functional coverage; consult the same run's separate runtime/overall verdict before accepting a release. `not-migrated` means an older stand has not joined this runner, not that the corresponding product feature is absent. Prepared files in cache `Lua/` are pinned; new native-generated layout/options files there are outputs. Added/removed code under `mods/` or `classes/` is rejected. Timestamped DebugLog and console copies are normalized for mirror counting while their source locations remain in the report.

## Result and isolation

New preparations also seal the full file lists and hashes under the live game's `media/lua` and `media/scripts` trees in `game-inputs.json`. Added, removed or changed files invalidate preparation, launch and reports. This guard covers Lua, translations and script inputs; it does not seal every native library or asset directory. Older prepared runs without this seal require fresh preparation.

Each run keeps input/source/mod manifests, original settings and individual launch/console/DebugLogs. `execution.json` records owned processes and their exit codes. On macOS, unexpected process exits fail the run even after fixture completion; zero and the runner's TERM/KILL conventions (`-15`/`143`, `-9`/`137`) are accepted. `report.json`, `report.txt` and `coverage.json` combine scenario outcomes, receipts, source integrity and full log audit. Mirrored logs use maximum occurrence counts per role, not a sum.

Exit 0: checks passed and runtime is `clean` or `background-only`. Exit 1: runtime failures, failed/incomplete execution or changed inputs. Exit 2: review needed for unclassified/new errors or incompatible control. A matching native control never clears runtime failures or unknown errors; it only records reproduction. Functional, runtime and coverage statuses stay separate.

Every runtime issue retains its message, location, fingerprint and occurrence count, plus `fatal`, `unclassified` or `background` severity. The inspected B42.21 engine JAR and source-verified single-client EN MP animal `equipment-fixed`/`equipment-missing` profiles permit only exact startup fluid-name normalization, fence sound defaults, Piano icon fallback and property-name fallback. Caller/stack, tile/property identities, readiness boundaries and per-message counts are checked; different profiles/builds, late messages and extra occurrences do not receive an automatic background verdict. Font page failures, skipped mannequin zones and other room-ID errors remain visible and require review. The exact `Basements.mergeRoomsOntoMetaCell` diagnostic `duplicate RoomDef.metaID for room at 10707,9484,0` is accepted for the verified B42.21 engine by the [explicit project decision](../../docs/reference/JAVA_PATCHES.md#map-data-and-cross-cell-basement-rooms); its raw messages and counts stay visible. The user approved the guarded split-key experiment and its save dependency; its gameplay fixture must prove actual key separation rather than rely on this background exception. The exception still covers native controls and unsupported-source fallback. Other coordinates, builds, methods and attached exceptions retain ordinary auditing.

Independent commands can run concurrently; there is no runner-count limit. Each launch atomically reserves an estimated memory/CPU budget in the per-user temporary `pz-native-<uid>` registry. The default per game process is 2048 MiB maximum Java heap, 1024 MiB estimated native/graphics/encoder memory and 1 logical CPU. MP normally reserves three processes, including its server. Configure `--heap-mib`, `--native-mib` and `--cpu-per-instance` during preparation; the heap setting also controls the actual JVM `-Xmx`. Batch plans accept the corresponding `resources` object (`heap_mib`, `native_mib`, `cpu_per_instance`, `exclusive`) at plan/job level.

Admission samples current host memory and process CPU, leaves the larger of 1 GiB or 10% physical RAM for the host, and subtracts the unconsumed portion of existing reservations. Resident memory is not charged twice. Startup reserves exist before the first child starts. `--resource-wait SECONDS` on run/resume bounds waiting (default 300, 0 refuses immediately); batch plans use `resource_wait` at plan/job level. Sampling failures stop admission. These are estimates, not OS memory/CPU/GPU limits: `ps` CPU values are averages, and mods/graphics/encoders can exceed the native estimate. Size it for the tested workload. Running processes are not killed when unrelated host load changes.

Omitting `--ports` reserves a unique adjacent UDP pair before freezing an MP profile. Resume preserves it; explicit ports wait until available at launch. Prepared automatic endpoints remain reserved until their output is removed or their run stops. Wishlist reload preserves its stopped seed endpoint. Port probes and reservations coordinate cooperating runners; an unrelated program may still bind between the probe and the game's bind, which causes a startup failure rather than reassignment of frozen inputs.

The old `/tmp/pz-queue-native-launch.lock` is held shared for the entire lifecycle, excluding legacy runners that require it exclusively. Use `--exclusive` during preparation for physical mouse/keyboard automation or timing/performance comparisons; it requests exclusive desktop admission. An unrelated game in a different profile is accounted as host load. A game already using the requested cachedir blocks that profile. Keep the shared game installation unchanged; Java/native mods writing outside cachedir require their own isolation. Background clients use `pauseOnFocusLoss=false`. Client/server VOIP stays off and every launch passes `-novoip`.

Timeout/interruption stop only processes created by that invocation. A crashed runner's reservation remains while its cachedir still has live game processes, including a crash between Popen and PID reporting. Stale owner PIDs alone never release it. Reservations disappear after the remaining games stop; discovery never kills another run's processes. `execution.json` records the admitted budget and host capacity snapshot.

Current live fixtures call actual menu/drop callbacks with prepared wounds, supplies and reading progress. Physical mouse input, natural long-session state, WAN latency and all third-party combinations remain separate coverage.
