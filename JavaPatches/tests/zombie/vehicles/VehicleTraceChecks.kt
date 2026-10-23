package zombie.vehicles

import net.alexredby.pztoolkitjavapatches.VehicleSyncTrace

object VehicleTraceChecks {
    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val car = NativeChecks.vehicle()
        NativeChecks.set(car, "passengers", emptyArray<BaseVehicle.Passenger>())
        car.netPlayerId = 9
        if (!VehicleSyncTrace.SUPPORTED) throw AssertionError("wrong native engine")
        if (VehicleSyncTrace.due("state", null)) throw AssertionError("missing car traced")
        if (VehicleSyncTrace.ENABLED) {
            if (!VehicleSyncTrace.due("state", car) || VehicleSyncTrace.due("state", car))
                throw AssertionError("per-vehicle sample throttle")
            for (i in 0 until 255) if (!VehicleSyncTrace.due("event$i", car))
                throw AssertionError("early key cap")
            if (VehicleSyncTrace.due("overflow", car)) throw AssertionError("unbounded keys")
        } else if (VehicleSyncTrace.due("state", car))
            throw AssertionError("trace enabled by default")
        if (car.netPlayerId.toInt() != 9 || car.getX() != 0f || car.getY() != 0f)
            throw AssertionError("diagnostics changed ownership or coordinates")
        println("VEHICLE_TRACE_CHECKS_PASS enabled=" + VehicleSyncTrace.ENABLED)
    }
}
