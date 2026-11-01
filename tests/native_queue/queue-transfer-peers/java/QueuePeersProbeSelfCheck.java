package net.alexredby.queuepeersprobe;

import java.util.HashMap;
import java.util.List;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;

/** Offline gate/transform verification. Does not start native game state. */
public final class QueuePeersProbeSelfCheck {
    private static java.lang.instrument.Instrumentation instrumentation;
    public static void premain(String arguments,java.lang.instrument.Instrumentation value) {
        instrumentation=value;
    }
    private static byte[] resource(String name) throws Exception {
        try (var input=Main.class.getClassLoader().getResourceAsStream(name+".class")) {
            if (input==null) throw new AssertionError("missing "+name);
            return input.readAllBytes();
        }
    }
    private static void check(boolean condition,String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] ignored) throws Exception {
        check(Main.sourceSupported(),"exact supported native source required");
        // Inert marker data tests the shape guard only, never native packet receipt.
        Object actor=new Object(), otherActor=new Object(), entry=new Object(), otherEntry=new Object();
        java.util.function.Predicate<Object> exactEntry=value->value==entry;
        check(Main.replyPayloadMatches(actor,actor,List.of(entry),exactEntry),"matching singleton payload");
        check(!Main.replyPayloadMatches(actor,otherActor,List.of(entry),exactEntry),"foreign actor payload");
        check(!Main.replyPayloadMatches(null,null,List.of(entry),exactEntry),"missing actor payload");
        check(!Main.replyPayloadMatches(actor,actor,null,exactEntry),"missing entries payload");
        check(!Main.replyPayloadMatches(actor,actor,List.of(),exactEntry),"empty entries payload");
        check(!Main.replyPayloadMatches(actor,actor,List.of(entry,otherEntry),exactEntry),"batch payload");
        check(!Main.replyPayloadMatches(actor,actor,List.of(otherEntry),exactEntry),"wrong item or containers");
        System.out.println("PASS reply payload guard rejects foreign actor, missing/empty/batch/wrong entry");
        var calls=new HashMap<String,Integer>();
        for (String name:List.of("zombie/core/TransactionManager","zombie/core/Transaction",
                "zombie/network/packets/ItemTransactionPacket")) {
            byte[] original=resource(name);
            byte[] woven=Main.weave(name,original,Main.class.getClassLoader());
            check(!java.util.Arrays.equals(original,woven),"target unchanged "+name);
            // ASM parses the complete generated output, including method frames.
            new ClassReader(woven).accept(new ClassVisitor(Opcodes.ASM9) {
                @Override public MethodVisitor visitMethod(int access,String method,String descriptor,
                        String signature,String[] exceptions) {
                    return new MethodVisitor(Opcodes.ASM9) {
                        @Override public void visitMethodInsn(int opcode,String owner,String target,String desc,boolean itf) {
                            if (owner.equals("net/alexredby/queuepeersprobe/Main"))
                                calls.merge(method+":"+target,1,Integer::sum);
                        }
                    };
                }
            },0);
        }
        check(calls.getOrDefault("createItemTransaction:begin",0)==1,"one request entry");
        check(calls.getOrDefault("createItemTransaction:end",0)==1,"one request exit including throw path");
        check(calls.getOrDefault("set:allocated",0)==1,"one allocation hook");
        check(calls.getOrDefault("add:added",0)==1,"one add hook");
        check(calls.getOrDefault("processClient:drop",0)==1,"one receive gate");
        check(calls.size()==5,"unexpected injection "+calls);
        boolean rejected=false;
        try { Main.weave("zombie/core/TransactionManager",resource("zombie/core/Transaction"),Main.class.getClassLoader()); }
        catch (RuntimeException expected) { rejected=true; }
        check(rejected,"wrong target descriptors accepted");
        if (instrumentation!=null) {
            var names=List.of("zombie/core/TransactionManager","zombie/core/Transaction",
                    "zombie/network/packets/ItemTransactionPacket");
            var loaded=new java.util.ArrayList<Class<?>>();
            for (String name:names) loaded.add(Class.forName(name.replace('/','.'),false,Main.class.getClassLoader()));
            java.lang.instrument.ClassFileTransformer transformer=new java.lang.instrument.ClassFileTransformer() {
                @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,
                        java.security.ProtectionDomain domain,byte[] bytes) {
                    return names.contains(name) ? Main.weave(name,bytes,loader) : null;
                }
            };
            instrumentation.addTransformer(transformer,true);
            try {
                instrumentation.retransformClasses(loaded.toArray(Class<?>[]::new));
                for (Class<?> type:loaded) type.getDeclaredMethods();
            } finally { instrumentation.removeTransformer(transformer); }
            System.out.println("PASS isolated JVM retransformation verification (no native state initialization)");
        }
        System.out.println("PASS exact native source hashes, descriptors, request/allocation/add/receive transformations");
    }
}
