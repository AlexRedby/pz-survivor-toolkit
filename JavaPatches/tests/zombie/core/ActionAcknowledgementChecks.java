package zombie.core;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Accessor;
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgements;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import sun.misc.Unsafe;
import zombie.GameTime;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.core.raknet.UdpEngine;
import zombie.iso.IsoCell;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.TableNetworkUtils;

public final class ActionAcknowledgementChecks {
    static Unsafe unsafe;
    static final byte ID = -126;

    public static final class Player extends IsoPlayer {
        Player() { super(null); }
        public zombie.inventory.InventoryItem getPrimaryHandItem() { return null; }
        public boolean isCurrentState(zombie.ai.State state) { return false; }
    }
    public static final class Connection extends UdpConnection {
        ByteBuffer bytes;
        ArrayList<KahluaTable> messages;
        ArrayList<String> order;
        boolean fail;
        int canceled;
        Connection() { super(null, 0, 0); }
        public boolean isFullyConnected() { return true; }
        public ByteBufferWriter startPacket() {
            bytes.clear(); return new ByteBufferWriter(bytes);
        }
        public void cancelPacket() { canceled++; }
        public void endPacket(int priority, int reliability, byte channel) {
            require(reliability == 3 && channel == 1, "receipt/native action lost ordered channel 1");
            bytes.flip(); var reader = new ByteBufferReader(bytes); reader.getByte(); short type = reader.getShort();
            if (type == PacketTypes.PacketType.ClientCommand.getId()) {
                String module = reader.getUTF(), command = reader.getUTF();
                if (fail && module.equals("PZSurvivorToolkitActions")) throw new IllegalStateException("fixture receipt transport unavailable");
                require(command.equals("State") && reader.getBoolean(), "invalid receipt envelope");
                var data = LuaManager.platform.newTable();
                try { TableNetworkUtils.load(data, reader); } catch (Exception error) { throw new AssertionError(error); }
                require(module.equals("PZSurvivorToolkitActions") || module.equals("PZSurvivorToolkitBuild"), "unknown receipt module");
                order.add(module + ":" + data.rawget("state"));
                if (module.equals("PZSurvivorToolkitActions")) messages.add(data);
            } else {
                require(type == PacketTypes.PacketType.BuildAction.getId() || type == PacketTypes.PacketType.NetTimedAction.getId(), "unexpected native packet");
                reader.getByte(); order.add("native:" + reader.getEnum(Transaction.TransactionState.class));
            }
        }
    }
    static final class Build extends BuildAction {
        int performed;
        public float getDuration() { return 10000; }
        public boolean perform() { performed++; return super.perform(); }
    }
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static Field field(Class<?> type, String name) throws Exception {
        var result = type.getDeclaredField(name); result.setAccessible(true); return result;
    }
    static Connection connection() throws Exception {
        Connection result = (Connection)unsafe.allocateInstance(Connection.class);
        result.bytes = ByteBuffer.allocate(8192); result.messages = new ArrayList<>(); result.order = new ArrayList<>();
        require(Accessor.trySet(result, "limits", new HashMap<>()), "fixture connection packet limits");
        return result;
    }
    static IsoPlayer player(short id, long address) throws Exception {
        IsoPlayer result = (IsoPlayer)unsafe.allocateInstance(Player.class); result.onlineId = id;
        require(Accessor.trySet(result, "ecsComponentMap", new HashMap<>()), "fixture player components");
        GameServer.PlayerToAddressMap.put(result, address); return result;
    }
    static void identify(Action action, IsoPlayer player) {
        action.id = ID; action.state = Transaction.TransactionState.Request; action.playerId.setID(player.onlineId);
        require(Accessor.trySet(action.playerId, "player", player), "fixture owner");
    }
    static NetTimedAction timed(IsoPlayer player, boolean succeeds) throws Exception {
        NetTimedAction action = new NetTimedAction(); identify(action, player); action.type = "ToolkitAckProbe";
        String code = "return {performed=0, stopped=0, getDuration=function(self) return 10000 end, "
            + "adjustMaxTime=function(self,duration) return duration+0 end, "
            + "serverStop=function(self) self.stopped=self.stopped+1 end, "
            + "complete=function(self) self.performed=self.performed+1 return " + succeeds + " end}";
        action.action = (KahluaTable)LuaManager.thread.call(LuaCompiler.loadstring(code, "ToolkitAckProbe", LuaManager.env), null, null, null);
        return action;
    }
    static Build build(IsoPlayer player) {
        Build action = new Build(); identify(action, player); action.item = LuaManager.platform.newTable(); return action;
    }
    static LuaTimedActionNew nativeClientAction(IsoPlayer player, boolean custom, String type) throws Exception {
        LuaTimedActionNew action = (LuaTimedActionNew)unsafe.allocateInstance(LuaTimedActionNew.class);
        KahluaTable table = (KahluaTable)LuaManager.thread.call(LuaCompiler.loadstring(
            "return {Type='" + type + "', start=function(self) self.transactionId=-126 end, "
                + "name='ack-client', getDuration=function(self) return 10000 end, isUsingTimeout=function(self) return true end}",
            "ToolkitClientAckProbe", LuaManager.env), null, null, null);
        KahluaTable metatable = LuaManager.platform.newTable(); metatable.rawset("Type", type);
        metatable.rawset("new", LuaCompiler.loadstring("return nil", "new", LuaManager.env)); table.setMetatable(metatable);
        require(Accessor.trySet(action, "table", table) && Accessor.trySet(action, "chr", player)
            && Accessor.trySet(action, "useCustomRemoteTimedActionSync", custom)
            && Accessor.trySet(action, "playerId", new zombie.network.fields.character.PlayerID()), "fixture native Lua action");
        return action;
    }
    static void start(Action action) { ActionManager.start(action); action.state = Transaction.TransactionState.Accept; }
    static KahluaTable last(Connection connection, String state) {
        require(!connection.messages.isEmpty(), "missing " + state + " receipt");
        KahluaTable data = connection.messages.get(connection.messages.size() - 1);
        require(state.equals(data.rawget("state")), "wrong terminal state: " + data.rawget("state"));
        require(data.rawget("protocol").equals(1.0) && data.rawget("player") instanceof Double
            && data.rawget("transaction").equals((double)ID), "invalid native wire identity");
        require(data.rawget("token") instanceof String && ((String)data.rawget("token")).length() == 36, "missing UUID identity");
        return data;
    }
    static void settle(Action action) { action.endTime = 0; ActionManager.update(); }
    static void sameToken(KahluaTable started, KahluaTable terminal) {
        require(started.rawget("token").equals(terminal.rawget("token")), "terminal changed action token");
    }
    static void ordered(Connection connection, String nativeState, String receipt) {
        require(connection.order.lastIndexOf("native:" + nativeState)
                < connection.order.lastIndexOf("PZSurvivorToolkitActions:" + receipt)
            && connection.order.contains("native:" + nativeState), "receipt preceded native outcome");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        unsafe = (Unsafe)field(Unsafe.class, "theUnsafe").get(null);
        GameTime.setInstance(new GameTime()); LuaManager.platform = new J2SEPlatform(); LuaManager.env = LuaManager.platform.newTable();
        LuaManager.env.rawset("Events", LuaManager.platform.newTable());
        LuaManager.thread = new se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        IsoWorld.instance.currentCell = (IsoCell)unsafe.allocateInstance(IsoCell.class);
        require(Accessor.trySet(zombie.network.ServerMap.instance, "grid", unsafe.allocateInstance(zombie.iso.IsoMetaGrid.class)), "fixture grid");
        Connection first = connection(), second = connection();
        UdpEngine engine = (UdpEngine)unsafe.allocateInstance(UdpEngine.class);
        field(UdpEngine.class, "connectionMap").set(engine, new HashMap<>(Map.of(1L, first, 2L, second)));
        GameServer.udpEngine = engine; GameServer.server = true; GameClient.client = false;
        IsoPlayer player = player((short)19, 1L), other = player((short)20, 2L);

        NetTimedAction baseline = timed(player, true); start(baseline); settle(baseline);
        require(baseline.action.rawget("performed").equals(1.0) && first.messages.isEmpty(), "original native completion/receipt baseline changed");
        NetTimedAction baselineStop = timed(player, true); start(baselineStop); ActionManager.stop(baselineStop);
        require(baselineStop.action.rawget("stopped").equals(1.0) && first.messages.isEmpty(), "original native cancellation baseline changed");
        GameServer.server = false; GameClient.client = true;
        LuaTimedActionNew baselineClient = nativeClientAction(player, true, "ISBuildAction"); baselineClient.start();
        require(baselineClient.getTable().rawget("toolkitNativeTransaction") == null, "unpatched client gained transaction proof");
        GameServer.server = true; GameClient.client = false;
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ActionAcknowledgementChecks.class.getClassLoader());
        require(ActionAcknowledgements.SUPPORTED, "unsupported native acknowledgement targets");

        NetTimedAction completed = timed(player, true); start(completed); KahluaTable started = last(first, "started");
        require(started.rawget("kind").equals("ToolkitAckProbe") && started.rawget("player").equals(19.0), "wrong action type/owner");
        int count = first.messages.size(); ActionAcknowledgements.started(completed);
        require(first.messages.size() == count, "duplicate start emitted a token");
        settle(completed); sameToken(started, last(first, "completed")); ordered(first, "Done", "completed");
        count = first.messages.size(); ActionManager.stop(completed); ActionManager.update();
        require(first.messages.size() == count && completed.action.rawget("performed").equals(1.0), "completion-before-cancel replayed effects or receipts");

        NetTimedAction canceled = timed(player, true), foreign = timed(other, true); start(canceled); started = last(first, "started"); start(foreign);
        require(!started.rawget("token").equals(last(second, "started").rawget("token")), "different owners reused token");
        ActionManager.stop(canceled); sameToken(started, last(first, "canceled"));
        count = first.messages.size(); ActionManager.stop(canceled); canceled.endTime = 0; ActionManager.update();
        require(first.messages.size() == count && canceled.action.rawget("performed").equals(0.0)
            && canceled.action.rawget("stopped").equals(1.0), "cancel-before-update executed or duplicated cancellation");
        require(foreign.state == Transaction.TransactionState.Accept && second.messages.size() == 1, "same byte id canceled another owner");
        ActionManager.stop(foreign); last(second, "canceled");
        NetTimedAction quietCancel = timed(player, true); start(quietCancel); started = last(first, "started");
        ActionManager.remove(quietCancel.playerId, quietCancel.id, false);
        sameToken(started, last(first, "canceled"));
        require(quietCancel.action.rawget("stopped").equals(1.0), "server remove(false) did not preserve native stop");

        NetTimedAction reused = timed(player, false); start(reused); KahluaTable reusedStart = last(first, "started");
        require(!reusedStart.rawget("token").equals(started.rawget("token")), "reused byte id inherited old token");
        settle(reused); sameToken(reusedStart, last(first, "rejected")); ordered(first, "Reject", "rejected");
        require(reused.action.rawget("performed").equals(1.0), "native Lua complete(false) not executed");

        Build building = build(player); start(building); started = last(first, "started");
        require(started.rawget("kind").equals("build"), "build receipt used generic Lua type");
        settle(building); sameToken(started, last(first, "completed"));
        require(building.performed == 1, "build receipt bypassed native perform"); ordered(first, "Done", "completed");
        Build stoppedBuild = build(player); start(stoppedBuild); started = last(first, "started");
        ActionManager.stop(stoppedBuild); sameToken(started, last(first, "canceled"));

        count = first.messages.size(); GameServer.server = false;
        NetTimedAction local = timed(player, true); start(local); ActionManager.stop(local);
        require(first.messages.size() == count, "single-player emitted multiplayer permission receipts");
        GameClient.client = true; ActionAcknowledgements.started(timed(player, true));
        require(first.messages.size() == count, "client emitted server receipt");
        GameClient.client = false; GameServer.server = true;
        first.fail = true;
        NetTimedAction transportFailure = timed(player, true); start(transportFailure); settle(transportFailure);
        require(transportFailure.state == Transaction.TransactionState.Done && transportFailure.action.rawget("performed").equals(1.0),
            "receipt transport failure interrupted native action lifecycle");
        first.fail = false;
        require(((Map<?, ?>)field(ActionAcknowledgements.class, "tokens").get(null)).isEmpty(), "terminal actions retained acknowledgement tokens");
        GameServer.server = false; GameClient.client = true; GameClient.connection = first;
        LuaTimedActionNew clientBuild = nativeClientAction(player, true, "ISBuildAction"); clientBuild.start();
        require(clientBuild.getTable().rawget("toolkitNativeTransaction").equals((double)ID)
            && clientBuild.getTable().rawget("toolkitNativeKind").equals("build"), "woven native client start did not bind custom build id");
        LuaTimedActionNew unknownCustom = nativeClientAction(player, true, "OtherCustomAction"); unknownCustom.start();
        require(unknownCustom.getTable().rawget("toolkitNativeTransaction") == null, "unsupported custom synchronizer gained proof");
        LuaTimedActionNew standard = nativeClientAction(player, false, "ToolkitAckProbe"); standard.start();
        Byte nativeId = Accessor.tryGet(standard, "transactionId", (Byte)null);
        require(nativeId != null && nativeId != 0 && standard.getTable().rawget("toolkitNativeTransaction").equals((double)nativeId)
            && standard.getTable().rawget("toolkitNativeKind").equals("ToolkitAckProbe"), "woven standard start did not bind native manager id/type: native="
                + nativeId + ", proof=" + standard.getTable().rawget("toolkitNativeTransaction") + ", kind=" + standard.getTable().rawget("toolkitNativeKind"));
        System.out.println("ACTION_ACKNOWLEDGEMENT_CHECKS_PASS (native Lua completion true/false, build, cancellation races, duplicate/reused IDs, owner isolation, ordered wire, role guards, transport failure)");
    }
}
