package toolkit.craftwalk;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.characters.CharacterTimedActions.LuaTimedActionNew;
import zombie.core.Core;
import zombie.network.GameServer;

/** Disposable native input follows the existing cart fixture's keyboard route. */
public final class Main {
    private static IsoPlayer owner;
    private static int direction = -1;
    @LuaMethod(name="craftWalkInput", global=true)
    public static void input(IsoPlayer player, int value) {
        if (GameServer.server || player == null || player != IsoPlayer.getInstance() || value < -1 || value > 4)
            throw new IllegalArgumentException("Owned fixture player and direction required");
        owner = player;
        direction = value;
    }
    public static boolean active() {
        return !GameServer.server && owner != null && owner == IsoPlayer.getInstance() && direction >= 0;
    }
    public static boolean key(int key) {
        return direction > 0 && key == Core.getInstance().getKey(
            new String[]{"", "Forward", "Left", "Backward", "Right"}[direction]);
    }
    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDown", warmUp=true, strictMatch=true)
    public static class Keys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) { fixture = active(); return fixture; }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) { if (fixture) result = key(key); }
    }
    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDownRaw", warmUp=true, strictMatch=true)
    public static class RawKeys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) { fixture = active(); return fixture; }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) { if (fixture) result = key(key); }
    }
    @Patch(className="zombie.characters.CharacterTimedActions.LuaTimedActionNew", methodName="stop", warmUp=true, strictMatch=true)
    public static class Stop {
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.This LuaTimedActionNew action, @Patch.Thrown Throwable failure) {
            if (!active() || action == null || LuaManager.env == null) return;
            var table = action.getTable();
            if (table == null || !"ISHandcraftAction".equals(table.rawget("Type"))) return;
            var observer = LuaManager.env.rawget("craftWalkStopped");
            if (observer == null) return;
            Object[] result = LuaManager.caller.pcall(LuaManager.thread, observer, table, failure == null);
            if (result.length == 0 || !Boolean.TRUE.equals(result[0]))
                System.err.println("[QUEUE_TEST] FAIL craft walk native stop observer");
        }
    }
}
