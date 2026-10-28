package net.alexredby.fitnessprobe;

import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.network.GameClient;
import zombie.characters.CharacterTimedActions.BaseAction;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.characters.IsoPlayer;
import zombie.core.ActionManager;
import zombie.core.Transaction.TransactionState;
import zombie.network.fields.character.PlayerID;

/** Optional, value-only observation of the common native validity decision. */
public final class Main {
    public record Sample(LuaTimedActionNew nativeAction, Object callback, KahluaTable values) {}

    public static Sample capture(LuaTimedActionNew action, boolean valid, boolean supported) {
        try {
            if (valid || action == null || LuaManager.env == null) return null;
            Object toolkit = LuaManager.env.rawget("PZSurvivorToolkit");
            Object lifecycle = toolkit instanceof KahluaTable table ? table.rawget("ActionQueueLifecycle") : null;
            Object callback = lifecycle instanceof KahluaTable table ? table.rawget("observeNativeValidation") : null;
            if (callback == null) return null;
            KahluaTable values = LuaManager.platform.newTable();
            IsoPlayer player = action.chr instanceof IsoPlayer value ? value : null;
            PlayerID owner = Accessor.tryGet(action, "playerId", (PlayerID)null);
            Byte id = Accessor.tryGet(action, "transactionId", (Byte)null);
            int matches = 0;
            String state = "missing";
            ConcurrentLinkedQueue<?> transactions = Accessor.tryGet(ActionManager.class, "actions", (ConcurrentLinkedQueue<?>)null);
            if (transactions != null && owner != null && id != null) {
                for (Object transaction : transactions) {
                    Byte candidate = Accessor.tryGet(transaction, "id", (Byte)null);
                    PlayerID candidateOwner = Accessor.tryGet(transaction, "playerId", (PlayerID)null);
                    if (candidate != null && candidate.byteValue() == id.byteValue() && candidateOwner != null
                            && candidateOwner.getID() == owner.getID()) {
                        matches++;
                        TransactionState observed = Accessor.tryGet(transaction, "state", (TransactionState)null);
                        state = matches == 1 ? String.valueOf(observed) : "multiple";
                    }
                }
            }
            values.rawset("supported", supported);
            values.rawset("originalValid", valid);
            values.rawset("nativeTransaction", id == null ? 0.0 : id.doubleValue());
            values.rawset("matchingTransactions", (double)matches);
            values.rawset("nativeState", state);
            values.rawset("done", owner != null && id != null && ActionManager.isDone(owner, id));
            values.rawset("rejected", owner != null && id != null && ActionManager.isRejected(owner, id));
            values.rawset("ownerMatches", player != null && owner != null && owner.getPlayer() == player && owner.getID() == player.getOnlineID());
            values.rawset("nativeCurrent", player != null && !player.getCharacterActions().isEmpty() && player.getCharacterActions().get(0) == action);
            values.rawset("baseStarted", ((BaseAction)action).started);
            values.rawset("remoteStarted", Accessor.tryGet(action, "started", false));
            values.rawset("customSync", Accessor.tryGet(action, "useCustomRemoteTimedActionSync", true));
            values.rawset("forceStopBefore", action.forceStop);
            values.rawset("forceCompleteBefore", action.forceComplete);
            values.rawset("waitForFinished", action.waitForFinished);
            return new Sample(action, callback, values);
        } catch (Throwable ignored) {
            return null;
        }
    }

    public static void observed(Sample sample, boolean result) {
        if (sample == null) return;
        try {
            sample.values().rawset("returned", result);
            sample.values().rawset("forceStopAfter", sample.nativeAction().forceStop);
            sample.values().rawset("forceCompleteAfter", sample.nativeAction().forceComplete);
            LuaManager.caller.pcall(LuaManager.thread, sample.callback(), sample.nativeAction().getTable(),
                    sample.nativeAction(), sample.values());
        } catch (Throwable ignored) {
            // Diagnostics cannot change native validity, stopping, completion or its errors.
        }
    }

    /** Reorder only the real test receipt; never forge its contents or replay effects. */
    public static boolean delay(String event, Object module, Object command, Object args) {
        try {
            if (!GameClient.client || !"OnServerCommand".equals(event) || LuaManager.env == null) return false;
            Object toolkit = LuaManager.env.rawget("PZSurvivorToolkit");
            Object lifecycle = toolkit instanceof KahluaTable table ? table.rawget("ActionQueueLifecycle") : null;
            Object callback = lifecycle instanceof KahluaTable table ? table.rawget("delayNativeReceipt") : null;
            if (callback == null) return false;
            Object[] result = LuaManager.caller.pcall(LuaManager.thread, callback, module, command, args);
            return result.length >= 2 && Boolean.TRUE.equals(result[0]) && Boolean.TRUE.equals(result[1]);
        } catch (Throwable ignored) { return false; }
    }

    @Patch(className="zombie.Lua.LuaEventManager", methodName="triggerEvent", warmUp=true, strictMatch=true)
    public static class ReceiptOrder {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) String event, @Patch.Argument(1) Object module,
                @Patch.Argument(2) Object command, @Patch.Argument(3) Object args) {
            return delay(event, module, command, args);
        }
    }

    @Patch(className="net.alexredby.pztoolkitjavapatches.ActionCompletion", methodName="restoreNativeCompletion", warmUp=true, strictMatch=true)
    public static class Decision {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(0) LuaTimedActionNew action, @Patch.Argument(1) boolean valid,
                @Patch.Argument(2) boolean supported, @Patch.Local("fitnessNativeDecision") Sample sample) {
            sample = capture(action, valid, supported);
        }
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.Local("fitnessNativeDecision") Sample sample, @Patch.Return boolean result) {
            observed(sample, result);
        }
    }
}
