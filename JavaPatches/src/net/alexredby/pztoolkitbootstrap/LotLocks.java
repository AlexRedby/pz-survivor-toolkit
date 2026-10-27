package net.alexredby.pztoolkitbootstrap;

import java.io.InputStream;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Modifier;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.HexFormat;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.Opcodes;

/** Load-time-only removal of the redundant IsoLot class monitor; the native parser is untouched. */
public final class LotLocks {
    static final String TARGET = "zombie/iso/IsoLot";
    static final String POOL = "zombie/popman/ObjectPool";
    static final String PRIMITIVE = "(Lzombie/iso/MapFiles;IIIILzombie/iso/IsoChunk;)Lzombie/iso/IsoLot;";
    static final String BOXED = "(Lzombie/iso/MapFiles;Ljava/lang/Integer;Ljava/lang/Integer;"
        + "Ljava/lang/Integer;Ljava/lang/Integer;Lzombie/iso/IsoChunk;)Lzombie/iso/IsoLot;";
    static final String LOT_HASH = "c7dd6226fec81d27e761e661fcedc93164bf95fe07c59c3b2b0475c160d37b05";
    static final String POOL_HASH = "38c883df7d01b8d168510c0aaebf0fd02ad0ecd13630dd4adf2d35dcd6bd641e";
    private static final ClassLoader GAME_LOADER = LotLocks.class.getClassLoader();
    private static boolean attempted;
    private static volatile boolean active;
    private static volatile String state = "not-installed";
    private static volatile String lotInputHash = "";
    private static volatile String poolInputHash = "";
    private static volatile int transformations;

    private LotLocks() { }

    /** Read-only proof for native fixtures and diagnostics, without triggering installation. */
    public record Snapshot(boolean active, String state, String lotInputHash, String poolInputHash,
                           int transformations) { }

    public static Snapshot snapshot() {
        return new Snapshot(active, state, lotInputHash, poolInputHash, transformations);
    }

    public static synchronized boolean install() {
        if (attempted) return active;
        attempted = true;
        ClassFileTransformer transformer = null;
        Instrumentation instrumentation = null;
        try {
            var field = Loader.class.getDeclaredField("g_instrumentation");
            field.setAccessible(true);
            instrumentation = (Instrumentation)field.get(null);
            if (instrumentation == null) return disabled("no-instrumentation");
            if (!LOT_HASH.equals(hash(resource(TARGET))) || !POOL_HASH.equals(hash(resource(POOL))))
                return disabled("unsupported-resource");
            for (Class<?> type : instrumentation.getAllLoadedClasses()) {
                if (type.getClassLoader() == GAME_LOADER
                    && (type.getName().equals(TARGET.replace('/', '.'))
                        || type.getName().equals(POOL.replace('/', '.'))))
                    return disabled("already-loaded:" + type.getName());
            }
            final boolean[] poolApproved = {false};
            transformer = new ClassFileTransformer() {
                @Override public byte[] transform(ClassLoader loader, String name, Class<?> type,
                        ProtectionDomain domain, byte[] bytes) {
                    if (loader != GAME_LOADER || type != null) return null;
                    if (POOL.equals(name)) {
                        poolInputHash = hash(bytes);
                        poolApproved[0] = POOL_HASH.equals(poolInputHash) && poolContract(bytes);
                        return null;
                    }
                    if (!TARGET.equals(name)) return null;
                    lotInputHash = hash(bytes);
                    if (!poolApproved[0]) return null;
                    byte[] result = transformReviewed(bytes);
                    if (result != null) transformations++;
                    return result;
                }
            };
            // Non-retransformable: the VM reuses this initial result on retransformation. Never
            // attempt to remove synchronized from an already defined method (a JVM schema change).
            instrumentation.addTransformer(transformer, false);
            Class<?> pool = Class.forName(POOL.replace('/', '.'), false, GAME_LOADER);
            if (!poolApproved[0] || !loadedPoolContract(pool)) return disabled("unsupported-pool-input");
            Class<?> lot = Class.forName(TARGET.replace('/', '.'), false, GAME_LOADER);
            if (transformations != 1 || !loadedLotContract(lot)) return disabled("unsupported-lot-input");
            active = true;
            state = "active";
            System.out.println("[PZToolkitJavaPatches] IsoLot locks ready: exact native inputs, two access flags");
            return true;
        } catch (Exception | LinkageError error) {
            return disabled(error.getClass().getSimpleName() + ":" + error.getMessage());
        } finally {
            if (!active && instrumentation != null && transformer != null)
                instrumentation.removeTransformer(transformer);
        }
    }

    private static boolean disabled(String reason) {
        state = reason;
        System.out.println("[PZToolkitJavaPatches] IsoLot locks disabled: " + reason);
        return false;
    }

    private static byte[] resource(String name) throws Exception {
        try (InputStream input = GAME_LOADER.getResourceAsStream(name + ".class")) {
            return input == null ? null : input.readAllBytes();
        }
    }

    static String hash(byte[] bytes) {
        if (bytes == null) return "";
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (java.security.NoSuchAlgorithmException impossible) {
            throw new AssertionError(impossible);
        }
    }

    static boolean poolContract(byte[] bytes) {
        if (!POOL_HASH.equals(hash(bytes))) return false;
        ClassReader reader = new ClassReader(bytes);
        char[] strings = new char[reader.getMaxStringLength()];
        int at = methods(reader), found = 0;
        int count = reader.readUnsignedShort(at);
        for (at += 2; count > 0; count--, at = skipMember(reader, at)) {
            String name = reader.readUTF8(at + 2, strings);
            String descriptor = reader.readUTF8(at + 4, strings);
            if (name.equals("alloc") && descriptor.equals("()Ljava/lang/Object;")
                || name.equals("release") && descriptor.equals("(Ljava/lang/Object;)V")) {
                if ((reader.readUnsignedShort(at) & Opcodes.ACC_SYNCHRONIZED) == 0) return false;
                found++;
            }
        }
        return found == 2;
    }

    static byte[] transformReviewed(byte[] bytes) {
        if (!LOT_HASH.equals(hash(bytes))) return null;
        ClassReader reader = new ClassReader(bytes);
        byte[] result = bytes.clone();
        char[] strings = new char[reader.getMaxStringLength()];
        int at = methods(reader), changed = 0;
        int count = reader.readUnsignedShort(at);
        for (at += 2; count > 0; count--, at = skipMember(reader, at)) {
            String name = reader.readUTF8(at + 2, strings);
            String descriptor = reader.readUTF8(at + 4, strings);
            if (name.equals("get") && (descriptor.equals(PRIMITIVE) || descriptor.equals(BOXED))) {
                int flags = reader.readUnsignedShort(at);
                if ((flags & (Opcodes.ACC_STATIC | Opcodes.ACC_SYNCHRONIZED))
                    != (Opcodes.ACC_STATIC | Opcodes.ACC_SYNCHRONIZED)) return null;
                result[at + 1] &= (byte)~Opcodes.ACC_SYNCHRONIZED;
                changed++;
            }
        }
        return changed == 2 ? result : null;
    }

    private static int methods(ClassReader reader) {
        int at = reader.header + 6;
        at += 2 + 2 * reader.readUnsignedShort(at);
        int count = reader.readUnsignedShort(at);
        for (at += 2; count > 0; count--) at = skipMember(reader, at);
        return at;
    }

    private static int skipMember(ClassReader reader, int at) {
        int count = reader.readUnsignedShort(at + 6);
        for (at += 8; count > 0; count--) at += 6 + reader.readInt(at + 2);
        return at;
    }

    private static boolean loadedPoolContract(Class<?> pool) throws Exception {
        return Modifier.isSynchronized(pool.getDeclaredMethod("alloc").getModifiers())
            && Modifier.isSynchronized(pool.getDeclaredMethod("release", Object.class).getModifiers());
    }

    private static boolean loadedLotContract(Class<?> lot) {
        int found = 0;
        for (var method : lot.getDeclaredMethods()) {
            String descriptor = java.lang.invoke.MethodType.methodType(method.getReturnType(),
                method.getParameterTypes()).descriptorString();
            if (method.getName().equals("get") && (descriptor.equals(PRIMITIVE) || descriptor.equals(BOXED))) {
                if (!Modifier.isStatic(method.getModifiers()) || Modifier.isSynchronized(method.getModifiers()))
                    return false;
                found++;
            }
        }
        return found == 2;
    }
}
