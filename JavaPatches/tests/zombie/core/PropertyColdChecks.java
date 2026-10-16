package zombie.core;

import java.io.ByteArrayOutputStream;
import java.lang.instrument.Instrumentation;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.PatchEngine;
import net.alexredby.pztoolkitjavapatches.Main;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;

public final class PropertyColdChecks {
    static boolean loaded() {
        Instrumentation instrumentation = Accessor.tryGet(Loader.class, "g_instrumentation", (Instrumentation)null);
        PropertyChecks.require(instrumentation != null, "native agent instrumentation unavailable");
        for (Class<?> type : instrumentation.getAllLoadedClasses())
            if (type.getName().equals("zombie.core.properties.IsoPropertyType")) return true;
        return false;
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        PropertyChecks.require(!loaded(), "cold check started with property enum loaded");
        Main.main(new String[0]);
        PropertyChecks.require(loaded(), "mod entry point did not preload property enum");
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", PropertyColdChecks.class.getClassLoader());
        var logger = DebugLog.getInstance();
        var log = new ByteArrayOutputStream();
        logger.setStdOut(log);
        logger.setStdErr(log);
        DebugType.WorldGen.setLogSeverity(LogSeverity.Error);
        try {
            PropertyChecks.generate();
            PropertyChecks.ordinaryLookups();
            PropertyChecks.require(!log.toString().contains("Property Name not found")
                && !log.toString().contains("Exception thrown"), "cold loader missed property advice: " + log);
        } finally {
            logger.setStdOut(System.out);
            logger.setStdErr(System.err);
        }
        System.out.println("PROPERTY_COLD_CHECKS_PASS (unloaded enum, mod entry point, actual loader advice, native alias generation, zero property exceptions)");
    }
}
