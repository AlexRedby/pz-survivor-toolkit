package net.alexredby.pztoolkitjavapatches

import zombie.scripting.ScriptParser

internal object FluidContainerNamesLogic {
    @JvmField
    val SUPPORTED = BytecodeSupport.supports("zombie/scripting/entity/components/fluids/FluidContainerScript.class",
        "d3a4191471515e9ec18f29e153559369d13dd448d02747370546f1af75ac5595") &&
        BytecodeSupport.supports("zombie/scripting/ScriptParser\$Block.class",
            "14a54eee1c27b98431913e8daa28f2dcae58d8fedb9e3b0ed8b6426f717062d2") &&
        BytecodeSupport.supports("zombie/scripting/ScriptParser\$Value.class",
            "5cf9e1fa32ef946ac194fd8cf2bf7f95da9eda67076eccd3dfc321b31e14a637")

    @JvmStatic
    fun normalize(block: ScriptParser.Block?, supported: Boolean) {
        if (!supported || block == null) return
        val value = block.getValue("ContainerName") ?: return
        // Match Java String.trim(), preserving native validation of Unicode whitespace.
        val name = value.getValue().trim { it <= ' ' }
        // Preserve the native parser's result for two malformed shipped tokens.
        val canonical = when (name) {
            "Large Bucket" -> "LargeBucket"
            "Fuel Pump" -> "FuelPump"
            else -> return
        }
        block.setValue("ContainerName", canonical)
    }
}
