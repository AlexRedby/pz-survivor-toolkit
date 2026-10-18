package net.alexredby.queueengineprobe;

import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgements;
import zombie.core.ActionManager;
import zombie.core.NetTimedAction;
import zombie.core.Transaction.TransactionState;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;

/** Read-only evidence at the actual cancellation boundary; never schedules or changes an action. */
public final class Main {
    public static void main(String[] args) {
        System.out.println("[ENGINE_TEST] PROBE active=" + ActionAcknowledgements.SUPPORTED);
    }

    public record Overlap(Object other, byte id, short first, short second, String firstToken, String secondToken) { }

    public static Overlap before(PlayerID owner, byte id) {
        if (!GameServer.server || owner == null || owner.getPlayer() == null
                || !"client1".equals(owner.getPlayer().getUsername())) return null;
        var actions = Accessor.tryGet(ActionManager.class, "actions", (ConcurrentLinkedQueue<?>)null);
        var tokens = Accessor.tryGet(ActionAcknowledgements.class, "tokens", (Map<?, ?>)null);
        if (actions == null || tokens == null) return null;
        Object target = null, other = null;
        for (Object action : actions) {
            if (!(action instanceof NetTimedAction timed) || !"ISFixGenerator".equals(timed.type)) continue;
            Byte transaction = Accessor.tryGet(action, "id", (Byte)null);
            if (transaction == null || transaction != id) continue;
            PlayerID player = Accessor.tryGet(action, "playerId", (PlayerID)null);
            if (player != null && player.getID() == owner.getID()) target = action;
            else if (player != null) other = action;
        }
        if (target == null) return null;
        if (other == null || Accessor.tryGet(target, "state", (TransactionState)null) != TransactionState.Accept
                || Accessor.tryGet(other, "state", (TransactionState)null) != TransactionState.Accept
                || !(tokens.get(target) instanceof String firstToken) || !(tokens.get(other) instanceof String secondToken)) {
            System.out.println("[QUEUE_TEST] FAIL engine cancel lacked simultaneous pending same-ID peer");
            return null;
        }
        PlayerID second = Accessor.tryGet(other, "playerId", (PlayerID)null);
        return new Overlap(other, id, owner.getID(), second.getID(), firstToken, secondToken);
    }

    public static void after(Overlap overlap) {
        if (overlap == null) return;
        var actions = Accessor.tryGet(ActionManager.class, "actions", (ConcurrentLinkedQueue<?>)null);
        boolean survived = actions != null && actions.contains(overlap.other())
            && Accessor.tryGet(overlap.other(), "state", (TransactionState)null) == TransactionState.Accept;
        System.out.println("[ENGINE_TEST] CANCEL_OVERLAP transaction=" + overlap.id()
            + " firstPlayer=" + overlap.first() + " secondPlayer=" + overlap.second()
            + " firstToken=" + overlap.firstToken() + " secondToken=" + overlap.secondToken()
            + " otherPending=" + survived);
    }

    @Patch(className="zombie.core.ActionManager", methodName="remove", warmUp=true, strictMatch=true)
    public static class Cancellation {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) PlayerID owner, @Patch.Argument(1) byte id,
                @Patch.Local("engineOverlap") Overlap overlap) { overlap = before(owner, id); }
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Local("engineOverlap") Overlap overlap) { after(overlap); }
    }
}
