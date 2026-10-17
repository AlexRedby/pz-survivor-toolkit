package net.alexredby.visualtrace;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.concurrent.atomic.AtomicInteger;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.skinnedmodel.visual.ItemVisual;
import zombie.core.skinnedmodel.visual.ItemVisuals;
import zombie.inventory.InventoryItem;
import zombie.network.GameServer;
import zombie.network.IConnection;
import zombie.network.fields.character.PlayerID;

public final class Main {
    public static final boolean SUPPORTED = supports("zombie/network/packets/SyncVisualsPacket.class", "360a8b23b17e4e307fa58116eccce8b3218c21ec8a8ba400bcce240151638c9e") &&
        supports("zombie/network/packets/SyncClothingPacket.class", "09e83606c9de4555802b2171e26df4739a78c787afeb8b2907d46c19be311dff") &&
        supports("zombie/characters/IsoGameCharacter$Bandages.class", "bb87836b717355811e6f699377896918b9d4f4d050a5ad7bc1f1a35a70ebdedd") &&
        supports("zombie/network/fields/character/PlayerID.class", "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56");
    public static final AtomicInteger lines = new AtomicInteger();
    public static void main(String[] args) { System.out.println("[SyncVisualsTrace] enabled supported=" + SUPPORTED); }
    public static boolean supports(String path, String hash) {
        try (var in = Main.class.getClassLoader().getResourceAsStream(path)) {
            return in != null && HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(in.readAllBytes())).equals(hash);
        } catch (Throwable error) { return false; }
    }
    public static String q(Object value) {
        if(value==null)return "null";
        return "\""+value.toString().replace("\\","\\\\").replace("\"","\\\"").replace("\n","\\n").replace("\r","\\r").replace("\t","\\t")+"\"";
    }
    public static void log(String kind, String fields) {
        if (!SUPPORTED) return;
        int n=lines.incrementAndGet();
        if(n<=30000)System.out.println("[SYNC_VISUALS_TRACE] {\"seq\":"+n+",\"timeMs\":"+System.currentTimeMillis()+",\"kind\":"+q(kind)+",\"side\":"+q(GameServer.server?"server":"client")+",\"thread\":"+q(Thread.currentThread().getName())+","+fields+"}");
        else if(n==30001)System.out.println("[SYNC_VISUALS_TRACE] {\"kind\":\"lineCap\"}");
    }
    public static String item(InventoryItem i) {
        return i==null?"null":"{\"id\":"+i.getID()+",\"type\":"+q(i.getFullType())+",\"object\":"+System.identityHashCode(i)+",\"assetReady\":"+ready(i)+"}";
    }
    public static String ready(InventoryItem i) { try { var ci=i.getClothingItem();return ci==null?"null":Boolean.toString(ci.isReady()); }catch(Throwable e){return "null";} }
    public static String visual(ItemVisual v) {
        return v==null?"null":"{\"type\":"+q(v.getItemType())+",\"object\":"+System.identityHashCode(v)+",\"item\":"+item(v.getInventoryItem())+"}";
    }
    public static String visuals(ItemVisuals list) {
        if(list==null)return "null";
        StringBuilder s=new StringBuilder("[");
        for(int i=0;i<list.size();i++){if(i>0)s.append(',');s.append(visual(list.get(i)));}
        return s.append(']').toString();
    }
    public static String player(IsoGameCharacter c) {
        if(c==null)return "null";
        StringBuilder s=new StringBuilder("{");
        if(c instanceof IsoPlayer p)s.append("\"onlineId\":").append(p.onlineId).append(",\"username\":").append(q(p.getUsername())).append(",\"local\":").append(p.isLocalPlayer()).append(",\"remote\":").append(p.remote).append(',');
        s.append("\"worn\":[");var w=c.getWornItems();
        if(w!=null)for(int i=0;i<w.size();i++){if(i>0)s.append(',');var wi=w.get(i);s.append("{\"location\":").append(q(wi.getLocation())).append(",\"item\":").append(item(wi.getItem())).append(",\"visual\":").append(visual(Accessor.tryGet(wi.getItem(),"visual",(ItemVisual)null))).append('}');}
        s.append(']');
        if(c instanceof IsoPlayer p && p.remote && !GameServer.server)s.append(",\"remoteVisuals\":").append(visuals(p.getItemVisuals()));
        return s.append('}').toString();
    }
    public static IsoPlayer packetPlayer(Object packet) {var id=Accessor.tryGet(packet,"playerId",(PlayerID)null);return id==null?null:id.getPlayer();}
    public static String wire(ByteBuffer bb,int start,int end) {
        try{var copy=bb.duplicate().order(bb.order());copy.position(start);copy.limit(end);byte[] bytes=new byte[copy.remaining()];copy.get(bytes);return "{\"bytes\":"+bytes.length+",\"header\":"+q(HexFormat.of().formatHex(bytes,0,Math.min(bytes.length,8)))+",\"sha256\":"+q(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)))+"}";}catch(Throwable e){return "{\"error\":"+q(e)+"}";}
    }
    public static String incoming(ByteBufferReader r,IConnection connection) {
        try{var copy=new ByteBufferReader(r.bb.duplicate().order(r.bb.order()));var id=new PlayerID();id.parse(copy,connection);int count=copy.getByte();return "\"wireId\":"+id.getID()+",\"count\":"+count+",\"player\":"+player(id.getPlayer())+",\"wire\":"+wire(r.bb,r.bb.position(),r.bb.limit());}catch(Throwable e){return "\"error\":"+q(e);}
    }
    public static String packet(Object p) {return "\"player\":"+player(packetPlayer(p))+",\"parsedCount\":"+Accessor.tryGet(p,"itemVisualsSize",Integer.MIN_VALUE)+",\"packetVisuals\":"+visuals(Accessor.tryGet(p,"itemVisuals",(ItemVisuals)null));}
    public static String descriptions(Object p) {
        Object list=Accessor.tryGet(p,"items",(Object)null);if(!(list instanceof java.util.List<?> items))return "null";
        StringBuilder s=new StringBuilder("[");for(Object i:items){if(s.length()>1)s.append(',');s.append("{\"id\":").append(Accessor.tryGet(i,"itemId",Integer.MIN_VALUE)).append(",\"type\":").append(q(Accessor.tryGet(i,"itemType",(Object)null))).append(",\"location\":").append(q(Accessor.tryGet(i,"location",(Object)null))).append('}');}return s.append(']').toString();
    }

    @Patch(className="zombie.network.packets.SyncVisualsPacket", methodName="write",warmUp=true,strictMatch=true)
    public static class VisualWrite {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ByteBufferWriter w,@Patch.Local("traceStart") int start) {start=w.bb.position();}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This Object p,@Patch.Argument(0) ByteBufferWriter w,@Patch.Local("traceStart") int start,@Patch.Thrown Throwable error) {log("visual.write",packet(p)+",\"wire\":"+wire(w.bb,start,w.bb.position())+",\"error\":"+q(error));}
    }
    @Patch(className="zombie.network.packets.SyncVisualsPacket",methodName="parse",warmUp=true,strictMatch=true)
    public static class VisualParse {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ByteBufferReader r,@Patch.Argument(1) IConnection c,@Patch.Local("traceStart") int start) {start=r.bb.position();try{log("visual.parse.enter",incoming(r,c));}catch(Throwable ignored){}}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This Object p,@Patch.Argument(0) ByteBufferReader r,@Patch.Local("traceStart") int start,@Patch.Thrown Throwable error) {log("visual.parse.exit",packet(p)+",\"consumed\":"+(r.bb.position()-start)+",\"remaining\":"+r.bb.remaining()+",\"error\":"+q(error));}
    }
    @Patch(className="zombie.network.packets.SyncClothingPacket",methodName="parse",warmUp=true,strictMatch=true)
    public static class ClothingParse {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) ByteBufferReader r,@Patch.Argument(1) IConnection c) {try{log("clothing.parse.enter",incoming(r,c));}catch(Throwable ignored){}}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This Object p,@Patch.Thrown Throwable error) {log("clothing.parse.exit","\"player\":"+player(packetPlayer(p))+",\"descriptions\":"+descriptions(p)+",\"error\":"+q(error));}
    }
    @Patch(className="zombie.network.packets.SyncClothingPacket",methodName="process",warmUp=true,strictMatch=true)
    public static class ClothingProcess {
        @Patch.OnEnter public static void enter(@Patch.This Object p) {try{log("clothing.process.enter","\"player\":"+player(packetPlayer(p)));}catch(Throwable ignored){}}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.This Object p,@Patch.Thrown Throwable error) {log("clothing.process.exit","\"player\":"+player(packetPlayer(p))+",\"error\":"+q(error));}
    }
    @Patch(className="zombie.characters.IsoGameCharacter$Bandages",methodName="addBandageModel",warmUp=true,strictMatch=true)
    public static class BandageAdd {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) IsoGameCharacter c,@Patch.Local("traceBefore") String before) {try{before=player(c);}catch(Throwable ignored){}}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) IsoGameCharacter c,@Patch.Argument(1) String type,@Patch.Local("traceBefore") String before,@Patch.Thrown Throwable error) {String after=player(c);if(error!=null || !after.equals(before)) log("bandage.add","\"type\":"+q(type)+",\"before\":"+before+",\"player\":"+after+",\"error\":"+q(error));}
    }
    @Patch(className="zombie.characters.IsoGameCharacter$Bandages",methodName="removeBandageModel",warmUp=true,strictMatch=true)
    public static class BandageRemove {
        @Patch.OnEnter public static void enter(@Patch.Argument(0) IsoGameCharacter c,@Patch.Local("traceBefore") String before) {try{before=player(c);}catch(Throwable ignored){}}
        @Patch.OnExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Patch.Argument(0) IsoGameCharacter c,@Patch.Argument(1) String type,@Patch.Local("traceBefore") String before,@Patch.Thrown Throwable error) {String after=player(c);if(error!=null || !after.equals(before)) log("bandage.remove","\"type\":"+q(type)+",\"before\":"+before+",\"player\":"+after+",\"error\":"+q(error));}
    }
}
