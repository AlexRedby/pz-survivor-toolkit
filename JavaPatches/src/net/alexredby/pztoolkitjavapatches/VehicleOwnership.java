package net.alexredby.pztoolkitjavapatches;

import zombie.characters.IsoPlayer;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;

public final class VehicleOwnership {
    public static void reconcile(BaseVehicle car, boolean supported) {
        if (!supported || !GameServer.server || car == null) return;
        BaseVehicle root = car.getVehicleTowedBy();
        if (root == null) root = car;
        else if (root.getVehicleTowing() != car) return;
        if (!(root.getDriver() instanceof IsoPlayer driver) || driver.getVehicle() != root
            || driver.getOnlineID() == -1 || driver.isDead()
            || GameServer.IDToPlayerMap.get(driver.getOnlineID()) != driver) return;
        var connection = GameServer.getConnectionFromPlayer(driver);
        if (connection == null || !connection.isFullyConnected()) return;
        assign(root, driver);
        var trailer = root.getVehicleTowing();
        if (trailer != null && trailer.getVehicleTowedBy() == root) assign(trailer, driver);
    }

    private static void assign(BaseVehicle car, IsoPlayer driver) {
        if (car.netPlayerId == driver.getOnlineID()
            && car.netPlayerAuthorization == BaseVehicle.Authorization.Local) return;
        if (VehicleSyncTrace.due("repair", car))
            VehicleSyncTrace.log("repair", car, "nextOwner=" + driver.getOnlineID());
        // A late collision release can leave an occupied car without its driver's authority.
        car.authorizationChanged(driver);
    }
}
