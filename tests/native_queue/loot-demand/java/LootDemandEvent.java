package net.alexredby.lootdemand;

import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.Event;

/** Before listeners, including LuaEventManager's queued replay through Event.trigger. */
@Patch(className="zombie.Lua.Event",methodName="trigger",strictMatch=true)
public final class LootDemandEvent {
    @Patch.OnEnter(skipOn=true)
    public static boolean enter(@Patch.This Event event,@Patch.Argument(0) KahluaTable env,
            @Patch.Argument(1) LuaCaller caller,@Patch.Argument(2) Object[] args) {
        // Returning true skips listeners and leaves Event.trigger's default false result.
        return LootDemand.beforeEvent(event,args);
    }
}
