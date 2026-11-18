package net.alexredby.pztoolkitjavapatches;

import java.awt.image.BufferedImage;
import java.io.InputStream;
import java.io.ByteArrayInputStream;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;
import javax.imageio.ImageIO;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.Label;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import zombie.GameWindow;
import zombie.asset.Asset;
import zombie.core.textures.Texture;

/** Runs native caller instructions; only GPU/world collaborators are replaced with recording fixtures. */
public final class WorldItemTextureChecks {
    private static final String SELF = WorldItemTextureChecks.class.getName().replace('.', '/');
    private static final String GLOBAL = "zombie/Lua/LuaManager$GlobalObject";
    private static final String TEX = "zombie/core/textures/Texture";
    private static final String HELPER = "net/alexredby/pztoolkitjavapatches/WorldItemTextureDimensions";
    private static final String CALLER = "(Lzombie/inventory/InventoryItem;Lzombie/iso/IsoGridSquare;FFFF)V";
    private static final String DRAW = "(L" + TEX + ";FFFFFFFFLjava/util/function/Consumer;)V";
    private static final List<String> events = new ArrayList<>();
    private static final Map<String, Texture> textures = new HashMap<>();
    private static int generated;
    private static Method textureRender, spriteRender;
    public static int tileScale = 2;
    public static boolean fboRenderChunk;
    public static float nextZ;
    public static final Frame frameState = new Frame();
    public static final Renderer instance = new Renderer();
    public static Status status = Status.Other;
    private static float[] geometry;

    public enum Status { Loading, Ready, Other }
    public static final class Script { public float scaleWorldIcon = 1.75f; }
    public static final class Item {
        public Texture texture;
        public Script script;
        public boolean world;
        public String worldTexture = "world";
        public Texture getTex() { return texture; }
        public boolean isUseWorldItem() { return world; }
        public String getWorldTexture() { return worldTexture; }
        public Script getScriptItem() { return script; }
    }
    public static final class Frame {
        public float offX = 7, offY = 11, camCharacterX = 4.25f, camCharacterY = 6.5f;
        public int playerIndex = 2;
    }
    public static final class Depth { public float depthStart = .625f; }
    public static final class Renderer {
        public void StartShader(int shader, int player) { events.add("shader:" + shader + ":" + player); }
        public void render(Texture t, float x, float y, float w, float h, float r, float g, float b, float a, Consumer<?> c) {
            invoke(spriteRender, this, t, x, y, w, h, r, g, b, a, c);
        }
    }
    public static Texture getSharedTexture(String name) { events.add("lookup:" + name); return textures.get(name); }
    public static Status renderMain(Item item, Object square, Object target, float x, float y, float z,
                                    float angle, float rotation, boolean enabled) { events.add("model"); return status; }
    public static float XToScreen(float x, float y, float z, int ignored) { return 50 * (x - y); }
    public static float YToScreen(float x, float y, float z, int ignored) { return 25 * (x + y) - 100 * z; }
    public static int fastfloor(float value) { return (int) Math.floor(value); }
    public static void glDepthMask(boolean value) { events.add("mask:" + value); }
    public static void enableDepthTest() { events.add("depth-test"); }
    public static void glDepthFunc(int value) { events.add("depth-func:" + value); }
    public static Depth getSquareDepthData(int x, int y, float xx, float yy, float z) {
        events.add("depth:" + x + ":" + y + ":" + xx + ":" + yy + ":" + z); return new Depth();
    }
    public static void render(Texture t, float x, float y, float w, float h, float r, float g, float b, float a, Consumer<?> c) {
        invoke(textureRender, t, x, y, w, h, r, g, b, a, c);
    }
    public static void capture(Texture t, float x, float y, float w, float h, float r, float g, float b, float a, Consumer<?> c) {
        events.add("draw"); geometry = new float[] {x, y, w, h, r, g, b, a, nextZ};
    }
    private static Object invoke(Method method, Object... args) {
        try { return method.invoke(null, args); }
        catch (InvocationTargetException e) { throw new RuntimeException(e.getCause()); }
        catch (ReflectiveOperationException e) { throw new AssertionError(e); }
    }
    private static byte[] resource(String name) throws Exception {
        try (InputStream input = WorldItemTextureChecks.class.getClassLoader().getResourceAsStream(name + ".class")) {
            require(input != null, "Missing resource " + name); return input.readAllBytes();
        }
    }
    private static String type(String name) {
        return switch (name) {
            case "zombie/inventory/InventoryItem" -> SELF + "$Item";
            case "zombie/iso/IsoGridSquare" -> "java/lang/Object";
            case "zombie/scripting/objects/Item" -> SELF + "$Script";
            case "zombie/core/skinnedmodel/model/ItemModelRenderer$RenderStatus" -> SELF + "$Status";
            case "zombie/iso/IsoCamera$FrameState" -> SELF + "$Frame";
            case "zombie/iso/IsoDepthHelper$Results" -> SELF + "$Depth";
            case "zombie/core/SpriteRenderer" -> SELF + "$Renderer";
            case "zombie/core/skinnedmodel/model/WorldItemModelDrawer", "zombie/core/Core",
                 "zombie/core/PerformanceSettings", "zombie/iso/IsoUtils", "zombie/iso/IsoCamera",
                 "zombie/IndieGL", "zombie/core/math/PZMath", "zombie/iso/IsoDepthHelper",
                 "zombie/core/textures/TextureDraw" -> SELF;
            default -> name;
        };
    }
    private static String descriptor(String desc) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < desc.length(); i++) {
            char c = desc.charAt(i); out.append(c);
            if (c == 'L') { int end = desc.indexOf(';', i); out.append(type(desc.substring(i + 1, end))).append(';'); i = end; }
        }
        return out.toString();
    }
    private static final class Loader extends ClassLoader {
        Loader() { super(WorldItemTextureChecks.class.getClassLoader()); }
        Class<?> define(String name, byte[] bytes) { return defineClass(name.replace('/', '.'), bytes, 0, bytes.length); }
    }
    /** Copy the actual method, including branches and exception handlers; do not encode its geometry here. */
    private static Method extract(byte[] bytes, String name, String desc, String outputDesc, boolean readiness) throws Exception {
        String generatedName = SELF + "$Native" + generated++;
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
        writer.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, generatedName, null, "java/lang/Object", null);
        int[] found = {0};
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access, String n, String d, String sig, String[] exceptions) {
                if (!name.equals(n) || !desc.equals(d)) return null;
                found[0]++;
                MethodVisitor output = writer.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "run", outputDesc, null, null);
                return new MethodVisitor(Opcodes.ASM9, output) {
                    boolean stopped;
                    @Override public void visitFrame(int t, int nl, Object[] l, int ns, Object[] s) {}
                    @Override public void visitFieldInsn(int op, String owner, String n, String d) {
                        if (!stopped) super.visitFieldInsn(op, owner.equals("zombie/core/SpriteRenderer") && n.equals("instance") ? SELF : type(owner), n, descriptor(d));
                    }
                    @Override public void visitMethodInsn(int op, String owner, String n, String d, boolean itf) {
                        if (stopped) return;
                        if (readiness && n.equals("CheckSpriteSlots")) {
                            // The receiver is already on the stack. Observe only after the native rejection checks.
                            output.visitInsn(Opcodes.POP);
                            output.visitVarInsn(Opcodes.ALOAD, 1);
                            for (int v = 2; v <= 9; v++) output.visitVarInsn(Opcodes.FLOAD, v);
                            output.visitVarInsn(Opcodes.ALOAD, 10);
                            output.visitMethodInsn(Opcodes.INVOKESTATIC, SELF, "capture", DRAW, false);
                            output.visitInsn(Opcodes.RETURN); stopped = true; return;
                        }
                        if (owner.equals(TEX) && n.equals("getSharedTexture")) owner = SELF;
                        else if (owner.equals(TEX) && n.equals("render")) {
                            owner = SELF; op = Opcodes.INVOKESTATIC; d = "(L" + TEX + ";" + d.substring(1);
                        }
                        super.visitMethodInsn(op, type(owner), n, descriptor(d), itf);
                    }
                    @Override public void visitVarInsn(int o, int v) { if (!stopped) super.visitVarInsn(o, v); }
                    @Override public void visitInsn(int o) { if (!stopped) super.visitInsn(o); }
                    @Override public void visitIntInsn(int o, int v) { if (!stopped) super.visitIntInsn(o, v); }
                    @Override public void visitLdcInsn(Object v) { if (!stopped) super.visitLdcInsn(v); }
                    @Override public void visitJumpInsn(int o, Label l) { if (!stopped) super.visitJumpInsn(o, l); }
                    @Override public void visitLabel(Label l) { if (!stopped) super.visitLabel(l); }
                    @Override public void visitTypeInsn(int o, String t) { if (!stopped) super.visitTypeInsn(o, type(t)); }
                    @Override public void visitLineNumber(int n, Label l) {}
                    @Override public void visitLocalVariable(String n, String d, String s, Label a, Label b, int v) {}
                    @Override public void visitMaxs(int a, int b) { super.visitMaxs(0, 0); }
                };
            }
        }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        require(found[0] == 1, "Native method missing/ambiguous: " + name);
        writer.visitEnd();
        return Arrays.stream(new Loader().define(generatedName, writer.toByteArray()).getMethods())
                .filter(m -> m.getName().equals("run")).findFirst().orElseThrow();
    }
    private record Result(List<String> events, float[] geometry, float depth, Class<?> error) {}
    private static Result run(Method method, Item item, Object square) {
        events.clear(); geometry = null; nextZ = -99;
        Class<?> error = null;
        try { method.invoke(null, null, item, square, 3f, 5f, .5f, 20f); }
        catch (InvocationTargetException e) { error = e.getCause().getClass(); }
        catch (ReflectiveOperationException e) { throw new AssertionError(e); }
        return new Result(List.copyOf(events), geometry == null ? null : geometry.clone(), nextZ, error);
    }
    private static void same(Result a, Result b, String context) {
        require(a.events.equals(b.events) && Arrays.equals(a.geometry, b.geometry) && a.depth == b.depth && a.error == b.error,
                context + ": " + a.events + " / " + b.events + " geometry " + Arrays.toString(a.geometry) + " / " + Arrays.toString(b.geometry));
    }
    private static void field(Texture texture, String name, Object value) throws Exception {
        Field f = Texture.class.getDeclaredField(name); f.setAccessible(true); f.set(texture, value);
    }
    private static int width(Texture texture) throws Exception {
        Field f = Texture.class.getDeclaredField("width"); f.setAccessible(true); return f.getInt(texture);
    }
    private static Texture pending(Path png) throws Exception { Texture t = new Texture(); field(t, "name", png.toString()); return t; }
    private static byte[] weave(Class<?> helper, byte[] bytes) throws Exception {
        Method m = helper.getDeclaredMethod("weave", byte[].class); m.setAccessible(true); return (byte[]) m.invoke(null, (Object) bytes);
    }
    private static byte[] changed(byte[] bytes) {
        ClassWriter w = new ClassWriter(0);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9, w) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                MethodVisitor out = super.visitMethod(a, n, d, s, e);
                if (!n.equals("Render3DItem") || !d.equals(CALLER)) return out;
                return new MethodVisitor(Opcodes.ASM9, out) {
                    @Override public void visitMethodInsn(int op, String o, String n, String d, boolean itf) {
                        super.visitMethodInsn(op, o, o.equals(TEX) && n.equals("getWidth") ? "getWidthHW" : n, d, itf);
                    }
                };
            }
        }, 0); return w.toByteArray();
    }
    private static void checkUnknownResources(byte[] original) throws Exception {
        for (String unknown : List.of(GLOBAL, TEX, "zombie/core/sprite/GenericSpriteRenderState", "zombie/core/SpriteRenderer",
                "zombie/asset/Asset", "zombie/asset/Asset$PRIVATE", "zombie/core/textures/TextureIDAssetManager",
                "zombie/core/textures/TextureID", "zombie/asset/AssetManager",
                "zombie/fileSystem/FileSystemImpl", "zombie/GameWindow")) {
            ClassLoader loader = new ClassLoader(WorldItemTextureChecks.class.getClassLoader()) {
                @Override public InputStream getResourceAsStream(String name) {
                    return name.equals(unknown + ".class") ? new ByteArrayInputStream(new byte[] {0}) : super.getResourceAsStream(name);
                }
                @Override protected synchronized Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
                    String internal = name.replace('.', '/');
                    if (!internal.equals(HELPER) && !internal.equals(SELF.substring(0, SELF.lastIndexOf('/')) + "/BytecodeSupport"))
                        return super.loadClass(name, resolve);
                    Class<?> result = findLoadedClass(name);
                    if (result == null) try {
                        byte[] bytes = resource(internal); result = defineClass(name, bytes, 0, bytes.length);
                    } catch (Exception e) { throw new ClassNotFoundException(name, e); }
                    if (resolve) resolveClass(result); return result;
                }
            };
            Class<?> helper = Class.forName(HELPER.replace('/', '.'), true, loader);
            require(!helper.getField("SUPPORTED").getBoolean(null), "Unknown dependency admitted: " + unknown);
            require(weave(helper, original) == null, "Unknown dependency transformed caller: " + unknown);
            require(!(Boolean) helper.getMethod("install").invoke(null), "Unknown dependency installed: " + unknown);
        }
    }
    private static void compareStructure(byte[] original, byte[] woven) {
        byte[][] normalized = new byte[2][]; int[] replaced = {0};
        for (int i = 0; i < 2; i++) {
            final boolean candidate = i == 1;
            ClassWriter w = new ClassWriter(0);
            new ClassReader(candidate ? woven : original).accept(new ClassVisitor(Opcodes.ASM9, w) {
                @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                    return new MethodVisitor(Opcodes.ASM9, super.visitMethod(a, n, d, s, e)) {
                        @Override public void visitMethodInsn(int op, String o, String n, String d, boolean itf) {
                            if (o.equals(HELPER)) { require(op == Opcodes.INVOKESTATIC && d.equals("(L" + TEX + ";)I"), "Unexpected helper call");
                                replaced[0]++; op = Opcodes.INVOKEVIRTUAL; o = TEX; d = "()I"; }
                            super.visitMethodInsn(op, o, n, d, itf);
                        }
                    };
                }
            }, 0); normalized[i] = w.toByteArray();
        }
        require(replaced[0] == 6, "Expected exactly six replaced getter call sites");
        require(Arrays.equals(normalized[0], normalized[1]), "Weave modified instructions/fields/state beyond getter calls");
    }
    public static final class CustomTexture extends Texture {
        int calls;
        @Override public int getWidth() { calls++; return 23; }
        @Override public int getHeight() { calls++; return 29; }
        @Override public int getWidthOrig() { calls++; return 31; }
        @Override public int getHeightOrig() { calls++; return 37; }
    }
    private static void require(boolean ok, String message) { if (!ok) throw new AssertionError(message); }

    public static void main(String[] args) throws Throwable {
        Class<?> helper = Class.forName(HELPER.replace('/', '.'));
        require(helper.getField("SUPPORTED").getBoolean(null), "Native resource guard rejected current game classes");
        byte[] original = resource(GLOBAL), woven = weave(helper, original);
        require(woven != null, "Native caller not transformed");
        require(weave(helper, woven) == null, "Already woven caller accepted");
        require(weave(helper, changed(original)) == null, "Unknown getter shape accepted");
        compareStructure(original, woven);
        checkUnknownResources(original);
        String output = "(Ljava/lang/Object;L" + SELF + "$Item;Ljava/lang/Object;FFFF)V";
        Method control = extract(original, "Render3DItem", CALLER, output, false);
        Method candidate = extract(woven, "Render3DItem", CALLER, output, false);
        textureRender = extract(resource(TEX), "render", "(FFFFFFFFLjava/util/function/Consumer;)V", DRAW, false);
        spriteRender = extract(resource("zombie/core/sprite/GenericSpriteRenderState"), "render", DRAW,
                "(L" + SELF + "$Renderer;" + DRAW.substring(1), true);
        Thread old = GameWindow.gameThread;
        Path png = Files.createTempFile("pz-world-texture-", ".png");
        try {
            ImageIO.write(new BufferedImage(41, 67, BufferedImage.TYPE_INT_ARGB), "PNG", png.toFile());
            // Initialize only the allowed fixture prefix, not the game/mod filesystem.
            zombie.ZomboidFileSystem.instance.base.set(png.getParent().toFile());
            GameWindow.gameThread = Thread.currentThread();
            Item item = new Item(); Object square = new Object();
            Texture baseline = pending(png); item.texture = baseline; textures.put(png.toString(), baseline);
            Result before = run(control, item, square);
            require(before.error == null && before.geometry == null && width(baseline) == 41,
                    "Native pending caller did not reproduce synchronous PNG header read before render rejection: " + before + " width=" + width(baseline));
            Texture optimized = pending(png); item.texture = optimized; textures.put(png.toString(), optimized);
            for (boolean fbo : new boolean[] {false, true}) for (boolean script : new boolean[] {false, true}) {
                fboRenderChunk = fbo; item.script = script ? new Script() : null;
                item.texture = baseline; textures.put(png.toString(), baseline); Result a = run(control, item, square);
                item.texture = optimized; textures.put(png.toString(), optimized);
                for (int repeat = 0; repeat < 5; repeat++) {
                    Result result = run(candidate, item, square); same(a, result, "pending rejection/state");
                    require(width(optimized) == 0, "Pending getter read PNG header");
                    require(!fbo || result.events.contains("mask:false") && result.depth == .25f,
                            "Rejected pending draw lost native FBO state commands");
                }
            }
            for (Texture t : new Texture[] {baseline, optimized}) {
                t.setWidth(43); t.setHeight(71); field(t, "widthOrig", 83); field(t, "heightOrig", 109);
                t.setOffsetX(2); t.setOffsetY(3); t.onCreated(Asset.State.READY);
            }
            for (boolean fbo : new boolean[] {false, true}) for (boolean script : new boolean[] {false, true}) {
                fboRenderChunk = fbo; item.script = script ? new Script() : null;
                item.texture = baseline; textures.put(png.toString(), baseline); Result a = run(control, item, square);
                item.texture = optimized; textures.put(png.toString(), optimized); Result b = run(candidate, item, square);
                same(a, b, "ready geometry/state fbo=" + fbo + " script=" + script);
                require(b.error == null && b.geometry != null && b.geometry[2] == 43 && b.geometry[3] == 71,
                        "Ready caller lost authored dimensions");
                require(b.events.get(b.events.size() - 1).equals("draw"), "Draw command order changed");
                require(!fbo || b.events.contains("mask:false") && b.geometry[8] == .25f, "FBO depth state missing");
            }
            same(run(control, null, square), run(candidate, null, square), "null item");
            same(run(control, item, null), run(candidate, item, null), "null square");
            for (Status model : new Status[] {Status.Ready, Status.Loading}) {
                status = model; Result result = run(candidate, item, square);
                same(run(control, item, square), result, "model " + model);
                require(result.events.equals(List.of("model")), "Model path fell through to texture lookup");
            }
            status = Status.Other; textures.clear();
            same(run(control, item, square), run(candidate, item, square), "missing shared texture");
            item.texture = null; same(run(control, item, square), run(candidate, item, square), "missing item texture");
            item.texture = optimized; textures.put(png.toString(), optimized); item.world = true;
            same(run(control, item, square), run(candidate, item, square), "world icon fallback"); item.world = false;
            for (String getter : List.of("getWidth", "getHeight", "getWidthOrig", "getHeightOrig")) {
                Method get = helper.getMethod(getter, Texture.class);
                Texture pending = pending(png); GameWindow.gameThread = new Thread();
                require(((Integer) get.invoke(null, pending)) == (getter.contains("Height") ? 67 : 41), "Off-thread fallback " + getter);
                GameWindow.gameThread = Thread.currentThread();
                CustomTexture custom = new CustomTexture();
                require(((Integer) get.invoke(null, custom)) > 0 && custom.calls == 1, "Custom texture virtual getter lost: " + getter);
                try { get.invoke(null, (Object) null); throw new AssertionError("Null texture should retain NPE"); }
                catch (InvocationTargetException expected) { require(expected.getCause() instanceof NullPointerException, "Null failure changed"); }
            }
            System.out.println("WORLD_ITEM_TEXTURE_CHECKS_PASS");
        } finally { GameWindow.gameThread = old; Files.deleteIfExists(png); }
    }
}
