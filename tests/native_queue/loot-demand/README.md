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

The lifecycle bank serializes containers in memory. The separate persistence
cases below save and reload the world. In the one-client Host lifecycle case,
the server creates an object outside the nearby inventory scan. The client
sends two native requests and compares its recursive inventory with the
authority. Coordination messages carry observations only.

Select `--cases furniture` to exercise the actual selected push/pull actions on
a two-part orange dumpster in SP or menu Host. Each part starts pending. The
case covers a controlled empty fill, an item already owned by each part, and a
populated fill. It checks the original item references at the destination and
after the return trip. On SP, the push commits on a later tick after the shove
animation. On Host, a native client checks both final trees and overlay states.
The fixture invokes the task's completion method on authority. It does not
exercise the player context menu or require a positive overlay on these sprites.

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

## First access from two Host players

Use suite `loot-demand-peers`, case `same-bin`, with two local clients, the
ordered pack from `SurvivorQoL-selected.ini` and the Host opt-ins above.
Both clients must see one pending world bin before a common release and send
native item requests before either observes its contents. The authority must
fill once. The original root sentinel, bag and child must appear under the
same parents with the same IDs on both clients. The comparison covers first
delivery. It does not exercise simultaneous pickups.

On macOS with 42.22.2, the clients sent their requests 4 ms apart and all three recursive item trees matched. The overall run remained
`needs-review` because the guest logged a native player lookup error during
connection, before the fixture created its bin.

## Natural map containers on Build 42.22.2

For a menu Host choose the `natural` case and set `loot_demand_arm` to
`observe` or `defer` in the runner config. Use the same ordered full pack
and world-generation seed. The server selects a loaded map bin outside the
initial inventory radius. Pin the same object in the second run with
`loot_demand_target` containing `x`, `y`, `z` and `index`. The client walks
to it using the ordinary timed action and opens the nearby inventory. The
server records the native fill and the client checks the observed item tree.
An empty native inventory cannot confirm arrival of a content packet.

For the paired orange dumpster, set `loot_demand_orange_pair=true` with
`loot_demand_target={"x":10634,"y":10376,"z":0,"index":1}`. The fixture
spawns the player outside nearby inventory range, walks to the real dumpster
and checks the native inventory of each section independently. Only this
case allocates two watch slots. Read the client timestamps per section.
The elapsed time between sections includes walking. An already matched
inventory on the tick when the section first appears has no measurable
additional delay at tick resolution.

In the full-pack 42.22.2 macOS Host pair, both ordinary sections already
matched on their first visible tick. With deferral the observed waits were
28.8 and 46.9 ms, including server fills of 3.75 and 8.18 ms respectively.
The largest gap between client render callbacks during the approaches was
38.1 ms ordinarily and 25.0 ms with deferral. Both runs passed native
client/server inventory equality. This single local Host comparison measures
panel content readiness and callback cadence during an approach.

For the separate single-player road comparison use suite `loot-demand-drive`,
mode `native` and the same pack plus `PZDrivingBench`. Set
`optimizer_enabled=false` and `driving_perf` to the Muldraugh Extinction
scenario, native population, full throttle and `Base.SportsCar`. Run case
`seed`, export with `check_action_queue.py save-world RUN TEMPLATE`, and run
case `drive` from that template for each arm. Both use maximum zoom by
default. Only the disposable fixture activates the probe. The shared road
controller supplies speed, lane, contacts, zombie counts and frame intervals.
Compare completed runs and inspect the eligible containers recorded between
the measured-distance markers. Different traffic and loot rolls can still
affect the comparison.

In either test `fill_ns` is elapsed time inside one native fill on the
authority. A pending row has no fill duration. Sum completed calls to describe
work performed across an area. Use the separate frame intervals to assess
hitches. Server and client timestamps belong to different processes.

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

Schema 2 also stores a nested, partially used roll of tape, a damaged hammer
with nested modData, and a bottle containing a measured volume of water.
The seed and reload check their exact IDs, contents and values. Earlier schema 1
seeds retain their original identity/nesting coverage. A separate client
request during the Host seed verifies replication for that case. Grid-event diagnostics run after possible earlier
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

The current Build 42.22.2 macOS full-pack comparison on a shared driving
save found 89 matched bins and dumpsters. Ordinary loading spent 285.6 ms
filling them, including 30.4 ms inside one 56.0 ms game interval. With
deferral, those bins had zero native fills during the measured drive. Client
buffer-swap p99 was 33.85 ms ordinarily and 28.73 ms with deferral in this
first pair. A repetition from the same sealed save found 89 common bins
and dumpsters, with 417.4 ms in native fills under ordinary loading and
zero during the measured drive under deferral. Client buffer-swap p99 was
64.32 ms ordinarily and 42.23 ms with deferral. Traffic, speed and traversal
time differed between arms. Both repetition captures passed independent
reanalysis with the current `watched=0` census field. The original reports
retain the earlier classifier failure for that field. Both driving pairs used
Toolkit 0.2.9 on macOS.

On the same runtime a menu Host player walked to a real street bin. Both runs
matched recursive client and server contents. Deferred first fill took
8.36 ms on the server. From listing to complete inventory the client observed
27 ms ordinarily and 32 ms with deferral in these local runs. A map-location
row can represent a different Java identity from the opened container.
A separate witness times the selected live object without importing the prior
automatic visit. The server reports missing timing separately from actual
inventory delivery.

On Build 42.22.2 with the full selected pack, fresh SP and menu Host processes
reloaded sealed worlds on macOS. The pending bin stayed unexplored until one
first fill. The completed dumpster retained its saved item tree, including the
non-default sentinel condition, uses, fluid and nested modData. Reopening did
not refill it. In a separate Host run, the client replicated the populated
world-bin overlay for `trashcontainers_01_17`. Ordinary empty-trash dispatch
during a native fill was blocked before listeners; it emptied the same bin
after the fill. The in-memory serialization check compares IDs and nested
items against the game’s native save format, including its type normalization
and grouping of items by type.

The actual dynamic-JAR activation checker also preserves regressions for helper
self-loading recursion and Buddy registered-JAR discovery. Startup-classpath tests
alone missed those defects; adding ZIP directory entries alone did not fix them.
