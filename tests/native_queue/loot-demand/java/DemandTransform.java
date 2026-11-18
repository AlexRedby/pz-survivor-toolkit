package net.alexredby.lootdemand;

import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Map;
import java.util.Set;
import net.bytebuddy.jar.asm.*;

/** Exact B42.22.2 method guards; unrelated class methods/advice remain untouched. */
public final class DemandTransform {
    public static final String PICKER="zombie/inventory/ItemPickerJava";
    public static final String LOADER="zombie/LoadGridsquarePerformanceWorkaround$ItemPicker";
    public static final String CONTAINER="zombie/inventory/ItemContainer";
    public static final Set<String> TARGETS=Set.of(LOADER,PICKER,CONTAINER);
    static final String BRIDGE="net/alexredby/lootdemand/LootDemand";
    static final String ITEM_CONTAINER="Lzombie/inventory/ItemContainer;";
    static final String FILL="(Lzombie/inventory/ItemContainer;Lzombie/characters/IsoPlayer;)V";
    private static final Map<String,String> METHODS=Map.of(
        LOADER+".checkObject(Lzombie/iso/IsoObject;)V","4e67abe12eff6f8b130e2c63f4ab849b108b4fb473af1055895126ac6e5ff288",
        PICKER+".fillContainer"+FILL,"3ae0b55334ac6e788aad2f6667c9967376c55b49d50b33833144b0005bc07697",
        PICKER+".doOverlaySprite(Lzombie/iso/IsoGridSquare;)V","add2dcd37b75d0163bda42ff4d285a99838c5c693249aa66a10d5692e24cdfc6",
        CONTAINER+".dumpContentsInSquare(Lzombie/iso/IsoGridSquare;)V","9f5559796888028d2b3c8627947e87d7780272850af62aaefd010bb3b8304ef9");
    /** Original whole-class provenance, not admission of other changes inside guarded methods.
     * Current official-selected profile replaces none of these three native classes. */
    public static final Map<String,String> SOURCE_SHA256=Map.of(
        LOADER,"3784cb74fa346686e4cd2be20a3fbbc0a83cc65d1be3e8df6f270a24ccd1201d",
        PICKER,"baaa48855c8289fd6758eedb2801c5bbc2837de9a1b6460eca72096cf6e3d8be",
        CONTAINER,"19ffefbabfc16ce3b40feb557189c4fbecdb752aa2c96e3daa8b8ec0542185d3");
    private DemandTransform() {}
    public static String sha(byte[] bytes) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }
    private static byte[] boundary(byte[] bytes,String owner,String method,String descriptor) {
        ClassWriter out=new ClassWriter(0);
        out.visit(Opcodes.V17,Opcodes.ACC_PUBLIC,owner,null,"java/lang/Object",null);
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int access,String name,String desc,String sig,String[] exceptions) {
                return name.equals(method) && desc.equals(descriptor)
                    ? out.visitMethod(access,name,desc,sig,exceptions) : null;
            }
        },ClassReader.SKIP_DEBUG);
        out.visitEnd(); return out.toByteArray();
    }
    public static byte[] transform(String owner,byte[] bytes) throws Exception {
        if (!TARGETS.contains(owner) || bytes==null) throw new IllegalArgumentException("Unsupported loot demand target");
        if (!new ClassReader(bytes).getClassName().equals(owner)) throw new IllegalArgumentException("Target owner mismatch");
        Map<String,Integer> locals=new java.util.HashMap<>();
        new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                return new MethodVisitor(Opcodes.ASM9) {
                    @Override public void visitMaxs(int stack,int count) { locals.put(n+d,count); }
                };
            }
        },0);
        int expected=0;
        for (var method:METHODS.entrySet()) if (method.getKey().startsWith(owner+".")) {
            expected++;
            String signature=method.getKey().substring(owner.length()+1);
            int paren=signature.indexOf('(');
            if (!method.getValue().equals(sha(boundary(bytes,owner,signature.substring(0,paren),signature.substring(paren)))))
                throw new IllegalArgumentException("Changed loot demand method: "+method.getKey());
        }
        ClassReader reader=new ClassReader(bytes);
        ClassWriter writer=new ClassWriter(reader,ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);
        int[] changed={0}, branches={0}, fills={0}, dumps={0}, dumpSteps={0};
        reader.accept(new ClassVisitor(Opcodes.ASM9,writer) {
            @Override public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e) {
                MethodVisitor mv=super.visitMethod(a,n,d,s,e);
                if (!METHODS.containsKey(owner+"."+n+d)) return mv;
                changed[0]++;
                if (n.equals("fillContainer")) {
                    fills[0]++;
                    int token=locals.get(n+d), throwable=token+1;
                    return new MethodVisitor(Opcodes.ASM9,mv) {
                        final Label start=new Label(),end=new Label(),handler=new Label();
                        @Override public void visitCode() {
                            super.visitCode();
                            super.visitVarInsn(Opcodes.ALOAD,0);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,BRIDGE,"enterFill","("+ITEM_CONTAINER+")I",false);
                            super.visitVarInsn(Opcodes.ISTORE,token);
                            super.visitVarInsn(Opcodes.ILOAD,token); super.visitInsn(Opcodes.ICONST_2);
                            Label run=new Label(); super.visitJumpInsn(Opcodes.IF_ICMPNE,run);
                            super.visitInsn(Opcodes.RETURN); super.visitLabel(run); super.visitLabel(start);
                        }
                        void exit(boolean failed) {
                            super.visitVarInsn(Opcodes.ALOAD,0); super.visitVarInsn(Opcodes.ILOAD,token);
                            super.visitInsn(failed ? Opcodes.ICONST_1 : Opcodes.ICONST_0);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,BRIDGE,"exitFill","("+ITEM_CONTAINER+"IZ)V",false);
                        }
                        @Override public void visitInsn(int opcode) { if (opcode==Opcodes.RETURN) exit(false); super.visitInsn(opcode); }
                        @Override public void visitMaxs(int maxStack,int maxLocals) {
                            super.visitLabel(end); super.visitTryCatchBlock(start,end,handler,"java/lang/Throwable");
                            super.visitLabel(handler); super.visitVarInsn(Opcodes.ASTORE,throwable);
                            exit(true); super.visitVarInsn(Opcodes.ALOAD,throwable); super.visitInsn(Opcodes.ATHROW);
                            super.visitMaxs(maxStack,Math.max(maxLocals,throwable+1));
                        }
                    };
                }
                if (n.equals("dumpContentsInSquare")) {
                    dumps[0]++;
                    int scoped=locals.get(n+d);
                    return new MethodVisitor(Opcodes.ASM9,mv) {
                        @Override public void visitCode() {
                            super.visitCode(); super.visitVarInsn(Opcodes.ALOAD,0);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,BRIDGE,"beforeDump","("+ITEM_CONTAINER+")Z",false);
                            super.visitVarInsn(Opcodes.ISTORE,scoped);
                        }
                        @Override public void visitIincInsn(int index,int increment) {
                            if (index!=2 || increment!=1) throw new IllegalArgumentException("Unexpected dump iteration");
                            // Native removes items[index] then increments, skipping half the remaining items.
                            // Only this opt-in target scope retains index0; other containers stay native.
                            Label step=new Label();
                            super.visitVarInsn(Opcodes.ILOAD,scoped); super.visitJumpInsn(Opcodes.IFNE,step);
                            super.visitIincInsn(index,increment); super.visitLabel(step); dumpSteps[0]++;
                        }
                    };
                }
                boolean loader=n.equals("checkObject");
                return new MethodVisitor(Opcodes.ASM9,mv) {
                    boolean afterExplored;
                    @Override public void visitMethodInsn(int op,String o,String name,String desc,boolean itf) {
                        super.visitMethodInsn(op,o,name,desc,itf);
                        afterExplored=o.equals(CONTAINER) && name.equals("isExplored") && desc.equals("()Z");
                    }
                    @Override public void visitJumpInsn(int op,Label target) {
                        super.visitJumpInsn(op,target);
                        if (afterExplored) {
                            if (op!=Opcodes.IFNE) throw new IllegalArgumentException("Unexpected explored branch");
                            super.visitVarInsn(Opcodes.ALOAD,3);
                            if (!loader) super.visitMethodInsn(Opcodes.INVOKEVIRTUAL,"zombie/iso/IsoObject","getContainer","()"+ITEM_CONTAINER,false);
                            super.visitMethodInsn(Opcodes.INVOKESTATIC,BRIDGE,"shouldDefer","("+ITEM_CONTAINER+")Z",false);
                            super.visitJumpInsn(Opcodes.IFNE,target); branches[0]++;
                            afterExplored=false;
                        }
                    }
                };
            }
        },ClassReader.EXPAND_FRAMES);
        int wantBranches=owner.equals(LOADER) || owner.equals(PICKER) ? 1 : 0;
        if (changed[0]!=expected || branches[0]!=wantBranches || fills[0]!=(owner.equals(PICKER)?1:0)
                || dumps[0]!=(owner.equals(CONTAINER)?1:0) || dumpSteps[0]!=(owner.equals(CONTAINER)?1:0)) throw new IllegalStateException("Loot demand splice count");
        writer.visitEnd(); return writer.toByteArray();
    }
}
