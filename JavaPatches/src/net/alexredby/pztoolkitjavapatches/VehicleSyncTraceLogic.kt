package net.alexredby.pztoolkitjavapatches

import java.nio.file.Path
import java.util.LinkedHashMap
import zombie.ZomboidFileSystem
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.packets.vehicle.VehiclePhysicsPacket
import zombie.vehicles.BaseVehicle

/** Opt-in diagnostics; never changes vehicle state or packet delivery. */
internal object VehicleSyncTraceLogic {
    @JvmField val enabled = java.lang.Boolean.getBoolean("pz.vehicle.trace")
    @JvmField
    val supported =
        Main.VEHICLE_OWNERSHIP_SUPPORTED &&
            BytecodeSupport.supports(
                "zombie/network/packets/vehicle/VehiclePhysicsPacket.class",
                "c3103be5b9bacad57747f49b94bff441ff6b530315885ed30c93dc05c13da2c4",
            )
    private val last = LinkedHashMap<String, Long>()
    private var requested = enabled
    private var writer: VehicleTraceFile? = null
    private var failed = false
    private var outputPath: Path? = null
    private var pathCacheDir: String? = null
    private var pathSide: String? = null

    private fun tracePath(): Path {
        val cacheDir = ZomboidFileSystem.instance.getCacheDir()
        val side = if (GameServer.server) "server" else if (GameClient.client) "client" else "sp"
        val cached = outputPath
        if (cached != null && cacheDir == pathCacheDir && side == pathSide) return cached
        val target =
            Path.of(cacheDir)
                .resolve("Logs/PZToolkitVehicleTrace")
                .resolve(side)
                .resolve("vehicle-sync.log")
                .toAbsolutePath()
                .normalize()
        outputPath = target
        pathCacheDir = cacheDir
        pathSide = side
        return target
    }

    fun path(): String =
        try {
            tracePath().toString()
        } catch (_: Exception) {
            ""
        }

    private fun fail(error: Exception) {
        try {
            writer?.close()
        } catch (_: Exception) {}
        writer = null
        if (!failed) System.err.println("[VEHICLE_SYNC] error=" + error)
        failed = true
    }

    private fun ensureWriter() {
        if (!requested || !supported || failed) return
        try {
            val target = tracePath()
            if (writer?.path == target) return
            writer?.close()
            writer = null
            writer = VehicleTraceFile(target)
            writer!!.write(
                "[VEHICLE_SYNC] t=" + System.currentTimeMillis() + " event=session state=active",
            )
            println("[VEHICLE_SYNC] state=active file=$target")
        } catch (error: Exception) {
            fail(error)
        }
    }

    /** All mutable session and file access uses VehicleSyncTrace's class monitor. */
    fun set(enabled: Boolean): String {
        if (!enabled) {
            val wasRequested = requested
            requested = false
            try {
                writer?.write(
                    "[VEHICLE_SYNC] t=" + System.currentTimeMillis() + " event=session state=off",
                )
                writer?.close()
            } catch (error: Exception) {
                fail(error)
            }
            writer = null
            failed = false
            last.clear()
            if (wasRequested && supported) println("[VEHICLE_SYNC] state=off file=" + path())
        } else if (!requested || failed) {
            requested = true
            failed = false
            last.clear()
        }
        return status()
    }

    fun status(supported: Boolean = this.supported): String {
        if (!supported) return "unsupported"
        if (!requested) return "off"
        ensureWriter()
        return if (failed) "error" else "active"
    }

    @JvmStatic
    fun due(event: String?, car: BaseVehicle?, now: Long = System.nanoTime()): Boolean {
        if (car == null || status() != "active") return false
        if (car.getDriver() == null && car.netPlayerId.toInt() == -1) return false
        val key = "$event:${car.getId()}"
        val previous = last[key]
        if (previous != null && now - previous < 1_000_000_000L) return false
        if (previous == null && last.size >= 256) {
            val oldest = last.entries.iterator()
            if (now - oldest.next().value < 1_000_000_000L) return false
            oldest.remove()
        }
        last.remove(key)
        last[key] = now
        return true
    }

    @JvmStatic
    fun log(event: String?, car: BaseVehicle?, detail: String?) {
        if (status() != "active") return
        val vehicle = car ?: return
        val driver = vehicle.getDriver()
        val local = if (GameClient.client) IsoPlayer.getInstance() else null
        try {
            writer!!.write(
                "[VEHICLE_SYNC] t=" +
                    System.currentTimeMillis() +
                    " side=" +
                    (if (GameServer.server) "server"
                    else if (GameClient.client) "client" else "sp") +
                    " event=" +
                    event +
                    " vehicle=" +
                    vehicle.getId() +
                    " local=" +
                    (if (local == null) -1 else local.getOnlineID().toInt()) +
                    " driver=" +
                    (if (driver == null) -1 else driver.getOnlineID().toInt()) +
                    " owner=" +
                    vehicle.netPlayerId +
                    " auth=" +
                    vehicle.netPlayerAuthorization +
                    " pos=" +
                    vehicle.getX() +
                    "," +
                    vehicle.getY() +
                    "," +
                    vehicle.getZ() +
                    " towing=" +
                    (if (vehicle.getVehicleTowing() == null) -1
                    else vehicle.getVehicleTowing().getId().toInt()) +
                    " towedBy=" +
                    (if (vehicle.getVehicleTowedBy() == null) -1
                    else vehicle.getVehicleTowedBy().getId().toInt()) +
                    " " +
                    detail,
            )
        } catch (error: Exception) {
            fail(error)
        }
    }

    @JvmStatic
    fun state(car: BaseVehicle?) {
        if (VehicleSyncTrace.due("state", car)) VehicleSyncTrace.log("state", car, "")
    }

    @JvmStatic
    fun owner(car: BaseVehicle?, authorization: BaseVehicle.Authorization?, player: Int) {
        if (VehicleSyncTrace.due("owner", car))
            VehicleSyncTrace.log("owner", car, "nextOwner=$player nextAuth=$authorization")
    }

    @JvmStatic
    fun seat(car: BaseVehicle?, player: IsoPlayer?, entering: Boolean) {
        if (VehicleSyncTrace.due("seat", car))
            VehicleSyncTrace.log(
                "seat",
                car,
                "actor=" +
                    (player ?: throw NullPointerException()).getOnlineID() +
                    " entering=" +
                    entering,
            )
    }

    @JvmStatic
    fun send(packet: VehiclePhysicsPacket?, car: BaseVehicle?) {
        if (VehicleSyncTrace.due("send", car)) {
            val sample = packet ?: throw NullPointerException()
            VehicleSyncTrace.log("send", car, "sample=" + sample.getX() + "," + sample.getY())
        }
    }

    @JvmStatic
    fun receiveServer(packet: VehiclePhysicsPacket?, sender: UdpConnection?) {
        val sample = packet ?: throw NullPointerException()
        val car = sample.getVehicle()
        if (VehicleSyncTrace.due("receiveServer", car))
            VehicleSyncTrace.log(
                "receiveServer",
                car,
                "allowed=" +
                    car.hasAuthorization(sender) +
                    " sample=" +
                    sample.getX() +
                    "," +
                    sample.getY(),
            )
    }

    @JvmStatic
    fun receiveClient(packet: VehiclePhysicsPacket?, sender: UdpConnection?) {
        val sample = packet ?: throw NullPointerException()
        val car = sample.getVehicle()
        if (VehicleSyncTrace.due("receiveClient", car))
            VehicleSyncTrace.log(
                "receiveClient",
                car,
                "ignoredAsOwner=" +
                    car.hasAuthorization(sender) +
                    " sample=" +
                    sample.getX() +
                    "," +
                    sample.getY(),
            )
    }
}
