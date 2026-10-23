package zombie.core

import java.io.ByteArrayOutputStream
import java.lang.instrument.Instrumentation
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Loader
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.Main
import zombie.debug.DebugLog
import zombie.debug.DebugType
import zombie.debug.LogSeverity

object PropertyColdChecks {
    @JvmStatic
    fun loaded(): Boolean {
        val instrumentation =
            Accessor.tryGet<Instrumentation>(Loader::class.java, "g_instrumentation", null)
                ?: throw AssertionError("native agent instrumentation unavailable")
        return instrumentation.allLoadedClasses.any {
            it.name == "zombie.core.properties.IsoPropertyType"
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        PropertyChecks.require(!loaded(), "cold check started with property enum loaded")
        Main.main(emptyArray())
        PropertyChecks.require(loaded(), "mod entry point did not preload property enum")
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            PropertyColdChecks::class.java.classLoader,
        )
        val logger = DebugLog.getInstance()
        val log = ByteArrayOutputStream()
        logger.setStdOut(log)
        logger.setStdErr(log)
        DebugType.WorldGen.setLogSeverity(LogSeverity.Error)
        try {
            PropertyChecks.generate()
            PropertyChecks.ordinaryLookups()
            PropertyChecks.require(
                "Property Name not found" !in log.toString() &&
                    "Exception thrown" !in log.toString(),
                "cold loader missed property advice: $log",
            )
        } finally {
            logger.setStdOut(System.out)
            logger.setStdErr(System.err)
        }
        println(
            "PROPERTY_COLD_CHECKS_PASS (unloaded enum, mod entry point, actual loader advice, native alias generation, zero property exceptions)",
        )
    }
}
