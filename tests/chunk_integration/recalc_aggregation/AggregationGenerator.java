import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import net.bytebuddy.jar.asm.*;

/** Copies actual guarded RecalcProperties twice inside the original class; changes aggregation only. */
public final class AggregationGenerator implements Opcodes {
    static boolean OBSERVE=true;
    static final String OWNER="zombie/iso/IsoGridSquare", SCOPE="pzresearch/AggregationScope";
    static final Set<String> HASHES=Set.of(
        "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467",
        "557646359c35a309c786c24c7d7fd522d2877f9ad64aea1315a29052d76920a6");
    static String sha(byte[] b)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(b));}
    static MethodVisitor transform(MethodVisitor output,boolean candidate) {
        return new MethodVisitor(ASM9,output) {
            Label startAggregation,endAggregation;
            final Label reuseSuffix=new Label(),bodyStart=new Label(),bodyEnd=new Label(),failure=new Label();
            boolean zoneSeen,inAggregation;String stage="prefix";int starts,ends;
            void helper(String name,String desc){super.visitMethodInsn(INVOKESTATIC,SCOPE,name,desc,false);}
            void count(String name){if(OBSERVE){super.visitLdcInsn(stage+":"+name);helper("count","(Ljava/lang/String;)V");}}
            public void visitCode(){super.visitCode();if(candidate){super.visitLabel(bodyStart);helper("startCall","()V");}
                else {Label baseline=new Label();helper("route","()Z");super.visitJumpInsn(IFEQ,baseline);
                    super.visitVarInsn(ALOAD,0);super.visitMethodInsn(INVOKEVIRTUAL,OWNER,"pztestRecalcProperties","()V",false);super.visitInsn(RETURN);super.visitLabel(baseline);}}
            public void visitFieldInsn(int op,String owner,String name,String desc) {
                if(op==GETFIELD && owner.equals(OWNER) && name.equals("zone"))zoneSeen=true;
                if(op==PUTFIELD)count("field:"+owner+"."+name);
                super.visitFieldInsn(op,owner,name,desc);
            }
            public void visitJumpInsn(int op,Label label) {
                if(zoneSeen && op==IFNONNULL && startAggregation==null){startAggregation=label;zoneSeen=false;}
                if(inAggregation && op==IF_ICMPGE && endAggregation==null)endAggregation=label;
                super.visitJumpInsn(op,label);
            }
            public void visitLabel(Label label) {
                super.visitLabel(label);
                if(label==startAggregation) {
                    starts++;stage="aggregate";inAggregation=true;
                    if(candidate) {
                        super.visitVarInsn(ALOAD,0);helper("lookup","(L"+OWNER+";)I");super.visitVarInsn(ISTORE,15);
                        Label miss=new Label();super.visitVarInsn(ILOAD,15);super.visitJumpInsn(IFLT,miss);
                        for(int i=0;i<8;i++){
                            super.visitVarInsn(ILOAD,15);super.visitIntInsn(BIPUSH,i);super.visitInsn(IUSHR);
                            super.visitInsn(ICONST_1);super.visitInsn(IAND);super.visitVarInsn(ISTORE,i+2);
                        }
                        super.visitJumpInsn(GOTO,reuseSuffix);super.visitLabel(miss);
                    }
                }
                if(label==endAggregation) {
                    ends++;inAggregation=false;stage="suffix";
                    if(candidate) {
                        super.visitVarInsn(ALOAD,0);super.visitInsn(ICONST_0);
                        for(int i=0;i<8;i++){
                            super.visitVarInsn(ILOAD,i+2);super.visitIntInsn(BIPUSH,i);super.visitInsn(ISHL);super.visitInsn(IOR);
                        }
                        helper("remember","(L"+OWNER+";I)V");super.visitLabel(reuseSuffix);
                    }
                }
            }
            public void visitMethodInsn(int op,String owner,String name,String desc,boolean iface){
                count("method:"+owner+"."+name+desc);super.visitMethodInsn(op,owner,name,desc,iface);
            }
            public void visitInsn(int op){if(candidate && op==RETURN)helper("endCall","()V");super.visitInsn(op);}
            public void visitMaxs(int stack,int locals){
                if(starts!=1 || ends!=1)throw new IllegalStateException("Aggregation boundaries "+starts+"/"+ends);
                if(candidate){
                    super.visitLabel(bodyEnd);super.visitTryCatchBlock(bodyStart,bodyEnd,failure,"java/lang/Throwable");
                    super.visitLabel(failure);super.visitVarInsn(ASTORE,16);helper("invalidate","()V");helper("endCall","()V");
                    super.visitVarInsn(ALOAD,16);super.visitInsn(ATHROW);
                }
                super.visitMaxs(stack,Math.max(locals,17));
            }
        };
    }
    public static void main(String[] args)throws Exception {
        OBSERVE=args.length<3 || !args[2].equals("plain");
        byte[] bytes=Files.readAllBytes(Path.of(args[0]));
        if(!HASHES.contains(sha(bytes)))throw new IllegalArgumentException("Unsupported/already transformed square class");
        ClassReader reader=new ClassReader(bytes);
        ClassWriter writer=new ClassWriter(reader,ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);
        int[] originals={0},copies={0};
        reader.accept(new ClassVisitor(ASM9,writer){
            public MethodVisitor visitMethod(int access,String name,String desc,String sig,String[] ex){
                MethodVisitor mv=super.visitMethod(access,name,desc,sig,ex);
                if(name.equals("RecalcProperties") && desc.equals("()V")){originals[0]++;return transform(mv,false);}
                return mv;
            }
        },ClassReader.SKIP_FRAMES);
        reader.accept(new ClassVisitor(ASM9){
            public MethodVisitor visitMethod(int access,String name,String desc,String sig,String[] ex){
                if(!name.equals("RecalcProperties") || !desc.equals("()V"))return null;
                copies[0]++;return transform(writer.visitMethod(ACC_PUBLIC,"pztestRecalcProperties",desc,null,ex),true);
            }
        },ClassReader.SKIP_FRAMES|ClassReader.SKIP_DEBUG);
        if(originals[0]!=1 || copies[0]!=1)throw new IllegalStateException("Method admission mismatch");
        writer.visitEnd();byte[] changed=writer.toByteArray();
        Set<String> originalFields=new TreeSet<>(),changedFields=new TreeSet<>();
        new ClassReader(bytes).accept(new ClassVisitor(ASM9){public FieldVisitor visitField(int a,String n,String d,String s,Object v){originalFields.add(n+d);return null;}},0);
        new ClassReader(changed).accept(new ClassVisitor(ASM9){public FieldVisitor visitField(int a,String n,String d,String s,Object v){changedFields.add(n+d);return null;}},0);
        if(!originalFields.equals(changedFields))throw new IllegalStateException("Native fields changed");
        if(HASHES.contains(sha(changed)))throw new IllegalStateException("Splice did not change bytes");
        Path output=Path.of(args[1]).resolve(OWNER+".class");Files.createDirectories(output.getParent());Files.write(output,changed);
        System.out.println("AGGREGATION_SPLICE_READY "+sha(changed));
    }
}
