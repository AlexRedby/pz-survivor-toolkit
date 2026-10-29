package net.alexredby.drivingperf;

import java.lang.reflect.InvocationTargetException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import jdk.jfr.consumer.RecordedEvent;
import jdk.jfr.consumer.RecordingFile;
import net.bytebuddy.jar.asm.*;

/** Real admitted classes are loaded but never invoked; a separate flow fixture exercises the weaver. */
public final class TileProfilerChecks {
    public static final RuntimeException SENTINEL=new RuntimeException("original-flow-error");
    public static final class FlowFixture {
        public static int effects, probes;
        public static long wideValue;
        public static boolean probe(int value) {
            probes++;
            if (value<0) throw SENTINEL;
            return (value&1)!=0;
        }
        public static long wide(long value) { return value ^ 0x1122334455667788L; }
        public static void renderTilesInternal(int value) {
            effects++;
            if (value==0) return;
            if (value==7) {
                try { probe(-1); } catch (RuntimeException error) { if (error!=SENTINEL) throw error; }
                return;
            }
            if (value==8) { renderTilesInternal(1); return; }
            effects+=probe(value) ? 10 : 20;
            wideValue=wide(value);
        }
    }
    static void check(boolean value,String label) { if (!value) throw new AssertionError(label); }
    static void eq(long expected,long actual,String label) { check(expected==actual,label+": "+actual+" != "+expected); }
    static byte[] resource(String name) throws Exception {
        try (var input=TileProfilerChecks.class.getClassLoader().getResourceAsStream(name+".class")) {
            if (input==null) throw new AssertionError("Missing resource "+name);
            return input.readAllBytes();
        }
    }
    static Class<?> loadFlow(byte[] bytes) throws Exception {
        String name=FlowFixture.class.getName();
        return new ClassLoader(TileProfilerChecks.class.getClassLoader()) {
            @Override protected Class<?> loadClass(String requested,boolean resolve) throws ClassNotFoundException {
                if (!requested.equals(name)) return super.loadClass(requested,resolve);
                Class<?> loaded=findLoadedClass(requested);
                if (loaded==null) loaded=defineClass(requested,bytes,0,bytes.length);
                if (resolve) resolveClass(loaded);
                return loaded;
            }
        }.loadClass(name);
    }
    static Throwable invoke(Class<?> type,int value) throws Exception {
        try { type.getMethod("renderTilesInternal",int.class).invoke(null,value); return null; }
        catch (InvocationTargetException error) { return error.getCause(); }
    }
    static byte[] mutate(byte[] bytes,String target) {
        ClassWriter output=new ClassWriter(0);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9,output) {
            @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                MethodVisitor next=super.visitMethod(access,name,desc,signature,exceptions);
                if (!target.equals(name+desc)) return next;
                return new MethodVisitor(Opcodes.ASM9,next) {
                    @Override public void visitCode() { super.visitCode(); super.visitInsn(Opcodes.NOP); }
                };
            }
        },0);
        return output.toByteArray();
    }
    static void admissionChecks() throws Exception {
        byte[] cell=resource(TileProfiler.CELL), manager=resource(TileProfiler.MANAGER);
        String flavor=StageProfiler.DetailHooks.digest(cell).equals(StageProfiler.DetailHooks.NATIVE) ? "native" : "official";
        for (byte[] original:new byte[][]{cell,manager}) {
            byte[] patched=TileProfiler.weave(original,flavor);
            check(patched!=null,"Exact input admitted");
            check(TileProfiler.weave(patched,flavor)==null,"Duplicate weaving rejected");
        }
        check(TileProfiler.weave(cell,flavor.equals("native") ? "official" : "native")==null,"Mixed profile rejected");
        for (String method:List.of("renderTilesInternal(I)V","runChecks(I)Z","renderWaterShore(I)V","renderPlayer(ILzombie/characters/IsoPlayer;)V"))
            check(TileProfiler.weave(mutate(cell,method),flavor)==null,"Changed exact boundary rejected "+method);
        check(TileProfiler.weave(mutate(manager,"endFrame()V"),flavor)==null,"Changed composite boundary rejected");
        check(TileProfiler.weave(null)==null,"Missing bytes rejected");
    }
    static String camel(String name) {
        StringBuilder out=new StringBuilder(); boolean upper=false;
        for (char ch:name.toCharArray()) { if (ch=='_') upper=true; else { out.append(upper ? Character.toUpperCase(ch) : ch); upper=false; } }
        return out.toString();
    }
    public static void main(String[] args) throws Exception {
        Path cache=Path.of(args[0]); Files.createDirectory(cache);
        admissionChecks();
        if (List.of(args).contains("--union")) {
            Class<?> union=Class.forName("net.alexredby.pztoolkitjavapatches.TranslucentSquareUnion");
            check(Boolean.TRUE.equals(union.getMethod("install").invoke(null)),"Existing union installed");
        }
        byte[] original=resource(FlowFixture.class.getName().replace('.','/'));
        check(TileProfiler.weave(original)==null,"Synthetic class rejected by production admission");
        byte[] patched=TileProfiler.weaveMethods(original,Map.of("renderTilesInternal(I)V",0,"probe(I)Z",14,"wide(J)J",5));
        check(patched!=null,"Synthetic semantic helper compiled");
        check(TileProfiler.weaveMethods(original,Map.of("absent()V",0))==null,"Missing hook rejected");
        Class<?> baseline=loadFlow(original), actual=loadFlow(patched);
        System.setProperty("pz.drivingPerf.stageProfile","true");
        System.setProperty("pz.drivingPerf.cachedir",cache.toString());
        StageProfiler.start(cache,Thread.currentThread());
        check(!Files.exists(cache.resolve("driving-tiles.csv")),"No output during capture");
        int[] cases={0,1,2,7,8,-1};
        for (int value:cases) {
            Throwable expected=invoke(baseline,value);
            StageProfiler.frameBegin(1,0,42);
            int token=StageProfiler.enter(StageProfiler.TILES);
            Throwable observed=invoke(actual,value);
            StageProfiler.exit(token); StageProfiler.frameEnd();
            check(expected==observed,"Original throwable identity preserved");
            if (value<0) check(observed==SENTINEL,"Uncaught original sentinel");
            for (String field:List.of("effects","probes","wideValue"))
                check(baseline.getField(field).get(null).equals(actual.getField(field).get(null)),"Original branch/return effects "+field);
            check(TileProfiler.diagnostic()==null,"Balanced method-finally stack");
        }
        StageProfiler.frameBegin(1,0,0);
        java.util.concurrent.atomic.AtomicReference<Throwable> failure=new java.util.concurrent.atomic.AtomicReference<>();
        Thread foreign=new Thread(() -> { try { check(invoke(actual,1)==null,"Foreign flow still executes"); } catch(Throwable error) { failure.set(error); } });
        foreign.start(); foreign.join();
        if (failure.get()!=null) throw new AssertionError(failure.get());
        StageProfiler.frameEnd();
        StageProfiler.frameBegin(1,0,0);
        check(Boolean.TRUE.equals(actual.getMethod("probe",int.class).invoke(null,1)),"Outside-root return intact");
        StageProfiler.frameEnd();
        StageProfiler.frameBegin(1,0,0); // Intentionally partial; no tile row/event must escape.
        if (List.of(args).contains("--export-failure")) {
            Files.createDirectory(cache.resolve("driving-stages.jfr"));
            boolean failed=false;
            try { StageProfiler.finish(); } catch (java.io.IOException expected) { failed=true; }
            check(failed,"Unwritable JFR target rejected");
            for (String name:List.of("enabled","transformer")) {
                var field=TileProfiler.class.getDeclaredField(name); field.setAccessible(true);
                check(name.equals("enabled") ? !field.getBoolean(null) : field.get(null)==null,"Export failure cleans "+name);
            }
            eq(0,TileProfiler.enter(0),"Capture inactive after export failure");
            StageProfiler.finish(); // Idempotent and already clean.
            System.out.println("TILE_EXPORT_FAILURE_CHECKS_PASS");
            return;
        }
        StageProfiler.finish();
        List<String> lines=Files.readAllLines(cache.resolve("driving-tiles.csv"));
        eq(9,lines.size(),"Exactly eight complete tile rows");
        String[] columns=lines.getFirst().split(",");
        List<Map<String,Long>> rows=new ArrayList<>();
        for (int i=1;i<lines.size();i++) {
            String[] values=lines.get(i).split(","); eq(columns.length,values.length,"Column count");
            Map<String,Long> row=new HashMap<>();
            for (int c=0;c<columns.length;c++) row.put(columns[c],Long.parseLong(values[c]));
            rows.add(row);
        }
        long[] roots={1,1,1,1,2,1,0,0}, preparation={0,1,1,1,1,1,0,0};
        for (int i=0;i<rows.size();i++) {
            eq(roots[i],rows.get(i).get("tiles_internal_calls"),"Root branch/reentry/foreign filtering");
            eq(preparation[i],rows.get(i).get("preparation_calls"),"Boolean finally/caught+uncaught exceptions");
        }
        List<RecordedEvent> all=RecordingFile.readAllEvents(cache.resolve("driving-stages.jfr"));
        List<RecordedEvent> tiles=all.stream().filter(e -> e.getEventType().getName().equals("pz.driving.Tiles")).toList();
        eq(rows.size(),tiles.size(),"JFR/CSV complete count");
        for (RecordedEvent event:tiles) {
            Map<String,Long> row=rows.get((int)event.getLong("frameId")-1);
            check(event.getStackTrace()==null,"No per-frame stack trace");
            for (String key:List.of("frame_id","nano_start","nano_end","wall_ns","other_exclusive_ns"))
                eq(row.get(key),event.getLong(camel(key)),"JFR/CSV identity/range "+key);
            for (String name:TileProfiler.NAMES) {
                for (String timing:List.of("inclusive_ns","exclusive_ns"))
                    eq(row.get(name+"_"+timing),event.getLong(camel(name+"_"+timing)),"JFR/CSV timing "+name);
                eq(row.get(name+"_calls"),event.getInt(camel(name+"_calls")),"JFR/CSV calls "+name);
            }
        }
        check(TileProfiler.diagnostic()==null,"Final capture valid");
        System.out.println("TILE_PROFILER_CHECKS_PASS real_classes_loaded=true game_methods_invoked=0 semantic_fixture=true csv_jfr_join=true");
    }
}
