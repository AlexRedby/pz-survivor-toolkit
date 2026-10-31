# Live food cooling

`food-cooling/appliances` runs one ordered appliance lifecycle in SP or one-client menu Host: powered refrigeration/freezing, fridge-to-inventory warming, return-to-fridge cooling, and generator shutdown/thawing. Use a fresh profile with the current prepared mods and exact selected dependency sources.

```sh
python3 tools/check_action_queue.py run /tmp/food-cooling-sp \
  --suite food-cooling --cases appliances --kind sp --mode toolkit \
  --mods selected --config /path/to/current-source-config.json \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --timeout 1800
```

For menu Host use `--kind mp` and `"mp_host": true` in the config. Run outside the sandbox under the common runner's default desktop policy. Native mode disables the Toolkit queue; selected Java patches and dependencies still need explicit source selection for an unpatched control.

The fixture creates a sprite-derived refrigerator/freezer, an ambient crate, a generator and three exact-ID `Base.Cabbage` items. Real native timed actions connect/start/stop the generator and transfer the chilled item. Initial food age/freezing is seeded once; observers never write age, heat or freezing, or call `Food.updateAge`. The native visible inventory panels cycle through containers and a delegating renderer observer proves the exact owned rows are visible. World time runs at five real minutes per game day; action durations remain unchanged. Recorded sandbox settings make the generator the power source. The ordinary `DaysForRottenFoodRemoval=-1` stays unchanged: enabling removal would add background age updates even for fresh SP food and could mask a renderer failure. The fixture restores its time/sandbox/UI/position settings, removes only its owned objects/items and verifies original inventory identities.

Use `--cases collapsed-stacks` for the same four transitions with 199 foods in the fridge, 200 in the freezer and one ambient control. The designated chilled/frozen sentinels are the exact last members of their collapsed groups, distinct from each displayed header. This variant selects the vanilla inventory renderer and requires the reviewed shared food-age updater. Its passive observer delegates that updater unchanged and verifies an admitted full-stack pass over the exact group. Active cookable food may already have been aged by native world processing, so an unchanged sentinel `lastAged` is allowed; this is not proof of renderer-driven ageing for inert food. Only the sentinels' thermal state is measured. Moving the chilled sentinel to inventory is explicitly checked as a singleton before returning it to its group.

The collapsed variant sets owned appliance capacity to fit the fixture's actual native weight, checks its Host replication and retains ordinary transfer admission. Cleanup removes all 400 owned foods and three world objects. Before switching mode, the fixture captures a settled UI baseline; after returning to the original fractional position and native squares it restores the original mode on the current live pages. Exact container bindings, geometry, selection/group identities, selection anchors and equipped-group state must pass before `UI_RESTORED` and cleanup are accepted. Missing items, bindings or UI state fail the case.

Native walking returns the actor to a shared observation tile after actions, and both roles must confirm a stable position before each phase. `SETTLED`, `BEGIN` and `RENDERED` receipts bind admission and on-screen item rows to the measured phase. Raw `SETUP`, `COMMAND`, `PHASE` and `CLEANUP` receipts record each role's time, age/lastAged, heat, freezing, power and item endpoints. The verifier independently checks thermal trends, slower refrigerator ageing against an ambient control, native action effects, exact identities and lifecycle order.

Thermal transition baselines precede the actual action: client action snapshots, and server setup or the preceding completed phase. Native transfer/walking time may already warm food before the later observation phase begins. Ageing rates still use each item's measured `lastAged` interval. Host completion requires both roles to reach the final state independently, including exact zero freezing after power loss; client readiness alone is insufficient. Bit-identical client/server ages observed at different times are not required. Runtime log auditing and source provenance remain separate completion gates.

This covers active cookable food, visible panes and generator power. It does not qualify hidden/inert stacks, freshness boundary regrouping, manual Nick's Turn Off Fridges commands, save/reload, physical input or WAN behavior. An adapter declaration or a successful mocked receipt check alone is not native qualification.

Focused checks: `.venv/bin/python -m unittest tests.test_queue_food_cooling tests.test_queue_catalog_selection`.
