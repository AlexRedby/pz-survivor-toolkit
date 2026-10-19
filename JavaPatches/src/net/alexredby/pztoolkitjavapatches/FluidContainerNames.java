package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.scripting.ScriptParser;
import zombie.scripting.entity.components.fluids.FluidContainerScript;

@Patch(className="zombie.scripting.entity.components.fluids.FluidContainerScript", methodName="load", warmUp=true, strictMatch=true)
public final class FluidContainerNames {
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/scripting/entity/components/fluids/FluidContainerScript.class",
        "d3a4191471515e9ec18f29e153559369d13dd448d02747370546f1af75ac5595")
        && BytecodeSupport.supports("zombie/scripting/ScriptParser$Block.class",
            "14a54eee1c27b98431913e8daa28f2dcae58d8fedb9e3b0ed8b6426f717062d2")
        && BytecodeSupport.supports("zombie/scripting/ScriptParser$Value.class",
            "5cf9e1fa32ef946ac194fd8cf2bf7f95da9eda67076eccd3dfc321b31e14a637");

    private FluidContainerNames() { }

    public static void prepare() {
        if (SUPPORTED) FluidContainerScript.class.getName();
    }

    public static void normalize(ScriptParser.Block block, boolean supported) {
        if (!supported || block == null) return;
        var value = block.getValue("ContainerName");
        if (value == null) return;
        String name = value.getValue().trim();
        // Preserve the native parser's result for two malformed shipped tokens.
        if (name.equals("Large Bucket")) block.setValue("ContainerName", "LargeBucket");
        else if (name.equals("Fuel Pump")) block.setValue("ContainerName", "FuelPump");
    }

    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) ScriptParser.Block block) {
        normalize(block, FluidContainerNames.SUPPORTED);
    }
}
