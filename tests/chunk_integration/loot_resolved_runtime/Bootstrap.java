package toolkit.lootresolved.bootstrap;

import java.io.InputStream;
import java.lang.instrument.*;
import java.nio.file.*;
import java.security.ProtectionDomain;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.*;

/** Initial-definition-only research splice plus identical control/candidate RNG ownership audit. */
public final class Bootstrap {
    public static final String OPT_IN = "loot-resolved-runtime.opt-in";
    static final String TARGET = "zombie/inventory/ItemPickerJava", RAND = "zombie/core/random/Rand";
    private static final ClassLoader GAME = Bootstrap.class.getClassLoader();
    private static final Properties hashes = new Properties();
    private static final Map<String,String> observed = new ConcurrentHashMap<>();
    private static volatile String state = "not-installed", mode = "unknown", outputHash = "";
    private static volatile Thread rngOwner;
    private static volatile boolean foreignRng;
    private static boolean attempted;
    private static int definitions, randDefinitions;
    private static Path ownedCache;

    public static String state() { return state; }
    public static String mode() { return mode; }
    public static Path cache() { return ownedCache; }
    public static boolean active() { return "active".equals(state); }
    static String text(String resource) throws Exception {
        try (InputStream in = Bootstrap.class.getResourceAsStream(resource)) {
            if (in == null) throw new IllegalStateException("missing " + resource);
            return new String(in.readNBytes(256), java.nio.charset.StandardCharsets.US_ASCII).trim();
        }
    }
    public static boolean owned(Path cache) throws Exception {
        Path marker = cache.resolve("Lua/smoke-user.txt"), token = cache.resolve(OPT_IN);
        if (!Files.exists(marker, LinkOption.NOFOLLOW_LINKS)) marker = cache.resolve("smoke-user.txt");
        return Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS) && Files.size(marker) > 0
            && Files.size(marker) <= 1024 && Files.isRegularFile(token, LinkOption.NOFOLLOW_LINKS)
            && Files.size(token) <= 128 && Files.readString(token).trim().equals(text("token.txt"));
    }
    private static byte[] resource(String name) throws Exception {
        try (InputStream in = GAME.getResourceAsStream(name + ".class")) {
            if (in == null) throw new IllegalStateException("missing native " + name);
            return in.readAllBytes();
        }
    }
    private static void fail(String reason) {
        state = "disabled:" + reason;
        System.out.println("[LOOT_RESOLVED_RUNTIME] ACTIVATION " + state);
    }
    public static synchronized boolean install(Path cache) {
        if (attempted) return active();
        attempted = true;
        Instrumentation instrumentation = null;
        ClassFileTransformer transformer = null;
        try {
            if (!owned(cache)) { fail("owned-cache-opt-in"); return false; }
            ownedCache = cache.toRealPath();
            mode = text("mode.txt");
            if (!Set.of("control", "candidate").contains(mode)) throw new IllegalArgumentException("mode");
            try (InputStream in = Bootstrap.class.getResourceAsStream("native-hashes.properties")) { hashes.load(in); }
            for (String name : hashes.stringPropertyNames())
                if (!hashes.getProperty(name).equals(ResolvedCandidate.sha(resource(name))))
                    throw new IllegalStateException("resource-byte-mismatch:" + name);
            var field = Loader.class.getDeclaredField("g_instrumentation");
            field.setAccessible(true);
            instrumentation = (Instrumentation)field.get(null);
            if (instrumentation == null) throw new IllegalStateException("no-instrumentation");
            // These are the candidate's skipped APIs or RNG audit target. Do not infer their
            // already-defined in-memory bytes from the corresponding disk resources.
            Set<String> early = Set.of(TARGET, RAND, "zombie/scripting/ScriptManager",
                "zombie/scripting/objects/Item", "zombie/SandboxOptions");
            for (Class<?> type : instrumentation.getAllLoadedClasses())
                if (type.getClassLoader() == GAME && early.contains(type.getName().replace('.', '/')))
                    throw new IllegalStateException("already-loaded:" + type.getName());
            transformer = new ClassFileTransformer() {
                @Override public byte[] transform(ClassLoader loader, String name, Class<?> redef,
                        ProtectionDomain domain, byte[] bytes) {
                    if (loader != GAME || !hashes.containsKey(name)) return null;
                    try {
                        if (redef != null) { fail("redefinition:" + name); return null; }
                        String inputHash = ResolvedCandidate.sha(bytes);
                        observed.put(name, inputHash);
                        if (!inputHash.equals(hashes.getProperty(name))) { fail("definition-byte-mismatch:" + name); return null; }
                        if (TARGET.equals(name)) {
                            definitions++;
                            byte[] result = mode.equals("candidate") ? ResolvedCandidate.transform(bytes, true) : bytes;
                            outputHash = ResolvedCandidate.sha(result);
                            return mode.equals("candidate") ? result : null;
                        }
                        if (RAND.equals(name)) { randDefinitions++; return auditRand(bytes); }
                        return null;
                    } catch (Throwable problem) { fail("transform:" + problem); return null; }
                }
            };
            instrumentation.addTransformer(transformer, false);
            Class.forName(RAND.replace('/', '.'), false, GAME);
            Class<?> picker = Class.forName(TARGET.replace('/', '.'), false, GAME);
            boolean bridge = Arrays.stream(picker.getDeclaredMethods()).anyMatch(m -> m.getName().equals("pztest$resolvedOrNative"));
            if (definitions != 1 || randDefinitions != 1 || bridge != mode.equals("candidate") || state.startsWith("disabled:"))
                throw new IllegalStateException("initial-definition-contract:" + definitions + ":" + randDefinitions + ":" + bridge);
            state = "active";
            writeActivation();
            System.out.println("[LOOT_RESOLVED_RUNTIME] ACTIVATION active mode=" + mode + " definitions=1 rng_audit=1 input="
                + hashes.getProperty(TARGET) + " output=" + outputHash);
            return true;
        } catch (Throwable failure) {
            fail(failure.toString());
            try { writeActivation(); } catch (Throwable ignored) { }
            return false;
        } finally {
            if (!active() && instrumentation != null && transformer != null) instrumentation.removeTransformer(transformer);
        }
    }
    private static byte[] auditRand(byte[] bytes) {
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
        int[] count = {0};
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                MethodVisitor method = super.visitMethod(a,n,d,s,e);
                if ((a & Opcodes.ACC_STATIC) == 0 || n.equals("<clinit>")) return method;
                count[0]++;
                return new MethodVisitor(Opcodes.ASM9, method) {
                    @Override public void visitCode() {
                        super.visitCode();
                        super.visitMethodInsn(Opcodes.INVOKESTATIC, "toolkit/lootresolved/bootstrap/Bootstrap", "rngEnter", "()V", false);
                    }
                };
            }
        }, 0);
        if (count[0] != 11) throw new IllegalStateException("Rand entry count:" + count[0]);
        return writer.toByteArray();
    }
    public static void rngEnter() {
        Thread owner = rngOwner;
        if (owner != null && owner != Thread.currentThread()) foreignRng = true;
    }
    public static synchronized void beginRng() {
        if (!active() || rngOwner != null) throw new IllegalStateException("RNG ownership");
        foreignRng = false; rngOwner = Thread.currentThread();
    }
    public static synchronized void endRng() {
        if (rngOwner != Thread.currentThread()) throw new IllegalStateException("RNG owner changed");
        rngOwner = null;
        if (foreignRng) throw new IllegalStateException("foreign-thread-native-RNG");
    }
    public static void writeActivation() throws Exception {
        if (ownedCache == null || !owned(ownedCache)) return;
        StringBuilder out = new StringBuilder("state=" + state + "\nmode=" + mode + "\npid=" + ProcessHandle.current().pid() + "\ndefinitions=" + definitions
            + "\nrng_audit_definitions=" + randDefinitions + "\ninput=" + hashes.getProperty(TARGET, "") + "\noutput=" + outputHash + "\n");
        for (String name : new TreeSet<>(observed.keySet())) out.append("observed=").append(name).append(':').append(observed.get(name)).append('\n');
        Files.writeString(ownedCache.resolve("loot-resolved-runtime-activation-" + ProcessHandle.current().pid() + ".txt"), out);
    }
}
