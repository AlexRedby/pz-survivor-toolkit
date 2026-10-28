package net.alexredby.drivingperf;

import java.lang.reflect.InvocationTargetException;
import java.io.StringReader;
import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.PatchEngine;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Deque;
import java.util.Map;
import net.bytebuddy.jar.asm.*;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaThread;

/** Headless checks execute actual transformed native LuaCaller methods with an isolated recorder. */
public final class LuaCallbackHookChecks {
    private static final String CALLER="se.krka.kahlua.integration.LuaCaller";
    private static final String HOOKS="net/alexredby/drivingperf/LuaCallbackHooks";
    private static final String CALLBACKS="net/alexredby/drivingperf/LuaCallbacks";
    private static int enters, exits, serial;
    private static boolean failEnter, failExit;
    private static Object lastCaller, lastFunction;
    private static final Deque<Integer> stack=new ArrayDeque<>();
    private static final AssertionError SENTINEL=new AssertionError("expected original failure");

    public static int receiverEnter(Object caller,Object function) {
        if (failEnter) throw new AssertionError("expected receiver enter failure");
        enters++; lastCaller=caller; lastFunction=function; stack.push(++serial); return serial;
    }
    public static void receiverExit(int token) {
        if (failExit) throw new AssertionError("expected receiver exit failure");
        if (token==0) return;
        check(!stack.isEmpty() && stack.pop()==token,"callback LIFO changed"); exits++;
    }
    private static void check(boolean ok,String reason) { if (!ok) throw new AssertionError(reason); }
    private static byte[] resource(String name) throws Exception {
        try (var input=LuaCallbackHookChecks.class.getClassLoader().getResourceAsStream(name)) {
            if (input==null) throw new AssertionError("missing resource "+name);
            return input.readAllBytes();
        }
    }
    private static byte[] receiver() {
        ClassWriter out=new ClassWriter(ClassWriter.COMPUTE_MAXS);
        out.visit(Opcodes.V17,Opcodes.ACC_PUBLIC,CALLBACKS,null,"java/lang/Object",null);
        MethodVisitor m=out.visitMethod(Opcodes.ACC_PUBLIC|Opcodes.ACC_STATIC,"enter","(Ljava/lang/Object;Ljava/lang/Object;)I",null,null);
        m.visitCode(); m.visitVarInsn(Opcodes.ALOAD,0); m.visitVarInsn(Opcodes.ALOAD,1);
        m.visitMethodInsn(Opcodes.INVOKESTATIC,"net/alexredby/drivingperf/LuaCallbackHookChecks","receiverEnter","(Ljava/lang/Object;Ljava/lang/Object;)I",false);
        m.visitInsn(Opcodes.IRETURN); m.visitMaxs(0,0); m.visitEnd();
        m=out.visitMethod(Opcodes.ACC_PUBLIC|Opcodes.ACC_STATIC,"exit","(I)V",null,null);
        m.visitCode(); m.visitVarInsn(Opcodes.ILOAD,0);
        m.visitMethodInsn(Opcodes.INVOKESTATIC,"net/alexredby/drivingperf/LuaCallbackHookChecks","receiverExit","(I)V",false);
        m.visitInsn(Opcodes.RETURN); m.visitMaxs(0,0); m.visitEnd(); out.visitEnd(); return out.toByteArray();
    }
    private static final class Isolated extends ClassLoader {
        final Map<String,byte[]> definitions;
        Isolated(byte[] caller) throws Exception {
            super(LuaCallbackHookChecks.class.getClassLoader());
            definitions=Map.of(CALLER,caller,HOOKS.replace('/','.'),resource(HOOKS+".class"),
                    CALLBACKS.replace('/','.'),receiver());
        }
        @Override protected synchronized Class<?> loadClass(String name,boolean resolve) throws ClassNotFoundException {
            if (!definitions.containsKey(name)) return super.loadClass(name,resolve);
            Class<?> type=findLoadedClass(name);
            if (type==null) { byte[] bytes=definitions.get(name); type=defineClass(name,bytes,0,bytes.length); }
            if (resolve) resolveClass(type); return type;
        }
    }
    public static final class FakeThread extends KahluaThread {
        static final Object[] RETURNS={Boolean.TRUE,"same-return"};
        boolean throwing;
        Runnable nested;
        FakeThread() { super(new J2SEPlatform(),new J2SEPlatform().newTable()); }
        private void run() { if (throwing) throw SENTINEL; if (nested!=null) { Runnable task=nested; nested=null; task.run(); } }
        @Override public void pcallvoid(Object f,Object a) { run(); }
        @Override public void pcallvoid(Object f,Object a,Object b) { run(); }
        @Override public void pcallvoid(Object f,Object a,Object b,Object c) { run(); }
        @Override public void pcallvoid(Object f,Object[] a) { run(); }
        @Override public Boolean pcallBoolean(Object f,Object a) { run(); return Boolean.TRUE; }
        @Override public Boolean pcallBoolean(Object f,Object a,Object b) { run(); return Boolean.TRUE; }
        @Override public Boolean pcallBoolean(Object f,Object a,Object b,Object c) { run(); return Boolean.TRUE; }
        @Override public Boolean pcallBoolean(Object f,Object[] a) { run(); return Boolean.TRUE; }
        @Override public Object[] pcall(Object f,Object[] a) { run(); return RETURNS; }
    }
    private static Object invoke(java.lang.reflect.Method method,Object caller,Object[] arguments) throws Throwable {
        try { return method.invoke(caller,arguments); }
        catch (InvocationTargetException wrapped) { throw wrapped.getCause(); }
    }
    private static void behavior(byte[] bytes,String label) throws Throwable {
        byte[] woven=LuaCallbackHooks.weave(bytes); check(woven!=null,label+" refused");
        check(LuaCallbackHooks.weave(woven)==null,"duplicate weaving accepted");
        Class<?> type=new Isolated(woven).loadClass(CALLER);
        Object caller=type.getConstructor(KahluaConverterManager.class).newInstance(new KahluaConverterManager());
        FakeThread thread=new FakeThread(); Object function=new Object();
        int methods=0;
        for (var method:type.getDeclaredMethods()) {
            if (!method.getName().startsWith("pcall") && !method.getName().startsWith("protectedCall")) continue;
            Class<?>[] parameters=method.getParameterTypes(); Object[] args=new Object[parameters.length];
            args[0]=thread; args[1]=function;
            for (int i=2;i<args.length;i++) args[i]=parameters[i]==Object[].class ? new Object[]{"argument"} : "argument";
            int before=enters, finished=exits;
            Object result=invoke(method,caller,args);
            check(enters==before+1 && exits==finished+1 && stack.isEmpty(),label+" delegated doublecount/missing exit "+method);
            check(lastCaller==caller && lastFunction==function,"caller/closure argument identity changed");
            if (method.getName().equals("pcall")) check(result==FakeThread.RETURNS,"pcall return identity changed");
            if (method.getReturnType()==Boolean.class) check(result==Boolean.TRUE,"Boolean result changed");
            thread.throwing=true; before=enters; finished=exits;
            try { invoke(method,caller,args); throw new AssertionError("original throwable swallowed"); }
            catch (AssertionError original) { check(original==SENTINEL,"original throwable identity replaced"); }
            finally { thread.throwing=false; }
            check(enters==before+1 && exits==finished+1 && stack.isEmpty(),"throwable callback exit missing");
            methods++;
        }
        check(methods==18,"unexpected LuaCaller method count");
        var one=type.getMethod("pcallvoid",KahluaThread.class,Object.class,Object.class);
        Object inner=new Object();
        thread.nested=() -> {
            try { invoke(one,caller,new Object[]{thread,inner,"argument"}); }
            catch (Throwable failure) { throw new AssertionError(failure); }
        };
        int before=enters;
        invoke(one,caller,new Object[]{thread,function,"argument"});
        check(enters==before+2 && stack.isEmpty(),"Java-to-Lua reentry missing/misnested");
        J2SEPlatform platform=new J2SEPlatform(); var env=platform.newTable();
        KahluaThread actualThread=new KahluaThread(platform,env); actualThread.debugOwnerThread=Thread.currentThread();
        var pcall=type.getMethod("pcall",KahluaThread.class,Object.class,Object[].class);
        for (String source:new String[]{
                "local function inner() return 7 end; local x=inner(); return x",
                "local function tail(n) if n==0 then return 9 end return tail(n-1) end; return tail(3)"}) {
            Object closure=LuaCompiler.loadis(new StringReader(source),"hook-vm.lua",env);
            before=enters; int finished=exits;
            Object[] result=(Object[])invoke(pcall,caller,new Object[]{actualThread,closure,new Object[0]});
            check(result[0]==Boolean.TRUE && enters==before+1 && exits==finished+1 && stack.isEmpty(),
                    "internal direct/tail Lua calls created callback boundaries");
        }
        Object broken=LuaCompiler.loadis(new StringReader("local x=nil; return x.missing"),"hook-error.lua",env);
        PrintStream stdout=System.out,stderr=System.err;
        try (PrintStream quiet=new PrintStream(new ByteArrayOutputStream())) {
            System.setOut(quiet); System.setErr(quiet); before=enters; int finished=exits;
            Object[] result=(Object[])invoke(pcall,caller,new Object[]{actualThread,broken,new Object[0]});
            check(result[0]==Boolean.FALSE && enters==before+1 && exits==finished+1 && stack.isEmpty(),
                    "normal protected Lua error changed callback cleanup/result");
        } finally { System.setOut(stdout); System.setErr(stderr); }
        failEnter=true;
        invoke(one,caller,new Object[]{thread,function,"argument"});
        failEnter=false;
        failExit=true; thread.throwing=true;
        try { invoke(one,caller,new Object[]{thread,function,"argument"}); throw new AssertionError("original failure swallowed by telemetry"); }
        catch (AssertionError original) { check(original==SENTINEL,"telemetry replaced original failure"); }
        finally { failExit=false; thread.throwing=false; stack.clear(); }
        System.out.println("LUA_CALLBACK_HOOK_BEHAVIOR_PASS input="+label+" entrypoints=18 leaves=15");
    }
    private static byte[] mutate(byte[] bytes,String name,boolean addMethod) {
        ClassReader reader=new ClassReader(bytes); ClassWriter out=new ClassWriter(0);
        reader.accept(new ClassVisitor(Opcodes.ASM9,out) {
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                MethodVisitor next=super.visitMethod(a,n,d,s,e);
                if (!n.equals(name)) return next;
                return new MethodVisitor(Opcodes.ASM9,next) {
                    @Override public void visitCode() { super.visitCode(); super.visitInsn(Opcodes.NOP); }
                };
            }
            @Override public void visitEnd() {
                if (addMethod) {
                    MethodVisitor m=super.visitMethod(Opcodes.ACC_PUBLIC,"unexpected","()V",null,null);
                    m.visitCode();m.visitInsn(Opcodes.RETURN);m.visitMaxs(0,1);m.visitEnd();
                }
                super.visitEnd();
            }
        },0); return out.toByteArray();
    }
    private static void installChecks(boolean completion,boolean incompatible) throws Exception {
        var field=Loader.class.getDeclaredField("g_instrumentation"); field.setAccessible(true);
        Instrumentation instrumentation=(Instrumentation)field.get(null);
        check(instrumentation!=null,"install checks require the real ZombieBuddy javaagent and disposable config_dir");
        // For --completion, the classpath must contain only the actual compiled
        // Main$ActionCallbackResult class extracted from the production jar and its receiver stub.
        if (completion) PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches",LuaCallbackHookChecks.class.getClassLoader());
        ClassFileTransformer changed=new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader l,String n,Class<?> c,ProtectionDomain d,byte[] b) {
                return LuaCallbackHooks.TARGET.equals(n) ? mutate(b,"pcallvoid",false) : null;
            }
        };
        if (incompatible) instrumentation.addTransformer(changed,true);
        try {
            if (incompatible) {
                try { LuaCallbackHooks.install(); throw new AssertionError("incompatible live input accepted"); }
                catch (IllegalStateException expected) {
                    check(!LuaCallbackHooks.installed && !LuaCallbackHooks.verified && LuaCallbackHooks.diagnostic!=null,
                            "incompatible install did not fail closed");
                }
                System.out.println("LUA_CALLBACK_HOOK_INSTALL_REJECTION_PASS"); return;
            }
            LuaCallbackHooks.install();
            check(LuaCallbackHooks.installed && LuaCallbackHooks.verified && LuaCallbackHooks.diagnostic==null,"install unverified");
            int[] hooks=new int[2];
            ClassFileTransformer observer=new ClassFileTransformer() {
                @Override public byte[] transform(ClassLoader l,String n,Class<?> c,ProtectionDomain d,byte[] b) {
                    if (!LuaCallbackHooks.TARGET.equals(n)) return null;
                    Arrays.fill(hooks,0);
                    new ClassReader(b).accept(new ClassVisitor(Opcodes.ASM9) {
                        @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                            return new MethodVisitor(Opcodes.ASM9) {
                                @Override public void visitMethodInsn(int o,String owner,String name,String desc,boolean itf) {
                                    if (!HOOKS.equals(owner)) return;
                                    if (name.equals("safeEnter")) hooks[0]++;
                                    if (name.equals("safeExit")) hooks[1]++;
                                }
                            };
                        }
                    },ClassReader.SKIP_DEBUG); return null;
                }
            };
            instrumentation.addTransformer(observer,true);
            try {
                Class<?> caller=Class.forName(CALLER,false,LuaCallbackHookChecks.class.getClassLoader());
                instrumentation.retransformClasses(caller);
                instrumentation.retransformClasses(caller);
                check(LuaCallbackHooks.verified && hooks[0]==15 && hooks[1]==30,"retransform lost/duplicated leaf hooks");
            } finally { instrumentation.removeTransformer(observer); }
            ClassWriter subtype=new ClassWriter(0);
            subtype.visit(Opcodes.V17,Opcodes.ACC_PUBLIC,"toolkit/luahookfixture/FutureLuaCaller",null,LuaCallbackHooks.TARGET,null);
            subtype.visitEnd(); byte[] bytes=subtype.toByteArray();
            class SubclassLoader extends ClassLoader {
                SubclassLoader() { super(LuaCallbackHookChecks.class.getClassLoader()); }
                Class<?> define() { return defineClass("toolkit.luahookfixture.FutureLuaCaller",bytes,0,bytes.length); }
            }
            new SubclassLoader().define();
            check(!LuaCallbackHooks.verified && "unsupported-LuaCaller-subclass".equals(LuaCallbackHooks.diagnostic),
                    "future subclass did not invalidate callback coverage");
            System.out.println("LUA_CALLBACK_HOOK_INSTALL_PASS completion="+completion+" retransforms=2 future_subclass_invalidates=true");
        } finally {
            LuaCallbackHooks.remove();
            if (incompatible) instrumentation.removeTransformer(changed);
            check(!LuaCallbackHooks.installed,"remove retained installed state");
        }
    }
    public static void main(String[] args) throws Throwable {
        if (args.length>0 && args[0].equals("--install")) {
            var options=java.util.List.of(args);
            installChecks(options.contains("--completion"),options.contains("--incompatible")); return;
        }
        byte[] nativeBytes=resource(LuaCallbackHooks.TARGET+".class");
        LuaCallbackHooks.prepare();
        check(LuaCallbackHooks.admitted(nativeBytes),"native input rejected");
        // Re-emitting with an independent constant pool must preserve canonical admission.
        ClassWriter reordered=new ClassWriter(0); new ClassReader(nativeBytes).accept(reordered,ClassReader.SKIP_DEBUG);
        check(LuaCallbackHooks.admitted(reordered.toByteArray()),"constant-pool/debug canonicalization rejected");
        check(!LuaCallbackHooks.admitted(mutate(nativeBytes,"pcallvoid",false)),"changed leaf accepted");
        check(!LuaCallbackHooks.admitted(mutate(nativeBytes,"protectedCall",false)),"changed delegator accepted");
        check(!LuaCallbackHooks.admitted(mutate(nativeBytes,"not-a-method",true)),"extra method accepted");
        behavior(nativeBytes,"native");
        if (args.length!=0) {
            byte[] overlay=Files.readAllBytes(Path.of(args[0]));
            check(LuaCallbackHooks.admitted(overlay),"current production completion advice rejected");
            behavior(overlay,"actual-compiled-completion-advice");
        }
        System.out.println("LUA_CALLBACK_HOOK_CHECKS_PASS");
    }
}
