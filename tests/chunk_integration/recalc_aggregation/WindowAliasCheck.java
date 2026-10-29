import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;
import java.util.zip.*;
import net.bytebuddy.jar.asm.*;
import zombie.iso.IsoObject;
import zombie.iso.sprite.IsoSprite;
import zombie.iso.SpriteDetails.IsoFlagType;
import zombie.core.properties.PropertyContainer;

/** Deterministic native-prefix/API counterexample, not a game or full-square fixture. */
public final class WindowAliasCheck implements Opcodes {
 record Op(int opcode,int var,String owner,String name,String desc){}
 static void require(boolean b,String s){if(!b)throw new AssertionError(s);}
 static Class<?> prefix(Path jar)throws Exception{
  byte[] raw;try(ZipFile z=new ZipFile(jar.toFile())){raw=z.getInputStream(z.getEntry("zombie/iso/objects/IsoWindow.class")).readAllBytes();}
  require(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(raw)).equals("41066d88458b7c88f25f893647cbb940af1f893315057813228932c5bafa92d9"),"native window changed");
  List<Op> ops=new ArrayList<>();
  new ClassReader(raw).accept(new ClassVisitor(ASM9){public MethodVisitor visitMethod(int a,String n,String d,String s,String[] x){
   if(!n.equals("<init>")||!d.equals("(Lzombie/iso/IsoCell;Lzombie/iso/IsoGridSquare;Lzombie/iso/sprite/IsoSprite;Z)V"))return null;
   return new MethodVisitor(ASM9){int line;
    public void visitLineNumber(int l,Label x){line=l;}
    public void visitVarInsn(int op,int v){if(line==118||line==119)ops.add(new Op(op,v,null,null,null));}
    public void visitMethodInsn(int op,String o,String n,String d,boolean itf){if(line==118||line==119)ops.add(new Op(op,-1,o,n,d));}
    public void visitFieldInsn(int op,String o,String n,String d){if(line==118||line==119)ops.add(new Op(op,-1,o,n,d));}
   };
  }},ClassReader.SKIP_FRAMES);
  String sprite="zombie/iso/sprite/IsoSprite",pc="zombie/core/properties/PropertyContainer",flag="zombie/iso/SpriteDetails/IsoFlagType";
  List<Op> expected=new ArrayList<>();for(String f:new String[]{"cutN","cutW"}){
   expected.add(new Op(ALOAD,3,null,null,null));expected.add(new Op(INVOKEVIRTUAL,-1,sprite,"getProperties","()L"+pc+";"));
   expected.add(new Op(GETSTATIC,-1,flag,f,"L"+flag+";"));expected.add(new Op(INVOKEVIRTUAL,-1,pc,"unset","(L"+flag+";)V"));
  }
  require(ops.equals(expected),"constructor prefix changed: "+ops);
  ClassWriter cw=new ClassWriter(ClassWriter.COMPUTE_FRAMES|ClassWriter.COMPUTE_MAXS);cw.visit(69,ACC_PUBLIC,"WindowConstructorPrefix",null,"java/lang/Object",null);
  MethodVisitor v=cw.visitMethod(ACC_PUBLIC|ACC_STATIC,"clearCuts","(L"+sprite+";)V",null,null);v.visitCode();
  for(Op op:ops){if(op.var>=0)v.visitVarInsn(op.opcode,0);else if(op.opcode==GETSTATIC)v.visitFieldInsn(op.opcode,op.owner,op.name,op.desc);else v.visitMethodInsn(op.opcode,op.owner,op.name,op.desc,false);}
  v.visitInsn(RETURN);v.visitMaxs(0,0);v.visitEnd();cw.visitEnd();byte[] generated=cw.toByteArray();
  return new ClassLoader(WindowAliasCheck.class.getClassLoader()){Class<?> make(){return defineClass("WindowConstructorPrefix",generated,0,generated.length);}}.make();
 }
 public static void main(String[] args)throws Exception{
  var clear=prefix(Path.of(args[0])).getMethod("clearCuts",IsoSprite.class);
  IsoSprite sprite=new IsoSprite();sprite.getProperties().set(IsoFlagType.cutN);sprite.getProperties().set(IsoFlagType.windowN);
  IsoObject loadedObject=new IsoObject();loadedObject.sprite=sprite;
  PropertyContainer cached=new PropertyContainer();cached.AddProperties(loadedObject.getProperties());
  require(cached.has(IsoFlagType.cutN),"before cutN missing");
  CountDownLatch cleared=new CountDownLatch(1),resume=new CountDownLatch(1);List<Throwable> failed=new ArrayList<>();
  Thread worker=new Thread(()->{try{clear.invoke(null,sprite);cleared.countDown();require(resume.await(10,TimeUnit.SECONDS),"resume timeout");sprite.getProperties().set(IsoFlagType.cutN);sprite.getProperties().set(IsoFlagType.windowN);}catch(Throwable t){failed.add(t);cleared.countDown();}},"controlled-native-prefix-worker");
  worker.start();require(cleared.await(10,TimeUnit.SECONDS),"prefix timeout");
  try{
   require(loadedObject.getProperties()==sprite.getProperties(),"not a shared property alias");
   PropertyContainer fresh=new PropertyContainer();fresh.AddProperties(loadedObject.getProperties());
   require(cached.has(IsoFlagType.cutN)&&!fresh.has(IsoFlagType.cutN),"no semantic-input change");
   System.out.println("ALIAS_COUNTEREXAMPLE cachedCutN=true freshCutN=false sameLoadedObject=true sameSprite=true");
  }finally{resume.countDown();worker.join(10000);}
  require(!worker.isAlive()&&failed.isEmpty(),"worker failure "+failed);require(sprite.getProperties().has(IsoFlagType.cutN),"direction restore missing");
  System.out.println("WINDOW_NATIVE_PREFIX_ALIAS_CHECK_PASS restoredCutN=true operations=8");
 }
}
