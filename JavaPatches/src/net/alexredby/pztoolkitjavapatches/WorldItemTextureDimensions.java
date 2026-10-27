package net.alexredby.pztoolkitjavapatches;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.Arrays;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import zombie.GameWindow;
import zombie.core.textures.Texture;

/** Avoid dimension I/O for the pending 2D item draws that the native queue rejects. */
public final class WorldItemTextureDimensions {
    private static final String TARGET = "zombie/Lua/LuaManager$GlobalObject";
    private static final String TEXTURE = "zombie/core/textures/Texture";
    private static final String OWNER = "net/alexredby/pztoolkitjavapatches/WorldItemTextureDimensions";
    private static final String METHOD = "(Lzombie/inventory/InventoryItem;Lzombie/iso/IsoGridSquare;FFFF)V";
    public static final boolean SUPPORTED =
BytecodeSupport.supports("zombie/Lua/LuaManager$GlobalObject.class",
            "80ecbd3bd702db2f992db6cba7cb09c32d775fa6f2a3297e0460874ff5ba20c7")
            && BytecodeSupport.supports("zombie/core/textures/Texture.class",
            "2f4fba9ad6c33a9ba0763a68d16164833a682f7645e61a061f70bfdca33c1f8f")
            && BytecodeSupport.supports("zombie/core/sprite/GenericSpriteRenderState.class",
            "87143831d7d4519388c6c49b3041a956f68c56ffe57cedc720cc1c1fa83ea222")
            && BytecodeSupport.supports("zombie/core/SpriteRenderer.class",
            "12735b2809ddab37c96b9614e54d2d38639baa8f342546baedeb8562c617f9be")
            && BytecodeSupport.supports("zombie/asset/Asset.class",
            "c208e4ad3dcafedc2ef6a5c9ff5e300941af8a48c1bc36bc2188dab696e4a7dc")
            && BytecodeSupport.supports("zombie/asset/Asset$PRIVATE.class",
            "8b84cfdf065dc6b75deec3bab8a1d536a0071d657c7260c462c44b5c8a433288")
            && BytecodeSupport.supports("zombie/core/textures/TextureIDAssetManager.class",
            "59fbf0ae907f0ff052977f2e22121b1315488f8f5c860ae1f255a04c012d26f1")
            && BytecodeSupport.supports("zombie/core/textures/TextureID.class",
            "6d42d6f8496d12af2a28cd42680ea0a4875f889ae988ffc54c16c63c89998e94")
            && BytecodeSupport.supports("zombie/asset/AssetManager.class",
            "ff91e1c77a7ec6eabedae4887da68321ce3bb92c75b34d78a9ae97ed508a56dc")
            && BytecodeSupport.supports("zombie/fileSystem/FileSystemImpl.class",
            "6486a2122ff3bc51ad502bb2df0a6ad4b19f112d0c885b8b802f05096c52ae84")
            && BytecodeSupport.supports("zombie/GameWindow.class",
            "c3a3583923191b6aea23a74e6b05e2b53302bbcded7f89cae930e364a409dfb2");
    private static boolean installed;
    private static volatile boolean woven;

    private WorldItemTextureDimensions() { }

    private static boolean pending(Texture texture) {
        // FileSystemImpl dispatches completed image tasks from GameWindow.logic, not from
        // its file workers. Render3DItem does not pump that queue. Keep other threads and
        // custom Texture implementations on their original path.
        return texture.getClass() == Texture.class && Thread.currentThread() == GameWindow.gameThread
                && !texture.isReady();
    }

    public static int getWidth(Texture texture) { return pending(texture) ? 0 : texture.getWidth(); }
    public static int getHeight(Texture texture) { return pending(texture) ? 0 : texture.getHeight(); }
    public static int getWidthOrig(Texture texture) { return pending(texture) ? 0 : texture.getWidthOrig(); }
    public static int getHeightOrig(Texture texture) { return pending(texture) ? 0 : texture.getHeightOrig(); }

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
            if (loaded == null) Class.forName(TARGET.replace('/', '.'), false, WorldItemTextureDimensions.class.getClassLoader());
            else instrumentation.retransformClasses(loaded);
            if (woven) {
                installed = true;
                System.out.println("[PZToolkitJavaPatches] World-item texture dimensions ready: pending assets avoid redundant PNG size reads");
                return true;
            }
        } catch (Exception | LinkageError error) {
            System.err.println("[PZToolkitJavaPatches] World-item texture dimensions disabled: " + error);
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
                return name.equals("Render3DItem") && descriptor.equals(METHOD)
                        ? writer.visitMethod(access, name, descriptor, signature, exceptions) : null;
            }
        }, ClassReader.SKIP_DEBUG);
        writer.visitEnd();
        return writer.toByteArray();
    }

    static byte[] weave(byte[] bytes) {
        if (!SUPPORTED || bytes == null) return null;
        try (var stream = WorldItemTextureDimensions.class.getClassLoader().getResourceAsStream(TARGET + ".class")) {
            if (stream == null || !Arrays.equals(boundary(stream.readAllBytes()), boundary(bytes))) return null;
            return transformReviewed(bytes);
        } catch (Exception error) {
            return null;
        }
    }

    private static byte[] transformReviewed(byte[] bytes) {
        ClassReader reader = new ClassReader(bytes);
        ClassWriter writer = new ClassWriter(reader, 0);
        int[] counts = new int[4];
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                MethodVisitor output = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals("Render3DItem") || !descriptor.equals(METHOD)) return output;
                return new MethodVisitor(Opcodes.ASM9, output) {
                    @Override public void visitMethodInsn(int opcode, String owner, String name, String desc, boolean itf) {
                        int index = switch (name) {
                            case "getWidth" -> 0;
                            case "getHeight" -> 1;
                            case "getWidthOrig" -> 2;
                            case "getHeightOrig" -> 3;
                            default -> -1;
                        };
                        if (opcode == Opcodes.INVOKEVIRTUAL && TEXTURE.equals(owner) && desc.equals("()I") && index >= 0) {
                            counts[index]++;
                            // Same operand/result types and all original frames. In particular keep
                            // the native shader/depth state commands even for a rejected pending draw.
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, OWNER, name, "(L" + TEXTURE + ";)I", false);
                        } else super.visitMethodInsn(opcode, owner, name, desc, itf);
                    }
                };
            }
        }, 0);
        return Arrays.equals(counts, new int[]{1, 1, 2, 2}) ? writer.toByteArray() : null;
    }
}
