package zombie.vehicles

import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.lang.reflect.Field
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.VehicleSyncTrace
import net.alexredby.pztoolkitjavapatches.VehicleSyncTraceLogic
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.KahluaThread
import zombie.Lua.LuaManager

object VehicleTraceChecks {
    private fun verify(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    private fun field(name: String): Field =
        VehicleSyncTraceLogic::class.java.getDeclaredField(name).apply { isAccessible = true }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        // Exercise the packaged global discovery before any direct trace reference.
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            VehicleTraceChecks::class.java.classLoader,
        )
        val bridge =
            Exposer.getClassesWithGlobalLuaMethod().firstOrNull {
                it.name == "net.alexredby.pztoolkitjavapatches.VehicleSyncTrace"
            } ?: throw AssertionError("ZombieBuddy did not discover the trace bridge")
        verify(
            Path.of(bridge.protectionDomain.codeSource.location.toURI()) ==
                Path.of(System.getProperty("pz.test.patch.jar")),
            "trace bridge did not come from the built JAR",
        )
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newTable()
        LuaManager.exposer =
            LuaManager.Exposer(KahluaConverterManager(), LuaManager.platform, LuaManager.env)
        Exposer.afterExposeAll()
        val status = LuaManager.env.rawget("toolkitVehicleTraceStatus")
        val set = LuaManager.env.rawget("toolkitVehicleTraceSet")
        verify(status != null && set != null, "ZombieBuddy did not register both trace globals")
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.thread = thread
        fun state(): Any? = thread.call(status, emptyArray<Any?>())
        fun enable(value: Boolean): Any? = thread.call(set, arrayOf<Any?>(value))

        val car = NativeChecks.vehicle()
        NativeChecks.set(car, "passengers", emptyArray<BaseVehicle.Passenger>())
        car.netPlayerId = 9
        verify(VehicleSyncTrace.SUPPORTED, "wrong native engine")
        val startup = java.lang.Boolean.getBoolean("pz.vehicle.trace")
        verify(VehicleSyncTrace.ENABLED == startup, "startup opt-in compatibility changed")
        verify(state() == if (startup) "active" else "off", "wrong startup state")
        verify(!VehicleSyncTrace.due("state", null), "missing car traced")
        if (!startup) verify(!VehicleSyncTrace.due("state", car), "trace enabled by default")
        verify(enable(false) == "off" && state() == "off", "Lua disable failed")
        verify(!VehicleSyncTrace.due("state", car), "disabled session admitted a record")

        verify(enable(true) == "active" && state() == "active", "Lua enable failed")
        val started = field("started").getLong(null)
        verify(
            VehicleSyncTrace.due("state", car) && !VehicleSyncTrace.due("state", car),
            "per-vehicle sample throttle",
        )
        for (i in 0 until 255) {
            verify(VehicleSyncTrace.due("event$i", car), "early key cap")
        }
        verify(!VehicleSyncTrace.due("overflow", car), "unbounded keys")
        verify(enable(true) == "active", "idempotent enable changed state")
        verify(field("started").getLong(null) == started, "repeated enable renewed time budget")
        verify(field("records").getInt(null) == 256, "repeated enable renewed record budget")
        verify(!VehicleSyncTrace.due("overflow", car), "repeated enable cleared bounded keys")
        @Suppress("UNCHECKED_CAST")
        val last = field("last").get(null) as MutableMap<String, Long>
        last["state:${car.getId()}"] = System.nanoTime() - 1_000_000_001L
        verify(VehicleSyncTrace.due("state", car), "existing key stopped sampling at key cap")

        // Move the real monotonic boundary rather than sleeping for ten minutes.
        field("started").setLong(null, System.nanoTime() - 600_000_000_001L)
        verify(state() == "expired", "elapsed session did not expire")
        verify(enable(true) == "expired", "repeated enable restarted expired session")
        verify(!VehicleSyncTrace.due("state", car), "elapsed session admitted a record")
        verify(enable(false) == "off" && enable(true) == "active", "off/on did not restart")
        verify(field("records").getInt(null) == 0 && last.isEmpty(), "restart kept old budget")
        verify(VehicleSyncTrace.due("state", car), "restart kept old throttle")

        field("records").setInt(null, 4999)
        verify(VehicleSyncTrace.due("lastRecord", car), "final budgeted record rejected")
        verify(state() == "expired", "record budget did not expire session")
        verify(!VehicleSyncTrace.due("tooMany", car), "record cap exceeded")
        verify(enable(true) == "expired", "enable renewed exhausted record budget")
        verify(VehicleSyncTraceLogic.status(false) == "unsupported", "unsupported gate changed")
        verify(enable(false) == "off" && enable(true) == "active", "exhausted session cannot restart")
        car.netPlayerId = -1
        verify(!VehicleSyncTrace.due("idle", car), "unoccupied unowned vehicle traced")
        verify(field("records").getInt(null) == 0, "ignored vehicle consumed record budget")
        car.netPlayerId = 9
        verify(enable(false) == "off", "final disable failed")
        verify(
            car.netPlayerId.toInt() == 9 && car.getX() == 0f && car.getY() == 0f,
            "diagnostics changed ownership or coordinates",
        )
        val output = ByteArrayOutputStream()
        val previousOutput = System.out
        try {
            System.setOut(PrintStream(output, true, UTF_8))
            enable(true)
            enable(true)
            state()
            enable(false)
            enable(false)
        } finally {
            System.setOut(previousOutput)
        }
        val markers = output.toString(UTF_8).lineSequence().filter { it.contains("[VEHICLE_SYNC]") }.toList()
        verify(
            markers.size == 2 && markers[0].endsWith("event=session state=active") &&
                markers[1].endsWith("event=session state=off"),
            "session markers missing or repeated by polling",
        )
        verify(field("records").getInt(null) == 0, "session markers consumed sample budget")
        println(
            "VEHICLE_TRACE_CHECKS_PASS startup=$startup (runtime Kahlua controls, bounded sessions, sampling, no vehicle writes)",
        )
        kotlin.system.exitProcess(0)
    }
}
