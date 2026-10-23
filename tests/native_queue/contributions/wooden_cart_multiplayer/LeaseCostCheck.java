import net.alexredby.cartlab.Main;
import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;

/** Pinned native command serialization/parser and read-only receipt checks; no world, socket or game launch. */
public final class LeaseCostCheck {
    private static final short TYPE=zombie.network.PacketTypes.PacketType.ClientCommand.getId();
    private static sun.misc.Unsafe unsafe;
    private static long generation;
    private static Throwable callbackFailure;
    private static int callbacks,nestedEvents;
    private static final ArrayDeque<Sample> active=new ArrayDeque<>();
    private static final ArrayList<Sample> measured=new ArrayList<>();
    private static final java.io.ByteArrayOutputStream traceBytes=new java.io.ByteArrayOutputStream();
    private static final java.io.PrintStream initialOut=System.out;
    private static final java.lang.reflect.Method CLIENT=method(zombie.network.GameClient.class,"receiveClientCommand",zombie.core.network.ByteBufferReader.class,short.class);
    private static final java.lang.reflect.Method SERVER=method(zombie.network.GameServer.class,"receiveClientCommand",zombie.core.network.ByteBufferReader.class,zombie.core.raknet.UdpConnection.class,short.class);
    public static class Owner extends zombie.characters.IsoPlayer {
        Owner(){super(null,null,0,0,0);}
        @Override public String getUsername(){return "client1";}
        @Override public short getOnlineID(){return 7;}
    }
    public static class Connection extends zombie.core.raknet.UdpConnection {
        Connection(){super(null,1L,0);}
        long guid=1;
        @Override public long getConnectedGUID(){return guid;}
        @Override public int getIndex(){return 0;}
        @Override public String getIDStr(){return "lease-cost-native";}
    }
    public static class Engine extends zombie.core.raknet.UdpEngine {
        HashMap<Long,zombie.core.raknet.UdpConnection> connections;
        Engine()throws Exception{super(0,0,1,null,false);}
        @Override public zombie.core.raknet.UdpConnection getActiveConnection(long guid){return connections.get(guid);}
    }
    public static class Peer extends Owner {
        @Override public short getOnlineID(){return 8;}
    }
    private static Connection foreignConnection;
    private static int membershipChecks;
    private static Engine engine;
    private static Connection connection;
    private static Owner player;
    private static Main.NativeWeakMap<zombie.core.network.ByteBufferReader,Main.LeaseCommandIngress> ingresses;
    private static ThreadLocal<?> callbackScopes,receiptFrames;
    private static final class Sample {
        final String module,command,mode;final boolean server,table;final zombie.network.ZomboidNetData data;
        final ByteBuffer buffer;final int begin,end,payload;final ByteOrder order;final byte[] original;
        Main.LeaseCommandIngress ingress;String receipt;Sample inner;
        Sample(String module,String command,String mode,boolean server,boolean table,ByteOrder order,boolean direct)throws Exception {
            this.module=module;this.command=command;this.mode=mode;this.server=server;this.table=table;this.order=order;
            buffer=(direct?ByteBuffer.allocateDirect(4096):ByteBuffer.allocate(4096)).order(order);begin=11;buffer.position(begin-3);
            var writer=new zombie.core.network.ByteBufferWriter(buffer);zombie.network.PacketTypes.PacketType.ClientCommand.doPacket(writer);
            check(buffer.position()==begin && (buffer.get(begin-3)&255)==134 && buffer.getShort(begin-2)==TYPE,"Pinned native engine header changed");
            if(server)writer.putByte(0);writer.putUTF(module);writer.putUTF(command);writer.putBoolean(table);
            if(table)zombie.network.TableNetworkUtils.save(table(),writer);
            if(mode.equals("trailing"))writer.putByte(99);
            end=buffer.position();payload=end-begin;buffer.limit(end);buffer.position(begin);buffer.mark();original=bytes(buffer);
            data=new zombie.network.ZomboidNetData();data.type=zombie.network.PacketTypes.PacketType.ClientCommand;data.connection=1;field(zombie.network.ZomboidNetData.class,"buffer").set(data,new zombie.core.network.ByteBufferReader(buffer));
        }
    }
    private static java.lang.reflect.Method method(Class<?> owner,String name,Class<?>... args){try{var method=owner.getDeclaredMethod(name,args);method.setAccessible(true);return method;}catch(Exception error){throw new ExceptionInInitializerError(error);}}
    private static Field field(Class<?> owner,String name)throws Exception{var result=owner.getDeclaredField(name);result.setAccessible(true);return result;}
    private static void check(boolean condition,String text){if(!condition)throw new AssertionError(text);}
    private static byte[] bytes(ByteBuffer buffer){var copy=buffer.duplicate();copy.clear();byte[] result=new byte[copy.remaining()];copy.get(result);return result;}
    private static int mark(ByteBuffer buffer){try{return buffer.duplicate().reset().position();}catch(java.nio.InvalidMarkException missing){return -1;}}
    private static se.krka.kahlua.vm.KahluaTable table(){
        var table=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();var nested=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();
        nested.rawset("inner","кириллица/é");nested.rawset("number",42d);nested.rawset("yes",true);table.rawset("payload",nested);table.rawset("op","UPDATE");table.rawset("seq",3d);return table;
    }
    private static String receipt(Sample sample,String module,String command){
        ByteBuffer buffer=sample.data.buffer.bb;int at=buffer.position(),limit=buffer.limit(),mark=mark(buffer);ByteOrder order=buffer.order();byte[] before=bytes(buffer);
        String result=Main.cartLeaseReceipt(module,command);
        check(sample.data.buffer.bb==buffer && buffer.position()==at && buffer.limit()==limit && buffer.order()==order && mark(buffer)==mark
            && java.util.Arrays.equals(before,bytes(buffer)),"Receipt observation changed native buffer identity/content/state");
        return result;
    }
    private static void positive(Sample sample)throws Exception {
        check(receipt(sample,sample.module+"foreign",sample.command)==null,"Foreign module matched native header");
        check(receipt(sample,sample.module,sample.command+"foreign")==null,"Foreign command matched native header");
        String wrong=sample.module.equals("CartLeaseProbe")?"CartLeaseLifetimes":"CartLeaseProbe";
        check(receipt(sample,wrong,sample.command)==null,"Another allowed module matched native header");
        String value=receipt(sample,sample.module,sample.command);
        if(value==null){
            var scope=(Main.LeaseCallbackScope)callbackScopes.get();
            initialOut.println("MISS server="+sample.server+" scope="+scope+" frames="+receiptFrames.get()+" source="+Main.cartLeaseSource(player)+" ingress="+Main.cartLeaseIngress()+" position="+sample.buffer.position()+" limit="+sample.buffer.limit());
            initialOut.println(traceBytes.toString(java.nio.charset.StandardCharsets.UTF_8));
        }
        check(value!=null && value.length()<=160,"Exact native command receipt missing");
        check(value.equals(receipt(sample,sample.module,sample.command)),"Repeated API call allocated another receipt");sample.receipt=value;measured.add(sample);
        if(sample.mode.equals("nested")){
            zombie.Lua.LuaEventManager.triggerEvent("LeaseCostNested",sample.module,sample.command,table());
            check(value.equals(receipt(sample,sample.module,sample.command)),"Unrelated nested event damaged the native receipt");
        }
        if(sample.inner!=null){
            invoke(sample.inner,true);
            check(value.equals(receipt(sample,sample.module,sample.command)),"Reentrant native callback replaced the outer receipt");
            check(!value.equals(sample.inner.receipt),"Nested native callback reused the outer receipt");
        }
    }
    @SuppressWarnings("unchecked")
    private static void membership(boolean server)throws Exception {
        var actual=server?Main.cartLeaseSource(player):Main.cartLeaseIngress();
        check(actual==connection && Boolean.TRUE.equals(Main.cartLeaseConnectionActive(actual)),"Exact live native transport was not active");
        check(Main.cartLeaseConnectionActive(null)==null,"Null connection acquired a transport status");
        var unrelated=(Connection)unsafe.allocateInstance(Connection.class);unrelated.guid=3;engine.connections.put(3L,unrelated);
        try{check(Main.cartLeaseConnectionActive(unrelated)==null,"Uncaptured connection borrowed current engine membership");}
        finally{engine.connections.remove(3L);}
        check(Main.cartLeaseConnectionActive(foreignConnection)==null,"Captured foreign engine reported a retired connection");
        boolean clientRole=zombie.network.GameClient.client,serverRole=zombie.network.GameServer.server;
        zombie.network.GameClient.client=true;zombie.network.GameServer.server=true;
        try{check(Main.cartLeaseConnectionActive(actual)==null,"Mixed client/server role acquired transport status");}
        finally{zombie.network.GameClient.client=clientRole;zombie.network.GameServer.server=serverRole;}
        var ownEngine=server?zombie.network.GameServer.udpEngine:zombie.network.GameClient.instance.udpEngine;
        if(server)zombie.network.GameServer.udpEngine=null;else zombie.network.GameClient.instance.udpEngine=null;
        try{check(Main.cartLeaseConnectionActive(actual)==null,"Missing owning engine reported a disconnect");}
        finally{if(server)zombie.network.GameServer.udpEngine=ownEngine;else zombie.network.GameClient.instance.udpEngine=ownEngine;}
        var failed=field(Main.class,"leaseControlFailed");failed.setBoolean(null,true);
        try{check(Main.cartLeaseConnectionActive(actual)==null,"Failed native observer returned transport status");}
        finally{failed.setBoolean(null,false);}
        if(server){
            var target=(Peer)unsafe.allocateInstance(Peer.class);target.onlineId=8;target.playerIndex=0;
            var original=(Connection)unsafe.allocateInstance(Connection.class);original.guid=2;
            original.players=new zombie.characters.IsoPlayer[]{target,null,null,null};engine.connections.put(2L,original);
            zombie.network.GameServer.IDToPlayerMap.put((short)8,target);zombie.network.GameServer.PlayerToAddressMap.put(target,2L);
            try{
                check(Main.cartLeaseOwnerConnection(target)==original,"Target native membership was not captured");
                check(Boolean.TRUE.equals(Main.cartLeaseConnectionActive(original)),"Captured target connection not active");
                var retired=(Main.NativeWeakMap<zombie.core.raknet.UdpConnection,Boolean>)field(Main.class,"equipmentRetiredConnections").get(null);
                retired.put(original,true);
                zombie.network.GameServer.IDToPlayerMap.remove((short)8);zombie.network.GameServer.PlayerToAddressMap.remove(target);
                try{check(Boolean.TRUE.equals(Main.cartLeaseConnectionActive(original)),"Actor/equipment retirement was mistaken for transport disconnect");}
                finally{retired.remove(original);}
                var replacement=(Connection)unsafe.allocateInstance(Connection.class);replacement.guid=2;engine.connections.put(2L,replacement);
                check(Boolean.FALSE.equals(Main.cartLeaseConnectionActive(original)),"Same-GUID replacement left old connection active");
                check(Main.cartLeaseConnectionActive(replacement)==null,"Same-GUID replacement inherited original membership");
                engine.connections.remove(2L);
                check(Boolean.FALSE.equals(Main.cartLeaseConnectionActive(original)),"Removed exact GUID did not retire captured transport");
            }finally{engine.connections.remove(2L);zombie.network.GameServer.IDToPlayerMap.remove((short)8);zombie.network.GameServer.PlayerToAddressMap.remove(target);}
        }
        membershipChecks++;
    }
    private static void event(se.krka.kahlua.vm.LuaCallFrame frame,int count)throws Exception {
        var sample=active.peek();check(sample!=null,"Native callback has no active fixture");callbacks++;
        check(sample.module.equals(frame.get(0)) && sample.command.equals(frame.get(1)),"Native decoded header differs");
        Object args=frame.get(sample.server?3:2);
        if(sample.table){
            check(args instanceof se.krka.kahlua.vm.KahluaTable,"Native nested table missing");
            var nested=(se.krka.kahlua.vm.KahluaTable)((se.krka.kahlua.vm.KahluaTable)args).rawget("payload");
            check(nested!=null && "кириллица/é".equals(nested.rawget("inner")) && Double.valueOf(42).equals(nested.rawget("number")),"Original native table parser lost nested values");
        }else check(args==null,"Empty native command unexpectedly acquired a table");
        if(sample.mode.equals("membership-capture")){
            foreignConnection=sample.server?(Connection)Main.cartLeaseSource(player):(Connection)Main.cartLeaseIngress();
            check(foreignConnection==connection && Boolean.TRUE.equals(Main.cartLeaseConnectionActive(foreignConnection)),"Foreign engine setup did not capture original transport");
        }else if(sample.mode.equals("membership")){
            membership(sample.server);
        }else if(sample.mode.equals("foreign-buffer")){
            field(zombie.core.network.ByteBufferReader.class,"bb").set(sample.data.buffer,sample.buffer.duplicate().order(sample.order));try{check(receipt(sample,sample.module,sample.command)==null,"Foreign buffer accepted");}finally{field(zombie.core.network.ByteBufferReader.class,"bb").set(sample.data.buffer,sample.buffer);}
        }else if(sample.mode.equals("foreign-ingress")){
            var foreign=new Main.LeaseCommandIngress(++generation,sample.ingress.transport());ingresses.put(sample.data.buffer,foreign);
            check(receipt(sample,sample.module,sample.command)==null,"Foreign ingress generation accepted");
        }else if(sample.mode.equals("reset")){
            sample.data.reset();check(receipt(sample,sample.module,sample.command)==null,"Pooled reader reset retained receipt authority");
        }else if(sample.mode.equals("changed-limit")){
            sample.buffer.limit(sample.end+1);try{check(receipt(sample,sample.module,sample.command)==null,"Changed original limit accepted");}finally{sample.buffer.limit(sample.end);}
        }else if(sample.mode.equals("changed-order")){
            sample.buffer.order(sample.order==ByteOrder.BIG_ENDIAN?ByteOrder.LITTLE_ENDIAN:ByteOrder.BIG_ENDIAN);
            try{check(receipt(sample,sample.module,sample.command)==null,"Changed original byte order accepted");}finally{sample.buffer.order(sample.order);}
        }else if(sample.mode.equals("trailing") || sample.mode.equals("unguarded") || sample.mode.equals("synthetic") || sample.mode.equals("foreign-module")){
            check(receipt(sample,sample.module,sample.command)==null,"Partial, unguarded or synthetic callback obtained receipt");
        }else positive(sample);
    }
    private static void roles(boolean server){
        zombie.network.GameServer.server=server;zombie.network.GameClient.client=!server;
        zombie.network.GameServer.udpEngine=engine;zombie.network.GameClient.instance.udpEngine=engine;
        zombie.network.GameClient.instance.connected=true;zombie.network.GameClient.connection=connection;
        zombie.network.GameServer.IDToPlayerMap.put((short)7,player);zombie.network.GameServer.PlayerToAddressMap.put(player,1L);
        zombie.network.GameClient.IDToPlayerMap.put((short)7,player);
    }
    private static void seed(Sample sample){
        sample.ingress=new Main.LeaseCommandIngress(++generation,new Main.LeaseTransport(new java.lang.ref.WeakReference<>(engine),
            new java.lang.ref.WeakReference<>(connection),Main.nativeTimeIdentity(connection,false),1,TYPE));
        ingresses.put(sample.data.buffer,sample.ingress);
    }
    private static void invoke(Sample sample,boolean guarded)throws Exception {
        roles(sample.server);active.push(sample);if(guarded)seed(sample);Main.LeaseDispatchScope dispatch=null;
        if(!sample.server)dispatch=Main.leaseControlDispatchEnter(sample.data);
        try{
            if(sample.server)SERVER.invoke(null,sample.data.buffer,connection,TYPE);else CLIENT.invoke(null,sample.data.buffer,TYPE);
            if(callbackFailure!=null)throw new AssertionError("Native callback assertion failed",callbackFailure);
        }catch(java.lang.reflect.InvocationTargetException failed){
            Throwable cause=failed.getCause();if(cause instanceof Exception exception)throw exception;throw new AssertionError(cause);
        }finally{
            if(dispatch!=null)Main.leaseControlDispatchExit(dispatch);ingresses.remove(sample.data.buffer);active.pop();
            if(active.isEmpty())check(callbackScopes.get()==null && receiptFrames.get()==null,"Native callback/frame cleanup leaked");
        }
        check(Main.cartLeaseReceipt(sample.module,sample.command)==null,"Receipt escaped its native callback");
        if(!sample.mode.equals("reset"))check(sample.buffer.position()==(sample.mode.equals("trailing")?sample.end-1:sample.end)
            && sample.buffer.limit()==sample.end && sample.buffer.order()==sample.order && mark(sample.buffer)==sample.begin
            && java.util.Arrays.equals(sample.original,bytes(sample.buffer)),"Original parser/API changed native content/mark/limit/order");
    }
    @SuppressWarnings("unchecked")
    public static void main(String[] argv)throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        var scratch=java.nio.file.Path.of(System.getenv("PZ_CART_RUNTIME_FILE")).toAbsolutePath().getParent().getParent();
        zombie.ZomboidFileSystem.instance.setCacheDir(scratch.resolve("native-cache").toString());
        var access=field(sun.misc.Unsafe.class,"theUnsafe");unsafe=(sun.misc.Unsafe)access.get(null);
        engine=(Engine)unsafe.allocateInstance(Engine.class);engine.connections=new HashMap<>();connection=(Connection)unsafe.allocateInstance(Connection.class);connection.guid=1;engine.connections.put(1L,connection);
        player=(Owner)unsafe.allocateInstance(Owner.class);player.onlineId=7;player.playerIndex=0;player.username="client1";
        connection.players=new zombie.characters.IsoPlayer[]{player,null,null,null};
        ingresses=(Main.NativeWeakMap<zombie.core.network.ByteBufferReader,Main.LeaseCommandIngress>)field(Main.class,"leaseControlIngresses").get(null);
        callbackScopes=(ThreadLocal<?>)field(Main.class,"leaseControlCallback").get(null);receiptFrames=(ThreadLocal<?>)field(Main.class,"leaseReceiptFrames").get(null);
        var platform=se.krka.kahlua.j2se.J2SEPlatform.getInstance();zombie.Lua.LuaManager.env=platform.newEnvironment();
        zombie.Lua.LuaManager.env.rawset("Events",platform.newTable());zombie.GameWindow.gameThread=Thread.currentThread();
        zombie.Lua.LuaManager.thread=new se.krka.kahlua.vm.KahluaThread(platform,zombie.Lua.LuaManager.env);zombie.Lua.LuaManager.thread.debugOwnerThread=Thread.currentThread();
        zombie.Lua.LuaManager.caller=new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        zombie.Lua.LuaManager.env.rawset("nativeLeaseCost",(se.krka.kahlua.vm.JavaFunction)(frame,count)->{try{event(frame,count);}catch(Throwable failure){callbackFailure=failure;}return 0;});
        zombie.Lua.LuaManager.env.rawset("nestedLeaseCost",(se.krka.kahlua.vm.JavaFunction)(frame,count)->{
            try{var sample=active.peek();nestedEvents++;check(receipt(sample,sample.module,sample.command)==null,"Unrelated nested Lua event borrowed outer native receipt");check(Main.cartLeaseConnectionActive(connection)==null,"Unrelated nested event borrowed connection membership scope");}catch(Throwable failure){callbackFailure=failure;}return 0;
        });
        var event=se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring("nativeLeaseCost(...)","native-lease-cost",zombie.Lua.LuaManager.env);
        zombie.Lua.LuaEventManager.AddEvent("OnClientCommand").callbacks.add(event);zombie.Lua.LuaEventManager.AddEvent("OnServerCommand").callbacks.add(event);
        zombie.Lua.LuaEventManager.AddEvent("LeaseCostNested").callbacks.add(se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring("nestedLeaseCost(...)","nested-lease-cost",zombie.Lua.LuaManager.env));
        String process=Main.cartLeaseSeed(),fresh=Main.cartLeaseChallengeSeed(),other=Main.cartLeaseChallengeSeed();
        check(process!=null && process.equals(Main.cartLeaseSeed()) && fresh!=null && other!=null && fresh.length()<=80 && other.length()<=80
            && !fresh.equals(other) && !fresh.equals(process) && !other.equals(process),"Fresh challenge seeds reused process/receiver namespace");
        check(Main.cartLeaseReceipt("CartLeaseProbe","Bind")==null,"No-scope receipt accepted");
        check(Main.cartLeaseConnectionActive(connection)==null,"No-scope connection status accepted");
        System.setOut(new java.io.PrintStream(traceBytes,true,java.nio.charset.StandardCharsets.UTF_8));
        try {
            var originalEngine=engine;var originalConnection=connection;
            engine=(Engine)unsafe.allocateInstance(Engine.class);engine.connections=new HashMap<>();
            connection=(Connection)unsafe.allocateInstance(Connection.class);connection.guid=1;connection.players=originalConnection.players;engine.connections.put(1L,connection);
            try{invoke(new Sample("CartLeaseLifetimes","Capture","membership-capture",true,false,ByteOrder.BIG_ENDIAN,false),true);}
            finally{engine=originalEngine;connection=originalConnection;}
            for(boolean server:new boolean[]{false,true})invoke(new Sample("CartLeaseLifetimes","Membership","membership",server,false,ByteOrder.BIG_ENDIAN,false),true);
            check(membershipChecks==2 && Main.cartLeaseConnectionActive(connection)==null,"Transport membership check escaped native callback");
            for(boolean server:new boolean[]{false,true})for(String module:new String[]{"CartLeaseProbe","CartLeaseLifetimes","CartActionAdmissionProbe"})
                invoke(new Sample(module,"Query","normal",server,true,ByteOrder.BIG_ENDIAN,false),true);
            invoke(new Sample("CartLeaseProbe","Empty","normal",false,false,ByteOrder.LITTLE_ENDIAN,true),true);
            invoke(new Sample("CartLeaseLifetimes","Nested","nested",false,true,ByteOrder.BIG_ENDIAN,false),true);
            for(boolean server:new boolean[]{false,true}){
                var outer=new Sample("CartLeaseProbe","Outer","normal",server,true,ByteOrder.BIG_ENDIAN,false);
                outer.inner=new Sample("CartActionAdmissionProbe","Inner","normal",server,true,ByteOrder.BIG_ENDIAN,false);invoke(outer,true);
            }
            for(String mode:new String[]{"trailing","unguarded","foreign-buffer","foreign-ingress","changed-limit","changed-order","reset"})
                invoke(new Sample("CartLeaseLifetimes",mode,mode,false,true,ByteOrder.BIG_ENDIAN,false),!mode.equals("unguarded"));
            invoke(new Sample("UnownedModule","Foreign","foreign-module",true,true,ByteOrder.BIG_ENDIAN,false),true);
            // A manually entered scope and synthetic event cannot stand in for the original native parser.
            var synthetic=new Sample("CartLeaseProbe","Synthetic","synthetic",false,true,ByteOrder.BIG_ENDIAN,false);roles(false);seed(synthetic);
            var dispatch=Main.leaseControlDispatchEnter(synthetic.data);var scope=Main.leaseControlClientEnter(synthetic.data.buffer,TYPE);
            synthetic.buffer.position(synthetic.end);active.push(synthetic);
            try{check(Main.cartLeaseReceipt(synthetic.module,synthetic.command)==null,"Synthetic complete cursor bypassed native parser");zombie.Lua.LuaEventManager.triggerEvent("OnServerCommand",synthetic.module,synthetic.command,table());}
            finally{active.pop();Main.leaseControlCallbackExit(scope);Main.leaseControlDispatchExit(dispatch);ingresses.remove(synthetic.data.buffer);}
            check(callbackFailure==null && receiptFrames.get()==null && callbackScopes.get()==null,"Synthetic scope cleanup failed");
            // Native header truncation throws before the event; neither duplicate decode nor cleanup changes its state.
            var truncated=new Sample("CartLeaseProbe","Truncated","normal",false,false,ByteOrder.BIG_ENDIAN,false);
            truncated.buffer.limit(truncated.begin+3);int before=callbacks;
            try{invoke(truncated,true);throw new AssertionError("Truncated native UTF header accepted");}catch(java.nio.BufferUnderflowException expected){}
            check(callbacks==before && receiptFrames.get()==null && callbackScopes.get()==null,"Truncated native parser emitted or leaked a callback");
        }finally{System.setOut(initialOut);}
        String trace=traceBytes.toString(java.nio.charset.StandardCharsets.UTF_8);var lines=trace.lines().filter(line->line.startsWith("[CART_LEASE_BYTES] ")).toList();
        check(lines.size()==measured.size() && measured.size()==12 && nestedEvents==1,"Native byte rows are missing, duplicated or attributed to rejected calls");
        var tokens=new java.util.HashSet<String>();
        for(var sample:measured){
            check(tokens.add(sample.receipt),"Receipt token reused across native callbacks");
            var matches=lines.stream().filter(line->line.contains("\"receipt\":\""+sample.receipt+"\"")).toList();
            check(matches.size()==1,"Exact native callback trace missing");String row=matches.get(0);
            check(row.contains("\"payloadBytes\":"+sample.payload+",") && row.contains("\"engineBytes\":"+(sample.payload+3)+",")
                && row.contains("\"direction\":\""+(sample.server?"client-to-server":"server-to-client")+"\"")
                && row.contains("\"ingressGeneration\":"+sample.ingress.generation()+","),"Native byte count/direction/source differs from serialized sample");
        }
        check(!trace.contains("[CART_TIMELINE] ERROR"),"Native receipt observer failed closed unexpectedly");
        for(String line:lines)initialOut.println(line);
        initialOut.println("LEASE_CONNECTION_ACTIVITY_CHECK_PASS roles="+membershipChecks+" exact-map replacement removed-guid actor-retirement unknown foreign-engine missing-engine wrong-role scope fail-closed");
        initialOut.println("LEASE_COST_CHECK_PASS rows="+lines.size()+" callbacks="+callbacks);
    }
}
