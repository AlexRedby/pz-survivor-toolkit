# Shared wishlist native fixture intake

[Development](../../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../../README.md)

This contribution preserves reusable client/server assertions for shared Wishlist behavior. It is **intake only**: no catalog entry, common-runner support or current native verification is claimed. `manifest.json` describes dependencies and parameters. No game files are distributed.

Run the no-game check from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/native_queue/contributions/shared-wishlist/check.py
```

The check loads Lua only to register callbacks and count stages. It also checks
helper installation and rejection of invalid/colliding parameters. It never
executes a stage body or launches the game.

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
Use the dependency APIs in the manifest; the current selected INI defines the mod set.

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
common native tooling. That launcher handles display and voice checks. Keep
paths, connection credentials and Java-agent policy in the runner-owned runtime
configuration; do not embed them in fixture sources.

The existing queue runner expects queue-specific selectors/events. It cannot
run this fixture just by selecting a suite name. A later integration should
install these Lua sides and provide the six-line config, retain the common safe
launcher/preflight, and collect the `[WISHLIST_TEST]` output contract. Do not
register the contribution as ready until that path has native validation.

For persistence, finish a fresh full/standalone run, stop **both clients and the
server cleanly**, then change only line 2 of each existing runtime config to
`reload` and restart the same world/caches. Do not prepare over an existing
fixture or start reload with a fresh world. For layout checks use fresh
standalone caches and `visual` mode. Screenshots are runtime outputs only.

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
