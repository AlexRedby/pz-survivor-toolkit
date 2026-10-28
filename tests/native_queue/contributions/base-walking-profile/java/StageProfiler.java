package toolkit.basewalking;

import java.io.BufferedWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Arrays;
import java.util.IdentityHashMap;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.Prototype;
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

/** Explicitly enabled, disposable stationary/walking/post-stationary instrumentation; never changes game behavior. */
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
    private static CallbackTimer callbacks;
    private static String diagnostic;
    private static final boolean[] adviceObserved=new boolean[STAGES];
    private static final String[] METHODS={"GameWindow.logic", "GameWindow.renderInternal", "IsoChunk.doLoadGridsquare",
        "ItemPickerJava.fillContainer", "KahluaThread.luaMainloop", "FBORenderCell.RenderTiles", "UIManager.render/update"};

    /** Called only from actual advice; markers prove invocation, not mere patch discovery. */
    public static int adviceEnter(int category) {
        if (owns() && frameOpen && !adviceObserved[category]) {
            adviceObserved[category]=true;
            System.out.println("[BASE_WALKING_PROFILE] HOOK_ACTIVE stage="+NAMES[category]+" method="+METHODS[category]);
        }
        return enter(category);
    }


    private StageProfiler() {}

    public static void start(Path outputCache, Thread ownerThread) throws Exception {
        if (!Boolean.getBoolean("pz.baseWalking.enabled")) return;
        if (started) throw new IllegalStateException("One stage profile per JVM");
        String expected=System.getProperty("pz.baseWalking.cachedir", "");
        if (expected.isBlank() || ownerThread != Thread.currentThread()
                || !Path.of(expected).toRealPath().equals(outputCache.toRealPath()))
            throw new IllegalStateException("Stage profile requires the explicit owned benchmark cache/thread");
        for (String name: new String[]{"base-walking-stages.jfr", "base-walking-stages.csv", "base-walking-stages-status.txt", "base-walking-lua-callbacks.csv"})
            if (Files.exists(outputCache.resolve(name))) throw new IllegalStateException("Existing stage output: "+name);
        Recording candidate=new Recording(Configuration.getConfiguration("profile"));
        try {
            candidate.setName("PZ base walking stages");
            candidate.enable("jdk.FileRead").withThreshold(Duration.ofMillis(1));
            candidate.enable(FrameEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            candidate.enable(SwapEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            candidate.enable(LuaCallbackEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            cache=outputCache.toRealPath(); owner=ownerThread;
            cpu=ManagementFactory.getThreadMXBean();
            cpuAvailable=cpu.isCurrentThreadCpuTimeSupported() && cpu.isThreadCpuTimeEnabled();
            timer=new Timer(); rows=new Rows(); callbacks=new CallbackTimer(); frameEvent=new FrameEvent();
            candidate.start(); recording=candidate; started=true; enabled=true;
        } catch (Exception | Error failure) {
            candidate.close();
            throw failure;
        }
    }

    private static boolean owns() { return enabled && Thread.currentThread()==owner; }
    public static long currentFrameId() { return owns() && frameOpen ? lastFrameId : 0; }
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
        callbacks.begin(phase);
        frameOpen=true; frameEvent.begin();
    }

    public static void frameEnd() {
        if (!owns() || !frameOpen) return;
        long now=System.nanoTime(), cpuEnd=cpuNow();
        frameOpen=false;
        if (!timer.complete(now)) { callbacks.cancel(); omitted++; return; }
        if (!callbacks.complete(lastFrameId)) { error(callbacks.error); omitted++; return; }
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

    /** Lua-to-Java-to-Lua reentry is nested; ordinary Lua calls stay within this entry closure. */
    public static int luaEnter(KahluaThread thread) {
        if (!owns() || !frameOpen || !timer.active) return 0;
        Prototype prototype=null;
        if (thread!=null && thread.currentCoroutine!=null) {
            var frame=thread.currentCoroutine.currentCallFrame();
            if (frame!=null && frame.closure!=null) prototype=frame.closure.prototype;
        }
        return callbacks.enter(prototype,System.nanoTime());
    }
    public static void luaExit(int token) {
        if (token==0 || !owns() || !frameOpen || !timer.active) return;
        callbacks.exit(token,System.nanoTime());
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
        timer.cancel(); callbacks.cancel();
        if (callbacks.error!=null) error(callbacks.error);
        if (timer.error!=null) error(timer.error);
        if (completed==0) error("No complete stage frames");
        try {
            recording.stop(); recording.dump(cache.resolve("base-walking-stages.jfr"));
        } finally { recording.close(); }
        try (BufferedWriter out=Files.newBufferedWriter(cache.resolve("base-walking-stages.csv"))) {
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
        callbacks.writeCsv(cache.resolve("base-walking-lua-callbacks.csv"));
        String status="complete_frames="+completed+" omitted_incomplete_frames="+omitted
                +" cpu_supported_and_enabled="+cpuAvailable+" diagnostic="+(diagnostic==null ? "none" : diagnostic)
                +" lua_callback_labels="+callbacks.labelCount+" lua_callback_overflow_calls="+callbacks.overflowCalls+" lua_callback_slow_events_dropped="+callbacks.slowDropped
                +" lua_callback_scope=luaMainloop-entry-closure-completed-frames-only nested_lua_callback_inclusive=nonadditive"
                +" phase_contacts_speed=snapshot-at-frame-begin exclusive_plus_other=wall inclusive=category-union-nonadditive phase1=stationary phase2=walking phase3=post-stationary";
        Files.writeString(cache.resolve("base-walking-stages-status.txt"), status+"\n");
        System.out.println("[BASE_WALKING_STAGES] "+status);
        for (int stage=0;stage<STAGES;stage++) {
            long calls=0;
            for (int row=0;row<completed;row++) calls+=rows.calls[stage][row];
            System.out.println("[BASE_WALKING_PROFILE] HOOK_COUNTS stage="+NAMES[stage]+" advice_observed="+adviceObserved[stage]+" calls="+calls);
        }
        if (diagnostic!=null) throw new IllegalStateException("Invalid stage profile: "+diagnostic);
    }

    /** Bounded entry-closure timing. Frame-local rows are committed only with a complete frame. */
    static final class CallbackTimer {
        static final int MAX_LABELS=2048, MAX_DEPTH=256, MAX_SLOW=128;
        final int[] slowLabels=new int[MAX_SLOW];
        final long[] slowStarts=new long[MAX_SLOW], slowInclusive=new long[MAX_SLOW], slowExclusive=new long[MAX_SLOW];
        int slowCount; long slowDropped;
        final IdentityHashMap<Prototype,Integer> prototypes=new IdentityHashMap<>();
        final String[] sources=new String[MAX_LABELS], names=new String[MAX_LABELS];
        final int[] firstLines=new int[MAX_LABELS], labels=new int[MAX_DEPTH], tokens=new int[MAX_DEPTH];
        final long[] starts=new long[MAX_DEPTH], children=new long[MAX_DEPTH];
        final long[] pendingCalls=new long[MAX_LABELS], pendingInclusive=new long[MAX_LABELS],
            pendingExclusive=new long[MAX_LABELS], pendingMax=new long[MAX_LABELS];
        final long[][] calls=new long[3][MAX_LABELS], inclusive=new long[3][MAX_LABELS],
            exclusive=new long[3][MAX_LABELS], max=new long[3][MAX_LABELS];
        int labelCount=2, depth, serial, phase;
        long overflowCalls;
        boolean active;
        String error;
        CallbackTimer() { sources[0]="<unknown>"; names[0]="<unknown>"; sources[1]="<label-overflow>"; names[1]="<label-overflow>"; }
        void begin(int value) {
            if (active || value<1 || value>3) { fail("Invalid Lua callback frame begin"); return; }
            if (error!=null) return;
            phase=value-1; depth=0; active=true;
        }
        int label(Prototype p) {
            if (p==null) return 0;
            Integer existing=prototypes.get(p);
            if (existing!=null) return existing;
            if (labelCount==MAX_LABELS) { overflowCalls++; return 1; }
            int id=labelCount++;
            sources[id]=safe(p.filename!=null ? p.filename : p.file!=null ? p.file : p.name);
            names[id]=safe(p.name);
            firstLines[id]=p.lines!=null && p.lines.length>0 ? p.lines[0] : 0;
            prototypes.put(p,id); return id;
        }
        private static String safe(String value) { return value==null ? "<anonymous>" : value.substring(0,Math.min(1024,value.length())); }
        int enter(Prototype p,long now) {
            if (!active) return 0;
            if (depth==MAX_DEPTH || serial==Integer.MAX_VALUE || (depth>0 && now<starts[depth-1])) {
                fail("Lua callback stack/token/timestamp overflow"); return 0;
            }
            labels[depth]=label(p); starts[depth]=now; children[depth]=0; tokens[depth]=++serial;
            return tokens[depth++];
        }
        void exit(int token,long now) {
            if (token==0 || !active) return;
            if (depth==0 || tokens[depth-1]!=token) { fail("Unbalanced Lua callback exit"); return; }
            int i=--depth, id=labels[i]; long elapsed=now-starts[i];
            if (elapsed<children[i]) { fail("Nonmonotonic Lua callback timestamp"); return; }
            pendingCalls[id]++; pendingInclusive[id]+=elapsed; pendingExclusive[id]+=elapsed-children[i];
            pendingMax[id]=Math.max(pendingMax[id],elapsed);
            if (elapsed>=1_000_000) {
                if (slowCount<MAX_SLOW) {
                    slowLabels[slowCount]=id; slowStarts[slowCount]=starts[i];
                    slowInclusive[slowCount]=elapsed; slowExclusive[slowCount++]=elapsed-children[i];
                } else slowDropped++;
            }
            if (depth>0) children[depth-1]+=elapsed;
        }
        boolean complete() { return complete(0); }
        boolean complete(long frameId) {
            if (!active) return false;
            if (depth!=0) { fail("Unbalanced Lua callback frame end"); return false; }
            for (int id=0;id<labelCount;id++) {
                calls[phase][id]+=pendingCalls[id]; inclusive[phase][id]+=pendingInclusive[id];
                exclusive[phase][id]+=pendingExclusive[id]; max[phase][id]=Math.max(max[phase][id],pendingMax[id]);
            }
            if (frameId>0) for (int i=0;i<slowCount;i++) {
                int id=slowLabels[i]; LuaCallbackEvent event=new LuaCallbackEvent();
                event.frameId=frameId; event.phase=phase+1; event.source=sources[id]; event.function=names[id];
                event.firstLine=firstLines[id]; event.nanoStart=slowStarts[i]; event.nanoEnd=slowStarts[i]+slowInclusive[i];
                event.inclusiveNs=slowInclusive[i]; event.exclusiveNs=slowExclusive[i]; event.commit();
            }
            cancel(); return true;
        }
        void cancel() {
            active=false; depth=0; slowCount=0;
            Arrays.fill(pendingCalls,0); Arrays.fill(pendingInclusive,0); Arrays.fill(pendingExclusive,0); Arrays.fill(pendingMax,0);
        }
        private void fail(String reason) { if (error==null) error=reason; cancel(); }
        void writeCsv(Path file) throws Exception {
            try (BufferedWriter out=Files.newBufferedWriter(file)) {
                out.write("phase,source,function,first_line,calls,inclusive_ns,exclusive_ns,max_inclusive_ns\n");
                for (int p=0;p<3;p++) for (int id=0;id<labelCount;id++) if (calls[p][id]>0)
                    out.write((p+1)+","+quote(sources[id])+","+quote(names[id])+","+firstLines[id]+","+calls[p][id]
                        +","+inclusive[p][id]+","+exclusive[p][id]+","+max[p][id]+"\n");
            }
        }
        private static String quote(String text) { return "\""+text.replace("\"","\"\"")+"\""; }
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

    @Name("pz.baseWalking.Frame") @Label("Base walking completed frame") @Category({"PZ","BaseWalking"}) @StackTrace(false)
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
    @Name("pz.baseWalking.LuaCallback") @Label("Completed-frame slow Lua entry callback")
    @Category({"PZ","BaseWalking"}) @StackTrace(false)
    @Description("Entry closure of luaMainloop, >=1ms inclusive; nested inclusive time is nonadditive. Frame accepted before emission.")
    public static final class LuaCallbackEvent extends Event {
        public long frameId, nanoStart, nanoEnd;
        public int phase, firstLine;
        public String source, function;
        @Timespan(Timespan.NANOSECONDS) public long inclusiveNs, exclusiveNs;
    }
    @Name("pz.baseWalking.Swap") @Label("Base walking render swap") @Category({"PZ","BaseWalking"}) @StackTrace(false)
    public static final class SwapEvent extends Event {
        public int phase, contacts;
        public long nanoTime, lastFrameId;
    }

    @Patch(className="zombie.GameWindow", methodName="logic", strictMatch=true)
    public static class Logic {
        @Patch.OnEnter public static void enter(@Patch.Local("baseWalkingStageToken") int token) { token=StageProfiler.adviceEnter(LOGIC); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.GameWindow", methodName="renderInternal", strictMatch=true)
    public static class Render {
        @Patch.OnEnter public static void enter(@Patch.Local("baseWalkingStageToken") int token) { token=StageProfiler.adviceEnter(RENDER); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.iso.IsoChunk", methodName="doLoadGridsquare", strictMatch=true)
    public static class Chunk {
        @Patch.OnEnter public static void enter(@Patch.Local("baseWalkingStageToken") int token) { token=StageProfiler.adviceEnter(CHUNK); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.inventory.ItemPickerJava", methodName="fillContainer", strictMatch=true)
    public static class Loot {
        // Explicit native arguments are required by ZombieBuddy strict signature matching.
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ItemContainer container, @Patch.Argument(1) IsoPlayer player,
                @Patch.Local("baseWalkingStageToken") int token) { token=StageProfiler.adviceEnter(LOOT); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="se.krka.kahlua.vm.KahluaThread", methodName="luaMainloop", strictMatch=true)
    public static class Lua {
        @Patch.OnEnter public static void enter(@Patch.This KahluaThread thread,
                @Patch.Local("baseWalkingStageToken") int token, @Patch.Local("baseWalkingLuaToken") int callback) {
            token=StageProfiler.adviceEnter(LUA); callback=StageProfiler.luaEnter(thread);
        }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token,
                @Patch.Local("baseWalkingLuaToken") int callback) { StageProfiler.luaExit(callback); StageProfiler.exit(token); }
    }

    @Patch(className="zombie.iso.fboRenderChunk.FBORenderCell", methodName="RenderTiles", strictMatch=true)
    public static class Tiles {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) int minHeight, @Patch.Argument(1) int maxHeight,
                @Patch.Local("baseWalkingStageToken") int token) { token=StageProfiler.adviceEnter(TILES); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.ui.UIManager", methodName="render", strictMatch=true)
    public static class UIRender {
        @Patch.OnEnter public static void enter(@Patch.Local("baseWalkingStageToken") int token) { token=StageProfiler.adviceEnter(UI); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token) { StageProfiler.exit(token); }
    }

    @Patch(className="zombie.ui.UIManager", methodName="update", strictMatch=true)
    public static class UIUpdate {
        @Patch.OnEnter public static void enter(@Patch.Local("baseWalkingStageToken") int token) { token=StageProfiler.adviceEnter(UI); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingStageToken") int token) { StageProfiler.exit(token); }
    }
}
