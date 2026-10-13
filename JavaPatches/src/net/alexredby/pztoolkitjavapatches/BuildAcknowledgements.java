package net.alexredby.pztoolkitjavapatches;

import java.util.UUID;
import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Accessor;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.core.BuildAction;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.TableNetworkUtils;
import zombie.network.fields.character.PlayerID;

public final class BuildAcknowledgements {
    private static final WeakHashMap<BuildAction, String> tokens = new WeakHashMap<>();

    public static synchronized void started(BuildAction action) {
        String token = UUID.randomUUID().toString();
        tokens.put(action, token);
        send(action, token, "started");
    }

    public static synchronized void settled(BuildAction action, String state) {
        String token = tokens.remove(action);
        if (token != null) send(action, token, state);
    }

    private static void send(BuildAction action, String token, String state) {
        PlayerID owner = Accessor.tryGet(action, "playerId", null);
        Byte transaction = Accessor.tryGet(action, "id", null);
        if (owner == null || owner.getPlayer() == null || transaction == null || transaction == 0) return;
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("player", (double)owner.getID());
        args.rawset("transaction", (double)transaction);
        args.rawset("token", token);
        args.rawset("state", state);
        UdpConnection connection = GameServer.getConnectionFromPlayer(owner.getPlayer());
        if (connection == null) return;
        try {
            var writer = connection.startPacket();
            PacketTypes.PacketType.ClientCommand.doPacket(writer);
            writer.putUTF("PZSurvivorToolkitBuild");
            writer.putUTF("State");
            writer.putBoolean(true);
            TableNetworkUtils.save(args, writer);
            // Share BuildAction's ordered channel so an old start cannot attach to a reused byte ID.
            connection.endPacket(1, 3, (byte)1);
        } catch (Exception error) {
            connection.cancelPacket();
            throw new IllegalStateException("Cannot send build acknowledgement", error);
        }
    }
}
