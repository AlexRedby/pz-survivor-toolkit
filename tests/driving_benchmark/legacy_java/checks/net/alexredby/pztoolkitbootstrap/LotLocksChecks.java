package net.alexredby.pztoolkitbootstrap;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Modifier;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.concurrent.TimeUnit;
import java.util.jar.Attributes;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;
import me.zed_0xff.zombie_buddy.Agent;
import java.security.ProtectionDomain;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.Opcodes;

/** Each mode runs in a fresh JVM, without a game loop, world data, or native GUI. */
public final class LotLocksChecks {
    private static void nativeGets(boolean synchronizedMethods) throws Exception {
        Class<?> lot = Class.forName("zombie.iso.IsoLot", false, LotLocksChecks.class.getClassLoader());
        int count = 0;
        for (var method : lot.getDeclaredMethods()) {
            if (!method.getName().equals("get")) continue;
            require(Modifier.isStatic(method.getModifiers()), "get lost static");
            require(Modifier.isSynchronized(method.getModifiers()) == synchronizedMethods,
                "loaded get synchronized mismatch: " + method);
            System.out.println("LOT_LOCKS_LOADED_GET modifiers=" + method.getModifiers() + " " + method);
            count++;
        }
        require(count == 2, "expected both native get overloads");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static byte[] resource(String name) throws Exception {
        try (var input = LotLocksChecks.class.getClassLoader().getResourceAsStream(name + ".class")) {
            return input.readAllBytes();
        }
    }

    private static Instrumentation instrumentation() throws Exception {
        var field = Loader.class.getDeclaredField("g_instrumentation");
        field.setAccessible(true);
        return (Instrumentation)field.get(null);
    }

    /** Fixture agent installed before ZombieBuddy to prove that real incoming bytes are guarded. */
    public static void premain(String mode, Instrumentation instrumentation) {
        if (!mode.equals("mutate-lot") && !mode.equals("mutate-pool"))
            throw new IllegalArgumentException(mode);
        String target = mode.equals("mutate-lot") ? LotLocks.TARGET : LotLocks.POOL;
        instrumentation.addTransformer(new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader, String name, Class<?> type,
                    ProtectionDomain domain, byte[] bytes) {
                if (!target.equals(name)) return null;
                ClassReader reader = new ClassReader(bytes);
                ClassWriter writer = new ClassWriter(0);
                reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
                    @Override public void visitSource(String source, String debug) {
                        super.visitSource("UnsupportedFixture.java", debug);
                    }
                }, 0);
                return writer.toByteArray();
            }
        }, false);
    }

    private static void childModes() throws Exception {
        String bootstrapArgument = Agent.arguments.getOrDefault("patches_jar", "");
        String suffix = ":net.alexredby.pztoolkitbootstrap";
        require(bootstrapArgument.endsWith(suffix), "active check requires the actual early bootstrap JAR");
        Path bootstrap = Path.of(bootstrapArgument.substring(0, bootstrapArgument.length() - suffix.length()));
        Path loader = Path.of(Loader.class.getProtectionDomain().getCodeSource().getLocation().toURI());
        Path directory = Files.createTempDirectory("pz-lot-lock-guards-");
        Path guard = directory.resolve("input-guard.jar");
        var manifest = new Manifest();
        manifest.getMainAttributes().put(Attributes.Name.MANIFEST_VERSION, "1.0");
        manifest.getMainAttributes().put(new Attributes.Name("Premain-Class"), LotLocksChecks.class.getName());
        try (var output = new JarOutputStream(Files.newOutputStream(guard), manifest)) {
            // The fixture class and its ASM dependency remain on the ordinary test classpath.
        }
        for (String mode : new String[]{"late-lot", "late-pool", "mutate-lot", "mutate-pool"}) {
            Path cache = directory.resolve(mode);
            Files.createDirectory(cache);
            var command = new ArrayList<String>();
            command.add(Path.of(System.getProperty("java.home"), "bin", "java").toString());
            if (mode.startsWith("mutate-")) command.add("-javaagent:" + guard + "=" + mode);
            command.add("-javaagent:" + loader + "=config_dir=" + cache + ",policy=deny-new,verbosity=1"
                + (mode.startsWith("mutate-") ? ",patches_jar=" + bootstrap + suffix : ""));
            command.add("-Djava.awt.headless=true");
            command.add("-Dzomboid.steam=0");
            command.add("-Djava.library.path=" + System.getProperty("java.library.path"));
            command.add("-cp");
            command.add(System.getProperty("java.class.path")
                + (mode.startsWith("late-") ? java.io.File.pathSeparator + bootstrap : ""));
            command.add(LotLocksChecks.class.getName());
            command.add(mode);
            Path log = cache.resolve("result.log");
            Process child = new ProcessBuilder(command).redirectErrorStream(true).redirectOutput(log.toFile()).start();
            try {
                require(child.waitFor(30, TimeUnit.SECONDS), "guard child timed out: " + mode);
                String output = Files.readString(log);
                require(child.exitValue() == 0 && output.contains("LOT_LOCKS_CHECKS_PASS " + mode),
                    "guard child failed: " + mode + "\n" + output);
                output.lines().filter(line -> line.startsWith("LOT_LOCKS_CHECKS_PASS ")
                    || line.startsWith("LOT_LOCKS_LOADED_GET ")).forEach(System.out::println);
            } finally {
                if (child.isAlive()) child.destroyForcibly().waitFor();
            }
        }
    }

    public static void main(String[] args) throws Exception {
        String mode = args.length == 0 ? "active" : args[0];
        byte[] lot = resource(LotLocks.TARGET), pool = resource(LotLocks.POOL);
        require(LotLocks.LOT_HASH.equals(LotLocks.hash(lot)), "fixture must use pinned native IsoLot");
        require(LotLocks.POOL_HASH.equals(LotLocks.hash(pool)), "fixture must use pinned native pool");
        byte[] transformed = LotLocks.transformReviewed(lot);
        require(transformed != null, "pinned native transform rejected");
        require(LotLocks.hash(transformed).equals("31f0a181531c3388cfc5970b7820f52dbcfa17bfd53512e2e98eb4e3addb6906"),
            "runtime output differs from reviewed two-byte candidate");
        int differences = 0;
        for (int i = 0; i < lot.length; i++) {
            if (lot[i] == transformed[i]) continue;
            require((lot[i] ^ transformed[i]) == Opcodes.ACC_SYNCHRONIZED, "changed non-lock bit");
            differences++;
        }
        require(differences == 2, "must change only two native lock bytes");
        require(LotLocks.transformReviewed(transformed) == null, "duplicate bytes admitted");
        byte[] changed = lot.clone();
        changed[changed.length - 1] ^= 1;
        require(LotLocks.transformReviewed(changed) == null, "unsupported bytes admitted");
        changed = pool.clone();
        changed[changed.length - 1] ^= 1;
        require(!LotLocks.poolContract(changed) && LotLocks.poolContract(pool), "pool guard failed");

        if (mode.equals("late-lot") || mode.equals("late-pool")) {
            require(!LotLocks.snapshot().active(), "early bootstrap was supplied for late fixture");
            Class.forName(mode.equals("late-lot") ? "zombie.iso.IsoLot" : "zombie.popman.ObjectPool",
                false, LotLocksChecks.class.getClassLoader());
            require(!LotLocks.install(), "late installation attempted schema change");
            require(LotLocks.snapshot().state().startsWith("already-loaded:"), "missing late guard proof");
            nativeGets(true);
        } else if (mode.equals("mutate-lot") || mode.equals("mutate-pool")) {
            require(!LotLocks.snapshot().active(), "changed real inputs were admitted");
            require(!LotLocks.install(), "duplicate failed installation was retried");
            nativeGets(true);
            var proof = LotLocks.snapshot();
            require(proof.transformations() == 0, "unsupported input was transformed");
            if (mode.equals("mutate-lot"))
                require(!proof.lotInputHash().isEmpty() && !LotLocks.LOT_HASH.equals(proof.lotInputHash()),
                    "did not observe changed actual lot bytes");
            else
                require(!proof.poolInputHash().isEmpty() && !LotLocks.POOL_HASH.equals(proof.poolInputHash()),
                    "did not observe changed actual pool bytes");
        } else {
            require(mode.equals("active"), "unknown mode " + mode);
            var before = LotLocks.snapshot();
            require(before.active() && before.transformations() == 1, "cold bootstrap did not install: " + before);
            require(LotLocks.install() && LotLocks.snapshot().equals(before), "duplicate installation changed state");
            require(LotLocks.LOT_HASH.equals(before.lotInputHash())
                && LotLocks.POOL_HASH.equals(before.poolInputHash()), "actual input guard proof missing");
            nativeGets(false);
            Class<?> poolType = Class.forName("zombie.popman.ObjectPool", false, LotLocksChecks.class.getClassLoader());
            require(Modifier.isSynchronized(poolType.getDeclaredMethod("alloc").getModifiers())
                && Modifier.isSynchronized(poolType.getDeclaredMethod("release", Object.class).getModifiers()),
                "loaded pool lock contract changed");
            // The VM reuses the initial flags without attempting a late modifier change.
            instrumentation().retransformClasses(Class.forName("zombie.iso.IsoLot", false,
                LotLocksChecks.class.getClassLoader()));
            nativeGets(false);
            require(LotLocks.snapshot().equals(before), "retransform reapplied load-time patch");
        }
        if (args.length == 0) childModes();
        System.out.println("LOT_LOCKS_CHECKS_PASS " + mode + " " + LotLocks.snapshot());
    }
}
