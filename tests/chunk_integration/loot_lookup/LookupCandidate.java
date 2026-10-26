import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.zip.ZipFile;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;

/** Research-only splice of one redundant native lookup. Never loaded by the shipped mods. */
public final class LookupCandidate {
    static final String TARGET = "zombie/inventory/ItemPickerJava";
    static final String PICK = "Lzombie/inventory/ItemPickerJava$ItemPickerItem;";
    static final String CHARACTER = "Lzombie/characters/IsoGameCharacter;";
    static final String ITEM = "Lzombie/scripting/objects/Item;";
    static final String BASE = "(" + PICK + CHARACTER + "Z)F";
    static final String CHANCE = "(" + PICK + CHARACTER + "Lzombie/inventory/ItemContainer;FZ)F";
    static final String HASH = "5c8cf626e46a52cdbd9d73e9de10766dece3388ee3e4f4d8d071df5e44d68522";

    static byte[] transform(byte[] bytes) throws Exception {
        if (!HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)).equals(HASH))
            throw new IllegalArgumentException("Unsupported or already transformed ItemPickerJava bytes");
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
        int[] changed = {0};
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                MethodVisitor output = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals("getActualSpawnChance") || !descriptor.equals(CHANCE)) return output;
                return new MethodVisitor(Opcodes.ASM9, output) {
                    @Override public void visitMethodInsn(int opcode, String owner, String name,
                            String descriptor, boolean isInterface) {
                        if (opcode == Opcodes.INVOKESTATIC && owner.equals(TARGET)
                                && name.equals("getBaseChance") && descriptor.equals(BASE)) {
                            // Replace only the lookup wrapper with its original multiply/callee.
                            // Slots 0, 1 and 4 are the same arguments already on the stack.
                            super.visitInsn(Opcodes.POP);
                            super.visitInsn(Opcodes.POP);
                            super.visitInsn(Opcodes.POP);
                            super.visitVarInsn(Opcodes.ALOAD, 0);
                            super.visitFieldInsn(Opcodes.GETFIELD, TARGET + "$ItemPickerItem", "chance", "F");
                            super.visitVarInsn(Opcodes.ALOAD, 1);
                            super.visitVarInsn(Opcodes.ILOAD, 4);
                            // Original lookup, including null; never substitute the modifier's Empty fallback.
                            super.visitVarInsn(Opcodes.ALOAD, 6);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, TARGET, "getBaseChanceMultiplier",
                                    "(" + CHARACTER + "Z" + ITEM + ")F", false);
                            super.visitInsn(Opcodes.FMUL);
                            changed[0]++;
                        } else super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                    }
                };
            }
        }, 0);
        if (changed[0] != 1) throw new IllegalStateException("Expected exactly one base-chance call");
        return writer.toByteArray();
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("native JAR and new overlay directory required");
        Path output = Path.of(args[1]);
        if (Files.exists(output)) throw new IllegalArgumentException("Overlay must be a new directory");
        byte[] bytes;
        try (ZipFile jar = new ZipFile(args[0])) {
            bytes = jar.getInputStream(jar.getEntry(TARGET + ".class")).readAllBytes();
        }
        byte[] patched = transform(bytes);
        // Fail-closed admission is exercised on changed input, including our own transformed class.
        try {
            transform(patched);
            throw new AssertionError("Transformed class was incorrectly admitted");
        } catch (IllegalArgumentException expected) { }
        Path target = output.resolve(TARGET + ".class");
        Files.createDirectories(target.getParent());
        Files.write(target, patched);
        System.out.println("LOOKUP_SPLICE_READY " + HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(patched)));
    }
}
