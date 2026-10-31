package toolkit.lootresolved.bootstrap;

import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import jdk.jfr.*;
import jdk.jfr.consumer.*;

/** Sparse process-local JFR from initial admission, never a live callback logger. */
public final class OperationsTelemetry {
    private static Recording recording;
    public static final List<String> EVENTS=List.of("jdk.Compilation","jdk.Deoptimization","jdk.GarbageCollection","jdk.GCPhasePause","jdk.SafepointBegin","jdk.DataLoss");
    @Name("pz.loot.RollWindow") @Label("Owned whole roll window") @StackTrace(false)
    public static final class Window extends Event {
        public long windowId;
        public String group,variant,phase;
        public int pair,batch;
    }
    public static void start() {
        if (recording!=null) throw new IllegalStateException("operations-JFR-already-started");
        Set<String> known=new HashSet<>();
        for (EventType event:FlightRecorder.getFlightRecorder().getEventTypes()) known.add(event.getName());
        if (!known.containsAll(EVENTS)) throw new IllegalStateException("operations-JFR-events-unavailable");
        FlightRecorder.register(Window.class);
        recording=new Recording(); recording.setName("owned-loot-whole-roll"); recording.setMaxSize(128L*1024*1024);
        for (String event:EVENTS) recording.enable(event).withThreshold(Duration.ZERO);
        recording.enable("jdk.Deoptimization").withStackTrace();
        recording.enable("pz.loot.RollWindow").withoutStackTrace().withThreshold(Duration.ZERO);
        recording.start();
        Window sentinel=new Window(); sentinel.windowId=-2; sentinel.group="none"; sentinel.variant="none";
        sentinel.phase="admission"; sentinel.pair=-1; sentinel.batch=0; sentinel.begin(); sentinel.end(); sentinel.commit();
    }
    private static long nanos(java.time.Instant value) { return Math.addExact(Math.multiplyExact(value.getEpochSecond(),1_000_000_000L),value.getNano()); }
    private static String method(RecordedEvent event) {
        RecordedMethod method=event.getValue("method");
        return method==null?"none":method.getType().getName()+"."+method.getName()+method.getDescriptor();
    }
    public static Path finish(Path cache,int expectedWindows) throws Exception {
        if (recording==null || recording.getState()!=RecordingState.RUNNING) throw new IllegalStateException("operations-JFR-not-running");
        Path path=cache.resolve("loot-operations-"+ProcessHandle.current().pid()+".jfr");
        if (Files.exists(path,LinkOption.NOFOLLOW_LINKS)) throw new IllegalStateException("operations-JFR-output-exists");
        recording.stop(); recording.dump(path); recording.close();
        StringBuilder rows=new StringBuilder("kind\tstart_ns\tend_ns\tthread_id\tmethod\tlevel\tcompile_id\twindow_id\tdetail\n");
        long count=0; int sentinels=0; Set<Long> windows=new HashSet<>();
        try (RecordingFile file=new RecordingFile(path)) {
            while (file.hasMoreEvents()) {
                if (++count>200_000) throw new IllegalStateException("operations-JFR-event-bound");
                RecordedEvent event=file.readEvent(); String name=event.getEventType().getName();
                if (!EVENTS.contains(name) && !name.equals("pz.loot.RollWindow")) continue;
                RecordedThread thread=event.getThread(); long tid=thread==null?0:thread.getJavaThreadId();
                String method="none",detail="none"; int level=0,compile=0; long window=-1;
                if (name.equals("jdk.Compilation")) { method=method(event);level=event.getShort("compileLevel");compile=event.getInt("compileId");detail="success="+event.getBoolean("succeded")+",osr="+event.getBoolean("isOsr"); }
                if (name.equals("jdk.Deoptimization")) { method=method(event);compile=event.getInt("compileId");detail="reason="+event.getString("reason")+",action="+event.getString("action"); }
                if (name.equals("jdk.DataLoss")) detail="amount="+event.getLong("amount");
                if (name.equals("pz.loot.RollWindow")) {
                    window=event.getLong("windowId");
                    if (window==-2) sentinels++; else if (!windows.add(window)) throw new IllegalStateException("operations-JFR-duplicate-window");
                    detail="group="+event.getString("group")+",variant="+event.getString("variant")+",phase="+event.getString("phase")+",pair="+event.getInt("pair")+",batch="+event.getInt("batch");
                }
                rows.append(name).append('\t').append(nanos(event.getStartTime())).append('\t').append(nanos(event.getEndTime())).append('\t').append(tid)
                    .append('\t').append(method).append('\t').append(level).append('\t').append(compile).append('\t').append(window).append('\t').append(detail.replace('\t',' ').replace('\n',' ')).append('\n');
            }
        }
        Files.writeString(cache.resolve("loot-operations-events.tsv"),rows,StandardOpenOption.CREATE_NEW);
        if (sentinels!=1 || windows.size()!=expectedWindows) throw new IllegalStateException("operations-JFR-history-incomplete");
        for (long i=0;i<expectedWindows;i++) if (!windows.contains(i)) throw new IllegalStateException("operations-JFR-history-window-gap");
        return path;
    }
}
