# Smart Deposit partial acceptance native fixture

The shared `smart-deposit/partial` suite stages this EN/SP B42.21 helper in a
fresh disposable profile. It does not install into the user's game. Use the full
selected pack and its locked local sources:

```sh
python3 tools/check_action_queue.py run /tmp/smart-deposit-selected-fresh \
  --suite smart-deposit --cases partial --kind sp --mode toolkit \
  --language EN --mods selected --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --workshop "$PZ_WORKSHOP" --config /path/to/selected-config.json
```

Use the runner's prepared selected-pack lock and ordinary local Java artifact
requirements. `manifest.json` records mandatory UI mods, exclusions and helper
identity. The helper must load last. The default window is 1280x900; the normal
runner's workspace, source/mod snapshot guards, log audit, VOIP-off validation,
resource admission and ownership-safe process teardown apply. Do not launch a
second owner over an existing user game. The fixture quits its owned test client
after completion or failure; the runner retains its timeout and cleanup duties.

To inspect staging without launching:

```sh
python3 tests/native_queue/contributions/smart-deposit/prepare.py \
  --toolkit-source PZSurvivorToolkit --output /tmp/smart-deposit-helper/SmartDepositNative
python3 tests/native_queue/contributions/smart-deposit/test_fixture.py
```

The fixture finds a clear loaded 3x3 outdoor area in its disposable save and
creates three real native world crates. It obtains the real Better Containers
proximity target and button from the native loot page. The actual BC button
order defines an early fallback crate, a later category crate with Screws and a
last full-type crate with Nails. Native Apples fill each crate so it has room
for one Nail but cannot admit two; native `hasRoomFor` proves that precondition.
The fixture rejects unexpected nearby storage instead of hiding it or replacing
BC's collection helper. All items, containers and renderers remain native.

Four native Nails from the player's root inventory exercise each CleanUI mode.
The fixture supplies native drag state programmatically, then calls installed
pane/page `canPutIn` and `draggedItems:update`. Repeated native hover updates must
reuse the advisory plan until its 200 ms expiry; the real container-button drop
resets and recomputes feedback before selecting its transfer batch. It requires exactly three
accepted item identities and one `itemNotOK` overflow. The public planner adds
exact routing checks: full type before category before fallback, independently
of the earlier container order. All four groups are expanded, with the physical
child rows selected through native `restoreSelection`. Each screenshot retains
the actual native feedback for manual inspection: overflow must be red, accepted
items must remain allowed. A rejected physical item can appear as both its group
header and expanded child, so the fixture does not equate row draw count with
the number of rejected item identities.
The programmatic drag initializes the same pane-local `draggingX`/`draggingY`
fields as native `onMouseDown` and holds their offset at zero during capture,
keeping native dragged rows within the visible source pane.

The installed container-button drop and `transferItemsByWeight` must enqueue exactly three real
`ISInventoryTransferAction` instances with the expected item identities and
source/destination endpoints. The duration control uses the same native
`ISInventoryTransferUtil` factory as upstream BC. Each queued item's raw time
must equal that factory baseline. The first action begins immediately and
native `ISBaseTimedAction:create` applies `adjustMaxTime` for moodles, wounds and
body temperature; its observed time must equal that adjusted baseline, while
waiting actions retain raw time. The fixture requires a stationary player and
logs factory, expected, observed and queue times for every action. Queue drain
alone cannot pass: exact native item IDs must occur
once at their expected destinations, the overflow must remain in its original
source, seeds/fillers must stay and capacities must hold. A subsequent batch of
four source Nails checks fully occupied storage through the same UI entry
points: all per-item rejections, both `canPutIn` results false and no queued
actions or changed source. The other UI mode repeats with fresh owned items.

Require `[SMART_DEPOSIT] COMPLETE`, every verifier receipt exactly once, two PNG
screenshots and a successful common full-log audit. These are programmatic UI
callbacks in English single-player on the platform actually run. They do not
cover physical mouse/controller dispatch, Windows, other game builds,
corpse-only mode, every container permission or pixel-level screenshot quality.
Queue-disabled `--mode native` changes the queue setting only; it does not
remove the owned Smart Deposit implementation or constitute a pre-fix control.
Store generated profiles, saves, screenshots and logs outside Git.

## One-client menu Host

Use the same suite/case with `--kind mp`, a fresh complete `--pack-lock`, and
`{"mp_host":true}` in the explicit config. The common startup helper launches the
owned native CoopServer. The SP fixture remains an independent control; Host
stages `ZZSmartDepositHost.lua`, `QueueSmartDepositHostFixture.lua` and
`ZZSmartDepositHostServer.lua` instead.

The Host server creates and replicates the three crates and all samples, stock
and fillers. The client supplies only the observed order of those owned crates
and the native sorted sample IDs. Both roles independently record every owned
ID and endpoint, crate contents/weights/capacities and the preserved original
root inventory. Each UI mode requires three real native transactions, one
retained overflow, then four fully rejected items and no queued action. Native
Host transfer constructors begin at `-1`; the fixture passively observes native
transaction duration and delegated callbacks without changing action times.
A light item may complete between frames, so rendered progress alone is not the
timing authority.

`host_verify.py` requires ordered, role/session/phase-bound JSON receipts from
both logs, exact endpoints and conservation, unmodified stock and fillers,
per-item drag feedback, native transaction timing, both screenshots, per-phase
item removal and final owned-crate removal. Native Host packets deserialize
replacement client item objects: transferred-item proof uses stable native IDs,
unique endpoints and unchanged type/name/weight rather than Java object references.
Untouched original inventory and equipment retain their identity checks. The client restores its original
fractional position, native square, equipment, UI and changed options. Cleanup
is limited to owned IDs and token-bearing objects. A partial cleanup or missing
server receipt cannot pass. Run `tests.test_queue_smart_deposit_host` and
`test_smart_deposit_host_fixture` for the offline receipt/ownership regressions.
Position transitions wait for stationary coordinates and zero native deferred
animation movement before a single placement; queue drain alone does not mean
the transfer animation has stopped moving the character.

Host coverage is one actual client through installed Lua drag/drop callbacks;
physical mouse dispatch, contention and a separate remote client remain outside
this scenario. Inspect both screenshots as well as the common runtime audit.

Before launching a changed fixture, compile it with the installed game's Kahlua
compiler as well as running the focused behavioral checks. Standard Lua accepts
some closures that exceed Kahlua's 60-upvalue limit. This check only compiles; it
does not execute Lua or initialize a game:

```sh
check_classes="$(mktemp -d)"
javac_source=tests/native_queue/contributions/smart-deposit/java/KahluaCompileCheck.java
"$PZ_JDK/bin/javac" -cp "$PZ_GAME/projectzomboid.jar" -d "$check_classes" "$javac_source"
"$PZ_JDK/bin/java" -cp "$check_classes:$PZ_GAME/projectzomboid.jar" KahluaCompileCheck \
  tests/native_queue/contributions/smart-deposit/ZZSmartDepositHost.lua \
  tests/native_queue/contributions/smart-deposit/QueueSmartDepositHostFixture.lua \
  tests/native_queue/contributions/smart-deposit/ZZSmartDepositHostServer.lua \
  tests/native_queue/contributions/smart-deposit/ZZSmartDepositNative.lua
```
