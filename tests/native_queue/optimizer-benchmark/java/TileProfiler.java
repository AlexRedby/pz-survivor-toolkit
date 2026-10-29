package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.Arrays;
import java.util.Collections;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import jdk.jfr.Category;
import jdk.jfr.Description;
import jdk.jfr.Event;
import jdk.jfr.Label;
import jdk.jfr.Name;
import jdk.jfr.StackTrace;
import jdk.jfr.Timespan;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.*;

/** Disposable owner-thread wall attribution, independent of the stage/detail stacks. */
public final class TileProfiler {
    static final String CELL="zombie/iso/fboRenderChunk/FBORenderCell";
    static final String MANAGER="zombie/iso/fboRenderChunk/FBORenderChunkManager";
    private static final String OWNER="net/alexredby/drivingperf/TileProfiler";
    private static final int CAPACITY=120000, GROUPS=15;
    static final String[] NAMES={"tiles_internal","perform","schedule","bake","precount","composite","chunk","moving","translucent","terrain","items","characters","lighting","other_world","preparation"};
    private static final String MANAGER_RESOURCE="f94aa259d6a371f4fd22f3e86e48aac47b4c823b0a13ebcccdbb9fa69671c7aa";
    private static final String MANAGER_BOUNDARY="8cea7e8c0da23347495a2bac404491ca54a386d9897a8f98545302535c512cb9";
    private static final Map<String,Integer> NATIVE_TARGETS, OFFICIAL_TARGETS;
    private static final Map<String,String> NATIVE_PINS, OFFICIAL_PINS;
    static {
        Map<String,Integer> nt=new LinkedHashMap<>(), ot=new LinkedHashMap<>();
        Map<String,String> np=new LinkedHashMap<>(), op=new LinkedHashMap<>();
        for (String line: """
            0 renderTilesInternal(I)V 131c9374823ca8f6511e8209f36562c8fe764261d464185c4534d5dd4fd62c83 b0e59608ed06915e24e78da96055396a32cb60da048958dd05a3e7eb5def8376
            1 performRenderTiles(Lzombie/iso/IsoCell$PerPlayerRender;IJ)V b7615c0d69116359512a92a306a511b1a461f60dd7a9bba0ee6058831d9104d0 9a57d158e33c0fdf7be7e9a846fad2fe12b27f46fe2a3ef8c79904f5ad90d37d
            2 pzoptSchedulePlan(IJ)V - ff103b4ed41dbf95a11b583e7c7f9b491e77bd6bc4775d379c36f051b7cbc6c1
            3 pzoptBakePrePass(I)V - b59544dbde5bd945ec3d3d1f6e730962181fb66fa74b85a53a7bdf64a35ea3e8
            4 pzoptPrecountRenderedSquares(I)Z - 393393310a5921963a343bd69b4be0dab4d9271e6d517a39b1a87c5d416f08c5
            5 pzoptCompositeChunks()V - 108c4ea7c063c71da173866b1386f44313129982bc555fb010cd18083965157c
            6 renderOneChunk(Lzombie/iso/IsoChunk;Lzombie/iso/IsoCell$PerPlayerRender;IJLzombie/core/opengl/Shader;Lzombie/core/opengl/Shader;)V c8e1f9352678f8945fcad49aa9c8bdeae555e406c7723243da9fae64a8d31a7b ddf43a38d8377b276c9df495e59fa6f5705439f7c66b75ac8c81c74f769a297e
            7 renderMovingObjects()V fa4f2891132d0bedb58414c43a17eedda1dde93973d8d302b3d0710ffd5ecf92 3fc629b2e07aa30b47f498505a6a3b0d5afa29e629b67e6e1c0c2e180a504075
            8 renderTranslucentFloorObjects(IILzombie/core/opengl/Shader;Lzombie/core/opengl/Shader;J)V ea06f1647ecd1baf4f9d109f4bc5c0c8e14d9fa1e118349d169d41c1a34a9333 7946e0696d9555f4504991d987a225a27e1485cc2aa08b35ef586b6512199f72
            8 renderTranslucentObjects(IILzombie/core/opengl/Shader;Lzombie/core/opengl/Shader;J)V cc0a4b377feddde95dbc33520b705de9081f3ea7dfc690b70547821b5dbb1008 3aa45fe9f0873457fb83d2bea64c633f4c5cd6888e338fb34852105e5ae546db
            9 renderPuddles(I)V 566926a7dc9cdf88e6415da49f05bc37aab8f1f71df0c47222e388e1abec8170 e0baab00685e05df7051cabbece843f365f171db15f16d695a43cd9db67e0246
            9 renderWater(I)V 7cc00d00186661b23367b210a179b523a5d385c0b30b9271f314b749f6248b08 7045868a20867d399c48a2917a3f7bfb8ff29a7b3eb081d31dde8066b13228fc
            9 renderPuddlesTranslucentFloorsOnly(II)V 03d5f5a878def64810244d9f674f1921c869a8884fabcb3aa054f8eb788c00d7 1e50af58982254b0b821a31455dd38ca378e7eea76768f03d789fdde0b74d5f5
            9 renderWaterShore(I)V 6feb50b2f933cd6cec4163f9f7d1e6cc26ed808c6f8411f9830dda1a162f0118 1744be6557c77c41198aa193a65f992bd37e83a1d78b2754088ae2b6f24f4aa8
            9 renderRainSplashes(II)V 2e65693c2801bfff5c86b8bd3810675deaecf76f658abfe6587bd33a7fea10fe 81246694225241290d527e9e655d5f900cf187b665860e1ac6378b41683ad460
            10 renderItemsInWorld(I)V c0207694f03d239bdafec5906a3d130e7948fc866df057205dfb2259239e9a3c 652d3eca668b51c2ed1401eec5868bc54ea303fa1027e0416823e4a2f996aac9
            10 renderCorpsesInWorld(I)V 1d2173bca65a50981270faec387aef63ce00b722a2ca8265ad20bc3d58bc865b a6beac7c120ae560e9c161e4dfdcc4d584ab2b41946fce2e00794cca2e8092b1
            11 renderPlayer(ILzombie/characters/IsoPlayer;)V b414eaba605c8b9ecdee99046953df0e1c7487a7116a4f874dcdc3b0cd51aa9b 02536d2547f9fa57aa6e6c5989c68ec66d04e71587ca317e4d4d7f488e3e6f06
            11 renderCorpseShadows(I)V 5080c1a3d6ce672021f782623c9ddc0c5d8e8e4806dfb6e2a74c42a1304ddefe 53eb1e413403e47497c7ae1790abc7d93828776cf54855d0d27702c4f0778297
            11 renderMannequinShadows(I)V d98a89960f4be3f5b60b7d9638d2d461af4431e0f940e48aba3828fe0cc231a4 79a82ccbe2c77dcaec955a550bd39fdde6aec3839d1f653df682e8f0653acb20
            12 updateChunkLighting(I)V 6307b72c31eb4e140318dc29bd3ce7ca7b51076a69dff0242d9ec9f8c33faa36 063a3586629890ddadf021e11bed5cb01e0191a280ab64df388321515d32ed62
            13 renderAnimatedAttachments(I)V e37dd2d33d7b5c8234d2d18c8268085957ed026ef86809a40910df5bc5fba5bb e37dd2d33d7b5c8234d2d18c8268085957ed026ef86809a40910df5bc5fba5bb
            13 renderFlies(I)V 6fe917897acc71d7effa67747d6f022ab11b9f1331e51af2cd3ce283cd826a63 6fe917897acc71d7effa67747d6f022ab11b9f1331e51af2cd3ce283cd826a63
            13 renderOpaqueObjectsEvent(I)V d400f604bcf06aad97b1251b2a6e1f49c2a0d70d614bf4e9d81646ee2a9ac23b d400f604bcf06aad97b1251b2a6e1f49c2a0d70d614bf4e9d81646ee2a9ac23b
            14 runChecks(I)Z 5235844f129f05475ce25c1977ead58813dd0ea6063aa9c96529842d43360b77 83108792ec0fb1ea8ff42408559bd4d596702bc0261cb31d9f9c4c09a1c75834
            14 recalculateGridStacks(Lzombie/characters/IsoPlayer;I)Z 7f6d6355ee0c1ce9894cf5ae8f23ebd86c07543e8b9bedaa22e27c497ea7441e 959192e3cbe27cd5148aae61d89b80d7a4efc3436431819adc8c8189224d6a81
            14 prepareChunksForUpdating(I)V 0934dae14eee5c5c7d42b0afef4d6ff2ec6ed26fa7dcc528489498d064950b4c 4a3258cd1170ef3952a8629b611bc20cd47f310d7fb68b455cc547c2d52f7da1
            14 calculateOccludingSquares(I)V b890f00024af486fcc894d28a8246f9b7a21b4c6cf129435b26c04e42ba62319 9eba7f2b3a5871ff537ca414b3c0052c51862ff4a0fc52696c7af1ca447139d3
                """.strip().split("\n")) {
            String[] parts=line.strip().split(" "); int category=Integer.parseInt(parts[0]);
            ot.put(parts[1],category); op.put(parts[1],parts[3]);
            if (!parts[2].equals("-")) { nt.put(parts[1],category); np.put(parts[1],parts[2]); }
        }
        NATIVE_TARGETS=Collections.unmodifiableMap(nt); OFFICIAL_TARGETS=Collections.unmodifiableMap(ot);
        NATIVE_PINS=Collections.unmodifiableMap(np); OFFICIAL_PINS=Collections.unmodifiableMap(op);
    }
    private static volatile boolean enabled, cellWoven, managerWoven;
    private static Thread owner;
    private static StageProfiler.Timer timer;
    private static Rows rows;
    private static TileFrameEvent event;
    private static Instrumentation instrumentation;
    private static ClassFileTransformer transformer;
    private static String selectedProfile;
    private static volatile String problem;
    private static boolean frameOpen, finished;
    private static int completed;
    private TileProfiler() { }
    private static boolean owns() { return enabled && Thread.currentThread()==owner; }
    private static void fail(String reason) { if (problem==null) problem=reason; }

    static void start(Thread ownerThread) throws Exception {
        if (ownerThread==null || ownerThread!=Thread.currentThread())
            throw new IllegalStateException("Tile profile requires the stage owner thread");
        if (owner!=null) throw new IllegalStateException("One tile profile per JVM");
        StageProfiler.DetailHooks.requireNativeInput();
        String resource=resourceDigest(CELL);
        selectedProfile=resource.equals(StageProfiler.DetailHooks.NATIVE) ? "native"
                : resource.equals(StageProfiler.DetailHooks.OFFICIAL) ? "official" : null;
        if (selectedProfile==null || !MANAGER_RESOURCE.equals(resourceDigest(MANAGER)))
            throw new IllegalStateException("Unsupported tile profile source resources");
        owner=ownerThread; timer=new StageProfiler.Timer(GROUPS); rows=new Rows(); event=new TileFrameEvent();
        try { install(); enabled=true; } catch (Exception | Error failure) { abort(); throw failure; }
    }
    static void frameBegin(long now) {
        if (!owns() || diagnostic()!=null) return;
        if (frameOpen) { fail("Frame began before previous tile frame ended"); cancelFrame(); return; }
        if (completed==CAPACITY) { fail("Tile frame buffer overflow"); return; }
        timer.begin(now); frameOpen=timer.active;
    }
    static boolean frameEnd(long id,long now) {
        if (!owns() || !frameOpen) return false;
        frameOpen=false;
        if (!timer.complete(now) || diagnostic()!=null) return false;
        if (id<1 || id>CAPACITY || (completed>0 && id<=rows.ids[completed-1]) || timer.end<=timer.start) {
            fail("Invalid tile frame identity or timing"); return false;
        }
        long exclusive=0;
        for (long value:timer.exclusive) exclusive+=value;
        if (exclusive!=timer.inclusive[0] || exclusive+timer.other!=timer.end-timer.start) {
            fail("Invalid tile frame partition"); return false;
        }
        rows.capture(completed++,id,timer); event.capture(id,timer); event.commit(); return true;
    }
    static void cancelFrame() { frameOpen=false; if (timer!=null) timer.cancel(); }
    /** Zero is inactive, foreign-thread or outside-root work. Capture hooks never allocate or write. */
    public static int enter(int category) {
        if (!owns() || !frameOpen || !timer.active) return 0;
        if (category<0 || category>=GROUPS) { timer.fail("Invalid tile category"); return 0; }
        if (category!=0 && timer.activeDepth[0]==0) return 0;
        if (timer.calls[category]==Integer.MAX_VALUE) { timer.fail("Tile call counter overflow"); return 0; }
        return timer.enter(category,System.nanoTime());
    }
    public static void exit(int token) {
        if (token==0 || !owns() || !frameOpen || !timer.active) return;
        timer.exit(token,System.nanoTime());
    }
    static String diagnostic() { return problem!=null ? problem : timer==null ? null : timer.error; }
    static String profile() { return selectedProfile==null ? "unknown" : selectedProfile; }
    static void finish(Path cache) throws Exception {
        if (owner==null || finished) return;
        if (Thread.currentThread()!=owner) throw new IllegalStateException("Tile profile finish requires owner thread");
        enabled=false; finished=true; cancelFrame(); remove();
        if (completed==0) fail("No complete tile frames");
        String diagnostic=diagnostic();
        // Persist an explicit status even for an invalid capture; the stage owner propagates it.
        Files.writeString(cache.resolve("driving-tiles-status.txt"),
                "version=1 complete_frames="+completed+" max_frames="+CAPACITY+" profile="+profile()
                +" diagnostic="+(diagnostic==null ? "none" : diagnostic.replaceAll("[\\s=]+","_"))
                +" coverage=renderTilesInternal-descendants inclusive=category-union-nonadditive"
                +" exclusive=tile-stack-only partition=exclusive-plus-other-equals-wall\n");
        try (BufferedWriter out=Files.newBufferedWriter(cache.resolve("driving-tiles.csv"))) {
            out.write("frame_id,nano_start,nano_end,wall_ns");
            for (String name:NAMES) out.write(","+name+"_inclusive_ns,"+name+"_exclusive_ns,"+name+"_calls");
            out.write(",other_exclusive_ns\n");
            for (int i=0;i<completed;i++) {
                out.write(rows.ids[i]+","+rows.starts[i]+","+rows.ends[i]+","+rows.wall[i]);
                for (int group=0;group<GROUPS;group++)
                    out.write(","+rows.inclusive[group][i]+","+rows.exclusive[group][i]+","+rows.calls[group][i]);
                out.write(","+rows.other[i]+"\n");
            }
        }
    }
    static void abort() { enabled=false; cancelFrame(); remove(); finished=true; }
    private static String digest(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }
    private static String resourceDigest(String target) throws Exception {
        try (var input=TileProfiler.class.getClassLoader().getResourceAsStream(target+".class")) {
            if (input==null) throw new IllegalStateException("Missing tile profile source "+target);
            return digest(input.readAllBytes());
        }
    }
    private static void install() throws Exception {
        instrumentation=Accessor.tryGet(Loader.class,"g_instrumentation",null);
        if (instrumentation==null || !instrumentation.isRetransformClassesSupported())
            throw new IllegalStateException("Tile profile requires ZombieBuddy retransformation");
        transformer=new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,ProtectionDomain domain,byte[] bytes) {
                if (!CELL.equals(name) && !MANAGER.equals(name)) return null;
                byte[] result=weave(bytes,selectedProfile);
                if (CELL.equals(name)) cellWoven=result!=null; else managerWoven=result!=null;
                if (result==null && enabled) fail("Tile method boundary changed during capture");
                return result;
            }
        };
        cellWoven=false; managerWoven=false; instrumentation.addTransformer(transformer,true);
        for (String name:new String[]{CELL,MANAGER}) {
            Class<?> target=Arrays.stream(instrumentation.getAllLoadedClasses())
                    .filter(type -> type.getName().equals(name.replace('/','.'))).findFirst().orElse(null);
            if (target==null) Class.forName(name.replace('/','.'),false,TileProfiler.class.getClassLoader());
            else instrumentation.retransformClasses(target);
        }
        if (!cellWoven || !managerWoven) throw new IllegalStateException("Tile profile method boundary/shape mismatch");
    }
    private static void remove() {
        if (instrumentation!=null && transformer!=null) instrumentation.removeTransformer(transformer);
        transformer=null;
    }
    /** Identical serialization to DetailHooks.boundary, preserving each actual target owner. */
    private static byte[] boundary(byte[] bytes,String method,String descriptor) {
        ClassWriter output=new ClassWriter(0);
        output.visit(Opcodes.V17,Opcodes.ACC_PUBLIC,new ClassReader(bytes).getClassName(),null,"java/lang/Object",null);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                return name.equals(method) && desc.equals(descriptor)
                        ? output.visitMethod(access,name,desc,signature,exceptions) : null;
            }
        },ClassReader.SKIP_DEBUG);
        output.visitEnd(); return output.toByteArray();
    }
    private static String boundaryDigest(byte[] bytes,String key) throws Exception {
        int split=key.indexOf('('); return digest(boundary(bytes,key.substring(0,split),key.substring(split)));
    }
    static byte[] weave(byte[] bytes) { return weave(bytes,null); }
    static byte[] weave(byte[] bytes,String requiredProfile) {
        try {
            if (bytes==null) return null;
            String owner=new ClassReader(bytes).getClassName();
            if (MANAGER.equals(owner)) {
                if (requiredProfile!=null && !requiredProfile.equals("native") && !requiredProfile.equals("official")) return null;
                return MANAGER_BOUNDARY.equals(boundaryDigest(bytes,"endFrame()V"))
                        ? weaveMethods(bytes,Map.of("endFrame()V",5)) : null;
            }
            if (!CELL.equals(owner)) return null;
            String root=boundaryDigest(bytes,"renderTilesInternal(I)V");
            String flavor=root.equals(NATIVE_PINS.get("renderTilesInternal(I)V")) ? "native"
                    : root.equals(OFFICIAL_PINS.get("renderTilesInternal(I)V")) ? "official" : null;
            if (flavor==null || requiredProfile!=null && !flavor.equals(requiredProfile)) return null;
            Map<String,String> pins=flavor.equals("native") ? NATIVE_PINS : OFFICIAL_PINS;
            Map<String,Integer> targets=flavor.equals("native") ? NATIVE_TARGETS : OFFICIAL_TARGETS;
            for (var pin:pins.entrySet()) if (!pin.getValue().equals(boundaryDigest(bytes,pin.getKey()))) return null;
            if (flavor.equals("native")) {
                boolean[] extra={false};
                new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
                    @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                        for (String key:OFFICIAL_TARGETS.keySet())
                            if (!NATIVE_TARGETS.containsKey(key) && key.startsWith(name+"(")) extra[0]=true;
                        return null;
                    }
                },ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG);
                if (extra[0]) return null;
            }
            return weaveMethods(bytes,targets);
        } catch (Exception | LinkageError invalid) { return null; }
    }
    /** Production calls only after pins match; exposed package-locally for semantic fixtures. */
    static byte[] weaveMethods(byte[] bytes,Map<String,Integer> targets) {
        if (bytes==null || targets==null || targets.isEmpty()) return null;
        try {
            Map<String,Integer> locals=new LinkedHashMap<>(), counts=new LinkedHashMap<>();
            for (var target:targets.entrySet()) {
                if (target.getKey()==null || target.getValue()==null || target.getValue()<0 || target.getValue()>=GROUPS) return null;
                locals.put(target.getKey(),-1); counts.put(target.getKey(),0);
            }
            ClassReader reader=new ClassReader(bytes);
            reader.accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                    String key=name+desc;
                    if (!targets.containsKey(key)) return null;
                    counts.put(key,counts.get(key)+1);
                    if ((access & (Opcodes.ACC_ABSTRACT | Opcodes.ACC_NATIVE))!=0 || name.equals("<init>") || name.equals("<clinit>")) return null;
                    return new MethodVisitor(Opcodes.ASM9) {
                        @Override public void visitMaxs(int stack,int count) { locals.put(key,count); }
                    };
                }
            },ClassReader.SKIP_DEBUG);
            for (String key:targets.keySet()) if (counts.get(key)!=1 || locals.get(key)<0 || locals.get(key)>65532) return null;
            ClassWriter output=new ClassWriter(reader,ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
            reader.accept(new ClassVisitor(Opcodes.ASM9,output) {
                @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                    MethodVisitor next=super.visitMethod(access,name,desc,signature,exceptions);
                    String key=name+desc;
                    if (!targets.containsKey(key)) return next;
                    int tokenSlot=locals.get(key), category=targets.get(key);
                    return new MethodVisitor(Opcodes.ASM9,next) {
                        final net.bytebuddy.jar.asm.Label start=new net.bytebuddy.jar.asm.Label(), end=new net.bytebuddy.jar.asm.Label(), handler=new net.bytebuddy.jar.asm.Label();
                        void close() {
                            super.visitVarInsn(Opcodes.ILOAD,tokenSlot);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,OWNER,"exit","(I)V",false);
                        }
                        @Override public void visitCode() {
                            super.visitCode(); super.visitLdcInsn(category);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,OWNER,"enter","(I)I",false);
                            super.visitVarInsn(Opcodes.ISTORE,tokenSlot); super.visitLabel(start);
                        }
                        @Override public void visitInsn(int opcode) {
                            // Leave each original return operand on its stack, including boolean/int and wide values.
                            if (opcode>=Opcodes.IRETURN && opcode<=Opcodes.RETURN) close();
                            super.visitInsn(opcode);
                        }
                        @Override public void visitMaxs(int stack,int count) {
                            super.visitLabel(end); super.visitLabel(handler);
                            super.visitTryCatchBlock(start,end,handler,"java/lang/Throwable");
                            super.visitVarInsn(Opcodes.ASTORE,tokenSlot+1); close();
                            super.visitVarInsn(Opcodes.ALOAD,tokenSlot+1); super.visitInsn(Opcodes.ATHROW);
                            super.visitMaxs(0,0);
                        }
                    };
                }
            },ClassReader.SKIP_FRAMES);
            return output.toByteArray();
        } catch (Exception | LinkageError invalid) { return null; }
    }
    private static final class Rows {
        final long[] ids=new long[CAPACITY], starts=new long[CAPACITY], ends=new long[CAPACITY], wall=new long[CAPACITY], other=new long[CAPACITY];
        final long[][] inclusive=new long[GROUPS][CAPACITY], exclusive=new long[GROUPS][CAPACITY];
        final int[][] calls=new int[GROUPS][CAPACITY];
        void capture(int index,long id,StageProfiler.Timer value) {
            ids[index]=id; starts[index]=value.start; ends[index]=value.end; wall[index]=value.end-value.start; other[index]=value.other;
            for (int group=0;group<GROUPS;group++) {
                inclusive[group][index]=value.inclusive[group]; exclusive[group][index]=value.exclusive[group]; calls[group][index]=value.calls[group];
            }
        }
    }
    @Name("pz.driving.Tiles") @Label("Driving tile method attribution") @Category({"PZ","Driving"}) @StackTrace(false)
    @Description("Independent owner-thread wall stack. Inclusive values are category unions; exclusive values partition the root. Attribution does not establish optimization gain.")
    public static final class TileFrameEvent extends Event {
        public long frameId, nanoStart, nanoEnd;
        @Timespan(Timespan.NANOSECONDS) public long wallNs, otherExclusiveNs;
        @Timespan(Timespan.NANOSECONDS) public long tilesInternalInclusiveNs, tilesInternalExclusiveNs;
        public int tilesInternalCalls;
        @Timespan(Timespan.NANOSECONDS) public long performInclusiveNs, performExclusiveNs;
        public int performCalls;
        @Timespan(Timespan.NANOSECONDS) public long scheduleInclusiveNs, scheduleExclusiveNs;
        public int scheduleCalls;
        @Timespan(Timespan.NANOSECONDS) public long bakeInclusiveNs, bakeExclusiveNs;
        public int bakeCalls;
        @Timespan(Timespan.NANOSECONDS) public long precountInclusiveNs, precountExclusiveNs;
        public int precountCalls;
        @Timespan(Timespan.NANOSECONDS) public long compositeInclusiveNs, compositeExclusiveNs;
        public int compositeCalls;
        @Timespan(Timespan.NANOSECONDS) public long chunkInclusiveNs, chunkExclusiveNs;
        public int chunkCalls;
        @Timespan(Timespan.NANOSECONDS) public long movingInclusiveNs, movingExclusiveNs;
        public int movingCalls;
        @Timespan(Timespan.NANOSECONDS) public long translucentInclusiveNs, translucentExclusiveNs;
        public int translucentCalls;
        @Timespan(Timespan.NANOSECONDS) public long terrainInclusiveNs, terrainExclusiveNs;
        public int terrainCalls;
        @Timespan(Timespan.NANOSECONDS) public long itemsInclusiveNs, itemsExclusiveNs;
        public int itemsCalls;
        @Timespan(Timespan.NANOSECONDS) public long charactersInclusiveNs, charactersExclusiveNs;
        public int charactersCalls;
        @Timespan(Timespan.NANOSECONDS) public long lightingInclusiveNs, lightingExclusiveNs;
        public int lightingCalls;
        @Timespan(Timespan.NANOSECONDS) public long otherWorldInclusiveNs, otherWorldExclusiveNs;
        public int otherWorldCalls;
        @Timespan(Timespan.NANOSECONDS) public long preparationInclusiveNs, preparationExclusiveNs;
        public int preparationCalls;
        void capture(long id,StageProfiler.Timer t) {
            frameId=id; nanoStart=t.start; nanoEnd=t.end; wallNs=t.end-t.start; otherExclusiveNs=t.other;
            tilesInternalInclusiveNs=t.inclusive[0]; tilesInternalExclusiveNs=t.exclusive[0]; tilesInternalCalls=t.calls[0];
            performInclusiveNs=t.inclusive[1]; performExclusiveNs=t.exclusive[1]; performCalls=t.calls[1];
            scheduleInclusiveNs=t.inclusive[2]; scheduleExclusiveNs=t.exclusive[2]; scheduleCalls=t.calls[2];
            bakeInclusiveNs=t.inclusive[3]; bakeExclusiveNs=t.exclusive[3]; bakeCalls=t.calls[3];
            precountInclusiveNs=t.inclusive[4]; precountExclusiveNs=t.exclusive[4]; precountCalls=t.calls[4];
            compositeInclusiveNs=t.inclusive[5]; compositeExclusiveNs=t.exclusive[5]; compositeCalls=t.calls[5];
            chunkInclusiveNs=t.inclusive[6]; chunkExclusiveNs=t.exclusive[6]; chunkCalls=t.calls[6];
            movingInclusiveNs=t.inclusive[7]; movingExclusiveNs=t.exclusive[7]; movingCalls=t.calls[7];
            translucentInclusiveNs=t.inclusive[8]; translucentExclusiveNs=t.exclusive[8]; translucentCalls=t.calls[8];
            terrainInclusiveNs=t.inclusive[9]; terrainExclusiveNs=t.exclusive[9]; terrainCalls=t.calls[9];
            itemsInclusiveNs=t.inclusive[10]; itemsExclusiveNs=t.exclusive[10]; itemsCalls=t.calls[10];
            charactersInclusiveNs=t.inclusive[11]; charactersExclusiveNs=t.exclusive[11]; charactersCalls=t.calls[11];
            lightingInclusiveNs=t.inclusive[12]; lightingExclusiveNs=t.exclusive[12]; lightingCalls=t.calls[12];
            otherWorldInclusiveNs=t.inclusive[13]; otherWorldExclusiveNs=t.exclusive[13]; otherWorldCalls=t.calls[13];
            preparationInclusiveNs=t.inclusive[14]; preparationExclusiveNs=t.exclusive[14]; preparationCalls=t.calls[14];
        }
    }
}
