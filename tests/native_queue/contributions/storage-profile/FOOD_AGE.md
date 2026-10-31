# Natural food freshness

The `storage-profile/inventory-food-age` case runs 12 phases in one fresh SP or one-client menu-Host session: CleanUI and vanilla inventory renderers, 199/200-item stacks, and visible, hidden-page and offscreen-row ageing. Each phase keeps a younger header and an older tail beyond the first 50 items. After the natural fresh-to-stale transition it checks the separate stale group, then expands and collapses the native groups three times while preserving every item identity. Native expanded-child row limits remain unchanged.

```sh
python3 tools/check_action_queue.py run /tmp/food-age-sp \
  --suite storage-profile --cases inventory-food-age --kind sp --mode toolkit \
  --mods selected --language EN --config /path/to/current-source-config.json \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --timeout 1800
```

For Host use `--kind mp` and `"mp_host": true` in the config. Use the common runner's default desktop policy outside the sandbox. Keep natural-age baselines separate from accelerated cooling and performance captures. Live refrigeration, freezing and power cycles use the separate [appliance fixture](../../food-cooling/README.md).

SP uses Apple in the player's root inventory. Host uses active, cookable Cabbage in an owned ambient world container: inert Apple can leave server processing before expiry. The server creates and seeds the exact items once; the client resolves their native replicas and never copies a server age into them. Native ItemStats does not periodically replicate `age` or `lastAged`. Host therefore checks initial identity replication and independent native freshness on both roles, with client UI events and separate authoritative receipts. It does not equate the two ageing mechanisms or require identical ages sampled at different times.

Identity is scoped to the ordered phase and its owned container. Native factory IDs are random and may recur after the previous phase has been released. Each live phase still requires unique numeric IDs, conserved object references/endpoints and exact client/server ID agreement; preparation cannot overlap an unreleased phase.

Only phase setup writes age and last-aged time. Observation delegates to native rendering without calling `Food.updateAge`, changing the world-clock rate or enabling extra rotten-food processing. Hidden/offscreen receipts record actual viewport bounds and a world-time interval spanning the freshness threshold. Owned nonfood fillers supply genuine scrollable rows for the offscreen case. Each phase removes its owned items/container; the lifecycle restores original inventory identities, UI, mode, options and player settings.

Before creating test items, the fixture waits for three identical native layout samples at least 120 ms apart, with a ten-second deadline, and proves a mode/large-resize/relocation restoration roundtrip. First-frame pane geometry can be transitional; it must not become the restoration baseline. Cleanup restores dimensions before coordinates, because native position setters clamp against the current size, and restores both container bindings before native owner layout. It then verifies exact geometry, selection and scroll. Host also waits for the original fractional actor position and both native square references before restoring its containers.

Acceptance requires functional evidence, clean runtime logs and verified source inputs. Mock receipts alone are insufficient. This case does not establish the rotten threshold, hidden inert Host food, physical-input, pixel, performance, second-player, WAN, reload or periodic age-replication coverage.

Focused checks: `.venv/bin/python -m unittest tests.test_queue_food_age tests.test_queue_auxiliary_adapters tests.test_queue_storage_session tests.test_queue_campaign`.
