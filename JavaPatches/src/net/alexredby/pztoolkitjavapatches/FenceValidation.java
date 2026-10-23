package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;

/** Java entry points retain the instrumentation owner, monitor and patch annotations. */
public final class FenceValidation {
    public static final boolean SUPPORTED = FenceValidationLogic.SUPPORTED;

    private FenceValidation() { }

    public static synchronized boolean install(boolean supported) {
        return FenceValidationLogic.install(supported);
    }

    public static synchronized void registered(String name) {
        FenceValidationLogic.registered(name);
    }

    public static synchronized void tilesLoaded() {
        FenceValidationLogic.tilesLoaded();
    }

    public static synchronized void reset() {
        FenceValidationLogic.reset();
    }

    private static byte[] weave(byte[] bytes) {
        return FenceValidationLogic.weave(bytes);
    }

    @Patch(className="zombie.Lua.LuaEventManager", methodName="triggerEvent", strictMatch=true)
    public static class FenceTileDefinitionsDispatch {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) String event, @Patch.Argument(1) Object manager) {
            FenceValidationLogic.dispatched(event, manager);
        }
    }

    @Patch(className="zombie.Lua.Event", methodName="trigger", strictMatch=true)
    public static class FenceTileDefinitions {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.Lua.Event event,
                                @Patch.Argument(0) se.krka.kahlua.vm.KahluaTable env,
                                @Patch.Argument(1) se.krka.kahlua.integration.LuaCaller caller,
                                @Patch.Argument(2) Object[] args) {
            FenceValidationLogic.triggered(event, args);
        }
    }
}
