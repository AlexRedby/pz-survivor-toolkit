package net.alexredby.pztoolkitjavapatches;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.Label;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import zombie.iso.IsoGridSquare;
import zombie.util.list.PZArrayList;
import zombie.util.list.PZArrayUtil;

/** Invocation-local identity membership for the ordered translucent square union. */
public final class TranslucentSquareUnion {
    private static final String TARGET = "zombie/iso/fboRenderChunk/FBORenderCell";
    private static final String LIST = "zombie/util/list/PZArrayList";
    private static final String OWNER = "net/alexredby/pztoolkitjavapatches/TranslucentSquareUnion";
    private static final String METHOD = "(ILzombie/iso/IsoChunk;I)V";
    private static final String HELPER = "(L" + LIST + ";Ljava/util/List;Ljava/util/List;Ljava/util/List;)Z";
    public static final boolean SUPPORTED = BytecodeSupport.supports(TARGET + ".class",
            "d5c46201d60cff36397ee46c56b53dbaee6e26e8733836f27bf56ad871eedf94")
            && BytecodeSupport.supports("zombie/iso/IsoGridSquare.class",
            "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467")
            && BytecodeSupport.supports(LIST + ".class",
            "7ce79434a59558ed7c966d46d592d765ea6160949e0e87705002ccac7d4f5394")
            && BytecodeSupport.supports("zombie/util/list/PZArrayUtil.class",
            "7a96591c4f108b5e867320ed7c0a2a1b842cf49149e637860da362abbc931cde");
    private static final ThreadLocal<Scratch> SCRATCH = ThreadLocal.withInitial(Scratch::new);
    private static boolean installed;
    private static volatile boolean woven;

    private TranslucentSquareUnion() { }

    // At most 512 source entries are admitted, so this table stays at most half full.
    // Only occupied slots are cleared; an empty table retains no square references.
    private static final class Scratch {
        final Object[] entries = new Object[1024];
        final int[] occupied = new int[512];
        int count;
        boolean containsNull;
        boolean busy;

        boolean add(Object value) {
            if (value == null) {
                boolean fresh = !containsNull;
                containsNull = true;
                return fresh;
            }
            int slot = System.identityHashCode(value) & (entries.length - 1);
            while (entries[slot] != null) {
                if (entries[slot] == value) return false;
                slot = (slot + 1) & (entries.length - 1);
            }
            entries[slot] = value;
            occupied[count++] = slot;
            return true;
        }

        void clear() {
            while (count != 0) entries[occupied[--count]] = null;
            containsNull = false;
        }
    }

    /** False leaves the cleared target untouched, for execution of the original block. */
    @SuppressWarnings({"rawtypes", "unchecked"})
    public static boolean tryBuild(PZArrayList target, List items, List outlines, List objects) {
        if (items == null || outlines == null || objects == null || target == null
                || items.getClass() != ArrayList.class || outlines.getClass() != ArrayList.class
                || objects.getClass() != ArrayList.class || !target.isEmpty()) return false;
        long appendCount = (long) outlines.size() + objects.size();
        long total = items.size() + appendCount;
        if (appendCount < 64 || total < 128 || total > 512) return false;
        Scratch scratch = SCRATCH.get();
        if (scratch.busy) return false;
        scratch.busy = true;
        try {
            // Keep the native item's copy, including duplicates, nulls and failure prefix.
            PZArrayUtil.addAll(target, items);
            int budget = 512;
            boolean hashed = false;
            for (int source = 0; source < 2; source++) {
                List squares = source == 0 ? outlines : objects;
                for (int i = 0; i < squares.size(); i++) {
                    // Native membership's argument is this same cast. IsoGridSquare is final,
                    // inherits Object.equals, and its native/official resources are admitted.
                    IsoGridSquare square = (IsoGridSquare) squares.get(i);
                    if (!hashed) {
                        if (budget <= 0 && appendCount >= 32) {
                            for (int n = 0; n < target.size(); n++) scratch.add(target.get(n));
                            hashed = true;
                        } else {
                            int size = target.size(), n = 0;
                            Object[] entries = target.getElements();
                            while (n < size && entries[n] != square) n++;
                            budget -= n + (n < size ? 1 : 0);
                            if (n == size) target.add(square);
                        }
                    }
                    if (hashed && scratch.add(square)) target.add(square);
                    appendCount--;
                }
            }
            return true;
        } finally {
            scratch.clear();
            scratch.busy = false;
        }
    }

    public static synchronized boolean install() {
        if (installed) return woven;
        if (!SUPPORTED) return false;
        Instrumentation instrumentation = Accessor.tryGet(Loader.class, "g_instrumentation", null);
        if (instrumentation == null || !instrumentation.isRetransformClassesSupported()) return false;
        ClassFileTransformer transformer = new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader, String name, Class<?> type,
                    ProtectionDomain domain, byte[] bytes) {
                if (!TARGET.equals(name)) return null;
                byte[] result = weave(bytes);
                woven = result != null;
                return result;
            }
        };
        instrumentation.addTransformer(transformer, true);
        try {
            Class<?> loaded = Arrays.stream(instrumentation.getAllLoadedClasses())
                    .filter(type -> type.getName().equals(TARGET.replace('/', '.'))).findFirst().orElse(null);
            if (loaded == null) Class.forName(TARGET.replace('/', '.'), false, TranslucentSquareUnion.class.getClassLoader());
            else instrumentation.retransformClasses(loaded);
            if (woven) {
                installed = true;
                System.out.println("[PZToolkitJavaPatches] Translucent square union ready: invocation-local identity membership");
                return true;
            }
        } catch (Exception | LinkageError error) {
            System.err.println("[PZToolkitJavaPatches] Translucent square union disabled: " + error);
        }
        instrumentation.removeTransformer(transformer);
        woven = false;
        return false;
    }

    private static byte[] boundary(byte[] bytes) {
        ClassWriter writer = new ClassWriter(0);
        writer.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, TARGET, null, "java/lang/Object", null);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                return name.equals("renderOneLevel_Translucent") && descriptor.equals(METHOD)
                        ? writer.visitMethod(access, name, descriptor, signature, exceptions) : null;
            }
        }, ClassReader.SKIP_DEBUG);
        writer.visitEnd();
        return writer.toByteArray();
    }

    static byte[] weave(byte[] bytes) {
        if (!SUPPORTED || bytes == null) return null;
        try (var stream = TranslucentSquareUnion.class.getClassLoader().getResourceAsStream(TARGET + ".class")) {
            if (stream == null || !Arrays.equals(boundary(stream.readAllBytes()), boundary(bytes))) return null;
            return transformReviewed(bytes);
        } catch (Exception error) {
            return null;
        }
    }

    // Add one conditional route around the two original union loops. Keep their frames,
    // exception handlers, sorting, profiler cleanup and every render call verbatim.
    private static byte[] transformReviewed(byte[] bytes) {
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader, 0);
        int[] additions = {0}, contains = {0}, ends = {0}, existing = {0};
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                MethodVisitor output = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals("renderOneLevel_Translucent") || !descriptor.equals(METHOD)) return output;
                return new MethodVisitor(Opcodes.ASM9, output) {
                    final Label success = new Label();
                    Label end;
                    int previousVariable = -1, lastVariable = -1;
                    @Override public void visitVarInsn(int opcode, int variable) {
                        previousVariable = lastVariable;
                        lastVariable = opcode == Opcodes.ALOAD ? variable : -1;
                        super.visitVarInsn(opcode, variable);
                    }
                    @Override public void visitMethodInsn(int opcode, String owner, String name, String desc, boolean itf) {
                        if (OWNER.equals(owner)) existing[0]++;
                        if (LIST.equals(owner) && name.equals("contains")) contains[0]++;
                        if (owner.equals("zombie/util/list/PZArrayUtil") && name.equals("addAll")) {
                            if (lastVariable != 8 || (previousVariable != 9 && previousVariable != 10)) {
                                additions[0] += 100;
                            } else {
                                additions[0]++;
                                super.visitVarInsn(Opcodes.ALOAD, 7);
                                super.visitVarInsn(Opcodes.ALOAD, 6);
                                super.visitMethodInsn(Opcodes.INVOKESTATIC, OWNER, "tryBuild", HELPER, false);
                                super.visitJumpInsn(Opcodes.IFNE, success);
                                super.visitVarInsn(Opcodes.ALOAD, previousVariable);
                                super.visitVarInsn(Opcodes.ALOAD, 8);
                            }
                        }
                        super.visitMethodInsn(opcode, owner, name, desc, itf);
                    }
                    @Override public void visitJumpInsn(int opcode, Label label) {
                        if (additions[0] == 1 && opcode == Opcodes.IF_ICMPGE && ++ends[0] == 2) end = label;
                        super.visitJumpInsn(opcode, label);
                    }
                    @Override public void visitLabel(Label label) {
                        if (label == end) super.visitLabel(success);
                        super.visitLabel(label);
                    }
                    @Override public void visitMaxs(int stack, int locals) {
                        super.visitMaxs(Math.max(4, stack), locals);
                    }
                };
            }
        }, 0);
        return additions[0] == 1 && contains[0] == 2 && ends[0] >= 2 && existing[0] == 0
                ? writer.toByteArray() : null;
    }
}
