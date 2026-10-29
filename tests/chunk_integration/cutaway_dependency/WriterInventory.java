import java.nio.file.*;
import java.security.*;
import java.util.*;
import java.util.zip.*;
import net.bytebuddy.jar.asm.*;

/** Bytecode inventory only: records accesses, not an unsupported alias-completeness claim. */
public final class WriterInventory implements Opcodes {
    static final String SQUARE="zombie/iso/IsoGridSquare", CHUNK="zombie/iso/IsoChunk";
    static final String DATA="zombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelData";
    static final Map<String,Set<String>> FIELDS=Map.of(
        SQUARE,Set.of("visionMatrix","x","y","z","chunk"),
        CHUNK,Set.of("wx","wy","squares","minLevel","maxLevel"),
        "zombie/iso/IsoChunkLevel",Set.of("squares","chunk","level"),
        DATA,Set.of("squareFlags","level","levelsData"),
        "zombie/iso/fboRenderChunk/FBORenderCutaways$ChunkLevelsData",Set.of("chunk"));
    static String sha(byte[] b)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(b));}
    public static void main(String[] args)throws Exception {
        if(args.length!=1)throw new IllegalArgumentException("archive required");
        List<String> rows=new ArrayList<>();int[] classes={0};
        try(ZipFile archive=new ZipFile(args[0])) {
            for(ZipEntry entry:Collections.list(archive.entries())) {
                if(!entry.getName().endsWith(".class"))continue;
                byte[] input=archive.getInputStream(entry).readAllBytes();String digest=sha(input);classes[0]++;
                new ClassReader(input).accept(new ClassVisitor(ASM9) {
                    String type;
                    public void visit(int v,int a,String n,String s,String p,String[] i){type=n;}
                    public MethodVisitor visitMethod(int access,String method,String desc,String sig,String[] ex) {
                        return new MethodVisitor(ASM9) {
                            final List<String> events=new ArrayList<>();boolean flags,squares,vision;
                            int arrayStores,byteStores,copies,fills;
                            public void visitFieldInsn(int op,String owner,String name,String desc) {
                                if(op==PUTFIELD && FIELDS.getOrDefault(owner,Set.of()).contains(name))
                                    events.add("PUTFIELD "+owner+"."+name+" "+desc);
                                if(op==GETFIELD && owner.equals(DATA) && name.equals("squareFlags"))flags=true;
                                if(op==GETFIELD && (owner.equals(CHUNK) || owner.equals("zombie/iso/IsoChunkLevel")) && name.equals("squares"))squares=true;
                                if(op==GETFIELD && owner.equals(SQUARE) && name.equals("visionMatrix"))vision=true;
                            }
                            public void visitInsn(int op){if(op==AASTORE)arrayStores++;if(op==BASTORE)byteStores++;}
                            public void visitMethodInsn(int op,String owner,String name,String desc,boolean iface) {
                                if(owner.equals(CHUNK) && name.equals("getSquaresForLevel"))squares=true;
                                if(owner.equals("java/lang/System") && name.equals("arraycopy"))copies++;
                                if(owner.equals("java/util/Arrays") && name.equals("fill"))fills++;
                            }
                            public void visitEnd(){
                                if(flags)events.add("SQUARE_FLAGS_CONSUMER byteStores="+byteStores+" arrayStores="+arrayStores+" arraycopy="+copies+" fill="+fills);
                                if(squares)events.add("SQUARES_ARRAY_CONSUMER arrayStores="+arrayStores+" arraycopy="+copies+" fill="+fills);
                                if(!events.isEmpty())for(String event:events)rows.add(type+"\t"+method+desc+"\t"+event+"\t"+digest);
                            }
                        };
                    }
                },ClassReader.SKIP_DEBUG|ClassReader.SKIP_FRAMES);
            }
        }
        Collections.sort(rows);for(String row:rows)System.out.println(row);
        System.out.println("INVENTORY_CLASSES="+classes[0]+" EVENTS="+rows.size());
    }
}
