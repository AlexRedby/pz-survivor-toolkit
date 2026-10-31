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
missing token, already-loaded rejection and concurrent RNG isolation. Native
private/global oracle streams check owner and foreign sequences independently,
including shared state/ID continuation and exception cleanup. Owner bypass,
unseeded float NextBool, escaped private receiver and foreign scope takeover
attempts are rejected. These checks do not serialize or pause real game threads. A
constructor-built native ItemSpawner/cleanup check verifies detached nested item
identities, preserved full types and actual spawn-counter restoration. It does
not initialize a game or test successful loot.

For the current reviewed optimizer classpath, add
`--optimizer-archive "$PZ_OPTIMIZER_ARCHIVE"`. The builder validates the exact
archive digest/size and all 888 selected resource digests against the current
`tests/optimizer_trial/candidate-manifest.json`, plus its native guards/absences.
The reviewed differing overlaps with this fixture's 72-class closure are
`zombie/Lua/LuaEventManager.class` and `zombie/iso/IsoGridSquare.class`. The latter
retains the reviewed Region-zone lookup and literal `General` fallback used by
the source-square cases. Any additional differing overlap rejects the build. The receipt retains unchanged `native_hashes`, effective `runtime_hashes`,
the current `optimizer_manifest_sha256`, archive hash and complete declared
profile. Native builds use null optimizer receipt fields. Optimizer headless
checks use that exact overlay and test the profile after the early preload,
including missing, wrong and extra profile-property rejection.

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

An optimizer-built artifact selects `optimized-client` resources by default.
The native menu Host child can select `native-host` only when the first actual
`sun.java.command` token is exactly `zombie.network.GameServer` and the owned
cache has a regular `loot-resolved-runtime.host-authority` marker containing
this build's token. The runner creates that marker exclusively for menu Host;
SP has no Host marker. This is one exact selected resource set, not dual-hash
fallback. A native build selects `native` resources.

Immediately before the bank, `optimized-client` requires non-server context and
all current optimizer profile/pin values, with no unreviewed `pzopt.*` property.
`native-host` requires actual `GameServer.server && !GameClient.client` and no
optimizer profile/pins. Native builds likewise require absent optimizer pins.
These checks occur after launcher profile setup, never during premain. Activation
and bank status record `resource_profile`, `optimizer_manifest_sha256` (`none`
for native builds), and `runtime_profile_checked`. Early activation has checked
false; the bank requires true. Pure selector headless checks test foreign/missing
tokens, main names, caches and symlinks; they do not qualify a real Host child.

Native resources are pinned, and definition-time bytes observed by this
transformer must match the exact selected native/optimizer role set. ItemPicker
itself must always match its separately retained native hash. An already-defined ItemPicker,
ScriptManager, Item, SandboxOptions or any of the four guarded Rand classes
disables admission. The loader must
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

The default `--bank base` bank is synchronous, once per JVM and bounded.
`lootResolvedRuntimeBank()` returns the embedded bank. Additional banks require
an explicit matching artifact and native selection, as described below. Status is `not-run`, `running`,
`complete` or `failed`. A multiplayer client cannot claim the authority pass.
The final log line is `[LOOT_RESOLVED_RUNTIME] FINISH status=complete|failed`.
Only an explicit `complete` plus all receipt checks qualifies the bank.

The cache contains:

- `loot-resolved-runtime-activation-PID.txt`: per-process initial-load proof;
- `loot-resolved-runtime-status.txt`: authority PID, mode, terminal status, eight
  completed cases, selected bank and coverage gates;
- `loot-resolved-runtime.tsv`: ordered cases, callback traces, item/container
  snapshots, following native RNG draws and cleanup receipts.
- `loot-resolved-runtime-rng-PID.txt`: owner-only native RNG scope proof,
  persistent bypass/rejection diagnostics and observed foreign thread/caller.

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

The direct Apple case retains its raw age and adds one bound `CLOCK` row per
Apple. It requires an actual detached non-fridge/non-freezer outer container,
unchanged raw world days/hours throughout that synchronous direct roll, and
stable TimeSinceApo/foodRotSpeed. The observed native rot factor and exact
`float32(float32(daysSinceBegin) * factor)` must match actual age bits. The native
GameTime class is pinned. No clock is set, stopped or rounded, and no tolerance
or refrigerated-food equivalence is inferred. The comparator may canonicalize
only this one verified direct Apple age after validating its complete oracle;
all raw evidence remains retained.

The RNG scope is explicitly versioned as
`owner-thread-private-native-randstandard-v1`. Each case seeds a privately
constructed **native RandStandard** with a native CellularAutomatonRNG and native
id=0. Exact initial-definition splices replace only the nine
`RandStandard.INSTANCE` receiver selections in the eleven native Rand wrappers.
During the bank, only its owner thread dispatches to the private instance. Every
other thread, and every call outside the bank, continues with the original native
singleton. The bank never reads/saves/reseeds/restores its shared RNG state or id,
and never blocks another thread to obtain a seeded window.

Pinned RandAbstract public/protected receiver guards reject owner calls on any
other RandAbstract receiver, including direct singleton/RandLua access. Native
private-instance delegation is preserved. RandStandard.init on the owner is
unsupported. RandInterface.NextBool(float) uses ThreadLocalRandom rather than the
native CA field, so owner use explicitly fails before that draw. A private
receiver escaped to another thread also fails. Each rejection poisons the bank
persistently even if native protected Lua calls swallow its exception. Owner
exit clears routing in finally; nothing restores or rewinds global RNG state.

Legitimate foreign global calls are accepted. Their counters and first caller
are nonblocking entry snapshots attached to the captured scope object; boundary
races can make counts lower bounds. Zero is never proof that no foreign call
occurred. Calls already in flight can finish recording after owner exit without
altering a subsequent scope. The RNG receipt records this scope, zero shared
singleton writes and zero accepted bypasses, not universal third-party RNG
determinism. The earlier shared-singleton strategy failed a real Host guard and
its failed result remains separate evidence; it cannot qualify this new scope.

Generated items stay in
detached test containers; cleanup detaches every child before recursively resetting
a bag, removes only generated identities from both native IsoCell processing
queues, unregisters their native entity
identity when registered, releases components, checks that their identity is no
longer registered, and checks actual per-type spawn-counter deltas before
reversing the fixture's inserted-item spawn counters. Acceptance alone is not
accepted as proof that the native counter increment happened; an unexpected
delta fails cleanup before any counter is reversed.
These are historical InstanceTracker counters, not an item-identity registry.
For banks running the base eight cases, the live tags/removal option are restored.
The terminal reload bank does not capture or write those pre-reload Item fields. Arbitrary third-party callback side
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

The comparator requires PID-bound activation, matching embedded/status bank,
complete ordered case receipts and exact row equality. It validates finite
chance/output bindings, callback replacement/finally order and terminal reload
input/API/output/disk-restore order before accepting the additional banks. It writes differences before failing. Compare
the build/native/mod/config receipts and audit logs as well; matching fixture
rows alone do not establish the complete full-pack game state.

## Additional explicitly selected banks

Build a separate artifact with `--bank semantics` or `--bank reload`. Select the
matching single native suite case (`semantics` or `reload`, rather than default
`bank`). The builder embeds the selected bank in both receipts and bootstrap;
the adapter rejects a different selection. Only these two artifacts stage
`42/media/scripts/loot-runtime-probes.txt` before native game initialization.
The adapter seals its exact bytes and rejects missing, changed or extra scripts.
Base artifacts stage no scripts. A terminal run must restore these exact disk
bytes to satisfy the ordinary final provenance seal; no file is exempted.

The two new banks declare initial **owned-test-only** sandbox inputs
`RollsMultiplier=1`, `MementoLootNew=0`, `MedicalLootNew=1.0`, in addition to the
existing fresh world/clock inputs. They do not edit the user's settings, change
the world clock or alter any shipped mod. Java checks these native options and
requires actual finite old/new chance observations. They call
`lootResolvedRuntimeRunFor(actualOwnedPlayer)` on the SP/server main tick; the
menu Host client still never runs the authoritative bank.

`semantics` runs twelve cases: the original eight plus:

- `finite-source-direct` and `finite-source-bag` use the actual owned actor's
  loaded square, verified against `IsoCell.getGridSquare`. Each runs four seeded
  finite trials: null-source hit/miss and actual-source hit/miss. Native unit
  chance determines picker chances just above/below the same native draw. Both
  exact native chance and observed initialized contents, following RNG draw,
  source identity, region and multiplier bits are recorded. The actual factory
  bag is in a detached root with that source; its roll inventory has the same
  real source. Coordinates stay in the owned cache's `loot-source-PID-path.txt`.
- `callback-module-replacement-direct` and `callback-module-replacement-bag`
  replace only the test probe's Base module and fulltype-map entries during the
  first actual Nails acceptance callback. The next qualified and unqualified
  names must resolve to the distinct preloaded Alternate Item. With finite
  picker chance 20000, the old Memento script has native chance zero and the new
  FirstAid script must have finite native chance at least 10000. Thus every
  native draw in `[0,10000)` changes guaranteed miss to hit, independently of
  factory re-resolution. Both created items must actually use the Alternate
  script/fulltype. Exact prior entries are checked and restored in finally,
  including when native protected Lua swallows a callback exception.

These source cases qualify **finite nonnull source plumbing**, not differential
regional influence. Exact B42.21 `IsoGridSquare.getSquareRegion()` returns a
named Region or literal `General`; it does not return null for an ordinary
square without a Region. Sandbox's ruralLooted branch specifically requires
null. The bank requires positive equal actual null/source factors and records
`regional_multiplier=uncovered-no-differential`; it neither fabricates a null
Region nor edits zones/scans for an outcome. A named equal-factor Region remains
recorded as that actual name. The general differential regional gate is retained
as uncovered; this is not a claim that every reachable profile has equal factors.

`reload` runs **one terminal disposable case**, without running the base eight.
It binds the already preloaded probe's native `getFileAbsPath()` and active
filesystem-resolved filename to the exact owned cache script, requires regular
non-symlink parents and exact original bytes, and bounds the native reload input
list (1..4096 files, each at most 8 MiB, total at most 128 MiB). It records the
aggregate ordered content digest before touching any file. Direct/bag pre-rolls
with both name spellings prove finite zero-chance misses and current script
fields; they do not claim pre-reload factory creation. It changes only the unique
probe category/weight anchor from Memento/0.05 to FirstAid/0.125, verifies the
written SHA, and calls actual `ScriptManager.ReloadScripts(ScriptType.Item)`.

Post-reload the native registry must reuse the same Item identity, resolve both
spellings to it, retain the exact owned source, have no native script load error,
and expose the changed category/weight. Direct/bag finite rolls then must each
create two actual initialized items with that script and weight. All generated
items are disposed between phases. Finally, independent of reload success, the
owned path/parents are checked again and exact original disk bytes restored and
verified. The native **runtime registry stays reload-changed**: no runtime
rollback is attempted or claimed, and no later fixture case is permitted. Native
reload processes the selected Item type across the real full input list, so the
whole profile/world is disposable and full logs remain required.

All non-full test containers use capacity 100; snapshots retain count, effective
capacity and finite weight within that capacity. The deliberate full case keeps
capacity zero. These are detached fixture capacities, not gameplay changes.

The new banks still need real full-pack SP/menu Host control/candidate runs. A
build/headless pass proves admission, native RNG isolation and parser/cleanup
contracts only; it does not execute these initialized-game cases. No runtime
adoption, gameplay settings change or end-to-end stutter claim follows from a
successful bank.

The terminal reload field proof checks the stored native `actualWeight` separately
from the public getter. For the pinned normal ComboItem, native
`getActualWeightUnmodded()` returns zero when its actual display name equals its
full type (an untranslated probe), otherwise `max(actualWeight, 0)`. Each
`RELOAD_ITEM` row binds both values, this name predicate, script identity and
initialization to an exact roll path/index/item ID. The stored field must contain
the reloaded script weight; a zero public weight never substitutes for that proof.
The constructor-only headless check covers both name branches without claiming
factory or initialized-world coverage.
