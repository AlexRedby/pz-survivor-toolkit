package toolkit.warehousewalking;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.*;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.network.*;

/** Private stand's initial-protocol fence. Never changes a PacketType setting. */
public final class OrderedCommands {
    static final String MODULE="WarehouseWalkingTest", MARKER="warehouse-walking-ordered.txt";
    static final String MAGIC="PZWarehouseWalkingProfile/ordered-command-v1";
    static final int PRIORITY=1, RELIABILITY=3, MAX_BYTES=524288;
    static final Map<String,Integer> CLIENT_CHANNELS=Map.of("Prepare",0,"Baseline",0,"Normalized",0);
    static final Map<String,Integer> SERVER_CHANNELS=Map.of("CaptureBaseline",0,"Normalize",0,"Prepared",1,"Abortd",1,"Done",1);
    static final Map<String,String> NATIVE_HASHES=Map.ofEntries(
        Map.entry("zombie/network/GameClient.class","99d1778ab2c2627ddcbc04fdbb435461289c3c3075c96cf70eae5c216193352b"),
        Map.entry("zombie/network/GameServer.class","308ee5247dc8bba4df2283d40d753c6839497767b9342a4adeea60e7c08cfacc"),
        Map.entry("zombie/network/PacketTypes$PacketType.class","aa6718ed4e2e33b199734c8cfa4b85a64c193ccc307b2cc4deafe18e0a43d5f5"),
        Map.entry("zombie/core/raknet/UdpConnection.class","9c9bb471ff0c3dccdd0e52a3bb3c770327d02f0ad262187f950e660b2730e763"),
        Map.entry("zombie/core/network/ByteBufferWriter.class","b8f4a1aeace9d91b7b252965a52afe6dfaa32bd2569fbd875eaf5aeb89470b6a"),
        Map.entry("zombie/core/network/ByteBufferReader.class","1c2731f2a49b57d2ad895069d499705f8492e3cb6ac275a8f1163b4940e370ff"),
        Map.entry("zombie/network/TableNetworkUtils.class","e25d6af0dfd36f6f08538463ee63d08f8d0990e64f61e52768c1506841bfe827"),
        Map.entry("zombie/network/packets/SyncClothingPacket.class","09e83606c9de4555802b2171e26df4739a78c787afeb8b2907d46c19be311dff"),
        Map.entry("zombie/network/packets/INetworkPacket.class","616a8d2e86a03952e16c45e756dae12910f637716568a74571defdc1884ce7e9"),
        Map.entry("zombie/network/packets/AddInventoryItemToContainerPacket.class","ebbd2e60b7430b6478498257cae19f21eb9d3e656bb1f03ac1dfa4422d2947f1"),
        Map.entry("zombie/network/packets/RemoveInventoryItemFromContainerPacket.class","9eaceabf11a0fc4b2e0dc843fecfeada2417f76155de03aa059e7dae766fa983"),
        Map.entry("zombie/network/packets/AddItemToMapPacket.class","bd27fa5f01bb071122156d1b915cd8d75e9de62404b68175b83dd9614e58463d"),
        Map.entry("zombie/network/packets/ObjectModDataPacket.class","1d6f806ee95bf6d22f5a69d0535b375a60085039311697eecd6b85dff8e9d9c2"),
        Map.entry("zombie/network/packets/RemoveItemFromSquarePacket.class","13fc4649b4dadba1d03f3bc1cc211f98b96116c7179c33ba681127daf3affb0c"));
    private static boolean nativeVerified;
    private OrderedCommands() {}
    static void require(boolean condition,String reason){if(!condition)throw new IllegalStateException("Private ordered warehouse command: "+reason);}
    static String digest(String resource)throws Exception {
        try(var input=OrderedCommands.class.getClassLoader().getResourceAsStream(resource)) {
            require(input!=null,"missing class resource");
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(input.readAllBytes()));
        }
    }
    static void verifyNative()throws Exception {
        if(nativeVerified)return;
        for(var entry:NATIVE_HASHES.entrySet())require(digest(entry.getKey()).equals(entry.getValue()),"unsupported native bytecode: "+entry.getKey());
        nativeVerified=true;
    }
    static void selection(KahluaTable value) {
        require(value!=null&&"warehouse-walking".equals(value.rawget("suite"))&&"mp".equals(value.rawget("kind"))
            &&"toolkit".equals(value.rawget("mode")),"selection differs");
        Object cases=value.rawget("cases");
        require(cases instanceof KahluaTable rows&&rows.len()==1&&"walk".equals(rows.rawget(1.0)),"case differs");
    }
    static String marker(Path cache,List<String> lines,String ownDigest) {
        require(lines.size()==4&&MAGIC.equals(lines.get(0))&&cache.toString().equals(lines.get(1))
            &&ownDigest.equals(lines.get(3)),"owned cache/class marker differs");
        String role=lines.get(2);require(Set.of("server","client1","client2").contains(role),"marker role differs");return role;
    }
    static String smallFile(Path path)throws IOException {
        require(Files.isRegularFile(path,LinkOption.NOFOLLOW_LINKS)&&Files.size(path)<=2048,"private marker missing/unbounded");
        return Files.readString(path).trim();
    }
    static void ownership(boolean server,String role,String username,boolean context,boolean owned,boolean loopback,boolean coopHost) {
        require(context&&owned&&loopback,"native role/actor/loopback ownership differs");
        require(Set.of("client1","client2").contains(username),"actor role differs");
        // Menu Host deliberately launches its separate coop JVM from client1's
        // private cache. It must prove both native coop and the live selection;
        // merely copying a client marker cannot authorize a server process.
        require(server?("server".equals(role)||coopHost&&"client1".equals(role)):role.equals(username),"cache/actor role differs");
    }
    static boolean coopHost(boolean server,boolean nativeCoop,Object options) {
        return server&&nativeCoop&&options instanceof KahluaTable selected&&Boolean.TRUE.equals(selected.rawget("mp_host"));
    }
    private static UdpConnection gate(boolean server,IsoPlayer player)throws Exception {
        require(LuaManager.thread!=null&&LuaManager.thread.debugOwnerThread==Thread.currentThread(),"Lua owner thread required");
        require(player!=null,"actor missing");
        Object config=LuaManager.env==null?null:LuaManager.env.rawget("QueueTestSelection");
        selection(config instanceof KahluaTable table?table:null);
        Path cache=Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath(),lua=cache.resolve("Lua");
        String role=marker(cache,List.of(smallFile(lua.resolve(MARKER)).split("\\R")),digest("toolkit/warehousewalking/OrderedCommands.class"));
        require(role.equals(smallFile(lua.resolve("smoke-user.txt")))&&"toolkit".equals(smallFile(lua.resolve("queue-mode.txt")))
            &&"warehouse-walking".equals(smallFile(lua.resolve("queue-scenario.txt")))&&"mp".equals(smallFile(lua.resolve("queue-health-kind.txt")))
            &&"walk".equals(smallFile(lua.resolve("queue-health-start.txt"))),"private selection markers differ");
        UdpConnection connection=server?GameServer.getConnectionFromPlayer(player):GameClient.connection;
        boolean owned=false;
        if(server&&GameServer.IDToPlayerMap.get(player.getOnlineID())==player&&connection!=null) {
            for(int index=0;index<4;index++)if(connection.getPlayerAt(index)==player)owned=true;
        } else if(!server&&player.isLocalPlayer()&&player.getPlayerNum()>=0&&player.getPlayerNum()<IsoPlayer.players.length
            &&IsoPlayer.players[player.getPlayerNum()]==player&&GameClient.IDToPlayerMap.get(player.getOnlineID())==player)owned=true;
        InetSocketAddress address=connection==null?null:connection.getInetSocketAddress();
        Object options=((KahluaTable)config).rawget("options");
        boolean coopHost=coopHost(server,GameServer.coop,options);
        ownership(server,role,player.getUsername(),server?GameServer.server&&!GameClient.client:GameClient.client&&!GameServer.server,
            owned,address!=null&&address.getAddress()!=null&&address.getAddress().isLoopbackAddress(),coopHost);
        verifyNative();return connection;
    }
    private static boolean token(Object value){return value instanceof String text&&text.length()<128&&text.matches("warehouse-walking:[0-9]+:-?[0-9]+");}
    static void protocol(boolean server,String actorRole,String module,String command,KahluaTable args) {
        require(MODULE.equals(module)&&(server?SERVER_CHANNELS:CLIENT_CHANNELS).containsKey(command),"module/initial command differs");
        require(args!=null,"initial payload missing");
        if(!server) {
            require("walk".equals(args.rawget("case"))&&Double.valueOf(1).equals(args.rawget("index")),"client case/index differs");
            if("Prepare".equals(command))require(args.rawget("token")==null,"Prepare token must be absent");
            else {
                require(token(args.rawget("token"))&&args.rawget("baseline") instanceof KahluaTable,"baseline/token differs");
                if("Normalized".equals(command))require(args.rawget("proof") instanceof KahluaTable proof
                    &&Boolean.TRUE.equals(proof.rawget("rootEmpty"))&&Boolean.TRUE.equals(proof.rawget("equipmentEmpty"))
                    &&Boolean.TRUE.equals(proof.rawget("originalsStashed")),"normalization proof differs");
            }
        } else if(Set.of("CaptureBaseline","Abortd","Done").contains(command))require(token(args.rawget("token")),"capture/cleanup token differs");
        else require(actorRole.equals(args.rawget("role"))&&args.rawget("ids") instanceof KahluaTable ids&&token(ids.rawget("token")),"server role/token differs");
    }
    static void data(KahluaTable table,IdentityHashMap<KahluaTable,Boolean> path,int[] entries,int depth) {
        require(depth<=16&&path.put(table,Boolean.TRUE)==null,"cyclic/deep payload");
        var values=table.iterator();
        while(values.advance()) {
            require(++entries[0]<=65536,"payload entry bound exceeded");
            Object key=values.getKey(),value=values.getValue();
            require((key instanceof String text&&!text.isEmpty()&&text.length()<=256)
                ||key instanceof Double number&&Double.isFinite(number),"unsupported payload key");
            require(TableNetworkUtils.canSave(key,value),"native serializer cannot preserve payload");
            if(value instanceof KahluaTable child)data(child,path,entries,depth+1);
            else require(value instanceof Boolean||value instanceof Double number&&Double.isFinite(number)
                ||value instanceof String text&&text.length()<=16384,"unsupported payload value");
        }
        path.remove(table);
    }
    static ByteBuffer encode(boolean server,int playerNum,String module,String command,KahluaTable args)throws IOException {
        if(args!=null)data(args,new IdentityHashMap<>(),new int[1],0);
        ByteBuffer bytes=ByteBuffer.allocate(MAX_BYTES);var writer=new ByteBufferWriter(bytes);
        PacketTypes.PacketType.ClientCommand.doPacket(writer);
        if(!server){require(playerNum>=-1&&playerNum<4,"native player index differs");writer.putByte((byte)playerNum);}
        writer.putUTF(module);writer.putUTF(command);boolean present=args!=null&&!args.isEmpty();writer.putBoolean(present);
        if(present)TableNetworkUtils.save(args,writer);
        bytes.flip();return bytes;
    }
    static int channel(boolean server,String command) {
        Integer channel=(server?SERVER_CHANNELS:CLIENT_CHANNELS).get(command);
        require(channel!=null,"command channel absent");return channel;
    }
    static void dispatch(IConnection connection,ByteBuffer encoded,int channel) {
        require(channel==0||channel==1,"command channel differs");
        try {
            ByteBufferWriter writer=connection.startPacket();writer.put(encoded);
            connection.endPacket(PRIORITY,RELIABILITY,(byte)channel);
        } catch(Throwable error) {
            connection.cancelPacket();throw error;
        }
    }
    private static void send(boolean server,IsoPlayer player,String module,String command,KahluaTable args)throws Exception {
        UdpConnection connection=gate(server,player);protocol(server,player.getUsername(),module,command,args);
        // Validate and seal the entire native payload before acquiring the live
        // network buffer. Serialization cannot dispatch a truncated packet.
        ByteBuffer encoded=encode(server,player.getPlayerNum(),module,command,args);dispatch(connection,encoded,channel(server,command));
    }
    @LuaMethod(name="warehouseWalkingOrderedClient",global=true)
    public static boolean client(IsoPlayer player,String module,String command,KahluaTable args)throws Exception{send(false,player,module,command,args);return true;}
    @LuaMethod(name="warehouseWalkingOrderedServer",global=true)
    public static boolean server(IsoPlayer player,String module,String command,KahluaTable args)throws Exception{send(true,player,module,command,args);return true;}
}
