package net.alexredby.equipworkprobe;

import java.lang.management.ManagementFactory;
import java.util.Arrays;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.pztoolkitjavapatches.EquipEventDispatchLogic;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaCallFrame;
import se.krka.kahlua.vm.Prototype;
import zombie.Lua.Event;
import zombie.Lua.LuaManager;

/** Disposable observation only. No game getters, Lua callbacks or authority APIs. */
public final class EquipWorkProbe {
    private static final long ORIGIN = System.nanoTime();
    static final int MOD_SOURCE=0, GAME_SOURCE=1, CAPTURE=2, FINGERPRINT=3,
        REGISTRY=4, DISPATCH_ENTER=5, DISPATCH_EXIT=6, EVENT=7;
    private static final String[] NAMES={"modSource", "gameSource", "captureMatch", "fingerprintTree",
        "registryMatches", "dispatchEnter", "dispatchExit", "eventTrigger"};
    private static final String[] SIGNATURES={
        "zombie.Lua.LuaManager$GlobalObject.getModFileReader(String,String,boolean)",
        "zombie.Lua.LuaManager$GlobalObject.getGameFilesInput(String)",
        "net.alexredby.pztoolkitjavapatches.LuaCaptureFacts.match(Object,Object)",
        "net.alexredby.pztoolkitjavapatches.LuaPrototypeFingerprint.tree(Prototype)",
        "net.alexredby.pztoolkitjavapatches.QueueEquipEventRegistry.matches(Object,KahluaTableImpl,String)",
        "net.alexredby.pztoolkitjavapatches.EquipEventDispatchLogic.enter(Event,KahluaTable)",
        "net.alexredby.pztoolkitjavapatches.EquipEventDispatchLogic.exit(Scope)",
        "zombie.Lua.Event.trigger(KahluaTable,LuaCaller,Object[])"};
    private static final int DEPTH=256, PATHS=128;
    private static final long[] calls=new long[NAMES.length], completed=new long[NAMES.length],
        inclusive=new long[NAMES.length], self=new long[NAMES.length], maximum=new long[NAMES.length];
    private static final int[] categories=new int[DEPTH];
    private static final long[] starts=new long[DEPTH], children=new long[DEPTH];
    private static final String[] sourceMods=new String[PATHS], sourcePaths=new String[PATHS];
    private static final long[] sourceCounts=new long[PATHS];
    private static final boolean[] signatureAvailable=new boolean[NAMES.length];
    private static final com.sun.management.ThreadMXBean ALLOCATION=allocationBean();
    private static volatile boolean active;
    private static volatile long ownerId;
    private static KahluaThread luaOwner;
    private static String stage="", diagnostic="";
    private static int depth, pathCount;
    private static long phaseStart, phaseEnd, allocatedStart=-1, allocatedEnd=-1,
        droppedCalls, droppedPaths, discardedOpen;
    private EquipWorkProbe() {}

    private static com.sun.management.ThreadMXBean allocationBean() {
        var bean=ManagementFactory.getThreadMXBean();
        return bean instanceof com.sun.management.ThreadMXBean value ? value : null;
    }
    private static long allocationNow() {
        try {
            return ALLOCATION!=null && ALLOCATION.isThreadAllocatedMemorySupported()
                && ALLOCATION.isThreadAllocatedMemoryEnabled()
                ? ALLOCATION.getThreadAllocatedBytes(Thread.currentThread().threadId()) : -1;
        } catch (RuntimeException ignored) { return -1; }
    }
    static long nowNs() { return System.nanoTime()-ORIGIN+1; }
    public static double nowMs() { return (System.nanoTime()-ORIGIN)/1_000_000.0; }
    private static boolean owns() { return active && Thread.currentThread().threadId()==ownerId; }

    /** Boundaries are invoked only by the supplied Lua controls, not timed advice. */
    static boolean mark(KahluaThread thread, String next) {
        long id=Thread.currentThread().threadId();
        if (thread==null || thread.debugOwnerThread!=Thread.currentThread()
                || active && (ownerId!=id || luaOwner!=thread)) return false;
        if (next==null || next.isEmpty()) {
            if (ownerId!=id || active && luaOwner!=thread) return false;
            phaseEnd=nowNs(); allocatedEnd=allocationNow();
            active=false; luaOwner=null;
            discardedOpen+=depth; depth=0;
            return true;
        }
        if (next.length()>128) return false;
        active=false;
        Arrays.fill(calls,0); Arrays.fill(completed,0); Arrays.fill(inclusive,0);
        Arrays.fill(self,0); Arrays.fill(maximum,0); Arrays.fill(sourceCounts,0);
        Arrays.fill(sourceMods,null); Arrays.fill(sourcePaths,null);
        discardedOpen=depth; depth=0; pathCount=0; droppedCalls=0; droppedPaths=0;
        diagnostic=""; stage=next; ownerId=id; luaOwner=thread;
        phaseEnd=0; allocatedEnd=-1; allocatedStart=allocationNow(); phaseStart=nowNs();
        active=true;
        return true;
    }

    /** Primitive timestamp token and preallocated stack; no per-call scope object. */
    public static long begin(int category) {
        if (!owns()) return 0;
        if (depth==DEPTH) { droppedCalls++; return 0; }
        long started=nowNs();
        categories[depth]=category; starts[depth]=started; children[depth]=0; depth++;
        calls[category]++;
        return started;
    }
    public static void end(int category, long started) {
        if (started==0 || !owns() || started<phaseStart) return;
        long ended=nowNs();
        if (depth==0 || categories[depth-1]!=category || starts[depth-1]!=started) {
            diagnostic="hook-stack-mismatch"; active=false; luaOwner=null; phaseEnd=ended;
            allocatedEnd=allocationNow(); discardedOpen+=depth; depth=0; return;
        }
        int slot=--depth;
        long elapsed=ended-started;
        inclusive[category]+=elapsed; self[category]+=Math.max(0,elapsed-children[slot]);
        maximum[category]=Math.max(maximum[category],elapsed); completed[category]++;
        if (depth>0) children[depth-1]+=elapsed;
    }
    /** Count relative Lua source-open attempts, retaining only immutable strings. */
    public static void source(String mod, String path) {
        if (!owns() || path==null || !path.startsWith("media/lua/") || path.length()>512) return;
        String id=mod==null ? "native" : mod;
        if (id.length()>128) { droppedPaths++; return; }
        for (int i=0;i<pathCount;i++) if (id.equals(sourceMods[i]) && path.equals(sourcePaths[i])) {
            sourceCounts[i]++; return;
        }
        if (pathCount==PATHS) { droppedPaths++; return; }
        sourceMods[pathCount]=id; sourcePaths[pathCount]=path; sourceCounts[pathCount]=1; pathCount++;
    }
    private static boolean accepts(KahluaThread thread) {
        return ownerId==Thread.currentThread().threadId() && (!active || luaOwner==thread);
    }
    /** Allocation/clock samples precede table creation, excluding snapshot output allocations. */
    static KahluaTable snapshot(KahluaThread thread) {
        if (!accepts(thread)) return null;
        long end=active ? nowNs() : phaseEnd;
        long allocated=active ? allocationNow() : allocatedEnd;
        var result=new J2SEPlatform().newTable();
        result.rawset("schema",1.0); result.rawset("stage",stage); result.rawset("active",active);
        result.rawset("elapsedMs",(end-phaseStart)/1_000_000.0);
        result.rawset("allocatedBytesAvailable",allocatedStart>=0 && allocated>=allocatedStart);
        result.rawset("allocatedBytes",allocatedStart>=0 && allocated>=allocatedStart ? (double)(allocated-allocatedStart) : -1.0);
        result.rawset("openDepth",(double)depth); result.rawset("discardedOpen",(double)discardedOpen);
        result.rawset("droppedCalls",(double)droppedCalls); result.rawset("droppedPaths",(double)droppedPaths);
        result.rawset("diagnostic",diagnostic); result.rawset("sourcePathCount",(double)pathCount);
        result.rawset("timer","relative-System.nanoTime"); result.rawset("source","disposable-jvm-probe");
        result.rawset("threadScope","mark-caller-Java-thread; controls-bind-originating-Kahlua-thread");
        result.rawset("timingScope","completed-advice-intervals; inclusive-is-nonadditive; self-excludes-nested-instrumented-intervals");
        result.rawset("sourceScope","media/lua-relative-source-open-attempts; no-reader-wrapping-or-byte-count");
        result.rawset("overheadCorrected",false); result.rawset("perCallScopeAllocation",false);
        result.rawset("overhead","two-nanoTime-samples-and-primitive-stack-per-completed-hook; source-path-registration; phase-allocation-samples; current-snapshot-output-excluded; earlier-active-snapshot-output-remains-in-phase");
        result.rawset("inactiveHookOverhead","unmarked-advice-still-checks-owner; use-the-same-probe-in-comparison-runs");
        result.rawset("adviceOrderLimit","Event-trigger-interval-may-exclude-sibling-advice; dispatch-helper-intervals-reported-separately");
        result.rawset("retention","primitive-stats-and-immutable-source-strings; no-Event-closure-action-arguments");
        result.rawset("depthCapacity",(double)DEPTH); result.rawset("pathCapacity",(double)PATHS);
        for (int i=0;i<NAMES.length;i++) {
            String name=NAMES[i];
            result.rawset(name+"Calls",(double)calls[i]); result.rawset(name+"Completed",(double)completed[i]);
            result.rawset(name+"InclusiveNs",(double)inclusive[i]); result.rawset(name+"SelfNs",(double)self[i]);
            result.rawset(name+"MaxNs",(double)maximum[i]); result.rawset(name+"Observed",calls[i]>0);
            result.rawset(name+"SignatureAvailable",signatureAvailable[i]); result.rawset(name+"Signature",SIGNATURES[i]);
        }
        for (int i=0;i<pathCount;i++) {
            String name="source"+(i+1);
            result.rawset(name+"Mod",sourceMods[i]); result.rawset(name+"Path",sourcePaths[i]);
            result.rawset(name+"Count",(double)sourceCounts[i]);
        }
        return result;
    }
    private static boolean signature(String owner, String name, Class<?>... arguments) {
        try { Class.forName(owner,false,EquipWorkProbe.class.getClassLoader()).getDeclaredMethod(name,arguments); return true; }
        catch (ReflectiveOperationException | LinkageError failure) { return false; }
    }
    private static void signatures() {
        String base="net.alexredby.pztoolkitjavapatches.";
        signatureAvailable[MOD_SOURCE]=signature("zombie.Lua.LuaManager$GlobalObject","getModFileReader",String.class,String.class,boolean.class);
        signatureAvailable[GAME_SOURCE]=signature("zombie.Lua.LuaManager$GlobalObject","getGameFilesInput",String.class);
        signatureAvailable[CAPTURE]=signature(base+"LuaCaptureFacts","match",Object.class,Object.class);
        signatureAvailable[FINGERPRINT]=signature(base+"LuaPrototypeFingerprint","tree",Prototype.class);
        signatureAvailable[REGISTRY]=signature(base+"QueueEquipEventRegistry","matches",Object.class,KahluaTableImpl.class,String.class);
        signatureAvailable[DISPATCH_ENTER]=signature(base+"EquipEventDispatchLogic","enter",Event.class,KahluaTable.class);
        signatureAvailable[DISPATCH_EXIT]=signature(base+"EquipEventDispatchLogic","exit",EquipEventDispatchLogic.Scope.class);
        signatureAvailable[EVENT]=signature("zombie.Lua.Event","trigger",KahluaTable.class,LuaCaller.class,Object[].class);
    }
    public static final class Clock implements JavaFunction {
        @Override public int call(LuaCallFrame frame,int arguments) { return frame.push(nowMs()); }
    }
    public static final class Mark implements JavaFunction {
        @Override public int call(LuaCallFrame frame,int arguments) {
            if (arguments!=1) return frame.push(false);
            Object value=frame.get(0);
            return frame.push((value==null || value instanceof String) && mark(frame.getThread(),(String)value));
        }
    }
    public static final class Snapshot implements JavaFunction {
        @Override public int call(LuaCallFrame frame,int arguments) {
            if (arguments!=0) return frame.pushNil();
            return frame.push(snapshot(frame.getThread()));
        }
    }
    private static final JavaFunction CLOCK=new Clock(), MARK=new Mark(), SNAPSHOT=new Snapshot();
    public static void install(KahluaTable environment) {
        signatures();
        environment.rawset("equipWorkNowMs",CLOCK); environment.rawset("equipWorkMark",MARK);
        environment.rawset("equipWorkSnapshot",SNAPSHOT);
    }
    @Patch(className="zombie.gameStates.GameLoadingState",methodName="exit",warmUp=true,strictMatch=true)
    public static class Install {
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit() { if (LuaManager.env!=null) EquipWorkProbe.install(LuaManager.env); }
    }
    @Patch(className="zombie.Lua.LuaManager$GlobalObject",methodName="getModFileReader",warmUp=true,strictMatch=true)
    public static class ModSource {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) String mod,@Patch.Argument(1) String path,@Patch.Argument(2) boolean create,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(MOD_SOURCE); EquipWorkProbe.source(mod,path); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(MOD_SOURCE,stamp); }
    }
    @Patch(className="zombie.Lua.LuaManager$GlobalObject",methodName="getGameFilesInput",warmUp=true,strictMatch=true)
    public static class GameSource {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) String path,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(GAME_SOURCE); EquipWorkProbe.source(null,path); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(GAME_SOURCE,stamp); }
    }
    @Patch(className="net.alexredby.pztoolkitjavapatches.LuaCaptureFacts",methodName="match",warmUp=true,strictMatch=true)
    public static class Capture {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Object callback,@Patch.Argument(1) Object recipe,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(CAPTURE); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(CAPTURE,stamp); }
    }
    @Patch(className="net.alexredby.pztoolkitjavapatches.LuaPrototypeFingerprint",methodName="tree",warmUp=true,strictMatch=true)
    public static class Fingerprint {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Prototype prototype,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(FINGERPRINT); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(FINGERPRINT,stamp); }
    }
    @Patch(className="net.alexredby.pztoolkitjavapatches.QueueEquipEventRegistry",methodName="matches",warmUp=true,strictMatch=true)
    public static class Registry {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Object event,@Patch.Argument(1) KahluaTableImpl supplied,@Patch.Argument(2) String name,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(REGISTRY); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(REGISTRY,stamp); }
    }
    @Patch(className="net.alexredby.pztoolkitjavapatches.EquipEventDispatchLogic",methodName="enter",warmUp=true,strictMatch=true)
    public static class DispatchEnter {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) Event event,@Patch.Argument(1) KahluaTable environment,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(DISPATCH_ENTER); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(DISPATCH_ENTER,stamp); }
    }
    @Patch(className="net.alexredby.pztoolkitjavapatches.EquipEventDispatchLogic",methodName="exit",warmUp=true,strictMatch=true)
    public static class DispatchExit {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) EquipEventDispatchLogic.Scope scope,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(DISPATCH_EXIT); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(DISPATCH_EXIT,stamp); }
    }
    @Patch(className="zombie.Lua.Event",methodName="trigger",warmUp=true,strictMatch=true)
    public static class EventTrigger {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) KahluaTable environment,@Patch.Argument(1) LuaCaller caller,@Patch.Argument(2) Object[] arguments,
                @Patch.Local("equipWorkStamp") long stamp) { stamp=EquipWorkProbe.begin(EVENT); }
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class)
        public static void exit(@Patch.Local("equipWorkStamp") long stamp) { EquipWorkProbe.end(EVENT,stamp); }
    }
}
