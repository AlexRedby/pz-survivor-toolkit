# Shared wishlist native fixture intake

This contribution preserves the reusable client/server assertions from the local
2026-10-12 wishlist investigation. The common `shared-wishlist` adapter now stages
the preserved scenarios and verifies their exact stage labels and server replies.
Integration does not claim a new native pass. `manifest.json` describes the
dependencies, parameters and historical counts. No game files are distributed.

Run the no-game check from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/native_queue/contributions/shared-wishlist/check.py
```

The check registers all original stage names/counts, checks helper installation
and rejects invalid/colliding parameters. Its focused protocol test executes the
actual fixture guards against controlled UI/network doubles: sidebar actions and
absolute rectangles, clipped row borders with exactly one overlay call, joint
observation ordering and deadlines, and restoration before server readiness.
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
`PZSurvivorWishlist` and `PZSurvivorToolkit`, but excluding `WishlistTest`.
The historical setup assumed 41 IDs while its first summary reports 39 selected
plus one candidate. This intake checks the supplied IDs instead of preserving
that stale count. Use the dependency APIs in the manifest rather than treating
the old selection as a current install list.

Enable `WishlistTest` after the selected product mods in each cache's
`mods/default.txt` and server `Mods=` list. Set the server's port to the supplied
port and UDP port to its successor, disable public listing/UPnP/voice, enable Lua
checksums, and use an isolated local server/world. Use client usernames `client1`
and `client2` with the runtime password, languages EN and RU respectively. The
server fixture waits for both fixed actors before it sends their item IDs/start
signal. Full mode needs the CleanUI, combined-container, Neat and Project Cook
APIs listed in the manifest; standalone/visual selects only the wishlist product.

Reuse `tests/native_queue/support/ToolkitSmokeLauncher.java` when that common
support is integrated. Compile it against the installed game with the selected
JDK; launch clients with the game/JDK native options and `-novoip`, matching the
common native tooling. That launcher handles display and voice checks. The
archived launcher was deliberately omitted: it resolved loading classes too
early and lacked the later display/voice protections. The old `setup.py` and
`run.py` were also omitted because they embedded a workstation layout, fixed
endpoint/password, platform user ID and Java-agent policy choices.

The common runner installs these Lua sides and their six-line config, retains
its safe launcher/preflight and verifies the `[WISHLIST_TEST]` contract. Select
exactly one case (`full`, `standalone`, `visual` or `reload`) per run. Full uses
the declared UI integrations; standalone and visual select only Wishlist.
Only full has a native queue-off control. Standalone, visual and reload contain
no Toolkit queue option, so they run only in the catalog's `toolkit` mode and
explicitly report that the queue control is inapplicable.

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
The reload evidence retains `seed_native_audit.pending=true` and
`requires_review=true`, so passing persistence assertions cannot clear that
pending audit. Failed, new-error, unknown, microphone-active or unavailable seed
audits are rejected.

The retained stage labels/counts are unchanged. With Toolkit loaded, the sidebar
stage follows the Wishlist entry in the tools hub; standalone uses its direct
button. Geometry checks use absolute rectangles in both dimensions. Inventory
checks retain actual border drawing and independently require exactly one
Wishlist overlay invocation, so a clipped candidate row does not masquerade as
a duplicate wrapper.

For completion/revocation and faction removal/restoration, the server releases
each destructive transition only after both clients successfully observed the
state that it replaces. A missing peer fails within 15 seconds; unknown actors,
out-of-order keys and duplicate observations cannot release it. This barrier
protects the assertions themselves instead of extending fixed sleeps.

## Historical evidence and known traps

The source is `.codex/investigations/wishlist-20261012/native/ZZWishlist.lua` and
`ZZWishlist_Server.lua`. The four evidence summaries in the adjacent `evidence`
directory report zero failures per EN/RU client: full 33, standalone 26, restart
5, visual 11. These are old B42.21 macOS MP results, not checks performed during
this intake. The current scenario registration retains those counts. Native SP
was not tested; the old unit log's SP model checks do not establish native SP UI,
storage or lifecycle behavior. No old logs, profiles, saves or images were copied.

The preserved regression assertions cover wanted-row wrapper duplication,
sidebar overlap, native handcraft/build buttons before their final layout,
catalog close retaining keyboard focus/UIManager references, stale access after
explicit/faction revocation, concurrent revision handling, and wishlist ground
colour competing with Toolkit. Assertions describe the failure each scenario
guards; the retained successful logs do not prove a failing pre-fix build.

The RU visual search deliberately uses decimal UTF-8 byte escapes for `топор`.
The archive contained a Kahlua encoding probe comparing literal Cyrillic with
escaped bytes; the byte form is kept, without claiming the probe alone proves
current engine behavior. UI work is programmatic and uses fixed delays, so
physical interaction, rendering on other systems, WAN reliability and current
Workshop versions still need separate verification. The concurrent scenario
accepts either winning amount plus an optional `stale_revision`; it proves no
chosen winner, and a later synchronization assertion supplies cross-client checks.
