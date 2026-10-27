import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.ZipFile;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;

/** Identical optional telemetry in stock/candidate. Never substitutes a parser or I/O. */
public final class LotIoCounters {
    public static final class Counts {
        public long opens, refills, bytes, eof;
    }
    private static final ThreadLocal<Counts> LOCAL = ThreadLocal.withInitial(Counts::new);
    public static Counts counts() { return LOCAL.get(); }
    public static void opened() { LOCAL.get().opens++; }
    public static void refill(int bytes) {
        Counts value = LOCAL.get();
        value.refills++;
        if (bytes >= 0) value.bytes += bytes;
        else value.eof++;
    }

    public static void main(String[] args) throws Exception {
        String name = "zombie/util/BufferedRandomAccessFile";
        byte[] nativeBytes;
        try (ZipFile jar = new ZipFile(args[0])) {
            nativeBytes = jar.getInputStream(jar.getEntry(name + ".class")).readAllBytes();
        }
        if (!LotLockCandidate.sha(nativeBytes).equals(
                "cfd4b73296db2dc5e1f2cf8f5b679af88caac9b642b507ee85674759ebd5c76c"))
            throw new IllegalArgumentException("Native buffered reader changed");
        ClassReader reader = new ClassReader(nativeBytes);
        ClassWriter writer = new ClassWriter(reader, ClassWriter.COMPUTE_MAXS);
        int[] hooks = new int[2];
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int access, String method, String descriptor,
                                                       String signature, String[] exceptions) {
                MethodVisitor delegate = super.visitMethod(access, method, descriptor, signature, exceptions);
                boolean constructor = method.equals("<init>");
                boolean refill = method.equals("fillBuffer") && descriptor.equals("()I");
                if (!constructor && !refill) return delegate;
                return new MethodVisitor(Opcodes.ASM9, delegate) {
                    @Override public void visitInsn(int opcode) {
                        if (constructor && opcode == Opcodes.RETURN) {
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, "LotIoCounters", "opened", "()V", false);
                            hooks[0]++;
                        } else if (refill && opcode == Opcodes.IRETURN) {
                            super.visitInsn(Opcodes.DUP);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, "LotIoCounters", "refill", "(I)V", false);
                            hooks[1]++;
                        }
                        super.visitInsn(opcode);
                    }
                };
            }
        }, 0);
        if (hooks[0] != 2 || hooks[1] != 1) throw new AssertionError("Unexpected telemetry hooks");
        Path path = Path.of(args[1]).resolve(name + ".class");
        if (Files.exists(path)) throw new IllegalArgumentException("Telemetry overlay must be new");
        Files.createDirectories(path.getParent());
        Files.write(path, writer.toByteArray());
        System.out.println("LOT_IO_TELEMETRY_READY " + LotLockCandidate.sha(writer.toByteArray()));
    }
}
