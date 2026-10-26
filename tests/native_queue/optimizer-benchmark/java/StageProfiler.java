package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Arrays;
import jdk.jfr.Category;
import jdk.jfr.Configuration;
import jdk.jfr.Description;
import jdk.jfr.Event;
import jdk.jfr.Label;
import jdk.jfr.Name;
import jdk.jfr.Recording;
import jdk.jfr.StackTrace;
import jdk.jfr.Timespan;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;

/** Explicitly enabled, disposable benchmark instrumentation; never changes game behavior. */
public final class StageProfiler {
    static final int LOGIC=0, RENDER=1, CHUNK=2, LOOT=3, LUA=4, TILES=5, UI=6, STAGES=7;
    private static final int CAPACITY=120000;
    private static final String[] NAMES={"logic","render","chunk","loot","lua","tiles","ui"};
    private static final Object swapLock=new Object();
    private static volatile boolean enabled;
    private static volatile long lastFrameId;
    private static Thread owner;
    private static ThreadMXBean cpu;
    private static boolean cpuAvailable, started, finished, frameOpen;
    private static long cpuStart;
    private static int framePhase, frameContacts, completed, omitted;
    private static double frameSpeed;
    private static Path cache;
    private static Recording recording;
    private static FrameEvent frameEvent;
    private static Timer timer;
    private static Rows rows;
    private static String diagnostic;

    private StageProfiler() {}

    public static void start(Path outputCache, Thread ownerThread) throws Exception {
        if (!Boolean.getBoolean("pz.drivingPerf.stageProfile")) return;
        if (started) throw new IllegalStateException("One stage profile per JVM");
        String expected=System.getProperty("pz.drivingPerf.cachedir", "");
        if (expected.isBlank() || ownerThread != Thread.currentThread()
                || !Path.of(expected).toRealPath().equals(outputCache.toRealPath()))
            throw new IllegalStateException("Stage profile requires the explicit owned benchmark cache/thread");
        Recording candidate=new Recording(Configuration.getConfiguration("profile"));
        try {
            candidate.setName("PZ driving stages");
            candidate.enable("jdk.FileRead").withThreshold(Duration.ofMillis(1));
            candidate.enable(FrameEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            candidate.enable(SwapEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            cache=outputCache.toRealPath(); owner=ownerThread;
            cpu=ManagementFactory.getThreadMXBean();
            cpuAvailable=cpu.isCurrentThreadCpuTimeSupported() && cpu.isThreadCpuTimeEnabled();
            timer=new Timer(); rows=new Rows(); frameEvent=new FrameEvent();
            candidate.start(); recording=candidate; started=true; enabled=true;
        } catch (Exception | Error failure) {
            candidate.close();
            throw failure;
        }
    }

    private static boolean owns() { return enabled && Thread.currentThread()==owner; }
    private static long cpuNow() { return cpuAvailable ? cpu.getCurrentThreadCpuTime() : -1; }
    private static void error(String message) { if (diagnostic==null) diagnostic=message; }

    public static void frameBegin(int phase, int contacts, double speed) {
        if (!owns() || phase<1 || phase>3 || diagnostic!=null || timer.error!=null) return;
        if (frameOpen) { error("Frame began before previous frame ended"); timer.cancel(); return; }
        if (completed==CAPACITY) { error("Stage frame buffer overflow"); return; }
        framePhase=phase; frameContacts=contacts; frameSpeed=speed;
        lastFrameId++;
        cpuStart=cpuNow();
        timer.begin(System.nanoTime());
        frameOpen=true; frameEvent.begin();
    }

    public static void frameEnd() {
        if (!owns() || !frameOpen) return;
        long now=System.nanoTime(), cpuEnd=cpuNow();
        frameOpen=false;
        if (!timer.complete(now)) { omitted++; return; }
        long cpuNs=cpuStart<0 || cpuEnd<cpuStart ? -1 : cpuEnd-cpuStart;
        rows.capture(completed, lastFrameId, framePhase, frameContacts, frameSpeed, timer, cpuNs);
        completed++;
        frameEvent.end();
        frameEvent.capture(lastFrameId, framePhase, frameContacts, frameSpeed, timer, cpuNs);
        frameEvent.commit();
    }

    /** A zero token means inactive/foreign-thread work. No allocation or file output per stage hook. */
    public static int enter(int category) {
        if (!owns() || !frameOpen || !timer.active) return 0;
        return timer.enter(category, System.nanoTime());
    }
    public static void exit(int token) {
        if (token==0 || !owns() || !frameOpen || !timer.active) return;
        timer.exit(token, System.nanoTime());
    }

    /** Render-thread instant marker, deliberately independent of the owner-thread timing stack. */
    public static void swapped(int phase, int contacts) {
        if (!enabled || phase<1 || phase>3) return;
        synchronized (swapLock) {
            if (!enabled) return;
            SwapEvent event=new SwapEvent();
            event.phase=phase; event.contacts=contacts;
            event.nanoTime=System.nanoTime(); event.lastFrameId=lastFrameId;
            event.commit();
        }
    }

    public static void finish() throws Exception {
        if (!started || finished) return;
        if (Thread.currentThread()!=owner) throw new IllegalStateException("Stage profile finish requires owner thread");
        synchronized (swapLock) { enabled=false; finished=true; }
        // OnTick may finish inside logic/Lua. Its trailing exits must be harmless; no partial frame is emitted.
        if (frameOpen) { omitted++; frameOpen=false; }
        timer.cancel();
        if (timer.error!=null) error(timer.error);
        if (completed==0) error("No complete stage frames");
        try {
            recording.stop(); recording.dump(cache.resolve("driving-stages.jfr"));
        } finally { recording.close(); }
        try (BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-stages.csv"))) {
            out.write("frame_id,phase,contacts,speed_kmh,nano_start,nano_end,wall_ns,cpu_ns");
            for (String name:NAMES) out.write(","+name+"_inclusive_ns,"+name+"_exclusive_ns,"+name+"_calls");
            out.write(",other_exclusive_ns\n");
            for (int i=0; i<completed; i++) {
                out.write(rows.ids[i]+","+rows.phases[i]+","+rows.contacts[i]+","+rows.speeds[i]+","
                        +rows.starts[i]+","+rows.ends[i]+","+rows.wall[i]+","+rows.cpu[i]);
                for (int stage=0; stage<STAGES; stage++)
                    out.write(","+rows.inclusive[stage][i]+","+rows.exclusive[stage][i]+","+rows.calls[stage][i]);
                out.write(","+rows.other[i]+"\n");
            }
        }
        String status="complete_frames="+completed+" omitted_incomplete_frames="+omitted
                +" cpu_supported_and_enabled="+cpuAvailable+" diagnostic="+(diagnostic==null ? "none" : diagnostic)
                +" phase_contacts_speed=snapshot-at-frame-begin exclusive_plus_other=wall inclusive=category-union-nonadditive";
        Files.writeString(cache.resolve("driving-stages-status.txt"), status+"\n");
        System.out.println("[DRIVING_STAGES] "+status);
        if (diagnostic!=null) throw new IllegalStateException("Invalid stage profile: "+diagnostic);
    }

    /** Primitive, deterministic state machine; timestamps are supplied for focused checks. */
    static final class Timer {
        static final int MAX_DEPTH=256;
        final long[] inclusive=new long[STAGES], exclusive=new long[STAGES], inclusiveStart=new long[STAGES];
        final int[] calls=new int[STAGES], activeDepth=new int[STAGES], stack=new int[MAX_DEPTH], tokens=new int[MAX_DEPTH];
        int depth, serial;
        long start, end, last, other;
        boolean active;
        String error;
        void begin(long now) {
            if (active) { fail("Unbalanced frame begin"); return; }
            if (error!=null) return;
            Arrays.fill(inclusive,0); Arrays.fill(exclusive,0); Arrays.fill(calls,0); Arrays.fill(activeDepth,0);
            depth=0; other=0; start=last=now; end=0; active=true;
        }
        private boolean advance(long now) {
            if (now<last) { fail("Nonmonotonic stage timestamp"); return false; }
            long elapsed=now-last;
            if (depth==0) other+=elapsed; else exclusive[stack[depth-1]]+=elapsed;
            last=now; return true;
        }
        int enter(int stage, long now) {
            if (!active) return 0;
            if (stage<0 || stage>=STAGES || depth==MAX_DEPTH || serial==Integer.MAX_VALUE) {
                fail("Stage stack/category/token overflow"); return 0;
            }
            if (!advance(now)) return 0;
            if (activeDepth[stage]++==0) inclusiveStart[stage]=now;
            calls[stage]++;
            stack[depth]=stage; tokens[depth]=++serial;
            return tokens[depth++];
        }
        void exit(int token, long now) {
            if (token==0 || !active) return;
            if (depth==0 || tokens[depth-1]!=token) { fail("Unbalanced stage exit"); return; }
            if (!advance(now)) return;
            int stage=stack[--depth];
            if (--activeDepth[stage]==0) inclusive[stage]+=now-inclusiveStart[stage];
        }
        boolean complete(long now) {
            if (!active) return false;
            if (depth!=0) { fail("Unbalanced stage stack at frame end"); return false; }
            if (!advance(now)) return false;
            end=now; active=false; return true;
        }
        void cancel() { active=false; depth=0; Arrays.fill(activeDepth,0); }
        private void fail(String reason) { if (error==null) error=reason; cancel(); }
    }

    private static final class Rows {
        final long[] ids=new long[CAPACITY], starts=new long[CAPACITY], ends=new long[CAPACITY], wall=new long[CAPACITY], cpu=new long[CAPACITY], other=new long[CAPACITY];
        final int[] phases=new int[CAPACITY], contacts=new int[CAPACITY];
        final double[] speeds=new double[CAPACITY];
        final long[][] inclusive=new long[STAGES][CAPACITY], exclusive=new long[STAGES][CAPACITY];
        final int[][] calls=new int[STAGES][CAPACITY];
        void capture(int i,long id,int phase,int contact,double speed,Timer t,long cpuNs) {
            ids[i]=id; phases[i]=phase; contacts[i]=contact; speeds[i]=speed;
            starts[i]=t.start; ends[i]=t.end; wall[i]=t.end-t.start; cpu[i]=cpuNs; other[i]=t.other;
            for (int s=0;s<STAGES;s++) { inclusive[s][i]=t.inclusive[s]; exclusive[s][i]=t.exclusive[s]; calls[s][i]=t.calls[s]; }
        }
    }

    @Name("pz.driving.Frame") @Label("Driving completed frame") @Category({"PZ","Driving"}) @StackTrace(false)
    @Description("Phase/contacts/speed at begin. Exclusive buckets plus other equal wall. Inclusive unions dedup recursion and are not additive.")
    public static final class FrameEvent extends Event {
        public long frameId, nanoStart, nanoEnd;
        public int phase, contacts;
        public double speedKmh;
        @Timespan(Timespan.NANOSECONDS) public long wallNs, cpuNs, otherExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long logicInclusiveNs, logicExclusiveNs, renderInclusiveNs, renderExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long chunkInclusiveNs, chunkExclusiveNs, lootInclusiveNs, lootExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long luaInclusiveNs, luaExclusiveNs, tilesInclusiveNs, tilesExclusiveNs, uiInclusiveNs, uiExclusiveNs;
        public int logicCalls, renderCalls, chunkCalls, lootCalls, luaCalls, tilesCalls, uiCalls;
        void capture(long id,int p,int contact,double speed,Timer t,long cpuTime) {
            frameId=id; phase=p; contacts=contact; speedKmh=speed; nanoStart=t.start; nanoEnd=t.end;
            wallNs=t.end-t.start; cpuNs=cpuTime; otherExclusiveNs=t.other;
            logicInclusiveNs=t.inclusive[LOGIC]; logicExclusiveNs=t.exclusive[LOGIC]; logicCalls=t.calls[LOGIC];
            renderInclusiveNs=t.inclusive[RENDER]; renderExclusiveNs=t.exclusive[RENDER]; renderCalls=t.calls[RENDER];
            chunkInclusiveNs=t.inclusive[CHUNK]; chunkExclusiveNs=t.exclusive[CHUNK]; chunkCalls=t.calls[CHUNK];
            lootInclusiveNs=t.inclusive[LOOT]; lootExclusiveNs=t.exclusive[LOOT]; lootCalls=t.calls[LOOT];
            luaInclusiveNs=t.inclusive[LUA]; luaExclusiveNs=t.exclusive[LUA]; luaCalls=t.calls[LUA];
            tilesInclusiveNs=t.inclusive[TILES]; tilesExclusiveNs=t.exclusive[TILES]; tilesCalls=t.calls[TILES];
            uiInclusiveNs=t.inclusive[UI]; uiExclusiveNs=t.exclusive[UI]; uiCalls=t.calls[UI];
        }
    }
    @Name("pz.driving.Swap") @Label("Driving render swap") @Category({"PZ","Driving"}) @StackTrace(false)
    public static final class SwapEvent extends Event {
        public int phase, contacts;
        public long nanoTime, lastFrameId;
    }

    @Patch(className="zombie.GameWindow", methodName="logic", strictMatch=true)
    public static class Logic {
        @Patch.OnEnter public static void enter(@Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(LOGIC); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.GameWindow", methodName="renderInternal", strictMatch=true)
    public static class Render {
        @Patch.OnEnter public static void enter(@Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(RENDER); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.iso.IsoChunk", methodName="doLoadGridsquare", strictMatch=true)
    public static class Chunk {
        @Patch.OnEnter public static void enter(@Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(CHUNK); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.inventory.ItemPickerJava", methodName="fillContainer", strictMatch=true)
    public static class Loot {
        // Explicit native arguments are required by ZombieBuddy strict signature matching.
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ItemContainer container, @Patch.Argument(1) IsoPlayer player,
                @Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(LOOT); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="se.krka.kahlua.vm.KahluaThread", methodName="luaMainloop", strictMatch=true)
    public static class Lua {
        @Patch.OnEnter public static void enter(@Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(LUA); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.iso.fboRenderChunk.FBORenderCell", methodName="RenderTiles", strictMatch=true)
    public static class Tiles {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) int minHeight, @Patch.Argument(1) int maxHeight,
                @Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(TILES); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.ui.UIManager", methodName="render", strictMatch=true)
    public static class UIRender {
        @Patch.OnEnter public static void enter(@Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(UI); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.ui.UIManager", methodName="update", strictMatch=true)
    public static class UIUpdate {
        @Patch.OnEnter public static void enter(@Patch.Local("drivingStageToken") int token) { token=StageProfiler.enter(UI); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("drivingStageToken") int token) { StageProfiler.exit(token); }
    }
}
