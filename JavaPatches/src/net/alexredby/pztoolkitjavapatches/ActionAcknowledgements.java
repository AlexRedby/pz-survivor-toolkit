package net.alexredby.pztoolkitjavapatches;

import java.util.ArrayList;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.characters.IsoPlayer;

/** Outcomes of existing native actions; the native managers still execute all effects. */
public final class ActionAcknowledgements {
    public static final boolean SUPPORTED = ActionAcknowledgementLogic.supported;

    public static synchronized void started(Object action) { ActionAcknowledgementLogic.started(action); }
    public static synchronized String token(Object action) { return ActionAcknowledgementLogic.token(action); }
    public static synchronized ArrayList<Object> pending() { return ActionAcknowledgementLogic.pending(); }
    public static synchronized void settled(ArrayList<Object> before, boolean removed) {
        ActionAcknowledgementLogic.settled(before, removed);
    }
    public static synchronized ArrayList<Object> removing(IsoPlayer player, byte id) {
        return ActionAcknowledgementLogic.removing(player, id);
    }
    public static void bind(LuaTimedActionNew nativeAction) { ActionAcknowledgementLogic.bind(nativeAction); }

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
        public static void enter(@Patch.Argument(0) IsoPlayer player, @Patch.Argument(1) byte id,
                @Patch.Local("toolkitRemovedActions") ArrayList<Object> before) {
            before = removing(player, id);
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
