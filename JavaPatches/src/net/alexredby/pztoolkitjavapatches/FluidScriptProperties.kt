package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import me.zed_0xff.zombie_buddy.Accessor
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.vm.KahluaTable
import zombie.Lua.LuaManager
import zombie.scripting.entity.components.fluids.FluidContainerScript

/** Read finalized script defaults without sampling the native randomized initial-amount getter. */
object FluidScriptProperties {
    @JvmField
    internal val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/scripting/entity/components/fluids/FluidContainerScript.class",
            "d3a4191471515e9ec18f29e153559369d13dd448d02747370546f1af75ac5595",
        )

    private fun field(name: String): Field? =
        if (SUPPORTED) Accessor.findField(FluidContainerScript::class.java, name) else null

    private val amountSet = field("initialAmountSet")
    private val amountMin = field("initialAmountMin")
    private val amountMax = field("initialAmountMax")
    private val capacity = field("capacity")

    @JvmStatic
    @LuaMethod(name = "toolkitScriptFluidInitialAmounts", global = true)
    fun initialAmounts(component: FluidContainerScript?): KahluaTable? = read(component, SUPPORTED)

    @JvmStatic
    @JvmName("read")
    internal fun read(component: FluidContainerScript?, supported: Boolean): KahluaTable? {
        if (!supported || component == null) return null
        val explicit = Accessor.tryGet<Boolean>(component, amountSet, null) ?: return null
        val size = Accessor.tryGet<Float>(component, capacity, null) ?: return null
        // OnScriptsLoaded converts the stored percentage bounds to absolute native float amounts.
        val min =
            if (explicit) Accessor.tryGet<Float>(component, amountMin, null) ?: return null
            else size
        val max =
            if (explicit) Accessor.tryGet<Float>(component, amountMax, null) ?: return null
            else size
        if (
            !size.isFinite() ||
                size < 0f ||
                !min.isFinite() ||
                min < 0f ||
                !max.isFinite() ||
                max < min
        )
            return null
        return LuaManager.platform.newTable().apply {
            rawset("min", min.toDouble())
            rawset("max", max.toDouble())
        }
    }
}
