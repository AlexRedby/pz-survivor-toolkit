# Native fitness menu fixture

The `fitness` suite exercises `ISFitnessUI:onClick(OK)` with the complete ordered
`SurvivorQoL-selected.ini` mod set. Select any canonical ordered subset:

`empty,queued,sequential,pending-cancel,pending-reorder,active-cancel,missing-dumbbell,exhaustion,closed-ui-restore,burpees-30,active-cancel-restore,pickup-cancel-restore,placement-cancel-restore,empty-restore`

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

The `burpees-30` case selects thirty minutes through the native menu and records
local native removal after the selected duration. Toolkit requires removal within
five real seconds, plus the ordinary authoritative outcome, real exercise effects
and completed independent tail. Its registration is not a native pass.

Other workouts retain the menu's native minimum of ten game minutes and the original
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
the same schoolbag worn again and every other inventory endpoint preserved. Toolkit also requires one real native
root-to-source-bag return begin and its completed shared borrowing receipt before
the independent reader. Read-only client begin and Host serverStart snapshots must
already contain the returned exact-ID/type dumbbell inside the recovered original
bag, with both original hands and worn bag restored. A late final P4 restoration
cannot satisfy this normal-cleanup boundary. Native controls keep their actual
pre-reader differences and original timer/order failures.

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

Host native restoration controls can also leave a client constructor stranded after
an authoritative zero-workout failure. After publishing that unchanged failed row,
the fixture may isolate `closed-ui-restore` or one of the three focused restoration
cases. It requires the exact constructor captured at the original request and
failure, empty client native/Lua queues, inactive observers, no started workouts,
and a fresh read-only server idle snapshot with the same six IDs. Only that local
constructor is cleared. `ISOLATION_STARTED`, server `ISOLATION_READY` and
`ISOLATION_SETTLED` witnesses retain the original failure, immediate before/after
state and actual native cleanup. A grounded bag must return through its genuine
native begin, completed item transaction and successful perform callback; final
client and fresh server snapshots must conserve every exact item ID/type, bag
contents and favourite flag, with the bag carried again. Actual native hand,
activation and prop endpoint differences remain recorded and failed by the original
case checks. No item or gear is reconstructed. Each wait is bounded to 45 real
seconds; a rejected gate or timeout emits `ISOLATION_FAILED` and stops without
advancing to the next case. This isolation does not establish the cause of the
original native failure or turn it into a pass.

The `empty-restore` case starts with an empty queue, the original Hammer and
screwdriver held, a non-favourite schoolbag worn and the exact dumbbell inside it.
It uses the real ten-minute biceps-curl menu request, leaves the UI open and queues
only the independent tail reader after the workout request. It never requests
cancellation or runs the front reader. A pass requires one full natural workout
with real clinical effects, the exact world bag and contents at workout start,
real native placement/recovery, and the ordinary borrowed-equipment return gates.
Toolkit must complete its exact shared prop return and restore equipment before
the tail begins; native pre-tail differences and genuine native failures remain
visible under the existing checks. This case adds an ordinary-completion control
without changing the queued closed-UI or active-cancel controls. Its separate
clock telemetry records the native constructor window, actual observed workout
start and removal. Vanilla constructs the ten-minute deadline before equipment
preparation; a natural Host body can therefore last less than ten minutes. This
new case requires an unchanged selected constructor window and client removal
strictly after that native deadline, while preserving real authoritative workout
effects and measuring its body duration separately. Existing cases retain their
original duration assertions.

The focused `active-cancel-restore`, `pickup-cancel-restore` and
`placement-cancel-restore` cases start with an
active exact-ID Torch and screwdriver held, a schoolbag worn, and the dumbbell
inside that bag together with the unused front book as conserved contents. The
bag is a favourite and must keep that flag on both replicas. Active cancellation
waits for six confirmed native preparation effects in order: prop pickup, both
original hand removals, bag unequip, actual ground placement and prop equip. It
also waits for real exercise repetitions
and (in Toolkit Host) its started acknowledgement. Pickup cancellation instead
targets the actual positive-progress native transfer and its live Host transaction,
before either hand or the worn bag is removed. Placement cancellation targets a
real positive-progress native `ISDropWorldItemAction`. Toolkit must finish the
atomic placement, recover the same world bag through a completed native transfer,
then restore equipment and return the prop. Neither early-cancel case may equip
the prop or execute a workout. Toolkit must finish the borrowed prop pickup, return the same dumbbell exactly once, restore
both original held items, bag and Torch activation before an independent reader,
and preserve the independent reader. Value-only
settlement snapshots prove native callback/transaction-confirmed effects; queue
disappearance is never a receipt. A read-only observer at the shared native begin boundary snapshots the original
equipment before the real reader begins, in both queue modes. The Host reader's
actual serverStart callback also records live authoritative equipment and activation, delegating once.

Both queue-disabled controls invoke the real Fitness OK and CANCEL callbacks.
Native CANCEL during pickup does nothing, so that control must complete one full
native workout with real repetitions and clinical effects. Native active-workout
CANCEL stops the actual workout. Controls preserve native equipment/UI behavior.
The selected P4 Tidy Up Meister 2.0.8 restores the original hands, worn bag and
activation and returns the dumbbell to its captured source bag after the native
queue drains, following the independent reader. Both modes require the exact final
preparation inventory and activation. Native pre-reader equipment and activation
snapshots retain the observed baseline differences; only Toolkit requires complete
restoration before the reader begins. The native closed-UI control's existing
constructor-clock and duration failures remain failures.

World storage receipts verify the exact bag ID/type, native world-object linkage,
placement square, favourite flag and conserved front-book contents. The prop is
separately accounted for in root inventory while its bag is on the ground. SP
records actual placement completion through the shared read-only boundary; Host
records it after the real server `complete`, delegated exactly once. Recovery
requires an actual native begin witness plus the sealed completed pickup state;
root/world disappearance alone proves no effect. Queue-disabled CANCEL during
placement is the real native no-op, so its workout, order and timer failures remain
visible under the same guards.
