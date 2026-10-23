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

By default, macOS runs use `desktop_mode=auto`: the runner first uses a valid AeroSpace CLI to place each owned client window on `PZ-TEST`. To choose another workspace, set `"test_workspace":"NAME"` in the JSON config. Explicit `current` uses the same AeroSpace-first policy and the same sleep-only fallback; it cannot bypass placement on an awake desktop. `aerospace` requires successful placement without fallback. You may already be on the target workspace at launch, visit it during a run and focus test windows; observation does not stop automated checks. The runner never switches your workspace or focuses a test window. It identifies windows by the PID it launched, sets them floating and moves them before allowing the initially transparent game window to appear. Only the disposable profile contains the window agent; game files and AeroSpace configuration stay unchanged. Missing/malformed AeroSpace, CLI failures, foreign or malformed window identities, invalid PID/GLFW handshakes and dead clients remain errors. Routing failures, windows disappearing after discovery, and escaped/replaced windows after placement also stop the run. Manual fixtures use the same placement rules; their separate completion policy waits for user exit. Other macOS game bytecode is rejected before window creation until its window lifecycle has been reviewed.

Current-desktop fallback is admitted only after 30 seconds without discovering any window for that client, with a live owned PID, its matching nonzero GLFW handshake and a fresh CoreGraphics observation that every online display is asleep. [CGGetOnlineDisplayList](https://developer.apple.com/documentation/coregraphics/cggetonlinedisplaylist%28_%3A_%3A_%3A%29) includes sleeping and mirrored displays; [CGDisplayIsAsleep](https://developer.apple.com/documentation/coregraphics/cgdisplayisasleep%28_%3A%29) supplies each display's sleep state. An empty, failed or invalid enumeration, including inconsistent online counts, is `unknown` and cannot admit fallback. Screen lock and an empty AeroSpace window list are not evidence of sleep. The probe runs independently at each eligible client's discovery deadline; one fallback does not disable AeroSpace routing or identity checks for other clients. Do not change the user's display state, workspace or focus to enable testing. The runner's `caffeinate -i` assertion prevents system idle sleep without waking a display or preventing its sleep. The prepared test agent and a fresh routing acknowledgement remain required; focus/fullscreen suppression stays active in both modes. Reports retain requested and actual mode, per-client modes, window/GLFW identities, the fallback reason and per-PID `display_probes`. A current-desktop fallback provides no workspace placement guarantee or physical-input coverage. The same options work as `options.desktop_mode` in a batch plan/job.

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

For feature development, select only the relevant jobs or a named plan set:

```sh
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/craft-fresh --set craft
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/targeted-fresh --jobs wishlist,tags
python3 tools/check_action_queue.py batch /path/to/plan.json /tmp/craft-fresh --set craft --dry-run
```

`--dry-run` prints JSON with the selected jobs in execution order, their control/seed paths and effective scenarios, mods, options and resources. It uses the same selection as execution and creates no output directories, profiles or processes. It validates the selection, not installed sources or runtime readiness; automatic ports are assigned during preparation. Remove `--dry-run` to execute that selection.

Plans define `sets` as names mapped to job ID lists. Required `control_job` and `seed_job` dependencies are included automatically, in plan order. `--skip-jobs` disables jobs, but disabling a required dependency is an error before preparation. Unselected jobs are not prepared and their fixtures are not installed. [The pack plan example](plans/pack-regression.example.json) includes targeted sets and a separate `full` set; replace its local paths before use. The full set is explicit regression scope, not evidence that every loaded mod has behavioral coverage.

Jobs may override `options`, `mods`, `ports`, `language`, `kind`, `resources`, `resource_wait` and `timeout`; default deadline is 900 seconds. Within `options.mod_sources`, nonempty job maps override plan paths per Mod ID; other plan pins remain. An explicit job `"mod_sources": {}` clears all plan source overrides, for example for a vanilla control. Jobs within a batch run sequentially; independent commands or batches may run concurrently through shared resource admission. A blocked/failed job remains visible while later independent jobs continue; interruption stops the batch. `batch-report.json` and `coverage.json` are updated after every job. Each job retains its full report and raw logs. Reload copies owned save/DB state and pins the exact world-specific Wishlist storage slots from a verified, stopped seed. A sealed test helper restores their unchanged text under the new absolute world path before server readiness, with the same endpoint; the server receives bounded native `save`/`quit` before signal fallback. A pending seed log audit remains `needs-review` in reload results.

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
