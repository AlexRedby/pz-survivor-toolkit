package net.alexredby.drivingperf;

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
        t=new StageProfiler.Timer(StageProfiler.DETAILS); t.begin(0);
        eq(0,t.enter(StageProfiler.DETAILS,1),"detail category bound");
        check(t.error!=null && !t.active,"detail category overflow fails closed");
    }
    private static void bytecodeChecks() throws Exception {
        StageProfiler.DetailHooks.requireNativeInput();
        byte[] original;
        try (var input=StageProfilerChecks.class.getClassLoader().getResourceAsStream(StageProfiler.DetailHooks.TARGET+".class")) {
            original=input.readAllBytes();
        }
        if (StageProfiler.DetailHooks.digest(original).equals(StageProfiler.DetailHooks.OFFICIAL)) {
            String key="pzopt.fogPass", previous=System.getProperty(key);
            try {
                System.setProperty(key,"true");
                boolean rejected=false;
                try { StageProfiler.DetailHooks.requireNativeInput(); } catch (IllegalStateException expected) { rejected=true; }
                check(rejected,"official profile mismatch fails admission");
            } finally {
                if (previous==null) System.clearProperty(key); else System.setProperty(key,previous);
            }
        }
        byte[] woven=StageProfiler.DetailHooks.weave(original);
        check(woven!=null,"reviewed native/official methods admitted");
        check(StageProfiler.DetailHooks.weave(woven)==null,"duplicate detail weaving rejected");
        int[] detailCalls={0,0,0,0};
        new ClassReader(woven).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access,String name,String descriptor,String signature,String[] exceptions) {
                if (!name.equals("renderFog") && !name.equals("renderOneLevel_Translucent")) return null;
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override public void visitMethodInsn(int opcode,String owner,String name,String descriptor,boolean itf) {
                        if (!owner.equals(StageProfiler.DetailHooks.OWNER)) return;
                        if (name.equals("detailEnter")) detailCalls[0]++;
                        if (name.equals("detailExit")) detailCalls[1]++;
                        if (name.equals("detailBegin")) detailCalls[2]++;
                        if (name.equals("detailEnd")) detailCalls[3]++;
                    }
                };
            }
        },ClassReader.SKIP_DEBUG);
        eq(2,detailCalls[0],"two whole-method detail entries");
        check(detailCalls[1]>=4,"normal and exceptional method exits close details");
        eq(2,detailCalls[2],"one actual merge and one exact sort entry");
        eq(2,detailCalls[3],"merge and sort normal exits");
        ClassWriter changed=new ClassWriter(0);
        new ClassReader(original).accept(new ClassVisitor(Opcodes.ASM9,changed) {
            @Override public MethodVisitor visitMethod(int access,String name,String descriptor,String signature,String[] exceptions) {
                MethodVisitor next=super.visitMethod(access,name,descriptor,signature,exceptions);
                if (!name.equals("renderFog")) return next;
                return new MethodVisitor(Opcodes.ASM9,next) {
                    @Override public void visitCode() { super.visitCode(); super.visitInsn(Opcodes.NOP); }
                };
            }
        },0);
        check(StageProfiler.DetailHooks.weave(changed.toByteArray())==null,"unreviewed target instruction rejected");
        check(StageProfiler.DetailHooks.weave(null)==null,"missing bytes rejected");
    }
    private static void installUnion() throws Exception {
        Class<?> helper=Class.forName("net.alexredby.pztoolkitjavapatches.TranslucentSquareUnion");
        check(Boolean.TRUE.equals(helper.getMethod("install").invoke(null)),"real existing union must install for --union");
    }
    private static void recordingChecks(Path cache) throws Exception {
        System.clearProperty("pz.drivingPerf.stageProfile");
        StageProfiler.start(null,null); StageProfiler.frameBegin(1,0,0); StageProfiler.frameEnd();
        eq(0,StageProfiler.enter(StageProfiler.LOGIC),"default off"); StageProfiler.finish();
        System.setProperty("pz.drivingPerf.stageProfile","true");
        System.setProperty("pz.drivingPerf.cachedir",Files.createDirectory(cache.resolve("wrong")).toString());
        boolean rejected=false;
        try { StageProfiler.start(cache,Thread.currentThread()); } catch (IllegalStateException expected) { rejected=true; }
        check(rejected,"cache mismatch rejected before recording");
        System.setProperty("pz.drivingPerf.cachedir",cache.toString());
        StageProfiler.start(cache,Thread.currentThread());
        check(StageProfiler.DetailHooks.woven,"real JVM accepted guarded detail bytecode");
        check(!Files.exists(cache.resolve("driving-stages.csv")),"no CSV output during capture");
        StageProfiler.frameBegin(0,0,0); eq(0,StageProfiler.enter(StageProfiler.LOGIC),"inactive phase");
        StageProfiler.frameBegin(1,2,12.5);
        int logic=StageProfiler.enter(StageProfiler.LOGIC), lua=StageProfiler.enter(StageProfiler.LUA);
        AtomicInteger foreignToken=new AtomicInteger(-1);
        Thread foreign=new Thread(() -> {
            StageProfiler.frameBegin(2,99,99); foreignToken.set(StageProfiler.enter(StageProfiler.CHUNK));
            eq(0,StageProfiler.detailEnter(StageProfiler.FOG),"foreign detail no-op");
            StageProfiler.detailBegin(StageProfiler.MERGE); StageProfiler.detailEnd(StageProfiler.MERGE);
            StageProfiler.exit(123); StageProfiler.frameEnd(); StageProfiler.swapped(1,2);
        });
        foreign.start(); foreign.join(); eq(0,foreignToken.get(),"foreign thread no-op");
        int fog=StageProfiler.detailEnter(StageProfiler.FOG); StageProfiler.detailExit(fog);
        int translucent=StageProfiler.detailEnter(StageProfiler.TRANSLUCENT);
        StageProfiler.detailBegin(StageProfiler.MERGE); StageProfiler.detailEnd(StageProfiler.MERGE);
        StageProfiler.detailBegin(StageProfiler.SORT); StageProfiler.detailEnd(StageProfiler.SORT);
        StageProfiler.detailExit(translucent);
        // Simulate a merge failure: whole-method finally must close the partial child.
        translucent=StageProfiler.detailEnter(StageProfiler.TRANSLUCENT);
        StageProfiler.detailBegin(StageProfiler.MERGE); StageProfiler.detailExit(translucent);
        StageProfiler.exit(lua); StageProfiler.exit(logic); StageProfiler.frameEnd();
        StageProfiler.frameBegin(2,3,20); int ui=StageProfiler.enter(StageProfiler.UI); StageProfiler.exit(ui); StageProfiler.frameEnd();
        StageProfiler.frameBegin(3,4,45); StageProfiler.frameEnd();
        StageProfiler.frameBegin(3,5,46); int incomplete=StageProfiler.enter(StageProfiler.LUA);
        StageProfiler.finish(); StageProfiler.exit(incomplete); StageProfiler.frameEnd();
        List<String> csv=Files.readAllLines(cache.resolve("driving-stages.csv"));
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
            for (String name:StageProfiler.DETAIL_NAMES) {
                long inclusive=Long.parseLong(fields.get(name+"_inclusive_ns"));
                long detailExclusive=Long.parseLong(fields.get(name+"_exclusive_ns"));
                check(inclusive>=detailExclusive && detailExclusive>=0,"nonnegative bounded detail accounting");
                check(inclusive<=Long.parseLong(fields.get("wall_ns")),"detail bounded by owning frame");
            }
            if (row==1) {
                eq(1,Long.parseLong(fields.get("fog_calls")),"CSV fog attribution");
                eq(2,Long.parseLong(fields.get("translucent_total_calls")),"CSV whole translucent count");
                eq(2,Long.parseLong(fields.get("translucent_merge_calls")),"CSV normal plus exceptional merge count");
                eq(1,Long.parseLong(fields.get("translucent_sort_calls")),"CSV actual sort count");
                eq(Long.parseLong(fields.get("translucent_total_inclusive_ns")),
                        Long.parseLong(fields.get("translucent_total_exclusive_ns"))
                        +Long.parseLong(fields.get("translucent_merge_inclusive_ns"))
                        +Long.parseLong(fields.get("translucent_sort_inclusive_ns")),"translucent children partition parent");
            } else eq(0,Long.parseLong(fields.get("translucent_total_calls")),"details reset each frame");
        }
        List<RecordedEvent> events=RecordingFile.readAllEvents(cache.resolve("driving-stages.jfr"));
        List<RecordedEvent> frames=events.stream().filter(e -> e.getEventType().getName().equals("pz.driving.Frame")).toList();
        List<RecordedEvent> swaps=events.stream().filter(e -> e.getEventType().getName().equals("pz.driving.Swap")).toList();
        eq(3,frames.size(),"JFR complete frame count"); eq(1,swaps.size(),"render-thread JFR swap count");
        for (int i=0;i<3;i++) {
            RecordedEvent event=frames.get(i); eq(i+1,event.getInt("phase"),"reusable event phase");
            check(event.getStackTrace()==null,"frame stack trace off");
            eq(event.getLong("nanoEnd")-event.getLong("nanoStart"),event.getLong("wallNs"),"event nano fields");
        }
        eq(1,frames.getFirst().getInt("logicCalls"),"JFR logic count");
        eq(1,frames.getFirst().getInt("luaCalls"),"JFR Lua count");
        eq(1,frames.getFirst().getInt("fogCalls"),"JFR fog count");
        eq(2,frames.getFirst().getInt("translucentMergeCalls"),"JFR merge count includes failed work");
        eq(1,frames.getFirst().getInt("translucentSortCalls"),"JFR actual sort count");
        eq(2,frames.getFirst().getInt("translucentTotalCalls"),"JFR total labeled separately");
        check(swaps.getFirst().getStackTrace()==null && swaps.getFirst().getDuration().isZero(),"instant swap without stack");
        check(Files.readString(cache.resolve("driving-stages-status.txt")).contains("omitted_incomplete_frames=1"),"incomplete diagnostic retained");
    }
    /** Optional actual ZombieBuddy weaving, using native metadata without initializing game classes. */
    private static void weaveChecks() throws Exception {
        var field=Loader.class.getDeclaredField("g_instrumentation"); field.setAccessible(true);
        Instrumentation instrumentation=(Instrumentation)field.get(null);
        check(instrumentation!=null,"--weave requires the real ZombieBuddy javaagent with a disposable config_dir");
        Map<String,String> targets=Map.of(
                "zombie/inventory/ItemPickerJava","fillContainer(Lzombie/inventory/ItemContainer;Lzombie/characters/IsoPlayer;)V",
                "zombie/iso/fboRenderChunk/FBORenderCell","RenderTiles(II)V");
        PatchEngine.applyPatches("net.alexredby.drivingperf",StageProfilerChecks.class.getClassLoader());
        Map<String,Boolean> observed=new HashMap<>();
        ClassFileTransformer observer=new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,ProtectionDomain domain,byte[] bytes) {
                if (!targets.containsKey(name)) return null;
                int[] calls={0,0};
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                    @Override public MethodVisitor visitMethod(int access,String method,String descriptor,String signature,String[] exceptions) {
                        if (!targets.get(name).equals(method+descriptor)) return null;
                        return new MethodVisitor(Opcodes.ASM9) {
                            @Override public void visitMethodInsn(int opcode,String owner,String method,String descriptor,boolean itf) {
                                if (!owner.equals("net/alexredby/drivingperf/StageProfiler")) return;
                                if (method.equals("enter") && descriptor.equals("(I)I")) calls[0]++;
                                if (method.equals("exit") && descriptor.equals("(I)V")) calls[1]++;
                            }
                        };
                    }
                },ClassReader.SKIP_DEBUG);
                observed.put(name,calls[0]>0 && calls[1]>0);
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
        System.out.println("STAGE_PROFILER_NATIVE_WEAVING_PASS targets=2 gameMethodsInvoked=0");
    }
    public static void main(String[] args) throws Exception {
        boolean weave=List.of(args).contains("--weave");
        if (List.of(args).contains("--union")) installUnion();
        if (weave) weaveChecks();
        timerChecks(); bytecodeChecks();
        if (!weave) {
            System.out.println("STAGE_PROFILER_CHECKS_PASS timer_and_bytecode_only=true recording=requires-real-javaagent-and--weave");
            return;
        }
        Path cache=Files.createTempDirectory("pz-stage-profiler-check-");
        try { recordingChecks(cache); }
        finally {
            try (var paths=Files.walk(cache)) { for (Path p:paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(p); }
        }
        System.out.println("STAGE_PROFILER_CHECKS_PASS");
    }
}
