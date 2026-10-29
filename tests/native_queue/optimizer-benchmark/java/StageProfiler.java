package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.HexFormat;
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
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.*;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;

/** Explicitly enabled, disposable benchmark instrumentation; never changes game behavior. */
public final class StageProfiler {
    static final int LOGIC=0, RENDER=1, CHUNK=2, LOOT=3, LUA=4, TILES=5, UI=6, STAGES=7;
    private static final int CAPACITY=120000;
    private static final String[] NAMES={"logic","render","chunk","loot","lua","tiles","ui"};
    static final int FOG=0, TRANSLUCENT=1, MERGE=2, SORT=3, DETAILS=4;
    static final String[] DETAIL_NAMES={"fog", "translucent_total", "translucent_merge", "translucent_sort"};
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
    private static Timer timer, details;
    private static Instrumentation instrumentation;
    private static ClassFileTransformer detailTransformer;
    private static Rows rows;
    private static volatile String diagnostic;

    private StageProfiler() {}

    public static void start(Path outputCache, Thread ownerThread) throws Exception {
        if (!Boolean.getBoolean("pz.drivingPerf.stageProfile")) return;
        if (started) throw new IllegalStateException("One stage profile per JVM");
        String expected=System.getProperty("pz.drivingPerf.cachedir", "");
        if (expected.isBlank() || ownerThread != Thread.currentThread()
                || !Path.of(expected).toRealPath().equals(outputCache.toRealPath()))
            throw new IllegalStateException("Stage profile requires the explicit owned benchmark cache/thread");
        DetailHooks.requireNativeInput();
        Recording candidate=new Recording(Configuration.getConfiguration("profile"));
        try {
            candidate.setName("PZ driving stages");
            candidate.enable("jdk.FileRead").withThreshold(Duration.ofMillis(1));
            candidate.enable(FrameEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            candidate.enable(SwapEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            candidate.enable(TileProfiler.TileFrameEvent.class).withThreshold(Duration.ZERO).withoutStackTrace();
            cache=outputCache.toRealPath(); owner=ownerThread;
            cpu=ManagementFactory.getThreadMXBean();
            cpuAvailable=cpu.isCurrentThreadCpuTimeSupported() && cpu.isThreadCpuTimeEnabled();
            timer=new Timer(); details=new Timer(DETAILS); rows=new Rows(); frameEvent=new FrameEvent();
            DetailHooks.install();
            TileProfiler.start(ownerThread);
            LuaCallbacks.start(ownerThread);
            candidate.start(); recording=candidate; started=true; enabled=true;
        } catch (Exception | Error failure) {
            DetailHooks.remove(); TileProfiler.abort(); LuaCallbacks.abort();
            candidate.close();
            throw failure;
        }
    }

    private static boolean owns() { return enabled && Thread.currentThread()==owner; }
    private static long cpuNow() { return cpuAvailable ? cpu.getCurrentThreadCpuTime() : -1; }
    private static void error(String message) { if (diagnostic==null) diagnostic=message; }

    public static void frameBegin(int phase, int contacts, double speed) {
        if (!owns() || phase<1 || phase>3 || diagnostic!=null || timer.error!=null || details.error!=null || TileProfiler.diagnostic()!=null) return;
        if (frameOpen) { error("Frame began before previous frame ended"); timer.cancel(); details.cancel(); TileProfiler.cancelFrame(); return; }
        if (completed==CAPACITY) { error("Stage frame buffer overflow"); return; }
        framePhase=phase; frameContacts=contacts; frameSpeed=speed;
        lastFrameId++;
        cpuStart=cpuNow();
        long now=System.nanoTime();
        timer.begin(now); details.begin(now); TileProfiler.frameBegin(now);
        LuaCallbacks.frameBegin(lastFrameId,now);
        frameOpen=true; frameEvent.begin();
    }

    public static void frameEnd() {
        if (!owns() || !frameOpen) return;
        long now=System.nanoTime(), cpuEnd=cpuNow();
        frameOpen=false;
        if (!timer.complete(now) || !details.complete(now) || !TileProfiler.frameEnd(lastFrameId,now)) {
            TileProfiler.cancelFrame(); LuaCallbacks.frameEnd(now,false); omitted++; return;
        }
        LuaCallbacks.frameEnd(now,true);
        long cpuNs=cpuStart<0 || cpuEnd<cpuStart ? -1 : cpuEnd-cpuStart;
        rows.capture(completed, lastFrameId, framePhase, frameContacts, frameSpeed, timer, details, cpuNs);
        completed++;
        frameEvent.end();
        frameEvent.capture(lastFrameId, framePhase, frameContacts, frameSpeed, timer, details, cpuNs);
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

    /** Separate detail stack leaves all existing exclusive buckets and their partition unchanged. */
    public static int detailEnter(int category) {
        if (!owns() || !frameOpen || !details.active) return 0;
        return details.enter(category, System.nanoTime());
    }
    public static void detailExit(int token) {
        if (token==0 || !owns() || !frameOpen || !details.active) return;
        long now=System.nanoTime();
        // A native exception can leave the merge or sort child open. Attribute that partial
        // work, then close the whole-method token; the original throwable is rethrown intact.
        while (details.depth>0 && details.tokens[details.depth-1]!=token)
            details.exit(details.tokens[details.depth-1],now);
        details.exit(token,now);
    }
    public static void detailBegin(int category) { detailEnter(category); }
    public static void detailEnd(int category) {
        if (!owns() || !frameOpen || !details.active) return;
        if (details.depth==0 || details.stack[details.depth-1]!=category) {
            details.fail("Unbalanced detail boundary"); return;
        }
        details.exit(details.tokens[details.depth-1],System.nanoTime());
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
        timer.cancel(); details.cancel(); TileProfiler.cancelFrame(); DetailHooks.remove();
        if (details.error!=null) error(details.error);
        if (timer.error!=null) error(timer.error);
        if (completed==0) error("No complete stage frames");
        try {
            try (Recording active=recording) {
                active.stop(); active.dump(cache.resolve("driving-stages.jfr"));
            }
            TileProfiler.finish(cache);
            if (TileProfiler.diagnostic()!=null) error(TileProfiler.diagnostic());
            try (BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-stages.csv"))) {
                out.write("frame_id,phase,contacts,speed_kmh,nano_start,nano_end,wall_ns,cpu_ns");
                for (String name:NAMES) out.write(","+name+"_inclusive_ns,"+name+"_exclusive_ns,"+name+"_calls");
                out.write(",other_exclusive_ns");
                for (String name:DETAIL_NAMES) out.write(","+name+"_inclusive_ns,"+name+"_exclusive_ns,"+name+"_calls");
                out.write("\n");
                for (int i=0; i<completed; i++) {
                    out.write(rows.ids[i]+","+rows.phases[i]+","+rows.contacts[i]+","+rows.speeds[i]+","
                            +rows.starts[i]+","+rows.ends[i]+","+rows.wall[i]+","+rows.cpu[i]);
                    for (int stage=0; stage<STAGES; stage++)
                        out.write(","+rows.inclusive[stage][i]+","+rows.exclusive[stage][i]+","+rows.calls[stage][i]);
                    out.write(","+rows.other[i]);
                    for (int stage=0;stage<DETAILS;stage++)
                        out.write(","+rows.detailInclusive[stage][i]+","+rows.detailExclusive[stage][i]+","+rows.detailCalls[stage][i]);
                    out.write("\n");
                }
            }
            String status="complete_frames="+completed+" omitted_incomplete_frames="+omitted
                    +" cpu_supported_and_enabled="+cpuAvailable+" diagnostic="+(diagnostic==null ? "none" : diagnostic)
                    +" phase_contacts_speed=snapshot-at-frame-begin exclusive_plus_other=wall inclusive=category-union-nonadditive"
                    +" detail=independent-nonadditive fog=renderFog-whole translucent_total=whole-method"
                    +" translucent_merge=after-tempSquares-clear-to-doSort-including-profiler-and-sort-arguments"
                    +" translucent_sort=TimSort.doSort-call partial-details-on-throwable=included"
                    +" tile_details=method-boundaries-v1 tile_profile="+TileProfiler.profile();
            Files.writeString(cache.resolve("driving-stages-status.txt"), status+"\n");
            System.out.println("[DRIVING_STAGES] "+status);
            LuaCallbacks.finish(cache);
            if (diagnostic!=null) throw new IllegalStateException("Invalid stage profile: "+diagnostic);
        } finally {
            // Failed JFR/CSV export must not leave retransformation hooks installed.
            TileProfiler.abort(); LuaCallbacks.abort();
        }
    }

    /** Primitive, deterministic state machine; timestamps are supplied for focused checks. */
    static final class Timer {
        static final int MAX_DEPTH=256;
        final long[] inclusive, exclusive, inclusiveStart;
        final int[] calls, activeDepth, stack=new int[MAX_DEPTH], tokens=new int[MAX_DEPTH];
        Timer() { this(STAGES); }
        Timer(int categories) {
            inclusive=new long[categories]; exclusive=new long[categories]; inclusiveStart=new long[categories];
            calls=new int[categories]; activeDepth=new int[categories];
        }
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
            if (stage<0 || stage>=inclusive.length || depth==MAX_DEPTH || serial==Integer.MAX_VALUE) {
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
        void fail(String reason) { if (error==null) error=reason; cancel(); }
    }

    private static final class Rows {
        final long[] ids=new long[CAPACITY], starts=new long[CAPACITY], ends=new long[CAPACITY], wall=new long[CAPACITY], cpu=new long[CAPACITY], other=new long[CAPACITY];
        final int[] phases=new int[CAPACITY], contacts=new int[CAPACITY];
        final double[] speeds=new double[CAPACITY];
        final long[][] inclusive=new long[STAGES][CAPACITY], exclusive=new long[STAGES][CAPACITY];
        final int[][] calls=new int[STAGES][CAPACITY];
        final long[][] detailInclusive=new long[DETAILS][CAPACITY], detailExclusive=new long[DETAILS][CAPACITY];
        final int[][] detailCalls=new int[DETAILS][CAPACITY];
        void capture(int i,long id,int phase,int contact,double speed,Timer t,Timer d,long cpuNs) {
            ids[i]=id; phases[i]=phase; contacts[i]=contact; speeds[i]=speed;
            starts[i]=t.start; ends[i]=t.end; wall[i]=t.end-t.start; cpu[i]=cpuNs; other[i]=t.other;
            for (int s=0;s<STAGES;s++) { inclusive[s][i]=t.inclusive[s]; exclusive[s][i]=t.exclusive[s]; calls[s][i]=t.calls[s]; }
            for (int s=0;s<DETAILS;s++) { detailInclusive[s][i]=d.inclusive[s]; detailExclusive[s][i]=d.exclusive[s]; detailCalls[s][i]=d.calls[s]; }
        }
    }

    /** Exact reviewed input/method admission; official inputs also require the current production profile. */
    static final class DetailHooks {
        static final String TARGET="zombie/iso/fboRenderChunk/FBORenderCell";
        static final String OWNER="net/alexredby/drivingperf/StageProfiler";
        static final String NATIVE="d5c46201d60cff36397ee46c56b53dbaee6e26e8733836f27bf56ad871eedf94";
        static final String OFFICIAL="646ef5e25432f02a1d0e00848585fb450985bf89887519a458f0f07271350748";
        static final String FOG_DESC="(I)V", TL_DESC="(ILzombie/iso/IsoChunk;I)V";
        static volatile boolean woven;
        static String digest(byte[] data) throws Exception {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
        }
        static void requireNativeInput() throws Exception {
            try (var input=StageProfiler.class.getClassLoader().getResourceAsStream(TARGET+".class")) {
                if (input==null) throw new IllegalStateException("Stage details missing FBORenderCell input");
                String actual=digest(input.readAllBytes());
                if (NATIVE.equals(actual)) return;
                // Reuse the production profile admission. An exact official resource alone
                // must not turn an unreviewed combination of optimizer switches into a profile.
                if (OFFICIAL.equals(actual)) {
                    Class<?> compatibility=Class.forName("net.alexredby.pztoolkitjavapatches.OptimizerCompatibility");
                    if (Boolean.TRUE.equals(compatibility.getMethod("supports",String.class,String.class,String.class)
                            .invoke(null,TARGET+".class",NATIVE,actual))) return;
                }
                throw new IllegalStateException("Unsupported stage detail FBORenderCell input/profile: "+actual);
            }
        }
        static void install() throws Exception {
            instrumentation=Accessor.tryGet(Loader.class,"g_instrumentation",null);
            if (instrumentation==null || !instrumentation.isRetransformClassesSupported())
                throw new IllegalStateException("Stage details require ZombieBuddy retransformation");
            detailTransformer=new ClassFileTransformer() {
                @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,ProtectionDomain domain,byte[] bytes) {
                    if (!TARGET.equals(name)) return null;
                    byte[] result=weave(bytes); woven=result!=null;
                    if (result==null && started && !finished) error("Stage detail boundary changed during capture");
                    return result;
                }
            };
            instrumentation.addTransformer(detailTransformer,true);
            Class<?> target=Arrays.stream(instrumentation.getAllLoadedClasses())
                    .filter(type -> type.getName().equals(TARGET.replace('/','.'))).findFirst().orElse(null);
            if (target==null) Class.forName(TARGET.replace('/','.'),false,StageProfiler.class.getClassLoader());
            else instrumentation.retransformClasses(target);
            if (!woven) throw new IllegalStateException("Stage detail method boundary/shape mismatch");
        }
        static void remove() {
            if (instrumentation!=null && detailTransformer!=null) instrumentation.removeTransformer(detailTransformer);
            detailTransformer=null;
        }
        static byte[] boundary(byte[] bytes,String method,String descriptor) {
            ClassWriter output=new ClassWriter(0);
            output.visit(Opcodes.V17,Opcodes.ACC_PUBLIC,TARGET,null,"java/lang/Object",null);
            new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                    return name.equals(method) && desc.equals(descriptor)
                            ? output.visitMethod(access,name,desc,signature,exceptions) : null;
                }
            },ClassReader.SKIP_DEBUG);
            output.visitEnd(); return output.toByteArray();
        }
        static boolean admitted(byte[] bytes) throws Exception {
            String fog=digest(boundary(bytes,"renderFog",FOG_DESC));
            String tl=digest(boundary(bytes,"renderOneLevel_Translucent",TL_DESC));
            // Native or selected official overlay, each with or without the existing
            // invocation-local TranslucentSquareUnion splice. No other method change is admitted.
            return fog.equals("eb1022046b12a9f0255a443034279947c7a73fbd5de2781d87d3c40a91320036")
                    && (tl.equals("6cb52a56be844854b095bf143939873aca93b7cc8b0a7551001e9e712f77f799")
                        || tl.equals("fca3e7a2c4d41d05aac2935631ad078e80b3b4a655dc9aee6a16ef36931cca50"))
                || fog.equals("57aee430d673f43626a7dcb6d32ec3b1b12b0271a513a4b1986feb557e574c62")
                    && (tl.equals("59c6421e61bacf8655e492abc8c140937d125fb8d909376eec277164b3d6f7d7")
                        || tl.equals("6e2c0a9b37d604d3df793afac4332dccc9368b8af9cb2c12ef79f676e9600b7e"));
        }
        static byte[] weave(byte[] bytes) {
            try {
                if (bytes==null || !admitted(bytes)) return null;
                int[] locals=new int[2], methods=new int[2], clear={0}, sort={0};
                ClassReader reader=new ClassReader(bytes);
                reader.accept(new ClassVisitor(Opcodes.ASM9) {
                    @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                        int target=name.equals("renderFog") && desc.equals(FOG_DESC) ? 0
                                : name.equals("renderOneLevel_Translucent") && desc.equals(TL_DESC) ? 1 : -1;
                        if (target<0) return null;
                        methods[target]++;
                        return new MethodVisitor(Opcodes.ASM9) {
                            @Override public void visitMaxs(int stack,int count) { locals[target]=count; }
                        };
                    }
                },ClassReader.SKIP_DEBUG);
                if (methods[0]!=1 || methods[1]!=1) return null;
                ClassWriter output=new ClassWriter(reader,ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
                reader.accept(new ClassVisitor(Opcodes.ASM9,output) {
                    @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                        MethodVisitor next=super.visitMethod(access,name,desc,signature,exceptions);
                        int target=name.equals("renderFog") && desc.equals(FOG_DESC) ? 0
                                : name.equals("renderOneLevel_Translucent") && desc.equals(TL_DESC) ? 1 : -1;
                        if (target<0) return next;
                        return new MethodVisitor(Opcodes.ASM9,next) {
                            final net.bytebuddy.jar.asm.Label start=new net.bytebuddy.jar.asm.Label(), end=new net.bytebuddy.jar.asm.Label(), handler=new net.bytebuddy.jar.asm.Label();
                            void call(String method,int category) {
                                super.visitLdcInsn(category);
                                super.visitMethodInsn(Opcodes.INVOKESTATIC,OWNER,method,"(I)V",false);
                            }
                            void close() {
                                super.visitVarInsn(Opcodes.ILOAD,locals[target]);
                                super.visitMethodInsn(Opcodes.INVOKESTATIC,OWNER,"detailExit","(I)V",false);
                            }
                            @Override public void visitCode() {
                                super.visitCode(); super.visitLdcInsn(target==0 ? FOG : TRANSLUCENT);
                                super.visitMethodInsn(Opcodes.INVOKESTATIC,OWNER,"detailEnter","(I)I",false);
                                super.visitVarInsn(Opcodes.ISTORE,locals[target]); super.visitLabel(start);
                            }
                            @Override public void visitInsn(int opcode) {
                                if (opcode==Opcodes.RETURN) close();
                                super.visitInsn(opcode);
                            }
                            @Override public void visitMethodInsn(int opcode,String owner,String method,String descriptor,boolean itf) {
                                boolean sorting=target==1 && opcode==Opcodes.INVOKEVIRTUAL
                                        && owner.equals("zombie/entity/util/TimSort") && method.equals("doSort")
                                        && descriptor.equals("([Ljava/lang/Object;Ljava/util/Comparator;II)V");
                                if (sorting) { sort[0]++; call("detailEnd",MERGE); call("detailBegin",SORT); }
                                super.visitMethodInsn(opcode,owner,method,descriptor,itf);
                                if (sorting) call("detailEnd",SORT);
                                if (target==1 && opcode==Opcodes.INVOKEVIRTUAL
                                        && owner.equals("zombie/util/list/PZArrayList") && method.equals("clear") && descriptor.equals("()V")) {
                                    clear[0]++; call("detailBegin",MERGE);
                                }
                            }
                            @Override public void visitMaxs(int stack,int count) {
                                super.visitLabel(end); super.visitLabel(handler);
                                super.visitTryCatchBlock(start,end,handler,"java/lang/Throwable");
                                super.visitVarInsn(Opcodes.ASTORE,locals[target]+1); close();
                                super.visitVarInsn(Opcodes.ALOAD,locals[target]+1); super.visitInsn(Opcodes.ATHROW);
                                super.visitMaxs(0,0);
                            }
                        };
                    }
                },ClassReader.SKIP_FRAMES);
                return clear[0]==1 && sort[0]==1 ? output.toByteArray() : null;
            } catch (Exception | LinkageError invalid) { return null; }
        }
    }

    @Name("pz.driving.Frame") @Label("Driving completed frame") @Category({"PZ","Driving"}) @StackTrace(false)
    @Description("Phase/contacts/speed at begin. Original exclusive buckets plus other equal wall. Details are an independent nonadditive stack; merge includes native profiler/argument preparation, sort is doSort only.")
    public static final class FrameEvent extends Event {
        public long frameId, nanoStart, nanoEnd;
        public int phase, contacts;
        public double speedKmh;
        @Timespan(Timespan.NANOSECONDS) public long wallNs, cpuNs, otherExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long logicInclusiveNs, logicExclusiveNs, renderInclusiveNs, renderExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long chunkInclusiveNs, chunkExclusiveNs, lootInclusiveNs, lootExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long luaInclusiveNs, luaExclusiveNs, tilesInclusiveNs, tilesExclusiveNs, uiInclusiveNs, uiExclusiveNs;
        public int logicCalls, renderCalls, chunkCalls, lootCalls, luaCalls, tilesCalls, uiCalls;
        @Timespan(Timespan.NANOSECONDS) public long fogInclusiveNs, fogExclusiveNs, translucentTotalInclusiveNs, translucentTotalExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long translucentMergeInclusiveNs, translucentMergeExclusiveNs, translucentSortInclusiveNs, translucentSortExclusiveNs;
        public int fogCalls, translucentTotalCalls, translucentMergeCalls, translucentSortCalls;
        void capture(long id,int p,int contact,double speed,Timer t,Timer d,long cpuTime) {
            frameId=id; phase=p; contacts=contact; speedKmh=speed; nanoStart=t.start; nanoEnd=t.end;
            wallNs=t.end-t.start; cpuNs=cpuTime; otherExclusiveNs=t.other;
            fogInclusiveNs=d.inclusive[FOG]; fogExclusiveNs=d.exclusive[FOG]; fogCalls=d.calls[FOG];
            translucentTotalInclusiveNs=d.inclusive[TRANSLUCENT]; translucentTotalExclusiveNs=d.exclusive[TRANSLUCENT]; translucentTotalCalls=d.calls[TRANSLUCENT];
            translucentMergeInclusiveNs=d.inclusive[MERGE]; translucentMergeExclusiveNs=d.exclusive[MERGE]; translucentMergeCalls=d.calls[MERGE];
            translucentSortInclusiveNs=d.inclusive[SORT]; translucentSortExclusiveNs=d.exclusive[SORT]; translucentSortCalls=d.calls[SORT];
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
