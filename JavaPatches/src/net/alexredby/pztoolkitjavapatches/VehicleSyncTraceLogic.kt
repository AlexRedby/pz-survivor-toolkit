package net.alexredby.pztoolkitjavapatches

import java.util.HashMap
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.packets.vehicle.VehiclePhysicsPacket
import zombie.vehicles.BaseVehicle

/** Opt-in diagnostics; never changes vehicle state or packet delivery. */
internal object VehicleSyncTraceLogic {
    @JvmField val enabled = java.lang.Boolean.getBoolean("pz.vehicle.trace")
    @JvmField val supported = Main.VEHICLE_OWNERSHIP_SUPPORTED
        && BytecodeSupport.supports("zombie/network/packets/vehicle/VehiclePhysicsPacket.class",
            "c3103be5b9bacad57747f49b94bff441ff6b530315885ed30c93dc05c13da2c4")
    private val last = HashMap<String, Long>()
    private var started = 0L
    private var records = 0

    /** Called only under VehicleSyncTrace's original Java class monitor. */
    @JvmStatic
    fun due(event: String?, car: BaseVehicle?): Boolean {
        if (!enabled || !supported || car == null || records >= 5000) return false
        if (car.getDriver() == null && car.netPlayerId.toInt() == -1) return false
        val now = System.nanoTime()
        if (started == 0L) started = now
        if (now - started > 600_000_000_000L) return false
        val key = "$event:${car.getId()}"
        val previous = last[key]
        if (previous != null && now - previous < 1_000_000_000L) return false
        if (previous == null && last.size >= 256) return false
        last[key] = now
        records++
        return true
    }

    @JvmStatic
    fun log(event: String?, car: BaseVehicle?, detail: String?) {
        val vehicle = car ?: throw NullPointerException()
        val driver = vehicle.getDriver()
        val local = if (GameClient.client) IsoPlayer.getInstance() else null
        println("[VEHICLE_SYNC] t=" + System.currentTimeMillis()
            + " side=" + (if (GameServer.server) "server" else if (GameClient.client) "client" else "sp")
            + " event=" + event + " vehicle=" + vehicle.getId()
            + " local=" + (if (local == null) -1 else local.getOnlineID().toInt())
            + " driver=" + (if (driver == null) -1 else driver.getOnlineID().toInt())
            + " owner=" + vehicle.netPlayerId + " auth=" + vehicle.netPlayerAuthorization
            + " pos=" + vehicle.getX() + "," + vehicle.getY() + "," + vehicle.getZ()
            + " towing=" + (if (vehicle.getVehicleTowing() == null) -1 else vehicle.getVehicleTowing().getId().toInt())
            + " towedBy=" + (if (vehicle.getVehicleTowedBy() == null) -1 else vehicle.getVehicleTowedBy().getId().toInt())
            + " " + detail)
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
            VehicleSyncTrace.log("seat", car, "actor=" + (player ?: throw NullPointerException()).getOnlineID() + " entering=" + entering)
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
            VehicleSyncTrace.log("receiveServer", car, "allowed=" + car.hasAuthorization(sender)
                + " sample=" + sample.getX() + "," + sample.getY())
    }

    @JvmStatic
    fun receiveClient(packet: VehiclePhysicsPacket?, sender: UdpConnection?) {
        val sample = packet ?: throw NullPointerException()
        val car = sample.getVehicle()
        if (VehicleSyncTrace.due("receiveClient", car))
            VehicleSyncTrace.log("receiveClient", car, "ignoredAsOwner=" + car.hasAuthorization(sender)
                + " sample=" + sample.getX() + "," + sample.getY())
    }
}
