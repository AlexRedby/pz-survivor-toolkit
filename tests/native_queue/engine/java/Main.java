package net.alexredby.queueengineprobe;

import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgementLogic;
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgements;
import zombie.core.ActionManager;
import zombie.core.NetTimedAction;
import zombie.core.Transaction.TransactionState;
import zombie.characters.IsoPlayer;
import zombie.network.GameServer;
import zombie.network.fields.character.ConnectionPlayer;
import zombie.network.server.EventManager;

/** Read-only evidence at the actual cancellation boundary; never schedules or changes an action. */
public final class Main {
    private static boolean packetObserverInstalled;

    public static void main(String[] args) {
        if (!ActionAcknowledgements.SUPPORTED) throw unavailable("native acknowledgements unsupported");
        actions();
        tokens();
        observePacketRejections();
        System.out.println("[ENGINE_TEST] PROBE active=true");
    }

    private static synchronized void observePacketRejections() {
        if (packetObserverInstalled) return;
        // Native dispatch reports the packet name and description after rejecting it.
        // Keep validation and default native logging authoritative; only retain evidence.
        EventManager.instance().registerCallback(message -> {
            if (message != null && message.startsWith("The packet ") && message.contains(" is not consistent: "))
                System.out.println("[ENGINE_TEST] NATIVE_PACKET_REJECTION " + message);
        });
        packetObserverInstalled = true;
    }

    private static IllegalStateException unavailable(String detail) {
        System.out.println("[QUEUE_TEST] FAIL engine peer probe " + detail);
        return new IllegalStateException("Engine peer probe " + detail);
    }

    private static ConcurrentLinkedQueue<?> actions() {
        var actions = Accessor.tryGet(ActionManager.class, "actions", (ConcurrentLinkedQueue<?>)null);
        if (actions == null) throw unavailable("native action store unavailable");
        return actions;
    }

    private static Map<?, ?> tokens() {
        var tokens = Accessor.tryGet(ActionAcknowledgementLogic.class, "tokens", (Map<?, ?>)null);
        if (tokens == null) throw unavailable("native acknowledgement token store unavailable");
        return tokens;
    }

    public record Overlap(Object other, byte id, short first, short second, String firstToken, String secondToken) { }

    public static Overlap before(IsoPlayer owner, byte id) {
        if (!GameServer.server || owner == null || !"client1".equals(owner.getUsername())) return null;
        ConcurrentLinkedQueue<?> actions;
        Map<?, ?> tokens;
        try { actions = actions(); tokens = tokens(); }
        catch (IllegalStateException unavailable) { return null; }
        Object target = null, other = null;
        for (Object action : actions) {
            if (!(action instanceof NetTimedAction timed) || !"ISFixGenerator".equals(timed.type)) continue;
            Byte transaction = Accessor.tryGet(action, "id", (Byte)null);
            if (transaction == null || transaction != id) continue;
            ConnectionPlayer player = Accessor.tryGet(action, "player", (ConnectionPlayer)null);
            IsoPlayer actor = player == null ? null : player.getPlayer();
            if (actor != null && actor.getOnlineID() == owner.getOnlineID()) target = action;
            else if (actor != null) other = action;
        }
        if (target == null) return null;
        if (other == null || Accessor.tryGet(target, "state", (TransactionState)null) != TransactionState.Accept
                || Accessor.tryGet(other, "state", (TransactionState)null) != TransactionState.Accept
                || !(tokens.get(target) instanceof String firstToken) || !(tokens.get(other) instanceof String secondToken)) {
            System.out.println("[QUEUE_TEST] FAIL engine cancel lacked simultaneous pending same-ID peer");
            return null;
        }
        ConnectionPlayer second = Accessor.tryGet(other, "player", (ConnectionPlayer)null);
        return new Overlap(other, id, owner.getOnlineID(), second.getPlayer().getOnlineID(), firstToken, secondToken);
    }

    public static void after(Overlap overlap) {
        if (overlap == null) return;
        ConcurrentLinkedQueue<?> actions;
        try { actions = actions(); }
        catch (IllegalStateException unavailable) { return; }
        boolean survived = actions.contains(overlap.other())
            && Accessor.tryGet(overlap.other(), "state", (TransactionState)null) == TransactionState.Accept;
        System.out.println("[ENGINE_TEST] CANCEL_OVERLAP transaction=" + overlap.id()
            + " firstPlayer=" + overlap.first() + " secondPlayer=" + overlap.second()
            + " firstToken=" + overlap.firstToken() + " secondToken=" + overlap.secondToken()
            + " otherPending=" + survived);
    }

    @Patch(className="zombie.core.ActionManager", methodName="remove", warmUp=true, strictMatch=true)
    public static class Cancellation {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) IsoPlayer owner, @Patch.Argument(1) byte id,
                @Patch.Local("engineOverlap") Overlap overlap) { overlap = before(owner, id); }
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Local("engineOverlap") Overlap overlap) { after(overlap); }
    }
}
