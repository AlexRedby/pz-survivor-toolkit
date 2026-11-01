# Disposable on-demand world loot experiment

This opt-in research fixture leaves shipped Toolkit, Java Patches and the Windows
package unchanged. It defers initial native `bin`/`dumpster` loading, retaining
`explored=false`, and reuses ordinary authority-side fill on access. The exact
native method guards reject unsupported code; partially installed hooks remain
inactive. No blanket `getItems()` interception or background fill queue is added.

`loot-demand` uses the shared runner's isolated SP or menu Host, one
client, current selected pack and normal desktop policy. Supply explicit local
sources and `loot_demand_experiment=true`, `preload_toolkit_fonts=true`, and (for
Host) `mp_host=true`. The runner must use `--exclusive`. An optional pinned
`optimizer_archive` uses the existing selective overlay stager. Never copy this
fixture into an ordinary game profile. The generated mod requires its matching
per-run token and ownership marker.

Select `--cases lifecycle` for the lifecycle bank. It uses synthetic world objects with real bin sprites,
actual loader/access methods, a fixture-only OnFillContainer sentinel, repeat and
reentrant calls, native ItemContainer serialization, and destruction spilling.
It checks that every generated item ID reaches the ground. The selected
FurniturePushPull sources are fingerprinted; their two authority movement
entrypoints ensure every member container before capturing contents. Run its
source-backed Lua checks with `furniture_checks.py --furniture-root PATH` using a
Python environment containing Lupa.

These are functional checks, not a driving benchmark. The lifecycle bank
serializes containers in memory; that alone is not a world restart. The Host phase creates a separate
source outside the nearby inventory scan, sends two native RequestItemsForContainer
requests and compares recursive item IDs/types/count/tree against authority.
Custom commands set up and verify the exchange; they do not transport contents.
This is one client, not a two-client race or condition/modData equality proof.
Source-backed furniture tests use engine/network/geometry doubles; actual full-pack furniture moves remain a separate gate. The fixture
must not be promoted before those gates and representative driving/first-access
cost are qualified.

Tradeoffs: delayed random outcome/callback and fill overlay, possible first-access
hitch, and unrealized pending fire fuel. Existing/placed/moved/special objects are
excluded from initial deferral; direct consumers still require review. The native
spill loop increments its index after removal and skips items; the prototype
corrects that loop only for authority-owned target containers so newly generated
contents are not stranded during destruction. Unrelated containers retain the
native path.

The `object/emptyTrash` command is intercepted before Event listeners, including
queued replay. An unopened target is marked explored without generating loot;
ordinary deletion still removes real items. Thus intentionally emptied potential
loot cannot appear later. A command during active fill is refused before any
listener can clear partially materialized contents. This is a deliberate behavior
choice for the experiment.

For a real JVM activation check without launching a world, run
`activation_check.py --game "$PZ_GAME" --jdk "$JAVA_HOME" --output NEW_DIRECTORY`.
It uses actual Instrumentation and `-Xverify:all`, dynamically appends/registers
the fixture JAR like Buddy, invokes the real Main without preloading helpers,
and retains exact sources/input receipts. It does not invoke game
methods, execute Lua callbacks or replace a full-pack native scenario.

The exact fill-method admission currently excludes additional stage/loot profiler
advice inside that method. Measure with a minimal unchanged frame collector, or
explicitly verify a composed transform before adding richer instrumentation; do
not weaken the guards merely to admit an unknown combination.

## Saved-world continuation

`--cases persist-seed` combines the lifecycle bank, pending/completed world objects
outside nearby inventory scanning, nested sentinel items and (in Host) the native
request exchange. It leaves its objects and global ModData record in the disposable
world. SP calls `save(true)`; the shared runner owns Host save/quit. After the run
has stopped, export with `check_action_queue.py save-world RUN TEMPLATE`, then use
`--cases persist-reload --world-template TEMPLATE` with the same pack/kind.

Reload checks authoritative pending state, completed recursive IDs/types/nesting,
unique IDs/counts, sentinel objects, no repeat fill and one first demand. The seed
stores both original rows and an actual native ItemContainer save/load reference;
reload compares exact rows to that reference. The native roundtrip must preserve
ID/nesting shape, container state and the original source rows. This is not a
blanket exception for changed types. Legacy seeds without that reference are
rejected. Native `Moveable.load` changes `Base.Mov_PalletEmpty` to
`Base.construction_01_5`; a separate real-item serialization control checks that
normalization with the same ID/world sprite, independently of loot generation.

The reference does not cover all item condition, age, uses, fluids or modData.
Reload observes server contents; its separate seed request exchange is still one
client, not concurrent clients. Grid-event diagnostics run after possible earlier
listeners and do not represent raw bytes before deserialization.

## Qualification state

On macOS, the preceding research source passed actual full-selected-pack menu
Host activation, lifecycle, repeated one-client native request/replication and a
sealed saved-world continuation, with clean runtime/source/viewport checks. Two
historical raw-type checksum failures were explained by native pallet type
normalization: changing that one type reconstructs the entire original eleven-item
SHA, with IDs/nesting unchanged. The final Host reload and independent native
pallet control passed. Failed original reports remain failed; they are retained
with the causal explanation.

SP lifecycle assertions passed, but the run failed the optimizer telemetry's
world-name guard. Clean SP, native furniture moves, multiplayer contention, broader
item state and representative driving/first-access performance remain open. The
subsequent main rebase includes newer inventory/Java code; earlier game results do
not qualify those combined bytes. This fixture is still test-only and is not a
Windows package improvement or a proven FPS gain.

The actual dynamic-JAR activation checker also preserves regressions for helper
self-loading recursion and Buddy registered-JAR discovery. Startup-classpath tests
alone missed those defects; adding ZIP directory entries alone did not fix them.
