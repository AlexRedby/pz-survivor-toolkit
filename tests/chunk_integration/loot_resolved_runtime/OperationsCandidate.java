package toolkit.lootresolved.bootstrap;

import java.util.*;
import net.bytebuddy.jar.asm.*;

/** Operations-only postpass; the reviewed ResolvedCandidate generator remains unchanged. */
final class OperationsCandidate {
    static final String FACTORY="zombie/inventory/InventoryItemFactory", SPAWNER="zombie/inventory/ItemSpawner";
    static final Set<String> CALLBACKS=Set.of("zombie/scripting/logic/ItemCodeOnCreate","zombie/inventory/types/Clothing",
        "se/krka/kahlua/integration/expose/LuaJavaInvoker","se/krka/kahlua/integration/expose/MultiLuaJavaInvoker",
        "se/krka/kahlua/integration/expose/caller/MethodCaller");
    private static final String SCOPE="toolkit/lootresolved/bootstrap/OperationsScope", INV="Lzombie/inventory/InventoryItem;";
    static byte[] picker(byte[] nativeBytes) throws Exception {
        byte[] candidate=ResolvedCandidate.transform(nativeBytes,true);
        ClassReader reader=new ClassReader(candidate);
        ClassWriter writer=new ClassWriter(reader,ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);
        int[] changed={0};
        reader.accept(new ClassVisitor(Opcodes.ASM9,writer) {
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                if (!n.equals("pztest$resolvedOrNative")) return super.visitMethod(a,n,d,s,e);
                if (!d.equals(ResolvedCandidate.RESOLVED)) throw new IllegalStateException("operations-helper-descriptor");
                changed[0]++;
                MethodVisitor mv=super.visitMethod(a,n,d,s,e); mv.visitCode();
                Label stock=new Label();
                mv.visitMethodInsn(Opcodes.INVOKESTATIC,SCOPE,"resolved","()Z",false);
                mv.visitJumpInsn(Opcodes.IFEQ,stock);
                mv.visitVarInsn(Opcodes.ALOAD,5); mv.visitJumpInsn(Opcodes.IFNULL,stock);
                ResolvedCandidate.loadChance(mv); mv.visitVarInsn(Opcodes.ALOAD,5);
                mv.visitMethodInsn(Opcodes.INVOKESTATIC,ResolvedCandidate.OWNER,"pztest$getActualSpawnChance",ResolvedCandidate.RESOLVED,false);
                mv.visitInsn(Opcodes.FRETURN); mv.visitLabel(stock); ResolvedCandidate.loadChance(mv);
                mv.visitMethodInsn(Opcodes.INVOKESTATIC,ResolvedCandidate.OWNER,"getActualSpawnChance",ResolvedCandidate.CHANCE,false);
                mv.visitInsn(Opcodes.FRETURN); mv.visitMaxs(0,0); mv.visitEnd();
                return null; // Replace only this generated helper, not its native sources.
            }
        },ClassReader.EXPAND_FRAMES);
        if (changed[0]!=1) throw new IllegalStateException("operations-helper-count");
        return writer.toByteArray();
    }
    static byte[] observer(byte[] bytes,String owner) {
        ClassReader reader=new ClassReader(bytes);
        ClassWriter writer=new ClassWriter(reader,ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);
        boolean factory=owner.equals(FACTORY);
        if (!factory && !owner.equals(SPAWNER)) throw new IllegalArgumentException("operations-observer-owner");
        String name=factory?"createItemInternal":"inc", desc=factory?"(Ljava/lang/String;FZZ)"+INV:"("+INV+"I)V";
        int[] methods={0}, returns={0};
        reader.accept(new ClassVisitor(Opcodes.ASM9,writer) {
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                MethodVisitor base=super.visitMethod(a,n,d,s,e);
                if (!n.equals(name) || !d.equals(desc)) return base;
                methods[0]++;
                return new MethodVisitor(Opcodes.ASM9,base) {
                    final Label start=new Label(),end=new Label(),handler=new Label();
                    @Override public void visitCode() { super.visitCode(); super.visitLabel(start); }
                    @Override public void visitInsn(int op) {
                        if (factory && op==Opcodes.ARETURN) {
                            returns[0]++; super.visitInsn(Opcodes.DUP);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,SCOPE,"factoryReturned","("+INV+")V",false);
                        } else if (!factory && op==Opcodes.RETURN) {
                            returns[0]++; super.visitVarInsn(Opcodes.ALOAD,0); super.visitVarInsn(Opcodes.ILOAD,1);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,SCOPE,"incremented","("+INV+"I)V",false);
                        }
                        super.visitInsn(op);
                    }
                    @Override public void visitMaxs(int stack,int locals) {
                        super.visitLabel(end); super.visitTryCatchBlock(start,end,handler,"java/lang/Throwable");
                        super.visitLabel(handler); super.visitInsn(Opcodes.DUP);
                        super.visitMethodInsn(Opcodes.INVOKESTATIC,SCOPE,"failed","(Ljava/lang/Throwable;)V",false);
                        super.visitInsn(Opcodes.ATHROW); super.visitMaxs(stack,locals);
                    }
                };
            }
        },ClassReader.EXPAND_FRAMES);
        if (methods[0]!=1 || returns[0]!=2) throw new IllegalStateException("operations-observer-splice:"+owner+":"+methods[0]+":"+returns[0]);
        return writer.toByteArray();
    }
}
