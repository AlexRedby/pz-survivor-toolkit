import net.alexredby.cartlab.Main;
import java.lang.reflect.Field;
import java.util.HashMap;

/** Actual native setter/removal advice checks; no game world, save, socket or installation. */
public final class EquipmentLifetimeCheck {
    public static class Owner extends zombie.characters.IsoPlayer {
        boolean nested,throwAfter,nativeAliveCheck;int blockedCallbacks;
        zombie.inventory.InventoryItem nestedItem;
        Owner(){super(null,null,0,0,0);}
        @Override public String getUsername(){return "client1";}
        @Override public boolean isAlive(){return !nativeAliveCheck || super.isAlive();}
        @Override public boolean isInvulnerable(){return false;}
        @Override public boolean isLocalPlayer(){return false;}
        @Override public void checkAnimalAttachedToRope(zombie.inventory.InventoryItem item){}
        @Override protected void setEquipParent(zombie.inventory.InventoryItem old,zombie.inventory.InventoryItem next){}
        @Override protected void setEquipParent(zombie.inventory.InventoryItem old,zombie.inventory.InventoryItem next,boolean ignored){}
        @Override public void setUseHandWeapon(zombie.inventory.types.HandWeapon item){}
        @Override public zombie.core.physics.BallisticsController getBallisticsController(){return null;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String key,String value){return null;}
        @Override public zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot setVariable(String key,boolean value){return null;}
        @Override public void resetEquippedHandsModels(){
            check(Main.cartLeaseLifetime(this)==null,"Intermediate native callback exposed a lifetime");blockedCallbacks++;
            if(expectedParseTrust!=null){var parse=checkedParsing.get();check(parse!=null && parse.trusted==expectedParseTrust,"Exact receipt/reader trust branch was not reached");check((parse.directCalls>0)==expectedDirectParse,"Actual native parser caller classification changed");parseCallbacks++;}
            if(nested){nested=false;setSecondaryHandItem(nestedItem);check(Main.cartLeaseLifetime(this)==null,"Nested setter exit exposed outer mutation");}
            if(throwAfter)throw new IllegalStateException("fixture setter failure");
        }
    }
    public static class Item extends zombie.inventory.InventoryItem {
        Item(){super("SaucedWheelbarrow","WheelbarrowWood","WheelbarrowWood","Item_WheelbarrowWood");}
        @Override public String getFullType(){return "SaucedWheelbarrow.WheelbarrowWood";}
    }
    public static class Connection extends zombie.core.raknet.UdpConnection {
        Connection(){super(null,1L,0);}
        @Override public long getConnectedGUID(){return 1;}
        @Override public int getIndex(){return 0;}
    }
    public static class Engine extends zombie.core.raknet.UdpEngine {
        Engine()throws Exception{super(0,0,1,null,false);}
    }
    private static sun.misc.Unsafe unsafe;
    private static int eventCallbacks;private static String eventFailure;
    private static Owner deathExpected;private static zombie.inventory.InventoryItem deathItem;
    private static int deathCallbacks;private static String deathFailure,deathToken;
    private static ThreadLocal<Main.EquipmentParse> checkedParsing;
    private static Boolean expectedParseTrust;private static boolean expectedDirectParse;private static int parseCallbacks;
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
    private static Field field(Class<?> type,String name)throws Exception{var value=type.getDeclaredField(name);value.setAccessible(true);return value;}
    private static Item item(int id)throws Exception{var item=(Item)unsafe.allocateInstance(Item.class);item.setID(id);return item;}
    private static Owner owner(Item item,short id)throws Exception{
        var owner=(Owner)unsafe.allocateInstance(Owner.class);owner.onlineId=id;owner.playerIndex=0;
        field(zombie.characters.IsoGameCharacter.class,"leftHandItem").set(owner,item);
        field(zombie.characters.IsoGameCharacter.class,"rightHandItem").set(owner,item);
        return owner;
    }
    @SuppressWarnings("unchecked")
    private static HashMap<Long,zombie.core.raknet.UdpConnection> connections(Engine engine)throws Exception{
        return (HashMap<Long,zombie.core.raknet.UdpConnection>)field(zombie.core.raknet.UdpEngine.class,"connectionMap").get(engine);
    }
    private static void registered(Owner owner,Connection connection,Engine engine)throws Exception{
        zombie.network.GameServer.IDToPlayerMap.clear();zombie.network.GameServer.PlayerToAddressMap.clear();
        zombie.network.GameServer.IDToPlayerMap.put(owner.getOnlineID(),owner);
        zombie.network.GameServer.PlayerToAddressMap.put(owner,1L);
        connection.players=new zombie.characters.IsoPlayer[]{owner,null,null,null};
        connections(engine).put(1L,connection);
        field(zombie.core.raknet.UdpEngine.class,"connectionArray").set(engine,new zombie.core.raknet.UdpConnection[]{connection});
    }
    private static String life(Owner owner){var life=Main.cartLeaseLifetime(owner);check(life!=null,"Expected admitted current lifetime");return life;}
    @SuppressWarnings("unchecked")
    private static void deathChecks(Engine engine,Connection connection)throws Exception {
        var item=item(42);var dying=owner(item,(short)7);registered(dying,connection,engine);
        dying.nativeAliveCheck=true;dying.setHealth(100);
        String token=life(dying);check(dying.isAlive(),"Native health baseline is not alive");
        var lives=(Main.NativeWeakMap<zombie.characters.IsoPlayer,Main.EquipmentLife>)field(Main.class,"equipmentLives").get(null);
        dying.setHealth(0);check(!dying.isAlive(),"Native death health not applied");
        check(Main.cartLeaseLifetime(dying)==null && !lives.get(dying).retired,"Dead guard did not precede permanent native entry retirement");
        deathExpected=dying;deathItem=item;deathToken=token;int beforeCallbacks=deathCallbacks;
        // Actual instrumented native OnDeath; server role stops after its original superclass event,
        // before world-dependent client UI/drop code. No helper or fake event invokes the advice.
        dying.OnDeath();
        check(deathCallbacks==beforeCallbacks+1 && deathFailure==null,"Native superclass death callback absent or observed a live binding: "+deathFailure);
        check(lives.get(dying).retired,"Native OnDeath did not leave a permanent actor tombstone");
        dying.setHealth(100);dying.setPrimaryHandItem(null);dying.setSecondaryHandItem(null);
        dying.setPrimaryHandItem(item);dying.setSecondaryHandItem(item);
        check(dying.isAlive() && dying.getHealth()==100 && dying.getPrimaryHandItem()==item && dying.getSecondaryHandItem()==item,
            "Native health/hands restoration fixture did not restore exact actor/item");
        check(Main.cartLeaseLifetime(dying)==null && !Main.cartLeaseResnapshot(dying,token),"Restored health/hands resurrected native death token");
        check(dying.removedFromWorldMs==0,"Death entry check unexpectedly used actor removal");
        var fresh=owner(item,(short)7);registered(fresh,connection,engine);
        check(!life(fresh).equals(token),"Death tombstone collapsed fresh same-ID actor incarnation");
        deathExpected=null;deathItem=null;deathToken=null;
        System.out.println("EQUIPMENT_NATIVE_DEATH_ENTRY_CHECK_PASS callbacks="+(deathCallbacks-beforeCallbacks)+" restoredHealthHands=true oldTokenRevived=false actorRemoval=false");
    }
    @SuppressWarnings("unchecked")
    private static void parseChecks(Engine engine,Connection connection)throws Exception {
        // Only negative classifier tests seed receipt objects. Positive native receipt proof is the Host gate.
        var ingress=(Main.NativeWeakMap<zombie.core.network.ByteBufferReader,Main.LeaseCommandIngress>)field(Main.class,"leaseControlIngresses").get(null);
        var dispatch=(ThreadLocal<Main.LeaseDispatchScope>)field(Main.class,"leaseControlDispatch").get(null);
        var parsing=(ThreadLocal<Main.EquipmentParse>)field(Main.class,"equipmentLifetimeParsing").get(null);checkedParsing=parsing;
        zombie.network.GameServer.server=false;zombie.network.GameClient.client=true;
        zombie.network.GameClient.instance.udpEngine=engine;zombie.network.GameClient.instance.connected=true;zombie.network.GameClient.connection=connection;
        for(String scenario:new String[]{"untrusted-release","trusted-release","trusted-failed-parse","foreign-reader","trusted-indirect-setters"}){
            var original=item(42);var player=owner(original,(short)7);registered(player,connection,engine);
            zombie.network.GameClient.IDToPlayerMap.clear();zombie.network.GameClient.IDToPlayerMap.put((short)7,player);
            String before=life(player);
            var bytes=java.nio.ByteBuffer.allocate(16).putShort((short)7).put((byte)-1).put((byte)0);
            if(!scenario.equals("trusted-failed-parse"))bytes.put((byte)0);bytes.flip();
            var reader=new zombie.core.network.ByteBufferReader(bytes);
            var receipt=new Main.LeaseCommandIngress(100+scenario.length(),new Main.LeaseTransport(new java.lang.ref.WeakReference<>(engine),
                new java.lang.ref.WeakReference<>(connection),Main.nativeTimeIdentity(connection,false),1,zombie.network.PacketTypes.PacketType.Equip.getId()));
            if(!scenario.equals("untrusted-release")){
                ingress.put(reader,receipt);
                var selected=scenario.equals("foreign-reader")?new zombie.core.network.ByteBufferReader(bytes.duplicate()):reader;
                dispatch.set(new Main.LeaseDispatchScope(selected,receipt,null));
            }
            boolean threw=false;int beforeCallbacks=parseCallbacks;
            expectedParseTrust=scenario.startsWith("trusted");expectedDirectParse=!scenario.equals("trusted-indirect-setters");
            try{
                if(scenario.equals("trusted-indirect-setters")){
                    var scope=Main.equipmentLifetimeParseEnter(reader,connection);check(scope!=null && scope.trusted,"Trusted negative-scope fixture refused");
                    var next=item(42);player.setPrimaryHandItem(next);player.setSecondaryHandItem(next);
                    check(Main.cartLeaseLifetime(player)==null && !Main.cartLeaseResnapshot(player,before),"Indirect setters exposed in-progress outer parse");
                    Main.equipmentLifetimeParseExit(scope,null);
                }else new zombie.network.packets.EquipPacket().parse(reader,connection);
            }catch(java.nio.BufferUnderflowException expected){threw=true;}
            finally{expectedParseTrust=null;dispatch.remove();ingress.remove(reader);}
            check(parseCallbacks>beforeCallbacks,"Native parse did not reach the receipt trust assertion");
            check(threw==scenario.equals("trusted-failed-parse"),"Actual native parse failure fixture changed");
            check(parsing.get()==null,"Native parse scope leaked after "+scenario);
            if(!scenario.equals("trusted-indirect-setters"))check(player.getPrimaryHandItem()==null,"Actual native parse did not release primary");
            check(!Main.cartLeaseResnapshot(player,before),"Release, indirect call or failed parse certified as resnapshot");
            if(!scenario.equals("trusted-indirect-setters"))check(Main.cartLeaseLifetime(player)==null,"Release or failed parse exposed held lifetime");
            player.setPrimaryHandItem(original);player.setSecondaryHandItem(original);
            if(threw)check(Main.cartLeaseLifetime(player)==null,"Failed parse actor revived");
            else{
                String after=life(player);check(!before.equals(after),"Parsed release roundtrip lost lifetime transition");
                check(!Main.cartLeaseResnapshot(player,before) && !Main.cartLeaseResnapshot(player,after),"Generic restoration or unchanged token certified");
            }
        }
        zombie.network.GameClient.client=false;zombie.network.GameServer.server=true;
    }
    private static void jsonField(String json,String key,Object value){
        String encoded=value instanceof String?"\""+value+"\"":String.valueOf(value);
        check(json!=null && json.contains("\""+key+"\":"+encoded+(json.endsWith("\""+key+"\":"+encoded+"}")?"}":",")),"Diagnostic field differs: "+key+" expected="+encoded+" json="+json);
    }
    @SuppressWarnings("unchecked")
    private static void eligibilityChecks(Owner known,Connection connection,Engine engine)throws Exception {
        var lives=(Main.NativeWeakMap<zombie.characters.IsoPlayer,Main.EquipmentLife>)field(Main.class,"equipmentLives").get(null);
        var records=(java.util.ArrayList<?>)field(Main.class,"equipmentLifetimeRecords").get(null);
        var issued=field(Main.class,"equipmentLifetimeIssuedCount");var state=lives.get(known);
        int count=records.size(),issuedSize=state.issued.size();long issuedCount=issued.getLong(null),revision=state.revision,hard=state.hardRevision;
        String json=Main.cartLeaseEligibility(known);check(json!=null && json.equals(Main.cartLeaseEligibility(known)),"Repeated diagnostic snapshot changed state");
        jsonField(json,"schema",1);jsonField(json,"authorityProof",false);jsonField(json,"diagnosticOnly",true);
        jsonField(json,"actorEpoch",Main.nativeTimeIdentity(known,true));jsonField(json,"clientMapExact",false);
        jsonField(json,"sourceRole","server");jsonField(json,"engineKnown",true);jsonField(json,"exactActiveMapping",true);
        jsonField(json,"baseline",true);jsonField(json,"retired",false);jsonField(json,"revision",revision);
        jsonField(json,"primaryEpoch",Main.nativeTimeIdentity(known.getPrimaryHandItem(),false));jsonField(json,"sameHands",true);
        var unknown=owner(item(84),(short)12);
        String absent=Main.cartLeaseEligibility(unknown);jsonField(absent,"lifePresent",false);jsonField(absent,"issuedCount",0);
        jsonField(absent,"connectionEpoch",0);jsonField(absent,"exactActiveMapping",null);
        check(lives.get(unknown)==null,"Diagnostic snapshot created an unknown actor lifetime");
        String missing=Main.cartLeaseEligibility(null);jsonField(missing,"playerPresent",false);jsonField(missing,"lifePresent",false);
        check(records.size()==count && issued.getLong(null)==issuedCount && state.issued.size()==issuedSize && state.revision==revision && state.hardRevision==hard,
            "Read-only diagnostics changed ledger count, issued tokens or native revision");
        zombie.network.GameServer.server=false;zombie.network.GameClient.client=true;zombie.network.GameClient.instance.connected=true;
        zombie.network.GameClient.instance.udpEngine=engine;zombie.network.GameClient.connection=connection;
        var previous=IsoPlayerState.capture();
        try{
            zombie.characters.IsoPlayer.players[0]=unknown;zombie.characters.IsoPlayer.setInstance(unknown);
            zombie.network.GameClient.IDToPlayerMap.clear();zombie.network.GameClient.IDToPlayerMap.put((short)12,unknown);
            String local=Main.cartLeaseEligibility(unknown);jsonField(local,"localSlotExact",true);jsonField(local,"currentActorExact",true);
            jsonField(local,"clientMapExact",true);jsonField(local,"clientMapActorEpoch",Main.nativeTimeIdentity(unknown,true));jsonField(local,"clientConnected",true);
            jsonField(local,"sourceRole","client");jsonField(local,"lifePresent",false);jsonField(local,"exactActiveMapping",true);
            check(lives.get(unknown)==null && records.size()==count && issued.getLong(null)==issuedCount,"Local eligibility diagnostics issued a binding");
            zombie.network.GameClient.IDToPlayerMap.put((short)12,known);
            String wrong=Main.cartLeaseEligibility(unknown);jsonField(wrong,"clientMapExact",false);jsonField(wrong,"clientMapActorEpoch",Main.nativeTimeIdentity(known,true));
            unknown.removedFromWorldMs=123;jsonField(Main.cartLeaseEligibility(unknown),"removedFromWorldMs",123);unknown.removedFromWorldMs=0;
            connections(engine).remove(1L);jsonField(Main.cartLeaseEligibility(unknown),"exactActiveMapping",false);connections(engine).put(1L,connection);
            zombie.network.GameClient.instance.udpEngine=null;jsonField(Main.cartLeaseEligibility(unknown),"engineKnown",false);jsonField(Main.cartLeaseEligibility(unknown),"exactActiveMapping",null);
            zombie.network.GameClient.instance.udpEngine=engine;
        }finally{previous.restore();zombie.network.GameClient.IDToPlayerMap.clear();zombie.network.GameClient.client=false;zombie.network.GameServer.server=true;}
        Main.equipmentLifetimeRetire(unknown,"actor-remove");var retired=lives.get(unknown);long retiredRevision=retired.revision;
        jsonField(Main.cartLeaseEligibility(unknown),"retired",true);
        check(retired.revision==retiredRevision && retired.issued.isEmpty() && issued.getLong(null)==issuedCount,"Diagnostic snapshot revived or issued retired actor");
        System.out.println("EQUIPMENT_ELIGIBILITY_CHECK_PASS noNewLife=true noTokenIssuance=true revisionsUnchanged=true unknownActor=true localMapAndSlot=true retiredPreserved=true");
    }
    private record IsoPlayerState(zombie.characters.IsoPlayer current,zombie.characters.IsoPlayer slot) {
        static IsoPlayerState capture(){return new IsoPlayerState(zombie.characters.IsoPlayer.getInstance(),zombie.characters.IsoPlayer.players[0]);}
        void restore(){zombie.characters.IsoPlayer.players[0]=slot;zombie.characters.IsoPlayer.setInstance(current);}
    }
    public static void main(String[] args)throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        zombie.Lua.LuaManager.env=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newEnvironment();
        zombie.Lua.LuaManager.env.rawset("Events",se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable());
        zombie.GameWindow.gameThread=Thread.currentThread();
        var platform=se.krka.kahlua.j2se.J2SEPlatform.getInstance();
        zombie.Lua.LuaManager.thread=new se.krka.kahlua.vm.KahluaThread(platform,zombie.Lua.LuaManager.env);
        zombie.Lua.LuaManager.thread.debugOwnerThread=Thread.currentThread();
        zombie.Lua.LuaManager.caller=new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        zombie.Lua.LuaManager.env.rawset("assertBlocked",(se.krka.kahlua.vm.JavaFunction)(frame,count)->{
            Object actor=frame.get(0);eventCallbacks++;
            if(!(actor instanceof Owner player) || Main.cartLeaseLifetime(player)!=null)eventFailure="Native OnEquip callback exposed intermediate lifetime";
            return 0;
        });
        var callback=se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring("assertBlocked(...)","native-equipment-event",zombie.Lua.LuaManager.env);
        zombie.Lua.LuaEventManager.AddEvent("OnEquipPrimary").callbacks.add(callback);
        zombie.Lua.LuaEventManager.AddEvent("OnEquipSecondary").callbacks.add(callback);
        zombie.Lua.LuaManager.env.rawset("assertDeathRetired",(se.krka.kahlua.vm.JavaFunction)(frame,count)->{
            Object actor=frame.get(0);deathCallbacks++;
            try{
                if(actor!=deathExpected || !(actor instanceof Owner player))deathFailure="Wrong native death actor";
                else {
                    var lives=(Main.NativeWeakMap<zombie.characters.IsoPlayer,Main.EquipmentLife>)field(Main.class,"equipmentLives").get(null);
                    var state=lives.get(player);
                    if(state==null || !state.retired || Main.cartLeaseLifetime(player)!=null || Main.cartLeaseResnapshot(player,deathToken))
                        deathFailure="Superclass OnCharacterDeath callback preceded retirement";
                    else if(player.getPrimaryHandItem()!=deathItem || player.getSecondaryHandItem()!=deathItem || player.removedFromWorldMs!=0)
                        deathFailure="Native death callback did not precede hand release/removal";
                }
            }catch(Throwable error){deathFailure=error.toString();}
            return 0;
        });
        var deathCallback=se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring("assertDeathRetired(...)","native-equipment-death-event",zombie.Lua.LuaManager.env);
        zombie.Lua.LuaEventManager.AddEvent("OnCharacterDeath").callbacks.add(deathCallback);
        var access=field(sun.misc.Unsafe.class,"theUnsafe");unsafe=(sun.misc.Unsafe)access.get(null);
        var engine=(Engine)unsafe.allocateInstance(Engine.class);
        field(zombie.core.raknet.UdpEngine.class,"connectionMap").set(engine,new HashMap<Long,zombie.core.raknet.UdpConnection>());
        var connection=(Connection)unsafe.allocateInstance(Connection.class);
        zombie.network.GameServer.server=true;zombie.network.GameClient.client=false;zombie.network.GameServer.udpEngine=engine;
        var original=item(42);var owner=owner(original,(short)7);registered(owner,connection,engine);
        String first=life(owner);check(first.equals(life(owner)),"Read-only sampling changed native lifetime");
        eligibilityChecks(owner,connection,engine);
        check(!Main.cartLeaseResnapshot(owner,first) && !Main.cartLeaseResnapshot(owner,"invalid"),"Unchanged or malformed native token certified");
        owner.setPrimaryHandItem(original);owner.setSecondaryHandItem(original);
        check(first.equals(life(owner)),"Native same-reference setter no-op invalidated lifetime");
        owner.setPrimaryHandItem(null);check(Main.cartLeaseLifetime(owner)==null,"Released primary retained held lifetime");
        owner.setSecondaryHandItem(null);owner.setPrimaryHandItem(original);owner.setSecondaryHandItem(original);
        String reacquired=life(owner);check(!reacquired.equals(first),"Complete release/reacquire between polls reused lifetime");
        var replacement=item(42);check(replacement!=original && replacement.getID()==original.getID(),"Same-ID fixture invalid");
        owner.nested=true;owner.nestedItem=replacement;owner.setPrimaryHandItem(replacement);
        String replaced=life(owner);check(!replaced.equals(reacquired),"Same numeric ID replacement reused old lifetime");
        check(owner.getPrimaryHandItem()==replacement && owner.getSecondaryHandItem()==replacement && owner.blockedCallbacks>=6,"Actual native hand setter effects/callback nesting not exercised");
        replacement.setID(43);replacement.setID(42);String idCycle=life(owner);check(!idCycle.equals(replaced),"Same-object numeric ID roundtrip invisible");
        var world=(zombie.iso.objects.IsoWorldInventoryObject)unsafe.allocateInstance(zombie.iso.objects.IsoWorldInventoryObject.class);
        replacement.setWorldItem(world);check(Main.cartLeaseLifetime(owner)==null,"World-bound item admitted as held");replacement.setWorldItem(null);
        check(!life(owner).equals(idCycle),"World-item roundtrip reused lifetime");
        short oldID=owner.getOnlineID();owner.setOnlineID((short)8);owner.setOnlineID(oldID);String onlineCycle=life(owner);
        check(!onlineCycle.equals(idCycle),"Actor online ID roundtrip invisible");
        owner.throwAfter=true;try{owner.setSecondaryHandItem(original);throw new AssertionError("Expected native callback throw");}catch(IllegalStateException expected){}
        owner.throwAfter=false;owner.setSecondaryHandItem(replacement);check(Main.cartLeaseLifetime(owner)==null,"Throwing setter revived poisoned actor");
        // A fresh exact actor with the same online ID can establish a new lifetime; old record remains poisoned.
        var next=owner(original,(short)7);registered(next,connection,engine);check(!life(next).equals(first),"Same-ID actor replacement collapsed identity");
        try{next.load(java.nio.ByteBuffer.allocate(0),249,false);}catch(Throwable expected){}
        check(Main.cartLeaseLifetime(next)==null,"Failed actual native load did not poison lifetime");
        var itemLoaded=item(42);var itemOwner=owner(itemLoaded,(short)7);registered(itemOwner,connection,engine);life(itemOwner);
        try{var bytes=java.nio.ByteBuffer.allocate(4).putInt(43);bytes.flip();itemLoaded.load(bytes,249);}catch(Throwable expected){}
        check(itemLoaded.getID()==43 && Main.cartLeaseLifetime(itemOwner)==null,"Actual item.load ID write/failure escaped lifetime fence");
        deathChecks(engine,connection);
        var removed=owner(original,(short)7);registered(removed,connection,engine);life(removed);
        try{removed.removeFromWorld();}catch(Throwable expected){}
        check(Main.cartLeaseLifetime(removed)==null,"Actual removal entry did not permanently retire actor");
        var disconnected=owner(original,(short)7);registered(disconnected,connection,engine);life(disconnected);
        // Neutral role avoids native cleanup infrastructure after the engine removes its actual map entry.
        zombie.network.GameServer.server=false;engine.removeConnection(1L);zombie.network.GameServer.server=true;
        check(!connections(engine).containsKey(1L),"Actual engine map removal not exercised");
        connections(engine).put(1L,connection);check(Main.cartLeaseLifetime(disconnected)==null,"Reinserting identical connection revived retired record");
        var lateActor=owner(original,(short)7);registered(lateActor,connection,engine);
        check(Main.cartLeaseLifetime(lateActor)==null,"An unadmitted actor revived an already removed exact transport");
        var reconnected=owner(original,(short)7);var connection2=(Connection)unsafe.allocateInstance(Connection.class);registered(reconnected,connection2,engine);
        check(!life(reconnected).equals(first),"New connection/actor incarnation reused lifetime");
        zombie.network.GameServer.IDToPlayerMap.remove((short)7);check(Main.cartLeaseLifetime(reconnected)==null,"Unregistered actor admitted");
        zombie.network.GameServer.IDToPlayerMap.put((short)7,reconnected);life(reconnected);
        var lives=(Main.NativeWeakMap<zombie.characters.IsoPlayer,Main.EquipmentLife>)field(Main.class,"equipmentLives").get(null);
        lives.get(reconnected).revision=9007199254740991L;
        reconnected.setSecondaryHandItem(null);check(Main.cartLeaseLifetime(reconnected)==null,"Exact Lua integer exhaustion did not poison record");
        check(Main.cartLeaseLifetime(owner)==null,"Historical owner unexpectedly revived");
        var parseConnection=(Connection)unsafe.allocateInstance(Connection.class);connections(engine).put(1L,parseConnection);
        parseChecks(engine,parseConnection);
        check(eventCallbacks>=8 && eventFailure==null,"Actual Lua OnEquip callbacks missing or exposed intermediate binding: "+eventFailure);
        System.out.println("EQUIPMENT_LIFETIME_CHECK_PASS");
    }
}
