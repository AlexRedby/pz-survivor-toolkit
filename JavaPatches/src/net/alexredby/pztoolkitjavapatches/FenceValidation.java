package net.alexredby.pztoolkitjavapatches;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HexFormat;
import java.util.LinkedHashSet;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.*;
import zombie.audio.parameters.ParameterFenceTypeLow.FenceType;
import zombie.debug.DebugType;
import zombie.iso.sprite.IsoSpriteManager;

public final class FenceValidation {
    private static final String TARGET = "zombie/iso/BrokenFences";
    private static final String HELPER = "net/alexredby/pztoolkitjavapatches/FenceValidation";
    private static final String HASH = "4368bbe6d2ec26198062bced328c3fef349e6be8e0f7184cbb9086de4cccc015";
    private static final LinkedHashSet<String> pending = new LinkedHashSet<>();
    private static boolean installed;
    private static boolean ready;

    private FenceValidation() { }

    public static synchronized boolean install(boolean supported) {
        if (!supported) return false;
        if (installed) return true;
        Instrumentation instrumentation = Accessor.tryGet(Loader.class, "g_instrumentation", (Instrumentation)null);
        if (instrumentation == null || !instrumentation.isRetransformClassesSupported()) return false;
        ClassFileTransformer transformer = new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader, String name, Class<?> type,
                                               ProtectionDomain domain, byte[] bytes) {
                return TARGET.equals(name) ? weave(bytes) : null;
            }
        };
        instrumentation.addTransformer(transformer, true);
        try {
            for (Class<?> type : instrumentation.getAllLoadedClasses()) {
                if (type.getName().equals(TARGET.replace('/', '.'))) instrumentation.retransformClasses(type);
            }
            installed = true;
            return true;
        } catch (Exception error) {
            instrumentation.removeTransformer(transformer);
            System.err.println("[PZToolkitJavaPatches] Disabled fence validation: " + error);
            return false;
        }
    }

    public static synchronized void registered(String name) {
        if (ready) validate(name);
        else pending.add(name);
    }

    public static synchronized void tilesLoaded() {
        if (ready) return;
        ready = true;
        int corrected = FenceProperties.tilesLoaded(IsoSpriteManager.instance, Main.FENCE_SUPPORTED && Main.PROPERTY_SUPPORTED);
        int checked = pending.size(), missing = 0;
        for (String name : pending) if (validate(name)) missing++;
        pending.clear();
        System.out.println("[PZToolkitJavaPatches] Fence validation ready: checked=" + checked + ", missing=" + missing
            + ", corrected=" + corrected);
    }

    public static synchronized void reset() {
        pending.clear();
        ready = false;
    }

    private static boolean validate(String name) {
        var properties = IsoSpriteManager.instance.getSprite(name).getProperties();
        if (properties.get("ThumpSound") == null
            && FenceType.fromString(properties.get("FenceTypeLow"), null) == null) {
            DebugType.Sound.error("Missing ThumpSound for breakable object " + name);
            return true;
        }
        return false;
    }

    // HotSpot reorders methods and Code attributes; compare the whole class after ASM serialization.
    private static byte[] canonical(byte[] bytes) {
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader, 0);
        var methods = new ArrayList<String>();
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                                                        String signature, String[] exceptions) {
                methods.add(name + descriptor);
                return null;
            }
            @Override public void visitEnd() { }
        }, 0);
        Collections.sort(methods);
        for (String key : methods) {
            reader.accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                                                            String signature, String[] exceptions) {
                    if (!key.equals(name + descriptor)) return null;
                    return new MethodVisitor(Opcodes.ASM9,
                        writer.visitMethod(access, name, descriptor, signature, exceptions)) { };
                }
            }, 0);
        }
        writer.visitEnd();
        return writer.toByteArray();
    }

    private static byte[] weave(byte[] bytes) {
        try {
            byte[] original;
            try (var input = FenceValidation.class.getClassLoader().getResourceAsStream(TARGET + ".class")) {
                if (input == null) return null;
                original = input.readAllBytes();
            }
            if (!HASH.equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(original)))
                || !Arrays.equals(canonical(original), canonical(bytes))) return null;
            ClassReader reader = new ClassReader(bytes);
            ClassWriter writer = new ClassWriter(reader, 0);
            int[] replacements = new int[2];
            reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
                @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                                                            String signature, String[] exceptions) {
                    MethodVisitor output = super.visitMethod(access, name, descriptor, signature, exceptions);
                    if (name.equals("Reset") && descriptor.equals("()V")) {
                        return new MethodVisitor(Opcodes.ASM9, output) {
                            @Override public void visitInsn(int opcode) {
                                if (opcode == Opcodes.RETURN) {
                                    super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "reset", "()V", false);
                                    replacements[1]++;
                                }
                                super.visitInsn(opcode);
                            }
                        };
                    }
                    if (!name.equals("addBrokenTiles") || !descriptor.equals("(Lse/krka/kahlua/j2se/KahluaTableImpl;)V")) return output;
                    return new MethodVisitor(Opcodes.ASM9, output) {
                        int skip;
                        boolean skipInstruction() { if (skip == 0) return false; skip--; return true; }
                        @Override public void visitFieldInsn(int opcode, String owner, String field, String type) {
                            if (skipInstruction()) return;
                            if (opcode == Opcodes.GETSTATIC && owner.equals("zombie/iso/sprite/IsoSpriteManager") && field.equals("instance")) {
                                super.visitVarInsn(Opcodes.ALOAD, 3);
                                super.visitMethodInsn(Opcodes.INVOKESTATIC, HELPER, "registered", "(Ljava/lang/String;)V", false);
                                skip = 10;
                                replacements[0]++;
                            } else super.visitFieldInsn(opcode, owner, field, type);
                        }
                        @Override public void visitVarInsn(int opcode, int variable) {
                            if (!skipInstruction()) super.visitVarInsn(opcode, variable);
                        }
                        @Override public void visitMethodInsn(int opcode, String owner, String method, String type, boolean itf) {
                            if (!skipInstruction()) super.visitMethodInsn(opcode, owner, method, type, itf);
                        }
                        @Override public void visitLdcInsn(Object value) { if (!skipInstruction()) super.visitLdcInsn(value); }
                        @Override public void visitJumpInsn(int opcode, Label label) { if (!skipInstruction()) super.visitJumpInsn(opcode, label); }
                        @Override public void visitInvokeDynamicInsn(String method, String type, Handle handle, Object... args) {
                            if (!skipInstruction()) super.visitInvokeDynamicInsn(method, type, handle, args);
                        }
                    };
                }
            }, 0);
            return replacements[0] == 1 && replacements[1] == 1 ? writer.toByteArray() : null;
        } catch (Exception error) {
            System.err.println("[PZToolkitJavaPatches] Disabled fence bytecode: " + error);
            return null;
        }
    }
}
