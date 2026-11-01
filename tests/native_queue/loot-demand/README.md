# Disposable on-demand world loot experiment

This opt-in research fixture leaves shipped Toolkit, Java Patches and the Windows
package unchanged. It defers initial native `bin`/`dumpster` loading, retaining
`explored=false`, and reuses ordinary authority-side fill on access. The exact
native method guards reject unsupported code; partially installed hooks remain
inactive. No blanket `getItems()` interception or background fill queue is added.

`loot-demand/lifecycle` uses the shared runner's isolated SP or menu Host, one
client, current selected pack and normal desktop policy. Supply explicit local
sources and `loot_demand_experiment=true`, `preload_toolkit_fonts=true`, and (for
Host) `mp_host=true`. The runner must use `--exclusive`. An optional pinned
`optimizer_archive` uses the existing selective overlay stager. Never copy this
fixture into an ordinary game profile. The generated mod requires its matching
per-run token and ownership marker.

The current native bank uses synthetic world objects with real bin sprites,
actual loader/access methods, a fixture-only OnFillContainer sentinel, repeat and
reentrant calls, native ItemContainer serialization, and destruction spilling.
It checks that every generated item ID reaches the ground. The selected
FurniturePushPull sources are fingerprinted; their two authority movement
entrypoints ensure every member container before capturing contents. Run its
source-backed Lua checks with `furniture_checks.py --furniture-root PATH` using a
Python environment containing Lupa.

These are functional checks, not a driving benchmark. Native serialization in
memory is not a stopped world save/restart. The Host phase creates a separate
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

## Qualification state

The first SP and Host attempts stopped before this lifecycle bank because of two
fixture activation defects. Both now have old-artifact regressions: initialize
the transformer's own helper before registration, and use Buddy's registered-JAR
scanner rather than explicit AppClassLoader scanning for a dynamically appended
JAR. Startup-classpath activation alone missed the latter. Directory entries
alone did not fix it and that attempted repair was discarded.

Corrected artifact activation passes outside the game. Actual SP/Host gameplay,
reload/movement and driving benefit remain unqualified; do not promote this
experiment to a user package on the strength of activation tests.
