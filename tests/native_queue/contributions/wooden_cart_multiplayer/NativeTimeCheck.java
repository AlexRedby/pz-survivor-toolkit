import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import net.alexredby.cartlab.Main;

/** Standalone native serialization/helper check. No game, transport, settings or save is started. */
public final class NativeTimeCheck {
    public static class Owner extends zombie.characters.IsoPlayer {
        boolean local;
        zombie.characters.NetworkPlayerAI ai;
        String motion,action;
        Owner(){super(null,null,0,0,0);}
        @Override public String getUsername(){return "client1";}
        @Override public short getOnlineID(){return 7;}
        @Override public boolean isLocalPlayer(){return local;}
        @Override public zombie.characters.NetworkPlayerAI getNetworkCharacterAI(){return ai;}
        @Override public String getVariableString(String key){return "ToolkitCartPose".equals(key)?motion:"ToolkitCartActionPose".equals(key)?action:null;}
    }
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    @SuppressWarnings("unchecked")
    private static <K,V> Main.NativeWeakMap<K,V> map(String name)throws Exception {
        var field=Main.class.getDeclaredField(name);field.setAccessible(true);return (Main.NativeWeakMap<K,V>)field.get(null);
    }
    private static void rejectSpan(ByteBuffer buffer,int begin,int end) {
        try{Main.nativeTimeBody(buffer,begin,end);throw new AssertionError("Invalid body span accepted");}
        catch(IllegalArgumentException expected){}
    }
    private static void checkAdmissionNumbers(java.nio.file.Path sources)throws Exception {
        var platform=se.krka.kahlua.j2se.J2SEPlatform.getInstance();
        var environment=platform.newEnvironment();
        var thread=new se.krka.kahlua.vm.KahluaThread(platform,environment);thread.debugOwnerThread=Thread.currentThread();
        String probe=java.nio.file.Files.readString(sources.resolve("action-admission.lua"));
        String functions=probe.substring(probe.indexOf("local function integerText"),probe.indexOf("local function emit"));
        String json=java.nio.file.Files.readString(sources.resolve("json.lua"));
        String script="local J=(function()\n"+json+"\nend)()\n"+functions
            +"\nlocal mono,maximum,wall=...;return encodeRow({monoNs=mono,maximum=maximum,negative=-maximum,wallMs=wall,zero=0,cart=-2147483648})";
        var closure=se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(script,"cart-admission-numbers",environment);
        Object[] result=thread.pcall(closure,new Object[]{253716934852789d,9007199254740991d,1792720134545d});
        check(result.length==2 && Boolean.TRUE.equals(result[0]),"Actual Kahlua admission encoder failed: "+Arrays.toString(result));
        String encoded=(String)result[1];
        for(String exact:new String[]{"\"monoNs\":253716934852789","\"maximum\":9007199254740991","\"negative\":-9007199254740991", "\"wallMs\":1792720134545","\"zero\":0","\"cart\":-2147483648"})
            check(encoded.contains(exact),"Actual Kahlua admission counter lost precision: "+encoded);
    }
    /** Native copy normalizes a remote owner; the parsed packet alone retains the signed wire slot. */
    private static void checkNativeActionOwnerCopy(sun.misc.Unsafe unsafe)throws Exception {
        boolean server=zombie.network.GameServer.server,client=zombie.network.GameClient.client;
        try {
            zombie.network.GameServer.server=true;zombie.network.GameClient.client=false;
            var remote=(Owner)unsafe.allocateInstance(Owner.class);remote.local=false;remote.onlineId=7;remote.playerIndex=0;
            // isLocal() is final and consults the native ECS component, not just isLocalPlayer().
            // Construct only the in-memory owner/component association, without an AI/world lifecycle.
            var components=zombie.iso.IsoObject.class.getDeclaredField("ecsComponentMap");components.setAccessible(true);
            components.set(remote,new java.util.HashMap<Class<? extends zombie.characters.ecs.ECSComponent>,zombie.characters.ecs.ECSComponent>());
            var network=(zombie.characters.component.NetworkPlayerComponent)unsafe.allocateInstance(zombie.characters.component.NetworkPlayerComponent.class);
            var componentClass=zombie.characters.ecs.ECSComponent.class.getDeclaredField("ecsClass");componentClass.setAccessible(true);
            componentClass.set(network,zombie.characters.ecs.ECSComponent.getECSClass(zombie.characters.component.NetworkPlayerComponent.class));
            network.setECSOwnerEntity(remote);
            check(network.isRemote() && !remote.isLocal(),"Native remote owner fixture is local");
            var actionClass=Class.forName("zombie.core.Action");
            var actionOwner=actionClass.getDeclaredField("playerId");actionOwner.setAccessible(true);
            var actionID=actionClass.getDeclaredField("id");actionID.setAccessible(true);
            var actionState=actionClass.getDeclaredField("state");actionState.setAccessible(true);
            var player=zombie.network.fields.character.PlayerID.class.getDeclaredField("player");player.setAccessible(true);
            var packet=new zombie.network.packets.NetTimedActionPacket();
            var source=(zombie.network.fields.character.PlayerID)actionOwner.get(packet);
            source.setID((short)7);source.setPlayerIndex((byte)0);player.set(source,remote);
            actionID.setByte(packet,(byte)1);actionState.set(packet,zombie.core.Transaction.TransactionState.Request);
            packet.type="ToolkitWoodCartPickup";packet.action=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();
            var actual=new zombie.core.NetTimedAction();actual.copyFrom(packet);
            var copied=(zombie.network.fields.character.PlayerID)actionOwner.get(actual);
            check(source.getPlayerIndex()==0,"Native action copy changed the packet's signed wire slot");
            check(copied.getPlayerIndex()==-1,"Native action copy retained the source slot for a remote server actor");
            check(copied.getPlayer()==remote && copied.getID()==7,"Native action copy lost exact actor/online ID");
            check(actionID.getByte(actual)==1 && actionState.get(actual)==zombie.core.Transaction.TransactionState.Request,"Native action copy lost transaction/state");
            check(actual.action==packet.action && actual.action.rawget("netAction")==actual,"Native action table did not rebind to the actual copied action");
        } finally {zombie.network.GameServer.server=server;zombie.network.GameClient.client=client;}
    }
    public static void main(String[] args)throws Exception {
        checkAdmissionNumbers(java.nio.file.Path.of(args[0]));
        check(Main.actionAdmissionKind("ToolkitWoodCartPickup") && !Main.actionAdmissionKind("ISWalkToTimedAction"),"Unrelated action admitted");
        check(Main.actionAdmissionCanAccept("pending","Accept",true,true,true,"exact-token"),"Actual accepted action refused");
        check(!Main.actionAdmissionCanAccept("terminal","Accept",true,true,true,"exact-token"),"Retired action reopened");
        check(!Main.actionAdmissionCanAccept("pending","Request",true,true,true,"exact-token"),"Pre-Accept start admitted");
        check(!Main.actionAdmissionCanAccept("pending","Accept",false,true,true,"exact-token")
            && !Main.actionAdmissionCanAccept("pending","Accept",true,false,true,"exact-token")
            && !Main.actionAdmissionCanAccept("pending","Accept",true,true,false,"exact-token")
            && !Main.actionAdmissionCanAccept("pending","Accept",true,true,true,null),"Missing authority/binding/queue/token admitted");
        check(Main.actionAdmissionInteger(Integer.MIN_VALUE) && Main.actionAdmissionInteger(Integer.MAX_VALUE)
            && !Main.actionAdmissionInteger(Double.NaN) && !Main.actionAdmissionInteger(.5)
            && !Main.actionAdmissionInteger(2147483648d),"Native constructor integer domain changed");
        for(var order:new ByteOrder[]{ByteOrder.BIG_ENDIAN,ByteOrder.LITTLE_ENDIAN}) {
            var header=ByteBuffer.allocate(16).order(order);header.position(4);header.put((byte)134).putShort((short)321);
            header.limit(7).position(4);header.mark();byte[] original=header.array().clone();
            check(Main.leaseControlHeader(header)==321,"Lease command header/order lost");
            check(header.position()==4 && header.limit()==7 && header.order()==order,"Lease header changed cursor/limit/order");
            header.reset();check(header.position()==4 && Arrays.equals(original,header.array()),"Lease header changed mark/content");
            header.limit(6);check(Main.leaseControlHeader(header)==-1,"Truncated lease header accepted");
            header.limit(7);header.put(4,(byte)1);check(Main.leaseControlHeader(header)==-1,"Foreign header accepted");
        }
        var buffer=ByteBuffer.allocate(300).order(ByteOrder.LITTLE_ENDIAN);
        buffer.putInt(0x01020304).putFloat(-0.0f).putInt(0x7fc01234);buffer.position(2);buffer.mark();
        byte[] before=buffer.array().clone();var body=Main.nativeTimeBody(buffer,4,12);
        check(body.hex().equals("000000803412c07f"),"Raw float bits/order lost");
        check(body.bytes()==8 && body.order().equals("LITTLE_ENDIAN") && body.sha().length()==64,"Body metadata");
        check(buffer.position()==2 && buffer.limit()==300 && buffer.order()==ByteOrder.LITTLE_ENDIAN,"Original cursor/order changed");
        buffer.reset();check(buffer.position()==2 && Arrays.equals(before,buffer.array()),"Original mark/content changed");
        var direct=ByteBuffer.allocateDirect(16);direct.putLong(0x0102030405060708L);direct.position(0);
        check(Main.nativeTimeBody(direct,0,8).hex().equals("0102030405060708"),"Direct body unsupported");
        check(Main.nativeTimeBody(buffer,4,12).equals(body),"Repeated payload fingerprint changed");
        rejectSpan(buffer,-1,2);rejectSpan(buffer,2,1);rejectSpan(buffer,0,257);rejectSpan(buffer,0,301);
        var identities=new Main.NativeWeakMap<Object,Long>();
        Object first=new Object(){@Override public boolean equals(Object ignored){return true;}@Override public int hashCode(){return 1;}};
        Object second=new Object(){@Override public boolean equals(Object ignored){return true;}@Override public int hashCode(){return 1;}};
        identities.put(first,1L);identities.put(second,2L);
        check(identities.get(first)==1L && identities.get(second)==2L,"Identity map used equality");
        identities.remove(first);check(identities.get(first)==null && identities.get(second)==2L,"Identity removal");
        long a=Main.nativeTimeIdentity(first,true),b=Main.nativeTimeIdentity(second,true),c=Main.nativeTimeIdentity(first,false);
        check(a>0 && b>a && c>b && Main.nativeTimeIdentity(first,true)==a,"Epoch ordinals reused");
        // Initialize native static facilities only. Unsafe avoids creating a world/player lifecycle.
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        Class.forName("zombie.characters.IsoGameCharacter");Class.forName("zombie.network.GameClient");
        var unsafeField=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");unsafeField.setAccessible(true);
        var unsafe=(sun.misc.Unsafe)unsafeField.get(null);checkNativeActionOwnerCopy(unsafe);
        var owner=(Owner)unsafe.allocateInstance(Owner.class);
        owner.local=true;owner.motion="motion-before";owner.action="action-before";
        owner.ai=(zombie.characters.NetworkPlayerAI)unsafe.allocateInstance(zombie.characters.NetworkPlayerAI.class);
        owner.ai.prediction=new zombie.network.fields.character.Prediction();
        zombie.network.GameServer.server=false;zombie.network.GameClient.client=true;
        // Helpers are checked without opening timeline output or relying on any cache settings.
        var closing=Main.class.getDeclaredField("timelineClosing");closing.setAccessible(true);closing.setBoolean(null,true);
        var packet=new zombie.network.packets.character.PlayerPacket();
        var playerField=zombie.network.fields.character.PlayerID.class.getDeclaredField("player");playerField.setAccessible(true);playerField.set(packet.id,owner);
        packet.id.setID((short)7);packet.id.setPlayerIndex((byte)0);
        packet.prediction.type=1;packet.prediction.x=12.5f;packet.prediction.y=15.5f;packet.prediction.z=1;
        packet.prediction.direction=-0.0f;packet.prediction.moveDirection=.5f;packet.prediction.speed=.75f;packet.prediction.distance=3;
        var source=Main.nativeTimeSourceEnter(packet,owner);check(source!=null,"Explicit timeline opt-in required");
        owner.motion="motion-after";owner.action="action-after";Main.nativeTimeSourceExit(packet,owner,source,null);
        Main.NativeSource frozen=NativeTimeCheck.<zombie.network.packets.character.PlayerPacket,Main.NativeSource>map("nativeTimeSources").get(packet);
        check(frozen.generation()==source.generation() && frozen.end()>=frozen.begin(),"Source sample interval");
        check(frozen.motionBegin().equals("motion-before") && frozen.motionEnd().equals("motion-after") && frozen.actionBegin().equals("action-before") && frozen.actionEnd().equals("action-after"),"Semantic set sample not frozen");
        var wire=ByteBuffer.allocate(256);wire.position(2);var wireWriter=new zombie.core.network.ByteBufferWriter(wire);
        zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.doPacket(wireWriter);
        int begin=wire.position();packet.write(wireWriter);
        int end=wire.position();var nativeBody=Main.nativeTimeBody(wire,begin,end);check(nativeBody.bytes()==32,"Native wire layout boundary");
        var repeated=Main.nativeTimeSourceEnter(packet,owner);Main.nativeTimeSourceExit(packet,owner,repeated,null);
        check(repeated.generation()!=source.generation(),"Repeated payload conflated source generations");
        var wire2=ByteBuffer.allocate(256);packet.write(new zombie.core.network.ByteBufferWriter(wire2));
        check(nativeBody.equals(Main.nativeTimeBody(wire2,0,wire2.position())),"Source tracing changed native wire");
        // Exact destination writer mapping; no transport call is made.
        var connection=(zombie.core.raknet.UdpConnection)unsafe.allocateInstance(zombie.core.raknet.UdpConnection.class);
        zombie.network.GameClient.connection=connection;
        var writer=new zombie.core.network.ByteBufferWriter(wire);
        Main.nativeTimeStartActive(connection,writer,null);
        Main.nativeTimeWrite(packet,writer,begin,null);
        var active=Main.nativeTimeFinishEnter(connection);check(active!=null && active.send()!=null,"Missing active native send");
        Main.nativeTimeStartActive(connection,writer,null); // Simulates next lock owner before old exit advice.
        Main.nativeTimeFinish(connection,active,true,null);
        check(Main.nativeTimeFinishEnter(connection)!=null,"Old completion removed new send");
        // Acceptance requires exact persistent destination/source inside exact AI/packet scope.
        owner.local=false;
        zombie.network.GameClient.IDToPlayerMap.put((short)7,owner);
        var data=new zombie.network.ZomboidNetData();
        var inputBuffer=wire.duplicate();inputBuffer.position(begin);inputBuffer.limit(end);
        var input=new zombie.core.network.ByteBufferReader(inputBuffer);long ingressMono=System.nanoTime();
        data.read(zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),input,connection);
        Main.nativeTimeIngressRead(data,zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),input,connection,begin,end,ingressMono,null);
        // VehicleID.parse resolves the wire ID through this ordinary in-memory manager.
        // Its constructor initializes maps/timers only; no world, socket or update loop starts.
        zombie.vehicles.VehicleManager.instance=new zombie.vehicles.VehicleManager();
        var parsed=new zombie.network.packets.character.PlayerPacket();int parseBegin=data.buffer.position();
        parsed.parse(data.buffer,connection);int parseEnd=data.buffer.position();
        Main.nativeTimeParse(parsed,data.buffer,connection,parseBegin,null);
        check(data.buffer.position()==parseEnd && Main.nativeTimeBody(data.buffer.bb,parseBegin,parseEnd).equals(nativeBody),"Parsed span changed native cursor/body");
        Main.NativeReceipt receipt=NativeTimeCheck.<zombie.network.packets.character.PlayerPacket,Main.NativeReceipt>map("nativeTimeReceipts").get(parsed);
        check(receipt!=null && receipt.ingress()>0 && receipt.type()==zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),"Ingress receipt not associated by exact reader");
        Main.nativeTimeIngressReset(data);data.reset();
        check(NativeTimeCheck.<zombie.core.network.ByteBufferReader,Main.NativeIngress>map("nativeTimeIngress").get(data.buffer)==null,"Pooled reader retained ingress generation");
        inputBuffer.position(begin);ingressMono=System.nanoTime();data.read(zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),input,connection);
        Main.nativeTimeIngressRead(data,zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),input,connection,begin,end,ingressMono,null);
        check(NativeTimeCheck.<zombie.core.network.ByteBufferReader,Main.NativeIngress>map("nativeTimeIngress").get(data.buffer).generation()!=receipt.ingress(),"Pooled reuse retained ingress generation");
        var scope=Main.nativeTimeCopyEnter(owner.ai,parsed);check(scope!=null,"Exact AI copy scope unavailable");
        Main.nativeTimeCopied(new zombie.network.fields.character.Prediction(),parsed.prediction,null);
        Main.nativeTimeCopied(owner.ai.prediction,parsed.prediction,new IllegalStateException("synthetic copy failure"));
        check(Main.timelineNativeSnapshot(owner).contains("\"nativeReceiveGeneration\":0"),"Foreign/failed copy accepted");
        owner.ai.prediction.copy(parsed.prediction);Main.nativeTimeCopied(owner.ai.prediction,parsed.prediction,null);Main.nativeTimeCopyExit(scope);
        String generation="\"nativeReceiveGeneration\":"+receipt.generation();
        check(Main.timelineNativeSnapshot(owner).contains(generation),"Exact copy not accepted");
        Main.nativeTimeCopied(owner.ai.prediction,parsed.prediction,null);
        var frozenSnapshot=Main.timelineNativeSnapshot(owner);
        owner.ai.prediction=new zombie.network.fields.character.Prediction();
        check(Main.timelineNativeSnapshot(owner).contains("\"nativeReceiveGeneration\":0"),"Replaced persistent prediction retained old receipt");
        check(frozenSnapshot.contains(generation),"Prepared snapshot mutated");
        var failed=Main.class.getDeclaredField("timelineFailed");failed.setAccessible(true);check(!failed.getBoolean(null),"Native tracing diagnostic failed");
        System.out.println("NATIVE_TIME_CHECK_PASS");
    }
}
