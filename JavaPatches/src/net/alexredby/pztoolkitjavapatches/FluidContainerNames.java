package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.scripting.ScriptParser;
import zombie.scripting.entity.components.fluids.FluidContainerScript;

@Patch(className="zombie.scripting.entity.components.fluids.FluidContainerScript", methodName="load", warmUp=true, strictMatch=true)
public final class FluidContainerNames {
    public static final boolean SUPPORTED = FluidContainerNamesLogic.SUPPORTED;

    private FluidContainerNames() { }

    public static void prepare() {
        if (SUPPORTED) FluidContainerScript.class.getName();
    }

    public static void normalize(ScriptParser.Block block, boolean supported) {
        FluidContainerNamesLogic.normalize(block, supported);
    }

    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) ScriptParser.Block block) {
        normalize(block, FluidContainerNames.SUPPORTED);
    }
}
