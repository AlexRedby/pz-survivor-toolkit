import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import net.bytebuddy.jar.asm.*;

/** Test-only exact full-operation extraction, with one bounded arithmetic rewrite. */
public final class CutawayGenerator implements Opcodes {
    static final String OWNER="zombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelData";
    static final String DESC="(IIIII[I)Z";
    public static void main(String[] a) throws Exception {
        if(a.length!=4 || !a[2].equals("25"))throw new IllegalArgumentException("archive, output, project target 25 required");
        byte[] bytes;
        try(ZipFile z=new ZipFile(a[0])) {bytes=z.getInputStream(z.getEntry(OWNER+".class")).readAllBytes();}
        ClassWriter cw=new ClassWriter(ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);
        cw.visit(44+Integer.parseInt(a[2]),ACC_PUBLIC|ACC_FINAL,a[3],null,"java/lang/Object",null);
        // Copy the complete native/official helper too. Its original receiver is local zero.
        new ClassReader(bytes).accept(new ClassVisitor(ASM9) {
            public MethodVisitor visitMethod(int access,String name,String desc,String sig,String[] ex) {
                if(!name.equals("shouldRenderSquare"))return null;
                return cw.visitMethod(ACC_PUBLIC|ACC_STATIC,"shouldRenderSquare","(L"+OWNER+";"+desc.substring(1),null,null);
            }
        },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
        for(boolean candidate:new boolean[]{false,true}) {
            MethodVisitor out=cw.visitMethod(ACC_PUBLIC|ACC_STATIC,candidate?"reduced":"stock","(L"+OWNER+";"+DESC.substring(1),null,null);
            int[] methods={0},changes={0};
            new ClassReader(bytes).accept(new ClassVisitor(ASM9) {
                public MethodVisitor visitMethod(int access,String name,String desc,String sig,String[] ex) {
                    if(!name.equals("calculateOccludingSquares") || !desc.equals(DESC))return null;
                    methods[0]++;
                    return new MethodVisitor(ASM9,out) {
                        boolean afterMax,mask;int at;
                        final List<String> expected=List.of("v:21:13","i:16:8","o:112","v:54:18","v:21:13","i:16:8","o:108","v:54:19","o:4","v:21:18","v:21:19","i:16:8","o:104","o:96","o:120","v:54:20");
                        boolean skip(String op) {
                            if(!candidate || !mask)return false;
                            if(at>=expected.size() || !expected.get(at++).equals(op))throw new AssertionError("native mask changed: "+op+" at "+at);
                            if(at==expected.size()) {
                                mask=false;changes[0]++;
                                super.visitInsn(ICONST_1);super.visitVarInsn(ILOAD,13);super.visitInsn(ISHL);super.visitVarInsn(ISTORE,20);
                            }
                            return true;
                        }
                        public void visitVarInsn(int op,int var) {if(!skip("v:"+op+":"+var))super.visitVarInsn(op,var);}
                        public void visitIntInsn(int op,int value) {if(!skip("i:"+op+":"+value))super.visitIntInsn(op,value);}
                        public void visitInsn(int op) {
                            if(skip("o:"+op))return;
                            super.visitInsn(op);
                            if(candidate && afterMax && op==IASTORE) {afterMax=false;mask=true;at=0;}
                        }
                        public void visitMethodInsn(int op,String owner,String name,String desc,boolean iface) {
                            if(owner.equals(OWNER) && name.equals("shouldRenderSquare"))
                                super.visitMethodInsn(INVOKESTATIC,a[3],name,"(L"+OWNER+";"+desc.substring(1),false);
                            else super.visitMethodInsn(op,owner,name,desc,iface);
                            if(owner.equals("zombie/core/math/PZMath") && name.equals("max"))afterMax=true;
                        }
                        public void visitEnd(){if(mask)throw new AssertionError("incomplete mask");super.visitEnd();}
                    };
                }
            },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
            if(methods[0]!=1 || changes[0]!=(candidate?1:0))throw new AssertionError("unexpected operation/mask count");
        }
        cw.visitEnd();Path out=Path.of(a[1]);Files.createDirectories(out);Files.write(out.resolve(a[3]+".class"),cw.toByteArray());
        System.out.println("CUTAWAY_EXTRACTED entire-operation mask-only 16-to-4 instructions");
    }
}
