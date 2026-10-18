# Shared wishlist native fixture intake

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

The common `shared-wishlist` adapter stages the B42.21 client/server scenarios and verifies exact stage labels and server replies. `manifest.json` describes dependencies and parameters; per-run reports record current verification separately from registration. No game files are distributed.

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

## Install hookup for a later authorized native run

Prepare three disposable caches with matching product/mod snapshots by the
existing native tooling or another reviewed launcher. Do not use normal profiles.
Then install this helper once in each cache; `prepare.py` copies only the two Lua
sources and `mod.info`, and writes the private runtime configuration. It does not
copy product mods, alter a server INI, compile Java or start processes.

Supply `TEST_CACHE`, `TEST_HOST`, `TEST_PORT` and `WISHLIST_TEST_PASSWORD` at runtime.
Keep the password out of shell history, argv, source and committed files. For
example, with those environment variables already set:

```sh
python3 tests/native_queue/contributions/shared-wishlist/prepare.py "$TEST_CACHE/client1" \
  --user client1 --mode standalone --host "$TEST_HOST" --port "$TEST_PORT" \
  --password-env WISHLIST_TEST_PASSWORD
```

Repeat for `client2` and `server`, changing the cache/actor. The fresh configuration
has six lines in the order documented in `manifest.json`. For full integrations,
use `--mode full --mods ...` with the exact selected product IDs, including
`PZSurvivorToolkit`, but excluding `WishlistTest`.
Use the dependency APIs in the manifest; the current selected INI defines the mod set.

Enable `WishlistTest` after the selected product mods in each cache's
`mods/default.txt` and server `Mods=` list. Set the server's port to the supplied
port and UDP port to its successor, disable public listing/UPnP/voice, enable Lua
checksums, and use an isolated local server/world. Use client usernames `client1`
and `client2` with the runtime password, languages EN and RU respectively. The
server fixture waits for both fixed actors before it sends their item IDs/start
signal. Full mode needs the CleanUI, combined-container, Neat and Project Cook
APIs listed in the manifest; standalone/visual selects only Toolkit, which includes Wishlist.

Reuse `tests/native_queue/support/ToolkitSmokeLauncher.java` from the common
support. Compile it against the installed game with the selected
JDK; launch clients with the game/JDK native options and `-novoip`, matching the
common native tooling. That launcher handles display and voice checks. Keep
paths, connection credentials and Java-agent policy in the runner-owned runtime
configuration; do not embed them in fixture sources.

The common runner installs these Lua sides and their six-line config, retains
its safe launcher/preflight and verifies the `[WISHLIST_TEST]` contract. Select
exactly one case (`full`, `standalone`, `visual` or `reload`) per run. Full uses
the declared UI integrations; `standalone` is a retained scenario ID for Toolkit
without optional UI mods, also used by visual and reload. All cases support the
Toolkit queue-off control. Historical standalone evidence predates the merge
and does not validate the integrated product.

For persistence through the common runner, finish a successful full/standalone
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

The retained stage labels/counts are unchanged. The sidebar stage follows the
Wishlist entry in the Toolkit tools hub in every mode. Geometry checks use absolute rectangles in both dimensions. Inventory
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

The RU visual search uses decimal UTF-8 byte escapes for `топор`. UI work is programmatic and uses fixed delays; physical interaction, rendering on other systems, WAN reliability and current Workshop versions need separate verification. The concurrent scenario
accepts either winning amount plus an optional `stale_revision`; it proves no
chosen winner, and a later synchronization assertion supplies cross-client checks.
