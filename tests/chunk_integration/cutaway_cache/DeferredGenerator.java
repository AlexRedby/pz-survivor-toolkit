import java.nio.file.*;
import net.bytebuddy.jar.asm.*;

/** Adds one isolated fixture field to the already emitted native IsoChunk; native methods stay unchanged. */
public final class DeferredGenerator implements Opcodes {
    public static void main(String[] args)throws Exception {
        Path path=Path.of(args[0],"zombie/iso/IsoChunk.class");
        ClassWriter out=new ClassWriter(0);
        new ClassReader(Files.readAllBytes(path)).accept(new ClassVisitor(ASM9,out){
            public void visitEnd(){super.visitField(ACC_PUBLIC,"cutawayDeferredState","LDeferredCache$State;",null,null).visitEnd();super.visitEnd();}
        },0);
        Files.write(path,out.toByteArray());System.out.println("DEFERRED_FIELD_ADDED native-methods-unchanged");
    }
}
