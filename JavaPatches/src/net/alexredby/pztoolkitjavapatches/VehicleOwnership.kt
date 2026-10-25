package net.alexredby.pztoolkitjavapatches

import zombie.characters.IsoPlayer
import zombie.network.GameServer
import zombie.vehicles.BaseVehicle

object VehicleOwnership {
    @JvmStatic
    fun reconcile(car: BaseVehicle?, supported: Boolean) {
        if (!supported || !GameServer.server || car == null) return
        var root = car.getVehicleTowedBy()
        if (root == null) root = car else if (root.getVehicleTowing() !== car) return
        val driver = root.getDriver()
        if (
            driver !is IsoPlayer ||
                driver.getVehicle() !== root ||
                driver.getOnlineID().toInt() == -1 ||
                driver.isDead() ||
                GameServer.IDToPlayerMap.get(driver.getOnlineID()) !== driver
        )
            return
        val connection = GameServer.getConnectionFromPlayer(driver) ?: return
        if (!connection.isFullyConnected()) return
        assign(root, driver)
        val trailer = root.getVehicleTowing()
        if (trailer != null && trailer.getVehicleTowedBy() === root) assign(trailer, driver)
    }

    private fun assign(car: BaseVehicle, driver: IsoPlayer) {
        if (
            car.netPlayerId.toInt() == driver.getOnlineID().toInt() &&
                car.netPlayerAuthorization === BaseVehicle.Authorization.Local
        )
            return
        if (VehicleSyncTrace.due("repair", car))
            VehicleSyncTrace.log("repair", car, "nextOwner=" + driver.getOnlineID())
        // A late collision release can leave an occupied car without its driver's authority.
        car.authorizationChanged(driver)
    }
}
