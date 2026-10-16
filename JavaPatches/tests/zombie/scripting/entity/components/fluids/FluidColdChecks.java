package zombie.scripting.entity.components.fluids;

import java.io.ByteArrayOutputStream;
import java.lang.instrument.Instrumentation;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.Main;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;

public final class FluidColdChecks {
    static boolean loaded() {
        Instrumentation instrumentation = Accessor.tryGet(Loader.class, "g_instrumentation", (Instrumentation)null);
        FluidChecks.require(instrumentation != null, "native agent instrumentation unavailable");
        for (Class<?> type : instrumentation.getAllLoadedClasses())
            if (type.getName().equals("zombie.scripting.entity.components.fluids.FluidContainerScript")) return true;
        return false;
    }

    public static void main(String[] args) throws Exception {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"));
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        FluidChecks.require(!loaded(), "cold check started with fluid parser loaded");
        Main.main(new String[0]);
        FluidChecks.require(loaded(), "mod entry point did not preload fluid parser");
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", FluidColdChecks.class.getClassLoader());
        var logger = DebugLog.getInstance();
        var log = new ByteArrayOutputStream();
        DebugType.General.setLogSeverity(LogSeverity.Error);
        logger.setStdOut(log);
        logger.setStdErr(log);
        try {
            FluidChecks.require(FluidChecks.load(FluidChecks.nativeBlock("Large Bucket")).get(0).equals("LargeBucket"), "cold bucket name changed");
            FluidChecks.require(FluidChecks.load(FluidChecks.nativeBlock("Fuel Pump")).get(0).equals("FuelPump"), "cold pump name changed");
            FluidChecks.require(!log.toString().contains("Sanitizing container name"), "cold loader missed fluid advice: " + log);
        } finally {
            logger.setStdOut(System.out);
            logger.setStdErr(System.err);
        }
        System.out.println("FLUID_COLD_CHECKS_PASS (unloaded parser, mod entry point, actual loader advice, native asset blocks, zero fluid validation errors)");
    }
}
