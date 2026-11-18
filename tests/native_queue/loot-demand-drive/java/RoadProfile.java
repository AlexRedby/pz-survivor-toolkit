package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import jdk.jfr.Event;
import jdk.jfr.FlightRecorder;
import jdk.jfr.Label;
import jdk.jfr.Name;
import jdk.jfr.Recording;
import jdk.jfr.RecordingState;
import jdk.jfr.StackTrace;

/** Optional diagnostic only. Main never initializes this helper on a normal drive. */
final class RoadProfile {
    @Name("pz.RoadClockAnchor")
    @Label("Road monotonic clock anchor")
    @StackTrace(false)
    public static final class ClockAnchor extends Event {
        public String label, owner;
        public long nanoBefore, nanoAfter, threadId, processId, recordingId;
    }

    private final Path cache;
    private final Thread ownerThread;
    private final String owner;
    private final Recording recording;
    private final ThreadMXBean cpu;
    private final long[] frameCpu, swapCpu;
    private final long gameThreadId;
    private long swapThreadId;
    private boolean finished;

    RoadProfile(Path cache, Thread ownerThread, int capacity) throws Exception {
        this.cache = cache.toRealPath();
        this.ownerThread = ownerThread;
        owner = System.getProperty("pz.drivingPerf.jfr.owner", "");
        if (Thread.currentThread() != ownerThread || !owner.matches("[0-9a-f]{32}"))
            throw new IllegalStateException("Missing owned road JFR identity");
        var recordings = FlightRecorder.getFlightRecorder().getRecordings().stream()
                .filter(r -> r.getName().equals("pz-road-" + owner)).toList();
        if (recordings.size() != 1) throw new IllegalStateException("Expected one launch-owned road JFR");
        recording = recordings.getFirst();
        checkRecording();
        cpu = ManagementFactory.getThreadMXBean();
        if (!cpu.isCurrentThreadCpuTimeSupported() || !cpu.isThreadCpuTimeEnabled())
            throw new IllegalStateException("Enabled current-thread CPU timing required for road JFR");
        frameCpu = new long[capacity];
        swapCpu = new long[capacity];
        gameThreadId = ownerThread.threadId();
    }

    private void checkRecording() throws java.io.IOException {
        if (recording.getState() != RecordingState.RUNNING || !recording.isToDisk()
                || recording.getDestination() == null
                || !recording.getDestination().toAbsolutePath().getParent().toRealPath()
                        .resolve(recording.getDestination().getFileName()).equals(cache.resolve("road-runtime.jfr")))
            throw new IllegalStateException("Road JFR recording is not owned by this cache");
    }

    void anchor(String label) {
        if (Thread.currentThread() != ownerThread || finished)
            throw new IllegalStateException("Road JFR owner thread required");
        ClockAnchor event = new ClockAnchor();
        if (!event.isEnabled()) throw new IllegalStateException("Required JFR clock event disabled");
        event.nanoBefore = System.nanoTime();
        event.begin();
        event.nanoAfter = System.nanoTime();
        event.label = label;
        event.threadId = Thread.currentThread().threadId();
        event.owner = owner;
        event.processId = ProcessHandle.current().pid();
        event.recordingId = recording.getId();
        event.commit();
    }

    void framed(int index) {
        if (Thread.currentThread() != ownerThread || finished)
            throw new IllegalStateException("Road game timing thread changed");
        frameCpu[index] = currentCpuTime();
    }

    void swapped(int index) {
        long id = Thread.currentThread().threadId();
        if (finished || swapThreadId != 0 && swapThreadId != id)
            throw new IllegalStateException("Road swap timing thread changed");
        swapThreadId = id;
        swapCpu[index] = currentCpuTime();
    }

    private long currentCpuTime() {
        long value = cpu.getCurrentThreadCpuTime();
        if (value < 0) throw new IllegalStateException("Road thread CPU timing unavailable");
        return value;
    }

    // Main calls this only after preserving the original frame CSV and census.
    void finish(long[] swapNs, int[] swapPhase, int swaps,
                long[] frameNs, int[] framePhase, int frames) throws Exception {
        anchor("finish");
        checkRecording();
        if (Files.exists(cache.resolve("road-measured.jfr")))
            throw new IllegalStateException("Road measured JFR already exists");
        try (BufferedWriter writer = Files.newBufferedWriter(cache.resolve("road-thread-cpu.csv"),
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            writer.write("channel,phase,nano_time,thread_cpu_ns,java_thread_id\n");
            for (int i = 0; i < swaps; i++)
                writer.write("swap,"+swapPhase[i]+","+swapNs[i]+","+swapCpu[i]+","+swapThreadId+"\n");
            for (int i = 0; i < frames; i++)
                writer.write("game,"+framePhase[i]+","+frameNs[i]+","+frameCpu[i]+","+gameThreadId+"\n");
        }
        recording.dump(cache.resolve("road-measured.jfr"));
        finished = true;
        System.out.println("[ROAD_JFR] DUMPED event=pz.RoadClockAnchor owner=" + owner
                + " recordingId=" + recording.getId() + " gameThread=" + gameThreadId + " swapThread=" + swapThreadId);
    }
}
