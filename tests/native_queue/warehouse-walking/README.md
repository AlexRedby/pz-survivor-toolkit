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
has separate frame spans; public functions and direct closure upvalues are
registered, while closures held only in tables may remain in their parent's
time. Shared prototypes combine inventory-page receivers. Inclusive nested
times must not be summed. Observer overhead is included.

Successful completion produces a `captured` result, not a performance pass.
Compare repeatable matched captures before choosing an optimization; these
figures do not establish GPU FPS, WAN behavior or the cause of a user's stutter.

```sh
python3 -m unittest tests.test_queue_warehouse_walking tests.test_warehouse_walking_profile
python3 tools/run_tests.py --test test_warehouse_walking_fixture \
  --test test_warehouse_walking_native --test test_warehouse_walking_client \
  --test test_warehouse_walking_profile --test test_warehouse_walking_lock
```

Set `PZ_GAME` and `PZ_JDK` for the observer's native JVM regression. Preparation
always executes that check; Lua doubles alone do not qualify the VM hooks or
gameplay replication.

For the source-backed manual-lock regression, set
`PZ_WALKING_BC_PROXIMITY_SOURCE` to the locked Better Containers `Proximity.lua`
and `PZ_WALKING_CLEANUI_PAGE_SOURCE` to the locked CleanUI `ISInventoryPage.lua`.
The check executes the actual native look-direction selection and force-hold
boundaries with controller doubles, then verifies the public lock and exact
restoration. Missing external sources are reported as a skip.
