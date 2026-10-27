package toolkit.basewalking;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.Map;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import jdk.jfr.consumer.RecordedEvent;
import jdk.jfr.consumer.RecordingFile;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.bytebuddy.jar.asm.*;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

/** Runs without launching or initializing game classes. */
public final class StageProfilerChecks {
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static void eq(long expected,long actual,String message) { check(expected==actual,message+": "+actual+" != "+expected); }
    private static void timerChecks() {
        StageProfiler.Timer t=new StageProfiler.Timer();
        t.begin(100);
        int logic=t.enter(StageProfiler.LOGIC,110), lua=t.enter(StageProfiler.LUA,120);
        int recursive=t.enter(StageProfiler.LUA,130);
        t.exit(recursive,140);
        int chunk=t.enter(StageProfiler.CHUNK,150); t.exit(chunk,170);
        t.exit(lua,180); t.exit(logic,190);
        check(t.complete(200),"balanced complete");
        eq(80,t.inclusive[StageProfiler.LOGIC],"logic inclusive");
        eq(60,t.inclusive[StageProfiler.LUA],"Lua recursive union");
        eq(20,t.inclusive[StageProfiler.CHUNK],"chunk inclusive");
        eq(20,t.exclusive[StageProfiler.LOGIC],"logic exclusive");
        eq(40,t.exclusive[StageProfiler.LUA],"Lua exclusive");
        eq(20,t.exclusive[StageProfiler.CHUNK],"chunk exclusive");
        eq(20,t.other,"uninstrumented exclusive");
        eq(2,t.calls[StageProfiler.LUA],"recursive invocation count");
        long sum=t.other; for (long n:t.exclusive) sum+=n; eq(t.end-t.start,sum,"exclusive partition");
        t.begin(300); logic=t.enter(StageProfiler.LOGIC,310); lua=t.enter(StageProfiler.LUA,320);
        recursive=t.enter(StageProfiler.LOGIC,330); t.exit(recursive,340); t.exit(lua,350); t.exit(logic,360);
        check(t.complete(370),"category reentry complete"); eq(50,t.inclusive[StageProfiler.LOGIC],"nonadjacent recursion union");
        t.begin(400); lua=t.enter(StageProfiler.LUA,410); t.cancel(); t.exit(lua,420);
        check(!t.complete(430) && t.error==null,"incomplete cancellation ignores trailing exits");
        t.begin(500); check(t.complete(510),"cancellation permits clean next frame");
        eq(10,t.other,"empty frame residual");
        t=new StageProfiler.Timer(); t.begin(0); logic=t.enter(StageProfiler.LOGIC,1); lua=t.enter(StageProfiler.LUA,2);
        t.exit(logic,3); check(t.error!=null && !t.active,"mismatched exit retained");
        t.begin(4); check(!t.active,"diagnostic cannot silently resume valid capture");
        t=new StageProfiler.Timer(); t.begin(0); t.enter(StageProfiler.LOGIC,1);
        check(!t.complete(2) && t.error!=null,"unfinished stack rejected");
        t=new StageProfiler.Timer(); t.begin(0);
        for (int i=0;i<StageProfiler.Timer.MAX_DEPTH;i++) check(t.enter(StageProfiler.LUA,i+1)!=0,"supported depth");
        eq(0,t.enter(StageProfiler.LUA,300),"overflow token"); check(t.error!=null && !t.active,"overflow retained");
        t=new StageProfiler.Timer(); t.begin(100); t.enter(StageProfiler.LOGIC,99);
        check(t.error!=null,"nonmonotonic time rejected");
    }
    private static Prototype prototype(String name) {
        Prototype p=new Prototype(); p.filename=name; p.name="callback"; p.lines=new int[]{42}; return p;
    }
    private static void callbackChecks(Path cache) throws Exception {
        StageProfiler.CallbackTimer t=new StageProfiler.CallbackTimer();
        Prototype outer=prototype("outer,\"quoted\".lua"), inner=prototype("inner.lua");
        t.begin(1); int a=t.enter(outer,100), b=t.enter(inner,110); t.exit(b,150); t.exit(a,200);
        check(t.complete(),"callback nested complete"); int ai=t.prototypes.get(outer), bi=t.prototypes.get(inner);
        eq(100,t.inclusive[0][ai],"parent callback inclusive"); eq(60,t.exclusive[0][ai],"parent callback exclusive");
        eq(40,t.inclusive[0][bi],"child inclusive"); eq(40,t.exclusive[0][bi],"child exclusive");
        t.begin(1); a=t.enter(outer,300); b=t.enter(outer,310); t.exit(b,330); t.exit(a,350); check(t.complete(),"recursive callback complete");
        eq(3,t.calls[0][ai],"recursive callback calls"); eq(170,t.inclusive[0][ai],"recursive callback inclusive is additive invocations");
        eq(110,t.exclusive[0][ai],"recursive callback exclusive is disjoint");
        t.begin(2); a=t.enter(outer,400); b=t.enter(inner,410); t.exit(b,420); t.cancel(); t.exit(a,430);
        t.begin(2); check(t.complete(),"partial callback cancellation permits next frame"); eq(0,t.calls[1][bi],"completed child of omitted frame discarded");
        t.writeCsv(cache.resolve("callback-unit.csv")); String csv=Files.readString(cache.resolve("callback-unit.csv"));
        check(csv.startsWith("phase,source,function,first_line,calls,inclusive_ns,exclusive_ns,max_inclusive_ns\n"),"callback CSV schema");
        check(csv.contains("\"outer,\"\"quoted\"\".lua\""),"callback CSV quotes escaped");
        t=new StageProfiler.CallbackTimer();t.begin(1);
        for(int i=0;i<StageProfiler.CallbackTimer.MAX_LABELS+3;i++){a=t.enter(prototype("p"+i),i*2L);t.exit(a,i*2L+1);}
        check(t.complete(),"bounded labels retain valid counts");eq(StageProfiler.CallbackTimer.MAX_LABELS,t.labelCount,"label cap");
        eq(StageProfiler.CallbackTimer.MAX_LABELS-2,t.prototypes.size(),"prototype map bound");check(t.calls[0][1]>0&&t.overflowCalls>0,"overflow attributed");
        t=new StageProfiler.CallbackTimer();t.begin(1);a=t.enter(outer,1);b=t.enter(inner,2);t.exit(a,3);
        check(t.error!=null&&!t.active,"mismatched callback exit rejected");
        t=new StageProfiler.CallbackTimer();t.begin(1);a=t.enter(outer,1);t.exit(a,2_000_001);t.cancel();eq(0,t.slowCount,"partial frame slow event discarded");
        t=new StageProfiler.CallbackTimer();t.begin(1);
        for(int i=0;i<StageProfiler.CallbackTimer.MAX_DEPTH;i++)check(t.enter(outer,i+1)!=0,"callback depth support");
        eq(0,t.enter(outer,1000),"callback depth bound");check(t.error!=null,"callback depth overflow diagnostic");
    }
    private static void nativeCallbacks(boolean finishInside) throws Exception {
        var platform=new J2SEPlatform();var env=platform.newTable();var thread=new KahluaThread(platform,env);
        thread.debugOwnerThread=Thread.currentThread();
        env.rawset("work",(JavaFunction)(frame,n)->{long until=System.nanoTime()+2_000_000;while(System.nanoTime()<until)Thread.onSpinWait();return 0;});
        var child=LuaCompiler.loadstring("work(); return 9","native-child.lua",env);child.prototype.filename="native-child.lua";
        env.rawset("bridge",(JavaFunction)(frame,n)->{thread.call(child,new Object[]{});return 0;});
        env.rawset("finishCapture",(JavaFunction)(frame,n)->{try{StageProfiler.finish();}catch(Exception e){throw new RuntimeException(e);}return 0;});
        var parent=LuaCompiler.loadstring(finishInside?"bridge(); finishCapture()":"bridge(); return 7","native-parent.lua",env);
        parent.prototype.filename=finishInside?"native-omitted.lua":"native-parent.lua";
        thread.call(parent,new Object[]{});
    }
    private static void recordingChecks(Path cache, boolean woven) throws Exception {
        System.clearProperty("pz.baseWalking.enabled");
        StageProfiler.start(null,null); StageProfiler.frameBegin(1,0,0); StageProfiler.frameEnd();
        eq(0,StageProfiler.enter(StageProfiler.LOGIC),"default off"); StageProfiler.finish();
        System.setProperty("pz.baseWalking.enabled","true");
        System.setProperty("pz.baseWalking.cachedir",Files.createDirectory(cache.resolve("wrong")).toString());
        boolean rejected=false;
        try { StageProfiler.start(cache,Thread.currentThread()); } catch (IllegalStateException expected) { rejected=true; }
        check(rejected,"cache mismatch rejected before recording");
        System.setProperty("pz.baseWalking.cachedir",cache.toString());
        StageProfiler.start(cache,Thread.currentThread());
        StageProfiler.frameBegin(0,0,0); eq(0,StageProfiler.enter(StageProfiler.LOGIC),"inactive phase");
        StageProfiler.frameBegin(1,2,12.5);
        int logic=StageProfiler.enter(StageProfiler.LOGIC), lua=StageProfiler.enter(StageProfiler.LUA);
        AtomicInteger foreignToken=new AtomicInteger(-1);
        Thread foreign=new Thread(() -> {
            StageProfiler.frameBegin(2,99,99); foreignToken.set(StageProfiler.enter(StageProfiler.CHUNK));
            StageProfiler.exit(123); StageProfiler.frameEnd(); StageProfiler.swapped(1,2);
        });
        foreign.start(); foreign.join(); eq(0,foreignToken.get(),"foreign thread no-op");
        StageProfiler.exit(lua); StageProfiler.exit(logic); StageProfiler.frameEnd();
        StageProfiler.frameBegin(2,3,20); int ui=StageProfiler.enter(StageProfiler.UI);
        if(woven)nativeCallbacks(false);
        StageProfiler.exit(ui); StageProfiler.frameEnd();
        StageProfiler.frameBegin(3,4,45); StageProfiler.frameEnd();
        StageProfiler.frameBegin(3,5,46); int incomplete=StageProfiler.enter(StageProfiler.LUA);
        if(woven)nativeCallbacks(true);else StageProfiler.finish();
        StageProfiler.exit(incomplete); StageProfiler.frameEnd();
        List<String> callbacks=Files.readAllLines(cache.resolve("base-walking-lua-callbacks.csv"));
        if(woven){
            check(callbacks.stream().anyMatch(line->line.contains("native-parent.lua")),"native callback parent attribution");
            check(callbacks.stream().anyMatch(line->line.contains("native-child.lua")),"native Java-to-Lua nested attribution");
            check(callbacks.stream().noneMatch(line->line.contains("native-omitted.lua")),"partial-frame callbacks omitted");
        }else eq(1,callbacks.size(),"no advice means empty callback table");
        List<String> csv=Files.readAllLines(cache.resolve("base-walking-stages.csv"));
        eq(4,csv.size(),"only complete frames emitted");
        String[] header=csv.getFirst().split(",");
        for (int row=1;row<csv.size();row++) {
            String[] values=csv.get(row).split(","); eq(header.length,values.length,"CSV column count");
            HashMap<String,String> fields=new HashMap<>();
            for (int i=0;i<header.length;i++) fields.put(header[i],values[i]);
            eq(row,Long.parseLong(fields.get("phase")),"phase-at-begin preserved");
            long exclusive=Long.parseLong(fields.get("other_exclusive_ns"));
            for (String stage:List.of("logic","render","chunk","loot","lua","tiles","ui"))
                exclusive+=Long.parseLong(fields.get(stage+"_exclusive_ns"));
            eq(Long.parseLong(fields.get("wall_ns")),exclusive,"CSV exclusive partition");
            check(Long.parseLong(fields.get("cpu_ns"))>=-1,"CPU unsupported sentinel");
        }
        List<RecordedEvent> events=RecordingFile.readAllEvents(cache.resolve("base-walking-stages.jfr"));
        List<RecordedEvent> frames=events.stream().filter(e -> e.getEventType().getName().equals("pz.baseWalking.Frame")).toList();
        List<RecordedEvent> swaps=events.stream().filter(e -> e.getEventType().getName().equals("pz.baseWalking.Swap")).toList();
        eq(3,frames.size(),"JFR complete frame count"); eq(1,swaps.size(),"render-thread JFR swap count");
        List<RecordedEvent> slow=events.stream().filter(e->e.getEventType().getName().equals("pz.baseWalking.LuaCallback")).toList();
        if(woven){
            eq(2,slow.size(),"only complete-frame slow parent/child emitted");
            for(var e:slow){
                eq(2,e.getInt("phase"),"slow callback phase");eq(2,e.getLong("frameId"),"slow callback completed frame ID");
                check(e.getLong("inclusiveNs")>=1_000_000&&e.getLong("exclusiveNs")>=0&&e.getLong("exclusiveNs")<=e.getLong("inclusiveNs"),"slow callback timing bounds");
                eq(e.getLong("nanoEnd")-e.getLong("nanoStart"),e.getLong("inclusiveNs"),"slow callback explicit clock interval");
                check(e.getStackTrace()==null&&!e.getString("source").contains("omitted"),"slow callback no stack or partial frame");
            }
        }else eq(0,slow.size(),"unwoven run no slow callback events");
        for (int i=0;i<3;i++) {
            RecordedEvent event=frames.get(i); eq(i+1,event.getInt("phase"),"reusable event phase");
            check(event.getStackTrace()==null,"frame stack trace off");
            eq(event.getLong("nanoEnd")-event.getLong("nanoStart"),event.getLong("wallNs"),"event nano fields");
        }
        eq(1,frames.getFirst().getInt("logicCalls"),"JFR logic count");
        eq(1,frames.getFirst().getInt("luaCalls"),"JFR Lua count");
        check(swaps.getFirst().getStackTrace()==null && swaps.getFirst().getDuration().isZero(),"instant swap without stack");
        check(Files.readString(cache.resolve("base-walking-stages-status.txt")).contains("omitted_incomplete_frames=1"),"incomplete diagnostic retained");
    }
    /** Optional actual ZombieBuddy weaving, using native metadata without initializing game classes. */
    private static void weaveChecks() throws Exception {
        var field=Loader.class.getDeclaredField("g_instrumentation"); field.setAccessible(true);
        Instrumentation instrumentation=(Instrumentation)field.get(null);
        check(instrumentation!=null,"--weave requires the real ZombieBuddy javaagent with a disposable config_dir");
        Map<String,Map<String,List<String>>> targets=Map.of(
            "zombie/GameWindow", Map.of(
                "frameStep()V", List.of("toolkit/basewalking/Main.frameStarting()V", "toolkit/basewalking/Main.framed()V"),
                "logic()V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V"),
                "renderInternal()V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V")),
            "zombie/iso/IsoChunk", Map.of("doLoadGridsquare()V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V")),
            "zombie/inventory/ItemPickerJava", Map.of("fillContainer(Lzombie/inventory/ItemContainer;Lzombie/characters/IsoPlayer;)V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V")),
            "se/krka/kahlua/vm/KahluaThread", Map.of("luaMainloop()V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V", "toolkit/basewalking/StageProfiler.luaEnter(Lse/krka/kahlua/vm/KahluaThread;)I", "toolkit/basewalking/StageProfiler.luaExit(I)V")),
            "zombie/iso/fboRenderChunk/FBORenderCell", Map.of("RenderTiles(II)V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V")),
            "zombie/ui/UIManager", Map.of(
                "render()V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V"),
                "update()V", List.of("toolkit/basewalking/StageProfiler.adviceEnter(I)I", "toolkit/basewalking/StageProfiler.exit(I)V")),
            "org/lwjglx/opengl/Display", Map.of("swapBuffers()V", List.of("toolkit/basewalking/Main.swapped()V")));
        PatchEngine.applyPatches("toolkit.basewalking",StageProfilerChecks.class.getClassLoader());
        Map<String,Boolean> observed=new HashMap<>();
        ClassFileTransformer observer=new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,ProtectionDomain domain,byte[] bytes) {
                if (!targets.containsKey(name)) return null;
                Map<String,java.util.Set<String>> calls=new HashMap<>();
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                    @Override public MethodVisitor visitMethod(int access,String method,String descriptor,String signature,String[] exceptions) {
                        String key=method+descriptor;
                        if (!targets.get(name).containsKey(key)) return null;
                        var seen=new java.util.HashSet<String>();calls.put(key,seen);
                        return new MethodVisitor(Opcodes.ASM9) {
                            @Override public void visitMethodInsn(int opcode,String owner,String method,String descriptor,boolean itf) {
                                seen.add(owner+"."+method+descriptor);
                            }
                        };
                    }
                },ClassReader.SKIP_DEBUG);
                boolean complete=true;
                for (var target:targets.get(name).entrySet())
                    complete &= calls.containsKey(target.getKey()) && calls.get(target.getKey()).containsAll(target.getValue());
                observed.put(name,complete);
                return null;
            }
        };
        instrumentation.addTransformer(observer,true);
        try {
            for (String name:targets.keySet()) {
                Class<?> type=Class.forName(name.replace('/','.'),false,StageProfilerChecks.class.getClassLoader());
                instrumentation.retransformClasses(type);
                check(Boolean.TRUE.equals(observed.get(name)),"No enter/exit woven into exact native method "+name);
            }
        } finally { instrumentation.removeTransformer(observer); }
        System.out.println("STAGE_PROFILER_NATIVE_WEAVING_PASS targets=7 methods=10 gameMethodsInvoked=0");
    }
    public static void main(String[] args) throws Exception {
        boolean woven=args.length==1 && args[0].equals("--weave");
        if (woven) weaveChecks();
        timerChecks();
        Path cache=Files.createTempDirectory("pz-stage-profiler-check-");
        try { callbackChecks(cache); recordingChecks(cache,woven); }
        finally {
            try (var paths=Files.walk(cache)) { for (Path p:paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(p); }
        }
        System.out.println("STAGE_PROFILER_CHECKS_PASS");
    }
}
