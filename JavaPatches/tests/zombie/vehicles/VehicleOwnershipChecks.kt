package zombie.vehicles

import java.util.HashMap
import net.alexredby.pztoolkitjavapatches.VehicleOwnership
import sun.misc.Unsafe
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.network.GameClient
import zombie.network.GameServer

object VehicleOwnershipChecks {
    private lateinit var unsafe: Unsafe

    private fun set(target: Any?, type: Class<*>, name: String, value: Any?) {
        val field = type.getDeclaredField(name).apply { isAccessible = true }
        field.set(target, value)
    }

    private fun car(id: Short): BaseVehicle {
        val car = NativeChecks.vehicle()
        NativeChecks.set(car, "passengers", arrayOf(BaseVehicle.Passenger()))
        car.vehicleId = id
        car.netPlayerId = -1
        car.netPlayerAuthorization = BaseVehicle.Authorization.Server
        return car
    }

    private fun seat(car: BaseVehicle, driver: IsoPlayer) {
        car.getPassenger(0).character = driver
        set(driver, IsoGameCharacter::class.java, "vehicle", car)
    }

    private fun owned(car: BaseVehicle, id: Short) {
        if (car.netPlayerId != id || car.netPlayerAuthorization !== BaseVehicle.Authorization.Local)
            throw AssertionError("wrong owner ${car.netPlayerId}/${car.netPlayerAuthorization}")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        unsafe = field.get(null) as Unsafe
        GameClient.client = false
        GameServer.server = true
        val driver = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        driver.onlineId = 4
        set(driver, IsoGameCharacter::class.java, "health", 100f)
        val connection = unsafe.allocateInstance(UdpConnection::class.java) as UdpConnection
        set(connection, UdpConnection::class.java, "fullyConnected", true)
        val engine = unsafe.allocateInstance(UdpEngine::class.java) as UdpEngine
        set(engine, UdpEngine::class.java, "connectionMap", HashMap(mapOf(42L to connection)))
        GameServer.udpEngine = engine
        GameServer.PlayerToAddressMap.put(driver, 42L)
        GameServer.IDToPlayerMap.put(driver.onlineId, driver)
        val car = car(1)
        seat(car, driver)

        // Original collision/seat/release methods reproduce the stale authority without a network
        // overlay.
        car.authorizationServerCollide(0, true)
        car.authorizationServerOnSeat(driver, true)
        if (car.netPlayerId.toInt() != 0)
            throw AssertionError("baseline collision owner was replaced")
        car.authorizationServerCollide((-1).toShort(), false)
        if (car.netPlayerId.toInt() != -1) throw AssertionError("baseline late release")
        VehicleOwnership.reconcile(car, false)
        if (car.netPlayerId.toInt() != -1) throw AssertionError("unsupported engine changed")
        VehicleOwnership.reconcile(car, true)
        owned(car, 4)
        NativeChecks.set(car, "timeSinceLastAuth", 3f)
        VehicleOwnership.reconcile(car, true)
        val timer =
            BaseVehicle::class.java.getDeclaredField("timeSinceLastAuth").apply {
                isAccessible = true
            }
        if (timer.getFloat(car) != 3f) throw AssertionError("unchanged owner refreshed every frame")

        car.netPlayerId = 0
        car.netPlayerAuthorization = BaseVehicle.Authorization.Local
        GameServer.server = false
        VehicleOwnership.reconcile(car, true)
        owned(car, 0)
        GameServer.server = true
        set(connection, UdpConnection::class.java, "fullyConnected", false)
        VehicleOwnership.reconcile(car, true)
        owned(car, 0)
        set(connection, UdpConnection::class.java, "fullyConnected", true)
        GameServer.IDToPlayerMap.remove(driver.onlineId)
        VehicleOwnership.reconcile(car, true)
        owned(car, 0)
        GameServer.IDToPlayerMap.put(driver.onlineId, driver)
        GameServer.PlayerToAddressMap.remove(driver)
        VehicleOwnership.reconcile(car, true)
        owned(car, 0)
        GameServer.PlayerToAddressMap.put(driver, 42L)
        set(driver, IsoGameCharacter::class.java, "vehicle", null)
        VehicleOwnership.reconcile(car, true)
        owned(car, 0)
        seat(car, driver)
        set(driver, IsoGameCharacter::class.java, "health", 0f)
        VehicleOwnership.reconcile(car, true)
        owned(car, 0)
        set(driver, IsoGameCharacter::class.java, "health", 100f)

        val trailer = car(2)
        NativeChecks.set(car, "vehicleTowing", trailer)
        NativeChecks.set(trailer, "vehicleTowedBy", car)
        VehicleOwnership.reconcile(trailer, true)
        owned(car, 4)
        owned(trailer, 4)
        car.getPassenger(0).character = null
        car.netPlayerAuthorization = BaseVehicle.Authorization.LocalCollide
        car.netPlayerId = 0
        trailer.netPlayerAuthorization = BaseVehicle.Authorization.LocalCollide
        trailer.netPlayerId = 0
        VehicleOwnership.reconcile(car, true)
        if (
            car.netPlayerId.toInt() != 0 ||
                trailer.netPlayerId.toInt() != 0 ||
                car.netPlayerAuthorization !== BaseVehicle.Authorization.LocalCollide
        )
            throw AssertionError("idle collision/towing authority changed")
        seat(car, driver)
        NativeChecks.set(car, "vehicleTowing", null)
        VehicleOwnership.reconcile(trailer, true)
        if (trailer.netPlayerId.toInt() != 0) throw AssertionError("asymmetric towing link changed")
        println(
            "VEHICLE_OWNERSHIP_CHECKS_PASS (native race, unsupported/client/dead/disconnected/asymmetric guards, idempotency, towing, idle collision)",
        )
    }
}
