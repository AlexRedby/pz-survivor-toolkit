# Stand intake

Preserve independent stands under topic directories. Integrate setup/events/receipts/log audit before adding them as ready suites in `../catalog.json`. Intake alone is not passing coverage.

Each contribution supplies source fixtures and a manifest/README with game/mod versions, prerequisites, local path parameters, fresh-profile setup, commands, exact assertions, reproduced problems and SP/MP/language limits. Preserve VOIP-off, desktop-lock/process checks and ownership-safe teardown. Do not commit generated worlds, downloaded files, binaries, media or raw logs. Preserve probe source and build commands instead. Old runs do not verify newly edited fixtures.

The map-reading chat had no separate live stand. Its existing regression is `tests/test_map_read.lua` in commit `3eea9b3` (`fix/map-read`): stale map references after MP inventory replacement with the same ID, cancellation/loss, player isolation and dropping the opened map. This is Lua/native-source coverage, not a live SP/MP claim; no game dumps are needed here.

The propane research chat had no executable stand or reproduced gameplay failure; its source inspection is not test coverage.

Preserved intakes from the other chats:

| Topic | Preserved source | Integration boundary |
|---|---|---|
| `video-recording` | Fresh-profile preparation, Java/Lua capture fixture, verifier and tests | macOS/EN/SP historical evidence; common-runner adapter pending |
| `animal-trailer` | Equipment race, trailer ghost and animal timer probes; build/verify tools | Historical one-client MP; new common-runner launch pending |
| `crafting-plans` | Chains, shared inputs, Neat UI and ingredient alternatives | Parameterized historical MP scenarios; event/receipt adapter pending |
| `shared-wishlist` | Shared edits/access, persistence and UI fixtures | Server/client preparation preserved; current native revalidation pending |
| `item-tags` | Five screenshot/assertion scenes and preparation test | Needs Toolkit 0.1.53+ and listed UI mods; common-runner adapter pending |
| `wooden_cart_motion` | Input bridge, disposable area and 16 clip scenarios | Needs candidate cart-motion APIs absent from queue main; remaining mesh/palette/grip probes and analyzers still need preservation |
