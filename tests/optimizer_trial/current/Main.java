package net.alexredby.optimizertrial;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.Lua.LuaManager;

/** Client-only diagnostic bridge. Flush the buffered Lua observations before Host teardown. */
public final class Main {
    private static final String ARM = System.getProperty("pz.optimizerTrial.arm");

    public static void main(String[] args) {
        if (ARM == null) return; // The menu Host child has no client trial arm.
        if ("Control".equals(ARM) || "Optimized".equals(ARM)) {
            System.out.println("[OptimizerTrial] current bridge ready mode=" + ARM);
        } else {
            System.err.println("[OptimizerTrial] current bridge failed: unsupported arm");
        }
    }

    public static void flush(String reason) {
        if (ARM == null) return;
        try {
            if (LuaManager.env != null && LuaManager.caller != null && LuaManager.thread != null
                    && LuaManager.env.rawget("PZOptimizerTrialTelemetryFlush") != null) {
                LuaManager.call("PZOptimizerTrialTelemetryFlush", reason);
            }
        } catch (RuntimeException | LinkageError error) {
            System.err.println("[OptimizerTrial] current bridge failed flushing " + reason + ": " + error);
        }
    }

    @Patch(className="zombie.gameStates.IngameState", methodName="exit", strictMatch=true)
    public static class WorldExit {
        @Patch.OnEnter public static void enter() { flush("WorldExit"); }
    }

    @Patch(className="zombie.gameStates.ServerDisconnectState", methodName="enter", strictMatch=true)
    public static class Disconnect {
        @Patch.OnEnter public static void enter() { flush("Disconnect"); }
    }
}
