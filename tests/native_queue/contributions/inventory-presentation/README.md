# Owned inventory presentation native fixture

The shared `inventory-presentation/scenes` suite stages this EN/SP B42.21 helper
inside a fresh disposable profile. It never installs into the user's game.

```sh
python3 tools/check_action_queue.py run /tmp/inventory-presentation-fresh \
  --suite inventory-presentation --cases scenes --kind sp --mode toolkit \
  --language EN --mods selected --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --workshop "$PZ_WORKSHOP"
```

The selected set omits the separate `ContainerCapacityIndicator` and
`BravoItemDetails` mods. The fixture rejects those external owners. The normal
source/mod snapshot guards and selected-pack lock validation apply.

Defaults are 1280x900 and the runner's normal `PZ-TEST` workspace. Optional
`--config` accepts `{"window_size":[1280,900],"test_workspace":"PZ-TEST"}`.
Required source mods are listed in the manifest; full selected-pack runs also
need the prepared local Java patch artifact required by that selection.

The fixture creates real native items in its disposable player's inventory:
a partly filled bag, loose magazine, chambered pistol, sharpened knife, food
with Nutritionist, water, clothing, vehicle battery, and seven drainable
batteries. It observes forwarding draw calls in actual CleanUI and vanilla
panes, toggles back to CleanUI, and verifies capacity fill, magazine segments,
native detail values and exactly one overlay per rendered icon. A native
container button must render its bar once. The expanded physical battery stack
then exercises a three-item sort prefix while preserving four tail items,
physical-child selection and the Shift anchor. All physical child IDs remain
unique. The shared full-log audit remains mandatory.

Four screenshots are required as artifacts. Their presence does not replace
visual inspection for clipping or layout quality. Programmatic native UI
callbacks do not establish physical mouse/controller, Host, English/Russian
parity, every third-party combination or long-session coverage. `--mode native`
only disables the queue; it is not an external-mod or pre-migration UI control.
