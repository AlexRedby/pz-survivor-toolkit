package net.alexredby.nativeviewport;

import se.krka.kahlua.integration.annotations.LuaMethod;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;

/** Disposable bridge to the common owned-window bootstrap; no rendering mutation. */
public final class Main {
    @LuaMethod(name = "toolkitTestViewport", global = true)
    public static KahluaTable observe(int width, int height) throws Exception {
        int[] values = (int[]) Class.forName("ToolkitWindowBootstrap")
            .getMethod("observeViewport", int.class, int.class).invoke(null, width, height);
        KahluaTable result = LuaManager.platform.newTable();
        for (int i = 0; i < values.length; i++) result.rawset((double) (i + 1), (double) values[i]);
        return result;
    }
}
