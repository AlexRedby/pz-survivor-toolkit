import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.HexFormat;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.characterTextures.BloodBodyPartType;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.skinnedmodel.visual.ItemVisual;
import zombie.core.skinnedmodel.visual.ItemVisuals;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.SyncVisualsPacket;

public class NativeChecks {
 public static class Patient extends IsoPlayer {
  ItemVisuals visuals;
  public Patient(){super(null);}
  @Override public void getItemVisuals(ItemVisuals out){out.clear();out.addAll(visuals);}
 }
 static final short ID=42;
 static final BloodBodyPartType PART=BloodBodyPartType.FromIndex(0);
 static Field field(Class<?> c,String n)throws Exception{Field f=c.getDeclaredField(n);f.setAccessible(true);return f;}
 static void require(boolean v,String why){if(!v)throw new AssertionError(why);}
 static Patient patient(int n,boolean reverse)throws Exception{
  Field uf=field(Unsafe.class,"theUnsafe");Unsafe u=(Unsafe)uf.get(null);
  Patient p=(Patient)u.allocateInstance(Patient.class);p.onlineId=ID;p.visuals=new ItemVisuals();
  for(int x=0;x<n;x++){int i=reverse?n-1-x:x;ItemVisual v=new ItemVisual();v.setItemType("Base.Trace"+i);v.setBlood(PART,(i+1)/10f);v.setDirt(PART,(i+1)/20f);if(i==0)v.setBasicPatch(PART);p.visuals.add(v);}
  return p;
 }
 static SyncVisualsPacket packet(Patient p)throws Exception{
  SyncVisualsPacket packet=new SyncVisualsPacket();PlayerID id=(PlayerID)field(SyncVisualsPacket.class,"playerId").get(packet);id.setID(ID);field(PlayerID.class,"player").set(id,p);return packet;
 }
 static byte[] write(Patient p)throws Exception{ByteBuffer b=ByteBuffer.allocate(8192);packet(p).write(new ByteBufferWriter(b));byte[] bytes=new byte[b.position()];b.flip();b.get(bytes);return bytes;}
 static String digest(byte[] b)throws Exception{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(b));}
 static void cases(String phase)throws Exception{
  GameServer.server=false;GameClient.client=true;
  Patient source=patient(8,false);byte[] wire=write(source);
  require(wire[3]==8,"wrong native count");
  Patient target=patient(7,false);target.visuals.get(0).setBlood(PART,.93f);target.visuals.get(0).setLeatherPatch(PART);
  float oldBlood=target.visuals.get(0).getBlood(PART),oldLeather=target.visuals.get(0).getLeatherPatch(PART),oldBasic=target.visuals.get(0).getBasicPatch(PART);
  GameClient.IDToPlayerMap.put(ID,target);SyncVisualsPacket mismatch=new SyncVisualsPacket();ByteBufferReader r=new ByteBufferReader(ByteBuffer.wrap(wire));mismatch.parse(r,null);
  require(!mismatch.isConsistent(null),"native count mismatch accepted");require(r.bb.position()==4,"native mismatch parsed body");
  require(target.visuals.get(0).getBlood(PART)==oldBlood&&target.visuals.get(0).getLeatherPatch(PART)==oldLeather&&target.visuals.get(0).getBasicPatch(PART)==oldBasic,"mismatch mutated blood/patch");
  Patient equal=patient(8,false);for(ItemVisual v:equal.visuals){v.setBlood(PART,0);v.removePatch(PART.index());}
  GameClient.IDToPlayerMap.put(ID,equal);SyncVisualsPacket valid=new SyncVisualsPacket();r=new ByteBufferReader(ByteBuffer.wrap(wire));valid.parse(r,null);
  require(valid.isConsistent(null),"equal native count rejected");require(!r.bb.hasRemaining(),"valid payload incomplete");
  for(int i=0;i<8;i++)require(equal.visuals.get(i).getBlood(PART)==source.visuals.get(i).getBlood(PART),"valid blood effect lost "+i);
  require(equal.visuals.get(0).getBasicPatch(PART)==source.visuals.get(0).getBasicPatch(PART),"valid basic patch effect lost");
  Patient swapped=patient(8,true);GameClient.IDToPlayerMap.put(ID,swapped);SyncVisualsPacket positional=new SyncVisualsPacket();r=new ByteBufferReader(ByteBuffer.wrap(wire));positional.parse(r,null);
  require(positional.isConsistent(null)&&!r.bb.hasRemaining(),"same count swapped packet rejected");
  require(swapped.visuals.get(0).getItemType().equals("Base.Trace7"),"parser changed identities");
  require(swapped.visuals.get(0).getBlood(PART)==source.visuals.get(0).getBlood(PART),"parser did not demonstrate positional application");
  require(swapped.visuals.get(0).getBasicPatch(PART)>0,"positionally wrong clothing did not receive patch");
  System.out.println("NATIVE_CASES_PASS phase="+phase+" bytes="+wire.length+" count="+wire[3]+" sha256="+digest(wire)+" mismatchConsumed=4 equalConsumed="+wire.length+" swappedIdentity=Base.Trace7<-Base.Trace0");
 }
 public static void main(String[] args)throws Exception{
  zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
  require(net.alexredby.visualtrace.Main.SUPPORTED,"trace hash guard mismatch");
  ByteBuffer probe=ByteBuffer.wrap(new byte[]{9,0,1,0,8,2});probe.position(1);
  String summary=net.alexredby.visualtrace.Main.wire(probe,1,6);
  require(probe.position()==1,"trace moved wire buffer position");
  System.out.println("JSON_CHECK {\"quoted\":"+net.alexredby.visualtrace.Main.q("quote\"\\\n\t")+",\"wire\":"+summary+"}");
  cases("original");
  me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.visualtrace",NativeChecks.class.getClassLoader());
  cases("woven");
  try {
   new SyncVisualsPacket().write(new ByteBufferWriter(ByteBuffer.allocate(16)));
   throw new AssertionError("trace suppressed native write NPE");
  } catch(NullPointerException expected) {
   require(expected.getMessage().contains("getItemVisuals"),"unrelated native exception: "+expected);
  }
  System.out.println("NATIVE_FAILURE_PRESERVED_PASS");
 }
}
