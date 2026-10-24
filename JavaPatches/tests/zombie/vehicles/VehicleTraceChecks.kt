package zombie.vehicles

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.PrintStream
import java.lang.reflect.Field
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.Files
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.VehicleSyncTrace
import net.alexredby.pztoolkitjavapatches.VehicleSyncTraceLogic
import net.alexredby.pztoolkitjavapatches.VehicleTraceFile
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.ZomboidFileSystem
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.network.GameClient
import zombie.network.GameServer

object VehicleTraceChecks {
    private fun verify(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun rotation(root: Path) {
        val file = root.resolve("small/vehicle-sync.log")
        VehicleTraceFile(file, 128).use { writer ->
            for (i in 0 until 100) writer.write("$i: поездка")
        }
        VehicleTraceFile(file, 128).use { writer ->
            for (i in 100 until 108) writer.write("$i: поездка")
        }
        val retained =
            (4 downTo 0).flatMap { index ->
                val path = if (index == 0) file else file.resolveSibling("vehicle-sync.log.$index")
                verify(Files.size(path) <= 128, "UTF-8 rotation byte limit exceeded")
                Files.readAllLines(path, UTF_8)
            }
        val numbers = retained.map { it.substringBefore(':').toInt() }
        verify(
            numbers.last() == 107 && numbers == (numbers.first()..107).toList(),
            "rotation/reopen lost, duplicated or reordered retained records",
        )
        verify(retained.all { it.endsWith("поездка") }, "rotation damaged UTF-8")
        verify(!Files.exists(file.resolveSibling("vehicle-sync.log.5")), "extra backup created")

        val full = root.resolve("full/vehicle-sync.log")
        val megabyte = "x".repeat(1024 * 1024 - 1)
        VehicleTraceFile(full).use { writer -> repeat(26) { writer.write(megabyte) } }
        val sizes =
            (0..4).map { index ->
                Files.size(if (index == 0) full else full.resolveSibling("vehicle-sync.log.$index"))
            }
        verify(
            sizes.all { it <= 5L * 1024 * 1024 } && sizes.sum() <= 25L * 1024 * 1024,
            "default 5 MiB / four-backup storage bound exceeded",
        )
        val before = Files.size(full)
        VehicleTraceFile(full).use { it.write("restart") }
        verify(Files.size(full) == before + 8, "process restart replaced rather than appended")
        VehicleTraceFile(full).use { writer ->
            writer.close()
            try {
                writer.write("closed")
                throw AssertionError("closed writer accepted record")
            } catch (_: IOException) {}
        }
    }

    private fun hostAuthorization(thread: KahluaThread, function: Any?) {
        fun allowed(player: IsoPlayer?): Any? = thread.call(function, arrayOf<Any?>(player))
        val unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        val player = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        val stranger = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        val connection = unsafe.allocateInstance(UdpConnection::class.java) as UdpConnection
        val engine = unsafe.allocateInstance(UdpEngine::class.java) as UdpEngine
        field(UdpEngine::class.java, "connectionMap").set(engine, hashMapOf(123L to connection))
        val previousEngine = GameServer.udpEngine
        try {
            GameServer.server = false
            connection.isCoopHost = true
            verify(
                allowed(player) == false && allowed(null) == false,
                "client authorized server control",
            )
            GameServer.server = true
            GameServer.udpEngine = engine
            verify(allowed(player) == false, "unmapped player authorized server control")
            GameServer.PlayerToAddressMap[player] = 123L
            verify(allowed(player) == true, "native coop-host connection denied")
            connection.isCoopHost = false
            verify(allowed(player) == false, "nonhost player authorized server control")
            connection.isCoopHost = true
            verify(
                allowed(stranger) == false && allowed(null) == false,
                "another player borrowed the host connection",
            )
        } finally {
            GameServer.PlayerToAddressMap.remove(player)
            GameServer.udpEngine = previousEngine
            GameServer.server = false
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val cache = Path.of(System.getProperty("pz.test.cache")).resolve("vehicle-trace")
        Files.createDirectories(cache)
        ZomboidFileSystem.instance.setCacheDir(cache.toString())
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
            "trace bridge did not come from built JAR",
        )
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newTable()
        LuaManager.exposer =
            LuaManager.Exposer(KahluaConverterManager(), LuaManager.platform, LuaManager.env)
        Exposer.afterExposeAll()
        val status = LuaManager.env.rawget("toolkitVehicleTraceStatus")
        val set = LuaManager.env.rawget("toolkitVehicleTraceSet")
        val path = LuaManager.env.rawget("toolkitVehicleTracePath")
        val authorization = LuaManager.env.rawget("toolkitVehicleTraceCanControl")
        verify(listOf(status, set, path, authorization).all { it != null }, "missing trace globals")
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.thread = thread
        fun state(): Any? = thread.call(status, emptyArray<Any?>())
        fun enable(value: Boolean): Any? = thread.call(set, arrayOf<Any?>(value))
        fun outputPath(): Path = Path.of(thread.call(path, emptyArray<Any?>()) as String)

        val car = NativeChecks.vehicle()
        NativeChecks.set(car, "passengers", emptyArray<BaseVehicle.Passenger>())
        car.netPlayerId = 9
        verify(VehicleSyncTrace.SUPPORTED, "wrong native engine")
        val startup = java.lang.Boolean.getBoolean("pz.vehicle.trace")
        verify(VehicleSyncTrace.ENABLED == startup, "startup opt-in compatibility changed")
        verify(state() == if (startup) "active" else "off", "wrong startup state")
        verify(
            outputPath() == cache.resolve("Logs/PZToolkitVehicleTrace/sp/vehicle-sync.log"),
            "wrong SP path",
        )
        verify(!VehicleSyncTrace.due("state", null), "missing car traced")
        verify(enable(false) == "off" && !VehicleSyncTrace.due("state", car), "disable failed")
        verify(enable(true) == "active", "Lua enable failed")
        val now = System.nanoTime()
        verify(
            VehicleSyncTraceLogic.due("state", car, now) &&
                !VehicleSyncTraceLogic.due("state", car, now + 999_999_999L),
            "per-key throttle",
        )
        for (i in 0 until 255) verify(
            VehicleSyncTraceLogic.due("event$i", car, now),
            "early sampling cap",
        )
        verify(!VehicleSyncTraceLogic.due("overflow", car, now), "unbounded recent keys")
        verify(
            enable(true) == "active" && !VehicleSyncTraceLogic.due("state", car, now),
            "enable reset throttle",
        )
        verify(
            VehicleSyncTraceLogic.due("new-car", car, now + 1_000_000_000L),
            "old sampling slot not reused",
        )
        verify(
            !VehicleSyncTraceLogic.due("new-car", car, now + 1_000_000_001L),
            "reused key bypassed throttle",
        )
        for (i in 1..6001) {
            verify(
                VehicleSyncTraceLogic.due("long$i", car, now + i * 1_000_000_000L),
                "long recording stopped",
            )
            VehicleSyncTrace.log("long$i", car, "sample=$i")
        }
        @Suppress("UNCHECKED_CAST")
        val last = field(VehicleSyncTraceLogic::class.java, "last").get(null) as Map<String, Long>
        verify(
            last.size == 256 && state() == "active",
            "sampling memory unbounded or time/count cutoff remains",
        )
        val trace = outputPath()
        verify(Files.readString(trace).contains("event=long6001"), "sample not flushed to file")
        val console = ByteArrayOutputStream()
        val previousOutput = System.out
        try {
            System.setOut(PrintStream(console, true, UTF_8))
            repeat(20) {
                enable(true)
                state()
                VehicleSyncTrace.log("file-only", car, "")
            }
        } finally {
            System.setOut(previousOutput)
        }
        verify(console.size() == 0, "samples or polling duplicated to console")
        verify(enable(false) == "off", "stop failed")
        val stoppedSize = Files.size(trace)
        VehicleSyncTrace.log("stopped", car, "")
        verify(Files.size(trace) == stoppedSize, "disabled trace kept writing")
        enable(true)
        VehicleSyncTrace.log("restart", car, "")
        enable(false)
        verify(
            Files.readString(trace).contains("event=long1 ") &&
                Files.readString(trace).contains("event=restart "),
            "restart lost earlier records",
        )

        enable(true)
        GameClient.client = true
        val clientPath = outputPath()
        verify(clientPath.parent.fileName.toString() == "client", "client path not isolated")
        verify(state() == "active", "joining MP stopped recording")
        VehicleSyncTrace.log("client", car, "")
        verify(
            Files.readString(clientPath).contains("event=client "),
            "active writer kept SP path after join",
        )
        GameClient.client = false
        GameServer.server = true
        val serverPath = outputPath()
        verify(serverPath.parent.fileName.toString() == "server", "server path not isolated")
        verify(state() == "active", "side switch stopped recording")
        VehicleSyncTrace.log("server", car, "")
        verify(
            Files.readString(serverPath).contains("event=server "),
            "active writer kept client path",
        )
        GameServer.server = false
        val movedCache = cache.resolve("cache-switch")
        Files.createDirectories(movedCache)
        ZomboidFileSystem.instance.setCacheDir(movedCache.toString())
        val movedPath = outputPath()
        verify(state() == "active", "cache change stopped recording")
        VehicleSyncTrace.log("new-cache", car, "")
        verify(
            movedPath.startsWith(movedCache) &&
                Files.readString(movedPath).contains("event=new-cache "),
            "active writer ignored cache change after path query",
        )
        enable(false)
        ZomboidFileSystem.instance.setCacheDir(cache.toString())
        hostAuthorization(thread, authorization)

        val blocked = cache.resolve("blocked")
        Files.createDirectories(blocked)
        Files.writeString(blocked.resolve("Logs"), "not a directory")
        ZomboidFileSystem.instance.setCacheDir(blocked.toString())
        verify(enable(true) == "error" && state() == "error", "IO failure did not reach Lua status")
        Files.delete(blocked.resolve("Logs"))
        verify(state() == "error", "polling retried failed IO implicitly")
        verify(enable(true) == "active", "explicit retry did not recover writer")
        // Closed-stream failure models a write/flush failure after successful start.
        val activeWriter =
            field(VehicleSyncTraceLogic::class.java, "writer").get(null) as VehicleTraceFile
        activeWriter.close()
        VehicleSyncTrace.log("io-error", car, "")
        verify(
            state() == "error" && enable(false) == "off",
            "write failure or error reset not reported",
        )
        verify(enable(true) == "active", "off/on after IO failure did not recover")
        car.netPlayerId = -1
        verify(!VehicleSyncTrace.due("idle", car), "unoccupied unowned vehicle traced")
        car.netPlayerId = 9
        enable(false)
        verify(VehicleSyncTraceLogic.status(false) == "unsupported", "unsupported gate changed")
        verify(
            car.netPlayerId.toInt() == 9 && car.getX() == 0f && car.getY() == 0f,
            "diagnostics changed ownership or coordinates",
        )
        rotation(cache.resolve("rotation"))
        println(
            "VEHICLE_TRACE_CHECKS_PASS startup=$startup (Kahlua controls/path/Host auth, rotation, unlimited duration/count, bounded sampling, IO recovery, no vehicle writes)",
        )
        kotlin.system.exitProcess(0)
    }
}
