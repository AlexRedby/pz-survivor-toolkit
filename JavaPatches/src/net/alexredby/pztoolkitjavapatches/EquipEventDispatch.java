package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.Event;

/** Passive dispatch scope only: native callback selection and execution stay unchanged. */
public final class EquipEventDispatch {
    private EquipEventDispatch() { }

    @Patch(className="zombie.Lua.Event", methodName="trigger", warmUp=true, strictMatch=true)
    public static class Trigger {
        @Patch.OnEnter
        public static void enter(@Patch.This Event event, @Patch.Argument(0) KahluaTable environment,
                                 @Patch.Local("toolkitEquipDispatchScope") EquipEventDispatchLogic.Scope scope) {
            scope = EquipEventDispatchLogic.enter(event, environment);
        }
        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.Local("toolkitEquipDispatchScope") EquipEventDispatchLogic.Scope scope) {
            EquipEventDispatchLogic.exit(scope);
        }
    }
}
