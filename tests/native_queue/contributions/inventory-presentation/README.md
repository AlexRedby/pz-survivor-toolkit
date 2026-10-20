# Owned inventory presentation native fixture

The shared `inventory-presentation/scenes` suite stages this EN/SP B42.21 helper
inside a fresh disposable profile. It never installs into the user's game.

```sh
python3 tools/check_action_queue.py run /tmp/inventory-presentation-fresh \
  --suite inventory-presentation --cases scenes --kind sp --mode toolkit \
  --language EN --mods selected --game "$PZ_GAME" --jdk "$PZ_JDK" \
  --workshop "$PZ_WORKSHOP"
```

The selected set omits the separate `ContainerCapacityIndicator`,
`BravoItemDetails`, `Quartermaster`, `HasResearch` and `SeedSeasonIndicator` mods.
The fixture rejects those external owners. The normal
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
unique.

Later scenes replace that inventory with native carrot seeds, a full and empty
seed packet, and barbed wire. Real recipe knowledge, Maintenance level 1 and
the native `getResearchableRecipes` API establish research eligibility; native
carrot data, known growing-season recipe and June establish planting status.
Forwarding draw observers require one badge at each actual icon coordinate in
both CleanUI modes, with no marker on the empty packet. Learning the research
recipes removes its marker. Disabling native growing seasons or the saved
indicator preference removes planting markers. A native `ISToolTipInv` shows
growing information exactly once in each native measure/draw pass, fits the
screen, and stops extending when the tooltip preference is disabled. The
shared full-log audit remains mandatory.

Seven screenshots are required as artifacts, including indicators in both
modes and the growing-information tooltip. Their presence does not replace
visual inspection for clipping or layout quality. Programmatic native UI
callbacks do not establish physical mouse/controller, Host, English/Russian
parity, every third-party combination or long-session coverage. `--mode native`
only disables the queue; it is not an external-mod or pre-migration UI control.
