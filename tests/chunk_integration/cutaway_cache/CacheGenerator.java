import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import net.bytebuddy.jar.asm.*;

/** Extracts the complete pinned caller and exact-mask helper; substitutes only fixture infrastructure. */
public final class CacheGenerator implements Opcodes {
    static final String CELL="zombie/iso/fboRenderChunk/FBORenderCell", DATA=CELL+"$PerPlayerData";
    static String map(String s){return s.replace(DATA,"CacheChecks$PlayerData").replace(CELL,"CacheChecks$Cell");}
    public static void main(String[] a)throws Exception {
        byte[] bytes;try(ZipFile z=new ZipFile(a[0])){bytes=z.getInputStream(z.getEntry(CELL+".class")).readAllBytes();}
        ClassWriter w=new ClassWriter(ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);
        w.visit(69,ACC_PUBLIC|ACC_FINAL,"PinnedCache",null,"java/lang/Object",null);
        int[] found={0,0};
        new ClassReader(bytes).accept(new ClassVisitor(ASM9){
            public MethodVisitor visitMethod(int access,String name,String desc,String sig,String[] ex){
                int kind=name.equals("calculateOccludingSquares")?0:name.equals("pzoptExactOccluderMask")?1:-1;
                if(kind<0)return null;found[kind]++;
                String outDesc=kind==0?"(LCacheChecks$Cell;I)V":desc;
                return new MethodVisitor(ASM9,w.visitMethod(ACC_PUBLIC|ACC_STATIC,name,outDesc,null,null)){
                    public void visitTypeInsn(int op,String type){super.visitTypeInsn(op,map(type));}
                    public void visitFieldInsn(int op,String owner,String name,String desc){
                        if(owner.equals("pzopt/Config") && name.equals("CUTAWAY_FAST")){super.visitFieldInsn(GETSTATIC,"CacheChecks","fast","Z");return;}
                        if(owner.equals("zombie/iso/IsoChunk") && name.equals("pzoptOccluderMask")){super.visitMethodInsn(INVOKESTATIC,"CacheChecks","mask","(Lzombie/iso/IsoChunk;)[J",false);return;}
                        if(owner.equals("zombie/iso/IsoChunk") && name.equals("pzoptOccluderMaskSet")){super.visitMethodInsn(INVOKESTATIC,"CacheChecks",op==GETFIELD?"maskSet":"setMaskSet",op==GETFIELD?"(Lzombie/iso/IsoChunk;)J":"(Lzombie/iso/IsoChunk;J)V",false);return;}
                        super.visitFieldInsn(op,map(owner),name,map(desc));
                    }
                    public void visitMethodInsn(int op,String owner,String name,String desc,boolean iface){
                        if(owner.equals("pzopt/Overrides") && name.equals("enabled")){super.visitInsn(ICONST_1);return;}
                        if(owner.equals("zombie/core/Core") && name.equals("getInstance")){super.visitInsn(ACONST_NULL);return;}
                        if(owner.equals("zombie/core/Core") && name.equals("getZoom")){super.visitInsn(POP2);super.visitInsn(FCONST_1);return;}
                        if(owner.equals("zombie/iso/IsoChunk") && name.equals("getCutawayData")){super.visitMethodInsn(INVOKESTATIC,"CacheChecks","levels","(Lzombie/iso/IsoChunk;)Lzombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelsData;",false);return;}
                        if(owner.equals("zombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelsData") && name.equals("getDataForLevel")){super.visitMethodInsn(INVOKESTATIC,"CacheChecks","level","(Lzombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelsData;I)Lzombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelData;",false);return;}
                        if(owner.equals("zombie/iso/fboRenderChunk/FBORenderOcclusion") && name.equals("getInstance")){super.visitInsn(ACONST_NULL);return;}
                        if(owner.equals("zombie/iso/fboRenderChunk/FBORenderOcclusion") && name.equals("invalidateOverlappedChunkLevels")){super.visitMethodInsn(INVOKESTATIC,"CacheChecks","invalidate","(Lzombie/iso/fboRenderChunk/FBORenderOcclusion;ILzombie/iso/IsoChunk;I)V",false);return;}
                        if(owner.equals(CELL) && name.equals("pzoptExactOccluderMask")){super.visitMethodInsn(INVOKESTATIC,"PinnedCache",name,desc,false);return;}
                        super.visitMethodInsn(op,map(owner),name,map(desc),iface);
                    }
                };
            }
        },ClassReader.SKIP_FRAMES|ClassReader.SKIP_DEBUG);
        if(!Arrays.equals(found,new int[]{1,1}))throw new AssertionError(Arrays.toString(found));
        w.visitEnd();Files.write(Path.of(a[1],"PinnedCache.class"),w.toByteArray());
        // Add only a fixture field to native IsoChunk: all native method bytecode remains untouched.
        byte[] chunk;try(ZipFile z=new ZipFile(a[2])){chunk=z.getInputStream(z.getEntry("zombie/iso/IsoChunk.class")).readAllBytes();}
        ClassWriter holder=new ClassWriter(0);
        new ClassReader(chunk).accept(new ClassVisitor(ASM9,holder){public void visitEnd(){
            super.visitField(ACC_PUBLIC,"cutawayCacheState","LCacheChecks$State;",null,null).visitEnd();super.visitEnd();
        }},0);
        Path chunkOut=Path.of(a[1],"zombie/iso/IsoChunk.class");Files.createDirectories(chunkOut.getParent());Files.write(chunkOut,holder.toByteArray());
        System.out.println("PINNED_CACHE_EXTRACTED caller+exact-helper infrastructure-only substitutions native-chunk-additive-field");
    }
}
