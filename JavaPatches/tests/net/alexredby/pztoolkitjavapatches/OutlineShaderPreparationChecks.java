package net.alexredby.pztoolkitjavapatches;

import java.io.InputStream;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.Label;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;

/** Run the native, runtime-extracted factory block and the preparation against the same fixtures. */
public final class OutlineShaderPreparationChecks {
    private static final String ROOT = "net/alexredby/pztoolkitjavapatches/";
    private static final String HELPER = ROOT + "OutlineShaderPreparation";
    private static final String CHECK = ROOT + "OutlineShaderPreparationChecks";
    private static final String OUTLINES = "zombie/core/skinnedmodel/model/ModelOutlines";
    private static final String PROGRAM = "zombie/core/opengl/ShaderProgram";
    private static final String THREAD = "zombie/core/opengl/RenderThread";
    private static final String[] FIELDS = {"thickenHShader", "thickenVShader", "blitShader"};
    private static final List<String> calls = new ArrayList<>();
    private static final List<Object> destroyed = new ArrayList<>();
    private static boolean context;
    private static int failAt, throwAt, invokes;
    private static Runnable reentry;
    private static int generated;

    public static Object create(Class<?> type, String name, boolean fixed, boolean instanced, boolean compile) throws Exception {
        require(context, "Shader creation escaped the render context");
        calls.add(name + ":" + fixed + ":" + instanced + ":" + compile);
        if (reentry != null) { Runnable pending = reentry; reentry = null; pending.run(); }
        if (calls.size() == throwAt) throw new IllegalStateException("fixture factory failure");
        Object result = type.getConstructor().newInstance();
        type.getField("compiled").setBoolean(result, calls.size() != failAt);
        return result;
    }

    public static void destroy(Object value) {
        require(context, "Shader cleanup escaped the render context");
        destroyed.add(value);
    }

    public static void onContext(Runnable task) {
        invokes++;
        boolean prior = context;
        context = true;
        try { task.run(); } finally { context = prior; }
    }

    private static byte[] resource(String name) throws Exception {
        try (InputStream in = OutlineShaderPreparationChecks.class.getClassLoader().getResourceAsStream(name + ".class")) {
            require(in != null, "Missing resource " + name);
            return in.readAllBytes();
        }
    }

    private static ClassWriter fixture(String name) {
        ClassWriter w = new ClassWriter(ClassWriter.COMPUTE_MAXS | ClassWriter.COMPUTE_FRAMES);
        w.visit(Opcodes.V17, Opcodes.ACC_PUBLIC, name, null, "java/lang/Object", null);
        MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0);
        m.visitMethodInsn(Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false);
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(0, 0); m.visitEnd();
        return w;
    }

    private static byte[] program() {
        ClassWriter w = fixture(PROGRAM);
        w.visitField(Opcodes.ACC_PUBLIC, "compiled", "Z", null, null).visitEnd();
        MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "createShaderProgram",
                "(Ljava/lang/String;ZZZ)L" + PROGRAM + ";", null, null);
        m.visitCode(); m.visitLdcInsn(net.bytebuddy.jar.asm.Type.getObjectType(PROGRAM));
        for (int i = 0; i < 4; i++) m.visitVarInsn(i == 0 ? Opcodes.ALOAD : Opcodes.ILOAD, i);
        m.visitMethodInsn(Opcodes.INVOKESTATIC, CHECK, "create", "(Ljava/lang/Class;Ljava/lang/String;ZZZ)Ljava/lang/Object;", false);
        m.visitTypeInsn(Opcodes.CHECKCAST, PROGRAM); m.visitInsn(Opcodes.ARETURN); m.visitMaxs(0, 0); m.visitEnd();
        m = w.visitMethod(Opcodes.ACC_PUBLIC, "isCompiled", "()Z", null, null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0); m.visitFieldInsn(Opcodes.GETFIELD, PROGRAM, "compiled", "Z");
        m.visitInsn(Opcodes.IRETURN); m.visitMaxs(0, 0); m.visitEnd();
        m = w.visitMethod(Opcodes.ACC_PUBLIC, "destroy", "()V", null, null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0);
        m.visitMethodInsn(Opcodes.INVOKESTATIC, CHECK, "destroy", "(Ljava/lang/Object;)V", false);
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(0, 0); m.visitEnd(); w.visitEnd(); return w.toByteArray();
    }

    private static byte[] outlines() {
        ClassWriter w = fixture(OUTLINES);
        for (String field : FIELDS) w.visitField(Opcodes.ACC_PUBLIC, field, "L" + PROGRAM + ";", null, null).visitEnd();
        w.visitField(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "instance", "L" + OUTLINES + ";", null, null).visitEnd();
        MethodVisitor m = w.visitMethod(Opcodes.ACC_STATIC, "<clinit>", "()V", null, null);
        m.visitCode(); m.visitTypeInsn(Opcodes.NEW, OUTLINES); m.visitInsn(Opcodes.DUP);
        m.visitMethodInsn(Opcodes.INVOKESPECIAL, OUTLINES, "<init>", "()V", false);
        m.visitFieldInsn(Opcodes.PUTSTATIC, OUTLINES, "instance", "L" + OUTLINES + ";");
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(0, 0); m.visitEnd(); w.visitEnd(); return w.toByteArray();
    }

    private static byte[] thread() {
        ClassWriter w = fixture(THREAD);
        MethodVisitor m = w.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "invokeOnRenderContext", "(Ljava/lang/Runnable;)V", null, null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD, 0);
        m.visitMethodInsn(Opcodes.INVOKESTATIC, CHECK, "onContext", "(Ljava/lang/Runnable;)V", false);
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(0, 0); m.visitEnd(); w.visitEnd(); return w.toByteArray();
    }

    private static final class FixtureLoader extends ClassLoader {
        FixtureLoader() { super(OutlineShaderPreparationChecks.class.getClassLoader()); }
        @Override protected synchronized Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
            String internal = name.replace('.', '/');
            if (!List.of(HELPER, PROGRAM, OUTLINES, THREAD).contains(internal)) return super.loadClass(name, resolve);
            Class<?> result = findLoadedClass(name);
            if (result == null) {
                try {
                    byte[] bytes = internal.equals(PROGRAM) ? program() : internal.equals(OUTLINES) ? outlines()
                            : internal.equals(THREAD) ? thread() : resource(internal);
                    result = defineClass(name, bytes, 0, bytes.length);
                } catch (Exception error) { throw new ClassNotFoundException(name, error); }
            }
            if (resolve) resolveClass(result);
            return result;
        }
        Class<?> define(String name, byte[] bytes) { return defineClass(name.replace('/', '.'), bytes, 0, bytes.length); }
    }

    /** Keep the original instructions from the sentinel read through the common continuation. */
    private static Method nativeInitialization(FixtureLoader loader) throws Exception {
        String name = ROOT + "ExtractedOutlineInitialization" + generated++;
        ClassWriter w = fixture(name);
        MethodVisitor output = w.visitMethod(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC, "initialize", "(L" + OUTLINES + ";)V", null, null);
        output.visitCode();
        int[] fields = {0}, factories = {0};
        boolean[] found = {false};
        new ClassReader(resource(OUTLINES)).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                if (!n.equals("endFrame") || !d.equals("(I)V")) return null;
                return new MethodVisitor(Opcodes.ASM9) {
                    boolean recording, finished;
                    Label continuation;
                    @Override public void visitFieldInsn(int op, String owner, String field, String desc) {
                        if (!finished && !recording && op == Opcodes.GETFIELD && owner.equals(OUTLINES) && field.equals(FIELDS[0])) {
                            recording = true; found[0] = true; output.visitVarInsn(Opcodes.ALOAD, 0);
                        }
                        if (!recording) return;
                        if (op == Opcodes.PUTFIELD) fields[0]++;
                        output.visitFieldInsn(op, owner, field, desc);
                    }
                    @Override public void visitVarInsn(int op, int variable) { if (recording) output.visitVarInsn(op, variable); }
                    @Override public void visitInsn(int op) { if (recording) output.visitInsn(op); }
                    @Override public void visitLdcInsn(Object value) { if (recording) output.visitLdcInsn(value); }
                    @Override public void visitJumpInsn(int op, Label label) {
                        if (!recording) return;
                        require(continuation == null && op == Opcodes.IFNONNULL, "Unexpected native shader branch");
                        continuation = label; output.visitJumpInsn(op, label);
                    }
                    @Override public void visitMethodInsn(int op, String owner, String method, String desc, boolean itf) {
                        if (!recording) return;
                        require(op == Opcodes.INVOKESTATIC && owner.equals(PROGRAM) && method.equals("createShaderProgram"), "Unexpected native shader call");
                        factories[0]++; output.visitMethodInsn(op, owner, method, desc, itf);
                    }
                    @Override public void visitLabel(Label label) {
                        if (recording && label == continuation) {
                            output.visitLabel(label); recording = false; finished = true;
                        }
                    }
                };
            }
        }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        require(found[0] && factories[0] == 3 && fields[0] == 3, "Native shader initialization boundary changed");
        output.visitInsn(Opcodes.RETURN); output.visitMaxs(0, 0); output.visitEnd(); w.visitEnd();
        return loader.define(name, w.toByteArray()).getMethod("initialize", loader.loadClass(OUTLINES.replace('/', '.')));
    }

    private static Object[] cached(Object outlines) throws Exception {
        Object[] result = new Object[3];
        for (int i = 0; i < result.length; i++) result[i] = outlines.getClass().getField(FIELDS[i]).get(outlines);
        return result;
    }

    private static FixtureLoader fresh() {
        calls.clear(); destroyed.clear(); failAt = throwAt = invokes = 0; reentry = null; context = false;
        return new FixtureLoader();
    }

    private static Method preparation(FixtureLoader loader) throws Exception {
        Class<?> type = loader.loadClass(HELPER.replace('/', '.'));
        require(type.getField("SUPPORTED").getBoolean(null), "Native shader resources are not admitted");
        return type.getMethod("prepareAfterLoad");
    }

    private static Object singleton(FixtureLoader loader) throws Exception {
        return loader.loadClass(OUTLINES.replace('/', '.')).getField("instance").get(null);
    }

    private static void invoke(Method method) {
        try { method.invoke(null); } catch (Exception error) { throw new AssertionError(error); }
    }

    private static void require(boolean condition, String message) { if (!condition) throw new AssertionError(message); }

    private static void lifecycleBoundary() throws Exception {
        int[] returns = {0};
        new ClassReader(resource("zombie/gameStates/IngameState")).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                if (!n.equals("enter") || !d.equals("()V")) return null;
                return new MethodVisitor(Opcodes.ASM9) {
                    String event;
                    boolean started, loaded;
                    @Override public void visitLdcInsn(Object value) { event = value instanceof String text ? text : null; }
                    @Override public void visitMethodInsn(int op, String owner, String method, String desc, boolean itf) {
                        require(!owner.equals("zombie/iso/IsoWorld") || !method.equals("render"), "World rendering moved into the load entry");
                        if (owner.equals("zombie/Lua/LuaEventManager") && method.equals("triggerEvent")) {
                            if ("OnGameStart".equals(event)) started = true;
                            if ("OnLoad".equals(event)) loaded = true;
                        }
                    }
                    @Override public void visitInsn(int op) {
                        if (op == Opcodes.RETURN) {
                            returns[0]++;
                            require(started && loaded, "Normal load completion precedes native ready events");
                        }
                    }
                };
            }
        }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        require(returns[0] == 1, "Native load completion boundary changed");
    }

    public static void main(String[] args) throws Exception {
        lifecycleBoundary();
        FixtureLoader nativeLoader = fresh();
        Method nativeBlock = nativeInitialization(nativeLoader);
        onContext(() -> { try { nativeBlock.invoke(null, singleton(nativeLoader)); } catch (Exception e) { throw new AssertionError(e); } });
        List<String> nativeCalls = List.copyOf(calls);
        require(nativeCalls.equals(List.of("aim_outline_h:false:false:true", "aim_outline_v:false:false:true", "aim_outline_blit:false:false:true")), "Unexpected native shader requests");

        FixtureLoader loader = fresh(); Method prepare = preparation(loader); Object outlines = singleton(loader);
        Method firstPreparation = prepare;
        reentry = () -> invoke(firstPreparation);
        invoke(prepare);
        require(calls.equals(nativeCalls) && invokes == 2 && destroyed.isEmpty(), "Preparation differs from the native factories or reentered");
        Object[] first = cached(outlines);
        for (Object program : first) require(program != null, "Incomplete shader publication");
        invoke(prepare);
        require(calls.equals(nativeCalls) && java.util.Arrays.equals(first, cached(outlines)), "Repeat load replaced cached programs");
        Method after = nativeInitialization(loader);
        Object firstOutlines = outlines;
        onContext(() -> { try { after.invoke(null, firstOutlines); } catch (Exception e) { throw new AssertionError(e); } });
        require(calls.equals(nativeCalls), "First outline still compiles composite programs");

        for (String field : FIELDS) {
            loader = fresh(); prepare = preparation(loader); outlines = singleton(loader);
            Object existing = loader.loadClass(PROGRAM.replace('/', '.')).getConstructor().newInstance();
            outlines.getClass().getField(field).set(outlines, existing);
            invoke(prepare);
            require(calls.isEmpty() && destroyed.isEmpty() && outlines.getClass().getField(field).get(outlines) == existing, "Preparation replaced an existing cache");
        }
        for (int failure = 1; failure <= 3; failure++) {
            loader = fresh(); prepare = preparation(loader); outlines = singleton(loader); failAt = failure;
            invoke(prepare);
            for (Object value : cached(outlines)) require(value == null, "Failed preparation published a shader");
            require(calls.size() == failure && destroyed.size() == failure, "Failed preparation leaked returned shaders");
            invoke(prepare);
            require(calls.size() == failure, "Failed preparation retried during a later load");
            failAt = 0;
            Method fallback = nativeInitialization(loader); Object target = outlines;
            onContext(() -> { try { fallback.invoke(null, target); } catch (Exception e) { throw new AssertionError(e); } });
            require(calls.subList(failure, calls.size()).equals(nativeCalls), "Failed preparation disabled native initialization");
        }
        loader = fresh(); prepare = preparation(loader); outlines = singleton(loader); throwAt = 2;
        invoke(prepare);
        require(destroyed.size() == 1, "Factory exception leaked an earlier shader");
        for (Object value : cached(outlines)) require(value == null, "Factory exception published a partial cache");
        System.out.println("OUTLINE_SHADER_PREPARATION_CHECKS_PASS");
    }
}
