import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.zip.ZipFile;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.Opcodes;

/** Development-only candidate. The native parser and file objects remain unchanged. */
public final class LotLockCandidate {
    static final String TARGET = "zombie/iso/IsoLot";
    static final String PRIMITIVE = "(Lzombie/iso/MapFiles;IIIILzombie/iso/IsoChunk;)Lzombie/iso/IsoLot;";
    static final String BOXED = "(Lzombie/iso/MapFiles;Ljava/lang/Integer;Ljava/lang/Integer;"
            + "Ljava/lang/Integer;Ljava/lang/Integer;Lzombie/iso/IsoChunk;)Lzombie/iso/IsoLot;";
    static final String HASH = "c7dd6226fec81d27e761e661fcedc93164bf95fe07c59c3b2b0475c160d37b05";
    static final String POOL_HASH = "38c883df7d01b8d168510c0aaebf0fd02ad0ecd13630dd4adf2d35dcd6bd641e";

    static String sha(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }

    static byte[] transform(byte[] bytes) throws Exception {
        if (!sha(bytes).equals(HASH))
            throw new IllegalArgumentException("Unsupported or already transformed IsoLot bytes");
        ClassReader reader = new ClassReader(bytes);
        byte[] result = bytes.clone();
        char[] strings = new char[reader.getMaxStringLength()];
        int at = reader.header + 6; // access_flags, this_class, super_class
        at += 2 + 2 * reader.readUnsignedShort(at); // interfaces
        int fields = reader.readUnsignedShort(at);
        at += 2;
        for (int i = 0; i < fields; i++) at = skipMember(reader, at);
        int methods = reader.readUnsignedShort(at), changed = 0;
        at += 2;
        for (int i = 0; i < methods; i++) {
            String name = reader.readUTF8(at + 2, strings);
            String descriptor = reader.readUTF8(at + 4, strings);
            if (name.equals("get") && (descriptor.equals(PRIMITIVE) || descriptor.equals(BOXED))) {
                int access = reader.readUnsignedShort(at);
                if ((access & (Opcodes.ACC_STATIC | Opcodes.ACC_SYNCHRONIZED))
                        != (Opcodes.ACC_STATIC | Opcodes.ACC_SYNCHRONIZED))
                    throw new IllegalStateException("Native get lock contract changed");
                // ObjectPool.alloc/release already synchronize and publish borrowed objects.
                // Patch the access field in place; preserve every Code/debug/class attribute byte.
                result[at + 1] &= (byte)~Opcodes.ACC_SYNCHRONIZED;
                changed++;
            }
            at = skipMember(reader, at);
        }
        if (changed != 2) throw new IllegalStateException("Expected two lock flags");
        return result;
    }

    private static int skipMember(ClassReader reader, int at) {
        int attributes = reader.readUnsignedShort(at + 6);
        at += 8;
        for (int i = 0; i < attributes; i++) at += 6 + reader.readInt(at + 2);
        return at;
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("native JAR and new overlay required");
        Path output = Path.of(args[1]);
        if (Files.exists(output)) throw new IllegalArgumentException("Overlay must be new");
        byte[] bytes;
        try (ZipFile jar = new ZipFile(args[0])) {
            bytes = jar.getInputStream(jar.getEntry(TARGET + ".class")).readAllBytes();
            if (!sha(jar.getInputStream(jar.getEntry("zombie/popman/ObjectPool.class")).readAllBytes())
                    .equals(POOL_HASH)) throw new IllegalArgumentException("ObjectPool contract changed");
        }
        byte[] candidate = transform(bytes);
        try {
            transform(candidate);
            throw new AssertionError("Transformed input was admitted");
        } catch (IllegalArgumentException expected) { }
        bytes[bytes.length - 1] ^= 1;
        try {
            transform(bytes);
            throw new AssertionError("Changed input was admitted");
        } catch (IllegalArgumentException expected) { }
        Path target = output.resolve(TARGET + ".class");
        Files.createDirectories(target.getParent());
        Files.write(target, candidate);
        System.out.println("LOT_LOCK_CANDIDATE_READY " + sha(candidate));
    }
}
