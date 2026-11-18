# Profiling a driving stall

Set `"road_jfr": true` in the selection options for an isolated single-player
`loot-demand-drive` run with case `drive` and arm `observe` or `defer`.
The ordinary seed and drive use their existing collectors. The optional
profiler retains the save, route, traffic and minimum-speed checks.

## Reading a capture

The test client starts a named JFR recording. The runner records the identities
of the profile, probe JAR and launcher as part of the prepared inputs. The owned
client cache contains these files when recording succeeds.

- `road-measured.jfr` contains startup, approach and measured driving up to
  the explicit dump. Use phase 3 of the frame CSV to select the driving window.
- `road-runtime.jfr` is the launch recording's separate JVM exit destination.
- `road-thread-cpu.csv` pairs game and swap timestamps with the corresponding
  Java thread ID and cumulative CPU time. Subtract adjacent readings for the
  same thread and channel to get the CPU time it used during an interval.
- `driving-perf.csv` retains its original schema. The legacy column
  `cpu_work_ns` measures elapsed wall time inside the game update.

Use the `begin`, `measure` and `finish` events of type `pz.RoadClockAnchor`
to align JFR with the frame timestamps. Each event brackets the JFR start time
with two monotonic readings and carries the process, thread, recording and
launch identities. Retain the bracket width as timing uncertainty.

The collector writes frame and census data before dumping JFR, so those files
survive a finalization error. A failed speed or route check excludes the run
from high-speed results. Use an unprofiled pair for performance comparisons.

## Observed driving stall

In a macOS 42.22.2 full-pack drive through Muldraugh, the sports car entered
the measured stretch at 98 km/h and left at 120 km/h with no contacts. A
231 ms game interval consumed 57 ms of main-thread CPU. During the overlapping
render interval, the renderer waited 209 ms for the main thread to submit its
state. The census recorded no target bin fills, and the longest recorded GC
pause during the measured drive was below 0.05 ms. The machine averaged 96%
CPU utilization. Scheduler data would be needed to distinguish runnable delay
from native waits during the remainder of the long game interval. This run
used the research collector that preceded the optional mode.

## Chunk admission in the recorded drive

In the measured stretch, 222 of 953 main-thread JFR samples included
`IsoChunk.doLoadGridsquare`. Its immediate children accounted for 52 samples
in erosion, 51 in `loadInMainThread`, 42 in Lua event dispatch and 40 in the
grid-square loader. The remaining 37 samples covered other children and the
method itself. These are mutually exclusive sample counts. The largest game
interval contained only three such samples. The separate Windows recording on
42.21 contained the same four branches.

Tree and bush replacement accounted for 36 of the erosion samples. Both use
the normal tile-removal path, including neighbor recalculation and Lua events.
The native per-square initialization flag survives serialization. The initial
world had no saved chunks along the center of the measured stretch. After
the drive, the first serialized ground square in each available route chunk
was initialized. A revisit can still require growth updates and chunk
admission. A fresh-route percentage cannot predict repeat-route frame times.

A native replay removed only the second navigation update at each corner of a
chunk. Ordinary dense, sparse and multilevel layouts preserved their observed
state. On freshly restored inputs, alternating uninstrumented JVM runs gave
approximately 0.73 ms per integration prefix in the dense layout and 0.38 ms
in the mixed layout for both variants. The experiment did not justify changing
the gameplay code. Navigation, collision, vision and pathfinding updates stay
on their original engine paths.

## Vegetation on first arrival in 42.22.2

An instrumented, full-pack macOS SP drive on the same fresh Muldraugh route
recorded 3,757 tree and bush removals. Of 3,756 consecutive transitions,
1,543 touched a common square and 750 recalculated a common pair of squares.
The latter account for 3,323 of 42,747 pair calls. Keys include the world
coordinates and object identity hashes of both endpoints. Matching geometry
does not establish interchangeable inputs after the next object removal.

In each removal the game updated collision data and dispatched removal events
before it returned. When the native pathfinding bit was set, 39 removals
also synchronously prepared navigation updates for their own squares.
On a synthetic tree, delaying the property refresh changed the observed
native navigation cost from 0 to 5 until the refresh ran. The same check
on a bush saw the updated live object list immediately. Broad deferral
would need to preserve these intermediate reads.

In the ten longest complete game intervals in this drive, neighbor
recalculation occupied 5.99 ms of 477.07 ms. In the longest interval it
occupied 0.47 ms of 56.33 ms. These inclusive wall durations come from
one instrumented JVM. They cannot establish a Windows or Host FPS change.
At 40 recorded removal centers found in the same drive's saved ground-square
sample, the saved erosion category matched. Reloading the sampled vegetation
skipped first-time validation and still scheduled growth when due.

A separate native replay refreshed the center's blocked navigation pointers
once at the end of the central neighbor loop, preserving the other pair
updates. Alternating JVMs on restored dense and mixed layouts showed no
consistent speedup. The current gameplay profile retains native behavior.

## Checking the profiler locally

```sh
python3 -m unittest discover -s tests -p 'test_loot_drive_jfr.py'
```

Set `PZ_JFR_TEST_JDK` to a JDK 25 home to exercise the owned recording, clock
anchors and thread counters. Set `PZ_JFR_TEST_GAME` to the game's Java
directory as well to verify ordinary probe initialization with the game JARs.
