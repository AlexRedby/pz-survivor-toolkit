package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.raknet.UdpConnection;
import zombie.network.packets.vehicle.VehiclePhysicsPacket;
import zombie.vehicles.BaseVehicle;

/** Java entry points retain the sampling monitor, patch identities and suppression. */
public final class VehicleSyncTrace {
    public static final boolean ENABLED = VehicleSyncTraceLogic.enabled;
    public static final boolean SUPPORTED = VehicleSyncTraceLogic.supported;

    public static synchronized boolean due(String event, BaseVehicle car) {
        return VehicleSyncTraceLogic.due(event, car);
    }

    public static void log(String event, BaseVehicle car, String detail) {
        VehicleSyncTraceLogic.log(event, car, detail);
    }

    @Patch(className="zombie.vehicles.BaseVehicle", methodName="update", warmUp=true)
    public static class State {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This BaseVehicle car) {
            VehicleSyncTraceLogic.state(car);
        }
    }

    @Patch(className="zombie.vehicles.BaseVehicle", methodName="setNetPlayerAuthorization", warmUp=true)
    public static class Owner {
        @Patch.OnExit(suppress=Throwable.class)
        public static void enter(@Patch.This BaseVehicle car,
                                 @Patch.Argument(0) BaseVehicle.Authorization authorization,
                                 @Patch.Argument(1) int player) {
            VehicleSyncTraceLogic.owner(car, authorization, player);
        }
    }

    @Patch(className="zombie.vehicles.BaseVehicle", methodName="authorizationServerOnSeat", warmUp=true)
    public static class Seat {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This BaseVehicle car,
                                @Patch.Argument(0) zombie.characters.IsoPlayer player,
                                @Patch.Argument(1) boolean entering) {
            VehicleSyncTraceLogic.seat(car, player, entering);
        }
    }

    @Patch(className="zombie.network.packets.vehicle.VehiclePhysicsPacket", methodName="set", warmUp=true)
    public static class Send {
        @Patch.OnExit(suppress=Throwable.class)
        public static void exit(@Patch.This VehiclePhysicsPacket packet, @Patch.Argument(0) BaseVehicle car) {
            VehicleSyncTraceLogic.send(packet, car);
        }
    }

    @Patch(className="zombie.network.packets.vehicle.VehiclePhysicsPacket", methodName="processServer", warmUp=true)
    public static class ReceiveServer {
        @Patch.OnExit(suppress=Throwable.class)
        public static void enter(@Patch.This VehiclePhysicsPacket packet, @Patch.Argument(1) UdpConnection sender) {
            VehicleSyncTraceLogic.receiveServer(packet, sender);
        }

    }

    @Patch(className="zombie.network.packets.vehicle.VehiclePhysicsPacket", methodName="processClient", warmUp=true)
    public static class ReceiveClient {
        @Patch.OnExit(suppress=Throwable.class)
        public static void enter(@Patch.This VehiclePhysicsPacket packet, @Patch.Argument(0) UdpConnection sender) {
            VehicleSyncTraceLogic.receiveClient(packet, sender);
        }
    }
}
