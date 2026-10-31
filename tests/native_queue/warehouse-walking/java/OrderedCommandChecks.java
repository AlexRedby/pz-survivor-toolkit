package toolkit.warehousewalking;

import java.nio.*;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.converter.KahluaConverterManager;
import zombie.Lua.KahluaNumberConverter;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.core.network.*;
import zombie.core.raknet.UdpConnection;
import zombie.network.*;

/** Native serializers and connection sink only; no socket, engine, game or UI. */
public final class OrderedCommandChecks {
    static final J2SEPlatform PLATFORM=new J2SEPlatform();
    static void check(boolean value,String reason){if(!value)throw new AssertionError(reason);}
    interface Operation{void run()throws Exception;}
    static void rejects(Operation work,String reason)throws Exception{
        boolean rejected=false;try{work.run();}catch(IllegalStateException|IllegalArgumentException expected){rejected=true;}
        check(rejected,reason);
    }
    static KahluaTable table(Object...pairs){var out=PLATFORM.newTable();for(int i=0;i<pairs.length;i+=2)out.rawset(pairs[i],pairs[i+1]);return out;}
    static final class Sink extends UdpConnection {
        ByteBuffer buffer=ByteBuffer.allocate(OrderedCommands.MAX_BYTES);byte[] payload;
        int starts,sends,cancels,priority,reliability,channel;
        Sink(){super(null,0,0);}
        @Override public ByteBufferWriter startPacket(){starts++;buffer.clear();return new ByteBufferWriter(buffer);}
        @Override public void endPacket(int p,int r,byte c){priority=p;reliability=r;channel=c;sends++;payload=Arrays.copyOf(buffer.array(),buffer.position());}
        @Override public void cancelPacket(){cancels++;}
        @Override public boolean isLimitExceeded(PacketTypes.PacketType type){return false;}
    }
    static byte[] bytes(ByteBuffer buffer){byte[] out=new byte[buffer.remaining()];buffer.duplicate().get(out);return out;}
    static void payloads()throws Exception {
        var sink=new Sink();var oldConnection=GameClient.connection;
        boolean oldClient=GameClient.client,oldServer=GameServer.server;
        try {
            GameClient.connection=sink;GameClient.client=false;GameServer.server=false;
            for(KahluaTable args:new KahluaTable[]{null,table(),table("case","walk","token","warehouse-walking:123:7","index",1.0,
                    "baseline",table("rootIds",table(1.0,31.0,2.0,32.0),"equipment",table("primaryEmpty",true,"worn",table())))}) {
                GameServer.sendServerCommand(OrderedCommands.MODULE,"CaptureBaseline",args,sink);
                byte[] nativeServer=sink.payload;
                check(sink.reliability==2&&sink.channel==0,"pinned native server command is unordered channel0");
                ByteBuffer encoded=OrderedCommands.encode(true,0,OrderedCommands.MODULE,"CaptureBaseline",args);
                check(Arrays.equals(nativeServer,bytes(encoded)),"server encoding equals actual GameServer serializer including header/nil/table");
                OrderedCommands.dispatch(sink,encoded,OrderedCommands.channel(true,"CaptureBaseline"));
                check(sink.priority==1&&sink.reliability==3&&sink.channel==0,"only per-call native transport metadata becomes ordered");
                check(Arrays.equals(nativeServer,sink.payload),"ordered transport preserves native server payload exactly");
                GameClient.instance.sendClientCommand(null,OrderedCommands.MODULE,"Baseline",args);
                byte[] nativeClient=sink.payload;
                check(Arrays.equals(nativeClient,bytes(OrderedCommands.encode(false,-1,OrderedCommands.MODULE,"Baseline",args))),
                    "client encoding equals actual GameClient serializer including null actor header and nil/table");
                var input=new ByteBufferReader(ByteBuffer.wrap(bytes(OrderedCommands.encode(false,3,OrderedCommands.MODULE,"Baseline",args))));
                check(input.getByte()==(byte)134&&input.getShort()==PacketTypes.PacketType.ClientCommand.getId()&&input.getByte()==3,"native packet/player header retained");
                check(OrderedCommands.MODULE.equals(input.getUTF())&&"Baseline".equals(input.getUTF()),"native strings round trip");
                boolean present=input.getBoolean();check(present==(args!=null&&!args.isEmpty()),"native nil/empty payload flag retained");
                if(present){var decoded=table();TableNetworkUtils.load(decoded,input);check(decoded.rawget("baseline") instanceof KahluaTable,"native nested table round trip");}
                check(input.remaining()==0,"native round trip consumes exact payload");
            }
        } finally {GameClient.connection=oldConnection;GameClient.client=oldClient;GameServer.server=oldServer;}
        var tiny=new Sink();tiny.buffer=ByteBuffer.allocate(1);
        boolean failed=false;try{OrderedCommands.dispatch(tiny,OrderedCommands.encode(true,0,"x","y",table()),1);}catch(BufferOverflowException expected){failed=true;}
        check(failed&&tiny.starts==1&&tiny.sends==0&&tiny.cancels==1,"partial connection write cancels without dispatch");
        var invalid=table("unsupported",new Object());
        rejects(()->OrderedCommands.encode(true,0,"x","y",invalid),"unsupported payload rejected before live connection");
        var cycle=table();cycle.rawset("self",cycle);rejects(()->OrderedCommands.encode(true,0,"x","y",cycle),"cyclic payload rejected");
        rejects(()->OrderedCommands.encode(true,0,"x","y",table("n",Double.NaN)),"nonfinite payload rejected");
        var changed=table("case","walk");changed.rawset("callback",(JavaFunction)(frame,count)->0);
        rejects(()->OrderedCommands.encode(true,0,"x","y",changed),"changed payload cannot be silently dropped by native serializer");
    }
    static void gates()throws Exception {
        var selection=table("suite","warehouse-walking","kind","mp","mode","toolkit","cases",table(1.0,"walk"));
        OrderedCommands.selection(selection);selection.rawset("kind","sp");rejects(()->OrderedCommands.selection(selection),"SP cannot use private MP transport");
        selection.rawset("kind","mp");selection.rawset("mode","vanilla");rejects(()->OrderedCommands.selection(selection),"wrong mode rejected");
        var marker=List.of(OrderedCommands.MAGIC,"/owned/cache","client1","sealed");
        check(OrderedCommands.marker(Path.of("/owned/cache"),marker,"sealed").equals("client1"),"owned marker accepted");
        rejects(()->OrderedCommands.marker(Path.of("/other/cache"),marker,"sealed"),"foreign cache rejected");
        rejects(()->OrderedCommands.marker(Path.of("/owned/cache"),marker,"changed"),"changed staged entry rejected");
        var hostOptions=table("mp_host",true);
        check(OrderedCommands.coopHost(true,true,hostOptions),"native coop with explicit live Host selection accepted");
        check(!OrderedCommands.coopHost(false,true,hostOptions)&&!OrderedCommands.coopHost(true,false,hostOptions),"both actual server and native coop required");
        hostOptions.rawset("mp_host",false);check(!OrderedCommands.coopHost(true,true,hostOptions),"changed live Host option revokes cache authorization");
        check(!OrderedCommands.coopHost(true,true,null),"missing live Host selection rejected");
        OrderedCommands.ownership(false,"client1","client1",true,true,true,false);OrderedCommands.ownership(true,"server","client2",true,true,true,false);
        OrderedCommands.ownership(true,"client1","client1",true,true,true,true);OrderedCommands.ownership(true,"client1","client2",true,true,true,true);
        rejects(()->OrderedCommands.ownership(false,"client1","client2",true,true,true,false),"foreign client actor rejected");
        rejects(()->OrderedCommands.ownership(true,"client1","client1",true,true,true,false),"client1 cache needs native coop/live Host selection");
        rejects(()->OrderedCommands.ownership(true,"client2","client2",true,true,true,true),"coop Host cannot use peer cache");
        rejects(()->OrderedCommands.ownership(true,"client1","client1",false,true,true,true),"coop marker cannot authorize wrong actual runtime role");
        rejects(()->OrderedCommands.ownership(false,"client1","client1",false,true,true,false),"wrong actual runtime role rejected");
        rejects(()->OrderedCommands.ownership(false,"client1","client1",true,false,true,false),"null/nonowned actor rejected");
        rejects(()->OrderedCommands.ownership(false,"client1","client1",true,true,false,false),"nonloopback rejected");
        var prepare=table("case","walk","index",1.0);OrderedCommands.protocol(false,"client1",OrderedCommands.MODULE,"Prepare",prepare);
        rejects(()->OrderedCommands.protocol(false,"client1","OtherModule","Prepare",prepare),"foreign module rejected");
        rejects(()->OrderedCommands.protocol(false,"client1",OrderedCommands.MODULE,"Ready",prepare),"measured protocol remains outside ordered bridge");
        prepare.rawset("token","warehouse-walking:123:7");rejects(()->OrderedCommands.protocol(false,"client1",OrderedCommands.MODULE,"Prepare",prepare),"changed Prepare token rejected");
        var baseline=table("case","walk","index",1.0,"token","warehouse-walking:123:7","baseline",table());
        OrderedCommands.protocol(false,"client1",OrderedCommands.MODULE,"Baseline",baseline);
        baseline.rawset("proof",table("rootEmpty",true,"equipmentEmpty",true,"originalsStashed",true));
        OrderedCommands.protocol(false,"client1",OrderedCommands.MODULE,"Normalized",baseline);
        baseline.rawset("token","foreign");rejects(()->OrderedCommands.protocol(false,"client1",OrderedCommands.MODULE,"Baseline",baseline),"foreign token rejected");
        OrderedCommands.protocol(true,"client1",OrderedCommands.MODULE,"CaptureBaseline",table("token","warehouse-walking:123:7"));
        var payload=table("role","client1","ids",table("token","warehouse-walking:123:7"));
        OrderedCommands.protocol(true,"client1",OrderedCommands.MODULE,"Normalize",payload);OrderedCommands.protocol(true,"client1",OrderedCommands.MODULE,"Prepared",payload);
        for(String terminal:new String[]{"Abortd","Done"})OrderedCommands.protocol(true,"client1",OrderedCommands.MODULE,terminal,table("token","warehouse-walking:123:7"));
        rejects(()->OrderedCommands.protocol(true,"client2",OrderedCommands.MODULE,"Normalize",payload),"foreign target role rejected");
        // The public entry point itself fails closed before touching a socket.
        rejects(()->OrderedCommands.client(null,OrderedCommands.MODULE,"Prepare",prepare),"public null/foreign-thread actor rejected");
        AtomicReference<Throwable> failure=new AtomicReference<>();
        Thread thread=new Thread(()->{try{OrderedCommands.client(null,OrderedCommands.MODULE,"Prepare",prepare);failure.set(new AssertionError("foreign thread admitted"));}
            catch(IllegalStateException expected){}catch(Throwable error){failure.set(error);}});
        thread.start();thread.join();check(failure.get()==null,"foreign thread entry fails closed");
    }
    static void channels()throws Exception {
        check(OrderedCommands.CLIENT_CHANNELS.equals(Map.of("Prepare",0,"Baseline",0,"Normalized",0)),"client clothing-fence command map exact");
        check(OrderedCommands.SERVER_CHANNELS.equals(Map.of("CaptureBaseline",0,"Normalize",0,"Prepared",1,"Abortd",1,"Done",1)),"server clothing/materialization/cleanup map exact");
        for(var entry:OrderedCommands.SERVER_CHANNELS.entrySet()) {
            var sink=new Sink();OrderedCommands.dispatch(sink,OrderedCommands.encode(true,0,OrderedCommands.MODULE,entry.getKey(),table()),OrderedCommands.channel(true,entry.getKey()));
            check(sink.reliability==3&&sink.channel==entry.getValue(),"actual per-command server ordering metadata: "+entry.getKey());
        }
        for(Class<?> type:new Class<?>[]{zombie.network.packets.AddInventoryItemToContainerPacket.class,
            zombie.network.packets.RemoveInventoryItemFromContainerPacket.class,zombie.network.packets.AddItemToMapPacket.class,
            zombie.network.packets.ObjectModDataPacket.class,zombie.network.packets.RemoveItemFromSquarePacket.class}) {
            var setting=type.getAnnotation(zombie.network.PacketSetting.class);
            check(setting.reliability()==3&&setting.ordering()==1,"materialization/cleanup fence matches actual native packet: "+type.getSimpleName());
        }
    }
    @LuaMethod(name="orderedSuccessProbe",global=true)
    public static boolean successProbe(){return true;}
    static void exposedResults()throws Exception {
        var platform=new J2SEPlatform();var env=platform.newTable();var thread=new KahluaThread(platform,env);thread.debugOwnerThread=Thread.currentThread();
        se.krka.kahlua.stdlib.BaseLib.register(env);
        var converters=new KahluaConverterManager();KahluaNumberConverter.install(converters);
        var exposer=new zombie.Lua.LuaManager.Exposer(converters,platform,env);
        for(String name:new String[]{"client","server"}) {
            var method=OrderedCommands.class.getMethod(name,zombie.characters.IsoPlayer.class,String.class,String.class,KahluaTable.class);
            check(method.getReturnType()==boolean.class,"both private globals explicitly return success");
        }
        var constructor=OrderedCommands.class.getDeclaredConstructor();constructor.setAccessible(true);
        exposer.exposeGlobalFunctions(constructor.newInstance());exposer.exposeGlobalFunctions(new OrderedCommandChecks());
        check(Boolean.TRUE.equals(thread.call(env.rawget("orderedSuccessProbe"),new Object[]{})),"native exposer preserves explicit boolean true");
        // Native LuaJavaInvoker's error reporting consults this VM reference;
        // provide the same binding as LuaManager.init without loading a game.
        var oldDefault=zombie.ui.UIManager.defaultthread;zombie.ui.UIManager.defaultthread=thread;
        try {
            Object[] swallowed=thread.pcall(ProfileChecks.compile("return warehouseWalkingOrderedClient(nil, 'WarehouseWalkingTest', 'Prepare', {case='walk',index=1})","ordered-rejection.lua",env),new Object[]{});
            check(swallowed[0]==Boolean.TRUE&&(swallowed.length==1||swallowed[1]==null),"native exposer swallows rejected Java global and returns nil: "+Arrays.toString(swallowed));
            Object[] guarded=thread.pcall(ProfileChecks.compile("if warehouseWalkingOrderedClient(nil, 'WarehouseWalkingTest', 'Prepare', {case='walk',index=1}) ~= true then error('ordered send rejected') end","ordered-result.lua",env),new Object[]{});
            check(guarded[0]==Boolean.FALSE&&guarded[1].toString().contains("ordered send rejected"),"explicit Lua success assertion turns swallowed rejection into protocol failure: "+Arrays.toString(guarded));
        } finally {zombie.ui.UIManager.defaultthread=oldDefault;}
    }
    static void run()throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();OrderedCommands.verifyNative();payloads();gates();
        var setting=zombie.network.packets.SyncClothingPacket.class.getAnnotation(zombie.network.PacketSetting.class);
        check(setting.reliability()==3&&setting.ordering()==0,"ordered fence matches actual native clothing channel");
        check(me.zed_0xff.zombie_buddy.Exposer.hasGlobalLuaMethod(OrderedCommands.class),"standard private mod loader discovers both annotated globals");
        channels();exposedResults();
        System.out.println("WAREHOUSE_WALKING_ORDERED_COMMANDS_PASS native_payload=true reliability=3 channels=0,1 gated=true no_partial_send=true explicit_success=true");
    }
}
