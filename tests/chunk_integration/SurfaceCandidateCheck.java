import com.sun.management.ThreadMXBean;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import zombie.core.TilePropertyAliasMap;
import zombie.core.properties.PropertyContainer;

/** Consumes external native/official classes; contains no redistributed runtime implementation. */
public final class SurfaceCandidateCheck {
    private static final String[] NAMES = {"Surface", "ItemHeight", "StackReplaceTileOffset",
        "SlopedSurfaceDirection", "SlopedSurfaceHeightMin", "SlopedSurfaceHeightMax",
        "IsSurfaceOffset", "IsTable", "IsTableTop"};
    private static final String[] NORMAL = {"20", "30", "7", "N", "11", "77", "true", "true", "true"};
    private static final VarHandle FLAGS;
    private static volatile long sink;
    static {
        try {
            FLAGS = MethodHandles.privateLookupIn(PropertyContainer.class, MethodHandles.lookup())
                .findVarHandle(PropertyContainer.class, "surfaceFlags", byte.class);
        } catch (ReflectiveOperationException e) { throw new ExceptionInInitializerError(e); }
    }

    public static void main(String[] args) throws Exception {
        boolean nativeMode = Boolean.parseBoolean(args[0]);
        if (!nativeMode && Class.forName("pzopt.Config").getField("PROPERTY_SURFACE_NOALLOC").getBoolean(null)
                != Boolean.parseBoolean(System.getProperty("pzopt.propertySurfaceNoAlloc")))
            throw new AssertionError("Requested flag was not applied");
        HashMap<String, ArrayList<String>> defs = new HashMap<>();
        List<String> values = Arrays.asList("20", "30", "7", "N", "11", "77", "true", "", "bad",
            "-1", "0", "100", "127", "128", "32768", "2147483648", "S", "999", "-50");
        for (String name : NAMES) defs.put(name, new ArrayList<>(values));
        for (int i = 0; i < 64; i++) defs.put("Other" + i, new ArrayList<>(values));
        TilePropertyAliasMap.instance.Generate(defs);
        PropertyContainer pc = filled();
        report("filled", pc);
        if (!Arrays.equals(snapshot(pc), new String[]{"20", "30", "7", "N", "11", "77", "true", "true", "true"}))
            throw new AssertionError("Expected all surface fields and flags");
        for (String value : values) {
            PropertyContainer vector = new PropertyContainer();
            for (String name : NAMES) vector.set(name, name.equals("SlopedSurfaceDirection") ? "N" : value, false);
            report("value=" + value, vector);
        }
        for (String direction : new String[]{"N", "S", "", "bad"}) {
            PropertyContainer vector = filled(); vector.set("SlopedSurfaceDirection", direction, false);
            report("direction=" + direction, vector);
        }
        // Public mutations: preserve existing cache behavior, including inherited put/remove and unset.
        pc.set("Surface", "127", false); report("set", pc);
        pc.unset("Surface"); report("unset-cached", pc);
        FLAGS.setVolatile(pc, (byte)0); report("unset-invalidated", pc);
        pc.put((short)id("Surface"), (short)valueId("Surface", "30")); report("put-cached", pc);
        pc.CreateKeySet();
        PropertyContainer other = new PropertyContainer(); other.set("Surface", "7", false); other.CreateKeySet();
        pc.AddProperties(other); report("add-cached", pc);
        FLAGS.setVolatile(pc, (byte)0); report("add-invalidated", pc);
        pc.remove((short)id("Surface")); FLAGS.setVolatile(pc, (byte)0); report("remove", pc);
        pc.Clear(); report("clear", pc);
        PropertyContainer dense = filled();
        for (int i = 0; i < 64; i++) dense.set("Other" + i, "20", false);
        report("rehash-dense", dense);
        for (int i = 0; i < 64; i += 2) dense.unset("Other" + i);
        FLAGS.setVolatile(dense, (byte)0); report("tombstones", dense);
        if (!nativeMode) {
            for (short key : new short[]{-1, (short)TilePropertyAliasMap.instance.properties.size()}) {
                PropertyContainer torn = filled(); int slot = freeSlot(torn);
                raw(torn, "_set", slot, key); raw(torn, "_values", slot, (short)0); raw(torn, "_states", slot, (byte)1);
                report("invalid-key=" + key, torn);
            }
            for (short value : new short[]{-1, (short)30000}) {
                PropertyContainer torn = filled(); int slot = keySlot(torn, (short)id("ItemHeight"));
                raw(torn, "_values", slot, value); report("invalid-value=" + value, torn);
            }
            // Removed/free slots must never contribute, even if their keys/values resemble valid properties.
            for (byte state : new byte[]{0, 2}) {
                PropertyContainer hole = filled(); int slot = freeSlot(hole);
                raw(hole, "_set", slot, (short)id("Surface"));
                raw(hole, "_values", slot, (short)valueId("Surface", "127")); raw(hole, "_states", slot, state);
                report("hole-state=" + state, hole);
            }
        }
        if (nativeMode || (args.length > 1 && args[1].equals("--correctness-only"))) return;
        ThreadMXBean bean = (ThreadMXBean)ManagementFactory.getThreadMXBean();
        if (!bean.isThreadAllocatedMemorySupported()) throw new AssertionError("Thread allocation unavailable");
        bean.setThreadAllocatedMemoryEnabled(true);
        for (String kind : new String[]{"empty", "surface", "mixed", "irrelevant64"}) {
            PropertyContainer bench = new PropertyContainer();
            if (!kind.equals("empty")) bench.set("Surface", "20", false);
            if (kind.equals("mixed")) bench = filled();
            if (kind.equals("irrelevant64")) for (int i = 0; i < 64; i++) bench.set("Other" + i, "20", false);
            for (String access : new String[]{"cold", "set", "cached"}) {
                for (int w = 0; w < 4; w++) loop(bench, access, 150_000);
                for (int round = 0; round < 7; round++) {
                    long alloc = bean.getThreadAllocatedBytes(Thread.currentThread().threadId());
                    long time = System.nanoTime(); loop(bench, access, 350_000); time = System.nanoTime() - time;
                    alloc = bean.getThreadAllocatedBytes(Thread.currentThread().threadId()) - alloc;
                    System.out.printf(java.util.Locale.ROOT,
                        "MEASURE %s %s %d %.4f %.4f%n", kind, access, round, time / 350000.0, alloc / 350000.0);
                }
            }
        }
    }
    private static void loop(PropertyContainer pc, String access, int count) {
        long sum = 0;
        for (int i = 0; i < count; i++) {
            if (access.equals("cold")) FLAGS.setVolatile(pc, (byte)0);
            else if (access.equals("set")) pc.set("Surface", "20", false);
            sum += pc.getSurface();
        }
        sink = sum;
    }
    private static int id(String name) { return TilePropertyAliasMap.instance.getIDFromPropertyName(name); }
    private static int valueId(String name, String value) { return TilePropertyAliasMap.instance.getIDFromPropertyValue(id(name), value); }
    private static PropertyContainer filled() {
        PropertyContainer pc = new PropertyContainer();
        for (int i = 0; i < NAMES.length; i++) pc.set(NAMES[i], NORMAL[i], false);
        return pc;
    }
    private static String[] snapshot(PropertyContainer pc) {
        return new String[]{"" + pc.getSurface(), "" + pc.getItemHeight(), "" + pc.getStackReplaceTileOffset(),
            "" + pc.getSlopedSurfaceDirection(), "" + pc.getSlopedSurfaceHeightMin(), "" + pc.getSlopedSurfaceHeightMax(),
            "" + pc.isSurfaceOffset(), "" + pc.isTable(), "" + pc.isTableTop()};
    }
    private static void report(String label, PropertyContainer pc) {
        try { System.out.println("VECTOR " + label + " " + String.join(",", snapshot(pc))); }
        catch (IllegalArgumentException e) { System.out.println("VECTOR " + label + " throws=" + e.getClass().getSimpleName()); }
    }
    private static Object array(PropertyContainer pc, String name) throws Exception {
        for (Class<?> c = pc.getClass(); c != null; c = c.getSuperclass()) {
            try { Field f = c.getDeclaredField(name); f.setAccessible(true); return f.get(pc); }
            catch (NoSuchFieldException ignored) {}
        }
        throw new AssertionError(name);
    }
    private static int freeSlot(PropertyContainer pc) throws Exception {
        byte[] states = (byte[])array(pc, "_states");
        for (int i = 0; i < states.length; i++) if (states[i] == 0) return i;
        throw new AssertionError("No free slot");
    }
    private static int keySlot(PropertyContainer pc, short key) throws Exception {
        short[] keys = (short[])array(pc, "_set"); byte[] states = (byte[])array(pc, "_states");
        for (int i = 0; i < keys.length; i++) if (states[i] == 1 && keys[i] == key) return i;
        throw new AssertionError("Missing key");
    }
    private static void raw(PropertyContainer pc, String field, int slot, Object value) throws Exception {
        java.lang.reflect.Array.set(array(pc, field), slot, value);
    }
}
