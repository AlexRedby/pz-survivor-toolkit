# Warehouse peer actions

`warehouse-workload/peer-edits` runs two actual EN/RU clients in a fresh menu Host.
The server owns twelve sparse capacity-100 crates. In both CleanUI and vanilla
inventory modes, client2 transfers an item, replaces another without changing the
crate count, and consumes a shared crafting input through the installed native
crafting UI. Client1 observes with loot hidden, walks away and back during the
transfer, then invokes the installed quick-transfer button callback while hidden.

Each step requires server-confirmed item IDs/endpoints and both clients' own
visibility projections. The checks record the cached proximity aggregate before reopening without
requiring an unused hidden cache to refresh. They require authoritative physical
replicas before opening, then fresh aggregate identities, native rows, counts
and categories after the installed reopen callback. No fixture refresh is added
to manufacture convergence. Cleanup checks
original items/equipment, UI/options, player placement and removal of only owned
items and crates. The craft receipt binds the actual control and callback: Neat
Crafting consumes directly from source containers; the native control first
queues an ingredient pickup. Selection alone does not identify the active
control because its toggle or dependency fallback can restore vanilla. Abort
cleanup waits for both native action queues to drain.

Inventory removal uses the [shared cleanup journal](../README.md#shared-inventory-cleanup).
It freezes live references and endpoints at the cleanup boundary, preserves the
consumed input separately, and records bounded recovery attempts. Unexpected
recovery receipts fail verification after cleanup finishes. World index packets
are sent at most once; uncertain publication blocks automatic retransmission.

Use the current complete pack and prepared Java Patches. The config contains
`mp_host: true`, `patch_jar` and any explicit `mod_sources`; no imported world or
other inventory owner is supported. Run outside the sandbox on macOS using the
[common desktop policy](../README.md#desktop-launch):

```sh
python3 tools/check_action_queue.py run /tmp/warehouse-peer-fresh \
  --suite warehouse-workload --cases peer-edits --kind mp --mods selected \
  --pack-lock "$PZ_PACK_LOCK" --config "$PZ_HOST_CONFIG" \
  --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --heap-mib 3072 --native-mib 1024 --timeout 1200 --resource-wait 1800
```

The campaign job is `warehouse-peer-host`. This is sparse functional coverage:
native callbacks do not prove physical mouse input, dense walking performance,
FPS, WAN behavior or the cause of a user's save-specific stutter. Dense walking
and window-state timing remain a separate campaign gate.

Focused checks before a game launch:

```sh
.venv/bin/python tools/run_tests.py \
  --test test_warehouse_workload_fixture --test test_warehouse_workload_client
python3 -m unittest tests.test_queue_warehouse_workload tests.test_queue_campaign
.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --check-lua tests/native_queue/warehouse-workload/client \
  --check-lua tests/native_queue/warehouse-workload/shared \
  --check-lua tests/native_queue/warehouse-workload/server
```

Synthetic receipt tests exercise rejection paths; only a fresh native report can
establish a game pass. Preserve failed attempts and prepare again after changing
sealed fixture sources.

## Hidden target affinity

Select `--cases hidden-affinity` with the same fresh two-client menu-Host and
complete-pack inputs. This separate case tests the visible personal page's
actual CleanUI split buttons, once by type and once by category. Vanilla pages
have no corresponding split buttons; `peer-edits` retains their existing checks.

The fixture saves the actual CleanUI `transferMethod` and `transferButtonLayout`
options, selects single-target/split mode and restores both. Single-target mode
reads the hidden selected aggregate before physical Smart Deposit routing;
CleanUI's default nearby-container mode uses physical destinations and a
different admission path. BetterContainers makes its virtual aggregate reject
items with `onlyAcceptCategory=none` and capacity zero. The current single-target
callback must respect that restriction before Smart Deposit is reached.

One peer replaces an exact Bandage stock ID with an exact Screwdriver ID while
keeping the crate count unchanged. The observer holds one owned candidate of
each type. After physical replication, multiple ordinary visible-page draw
frames and at least 500 ms precede the real button callback. The fixture never
forces hidden discovery after replacement. Read-only aggregate samples record
whether the UI naturally converged. Initial source readiness waits for ordinary
visible-page category preparation. Later client observations read native
identity and raw display categories directly: `ManifestModel.item` prepares
categories and would change the state being tested.

Both candidates must be eligible for the physical crate but rejected by the
selected aggregate. Invoke the installed visible button and require no native
actions, at least three further draw frames and 500 ms, an idle queue and exact
unchanged candidate endpoints on the server and both clients. A fresh or stale
transfer is still conserved and cleaned up before the functional verifier
rejects that changed contract. Receipts audit both clients, all 15 owned identities,
original equipment/UI/options and twelve removed crates. Source-only tests use
the installed handler, page callbacks, getters and native ModOptions:

```sh
.venv/bin/python tools/run_tests.py --game "$PZ_GAME" --pack-lock "$PZ_PACK_LOCK" \
  --test test_warehouse_workload_affinity --test test_warehouse_workload_client \
  --test test_warehouse_workload_fixture
.venv/bin/python -m unittest tests.test_queue_warehouse_affinity
```

Accepting source doubles demonstrate the handler's type/category input
dependency; rejecting doubles exercise the aggregate restriction. They do not
establish natural Host staleness. A successful native run covers the restricted
single-target callback with this pack, not nearby transfers, physical mouse
input, immediate packet/input ordering, other stock types or performance.

## Physical target affinity

Select `--cases physical-affinity` with the same complete-pack Host inputs.
Four phases use the actual visible personal split buttons: type/category in
single-target mode, then type/category in nearby mode. The hidden loot page
selects physical crate3 during initial setup. A peer replaces its Bandage with
a Screwdriver without changing the count; no target refresh or category/model
preparation is added after replication.

Receipts record raw physical categories immediately before/after the callback,
native eligibility for both carried candidates, exact queued/transferred IDs,
and at least three post-callback game ticks, three draw frames and 500 ms with
an idle queue. CleanUI may defer enqueue until the next tick; an empty queue
immediately after the button callback does not establish a no-op.
Both methods must deposit only the new Screwdriver candidate. A coherent
category miss or stale transfer is conserved and fully cleaned up before the
functional verifier rejects the result; a failing baseline is never a pass.
Explicit native action refreshes may build hidden rows during this active
step. This case makes no idle-row or performance claim.

The four-phase contract still requires authoritative and both peer endpoint
proofs, fifteen exact owned removals per phase, unchanged original inventories,
restored UI/options/positions and all twelve crates absent. Keep failed
baselines separate from fresh candidate runs; changing sealed fixture inputs
requires a fresh preparation.
