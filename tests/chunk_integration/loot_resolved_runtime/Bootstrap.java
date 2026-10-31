package toolkit.lootresolved.bootstrap;

import java.io.InputStream;
import java.lang.instrument.*;
import java.nio.file.*;
import java.security.ProtectionDomain;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.*;

/** Initial-definition-only research splice plus identical control/candidate private RNG routing. */
public final class Bootstrap {
    public static final String OPT_IN = "loot-resolved-runtime.opt-in";
    public static final String HOST_AUTHORITY = "loot-resolved-runtime.host-authority";
    static final String TARGET = "zombie/inventory/ItemPickerJava", RAND = "zombie/core/random/Rand";
    static final String RAND_ABSTRACT = "zombie/core/random/RandAbstract", RAND_STANDARD = "zombie/core/random/RandStandard",
        RAND_INTERFACE = "zombie/core/random/RandInterface";
    public static final String RNG_SCOPE = "owner-thread-private-native-randstandard-v1";
    private static final ClassLoader GAME = Bootstrap.class.getClassLoader();
    private static final Properties hashes = new Properties();
    private static final Properties nativeHashes = new Properties(), optimizerProperties = new Properties();
    private static final Map<String,String> observed = new ConcurrentHashMap<>();
    private static volatile String state = "not-installed", mode = "unknown", bank = "unknown", outputHash = "";
    private static volatile String resourceProfile = "unknown", optimizerManifest = "none";
    private static volatile boolean runtimeProfileChecked;
    private static boolean attempted;
    private static int definitions, randDefinitions;
    private static int abstractDefinitions, standardDefinitions, interfaceDefinitions;
    private static Path ownedCache;

    public static String state() { return state; }
    public static String mode() { return mode; }
    public static String bank() { return bank; }
    public static Path cache() { return ownedCache; }
    public static boolean active() { return "active".equals(state); }
    public static String resourceProfile() { return resourceProfile; }
    public static String optimizerManifest() { return optimizerManifest; }
    public static boolean runtimeProfileChecked() { return runtimeProfileChecked; }
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
    static String selectResourceProfile(Path cache, String command, boolean optimized) throws Exception {
        if (!optimized) return "native";
        String main = command == null || command.isBlank() ? "" : command.trim().split("\\s+",2)[0];
        Path marker = cache.resolve(HOST_AUTHORITY);
        boolean host = main.equals("zombie.network.GameServer") && owned(cache)
            && Files.isRegularFile(marker,LinkOption.NOFOLLOW_LINKS) && Files.size(marker) <= 128
            && Files.readString(marker).trim().equals(text("token.txt"));
        return host ? "native-host" : "optimized-client";
    }
    /** Called only after the real launcher has assigned its complete profile, immediately before
     * the bank. Booleans are actual GameServer/GameClient state supplied by the native bridge. */
    public static void verifyRuntimeProfile(boolean server, boolean client) {
        runtimeProfileChecked = false;
        Properties live = System.getProperties();
        synchronized (live) {
            if (resourceProfile.equals("optimized-client")) {
                if (server || optimizerProperties.size() != 771) throw new IllegalStateException("optimized-client-runtime-context");
                for (String key : optimizerProperties.stringPropertyNames())
                    if (!optimizerProperties.getProperty(key).equals(live.getProperty(key)))
                        throw new IllegalStateException("optimizer-profile-mismatch:" + key);
                for (Object key : live.keySet())
                    if (key instanceof String name && name.startsWith("pzopt.") && !optimizerProperties.containsKey(name))
                        throw new IllegalStateException("optimizer-profile-extra:" + name);
            } else {
                if (!resourceProfile.equals("native") && !resourceProfile.equals("native-host"))
                    throw new IllegalStateException("unknown-runtime-resource-profile");
                if (resourceProfile.equals("native-host") && (!server || client))
                    throw new IllegalStateException("native-host-runtime-context");
                if (live.getProperty("pz.optimizerTrial.profile") != null)
                    throw new IllegalStateException("native-runtime-has-optimizer-profile");
                for (Object key : live.keySet())
                    if (key instanceof String name && name.startsWith("pzopt."))
                        throw new IllegalStateException("native-runtime-has-optimizer-pin:" + name);
            }
        }
        runtimeProfileChecked = true;
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
            bank = text("bank.txt");
            if (!Set.of("control", "candidate").contains(mode)) throw new IllegalArgumentException("mode");
            if (!Set.of("base", "semantics", "reload").contains(bank)) throw new IllegalArgumentException("bank");
            try (InputStream in = Bootstrap.class.getResourceAsStream("native-hashes.properties")) { nativeHashes.load(in); }
            optimizerManifest = text("optimizer-manifest.sha256");
            boolean optimized = !optimizerManifest.equals("none");
            if (optimized && !optimizerManifest.matches("[0-9a-f]{64}")) throw new IllegalStateException("optimizer-manifest-metadata");
            try (InputStream in = Bootstrap.class.getResourceAsStream("optimizer-profile.properties")) { optimizerProperties.load(in); }
            if (optimized != !optimizerProperties.isEmpty()) throw new IllegalStateException("optimizer-profile-metadata");
            resourceProfile = selectResourceProfile(ownedCache,System.getProperty("sun.java.command"),optimized);
            if (resourceProfile.equals("optimized-client")) {
                try (InputStream in = Bootstrap.class.getResourceAsStream("runtime-hashes.properties")) { hashes.load(in); }
            } else hashes.putAll(nativeHashes);
            if (hashes.size() != nativeHashes.size() || !Objects.equals(hashes.getProperty(TARGET),nativeHashes.getProperty(TARGET)))
                throw new IllegalStateException("native-target-guard-metadata");
            for (String name : hashes.stringPropertyNames())
                if (!hashes.getProperty(name).equals(ResolvedCandidate.sha(resource(name))))
                    throw new IllegalStateException("resource-byte-mismatch:" + name);
            var field = Loader.class.getDeclaredField("g_instrumentation");
            field.setAccessible(true);
            instrumentation = (Instrumentation)field.get(null);
            if (instrumentation == null) throw new IllegalStateException("no-instrumentation");
            // These are the candidate's skipped APIs or RNG audit target. Do not infer their
            // already-defined in-memory bytes from the corresponding disk resources.
            Set<String> early = Set.of(TARGET, RAND, RAND_ABSTRACT, RAND_STANDARD, RAND_INTERFACE, "zombie/scripting/ScriptManager",
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
                        if (RAND_ABSTRACT.equals(name)) { abstractDefinitions++; return auditReceivers(bytes,name); }
                        if (RAND_STANDARD.equals(name)) { standardDefinitions++; return auditReceivers(bytes,name); }
                        if (RAND_INTERFACE.equals(name)) { interfaceDefinitions++; return auditReceivers(bytes,name); }
                        return null;
                    } catch (Throwable problem) { fail("transform:" + problem); return null; }
                }
            };
            instrumentation.addTransformer(transformer, false);
            Class.forName(RAND_INTERFACE.replace('/', '.'), false, GAME);
            Class.forName(RAND_ABSTRACT.replace('/', '.'), false, GAME);
            Class.forName(RAND_STANDARD.replace('/', '.'), false, GAME);
            Class.forName(RAND.replace('/', '.'), false, GAME);
            Class<?> picker = Class.forName(TARGET.replace('/', '.'), false, GAME);
            boolean bridge = Arrays.stream(picker.getDeclaredMethods()).anyMatch(m -> m.getName().equals("pztest$resolvedOrNative"));
            if (definitions != 1 || randDefinitions != 1 || abstractDefinitions != 1 || standardDefinitions != 1 || interfaceDefinitions != 1
                    || bridge != mode.equals("candidate") || state.startsWith("disabled:"))
                throw new IllegalStateException("initial-definition-contract:" + definitions + ":" + randDefinitions + ":" + bridge);
            state = "active";
            writeActivation();
            System.out.println("[LOOT_RESOLVED_RUNTIME] ACTIVATION active mode=" + mode + " resource_profile=" + resourceProfile + " definitions=1 rng_audit=1 input="
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
        int[] count = {0}, selections = {0};
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                MethodVisitor method = super.visitMethod(a,n,d,s,e);
                if ((a & Opcodes.ACC_STATIC) == 0 || n.equals("<clinit>")) return method;
                count[0]++;
                return new MethodVisitor(Opcodes.ASM9, method) {
                    @Override public void visitFieldInsn(int op, String owner, String name, String descriptor) {
                        if (op == Opcodes.GETSTATIC && owner.equals(RAND_STANDARD) && name.equals("INSTANCE")
                                && descriptor.equals("L" + RAND_STANDARD + ";")) {
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,"toolkit/lootresolved/bootstrap/RngScope","dispatch",
                                "()L" + RAND_STANDARD + ";",false);
                            selections[0]++;
                        } else super.visitFieldInsn(op,owner,name,descriptor);
                    }
                };
            }
        }, 0);
        if (count[0] != 11 || selections[0] != 9) throw new IllegalStateException("Rand splice counts:" + count[0] + ":" + selections[0]);
        return writer.toByteArray();
    }
    private static byte[] auditReceivers(byte[] bytes, String owner) {
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader,ClassWriter.COMPUTE_MAXS);
        int[] count = {0};
        reader.accept(new ClassVisitor(Opcodes.ASM9,writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                MethodVisitor method = super.visitMethod(access,name,descriptor,signature,exceptions);
                boolean target = owner.equals(RAND_ABSTRACT) && name.equals("Next")
                    || owner.equals(RAND_INTERFACE) && (name.equals("NextBool") || name.equals("AdjustForFramerate"))
                    || owner.equals(RAND_STANDARD) && name.equals("init");
                if (!target || (access & (Opcodes.ACC_STATIC | Opcodes.ACC_ABSTRACT)) != 0) return method;
                count[0]++;
                int kind = owner.equals(RAND_INTERFACE) && name.equals("NextBool") && descriptor.equals("(F)Z") ? 1
                    : owner.equals(RAND_STANDARD) ? 2 : 0;
                return new MethodVisitor(Opcodes.ASM9,method) {
                    @Override public void visitCode() {
                        super.visitCode(); super.visitVarInsn(Opcodes.ALOAD,0);
                        super.visitLdcInsn(owner + "." + name + descriptor); super.visitLdcInsn(kind);
                        super.visitMethodInsn(Opcodes.INVOKESTATIC,"toolkit/lootresolved/bootstrap/RngScope","receiver",
                            "(Ljava/lang/Object;Ljava/lang/String;I)V",false);
                    }
                };
            }
        },0);
        int expected = owner.equals(RAND_ABSTRACT) ? 10 : owner.equals(RAND_INTERFACE) ? 3 : 1;
        if (count[0] != expected) throw new IllegalStateException("RNG receiver entry count:" + owner + ":" + count[0]);
        return writer.toByteArray();
    }
    public static void beginRng() throws Exception { if (!active()) throw new IllegalStateException("RNG bootstrap disabled"); RngScope.begin(); }
    public static void seedRng(int number) throws Exception { RngScope.seed(number); }
    public static void endRng() { RngScope.end(); }
    public static boolean rngComplete() { return RngScope.complete(); }
    public static void writeRngReceipt() throws Exception { if (!owned(ownedCache)) throw new IllegalStateException("RNG receipt ownership"); RngScope.writeReceipt(ownedCache); }
    public static void writeActivation() throws Exception {
        if (ownedCache == null || !owned(ownedCache)) return;
        StringBuilder out = new StringBuilder("state=" + state + "\nmode=" + mode + "\nbank=" + bank + "\npid=" + ProcessHandle.current().pid() + "\ndefinitions=" + definitions
            + "\nrng_audit_definitions=" + randDefinitions + "\ninput=" + hashes.getProperty(TARGET, "") + "\noutput=" + outputHash + "\n");
        out.append("native_target_input=").append(nativeHashes.getProperty(TARGET,"")).append('\n')
            .append("resource_profile=").append(resourceProfile).append('\n')
            .append("optimizer_manifest_sha256=").append(optimizerManifest).append('\n')
            .append("runtime_profile_checked=").append(runtimeProfileChecked).append('\n')
            .append("rng_scope=").append(RNG_SCOPE).append('\n')
            .append("rng_abstract_definitions=").append(abstractDefinitions).append('\n')
            .append("rng_standard_definitions=").append(standardDefinitions).append('\n')
            .append("rng_interface_definitions=").append(interfaceDefinitions).append('\n');
        for (String name : new TreeSet<>(observed.keySet())) out.append("observed=").append(name).append(':').append(observed.get(name)).append('\n');
        Files.writeString(ownedCache.resolve("loot-resolved-runtime-activation-" + ProcessHandle.current().pid() + ".txt"), out);
    }
}
