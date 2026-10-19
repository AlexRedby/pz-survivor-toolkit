package net.alexredby.pztoolkitjavapatches;

import java.util.ArrayList;
import java.util.WeakHashMap;
import java.util.UUID;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.core.BuildAction;
import zombie.core.NetTimedAction;
import zombie.core.Transaction.TransactionState;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.TableNetworkUtils;
import zombie.network.fields.character.PlayerID;

/** Outcomes of existing native actions; the native managers still execute all effects. */
public final class ActionAcknowledgements {
    public static final boolean SUPPORTED = Main.BUILD_SUPPORTED
        && BytecodeSupport.supports("zombie/core/NetTimedAction.class", "d4a3046eeaec409977a756c6ea80b0676229274684012ad51210559ebfcb1090")
        && BytecodeSupport.supports("zombie/characters/CharacterTimedActions/LuaTimedActionNew.class", "f10236f1e8be9d0822dc144ebe61c42fa1d0e8ded3279c7aa6dd0ffb7291feb0")
        && BytecodeSupport.supports("zombie/network/packets/NetTimedActionPacket.class", "ce367190ce6158eb88809f3215ebc471e6161896d9d526eb9ef0e73d58de847b");
    private static final WeakHashMap<Object, String> tokens = new WeakHashMap<>();

    public static synchronized void started(Object action) {
        if (!SUPPORTED || !GameServer.server || !(action instanceof BuildAction || action instanceof NetTimedAction)
                || tokens.containsKey(action)) return;
        String token = UUID.randomUUID().toString();
        tokens.put(action, token);
        send(action, token, "started");
    }

    public static synchronized ArrayList<Object> pending() {
        return SUPPORTED && GameServer.server ? new ArrayList<>(tokens.keySet()) : null;
    }

    public static synchronized void settled(ArrayList<Object> before, boolean removed) {
        if (before == null || !GameServer.server) return;
        for (Object action : before) {
            TransactionState state = Accessor.tryGet(action, "state", (TransactionState)null);
            String outcome = state == TransactionState.Done ? "completed"
                : state == TransactionState.Reject ? "rejected" : removed ? "canceled" : null;
            if (outcome == null) continue;
            String token = tokens.remove(action);
            if (token != null) send(action, token, outcome);
        }
    }

    public static synchronized ArrayList<Object> removing(PlayerID player, byte id, boolean canceled) {
        // On the server native remove stops actions for either flag; the flag controls only client sending.
        if (!SUPPORTED || !GameServer.server || player == null) return null;
        ArrayList<Object> result = new ArrayList<>();
        for (Object action : tokens.keySet()) {
            PlayerID owner = Accessor.tryGet(action, "playerId", (PlayerID)null);
            Byte transaction = Accessor.tryGet(action, "id", (Byte)null);
            if (owner != null && owner.getID() == player.getID() && transaction != null && transaction == id)
                result.add(action);
        }
        return result;
    }

    private static void send(Object action, String token, String state) {
        PlayerID owner = Accessor.tryGet(action, "playerId", (PlayerID)null);
        Byte transaction = Accessor.tryGet(action, "id", (Byte)null);
        if (owner == null || owner.getPlayer() == null || transaction == null || transaction == 0) return;
        var connection = GameServer.getConnectionFromPlayer(owner.getPlayer());
        if (connection == null) return;
        KahluaTable args = LuaManager.platform.newTable();
        args.rawset("protocol", 1.0);
        args.rawset("player", (double)owner.getID());
        args.rawset("transaction", (double)transaction);
        args.rawset("token", token);
        args.rawset("state", state);
        args.rawset("kind", action instanceof BuildAction ? "build" : ((NetTimedAction)action).type);
        try {
            var writer = connection.startPacket();
            PacketTypes.PacketType.ClientCommand.doPacket(writer);
            writer.putUTF("PZSurvivorToolkitActions");
            writer.putUTF("State");
            writer.putBoolean(true);
            TableNetworkUtils.save(args, writer);
            // Native Accept/Done and these receipts share reliable ordered channel 1.
            connection.endPacket(1, 3, (byte)1);
        } catch (Exception error) {
            connection.cancelPacket();
            System.err.println("[PZToolkitJavaPatches] Cannot send action acknowledgement: " + error);
        }
    }

    public static void bind(LuaTimedActionNew nativeAction) {
        if (!SUPPORTED || !GameClient.client) return;
        KahluaTable action = nativeAction.getTable();
        boolean custom = Accessor.tryGet(nativeAction, "useCustomRemoteTimedActionSync", true);
        Object type = action.rawget("Type");
        Object transaction = custom ? action.rawget("transactionId")
            : Accessor.tryGet(nativeAction, "transactionId", (Byte)null);
        if (!(transaction instanceof Number id) || id.byteValue() == 0
                || (custom && !"ISBuildAction".equals(type))) return;
        action.rawset("toolkitNativeTransaction", (double)id.byteValue());
        action.rawset("toolkitNativeKind", custom ? "build" : type);
    }

    @Patch(className="zombie.core.ActionManager", methodName="start", warmUp=true, strictMatch=true)
    public static class Started {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Argument(0) Object action) { started(action); }
    }

    @Patch(className="zombie.core.ActionManager", methodName="update", warmUp=true, strictMatch=true)
    public static class Updated {
        @Patch.OnEnter
        public static void enter(@Patch.Local("toolkitPendingActions") ArrayList<Object> before) { before = pending(); }
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Local("toolkitPendingActions") ArrayList<Object> before) { settled(before, false); }
    }

    @Patch(className="zombie.core.ActionManager", methodName="remove", warmUp=true, strictMatch=true)
    public static class Removed {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) PlayerID player, @Patch.Argument(1) byte id,
                @Patch.Argument(2) boolean canceled, @Patch.Local("toolkitRemovedActions") ArrayList<Object> before) {
            before = removing(player, id, canceled);
        }
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Local("toolkitRemovedActions") ArrayList<Object> before) { settled(before, true); }
    }

    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="start", warmUp=true, strictMatch=true)
    public static class Bound {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This LuaTimedActionNew action) { bind(action); }
    }
}
