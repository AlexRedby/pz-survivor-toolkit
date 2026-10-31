# Opt-in native resolved-loot success fixture

This research fixture changes no shipped Toolkit/Java Patches source, installs
nothing globally and requires a fresh owned native-test profile. It reuses
`../loot_resolved/ResolvedCandidate.java` at build time. The control keeps the
native ItemPicker class unchanged. The candidate applies the reviewed two-loop
splice only on initial definition; the same RNG ownership audit is installed in
both modes. This is a semantic bank, not a timing/FPS measurement or production
loader.

## Build and stage

Use the external B42.21 game directory containing `projectzomboid.jar` and
`ZombieBuddy.jar`, JDK 25, a new output directory, and an owned authorizer cache:

```sh
python3 tests/chunk_integration/loot_resolved_runtime/build.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" --cache "$PZ_LOOT_AUTHORIZER" \
  --output "$PZ_LOOT_FIXTURE" --mode candidate --check
```

Build `--mode control` separately, with another fresh authorizer/output. The
cache must already have a regular nonempty `Lua/smoke-user.txt` ownership marker;
the root-level marker is also accepted for standalone builder/admission checks.
The builder creates only its own `loot-resolved-runtime.opt-in` random token after
successful compilation/checks. No native class bytes are distributed in either
fixture JAR. Sources/native hashes and check scope are recorded in the build
receipt. `--check` exercises real ZombieBuddy Instrumentation, initial definition,
missing token, already-loaded rejection and foreign-thread RNG rejection. A
constructor-built native ItemSpawner/cleanup check verifies detached nested item
identities, preserved full types and actual spawn-counter restoration. It does
not initialize a game or test successful loot.

The native runner stages the `PZLootResolvedRuntime` mod into its fresh profile,
copies that build's token into the verified owned game cache, and adds
`42/media/bootstrap/PZLootResolvedBootstrap.jar:toolkit.lootresolved.bootstrap`
to the **single** ZombieBuddy `patches_jar` parameter. Existing entries are joined
by `;`; repeated parameters overwrite each other. Explicit preload is mandatory.
The bootstrap reads the public native Agent `arguments["config_dir"]`, requires
the final directory name `zombie-buddy`, and derives the early owned cache from
its parent. It never relies on the game's not-yet-initialized default cache.
At invocation, the actual `ZomboidFileSystem` cache must resolve to that same
directory and contain its `Lua/smoke-user.txt` marker and matching token.

Native resources are pinned, and definition-time bytes observed by this
transformer must match the pinned originals. An already-defined ItemPicker,
ScriptManager, Item, SandboxOptions or Rand disables admission. The loader must
be the bootstrap's game classloader; no retransformation or second target
definition is supported. Candidate proof requires the synthetic resolved helper,
exact input hash, different output hash and one target definition. Control proof
requires equal input/output hashes. Later Java agents or unsynchronized script
mutation are not proven compatible by these guards.

## Native completion handshake

The shared Lua file only registers the test acceptance function and a forwarding
OnFillContainer handler. It never starts the bank automatically. After real SP
startup, or on the menu Host **server authority**, call:

```lua
local ok = lootResolvedRuntimeRun()
local status = lootResolvedRuntimeStatus()
```

The bank is synchronous, once per JVM and bounded. Status is `not-run`, `running`,
`complete` or `failed`. A multiplayer client cannot claim the authority pass.
The final log line is `[LOOT_RESOLVED_RUNTIME] FINISH status=complete|failed`.
Only an explicit `complete` plus all receipt checks qualifies the bank.

The cache contains:

- `loot-resolved-runtime-activation-PID.txt`: per-process initial-load proof;
- `loot-resolved-runtime-status.txt`: authority PID, mode, terminal status, eight
  completed cases and uncovered gates;
- `loot-resolved-runtime.tsv`: ordered cases, callback traces, item/container
  snapshots, following native RNG draws and cleanup receipts.

Menu Host client and child may share a cache; activation files are PID-specific.
The bank receipt is written only by the explicitly invoked authority and binds
to its activation PID. A missing bridge, activation failure, missing terminal
receipt or callback exception cannot be treated as success.

## Cases and interpretation

Eight cases call real public ItemPicker methods, reaching both native successful
inner loops with the fully initialized game registry, factory, entity machinery,
Kahlua, stash/world systems and active mod callbacks:

1. Direct rolls with real registered Nails, Bandage, Apple and WaterBottle scripts.
2. A real factory-created Schoolbag and native bag rolls with Nails, Bandage, Pen.
3. Actual Lua acceptance mutates the next picker name; the next item must change.
4. Actual Lua acceptance adds the live Pen memento tag and changes the sandbox
   removal list; native lookup/classification/removal is observed on the next item.
5. Native nested Schoolbag fill, actual OnFillContainer delivery and a reentrant
   successful direct roll inside that Lua callback.
6. Denied container: factory/acceptance occur once, no insertion and no next item.
7. Full container: admission rejects before factory/acceptance.
8. An intentionally failing actual Lua acceptance callback: its tagged native
   protected-call error is logged, no insertion and no next item.

The final case must produce `LOOT_RESOLVED_EXPECTED_ACCEPT_ERROR` in the full
runtime log. Audit that expected error separately from unrelated new exceptions;
native protected calls can swallow errors. Fixture Java failures make the bank
fail even if Lua swallows them. Full logs remain required evidence.

Every observed created/snapshotted item must report native `isInitialised=true`.
Ordered snapshots retain native subtype/full type, random item ID, condition,
age/current-use float bits, food heat/frozen state, fluid capacity and individual
fluid amounts, explored flags and nested contents. No stash/world/factory stub
is substituted. Candidate/control item order and callback order must match
exactly, including a following Rand draw for each case.

Each case uses the native CellularAutomatonRNG with an explicit seed. The original
native RNG object/id are saved and restored after cleanup. Any other thread
entering native `Rand` during the bank rejects the result. This checks native
Rand ownership, not arbitrary Lua/third-party RNGs. Generated items stay in
detached test containers; cleanup detaches every child before recursively resetting
a bag, removes only generated identities from both native IsoCell processing
queues, unregisters their native entity
identity when registered, releases components, checks that their identity is no
longer registered, and checks actual per-type spawn-counter deltas before
reversing the fixture's inserted-item spawn counters. Acceptance alone is not
accepted as proof that the native counter increment happened; an unexpected
delta fails cleanup before any counter is reversed.
These are historical InstanceTracker counters, not an item-identity registry.
The live tags/removal option are restored. Arbitrary third-party callback side
effects are subject to the disposable-profile boundary and full log audit.

Run control/candidate from equivalent separate fresh saves/settings, with the
same complete selected mod set, once in SP and once under menu Host authority.
Use the normal owned runner/AeroSpace policy. Do not repurpose a user's save or
install either fixture into their game. Compare each environment separately:

```sh
python3 tests/chunk_integration/loot_resolved_runtime/compare.py \
  --control-cache "$PZ_LOOT_CONTROL_CACHE" \
  --candidate-cache "$PZ_LOOT_CANDIDATE_CACHE" \
  --output "$PZ_LOOT_COMPARISON_JSON"
```

The comparator requires PID-bound activation, complete ordered eight-case
receipts and exact row equality. It writes differences before failing. Compare
the build/native/mod/config receipts and audit logs as well; matching fixture
rows alone do not establish the complete full-pack game state.

Non-null source-square regional multiplier, actual live script reload and module
item replacement remain explicit uncovered gates. No claim of successful native
execution follows from this fixture's existence or headless check. No runtime
adoption, gameplay settings change or end-to-end stutter claim follows from a
successful bank.
