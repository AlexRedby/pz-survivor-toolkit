# Native tag checks

Two actual EN/RU clients and an isolated server, launched through the shared native process guard. Requires macOS, JDK 25+, B42.21 and explicit installed mod roots. No live profile is changed; VOIP is disabled. The fixture applies Better Containers' normal option to disable its alternate categorization before stages and again after reconnect, using organizedCategories as the provider. Stock action durations remain in use. Inputs, source hashes, logs, screenshots and exact authoritative item receipts stay in the output directory.

```sh
python3 tests/native_tags/run.py /tmp/tag-rules-fresh \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --workshop "$PZ_WORKSHOP" --selected
```

Build the local Java patch with `tools/prepare_install.py` before `--selected`. Repeat `--workshop` for explicit alternate roots; the first root containing a Mod ID wins, while ambiguity within one root fails. Omit `--selected` for the seven inventory/Quartermaster integration mods. Output must be fresh. Coordinate the desktop slot before launch.

For the four-case selection/sort/reconnect baseline, add `--baseline --source-ref <committed-ref>`. Otherwise 16 cases exercise all/any/excluded/empty inventory filters, match previews, named filter save/apply and disk-read/delete after reconnect, real Quartermaster Save callbacks, saved/reopened rules, stale writes, peer replication, live disable/re-enable, native sorting, every configured icon, and actual client reconnection with the same saved crate/bag/item IDs. Only fixture-owned bags/crates/items are mutated; server receipts check their original IDs and preserve pre-existing inventory IDs. Both modes disconnect/reconnect both clients and require separate authoritative receipts before and after that transition.

Add `--planting` for 20 cases: the original 16 plus item-aware inventory previews, seed-only sorting, Food excluding Seed, and rule restoration. The native catalog must also pass all 75 planting types and 55 full/55 empty packets with exact legacy category projection. After both base sorts, the server creates eight uniquely identified samples: sunflower seeds, candy, carrot seeds, full/empty packets, potato, lemongrass and an unconfigured hemp bundle. Native UI Save and transfer actions must move exactly the five planting samples, then candy for the exclusion rule. Server receipts verify all eight IDs, untouched manual selections and restored rules before and after reconnect. This mode cannot be combined with baseline or cold restart modes.

The icon case also resolves all 209 defined tags through the actual native texture loader, checks the generic custom-category icon, and verifies the case-sensitive `FurnitureDoor` projection plus compatibility with previously saved exact-category rules.

Before either crate is created, both clients must acknowledge that all four staging and crate squares are loaded. This prevents late-joining observers from missing a test object created during their world load. Peer checks continue polling and log square/object/rule/revision diagnostics until the actual native object is available; no synthetic object or injected rule satisfies this check.

Reconnect reacquires native squares and the unique owned crate from primitive saved coordinates, then finds the bag by its original item ID. It does not retain square references across chunk unloads or create replacement fixtures. Missing world objects remain pending with bounded diagnostics.

`--prepare-only` seals inputs without starting the game. The shared `queue_checks.runner.run(output/run)` can launch the prepared snapshot later; `run.verify(output)` audits its tag cases and receipts. `result.json` separates functional success from the complete runtime error audit. Existing errors must be inspected against a comparable baseline; a functional pass alone is not a clean runtime verdict.

For a full server/world restart, run the candidate with `--restart-seed`, then launch a fresh output with `--restart-from /tmp/tag-seed`. Both commands take the same game/JDK/workshop arguments; the reload inherits the seed's Mod IDs and ports. The seed retains its named local filter instead of deleting it. The reload refuses incomplete shutdown, changed source/mod bytes, altered persisted inputs and symlinks. It copies only owned saves, databases, server settings and local filter files, and records their hashes in `run/restart-inputs.json` before launch.

The new processes resolve the original crate, bag, item IDs, manual selections and rule revision from the saved world. Expected fixture metadata never supplies replacement objects or writes product rules. Two reload cases check the persisted rule/editor/local filter, then pick up the original Apple through the native transfer action and sort it back through Quartermaster. Separate ordered server receipts prove the pre-pickup, post-pickup and post-sort locations. `python3 -m unittest discover -s tests -p 'test_native_tag*.py'` checks the seed and receipt gates without launching the game.

These are programmatic native callbacks and rendered screenshots, not physical mouse/controller or WAN tests. The native launcher supports macOS; Windows Host remains unverified. This suite has its own receipt verifier and is not a health-suite coverage declaration in the shared matrix.
