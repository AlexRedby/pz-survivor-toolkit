# Pinning items in a truck trunk

The `pinned-items` suite uses the shared native runner with a fresh SP save/profile or a real Host with two clients. It spawns a `Base.PickUpVan`, opens its real `TruckBed` in the loot window, and invokes Pin/Unpin Item Type through the actual inventory context menu.

The first scene captures the inventory class, comparator, and active search/category/tag filters before the fixture changes the UI. It pins the last visible type through the native context menu and checks automatic row movement, persistence after refresh/render, preserved selection, unpin order, and item conservation. Later scenes cover ascending and descending name/category/weight sorts through inventory sort callbacks and a Toolkit category filter with duplicate screwdriver items. With CleanUI selected, the fixture also checks matching-first search, the existing enhanced search path, and the three supported sorts in the vanilla inventory class. The vanilla CleanUI window has no supported search path. When Organized Categories is selected with CleanUI, an additional cold UI scene invokes its real pin button; when selected in any mode, another scene splits the two screwdriver instances across categories and verifies the Better Containers pin.

```sh
python3 tools/check_action_queue.py run /tmp/pinned-items-fresh \
  --suite pinned-items --kind sp --mode toolkit --mods selected \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --workshop "$PZ_WORKSHOP" \
  --config /path/to/explicit-mod-sources.json
```

Use `--mod-source EURY_CONTAINERS=/absolute/mod/root` to select an isolated downloaded version. The smallest valid set is `PZSurvivorToolkit,EURY_CONTAINERS`; add `NeatUI_Framework,CleanUI` to exercise the CleanUI and vanilla scenes. Add `organizedCategories_core` to the selected mods to run its integration scenes; the toolbar scene also requires CleanUI. On game start the fixture sets Better Containers `showAdvancedDisplayCategories=false` in the isolated process. The generated ModOptions file remains runtime output. To test advanced categories, add `"advanced_categories": true` to the JSON supplied with `--config`. Never update the live Workshop directory or read its settings to prepare a comparison.

For the two-client Host run, select both `CleanUI` and `organizedCategories_core` and provide an options JSON containing `{"mp_host": true}`. The runner uses EN for client1 and RU for client2. Each client must produce all 15 scene results with the same six-item ID/type signature; the adapter also matches one server authority receipt per turn and ordered peer-pin absence probes for Better Containers and Organized Categories. Each probe target must match the corresponding startup pin target on the other client.

Run it with `--kind mp`, `--mods selected`, and that Host options file in `--config`; the suite definition starts two clients automatically. This is the game's Host process with two joining clients, not a dedicated server.

The runner seals sources and settings and owns launch/cleanup. `report.json` records per-scene results under functional evidence, separately from runtime/log audit. Each scene also requests a `pin-<scene>.png` screenshot in the test cache. A failed scene remains failed even when the fixture reaches its completion marker. These are programmatic UI callbacks, not physical mouse input. MP uses a real Host and two local clients; dedicated-server coverage is outside this suite. No product sorting is patched by this suite.

The independent SP case `--cases selection` uses the real player inventory in both CleanUI modes (or native inventory alone). It checks exact group/child selection and Shift anchors past a 55-item stack capped to 50 rendered children, including hidden equipment and section headers. It then enables BC player-inventory pins in the isolated process and records actual marker draw coordinates while forwarding the original drawing calls. Markers must follow rendered group rows with expanded/collapsed stacks, visible/hidden equipment, selected-row dragging and the player-pin option. `pin-markers-<mode>-expanded.png` and `pin-markers-<mode>-collapsed.png` support visual inspection; callback assertions alone do not establish correct pixels or physical input.
