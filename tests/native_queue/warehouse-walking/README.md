# Warehouse walking capture

`warehouse-walking/walk` uses the same 16-phase workload in fresh SP and a
two-client menu Host: 12 or 4,800 nails in twelve capacity-100 crates, CleanUI
and vanilla inventory modes, and four window states. Each client walks a
separate mirrored outer aisle through native timed actions, avoiding shared
start/goal collisions. SP uses the same aisle as the first Host client. Each
interval starts and ends beside three crates (3 or 1,200 selected items); the
total warehouse load stays 12 or 4,800. Server authority and client replicas
must agree before and after each interval; identity scans and sorting stay
outside measured ticks. Original inventories, positions, UI and options must
be restored and every owned crate removed.

Each measured actor carries exactly eight unequipped `Base.Nails`, with the
same native weight and empty hands, worn and attached slots. Original root
objects and their nested contents are retained outside measured containers
independently on authority and replica. The fixture restores those exact
objects, root order and equipment; it never sends original-item replacement
packets. Fresh actors must already have empty hands and attached slots before
mutation. Worn clothing uses the native silent bulk-clear/collection APIs:
ordinary clothing setters send synchronization packets and can race the
authority's baseline capture. Both clients join before originals are captured;
authority and replicas then correlate original worn slots and IDs while those
objects remain in their inventories. Authority seeding waits for both clients
to acknowledge silent normalization. Final receipts require the original slots
and exact objects after restoration. Barriers verify
cohort composition, weight, IDs, authority/replica agreement and retained
original identities, topology and payload fields.
Partial setup and abort cleanup use the same ownership checks before removal.
Native factory IDs are random and are not guaranteed unique. Dense seeding
first stages the entire cohort through native `instanceItem`, detached from
containers. Each slot permits up to 32 collision retries against saved originals,
both live actor cohorts and the current warehouse cohort. IDs may recur after a
previous phase is fully released; the fixture never rewrites IDs or changes RNG.
It inserts the exact staged objects with `AddItem(InventoryItem)`, recording
each insertion before the native mutation. Allocation failures publish no
partial cohort; insertion/publication failures retain exact-object ownership
for cleanup after the normal drain barrier, including native calls that insert
before throwing. Only a complete seed can reach measurement. Cleanup still
rejects foreign objects and missing committed items; interrupted cleanup itself
remains a separate TODO. Exclude the entire failed capture from comparisons and
retain its report.

The disposable test mod sends the setup and final cleanup commands through the
unchanged native command serializer with reliable ordered delivery. Initial
capture and normalization use channel zero, like native clothing; `Prepared`,
`Abortd` and `Done` use channel one, like native item/container/world changes.
Ordinary Lua commands are reliable unordered and cannot provide these fences.
The private sender checks exact native bytecode, the staged
cache/class marker, owner thread, loopback connection, actor and command allowlist;
it changes no global packet settings. The menu Host server may use its first
client's cache only under the checked native coop-server and fixture options.
Lua requires an explicit successful-send result because native exposed Java
exceptions can be logged without propagating through Lua `pcall`.
Fences drain prior packets in that direction and channel only. A world removal
can additionally be deferred until its square loads, so actual loaded-square,
cohort and absence checks remain required. Later changes still fail invariants.
Measured-loop commands retain their ordinary transport.

Setup uses Better Containers' public manual proximity lock. Native inventory
discovery can otherwise select the physical container the character turns
toward, changing the workload mid-walk. The lock is established before warmup;
the fixture only checks it during measurement. Original per-player lock state,
pending intent and page unlock flags are restored alongside the UI.

Prepare matching snapshots from frozen sources. Use one complete current pack lock
and the same product sources, heap, native budget and sandbox settings:

```sh
python3 tools/check_action_queue.py prepare /tmp/warehouse-walk-sp \
  --suite warehouse-walking --cases walk --kind sp --mods selected \
  --config /path/to/sp-options.json \
  --pack-lock "$PZ_PACK_LOCK" --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --heap-mib 3072 --native-mib 1024 --exclusive --timeout 1800
python3 tools/check_action_queue.py prepare /tmp/warehouse-walk-host \
  --suite warehouse-walking --cases walk --kind mp --mods selected \
  --config /path/to/host-options.json --pack-lock "$PZ_PACK_LOCK" \
  --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --heap-mib 3072 --native-mib 1024 --exclusive --timeout 1800
python3 tools/check_action_queue.py resume /tmp/warehouse-walk-sp
python3 tools/check_action_queue.py resume /tmp/warehouse-walk-host
```

The SP options file contains `{"preload_toolkit_fonts": true}`; the Host file
contains `{"mp_host": true, "preload_toolkit_fonts": true}`. This explicitly
loads the selected Toolkit font bootstrap before native font initialization.
Keep the default `auto`
desktop policy and normal admission guards. Do not build or prepare another
snapshot during measurement. The campaign jobs are `warehouse-dense-sp` and
`warehouse-dense-host`; sparse `warehouse-peer-host` remains a separate
functional check. The older storage-profile walk also retains its separate
highlight, fairness and selection checks.

The disposable Java observer checks exact native Kahlua hashes and exercises
its hooks against the installed VM before staging. It observes registered Lua
frame lifetimes without replacing UI functions. Metrics retain source and line
identity. Exclusive time subtracts registered children only; tail replacement
has separate frame spans. Public functions, direct closure upvalues and nested
prototype templates are registered, including tag readers and dynamically
created recipe-context methods. Public labels take priority and each metric
retains bounded aliases; aliases refer to the same counter. Exclusive reader
time includes that reader's own work and Java/native calls. Shared prototypes
combine inventory-page receivers. Inclusive nested times must not be summed.
Observer overhead is included, so comparisons require the same observer.

When the JVM supports and enables it, allocation bytes cover the entire owner
MainThread interval, including other game work and the observer. Only two
allocation-counter reads occur per interval. This is an aggregate diagnostic,
not attribution to an individual reader; unavailable counters remain explicit.

Successful completion produces a `captured` result, not a performance pass.
Compare repeatable matched captures before choosing an optimization; these
figures do not establish GPU FPS, WAN behavior or the cause of a user's stutter.

```sh
python3 -m unittest tests.test_queue_warehouse_walking tests.test_warehouse_walking_profile \
  tests.test_warehouse_walking_equipment_native
python3 tools/run_tests.py --test test_warehouse_walking_fixture \
  --test test_warehouse_walking_items \
  --test test_warehouse_walking_native --test test_warehouse_walking_client \
  --test test_warehouse_walking_profile --test test_warehouse_walking_lock
```

Set `PZ_GAME` and `PZ_JDK` for the observer's native JVM regression. Preparation
always executes that check; Lua doubles alone do not qualify the VM hooks or
gameplay replication. The opt-in native equipment checks also verify the
installed setter packet side effects and the silent collection/model boundary;
enable them with `PZ_NATIVE_WALKING_EQUIPMENT_CHECK=1` alongside those paths.

For the source-backed manual-lock regression, set
`PZ_WALKING_BC_PROXIMITY_SOURCE` to the locked Better Containers `Proximity.lua`
and `PZ_WALKING_CLEANUI_PAGE_SOURCE` to the locked CleanUI `ISInventoryPage.lua`.
The check executes the actual native look-direction selection and force-hold
boundaries with controller doubles, then verifies the public lock and exact
restoration. Missing external sources are reported as a skip.
