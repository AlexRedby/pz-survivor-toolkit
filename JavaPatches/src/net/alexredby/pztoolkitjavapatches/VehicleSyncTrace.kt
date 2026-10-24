package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.network.packets.vehicle.VehiclePhysicsPacket
import zombie.vehicles.BaseVehicle

/** Preserve the sampling class monitor, patch identities and suppression. */
object VehicleSyncTrace {
    /** Startup opt-in; use status() for the live session state. */
    @JvmField val ENABLED = VehicleSyncTraceLogic.enabled

    @JvmField val SUPPORTED = VehicleSyncTraceLogic.supported

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitVehicleTraceSet", global = true)
    fun set(enabled: Boolean): String = VehicleSyncTraceLogic.set(enabled)

    @JvmStatic
    @Synchronized
    @LuaMethod(name = "toolkitVehicleTraceStatus", global = true)
    fun status(): String = VehicleSyncTraceLogic.status()

    @JvmStatic
    @Synchronized
    fun due(event: String?, car: BaseVehicle?): Boolean = VehicleSyncTraceLogic.due(event, car)

    @JvmStatic
    fun log(event: String?, car: BaseVehicle?, detail: String?) {
        VehicleSyncTraceLogic.log(event, car, detail)
    }

    @Patch(className = "zombie.vehicles.BaseVehicle", methodName = "update", warmUp = true)
    object State {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun exit(@Patch.This car: BaseVehicle?) {
            VehicleSyncTraceLogic.state(car)
        }
    }

    @Patch(
        className = "zombie.vehicles.BaseVehicle",
        methodName = "setNetPlayerAuthorization",
        warmUp = true,
    )
    object Owner {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun enter(
            @Patch.This car: BaseVehicle?,
            @Patch.Argument(0) authorization: BaseVehicle.Authorization?,
            @Patch.Argument(1) player: Int,
        ) {
            VehicleSyncTraceLogic.owner(car, authorization, player)
        }
    }

    @Patch(
        className = "zombie.vehicles.BaseVehicle",
        methodName = "authorizationServerOnSeat",
        warmUp = true,
    )
    object Seat {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun exit(
            @Patch.This car: BaseVehicle?,
            @Patch.Argument(0) player: IsoPlayer?,
            @Patch.Argument(1) entering: Boolean,
        ) {
            VehicleSyncTraceLogic.seat(car, player, entering)
        }
    }

    @Patch(
        className = "zombie.network.packets.vehicle.VehiclePhysicsPacket",
        methodName = "set",
        warmUp = true,
    )
    object Send {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun exit(@Patch.This packet: VehiclePhysicsPacket?, @Patch.Argument(0) car: BaseVehicle?) {
            VehicleSyncTraceLogic.send(packet, car)
        }
    }

    @Patch(
        className = "zombie.network.packets.vehicle.VehiclePhysicsPacket",
        methodName = "processServer",
        warmUp = true,
    )
    object ReceiveServer {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun enter(
            @Patch.This packet: VehiclePhysicsPacket?,
            @Patch.Argument(1) sender: UdpConnection?,
        ) {
            VehicleSyncTraceLogic.receiveServer(packet, sender)
        }
    }

    @Patch(
        className = "zombie.network.packets.vehicle.VehiclePhysicsPacket",
        methodName = "processClient",
        warmUp = true,
    )
    object ReceiveClient {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun enter(
            @Patch.This packet: VehiclePhysicsPacket?,
            @Patch.Argument(0) sender: UdpConnection?,
        ) {
            VehicleSyncTraceLogic.receiveClient(packet, sender)
        }
    }
}
