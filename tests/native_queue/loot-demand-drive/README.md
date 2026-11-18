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

## Checking the profiler locally

```sh
python3 -m unittest discover -s tests -p 'test_loot_drive_jfr.py'
```

Set `PZ_JFR_TEST_JDK` to a JDK 25 home to exercise the owned recording, clock
anchors and thread counters. Set `PZ_JFR_TEST_GAME` to the game's Java
directory as well to verify ordinary probe initialization with the game JARs.
