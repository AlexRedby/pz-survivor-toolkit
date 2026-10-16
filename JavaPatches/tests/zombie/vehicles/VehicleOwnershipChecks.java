package zombie.vehicles;

import java.lang.reflect.Field;
import java.util.HashMap;
import sun.misc.Unsafe;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.raknet.UdpConnection;
import zombie.core.raknet.UdpEngine;
import zombie.network.GameClient;
import zombie.network.GameServer;
import net.alexredby.pztoolkitjavapatches.VehicleOwnership;

public final class VehicleOwnershipChecks {
    static Unsafe unsafe;
    static void set(Object target, Class<?> type, String name, Object value) throws Exception {
        Field field = type.getDeclaredField(name); field.setAccessible(true); field.set(target, value);
    }
    static BaseVehicle car(short id) throws Exception {
        BaseVehicle car = NativeChecks.vehicle();
        NativeChecks.set(car, "passengers", new BaseVehicle.Passenger[]{new BaseVehicle.Passenger()});
        car.vehicleId = id; car.netPlayerId = -1; car.netPlayerAuthorization = BaseVehicle.Authorization.Server;
        return car;
    }
    static void seat(BaseVehicle car, IsoPlayer driver) throws Exception {
        car.getPassenger(0).character = driver;
        set(driver, IsoGameCharacter.class, "vehicle", car);
    }
    static void owned(BaseVehicle car, short id) {
        if (car.netPlayerId != id || car.netPlayerAuthorization != BaseVehicle.Authorization.Local)
            throw new AssertionError("wrong owner " + car.netPlayerId + "/" + car.netPlayerAuthorization);
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        Field field = Unsafe.class.getDeclaredField("theUnsafe"); field.setAccessible(true); unsafe = (Unsafe) field.get(null);
        GameClient.client = false; GameServer.server = true;
        IsoPlayer driver = (IsoPlayer) unsafe.allocateInstance(IsoPlayer.class);
        driver.onlineId = 4; set(driver, IsoGameCharacter.class, "health", 100f);
        UdpConnection connection = (UdpConnection) unsafe.allocateInstance(UdpConnection.class);
        set(connection, UdpConnection.class, "fullyConnected", true);
        UdpEngine engine = (UdpEngine) unsafe.allocateInstance(UdpEngine.class);
        set(engine, UdpEngine.class, "connectionMap", new HashMap<>(java.util.Map.of(42L, connection)));
        GameServer.udpEngine = engine;
        GameServer.PlayerToAddressMap.put(driver, 42L); GameServer.IDToPlayerMap.put(driver.onlineId, driver);
        BaseVehicle car = car((short)1); seat(car, driver);

        // Original collision/seat/release methods reproduce the stale authority without a network overlay.
        car.authorizationServerCollide((short)0, true);
        car.authorizationServerOnSeat(driver, true);
        if (car.netPlayerId != 0) throw new AssertionError("baseline collision owner was replaced");
        car.authorizationServerCollide((short)-1, false);
        if (car.netPlayerId != -1) throw new AssertionError("baseline late release");
        VehicleOwnership.reconcile(car, false);
        if (car.netPlayerId != -1) throw new AssertionError("unsupported engine changed");
        VehicleOwnership.reconcile(car, true); owned(car, (short)4);
        NativeChecks.set(car, "timeSinceLastAuth", 3f);
        VehicleOwnership.reconcile(car, true);
        Field timer = BaseVehicle.class.getDeclaredField("timeSinceLastAuth"); timer.setAccessible(true);
        if (timer.getFloat(car) != 3f) throw new AssertionError("unchanged owner refreshed every frame");

        car.netPlayerId = 0; car.netPlayerAuthorization = BaseVehicle.Authorization.Local;
        GameServer.server = false; VehicleOwnership.reconcile(car, true); owned(car, (short)0);
        GameServer.server = true;
        set(connection, UdpConnection.class, "fullyConnected", false);
        VehicleOwnership.reconcile(car, true); owned(car, (short)0);
        set(connection, UdpConnection.class, "fullyConnected", true);
        GameServer.IDToPlayerMap.remove(driver.onlineId);
        VehicleOwnership.reconcile(car, true); owned(car, (short)0);
        GameServer.IDToPlayerMap.put(driver.onlineId, driver);
        GameServer.PlayerToAddressMap.remove(driver);
        VehicleOwnership.reconcile(car, true); owned(car, (short)0);
        GameServer.PlayerToAddressMap.put(driver, 42L);
        set(driver, IsoGameCharacter.class, "vehicle", null);
        VehicleOwnership.reconcile(car, true); owned(car, (short)0);
        seat(car, driver);
        set(driver, IsoGameCharacter.class, "health", 0f);
        VehicleOwnership.reconcile(car, true); owned(car, (short)0);
        set(driver, IsoGameCharacter.class, "health", 100f);

        BaseVehicle trailer = car((short)2);
        NativeChecks.set(car, "vehicleTowing", trailer); NativeChecks.set(trailer, "vehicleTowedBy", car);
        VehicleOwnership.reconcile(trailer, true); owned(car, (short)4); owned(trailer, (short)4);
        car.getPassenger(0).character = null;
        car.netPlayerAuthorization = BaseVehicle.Authorization.LocalCollide; car.netPlayerId = 0;
        trailer.netPlayerAuthorization = BaseVehicle.Authorization.LocalCollide; trailer.netPlayerId = 0;
        VehicleOwnership.reconcile(car, true);
        if (car.netPlayerId != 0 || trailer.netPlayerId != 0
            || car.netPlayerAuthorization != BaseVehicle.Authorization.LocalCollide)
            throw new AssertionError("idle collision/towing authority changed");
        seat(car, driver); NativeChecks.set(car, "vehicleTowing", null);
        VehicleOwnership.reconcile(trailer, true);
        if (trailer.netPlayerId != 0) throw new AssertionError("asymmetric towing link changed");
        System.out.println("VEHICLE_OWNERSHIP_CHECKS_PASS (native race, unsupported/client/dead/disconnected/asymmetric guards, idempotency, towing, idle collision)");
    }
}
