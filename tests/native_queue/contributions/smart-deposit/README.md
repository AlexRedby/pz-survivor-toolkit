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
pane/page `canPutIn` and `draggedItems:update`. It requires exactly three
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

The installed `transferItemsByWeight` must enqueue exactly three real
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
cover physical mouse/controller dispatch, Host, Windows, other game builds,
corpse-only mode, every container permission or pixel-level screenshot quality.
Queue-disabled `--mode native` changes the queue setting only; it does not
remove the owned Smart Deposit implementation or constitute a pre-fix control.
Store generated profiles, saves, screenshots and logs outside Git.
