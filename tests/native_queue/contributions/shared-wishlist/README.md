# Shared wishlist native fixture

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

The `shared-wishlist` adapter stages B42.21 client/server scenarios and verifies exact stage labels and server replies. `manifest.json` lists fixture dependencies and parameters. The shared runner guide explains preparation, launch and report interpretation; no game files are distributed here.

Run the no-game check from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/native_queue/contributions/shared-wishlist/check.py
```

The check registers all original stage names/counts, checks helper installation
and rejects invalid/colliding parameters. Its focused protocol test executes the
actual fixture guards against controlled UI/network doubles: sidebar actions and
absolute rectangles, native target-row lookup and bounded scrolling, clipped row
borders with exactly one overlay call, actual combined-container selection,
joint observation ordering and deadlines, and restoration before server readiness.
It does not launch the game or claim native UI/network coverage.

## Native run

The adapter invokes `prepare.py` to stage role-specific sources and private
parameters. Select `full`, `standalone`, `visual` or `reload`. The compatible
`--cases visual,standalone` pair shares one lifecycle in that order; `full` and
`reload` require separate runs.
Full mode uses CleanUI, combined-container, Neat and Project Cook APIs; the other
cases use Wishlist included with Toolkit. All cases support the Toolkit queue-off
control.

For menu Host, use `mp_host=true` with two clients in EN/RU; client1 owns the
native CoopServer and client2 joins. Host reload is unsupported.

For persistence through the common runner, finish a successful `full`, `standalone` or grouped `visual,standalone`
run and supply its absolute directory as `options.seed_run` in the JSON passed
to `--config` for the `reload` case. The adapter requires verified seed evidence,
stopped clients/server and the same ports. It copies the seed's owned `Saves/`
and `db/` state and pins the current product's exact wishlist storage slots under
`Lua/PZSurvivorWishlist/`. Those slots use an encoded absolute world path: a
reload helper carries the unchanged slot text as frozen input data and restores
it through native file APIs for the new world path before `SERVER_READY`.
The completed seed stays unchanged; the new live storage slots are native
outputs. For layout checks use fresh standalone caches and `visual` mode.
Screenshots still need visual inspection.

A seed with verified functional assertions may still have an unresolved native
startup audit. Reload accepts `needs-review` only for `unclassified-errors` with
microphone disabled and every role's logs available; stopped processes, sealed
provenance, exact native stages and server authority receipts remain mandatory.
Seed runtime logs are audited again before reuse; late failures, microphone
activation or unknown errors behind a stale green report reject the seed.
The reload evidence retains `seed_native_audit.pending=true` and
`requires_review=true`, so passing persistence assertions cannot clear that
pending audit. Failed, new-error, unknown, microphone-active or unavailable seed
audits are rejected.

The sidebar stage follows the Wishlist entry in the Toolkit tools hub in every
mode. Geometry checks use absolute rectangles in both dimensions. Inventory
checks retain actual border drawing and independently require exactly one
Wishlist overlay invocation, so a clipped candidate row does not masquerade as
a duplicate wrapper. Before measurement, a real native render builds flattened
rows and scroll bounds; the fixture finds its exact item type, clears pending
smooth scrolling and uses native scrolling to expose that row. The measured
render must highlight that target, not merely another wanted item. This handles
localized loot ordering without replacing items or changing row/pane geometry.
Combined loot is selected through its existing BC button immediately before
measurement, and the fixture verifies the actual selected container.

For completion/revocation and faction removal/restoration, the server releases
each destructive transition only after both clients successfully observed the
state that it replaces. A missing peer fails within 15 seconds; unknown actors,
out-of-order keys and duplicate observations cannot release it. This barrier
protects the assertions themselves instead of extending fixed sleeps.

## Known traps and verification limits

The fixture sources are `client/ZZWishlist.lua` and `server/ZZWishlist_Server.lua`. Native SP UI, storage and lifecycle are not covered by this fixture.

The preserved regression assertions cover wanted-row wrapper duplication,
sidebar overlap, native handcraft/build buttons before their final layout,
catalog close retaining keyboard focus/UIManager references, stale access after
explicit/faction revocation, concurrent revision handling, and wishlist ground
colour competing with Toolkit. Assertions describe the failure each scenario
guards; the retained successful logs do not prove a failing pre-fix build.

The RU visual search uses decimal UTF-8 byte escapes for the Russian word for "axe". UI work is programmatic and uses fixed delays; physical interaction, rendering on other systems, WAN reliability and current Workshop versions need separate verification. The concurrent scenario
accepts either winning amount plus an optional `stale_revision`; it proves no
chosen winner, and a later synchronization assertion supplies cross-client checks.
