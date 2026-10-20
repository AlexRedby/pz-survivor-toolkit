# Bulk reading

`--suite bulk-reading --cases dresser-15 --kind mp --mode toolkit` runs one client in menu Host (`{"mp_host":true}` in the options file). The same fixture supports SP and a queue-disabled `--mode native` control.

The authority creates 15 individually identified ordinary magazines in an adjacent dresser. The client opens the native loot pane, dispatches the native Read callback for five selected magazines, then adds the remaining magazines one at a time. Native transfer, reading and return actions retain their normal durations. Completion requires every exact magazine to be marked read and returned once to the dresser, with none left in the player's nested inventory; Host verifies those effects independently on the server.

The profile records enqueue times, queue panel/policy calls and `OnTickEvenPaused` intervals before and during reading. These intervals describe the game callback cadence, not GPU FPS. Compare the same game, mod set, fixture and resource conditions before/after a change. No fixed timing threshold is asserted across machines.

This is native menu callback dispatch, not physical mouse-input coverage. It checks ordinary magazines from one dresser and one client, not every literature type or bulk action family. The focused queue tests separately check shared enqueue scaling, deferred expansion, UI controls and live edit validation.
