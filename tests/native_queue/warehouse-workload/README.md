# Warehouse peer actions

`warehouse-workload/peer-edits` runs two actual EN/RU clients in a fresh menu Host.
The server owns twelve sparse capacity-100 crates. In both CleanUI and vanilla
inventory modes, client2 transfers an item, replaces another without changing the
crate count, and consumes a shared crafting input through the installed native
crafting UI. Client1 observes with loot hidden, walks away and back during the
transfer, then invokes the installed quick-transfer button callback while hidden.

Each step requires server-confirmed item IDs/endpoints and both clients' own
visibility projections. The checks compare the cached proximity aggregate before
reopening, then native rows, counts and categories after reopening. Cleanup checks
original items/equipment, UI/options, player placement and removal of only owned
items and crates. Abort cleanup waits for both native action queues to drain.

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
mkdir -p /tmp/pz-kahlua-check
"$PZ_JDK/bin/javac" -cp "$PZ_GAME/projectzomboid.jar" -d /tmp/pz-kahlua-check \
  tests/native_queue/contributions/smart-deposit/java/KahluaCompileCheck.java
"$PZ_JDK/bin/java" -cp "/tmp/pz-kahlua-check:$PZ_GAME/projectzomboid.jar" \
  KahluaCompileCheck tests/native_queue/warehouse-workload/client/*.lua \
  tests/native_queue/warehouse-workload/shared/*.lua \
  tests/native_queue/warehouse-workload/server/*.lua
```

Synthetic receipt tests exercise rejection paths; only a fresh native report can
establish a game pass. Preserve failed attempts and prepare again after changing
sealed fixture sources.
