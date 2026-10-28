package net.alexredby.pztoolkitjavapatches;

import java.io.InputStream;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.zip.ZipFile;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import zombie.entity.util.TimSort;
import zombie.util.list.PZArrayList;

/**
 * Bounded correctness experiment, not admission or a performance benchmark.
 * Supply -Dpz.test.optimizer.archive=... (or PZ_TEST_OPTIMIZER_ARCHIVE).
 * Executes the pinned release's cache, the active production union helper and
 * extracted caller union/comparator instructions with native PZArrayList/TimSort.
 * World, chunk and square fixtures expose only the fields those instructions use.
 */
@SuppressWarnings({"rawtypes", "unchecked"})
public final class TranslucentOrderChecks {
    private static final String CELL = "zombie/iso/fboRenderChunk/FBORenderCell";
    private static final String CHUNK = "zombie/iso/IsoChunk";
    private static final String SQUARE = "zombie/iso/IsoGridSquare";
    private static final String WORLD = "zombie/iso/IsoWorld";
    private static final String META = "zombie/iso/IsoMetaGrid";
    private static final String CACHE = "pzopt/TranslucentOrder";
    private static final String UNION = "net/alexredby/pztoolkitjavapatches/TranslucentSquareUnion";
    private static final Map<String, String> PINNED = Map.of(
            CELL, "646ef5e25432f02a1d0e00848585fb450985bf89887519a458f0f07271350748",
            CHUNK, "b64c02249418637e0bebb6e3a5c481f607db346869aa4b9c4409e4b077238a0f",
            CACHE, "bd6a15c04d4b99e64a511c71f6e19662ed3d4b0d0a99cc98113cd1b0296d4455",
            CACHE + "$Entry", "8c7beb1517569d4ba12d80cd71f729a25c77ba42740915fa8dd42a716bb06eba");
    private static int cases;

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static byte[] resource(String name) throws Exception {
        try (InputStream in = TranslucentOrderChecks.class.getClassLoader().getResourceAsStream(name + ".class")) {
            require(in != null, "Missing native resource: " + name);
            return in.readAllBytes();
        }
    }

    private static String hash(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }

    private static Map<String, byte[]> release(Path archive) throws Exception {
        Map<String, byte[]> out = new HashMap<>();
        try (ZipFile zip = new ZipFile(archive.toFile())) {
            for (var pin : PINNED.entrySet()) {
                var entry = zip.getEntry(pin.getKey() + ".class");
                require(entry != null, "Missing pinned entry: " + pin.getKey());
                byte[] bytes;
                try (InputStream in = zip.getInputStream(entry)) { bytes = in.readAllBytes(); }
                require(hash(bytes).equals(pin.getValue()), "Unreviewed release entry: " + pin.getKey());
                out.put(pin.getKey(), bytes);
            }
        }
        require(hash(resource("zombie/entity/util/TimSort")).equals(
                "6ae5a9d66cf68cef8724ae77464ccbafd366b2d49d09367ee3d8e643d30fcb99"), "Unreviewed native TimSort");
        require(hash(resource("zombie/util/list/PZArrayList")).equals(
                "7ce79434a59558ed7c966d46d592d765ea6160949e0e87705002ccac7d4f5394"), "Unreviewed native PZArrayList");
        return out;
    }

    private static ClassWriter fixture(String name) {
        ClassWriter w = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        w.visit(Opcodes.V17, Opcodes.ACC_PUBLIC | Opcodes.ACC_FINAL, name, null, "java/lang/Object", null);
        MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0);
        m.visitMethodInsn(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false);
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(0, 0); m.visitEnd();
        return w;
    }

    private static byte[] worldFixture(boolean meta) {
        String name = meta ? META : WORLD, field = meta ? "maxX" : "grid";
        String type = meta ? "I" : "L" + META + ";";
        ClassWriter w = fixture(name);
        w.visitField(Opcodes.ACC_PUBLIC, field, type, null, null).visitEnd();
        if (!meta) w.visitField(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "instance", "L" + WORLD + ";", null, null).visitEnd();
        MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC, meta ? "getMaxX" : "getMetaGrid", "()" + type, null, null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0);
        m.visitFieldInsn(Opcodes.GETFIELD, name, field, type);
        m.visitInsn(meta ? Opcodes.IRETURN : Opcodes.ARETURN); m.visitMaxs(0, 0); m.visitEnd();
        w.visitEnd(); return w.toByteArray();
    }

    /** Isolate only the actual resetForStore assignment, not the rest of chunk reset. */
    private static byte[] chunkFixture(byte[] actual) {
        ClassWriter w = fixture(CHUNK);
        w.visitField(Opcodes.ACC_PUBLIC, "pzoptTlOrder", "[Ljava/lang/Object;", null, null).visitEnd();
        int[] found = {0};
        new ClassReader(actual).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                if (!n.equals("resetForStore") || !d.equals("()V")) return null;
                return new MethodVisitor(Opcodes.ASM9) {
                    int state;
                    @Override public void visitVarInsn(int op, int v) { state = op == Opcodes.ALOAD && v == 0 ? 1 : 0; }
                    @Override public void visitInsn(int op) { state = state == 1 && op == Opcodes.ACONST_NULL ? 2 : 0; }
                    @Override public void visitMethodInsn(int op, String o, String n, String d, boolean i) { state = 0; }
                    @Override public void visitFieldInsn(int op, String o, String n, String d) {
                        if (o.equals(CHUNK) && n.equals("pzoptTlOrder")) {
                            require(state == 2 && op == Opcodes.PUTFIELD && d.equals("[Ljava/lang/Object;"), "Reset assignment changed");
                            found[0]++;
                            MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC, "resetOrder", "()V", null, null);
                            m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0); m.visitInsn(Opcodes.ACONST_NULL);
                            m.visitFieldInsn(op, o, n, d); m.visitInsn(Opcodes.RETURN); m.visitMaxs(0, 0); m.visitEnd();
                        }
                        state = 0;
                    }
                };
            }
        }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        require(found[0] == 1, "Missing unique reset assignment");
        w.visitEnd(); return w.toByteArray();
    }

    /** Copy the pinned caller's complete comparator body, including integer overflow. */
    private static MethodHandle comparator(TranslucentUnionChecks.FixtureLoader loader, byte[] caller, Class<?> square) throws Exception {
        String owner = "orderfixture/Comparator";
        String descriptor = "(L" + SQUARE + ";L" + SQUARE + ";)I";
        ClassWriter w = new ClassWriter(0);
        w.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, owner, null, "java/lang/Object", null);
        int[] count = {0};
        new ClassReader(caller).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                if (!n.equals("lambda$renderOneLevel_Translucent$0") || !d.equals(descriptor)) return null;
                require((a & Opcodes.ACC_STATIC) != 0, "Comparator is no longer static"); count[0]++;
                return w.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "compare", d, null, null);
            }
        }, ClassReader.SKIP_DEBUG);
        require(count[0] == 1, "Missing actual comparator"); w.visitEnd();
        return MethodHandles.lookup().findStatic(loader.define(owner, w.toByteArray()), "compare",
                MethodType.methodType(int.class, square, square));
    }

    private record Outcome(Class<?> failure, Object[] order, boolean hit) { }

    private static final class Experiment {
        final TranslucentUnionChecks.FixtureLoader loader;
        final Class<?> square, chunk, cache;
        final MethodHandle union, compare;
        final Method reuse, store;
        final Object meta;
        final Field x, y, z, maxX;
        Experiment(Map<String, byte[]> release) throws Throwable {
            Map<String, byte[]> fixtures = new HashMap<>();
            for (String name : List.of(CACHE, CACHE + "$Entry")) fixtures.put(name.replace('/', '.'), release.get(name));
            fixtures.put(CHUNK.replace('/', '.'), chunkFixture(release.get(CHUNK)));
            fixtures.put(WORLD.replace('/', '.'), worldFixture(false));
            fixtures.put(META.replace('/', '.'), worldFixture(true));
            ClassWriter config = fixture("pzopt/Config");
            config.visitField(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "DEV_TL_ORDER_CHECK", "Z", null, null).visitEnd();
            config.visitEnd(); fixtures.put("pzopt.Config", config.toByteArray());
            loader = new TranslucentUnionChecks.FixtureLoader(fixtures);
            square = loader.loadClass(SQUARE.replace('/', '.')); chunk = loader.loadClass(CHUNK.replace('/', '.'));
            cache = loader.loadClass(CACHE.replace('/', '.'));
            Class<?> world = loader.loadClass(WORLD.replace('/', '.')), grid = loader.loadClass(META.replace('/', '.'));
            meta = grid.getConstructor().newInstance(); maxX = grid.getField("maxX"); maxX.setInt(meta, 1024);
            Object worldValue = world.getConstructor().newInstance(); world.getField("grid").set(worldValue, meta);
            world.getField("instance").set(null, worldValue);
            x = square.getField("x"); y = square.getField("y"); z = square.getField("z");
            Class<?> helper = loader.loadClass(UNION.replace('/', '.'));
            Method weave = helper.getDeclaredMethod("transformReviewed", byte[].class); weave.setAccessible(true);
            byte[] woven = (byte[]) invoke(weave, null, (Object) release.get(CELL));
            require(woven != null, "Production union could not weave pinned caller");
            union = TranslucentUnionChecks.extract(loader, woven, true);
            compare = comparator(loader, release.get(CELL), square);
            reuse = cache.getMethod("reuse", chunk, int.class, int.class, List.class, List.class, List.class, PZArrayList.class);
            store = cache.getMethod("store", chunk, int.class, int.class, List.class, List.class, List.class, PZArrayList.class);
        }
        Object square(int xx, int yy) throws Exception {
            Object out = square.getConstructor().newInstance(); x.setInt(out, xx); y.setInt(out, yy); return out;
        }
        Object chunk() throws Exception { return chunk.getConstructor().newInstance(); }
        Outcome run(boolean cached, Object owner, int player, int level, List[] source) {
            PZArrayList target = new PZArrayList(square, 16); boolean hit = false;
            // The caller's outer guard and control flow are test scaffolding; union,
            // comparator, sorter, reuse/store and reset assignment are real instructions.
            try {
                if (source[2].size() + source[0].size() + source[1].size() != 0) {
                    if (cached) hit = (boolean) invoke(reuse, null, owner, player, level, source[0], source[1], source[2], target);
                    if (!hit) {
                        target.clear(); union.invokeExact(target, source[0], source[1], source[2]);
                        new TimSort().doSort(target.getElements(), (Comparator) (a, b) -> {
                            try { return (int) compare.invoke(a, b); }
                            catch (Throwable error) { throw unchecked(error); }
                        }, 0, target.size());
                        if (cached) invoke(store, null, owner, player, level, source[0], source[1], source[2], target);
                    }
                }
                return new Outcome(null, Arrays.copyOf(target.getElements(), target.size(), Object[].class), hit);
            } catch (Throwable error) {
                return new Outcome(error.getClass(), Arrays.copyOf(target.getElements(), target.size(), Object[].class), hit);
            }
        }
        Outcome check(Object owner, int player, int level, List[] source, boolean hit, String label) {
            Outcome baseline = run(false, owner, player, level, source), candidate = run(true, owner, player, level, source);
            equal(baseline, candidate, label); require(candidate.hit == hit, label + ": unexpected hit=" + candidate.hit); cases++;
            return candidate;
        }
        Object entry(Object owner, int player, int level) throws Exception {
            Object[] entries = (Object[]) chunk.getField("pzoptTlOrder").get(owner);
            return entries == null ? null : entries[player * 64 + level + 32];
        }
    }

    private static RuntimeException unchecked(Throwable error) {
        if (error instanceof Error fatal) throw fatal;
        return error instanceof RuntimeException runtime ? runtime : new RuntimeException(error);
    }
    private static Object invoke(Method method, Object receiver, Object... args) throws Throwable {
        try { return method.invoke(receiver, args); }
        catch (InvocationTargetException error) { throw error.getCause(); }
    }
    private static void equal(Outcome left, Outcome right, String label) {
        require(left.failure == right.failure, label + ": failure differs");
        require(left.order.length == right.order.length, label + ": length differs");
        for (int i = 0; i < left.order.length; i++) require(left.order[i] == right.order[i], label + ": identity differs at " + i);
    }
    private static List[] inputs(List items, List outlines, List objects) { return new List[] {items, outlines, objects}; }
    private static ArrayList list(Object... values) { return new ArrayList(Arrays.asList(values)); }

    private static void stableAndMutable(Experiment e) throws Throwable {
        Object owner = e.chunk(), a = e.square(1, 1), b = e.square(2, 1), tie = e.square(1, 1), c = e.square(3, 1);
        List[] lists = inputs(list(b, a, a), list(tie, a), list(c, b));
        Outcome first = e.check(owner, 0, 0, lists, false, "cold duplicate items / equal keys");
        require(Arrays.equals(first.order, new Object[] {a, a, tie, b, c}), "Native stable tie/duplicate order changed");
        e.check(owner, 0, 0, lists, true, "warm");
        lists = inputs(new ArrayList(lists[0]), new ArrayList(lists[1]), new ArrayList(lists[2]));
        e.check(owner, 0, 0, lists, true, "new list instances / same identities");
        for (int source = 0; source < 3; source++) {
            Object prior = lists[source].set(0, e.square(7 + source, 1));
            e.check(owner, 0, 0, lists, false, "replace source " + source);
            e.check(owner, 0, 0, lists, true, "replace warm " + source);
            lists[source].set(0, prior);
            e.check(owner, 0, 0, lists, false, "restore source " + source);
            lists[source].add(e.square(10 + source, 2));
            e.check(owner, 0, 0, lists, false, "grow source " + source);
            lists[source].remove(lists[source].size() - 1);
            e.check(owner, 0, 0, lists, false, "shrink source " + source);
            java.util.Collections.swap(lists[source], 0, 1);
            e.check(owner, 0, 0, lists, false, "reorder source " + source);
        }
        e.x.setInt(a, 99); e.check(owner, 0, 0, lists, false, "x mutation");
        e.y.setInt(a, 3); e.check(owner, 0, 0, lists, false, "y mutation");
        e.z.setInt(a, 1); e.check(owner, 0, 0, lists, true, "z ignored by comparator / draw remains live");
        e.check(owner, 1, 0, lists, false, "other player"); e.check(owner, 1, 0, lists, true, "other player warm");
        e.check(owner, 0, 1, lists, false, "other level"); e.check(owner, 0, 1, lists, true, "other level warm");
        for (int[] key : new int[][] {{0, -32}, {3, 31}, {-1, 0}, {4, 0}, {0, -33}, {0, 32}}) {
            e.check(owner, key[0], key[1], lists, false, "key bounds " + Arrays.toString(key));
            e.check(owner, key[0], key[1], lists, key[0] >= 0 && key[0] <= 3 && key[1] >= -32 && key[1] <= 31,
                    "key bounds repeat " + Arrays.toString(key));
        }
        e.check(owner, 0, 0, inputs(list(), list(), list()), false, "empty guard");
        e.check(owner, 0, 0, lists, true, "empty interval retains usable entry");
        e.chunk.getMethod("resetOrder").invoke(owner);
        require(e.chunk.getField("pzoptTlOrder").get(owner) == null, "Actual reset assignment retained cache");
        e.check(owner, 0, 0, lists, false, "chunk reuse after reset");
    }

    private static void randomChecks(Experiment e) throws Throwable {
        Random random = new Random(780192); Object[] pool = new Object[240];
        for (int i = 0; i < pool.length; i++) pool[i] = e.square((i / 2) % 8, (i / 2) / 8);
        for (int run = 0; run < 500; run++) {
            List[] lists = inputs(list(), list(), list());
            for (List source : lists) for (int i = random.nextInt(170); i > 0; i--) source.add(pool[random.nextInt(pool.length)]);
            Object owner = e.chunk();
            e.check(owner, 0, 0, lists, false, "random cold " + run);
            e.check(owner, 0, 0, lists, true, "random warm " + run);
        }
    }

    private static void nullChecks(Experiment e) throws Throwable {
        for (int source = 0; source < 3; source++) {
            List[] lists = inputs(list(), list(), list()); lists[source] = list((Object) null);
            Object owner = e.chunk();
            e.check(owner, 0, 0, lists, false, "single null cold " + source);
            e.check(owner, 0, 0, lists, true, "single null warm " + source);
            // Multiple-element sort fails before store; neither path has a usable entry.
            lists[source].add(e.square(0, 0));
            e.check(owner, 0, 0, lists, false, "null comparator failure " + source);
            e.check(owner, 0, 0, lists, false, "null comparator failure repeat " + source);
            lists[source] = null;
            e.check(owner, 0, 0, lists, false, "null source outer guard " + source);
        }
    }

    private static void knownLimitations(Experiment e) throws Throwable {
        Object owner = e.chunk(), a = e.square(300, 0), b = e.square(0, 1);
        List[] lists = inputs(list(a, b), list(), list());
        e.maxX.setInt(e.meta, 1); e.check(owner, 0, 0, lists, false, "worldRight initial");
        e.maxX.setInt(e.meta, 2);
        Outcome fresh = e.run(false, owner, 0, 0, lists), stale = e.run(true, owner, 0, 0, lists);
        require(fresh.failure == null && stale.failure == null && stale.hit, "worldRight limitation setup failed");
        require(fresh.order[0] == a && stale.order[0] == b, "worldRight omission counterexample no longer reproduced");
        e.maxX.setInt(e.meta, 1024);

        owner = e.chunk(); Object[] many = new Object[80];
        for (int i = 0; i < many.length; i++) many[i] = e.square(i, 0);
        e.check(owner, 0, 0, inputs(list(many), list(), list()), false, "retention large");
        e.check(owner, 0, 0, inputs(list(many[0]), list(), list()), false, "retention shrink");
        Object entry = e.entry(owner, 0, 0);
        for (String field : List.of("src", "sorted")) {
            Field f = entry.getClass().getDeclaredField(field); f.setAccessible(true);
            Object[] retained = (Object[]) f.get(entry);
            require(retained[79] == many[79], field + " stale reference after shrink was not reproduced");
        }
        System.out.println("KNOWN_LIMITATIONS_REPRODUCED worldRight_not_keyed=true shrink_retains_src_and_sorted=true");
    }

    public static void main(String[] args) throws Throwable {
        String archive = System.getProperty("pz.test.optimizer.archive", System.getenv("PZ_TEST_OPTIMIZER_ARCHIVE"));
        require(archive != null, "Set pz.test.optimizer.archive or PZ_TEST_OPTIMIZER_ARCHIVE to the pinned release ZIP");
        Experiment e = new Experiment(release(Path.of(archive)));
        stableAndMutable(e); randomChecks(e); nullChecks(e); knownLimitations(e);
        System.out.println("TRANSLUCENT_ORDER_CHECKS_PASS cases=" + cases
                + " actual_release_cache=true active_union=true actual_comparator=true native_sorter=true"
                + " scope=stable-worldRight-single-writer no_performance_or_runtime_admission=true");
    }
}
