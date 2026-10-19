package zombie.core;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import net.alexredby.pztoolkitjavapatches.BytecodeSupport;
import net.alexredby.pztoolkitjavapatches.Main;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.KahluaTable;
import sun.misc.Unsafe;
import zombie.GameTime;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.core.raknet.UdpEngine;
import zombie.iso.IsoCell;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.TableNetworkUtils;
import zombie.network.packets.GeneralActionPacket;

public final class BuildChecks {
    static Unsafe unsafe;
    static Connection connection;

    static final class Player extends IsoPlayer {
        Player() { super(null); }
        public zombie.inventory.InventoryItem getPrimaryHandItem() { return null; }
    }

    static final class Connection extends UdpConnection {
        ByteBuffer bytes;
        ArrayList<KahluaTable> messages;
        Connection() { super(null, 0, 0); }
        public ByteBufferWriter startPacket() { bytes.clear(); return new ByteBufferWriter(bytes); }
        public boolean isFullyConnected() { return false; }
        public void endPacket(int priority, int reliability, byte channel) {
            require(reliability == 3 && channel == 1, "acknowledgements must share native build ordering");
            bytes.flip();
            ByteBufferReader reader = new ByteBufferReader(bytes);
            reader.getByte(); reader.getShort();
            String module = reader.getUTF(), command = reader.getUTF();
            if (module.equals("PZSurvivorToolkitActions")) return;
            if (!module.equals("PZSurvivorToolkitBuild") || !command.equals("State"))
                throw new AssertionError("unexpected command " + module + "/" + command);
            if (!reader.getBoolean()) throw new AssertionError("missing payload");
            KahluaTable data = LuaManager.platform.newTable();
            try { TableNetworkUtils.load(data, reader); } catch (Exception error) { throw new AssertionError(error); }
            messages.add(data);
        }
    }

    static final class Build extends BuildAction {
        int performed;
        public float getDuration() { return 10000; }
        // Count only native scheduled completion; the actual BuildAction.perform remains woven.
        public boolean perform() { performed++; return super.perform(); }
    }

    static void set(Object owner, String name, Object value) throws Exception {
        Field field = owner.getClass().getDeclaredField(name);
        field.setAccessible(true); field.set(owner, value);
    }

    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    static Build build(IsoPlayer player, byte id) {
        Build action = new Build();
        action.playerId.setID(player.onlineId);
        require(me.zed_0xff.zombie_buddy.Accessor.trySet(action.playerId, "player", player), "fixture owner");
        action.id = id;
        action.item = LuaManager.platform.newTable();
        ActionManager.start(action);
        action.state = Transaction.TransactionState.Accept;
        return action;
    }

    static KahluaTable last(String state) {
        KahluaTable data = connection.messages.get(connection.messages.size() - 1);
        require(state.equals(data.rawget("state")), "expected " + state + " got " + data.rawget("state"));
        require(data.rawget("player") instanceof Double && data.rawget("transaction") instanceof Double,
            "wire IDs must use Lua numbers");
        require(data.rawget("token") instanceof String, "wire token must be a string");
        return data;
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Field field = Unsafe.class.getDeclaredField("theUnsafe"); field.setAccessible(true);
        unsafe = (Unsafe)field.get(null);
        GameTime.setInstance(new GameTime());
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newTable();
        LuaManager.env.rawset("Events", LuaManager.platform.newTable());
        LuaManager.thread = new se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new se.krka.kahlua.integration.LuaCaller(new se.krka.kahlua.converter.KahluaConverterManager());
        IsoWorld.instance.currentCell = (IsoCell)unsafe.allocateInstance(IsoCell.class);
        require(me.zed_0xff.zombie_buddy.Accessor.trySet(zombie.network.ServerMap.instance, "grid",
            unsafe.allocateInstance(zombie.iso.IsoMetaGrid.class)), "fixture server grid");
        connection = (Connection)unsafe.allocateInstance(Connection.class);
        connection.bytes = ByteBuffer.allocate(4096); connection.messages = new ArrayList<>();
        UdpEngine engine = (UdpEngine)unsafe.allocateInstance(UdpEngine.class);
        set(engine, "connectionMap", new HashMap<>(java.util.Map.of(1L, connection)));
        GameServer.udpEngine = engine;
        IsoPlayer player = (IsoPlayer)unsafe.allocateInstance(Player.class); player.onlineId = 19;
        GameServer.PlayerToAddressMap.put(player, 1L);
        GameClient.client = false; GameServer.server = true;

        Build baseline = build(player, (byte)-126);
        require(connection.messages.isEmpty(), "unpatched engine already acknowledged start");
        ActionManager.stop(baseline);
        require(connection.messages.isEmpty(), "unpatched engine already acknowledged stop");

        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", BuildChecks.class.getClassLoader());
        require(Main.BUILD_SUPPORTED, "unsupported native engine");
        Build canceled = build(player, (byte)-126);
        KahluaTable started = last("started");
        require(started.rawget("transaction").equals(-126.0) && started.rawget("player").equals(19.0), "wrong owner/id");
        IsoPlayer otherPlayer = (IsoPlayer)unsafe.allocateInstance(Player.class); otherPlayer.onlineId = 20;
        Build other = build(otherPlayer, (byte)-126);
        GeneralActionPacket reject = new GeneralActionPacket();
        reject.id = (byte)-126; reject.playerId.copy(canceled.playerId); reject.state = Transaction.TransactionState.Reject;
        reject.processServer(null, connection);
        KahluaTable terminal = last("canceled");
        require(terminal.rawget("token").equals(started.rawget("token")), "stop changed token");
        int messages = connection.messages.size();
        reject.processServer(null, connection); canceled.endTime = 0; ActionManager.update();
        require(connection.messages.size() == messages && canceled.performed == 0, "duplicate reject or late update re-completed canceled build");
        require(other.state == Transaction.TransactionState.Accept && other.performed == 0, "same byte ID canceled another player's build");
        ActionManager.stop(other);

        Build completed = build(player, (byte)-126);
        KahluaTable secondStart = last("started");
        require(!secondStart.rawget("token").equals(started.rawget("token")), "reused byte id reused token");
        completed.endTime = 0; ActionManager.update();
        terminal = last("completed");
        require(terminal.rawget("token").equals(secondStart.rawget("token")) && completed.performed == 1, "completion lost identity");
        messages = connection.messages.size();
        reject.processServer(null, connection); completed.stop(); ActionManager.update();
        require(connection.messages.size() == messages && completed.performed == 1, "completed build emitted cancellation or replayed");

        Build untracked = new Build(); untracked.stop();
        require(connection.messages.size() == messages, "untracked stop acknowledged cancellation");
        GameServer.server = false; GameClient.client = true; canceled.stop();
        require(connection.messages.size() == messages, "client emitted server acknowledgement");
        field = net.alexredby.pztoolkitjavapatches.BuildAcknowledgements.class.getDeclaredField("tokens"); field.setAccessible(true);
        require(((java.util.Map<?, ?>)field.get(null)).isEmpty(), "terminal builds retained tokens");
        require(!BytecodeSupport.supports("zombie/core/BuildAction.class", "unknown"), "unknown engine fingerprint accepted");
        System.out.println("BUILD_CHECKS_PASS (native reject, completion race, token cleanup, reused byte ID, wire serialization, authority guards)");
    }
}
