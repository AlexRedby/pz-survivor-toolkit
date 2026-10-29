import java.nio.file.*;
import java.util.*;
import net.bytebuddy.jar.asm.*;

/** Compare exact affected instruction streams after removing only paired semantic-observer calls. */
public final class ObserveEquivalence implements Opcodes {
    static Map<String,List<String>> read(byte[] b) {
        Map<String,List<String>> result=new TreeMap<>();
        new ClassReader(b).accept(new ClassVisitor(ASM9){
            public MethodVisitor visitMethod(int a,String n,String d,String s,String[] e){
                if(!n.equals("RecalcProperties") && !n.equals("pztestRecalcProperties"))return null;
                List<String> tokens=new ArrayList<>();result.put(n+d,tokens);
                return new MethodVisitor(ASM9){
                    final IdentityHashMap<Label,Integer> labels=new IdentityHashMap<>();String pending;
                    int label(Label l){return labels.computeIfAbsent(l,k->labels.size());}
                    void add(String s){if(pending!=null)throw new AssertionError("Unpaired count constant");tokens.add(s);}
                    public void visitInsn(int op){add("I"+op);}public void visitIntInsn(int op,int v){add("N"+op+":"+v);}
                    public void visitVarInsn(int op,int v){add("V"+op+":"+v);}
                    public void visitTypeInsn(int op,String t){add("T"+op+":"+t);}
                    public void visitFieldInsn(int op,String o,String n,String d){add("F"+op+":"+o+":"+n+":"+d);}
                    public void visitMethodInsn(int op,String o,String n,String d,boolean i){
                        if(o.equals("pzresearch/AggregationScope") && n.equals("count")){if(pending==null)throw new AssertionError("Unpaired count");pending=null;return;}
                        add("M"+op+":"+o+":"+n+":"+d+":"+i);
                    }
                    public void visitLdcInsn(Object v){if(v instanceof String x && (x.startsWith("prefix:") || x.startsWith("aggregate:") || x.startsWith("suffix:"))){if(pending!=null)throw new AssertionError("Double count constant");pending=x;}else add("C"+v);}
                    public void visitJumpInsn(int op,Label l){add("J"+op+":"+label(l));}
                    public void visitLabel(Label l){add("L"+label(l));}
                    public void visitIincInsn(int v,int i){add("INC"+v+":"+i);}
                    public void visitTryCatchBlock(Label a,Label b,Label h,String t){add("TRY"+label(a)+":"+label(b)+":"+label(h)+":"+t);}
                    public void visitEnd(){if(pending!=null)throw new AssertionError("Trailing count");}
                };
            }
        },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
        return result;
    }
    public static void main(String[] args)throws Exception {
        Map<String,List<String>> a=read(Files.readAllBytes(Path.of(args[0]))),b=read(Files.readAllBytes(Path.of(args[1])));
        if(!a.equals(b))throw new AssertionError("Observer-free splice differs beyond counter pairs");
        System.out.println("OBSERVER_FREE_EQUIVALENCE_PASS methods="+a.size());
    }
}
