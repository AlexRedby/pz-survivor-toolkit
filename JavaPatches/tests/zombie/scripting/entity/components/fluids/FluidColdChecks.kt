package zombie.scripting.entity.components.fluids

import java.io.ByteArrayOutputStream
import java.lang.instrument.Instrumentation
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.Main
import zombie.debug.DebugLog
import zombie.debug.DebugType
import zombie.debug.LogSeverity

object FluidColdChecks {
    @JvmStatic
    fun loaded(): Boolean {
        val instrumentation = Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
            ?: throw AssertionError("native agent instrumentation unavailable")
        return instrumentation.allLoadedClasses.any {
            it.name == "zombie.scripting.entity.components.fluids.FluidContainerScript"
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        FluidChecks.require(!loaded(), "cold check started with fluid parser loaded")
        Main.main(emptyArray())
        FluidChecks.require(loaded(), "mod entry point did not preload fluid parser")
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", FluidColdChecks::class.java.classLoader)
        val logger = DebugLog.getInstance()
        val log = ByteArrayOutputStream()
        DebugType.General.setLogSeverity(LogSeverity.Error)
        logger.setStdOut(log)
        logger.setStdErr(log)
        try {
            FluidChecks.require(FluidChecks.load(FluidChecks.nativeBlock("Large Bucket"))[0] == "LargeBucket",
                "cold bucket name changed")
            FluidChecks.require(FluidChecks.load(FluidChecks.nativeBlock("Fuel Pump"))[0] == "FuelPump",
                "cold pump name changed")
            FluidChecks.require("Sanitizing container name" !in log.toString(), "cold loader missed fluid advice: $log")
        } finally {
            logger.setStdOut(System.out)
            logger.setStdErr(System.err)
        }
        println("FLUID_COLD_CHECKS_PASS (unloaded parser, mod entry point, actual loader advice, native asset blocks, zero fluid validation errors)")
    }
}
