package zombie.iso;

import zombie.core.stash.StashSystem;
import zombie.randomizedWorld.randomizedBuilding.RBBasic;
import java.nio.*;
import java.lang.reflect.*;
import java.util.*;

/** Native regression and recovery candidate only; this does not install a live repair. */
public final class RoomCollisionChecks {
  static void check(boolean ok, String message) { if (!ok) throw new AssertionError(message); }
  static RoomDef room(int index, long meta, int flags) {
    RoomDef room=new RoomDef(RoomID.makeID(41,37,index),"hall");
    room.rects.add(new RoomDef.RoomRect(10707,9484,1,4)); room.CalculateBounds();
    room.metaId=meta; setFlags(room,flags); return room;
  }
  static int flags(RoomDef r) { return (r.explored?1:0)|(r.lightsActive?2:0)|(r.doneSpawn?4:0)|(r.isRoofFixed()?8:0); }
  static void setFlags(RoomDef r,int f) { r.setExplored((f&1)!=0); r.lightsActive=(f&2)!=0; r.doneSpawn=(f&4)!=0; r.setRoofFixed((f&8)!=0); }
  static IsoMetaGrid grid(RoomDef... rooms) throws Exception {
    IsoMetaGrid g=new IsoMetaGrid(); g.minX=g.maxX=41; g.minY=g.maxY=37;
    IsoMetaCell c=new IsoMetaCell(41,37); c.info=new LotHeader(41,37);
    for(RoomDef r:rooms) { c.roomList.add(r); c.rooms.put(r.id,r); c.roomByMetaId.put(r.metaId,r); }
    BuildingDef building=new BuildingDef(); building.metaId=987654;building.setKeyId(777);building.alarmed=true;
    building.seen=true;building.hasBeenVisited=true;building.lootRespawnHour=123;building.alarmDecay=456;
    c.buildings.add(building);c.buildingByMetaId.put(building.metaId,building);
    for(RoomDef room:rooms) { building.rooms.add(room);room.building=building; }
    Field f=IsoMetaGrid.class.getDeclaredField("grid"); f.setAccessible(true); f.set(g,new IsoMetaCell[][]{{c}});
    for(String name:new String[]{"width","height"}) { f=IsoMetaGrid.class.getDeclaredField(name);f.setAccessible(true);f.setInt(g,1); }
    return g;
  }
  record Restore(RoomDef room, int flags) {}
  static List<Restore> prepare(IsoMetaGrid grid, ByteBuffer original) {
    // duplicate() defaults BIG_ENDIAN even if the source is LITTLE_ENDIAN.
    ByteBuffer b=original.duplicate().order(original.order());
    check(b.get()==77&&b.get()==69&&b.get()==84&&b.get()==65,"signature"); check(b.getInt()==249,"version");
    int minX=b.getInt(), minY=b.getInt(), maxX=b.getInt(), maxY=b.getInt();
    check(minX==grid.minX&&minY==grid.minY&&maxX==grid.maxX&&maxY==grid.maxY,"bounds");
    List<Restore> pending=new ArrayList<>();
    for(int x=minX;x<=maxX;x++) for(int y=minY;y<=maxY;y++) {
      IsoMetaCell cell=grid.getCellData(x,y);
      List<RoomDef> expected=new ArrayList<>();
      if(cell!=null&&cell.info!=null) for(RoomDef r:cell.roomList) if(!r.userDefined) expected.add(r);
      int count=b.getInt(); check(count==expected.size(),"room count");
      Map<Long,Integer> counts=new HashMap<>();
      for(RoomDef r:expected) counts.merge(r.metaId,1,Integer::sum);
      for(RoomDef r:expected) {
        check(b.getLong()==r.metaId,"ordered room identity");
        int f=Short.toUnsignedInt(b.getShort()); check((f&~15)==0,"unknown flags");
        if(counts.get(r.metaId)>1) pending.add(new Restore(r,f));
      }
      int buildingCount=b.getInt();
      int expectedBuildings=cell!=null&&cell.info!=null?cell.getBuildingCount(true):0;
      check(buildingCount==expectedBuildings&&buildingCount<=b.remaining()/23,"building bounds");
      // Only room flags are interpreted. Native loader owns every building/global section.
      b.position(b.position()+buildingCount*23);
    }
    return pending;
  }
  static final class Session {
    final boolean equalOnly;
    Session() { this(false); }
    Session(boolean equalOnly) { this.equalOnly=equalOnly; }
    byte[] unresolvedRaw;
    void load(IsoMetaGrid grid,ByteBuffer input) {
      if(unresolvedRaw!=null) throw new IllegalStateException("prior unresolved load retained; restart after explicit recovery");
      ByteBuffer raw=input.duplicate(); unresolvedRaw=new byte[raw.remaining()]; raw.get(unresolvedRaw);
      List<Restore> pending=prepare(grid,input);
      if(equalOnly) for(Restore restore:pending)
        check(restore.flags()==pending.get(0).flags(),"historical owner provenance unavailable");
      grid.load(input); // No catch: native exception, position and mark are retained.
      for(Restore restore:pending) setFlags(restore.room(),restore.flags());
      unresolvedRaw=null;
    }
    void maySave() { if(unresolvedRaw!=null) throw new IllegalStateException("unresolved room load; saving blocked"); }
  }
  static ByteBuffer initialFixture(IsoMetaGrid g,ByteOrder order) {
    ByteBuffer b=ByteBuffer.allocate(1024).order(order); b.putLong(0x1122334455667788L); // nonzero position
    g.savePart(b,0,false);
    for(int i=0;i<7;i++) b.putInt(0); // safehouse/nonpvp/faction/designation; three stash lists
    b.putInt(1); zombie.GameWindow.WriteString(b,"AFTER_NATIVE_GLOBAL_SECTIONS");
    b.flip();b.position(8); return b;
  }
  static ByteBuffer save(IsoMetaGrid g,ByteOrder order) {
    ByteBuffer b=ByteBuffer.allocate(1024).order(order);b.putLong(0x1122334455667788L);
    g.savePart(b,0,false);g.savePart(b,1,false);b.flip();b.position(8);return b;
  }
  static ByteBuffer copy(ByteBuffer b) { ByteBuffer c=ByteBuffer.allocate(b.limit()).order(b.order()); for(int i=0;i<b.limit();i++)c.put(b.get(i)); c.flip();c.position(b.position());return c; }
  static void assertUnmodified(ByteBuffer before,ByteBuffer after,int position,ByteOrder order,int expectedMark) {
    check(after.position()==position&&after.order()==order,"prepare changed buffer state");
    for(int i=0;i<before.limit();i++)check(before.get(i)==after.get(i),"input bytes changed");
    int current=after.position(); after.reset();check(after.position()==expectedMark,"prepare changed mark");after.position(current);
  }
  static void reject(ByteBuffer input,IsoMetaGrid target,String what) {
    input.position(3);input.mark();input.position(8);ByteBuffer before=copy(input);Session s=new Session();
    try { s.load(target,input); throw new AssertionError("accepted "+what); }
    catch(AssertionError|BufferUnderflowException e) { check(!("accepted "+what).equals(e.getMessage()),"accepted bad input"); }
    assertUnmodified(before,input,8,input.order(),3);check(s.unresolvedRaw!=null,"lost rejected raw records");
    for(int i=0;i<s.unresolvedRaw.length;i++)check(s.unresolvedRaw[i]==before.get(i+8),"retained raw bytes changed");
    try {s.maySave();throw new AssertionError("save escaped failed prepare");}catch(IllegalStateException expected){}
  }
  static void supported(String resource,String expected) throws Exception {
    try(var input=ClassLoader.getSystemResourceAsStream(resource)) {
      check(input!=null,"native resource missing: "+resource);
      String actual=HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(input.readAllBytes()));
      check(expected.equals(actual),"unsupported native bytecode: "+resource);
    }
  }
  public static void main(String[] args)throws Exception {
    String cache=System.getProperty("pz.test.cache");
    if(cache!=null) zombie.ZomboidFileSystem.instance.setCacheDir(cache);
    supported("zombie/iso/IsoMetaGrid.class","cdd50bb0a393c766d25c9dcbc5f7e929d7e10a6b9c9b95e22c3bae94b3b5b1f9");
    supported("zombie/iso/RoomDef.class","7cf340ad83010a27bb41a7b576d934c795b3a855118fc683ae80dfa02d8be989");
    zombie.core.random.RandStandard.INSTANCE.init();
    StashSystem.allStashes=new ArrayList<>(); StashSystem.possibleStashes=new ArrayList<>();
    IsoMetaGrid warmup=grid(room(107,786643,0),room(306,786643,0));
    warmup.load(initialFixture(warmup,ByteOrder.BIG_ENDIAN));
    int completed=0;
    for(ByteOrder order:new ByteOrder[]{ByteOrder.BIG_ENDIAN,ByteOrder.LITTLE_ENDIAN})
      for(int a=0;a<16;a++)for(int z=0;z<16;z++) {
        IsoMetaGrid source=grid(room(107,786643,a),room(200,123456,5),room(306,786643,z));
        ByteBuffer bytes=save(source,order),raw=copy(bytes),nativeInput=copy(bytes);
        RoomDef first=room(107,786643,0),unique=room(200,123456,0),last=room(306,786643,0);
        IsoMetaGrid target=grid(first,unique,last);
        BuildingDef loadedBuilding=target.getCellData(41,37).buildings.get(0);
        loadedBuilding.setKeyId(0);loadedBuilding.alarmed=false;loadedBuilding.seen=false;
        loadedBuilding.hasBeenVisited=false;loadedBuilding.lootRespawnHour=0;loadedBuilding.alarmDecay=0;
        Session session=new Session();session.load(target,bytes);session.maySave();
        check(bytes.position()==bytes.limit(),"native did not finish buffer");
        check(loadedBuilding.getKeyId()==777&&loadedBuilding.alarmed&&loadedBuilding.seen&&loadedBuilding.hasBeenVisited
          &&loadedBuilding.lootRespawnHour==123&&loadedBuilding.alarmDecay==456,"native building section skipped");
        check(flags(first)==a&&flags(last)==z&&flags(unique)==5,"occurrence restoration mismatch");
        check(first.id==RoomID.makeID(41,37,107)&&last.id==RoomID.makeID(41,37,306)
          &&first.metaId==786643&&last.metaId==786643&&first.building==loadedBuilding&&last.building==loadedBuilding
          &&target.getCellData(41,37).roomByMetaId.get(786643)==last,"candidate changed native identities/index/owners");
        check(RBBasic.getUniqueRDSSpawned().equals(List.of("AFTER_NATIVE_GLOBAL_SECTIONS")),"native suffix not executed");
        IsoMetaGrid nativeGrid=grid(room(107,786643,0),room(200,123456,0),room(306,786643,0));
        nativeGrid.load(nativeInput);
        check(flags(nativeGrid.getCellData(41,37).roomList.get(0))==0
          &&flags(nativeGrid.getCellData(41,37).roomList.get(2))==z,"native duplicate baseline changed");
        check(nativeInput.position()==bytes.position(),"hook changed final native position");
        bytes.reset();nativeInput.reset();check(bytes.position()==8&&nativeInput.position()==8,"hook changed native mark");
        bytes.position(8);ByteBuffer second=save(target,order);
        check(second.equals(raw),"second save changed serialized data");
        RoomDef reloadedFirst=room(107,786643,0),reloadedLast=room(306,786643,0);
        new Session().load(grid(reloadedFirst,room(200,123456,0),reloadedLast),second);
        check(flags(reloadedFirst)==a&&flags(reloadedLast)==z,"second full reload lost separate flags");completed++;
      }
    ByteBuffer valid=save(grid(room(107,786643,1),room(306,786643,14)),ByteOrder.BIG_ENDIAN);
    IsoMetaGrid fresh=grid(room(107,786643,0),room(306,786643,0));
    ByteBuffer b=copy(valid);b.putInt(12,248);reject(b,fresh,"version");
    b=copy(valid);b.putInt(16,42);reject(b,fresh,"bounds");
    b=copy(valid);b.putInt(32,3);reject(b,fresh,"extra count");
    b=copy(valid);b.putInt(32,-1);reject(b,fresh,"negative count");
    b=copy(valid);b.putInt(56,Integer.MAX_VALUE);reject(b,fresh,"building count overflow");
    b=copy(valid);b.putLong(36,999);reject(b,fresh,"identity/order");
    b=copy(valid);b.putShort(44,(short)16);reject(b,fresh,"unknown flag");
    b=copy(valid);b.limit(47);reject(b,fresh,"truncated room");
    ByteBuffer direct=ByteBuffer.allocateDirect(valid.limit());direct.put(valid.duplicate().position(0));
    direct.flip();direct.position(8);new Session().load(fresh,direct.asReadOnlyBuffer());
    RoomDef first=room(107,786643,0),last=room(306,786643,0);IsoMetaGrid failed=grid(first,last);
    b=copy(valid);b.limit(111);ByteBuffer nativeBad=copy(b);Session session=new Session();
    try{session.load(failed,b);throw new AssertionError("native failure ignored");}catch(BufferUnderflowException expected){}
    check(flags(first)==0&&flags(last)==14,"post-load restore ran after native failure");
    check(session.unresolvedRaw!=null,"raw bytes discarded after native failure");
    byte[] retained=session.unresolvedRaw;
    try{session.load(failed,valid);throw new AssertionError("retry discarded unresolved raw");}catch(IllegalStateException expected){}
    check(session.unresolvedRaw==retained,"retry replaced unresolved raw");
    try{session.maySave();throw new AssertionError("save escaped native failure");}catch(IllegalStateException expected){}
    try{fresh.load(nativeBad);throw new AssertionError("native unexpectedly succeeded");}catch(BufferUnderflowException expected){}
    check(b.position()==nativeBad.position()&&b.order()==nativeBad.order(),"failure buffer state differs from native");
    b.reset();nativeBad.reset();check(b.position()==nativeBad.position(),"failure mark differs from native");
    RoomDef stockA=room(107,786643,1),accessA=room(306,786643,14);
    RoomDef accessB=room(107,786643,1),stockB=room(306,786643,14);
    stockA.name=stockB.name="stock-owner";accessA.name=accessB.name="access-owner";
    check(save(grid(stockA,accessA),ByteOrder.BIG_ENDIAN).equals(save(grid(accessB,stockB),ByteOrder.BIG_ENDIAN)),
      "native format unexpectedly encodes semantic owner assignment");
    int equalAccepted=0,unequalRefused=0;
    for(int a=0;a<16;a++)for(int z=0;z<16;z++) {
      ByteBuffer saved=save(grid(room(107,786643,a),room(306,786643,z)),ByteOrder.BIG_ENDIAN);
      Session equalOnly=new Session(true);
      try { equalOnly.load(grid(room(107,786643,0),room(306,786643,0)),saved);equalAccepted++; }
      catch(AssertionError expected) { check(a!=z,"equal states rejected");check(saved.position()==8&&equalOnly.unresolvedRaw!=null,"refusal consumed/lost raw input");unequalRefused++; }
    }
    check(equalAccepted==16&&unequalRefused==240,"equality gate coverage changed");
    RoomDef activeFirst=room(107,786643,0),activeLast=room(306,786643,0);
    IsoMetaGrid active=grid(activeFirst,activeLast);Session equalityAdmission=new Session(true);
    equalityAdmission.load(active,save(grid(room(107,786643,7),room(306,786643,7)),ByteOrder.BIG_ENDIAN));
    setFlags(activeFirst,1);setFlags(activeLast,14);equalityAdmission.maySave();
    ByteBuffer future=save(active,ByteOrder.BIG_ENDIAN);Session futureLoad=new Session(true);
    try {futureLoad.load(grid(room(107,786643,0),room(306,786643,0)),future);
      throw new IllegalStateException("equality gate unexpectedly accepted divergent future save");}
    catch(AssertionError expected) {check(futureLoad.unresolvedRaw!=null,"equality trap lost future records");}
    System.out.println("ROOM_COLLISION_CHECKS_PASS candidate/proof only; no live repair; "+completed+" full native normal-return load/save pairs (all256 per byte order), native building/global sections, native savePart0+1, byte-identical second save, input-state negatives, native late-failure/raw-retention/save-block");
  }
}
