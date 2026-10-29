import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import net.bytebuddy.jar.asm.*;

/** Extracts the pinned object-prefix operations; no game method is transformed. */
public final class FogScanGenerator implements Opcodes {
    record Op(int opcode, int var, String owner, String name, String desc) {
        String signature() { return opcode + ":" + var + ":" + owner + ":" + name + ":" + desc; }
        void emit(MethodVisitor v) {
            if (var >= 0) v.visitVarInsn(opcode, switch(var) {
                case 12 -> 0; case 13 -> 1; case 1 -> 2; case 14 -> 3;
                case 15 -> 4; case 16 -> 5; default -> throw new AssertionError(var);
            });
            else if (owner != null) {
                if (opcode == INVOKEVIRTUAL) v.visitMethodInsn(opcode, owner, name, desc, false);
                else v.visitFieldInsn(opcode, owner, name, desc);
            } else v.visitInsn(opcode);
        }
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 3 || !args[2].equals("25")) throw new IllegalArgumentException("project JVM target 25 required");
        List<Op> ops = new ArrayList<>();
        byte[] input;
        try (ZipFile z = new ZipFile(args[0])) {
            input = z.getInputStream(z.getEntry("zombie/iso/fboRenderChunk/FBORenderCell.class")).readAllBytes();
        }
        new ClassReader(input).accept(new ClassVisitor(ASM9) {
            public MethodVisitor visitMethod(int a, String n, String d, String s, String[] e) {
                if (!n.equals("renderFog") || !d.equals("(I)V")) return null;
                return new MethodVisitor(ASM9) {
                    public void visitVarInsn(int op, int var) { ops.add(new Op(op,var,null,null,null)); }
                    public void visitInsn(int op) { ops.add(new Op(op,-1,null,null,null)); }
                    public void visitJumpInsn(int op, Label l) { ops.add(new Op(op,-1,null,null,null)); }
                    public void visitMethodInsn(int op,String o,String n,String d,boolean i) { ops.add(new Op(op,-1,o,n,d)); }
                    public void visitFieldInsn(int op,String o,String n,String d) { ops.add(new Op(op,-1,o,n,d)); }
                    public void visitIincInsn(int var,int n) { ops.add(new Op(IINC,var,null,null,Integer.toString(n))); }
                    public void visitTypeInsn(int op,String type) { ops.add(new Op(op,-1,type,null,null)); }
                    public void visitLdcInsn(Object value) { ops.add(new Op(LDC,-1,null,null,String.valueOf(value))); }
                };
            }
        }, ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
        int call = -1;
        for(int i=0;i<ops.size();i++) if ("getRenderInfo".equals(ops.get(i).name())) {
            if (call!=-1) throw new AssertionError("ambiguous getRenderInfo"); call=i;
        }
        List<Op> prefix = ops.subList(call-9,call+6);
        String iso="zombie/iso/IsoObject", info="zombie/iso/fboRenderChunk/ObjectRenderInfo", layer="zombie/iso/fboRenderChunk/ObjectRenderLayer";
        List<Op> expected=List.of(new Op(ILOAD,14,null,null,null),new Op(ILOAD,13,null,null,null),new Op(IF_ICMPGE,-1,null,null,null),
            new Op(ALOAD,12,null,null,null),new Op(ILOAD,14,null,null,null),new Op(AALOAD,-1,null,null,null),new Op(ASTORE,15,null,null,null),
            new Op(ALOAD,15,null,null,null),new Op(ILOAD,1,null,null,null),new Op(INVOKEVIRTUAL,-1,iso,"getRenderInfo","(I)L"+info+";"),
            new Op(ASTORE,16,null,null,null),new Op(ALOAD,16,null,null,null),new Op(GETFIELD,-1,info,"layer","L"+layer+";"),
            new Op(GETSTATIC,-1,layer,"MinusFloor","L"+layer+";"),new Op(IF_ACMPNE,-1,null,null,null));
        if (!prefix.equals(expected)) throw new AssertionError("native prefix changed: "+prefix);
        ClassWriter cw=new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);
        // Class-file major is Java release + 44: JVM 25 => 69. Avoid requiring ASM V25.
        cw.visit(Integer.parseInt(args[2])+44,ACC_PUBLIC|ACC_FINAL,"FogObjectScan",null,"java/lang/Object",null);
        for(int width:new int[]{1,4}) {
            MethodVisitor v=cw.visitMethod(ACC_PUBLIC|ACC_STATIC,width==1?"stock":"unrolled","([L"+iso+";II)I",null,null);
            v.visitCode(); v.visitInsn(ICONST_0);v.visitVarInsn(ISTORE,3);
            Label loop=new Label(),end=new Label();v.visitLabel(loop);
            for(int n=0;n<width;n++) {
                Label next=new Label();
                for(Op op:prefix) {
                    if(op.opcode()==IF_ICMPGE) v.visitJumpInsn(IF_ICMPGE,end);
                    else if(op.opcode()==IF_ACMPNE) v.visitJumpInsn(IF_ACMPNE,next);
                    else op.emit(v);
                }
                v.visitVarInsn(ILOAD,3);v.visitInsn(IRETURN);
                v.visitLabel(next);v.visitIincInsn(3,1);
            }
            v.visitJumpInsn(GOTO,loop);v.visitLabel(end);v.visitInsn(ICONST_M1);v.visitInsn(IRETURN);v.visitMaxs(0,0);v.visitEnd();
        }
        cw.visitEnd();Path output=Path.of(args[1]);Files.createDirectories(output);Files.write(output.resolve("FogObjectScan.class"),cw.toByteArray());
        System.out.println("FOG_SCAN_EXTRACTED operations="+prefix.size()+" widths=1,4");
    }
}
