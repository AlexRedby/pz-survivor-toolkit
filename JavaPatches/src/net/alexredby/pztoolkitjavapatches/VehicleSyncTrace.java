package net.alexredby.pztoolkitjavapatches;

import java.util.HashMap;
import java.util.Map;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.packets.vehicle.VehiclePhysicsPacket;
import zombie.vehicles.BaseVehicle;

/** Opt-in diagnostics; never changes vehicle state or packet delivery. */
public final class VehicleSyncTrace {
    public static final boolean ENABLED = Boolean.getBoolean("pz.vehicle.trace");
    public static final boolean SUPPORTED = Main.VEHICLE_OWNERSHIP_SUPPORTED
        && BytecodeSupport.supports("zombie/network/packets/vehicle/VehiclePhysicsPacket.class",
            "c3103be5b9bacad57747f49b94bff441ff6b530315885ed30c93dc05c13da2c4");
    private static final Map<String, Long> last = new HashMap<>();
    private static long started;
    private static int records;

    public static synchronized boolean due(String event, BaseVehicle car) {
        if (!ENABLED || !SUPPORTED || car == null || records >= 5000) return false;
        if (car.getDriver() == null && car.netPlayerId == -1) return false;
        long now = System.nanoTime();
        if (started == 0) started = now;
        if (now - started > 600_000_000_000L) return false;
        String key = event + ":" + car.getId();
        Long previous = last.get(key);
        if (previous != null && now - previous < 1_000_000_000L) return false;
        if (previous == null && last.size() >= 256) return false;
        last.put(key, now);
        records++;
        return true;
    }

    public static void log(String event, BaseVehicle car, String detail) {
        var driver = car.getDriver();
        var local = GameClient.client ? zombie.characters.IsoPlayer.getInstance() : null;
        System.out.println("[VEHICLE_SYNC] t=" + System.currentTimeMillis()
            + " side=" + (GameServer.server ? "server" : GameClient.client ? "client" : "sp")
            + " event=" + event + " vehicle=" + car.getId()
            + " local=" + (local == null ? -1 : local.getOnlineID())
            + " driver=" + (driver == null ? -1 : driver.getOnlineID())
            + " owner=" + car.netPlayerId + " auth=" + car.netPlayerAuthorization
            + " pos=" + car.getX() + "," + car.getY() + "," + car.getZ()
            + " towing=" + (car.getVehicleTowing() == null ? -1 : car.getVehicleTowing().getId())
            + " towedBy=" + (car.getVehicleTowedBy() == null ? -1 : car.getVehicleTowedBy().getId())
            + " " + detail);
    }

    @Patch(className="zombie.vehicles.BaseVehicle", methodName="update", warmUp=true)
    public static class State {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This BaseVehicle car) {
            if (VehicleSyncTrace.due("state", car)) VehicleSyncTrace.log("state", car, "");
        }
    }

    @Patch(className="zombie.vehicles.BaseVehicle", methodName="setNetPlayerAuthorization", warmUp=true)
    public static class Owner {
        @Patch.OnExit(suppress=Throwable.class)
        public static void enter(@Patch.This BaseVehicle car,
                                 @Patch.Argument(0) BaseVehicle.Authorization authorization,
                                 @Patch.Argument(1) int player) {
            if (VehicleSyncTrace.due("owner", car))
                VehicleSyncTrace.log("owner", car, "nextOwner=" + player + " nextAuth=" + authorization);
        }
    }

    @Patch(className="zombie.vehicles.BaseVehicle", methodName="authorizationServerOnSeat", warmUp=true)
    public static class Seat {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This BaseVehicle car,
                                @Patch.Argument(0) zombie.characters.IsoPlayer player,
                                @Patch.Argument(1) boolean entering) {
            if (VehicleSyncTrace.due("seat", car))
                VehicleSyncTrace.log("seat", car, "actor=" + player.getOnlineID() + " entering=" + entering);
        }
    }

    @Patch(className="zombie.network.packets.vehicle.VehiclePhysicsPacket", methodName="set", warmUp=true)
    public static class Send {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This VehiclePhysicsPacket packet, @Patch.Argument(0) BaseVehicle car) {
            if (VehicleSyncTrace.due("send", car))
                VehicleSyncTrace.log("send", car, "sample=" + packet.getX() + "," + packet.getY());
        }
    }

    @Patch(className="zombie.network.packets.vehicle.VehiclePhysicsPacket", methodName="processServer", warmUp=true)
    public static class ReceiveServer {
        @Patch.OnExit(suppress=Throwable.class)
        public static void enter(@Patch.This VehiclePhysicsPacket packet, @Patch.Argument(1) UdpConnection sender) {
            var car = packet.getVehicle();
            if (VehicleSyncTrace.due("receiveServer", car))
                VehicleSyncTrace.log("receiveServer", car, "allowed=" + car.hasAuthorization(sender)
                    + " sample=" + packet.getX() + "," + packet.getY());
        }

    }

    @Patch(className="zombie.network.packets.vehicle.VehiclePhysicsPacket", methodName="processClient", warmUp=true)
    public static class ReceiveClient {
        @Patch.OnExit(suppress=Throwable.class)
        public static void enter(@Patch.This VehiclePhysicsPacket packet, @Patch.Argument(0) UdpConnection sender) {
            var car = packet.getVehicle();
            if (VehicleSyncTrace.due("receiveClient", car))
                VehicleSyncTrace.log("receiveClient", car, "ignoredAsOwner=" + car.hasAuthorization(sender)
                    + " sample=" + packet.getX() + "," + packet.getY());
        }
    }
}
