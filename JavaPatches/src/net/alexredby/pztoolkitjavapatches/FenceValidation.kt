package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import se.krka.kahlua.integration.LuaCaller
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.Event

/** Preserve the instrumentation owner and class monitor at the patch boundary. */
object FenceValidation {
    @JvmField val SUPPORTED = FenceValidationLogic.SUPPORTED

    @JvmStatic
    @Synchronized
    fun install(supported: Boolean): Boolean = FenceValidationLogic.install(supported)

    @JvmStatic
    @Synchronized
    fun registered(name: String?) {
        FenceValidationLogic.registered(name)
    }

    @JvmStatic
    @Synchronized
    fun tilesLoaded() {
        FenceValidationLogic.tilesLoaded()
    }

    @JvmStatic
    @Synchronized
    fun reset() {
        FenceValidationLogic.reset()
    }

    @JvmStatic private fun weave(bytes: ByteArray?): ByteArray? = FenceValidationLogic.weave(bytes)

    @Patch(
        className = "zombie.Lua.LuaEventManager",
        methodName = "triggerEvent",
        strictMatch = true,
    )
    object FenceTileDefinitionsDispatch {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.Argument(0) event: String?, @Patch.Argument(1) manager: Any?) {
            FenceValidationLogic.dispatched(event, manager)
        }
    }

    @Patch(className = "zombie.Lua.Event", methodName = "trigger", strictMatch = true)
    object FenceTileDefinitions {
        @JvmStatic
        @Patch.OnExit
        fun exit(
            @Patch.This event: Event?,
            @Patch.Argument(0) env: KahluaTable?,
            @Patch.Argument(1) caller: LuaCaller?,
            @Patch.Argument(2) args: Array<Any?>?,
        ) {
            FenceValidationLogic.triggered(event, args)
        }
    }
}
