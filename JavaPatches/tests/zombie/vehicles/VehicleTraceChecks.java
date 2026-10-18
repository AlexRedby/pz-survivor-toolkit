package zombie.vehicles;

import net.alexredby.pztoolkitjavapatches.VehicleSyncTrace;

public final class VehicleTraceChecks {
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        BaseVehicle car = NativeChecks.vehicle();
        NativeChecks.set(car, "passengers", new BaseVehicle.Passenger[0]);
        car.netPlayerId = 9;
        if (!VehicleSyncTrace.SUPPORTED) throw new AssertionError("wrong native engine");
        if (VehicleSyncTrace.due("state", null)) throw new AssertionError("missing car traced");
        if (VehicleSyncTrace.ENABLED) {
            if (!VehicleSyncTrace.due("state", car) || VehicleSyncTrace.due("state", car))
                throw new AssertionError("per-vehicle sample throttle");
            for (int i = 0; i < 255; i++)
                if (!VehicleSyncTrace.due("event" + i, car)) throw new AssertionError("early key cap");
            if (VehicleSyncTrace.due("overflow", car)) throw new AssertionError("unbounded keys");
        } else if (VehicleSyncTrace.due("state", car)) throw new AssertionError("trace enabled by default");
        if (car.netPlayerId != 9 || car.getX() != 0 || car.getY() != 0)
            throw new AssertionError("diagnostics changed ownership or coordinates");
        System.out.println("VEHICLE_TRACE_CHECKS_PASS enabled=" + VehicleSyncTrace.ENABLED);
    }
}
