# Native fitness menu fixture

The `fitness` suite exercises `ISFitnessUI:onClick(OK)` with the complete ordered
`SurvivorQoL-selected.ini` mod set. Select any canonical ordered subset:

`empty,queued,sequential,pending-cancel,pending-reorder,active-cancel,missing-dumbbell,exhaustion,closed-ui-restore`

Use the common runner's fresh profiles, pack lock, native/toolkit controls and
runtime log audit. The fixture never installs into the normal game profile and
never changes the player's real saves. The adapter rejects world templates,
partial mod sets and one-client multiplayer substitutes.

```sh
python3 tools/check_action_queue.py run /tmp/fitness-sp-native \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --suite fitness --kind sp \
  --cases empty,queued,sequential --mode native --language EN \
  --pack-lock /tmp/selected-pack.lock.json
python3 tools/check_action_queue.py run /tmp/fitness-sp-toolkit \
  --game "$PZ_GAME" --jdk "$PZ_JDK" --suite fitness --kind sp \
  --cases empty,queued,sequential --mode toolkit --language EN \
  --pack-lock /tmp/selected-pack.lock.json --control /tmp/fitness-sp-native
```

For Host use `--kind mp --config /tmp/fitness-host.json` with
`{"mp_host":true}`. The suite starts two actual game clients, EN and RU, and the
real menu Host server. `client1` performs the workouts; `client2` independently
reads a fresh exact-ID native book per case. Both actors have ordered joint-case
outcomes; the peer outcome explicitly records `participantRole=independent-reader`
and `workoutActor=client1`. It does not claim that the peer performed a workout.
The server verifies the peer is connected and its book is fully read.

Workouts retain the menu's native minimum of ten game minutes and the original
`ISFitnessAction:getDuration()`. Queued cases use six remaining book pages at the
native two minutes per page: the workout waits longer than its selected duration.
The sequential case requests squats followed by pushups before the first starts;
separate authoritative start/stop records must prove both full workouts and no
server overlap. The reorder case moves the whole pending workout after the
independent tail reader and verifies that reader finished before workout start.

Pending cancellation uses the Toolkit operation API. Its queue-disabled control
makes the identical unedited request. Active cancellation starts with an empty queue in both modes, waits for real native
progress and, in Toolkit Host, the native started acknowledgement, then cancels the
operation. The native control uses the actual Fitness Cancel callback. Required
item loss removes the exact queued biceps-curl dumbbell on the authority before
start. Exhaustion maintains a deliberately exhausted fixture player while the
front reader runs, so native rest cannot silently remove the tested condition.
The closed-UI case requests biceps curls with its exact dumbbell borrowed from the
worn schoolbag, then closes the actual window immediately after enqueue. Toolkit
must show real native pickup progress and the authority must observe that dumbbell
in the primary hand, with the bag unequipped, at workout start. Final receipts
require the dumbbell back inside that exact bag, both original held IDs restored,
the same schoolbag worn again and every other inventory endpoint preserved.

The observer never replaces source-guarded client/SP action methods. SP reads the
real live `repnb` and clinical state; the server wraps its own native
`serverStart`, `exeLooped`, `serverStop` and `complete` callbacks and always delegates
once. It never calls `exerciseRepeat`, emits artificial animation events, awards
XP, or shortens action/game time. Receipts contain actual repetitions, Fitness and
Strength XP, endurance loss, regularity, stiffness, workout order, server stop
settlement and exact inventory/hand/worn identities. Toolkit Host additionally
requires distinct native started and terminal acknowledgement tokens. Every Toolkit
workout also supplies a real positive `ActionQueueFitness.progress` sample and its
nonempty display label; elapsed minutes, selected ten-minute total and fraction
must agree with the native workout clock. The server
must remain idle for two real seconds before issuing its final receipt.

Native control deviations, missing tails, incomplete restoration, premature timers
and log exceptions remain failures. A failed native control is retained as evidence;
it cannot satisfy the corresponding Toolkit gate. Fixture callbacks do not certify
physical mouse/controller input. No native gameplay pass is established by the
adapter's offline checks.

Run the focused falsification and observer checks without launching the game:

```sh
.venv/bin/python -m unittest discover -s tests -p test_queue_fitness_adapter.py
```

Known native constructor failures in `missing-dumbbell` and `exhaustion` can
leave `currentExe` set without starting a native action. The fixture first records
the unchanged failed receipt and failed case. Only then may it clear that exact
captured object, with empty Lua/native queues and no observed active or started
workout. Explicit `RECOVERY` witnesses retain clinical and inventory snapshots
before and after cleanup. Host verifies the same idle boundary before recording
its failed receipt and recovers only after the client confirms publication of the
failed case. This allows later controls to run; it never turns the failed case
into a pass or changes the recorded clinical/tail observations.
