package net.alexredby.pztoolkitjavapatches;

import java.io.InputStream;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.management.ManagementFactory;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Random;
import java.util.function.Consumer;
import java.util.zip.ZipFile;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.Label;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import zombie.util.list.PZArrayList;

/** Execute the caller's real union instructions against the production helper. */
@SuppressWarnings({"rawtypes", "unchecked"})
public final class TranslucentUnionChecks {
    private static final String CELL = "zombie/iso/fboRenderChunk/FBORenderCell";
    private static final String SQUARE = "zombie/iso/IsoGridSquare";
    private static final String PL = "zombie/util/list/PZArrayList";
    private static final String HELPER = "net/alexredby/pztoolkitjavapatches/TranslucentSquareUnion";
    private static final String CALLER = "(ILzombie/iso/IsoChunk;I)V";
    private static final String UNION = "(L" + PL + ";Ljava/util/List;Ljava/util/List;Ljava/util/List;)V";
    private static int generated;
    private static volatile int sink;
    private static com.sun.management.ThreadMXBean allocations;

    private record Op(String kind, int code, int var, String owner, String name,
                      Label label, Consumer<MethodVisitor> emit) {}

    private static byte[] resource(String name) throws Exception {
        try (InputStream in = TranslucentUnionChecks.class.getClassLoader().getResourceAsStream(name + ".class")) {
            require(in != null, "Missing class resource: " + name);
            return in.readAllBytes();
        }
    }

    /** Only the square fixture and production helper are child-first; utility classes stay real. */
    private static final class FixtureLoader extends ClassLoader {
        FixtureLoader() { super(TranslucentUnionChecks.class.getClassLoader()); }
        @Override protected synchronized Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
            if (!name.equals(SQUARE.replace('/', '.')) && !name.startsWith(HELPER.replace('/', '.'))) {
                return super.loadClass(name, resolve);
            }
            Class<?> result = findLoadedClass(name);
            if (result == null) {
                try {
                    byte[] bytes = name.equals(SQUARE.replace('/', '.')) ? squareFixture() : resource(name.replace('.', '/'));
                    result = defineClass(name, bytes, 0, bytes.length);
                } catch (Exception error) { throw new ClassNotFoundException(name, error); }
            }
            if (resolve) resolveClass(result);
            return result;
        }
        Class<?> define(String name, byte[] bytes) { return defineClass(name.replace('/', '.'), bytes, 0, bytes.length); }
    }

    private static byte[] squareFixture() {
        ClassWriter w = new ClassWriter(0);
        w.visit(Opcodes.V17, Opcodes.ACC_PUBLIC | Opcodes.ACC_FINAL, SQUARE, null, "java/lang/Object", null);
        for (String field : List.of("x", "y", "z")) w.visitField(Opcodes.ACC_PUBLIC, field, "I", null, null).visitEnd();
        MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0);
        m.visitMethodInsn(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false);
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(1, 1); m.visitEnd(); w.visitEnd();
        return w.toByteArray();
    }

    private static List<Op> instructions(byte[] bytes) {
        List<Op> result = new ArrayList<>();
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                if (!n.equals("renderOneLevel_Translucent") || !d.equals(CALLER)) return null;
                return new MethodVisitor(Opcodes.ASM9) {
                    private void add(String k, int c, int v, String o, String n, Label l, Consumer<MethodVisitor> emit) {
                        result.add(new Op(k, c, v, o, n, l, emit));
                    }
                    @Override public void visitVarInsn(int c, int v) { add("var", c, v, null, null, null, m -> m.visitVarInsn(c, v)); }
                    @Override public void visitInsn(int c) { add("insn", c, 0, null, null, null, m -> m.visitInsn(c)); }
                    @Override public void visitMethodInsn(int c, String o, String n, String d, boolean itf) {
                        add("call", c, 0, o, n, null, m -> m.visitMethodInsn(c, o, n, d, itf));
                    }
                    @Override public void visitTypeInsn(int c, String t) { add("type", c, 0, t, null, null, m -> m.visitTypeInsn(c, t)); }
                    @Override public void visitFieldInsn(int c, String o, String n, String d) {
                        add("field", c, 0, o, n, null, m -> m.visitFieldInsn(c, o, n, d));
                    }
                    @Override public void visitJumpInsn(int c, Label l) { add("jump", c, 0, null, null, l, m -> m.visitJumpInsn(c, l)); }
                    @Override public void visitLabel(Label l) { add("label", 0, 0, null, null, l, m -> m.visitLabel(l)); }
                    @Override public void visitIincInsn(int v, int i) { add("inc", 0, v, null, null, null, m -> m.visitIincInsn(v, i)); }
                    @Override public void visitIntInsn(int c, int v) { add("unsupported", c, v, null, null, null, null); }
                    @Override public void visitLdcInsn(Object x) { add("unsupported", 0, 0, null, null, null, null); }
                    @Override public void visitInvokeDynamicInsn(String n, String d, net.bytebuddy.jar.asm.Handle b, Object... x) {
                        add("unsupported", 0, 0, null, n, null, null);
                    }
                };
            }
        }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        return result;
    }

    /** Extract instructions at runtime; no engine method bodies are committed in this test. */
    private static MethodHandle extract(FixtureLoader loader, byte[] bytes, boolean woven) throws Throwable {
        List<Op> ops = instructions(bytes);
        int add = -1, helper = -1, contains = 0;
        for (int i = 0; i < ops.size(); i++) {
            Op op = ops.get(i);
            if ("call".equals(op.kind) && "zombie/util/list/PZArrayUtil".equals(op.owner) && "addAll".equals(op.name)) {
                require(add == -1, "Multiple union addAll calls"); add = i;
            }
            if ("call".equals(op.kind) && HELPER.equals(op.owner) && "tryBuild".equals(op.name)) {
                require(helper == -1, "Multiple helper calls"); helper = i;
            }
            if (PL.equals(op.owner) && "contains".equals(op.name)) contains++;
        }
        require(add >= 2 && contains == 2 && (woven ? helper >= 4 : helper == -1), "Union shape changed");
        int sorted = ops.get(add - 2).var;
        require(ops.get(add - 2).code == Opcodes.ALOAD && ops.get(add - 1).var == 8, "Union input locals changed");
        int begin = woven ? helper - 4 : add - 2;
        Label endLabel = null; int loops = 0;
        for (int i = add + 1; i < ops.size(); i++) {
            if (ops.get(i).code == Opcodes.IF_ICMPGE && ++loops == 2) { endLabel = ops.get(i).label; break; }
        }
        Label helperEnd = null;
        if (woven) for (int i = helper + 1; i < add; i++) if (ops.get(i).code == Opcodes.IFNE) { helperEnd = ops.get(i).label; break; }
        require(!woven || helperEnd != null, "Missing helper short circuit");
        int end = -1, helperTarget = -1;
        for (int i = add + 1; i < ops.size(); i++) if ("label".equals(ops.get(i).kind)) {
            if (ops.get(i).label == endLabel) end = i;
            if (ops.get(i).label == helperEnd) helperTarget = i;
        }
        require(end > add, "Missing union end");
        require(!woven || helperTarget > add, "Missing helper target");
        if (woven) for (int i = Math.min(end, helperTarget); i <= Math.max(end, helperTarget); i++) {
            require("label".equals(ops.get(i).kind), "Helper does not branch to union end");
        }
        end = Math.max(end, helperTarget);
        String name = "unionfixture/Actual" + generated++;
        ClassWriter w = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
        w.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, name, null, "java/lang/Object", null);
        MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "run", UNION, null, null);
        m.visitCode();
        for (int[] move : new int[][] {{3, 6}, {2, 7}, {1, 8}, {0, sorted}}) {
            m.visitVarInsn(Opcodes.ALOAD, move[0]); m.visitVarInsn(Opcodes.ASTORE, move[1]);
        }
        for (int i = begin; i <= end; i++) {
            Op op = ops.get(i); require(op.emit != null, "Unsupported instruction inside union: " + op.kind);
            op.emit.accept(m);
        }
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(0, 0); m.visitEnd(); w.visitEnd();
        return MethodHandles.lookup().findStatic(loader.define(name, w.toByteArray()), "run",
                MethodType.methodType(void.class, PZArrayList.class, List.class, List.class, List.class));
    }

    private record Outcome(Throwable error, Object[] prefix) {}
    private static Outcome run(MethodHandle body, PZArrayList target, List a, List b, List c) {
        Throwable error = null;
        try { body.invokeExact(target, a, b, c); } catch (Throwable caught) { error = caught; }
        return new Outcome(error, Arrays.copyOf(target.getElements(), target.size(), Object[].class));
    }
    private static void equal(Outcome expected, Outcome actual, String context) {
        require((expected.error == null ? null : expected.error.getClass()) ==
                (actual.error == null ? null : actual.error.getClass()), context + " exception differs");
        require(expected.prefix.length == actual.prefix.length, context + " prefix length differs");
        for (int i = 0; i < expected.prefix.length; i++) require(expected.prefix[i] == actual.prefix[i], context + " reference differs at " + i);
    }
    private static Outcome sort(Outcome before, Comparator comparator) {
        if (before.error != null) return before;
        Object[] values = before.prefix.clone(); Throwable error = null;
        try { Arrays.sort(values, comparator); } catch (Throwable caught) { error = caught; }
        return new Outcome(error, values);
    }
    private static void compare(MethodHandle original, MethodHandle woven, Class<?> square, Comparator comparator,
                                List a, List b, List c, String context) {
        Outcome expected = run(original, new PZArrayList(square, 512), a, b, c);
        Outcome actual = run(woven, new PZArrayList(square, 512), a, b, c);
        equal(expected, actual, context + " before sort");
        equal(sort(expected, comparator), sort(actual, comparator), context + " after sort");
    }

    private static byte[] mutate(byte[] bytes) {
        ClassWriter w = new ClassWriter(0);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9, w) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                MethodVisitor output = super.visitMethod(a, n, d, s, e);
                if (!n.equals("renderOneLevel_Translucent") || !d.equals(CALLER)) return output;
                return new MethodVisitor(Opcodes.ASM9, output) {
                    @Override public void visitMethodInsn(int c, String o, String name, String type, boolean itf) {
                        super.visitMethodInsn(c, o, PL.equals(o) && name.equals("contains") ? "containsReference" : name, type, itf);
                    }
                };
            }
        }, 0);
        return w.toByteArray();
    }
    private static byte[] invokeTransform(Class<?> helper, String name, byte[] bytes) throws Throwable {
        Method m = helper.getDeclaredMethod(name, byte[].class); m.setAccessible(true);
        try { return (byte[]) m.invoke(null, (Object) bytes); }
        catch (InvocationTargetException error) { throw error.getCause(); }
    }
    private static boolean tryBuild(Method helper, PZArrayList target, List a, List b, List c) throws Throwable {
        try { return (boolean) helper.invoke(null, target, a, b, c); }
        catch (InvocationTargetException error) { throw error.getCause(); }
    }
    private static ArrayList list(Object[] pool, int start, int count) {
        ArrayList out = new ArrayList(); for (int i = 0; i < count; i++) out.add(pool[(start + i) % pool.length]); return out;
    }

    private static void scratchChecks(Class<?> helper, Class<?> square, Object[] pool) throws Throwable {
        var field = helper.getDeclaredField("SCRATCH"); field.setAccessible(true);
        Object scratch = ((ThreadLocal<?>) field.get(null)).get();
        Class<?> type = scratch.getClass();
        var entries = type.getDeclaredField("entries"); entries.setAccessible(true);
        var count = type.getDeclaredField("count"); count.setAccessible(true);
        var busy = type.getDeclaredField("busy"); busy.setAccessible(true);
        var containsNull = type.getDeclaredField("containsNull"); containsNull.setAccessible(true);
        Method add = type.getDeclaredMethod("add", Object.class); add.setAccessible(true);
        Method clear = type.getDeclaredMethod("clear"); clear.setAccessible(true);
        Method build = helper.getMethod("tryBuild", PZArrayList.class, List.class, List.class, List.class);
        require(count.getInt(scratch) == 0 && !busy.getBoolean(scratch) && !containsNull.getBoolean(scratch), "Scratch state retained after calls");
        for (Object value : (Object[]) entries.get(scratch)) require(value == null, "Scratch retained square reference");
        busy.setBoolean(scratch, true);
        try {
            PZArrayList target = new PZArrayList(square, 512);
            require(!tryBuild(build, target, list(pool, 0, 64), list(pool, 64, 64), list(pool, 128, 64))
                    && target.isEmpty() && busy.getBoolean(scratch), "Reentrant fallback changed outer state");
        } finally { busy.setBoolean(scratch, false); }
        // Deliberately collide in the real table's hash mask, including wraparound.
        int mask = ((Object[]) entries.get(scratch)).length - 1;
        ArrayList colliding = new ArrayList();
        for (int i = 0; colliding.size() < 16 && i < 200000; i++) {
            Object candidate = square.getConstructor().newInstance();
            if ((System.identityHashCode(candidate) & mask) == mask) colliding.add(candidate);
        }
        require(colliding.size() == 16, "Could not create bounded identity collision fixture");
        try {
            for (Object value : colliding) require((boolean) add.invoke(scratch, value), "Collision lost unique reference");
            for (Object value : colliding) require(!(boolean) add.invoke(scratch, value), "Collision lost duplicate reference");
            require((boolean) add.invoke(scratch, new Object[] {null}) && !(boolean) add.invoke(scratch, new Object[] {null}), "Null membership differs");
        } finally { clear.invoke(scratch); }
        require(count.getInt(scratch) == 0 && !containsNull.getBoolean(scratch), "Collision scratch not reset");
        for (Object value : (Object[]) entries.get(scratch)) require(value == null, "Collision scratch retained reference");
        // Throw after conversion has had enough comparisons to populate the table.
        ArrayList invalid = list(pool, 128, 64); invalid.set(60, "invalid after hashed conversion");
        boolean failed = false;
        try { tryBuild(build, new PZArrayList(square, 512), list(pool, 0, 64), list(pool, 64, 64), invalid); }
        catch (ClassCastException expected) { failed = true; }
        require(failed, "Missing cast failure after hashed conversion");
        require(count.getInt(scratch) == 0 && !busy.getBoolean(scratch) && !containsNull.getBoolean(scratch), "Exceptional scratch state retained");
        for (Object value : (Object[]) entries.get(scratch)) require(value == null, "Exceptional scratch retained reference");
    }

    private static int checkInput(FixtureLoader loader, Class<?> helper, Class<?> square, Object[] pool,
                                  Comparator comparator, byte[] original, boolean official) throws Throwable {
        byte[] woven = invokeTransform(helper, official ? "transformReviewed" : "weave", original);
        require(woven != null, "Reviewed " + (official ? "official" : "native") + " input rejected");
        require(invokeTransform(helper, "weave", woven) == null, "Double weave accepted");
        require(invokeTransform(helper, "weave", mutate(original)) == null, "Changed caller accepted");
        MethodHandle control = extract(loader, original, false), candidate = extract(loader, woven, true);
        Random random = new Random(34318); int cases = 0;
        for (int run = 0; run < 2000; run++) {
            ArrayList[] lists = {new ArrayList(), new ArrayList(), new ArrayList()};
            for (ArrayList source : lists) {
                int n = random.nextInt(180);
                for (int i = 0; i < n; i++) source.add(random.nextInt(37) == 0 ? null : pool[random.nextInt(220)]);
            }
            compare(control, candidate, square, comparator, lists[0], lists[1], lists[2], "random " + run); cases++;
        }
        for (int total : new int[] {0, 63, 64, 127, 128, 129, 191, 192, 511, 512, 513, 600}) {
            compare(control, candidate, square, comparator, list(pool, 0, total / 3),
                    list(pool, 20, total / 3), list(pool, 40, total - 2 * (total / 3)), "threshold " + total);
            compare(control, candidate, square, comparator, list(pool, 0, total), new ArrayList(), new ArrayList(), "items-only " + total);
        }
        ArrayList repeated = new ArrayList(); for (int i = 0; i < 128; i++) repeated.add(pool[0]);
        compare(control, candidate, square, comparator, list(pool, 0, 64), repeated, repeated, "repeat-first");
        compare(control, candidate, square, comparator, repeated, list(pool, 0, 64), list(pool, 32, 64), "duplicate-items");
        for (int source = 0; source < 3; source++) {
            List[] lists = {list(pool, 0, 64), list(pool, 32, 64), list(pool, 64, 64)};
            ((ArrayList) lists[source]).set(40, "invalid raw entry");
            compare(control, candidate, square, comparator, lists[0], lists[1], lists[2], "raw source " + source);
            lists[source] = null;
            compare(control, candidate, square, comparator, lists[0], lists[1], lists[2], "null source " + source);
        }
        Method build = helper.getMethod("tryBuild", PZArrayList.class, List.class, List.class, List.class);
        PZArrayList accepted = new PZArrayList(square, 512);
        require(tryBuild(build, accepted, list(pool, 0, 64), list(pool, 64, 64), list(pool, 128, 64)),
                "Dense supported input did not use helper");
        equal(run(control, new PZArrayList(square, 512), list(pool, 0, 64), list(pool, 64, 64), list(pool, 128, 64)),
                new Outcome(null, Arrays.copyOf(accepted.getElements(), accepted.size(), Object[].class)), "accepted helper");
        for (List[] rejected : List.of(
                new List[] {list(pool, 0, 65), list(pool, 64, 63), new ArrayList()},
                new List[] {list(pool, 0, 170), list(pool, 64, 170), list(pool, 128, 173)})) {
            PZArrayList unchanged = new PZArrayList(square, 512);
            require(!tryBuild(build, unchanged, rejected[0], rejected[1], rejected[2]) && unchanged.isEmpty(),
                    "Ineligible sizes partially changed target");
        }
        PZArrayList nonempty = new PZArrayList(square, 8); nonempty.add(pool[0]);
        require(!tryBuild(build, nonempty, list(pool, 0, 64), list(pool, 64, 64), list(pool, 128, 64)) && nonempty.size() == 1,
                "Nonempty target changed");
        List custom = new ArrayList(list(pool, 0, 64)) {};
        PZArrayList target = new PZArrayList(square, 512);
        require(!tryBuild(build, target, custom, list(pool, 64, 64), list(pool, 128, 64)) && target.isEmpty(), "Custom list changed target");
        compare(control, candidate, square, comparator, custom, list(pool, 64, 64), list(pool, 128, 64), "custom fallback");
        // Repeated accepted calls after exception/fallback detect retained membership decisions.
        for (int call = 0; call < 20; call++) compare(control, candidate, square, comparator,
                list(pool, call, 64), list(pool, 64 + call, 64), list(pool, 128 + call, 64), "repeated " + call);
        scratchChecks(helper, square, pool);
        if (Boolean.getBoolean("pz.test.union.benchmark")) benchmark(control, candidate, square, pool, official ? "official" : "native");
        return cases;
    }

    private record Sample(long nanos, long bytes) {}
    private static Sample measure(MethodHandle body, Class<?> square, List a, List b, List c, int count) throws Throwable {
        PZArrayList target = new PZArrayList(square, 512); int checksum = 0;
        long allocated = allocations == null ? -1 : allocations.getThreadAllocatedBytes(Thread.currentThread().threadId());
        long begin = System.nanoTime();
        for (int i = 0; i < count; i++) { target.clear(); body.invokeExact(target, a, b, c); checksum += target.size(); }
        long nanos = System.nanoTime() - begin;
        long bytes = allocations == null ? -1 : allocations.getThreadAllocatedBytes(Thread.currentThread().threadId()) - allocated;
        sink = checksum; return new Sample(nanos, bytes);
    }
    private static void benchmark(MethodHandle original, MethodHandle woven, Class<?> square, Object[] pool, String input) throws Throwable {
        if (ManagementFactory.getThreadMXBean() instanceof com.sun.management.ThreadMXBean bean && bean.isThreadAllocatedMemorySupported()) {
            if (!bean.isThreadAllocatedMemoryEnabled()) bean.setThreadAllocatedMemoryEnabled(true);
            allocations = bean;
        }
        List repeat = new ArrayList(); for (int i = 0; i < 128; i++) repeat.add(pool[0]);
        List same64 = list(pool, 0, 64), same96 = list(pool, 0, 96), same128 = list(pool, 0, 128);
        List<List[]> shapes = List.of(
                new List[] {list(pool, 0, 64), list(pool, 32, 64), list(pool, 64, 64)},
                new List[] {list(pool, 0, 96), list(pool, 48, 96), list(pool, 96, 96)},
                new List[] {same64, same64, same64},
                new List[] {same96, same96, same96},
                new List[] {same128, same128, same128},
                new List[] {list(pool, 0, 64), list(pool, 64, 64), list(pool, 128, 64)},
                new List[] {list(pool, 0, 128), list(pool, 128, 128), list(pool, 256, 128)},
                new List[] {list(pool, 0, 128), list(pool, 64, 128), list(pool, 128, 128)},
                new List[] {list(pool, 0, 16), list(pool, 8, 16), list(pool, 16, 16)},
                new List[] {new ArrayList(), list(pool, 0, 64), list(pool, 64, 64)},
                new List[] {list(pool, 0, 170), list(pool, 85, 170), list(pool, 170, 172)},
                new List[] {list(pool, 0, 64), repeat, repeat},
                new List[] {list(pool, 0, 192), new ArrayList(), new ArrayList()},
                new List[] {list(pool, 0, 128), list(pool, 20, 1), new ArrayList()});
        String[] names = {"dense192", "dense288", "same-unique64", "same-unique96", "same-unique128",
                "disjoint192", "disjoint384", "overlap384", "small16", "eligibility128", "eligibility512",
                "repeat-first", "items-only", "sparse"};
        for (int s = 0; s < shapes.size(); s++) {
            List[] shape = shapes.get(s); int count = 20000;
            for (int warm = 0; warm < 6; warm++) { measure(original, square, shape[0], shape[1], shape[2], count); measure(woven, square, shape[0], shape[1], shape[2], count); }
            long[] left = new long[7], right = new long[7], leftBytes = new long[7], rightBytes = new long[7];
            for (int trial = 0; trial < 7; trial++) {
                Sample a, b;
                if ((trial & 1) == 0) { a = measure(original, square, shape[0], shape[1], shape[2], count); b = measure(woven, square, shape[0], shape[1], shape[2], count); }
                else { b = measure(woven, square, shape[0], shape[1], shape[2], count); a = measure(original, square, shape[0], shape[1], shape[2], count); }
                left[trial] = a.nanos; right[trial] = b.nanos; leftBytes[trial] = a.bytes; rightBytes[trial] = b.bytes;
            }
            Arrays.sort(left); Arrays.sort(right); Arrays.sort(leftBytes); Arrays.sort(rightBytes);
            System.out.printf(Locale.ROOT, "engine=%s union_bench=%s control_ns=%.1f woven_ns=%.1f ratio=%.3f control_b_op=%.2f woven_b_op=%.2f%n", input, names[s],
                    (double) left[3] / count, (double) right[3] / count, (double) right[3] / left[3],
                    allocations == null ? -1.0 : (double) leftBytes[3] / count, allocations == null ? -1.0 : (double) rightBytes[3] / count);
        }
    }

    private static void require(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
    public static void main(String[] args) throws Throwable {
        FixtureLoader loader = new FixtureLoader();
        Class<?> square = loader.loadClass(SQUARE.replace('/', '.')), helper = loader.loadClass(HELPER.replace('/', '.'));
        Object[] pool = new Object[1024];
        for (int i = 0; i < pool.length; i++) {
            pool[i] = square.getConstructor().newInstance();
            // Pairs have equal coordinates but distinct identity; both z levels participate in union.
            square.getField("x").setInt(pool[i], (i / 2) % 8);
            square.getField("y").setInt(pool[i], (i / 2) / 8);
            square.getField("z").setInt(pool[i], i % 2);
        }
        var x = square.getField("x"); var y = square.getField("y");
        Comparator comparator = (a, b) -> {
            try { return (x.getInt(a) + y.getInt(a) * 262144) - (x.getInt(b) + y.getInt(b) * 262144); }
            catch (IllegalAccessException error) { throw new AssertionError(error); }
        };
        int cases = checkInput(loader, helper, square, pool, comparator, resource(CELL), false);
        String archive = System.getProperty("pz.test.optimizer.archive", System.getenv("PZ_TEST_OPTIMIZER_ARCHIVE"));
        if (archive != null) {
            byte[] official;
            try (ZipFile zip = new ZipFile(Path.of(archive).toFile())) { official = zip.getInputStream(zip.getEntry(CELL + ".class")).readAllBytes(); }
            require(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(official)).equals(
                    "646ef5e25432f02a1d0e00848585fb450985bf89887519a458f0f07271350748"), "Unreviewed official caller resource");
            cases += checkInput(loader, helper, square, pool, comparator, official, true);
        }
        System.out.println("TRANSLUCENT_UNION_CHECKS_PASS (actual caller union and woven fallback, " + cases + " randomized cases, reference order, sort, raw exceptions)");
    }
}
