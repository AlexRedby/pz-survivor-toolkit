package net.alexredby.drivingperf;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.MessageDigest;
import java.security.ProtectionDomain;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.*;

/** Test-only engine-to-Lua boundaries. No VM opcode, argument or return-value changes. */
public final class LuaCallbackHooks {
    static final String TARGET="se/krka/kahlua/integration/LuaCaller";
    static final String OWNER="net/alexredby/drivingperf/LuaCallbackHooks";
    static final String NATIVE="0443930027e8f312ae9cb192c628f4b6c10743204597c508f8693cfd7bd79d0b";
    private static final String PREFIX="(Lse/krka/kahlua/vm/KahluaThread;Ljava/lang/Object;";
    private static final String OBJECT="Ljava/lang/Object;", ARRAY="[Ljava/lang/Object;";
    private static final String BOOLEAN="Ljava/lang/Boolean;";
    private static final String PCALL_ARRAY="pcall"+PREFIX+ARRAY+")[Ljava/lang/Object;";
    private static final String PCALL_SCALAR="pcall"+PREFIX+OBJECT+")[Ljava/lang/Object;";
    // Actual current Main$ActionCallbackResult advice from the compiled production patch jar,
    // applied by ZombieBuddy 2.3.4 to both pcall overloads. No other overlay is admitted.
    private static final Map<String,String> COMPLETION=Map.of(
            PCALL_ARRAY,"3d0bd42b2b0ca4f87a1ffa4d8c782d9f301a965e8adb153256936fe6ae9cdc88",
            PCALL_SCALAR,"fa45c30285da80a8ee12c6bb69ebef5df1da57da146beb9b75dabdf9cd890914");
    private static final Map<String,Boolean> LEAVES=leaves();
    static volatile String diagnostic;
    static volatile boolean installed, verified;
    private static Instrumentation instrumentation;
    private static ClassFileTransformer transformer;
    private static Map<String,String> nativeMethods;
    private static String nativeShape;
    private static Class<?> targetClass;

    private LuaCallbackHooks() {}

    private static Map<String,Boolean> leaves() {
        Map<String,Boolean> result=new LinkedHashMap<>();
        for (int n=1;n<=3;n++) {
            result.put("pcallvoid"+PREFIX+OBJECT.repeat(n)+")V",true);
            result.put("protectedCallVoid"+PREFIX+OBJECT.repeat(n)+")V",true);
            result.put("protectedCallBoolean"+PREFIX+OBJECT.repeat(n)+")"+BOOLEAN,true);
        }
        for (int n=2;n<=3;n++) result.put("pcallBoolean"+PREFIX+OBJECT.repeat(n)+")"+BOOLEAN,true);
        result.put("pcallvoid"+PREFIX+ARRAY+")V",true);
        result.put("pcallBoolean"+PREFIX+ARRAY+")"+BOOLEAN,true);
        result.put(PCALL_ARRAY,true); result.put(PCALL_SCALAR,true);
        return Map.copyOf(result);
    }

    static String digest(byte[] data) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
    }

    /** Read the resource only as the pinned reference, never as proof of transformed memory. */
    static synchronized void prepare() throws Exception {
        if (nativeMethods!=null) return;
        byte[] original;
        try (var input=LuaCallbackHooks.class.getClassLoader().getResourceAsStream(TARGET+".class")) {
            if (input==null) throw new IllegalStateException("Lua callback native resource missing");
            original=input.readAllBytes();
        }
        if (!NATIVE.equals(digest(original))) throw new IllegalStateException("Lua callback native resource mismatch");
        Map<String,String> methods=boundaries(original);
        if (LEAVES.size()!=15 || methods.size()!=19 || !methods.keySet().containsAll(LEAVES.keySet()))
            throw new IllegalStateException("Lua callback native method shape mismatch");
        nativeShape=shape(original); nativeMethods=Map.copyOf(methods);
    }

    static synchronized void install() throws Exception {
        if (installed || diagnostic!=null) throw new IllegalStateException("Lua callback hooks cannot be restarted");
        try {
            prepare();
            instrumentation=Accessor.tryGet(Loader.class,"g_instrumentation",null);
            if (instrumentation==null || !instrumentation.isRetransformClassesSupported())
                throw new IllegalStateException("Lua callbacks require ZombieBuddy retransformation");
            targetClass=Class.forName(TARGET.replace('/','.'),false,LuaCallbackHooks.class.getClassLoader());
            if (!instrumentation.isModifiableClass(targetClass))
                throw new IllegalStateException("LuaCaller is not modifiable");
            transformer=new ClassFileTransformer() {
                @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,
                        ProtectionDomain domain,byte[] bytes) {
                    try {
                        if (TARGET.equals(name)) {
                            if (loader!=targetClass.getClassLoader() || type!=null && type!=targetClass) {
                                fail("unsupported-LuaCaller-classloader"); return null;
                            }
                            byte[] result=weave(bytes);
                            if (result==null) fail("LuaCaller-transformed-input-mismatch");
                            else if (diagnostic==null) verified=true;
                            return result;
                        }
                        // Registration precedes the loaded-subclass scan. A future direct subclass
                        // invalidates coverage even though instrumentation never blocks its loading.
                        if (bytes!=null && TARGET.equals(new ClassReader(bytes).getSuperName()))
                            fail("unsupported-LuaCaller-subclass");
                    } catch (Throwable failure) { fail("LuaCaller-transform-failure"); }
                    return null;
                }
            };
            instrumentation.addTransformer(transformer,true); installed=true;
            for (Class<?> type:instrumentation.getAllLoadedClasses()) {
                if (type!=targetClass && (type.getName().equals(TARGET.replace('/','.'))
                        || targetClass.isAssignableFrom(type))) {
                    fail("unsupported-loaded-LuaCaller-subclass-or-loader");
                    throw new IllegalStateException(diagnostic);
                }
            }
            instrumentation.retransformClasses(targetClass);
            if (!verified || diagnostic!=null) throw new IllegalStateException("Unverified Lua callback hooks: "+diagnostic);
        } catch (Exception | Error failure) {
            if (diagnostic==null) fail("LuaCaller-install-failure");
            remove(); throw failure;
        }
    }

    /** Leaves successful verification visible to finish/reporting. Already woven calls are inert at the receiver. */
    static synchronized void remove() {
        if (instrumentation!=null && transformer!=null) instrumentation.removeTransformer(transformer);
        transformer=null; installed=false;
    }

    private static void fail(String reason) { verified=false; if (diagnostic==null) diagnostic=reason; }

    /** Defensive adapters ensure a telemetry failure cannot replace a game return or throwable. */
    public static int safeEnter(Object caller,Object function) {
        try { return LuaCallbacks.enter(caller,function); }
        catch (Throwable failure) { fail("LuaCaller-callback-enter-failure"); return 0; }
    }
    public static void safeExit(int token) {
        try { LuaCallbacks.exit(token); }
        catch (Throwable failure) { fail("LuaCaller-callback-exit-failure"); }
    }

    /** Independent method writers remove constant-pool ordering, debug tables and stack-map differences. */
    static Map<String,String> boundaries(byte[] bytes) throws Exception {
        Map<String,String> result=new HashMap<>();
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                ClassWriter output=new ClassWriter(0);
                output.visit(Opcodes.V17,Opcodes.ACC_PUBLIC,TARGET,null,"java/lang/Object",null);
                return new MethodVisitor(Opcodes.ASM9,output.visitMethod(access,name,desc,signature,exceptions)) {
                    @Override public void visitEnd() {
                        super.visitEnd(); output.visitEnd();
                        try {
                            if (result.put(name+desc,digest(output.toByteArray()))!=null)
                                throw new IllegalArgumentException("Duplicate LuaCaller method");
                        } catch (Exception failure) { throw new IllegalArgumentException(failure); }
                    }
                };
            }
        },ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        return result;
    }

    /** Preserve admission of the class header and fields as well as every method, including delegators. */
    private static String shape(byte[] bytes) throws Exception {
        ClassWriter output=new ClassWriter(0);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9,output) {
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) { return null; }
        },ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        return digest(output.toByteArray());
    }

    static boolean admitted(byte[] bytes) throws Exception {
        prepare();
        if (!nativeShape.equals(shape(bytes))) return false;
        Map<String,String> actual=boundaries(bytes);
        if (!actual.keySet().equals(nativeMethods.keySet())) return false;
        boolean nativePair=true, completionPair=true;
        for (var expected:nativeMethods.entrySet()) {
            String key=expected.getKey(), observed=actual.get(key);
            if (COMPLETION.containsKey(key)) {
                nativePair &= expected.getValue().equals(observed);
                completionPair &= COMPLETION.get(key).equals(observed);
            } else if (!expected.getValue().equals(observed)) return false;
        }
        return nativePair || completionPair;
    }

    static byte[] weave(byte[] bytes) {
        try {
            if (bytes==null || !admitted(bytes)) return null;
            Map<String,Integer> locals=new HashMap<>();
            ClassReader reader=new ClassReader(bytes);
            reader.accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                    String key=name+desc;
                    if (!LEAVES.containsKey(key)) return null;
                    if ((access & (Opcodes.ACC_STATIC | Opcodes.ACC_ABSTRACT | Opcodes.ACC_NATIVE))!=0)
                        throw new IllegalArgumentException("Non-instance Lua callback leaf");
                    return new MethodVisitor(Opcodes.ASM9) {
                        @Override public void visitMaxs(int stack,int count) { locals.put(key,count); }
                    };
                }
            },ClassReader.SKIP_DEBUG);
            if (locals.size()!=15) return null;
            ClassWriter output=new ClassWriter(reader,ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
            int[] methods={0};
            reader.accept(new ClassVisitor(Opcodes.ASM9,output) {
                @Override public MethodVisitor visitMethod(int access,String name,String desc,String signature,String[] exceptions) {
                    MethodVisitor next=super.visitMethod(access,name,desc,signature,exceptions);
                    String key=name+desc;
                    if (!LEAVES.containsKey(key)) return next;
                    methods[0]++;
                    int token=locals.get(key), thrown=token+1;
                    return new MethodVisitor(Opcodes.ASM9,next) {
                        final Label start=new Label(),end=new Label(),handler=new Label();
                        void close() {
                            super.visitVarInsn(Opcodes.ILOAD,token);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,OWNER,"safeExit","(I)V",false);
                        }
                        @Override public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(Opcodes.ALOAD,0); super.visitVarInsn(Opcodes.ALOAD,2);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,OWNER,"safeEnter","(Ljava/lang/Object;Ljava/lang/Object;)I",false);
                            super.visitVarInsn(Opcodes.ISTORE,token); super.visitLabel(start);
                        }
                        @Override public void visitInsn(int opcode) {
                            if (opcode>=Opcodes.IRETURN && opcode<=Opcodes.RETURN) close();
                            super.visitInsn(opcode);
                        }
                        @Override public void visitMaxs(int stack,int count) {
                            super.visitLabel(end); super.visitLabel(handler);
                            // Appended last so native catch handlers keep their original precedence.
                            super.visitTryCatchBlock(start,end,handler,"java/lang/Throwable");
                            super.visitVarInsn(Opcodes.ASTORE,thrown); close();
                            super.visitVarInsn(Opcodes.ALOAD,thrown); super.visitInsn(Opcodes.ATHROW);
                            super.visitMaxs(0,0);
                        }
                    };
                }
            },ClassReader.SKIP_FRAMES);
            return methods[0]==15 ? output.toByteArray() : null;
        } catch (Throwable invalid) { return null; }
    }
}
