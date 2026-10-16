# Shared wishlist native fixture intake

This contribution preserves the reusable client/server assertions from the local
2026-10-12 wishlist investigation. It is **intake only**: no catalog entry, common
runner support or new native pass is claimed. `manifest.json` describes the
dependencies, parameters and historical counts. No game files are distributed.

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
