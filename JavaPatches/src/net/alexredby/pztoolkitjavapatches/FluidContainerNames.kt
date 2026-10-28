package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import zombie.scripting.ScriptParser
import zombie.scripting.entity.components.fluids.FluidContainerScript

@Patch(
    className = "zombie.scripting.entity.components.fluids.FluidContainerScript",
    methodName = "load",
    warmUp = true,
    strictMatch = true,
)
object FluidContainerNames {
    @JvmField val SUPPORTED = FluidContainerNamesLogic.SUPPORTED

    @JvmStatic
    fun prepare() {
        if (SUPPORTED) FluidContainerScript::class.java.name
    }

    @JvmStatic
    fun normalize(block: ScriptParser.Block?, supported: Boolean) {
        FluidContainerNamesLogic.normalize(block, supported)
    }

    @JvmStatic
    @Patch.OnEnter
    fun enter(@Patch.Argument(0) block: ScriptParser.Block?) {
        normalize(block, SUPPORTED)
    }
}
