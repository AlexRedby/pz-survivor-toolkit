# Concurrent native queue transfers

A fresh menu Host with two real clients (EN/RU), the full selected pack, original
native book producers and ordinary action durations. Compatible cases share one
world and game lifecycle. Select any nonempty ordered subset:

- `disjoint-returns`: distinct earned books return independently.
- `shared-capacity`: two books compete for one native unit of destination space;
  verify the original reservation/rejection and exact carried-item retention.
- `contested-pickup`: two clients request one physical book. Verify one owner,
  one rejected pickup and no invented earned return. The losing actor currently
  loses its independent queued tail in both profiles; this bank records that
  fallback and does not qualify independent-tail isolation for failed pickups.
- `lost-done`: last when selected. A disposable, native-source-gated probe drops
  only one exact fresh transaction's Done. Accept, Reject, native work and
  container replication remain unchanged. The server must confirm the physical
  effect before ordinary client cancellation; unknown cannot acquire Keep,
  completed-return pairing or automatic replay.

```sh
python3 tools/check_action_queue.py run "$OUT" \
  --suite queue-transfer-peers --kind mp --mode toolkit --mods selected \
  --cases disjoint-returns,shared-capacity,contested-pickup,lost-done \
  --config "$CONFIG" --game "$PZ_GAME" --jdk "$PZ_JDK" --workshop "$PZ_WORKSHOP"
```

The JSON configuration requires `mp_host: true`; use a current full pack lock
and explicit candidate sources as described in the common runner guide. A
matching `--mode native` run is the queue-disabled control. Both profiles use
silent settings and disabled VOIP; common FIFO/resource/desktop ownership applies.

Authority snapshots count every owned ID across both player inventories and the
fixture shelves and preserve original actor items. Stop observations precede
native transaction removal. Neither advisory receipts nor the vacuous terminal
queries for an absent byte substitute for physical outcomes. Cleanup requires
both peers to drain and acknowledge phase removal. Unsafe/unknown state is not
rolled back into a fabricated successful phase.

This bank does not qualify WAN behavior, late replies after byte reuse, batches
with partial effects, or every queue action family. The signed/zero/reused-byte
allocator regressions live in `NativeTransferRequestsChecks`.
