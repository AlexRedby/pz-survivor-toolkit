# Native root inventory to car trunk transfer

`trunk-15` creates a repaired `Base.CarNormal`, an empty real `TruckBed` container,
and fifteen `Base.EngineParts` in the player's root inventory. It places the
player at the native trunk access area, opens the two inventory pages, records a
five-second idle baseline, then invokes the destination pane's actual
`onMouseUp` drop callback with those physical items. Deferred CleanUI admission
is observed until all fifteen exact IDs have been enqueued. Native durations,
transfer callbacks and native source/provenance remain unchanged.

After an observed active transfer and three seconds of queue idle, the fixture
checks all fifteen exact item IDs in the trunk, with one occurrence each across
the player's recursive inventory and every container of the fixture car. Host
uses a separate server receipt and compares the client's current endpoints.

Use the existing runner with `--suite inventory-transfer --cases trunk-15
--kind mp --mods selected --config /absolute/host-config.json`; the configuration
must contain `{"mp_host": true}`. Supply the runner's usual `--game`, `--jdk`,
`--workshop`, resource options and fresh output directory. `--mode native`
provides the corresponding ActionQueue-disabled control. No game copy is
installed or changed by the fixture.

Add `"inventory_transfer_density": true` to the same configuration for a bounded
high-item-count control: 500 ordinary `Base.Paperclip` items in root inventory
and 1000 in the trunk. Their native weight is 0.01 each; all fifteen Engine Parts
still move with unchanged timing. The fixture checks actual native capacities,
retains filler IDs independently on client and server, and verifies each filler
remains at its original endpoint exactly once. Receipts report verified counts
without logging 1500 filler IDs. The default/false configuration remains the
original case, and older default receipts remain verifiable.

The `PROFILE` JSON contains idle and transfer-running UI frame interval counts,
mean, median, p95 and maximum in milliseconds. `calls` reports inclusive Lua
wall time/counts for pane refresh, selection restoration and rendering, inventory
page callbacks, ActionQueue panel callbacks, public policy evaluation and source
proof hashing. Uncalled installed probes report zero. Timing uses
`getTimestampMs`; nested probes overlap and must not be added together. These
are diagnostic UI callback intervals and inclusive Lua costs, not measured GPU
FPS. Native `ISInventoryTransferAction:update` is deliberately not wrapped because
that would invalidate ActionQueue's native method provenance. Physical mouse
movement and a second client are not covered. `performance.inventory` reports
actual root/trunk physical counts, weights and capacities at idle and settlement.
