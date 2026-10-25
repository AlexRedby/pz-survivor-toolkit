package zombie.vehicles

import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.Main
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.GameTime
import zombie.core.physics.Transform
import zombie.core.physics.WorldSimulation

object NativeChecks {
    @JvmStatic
    fun point(time: Long, x: Float): VehicleInterpolationData =
        VehicleInterpolationData().apply {
            this.time = time
            this.x = x
            qw = 1f
        }

    @JvmStatic
    fun set(target: Any?, name: String, value: Any?) {
        val field = BaseVehicle::class.java.getDeclaredField(name).apply { isAccessible = true }
        field.set(target, value)
    }

    @JvmStatic
    fun vehicle(): BaseVehicle {
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        val car =
            (field.get(null) as Unsafe).allocateInstance(BaseVehicle::class.java) as BaseVehicle
        val transform = Transform()
        transform.setIdentity()
        set(car, "jniTransform", transform)
        set(car, "jniLinearVelocity", Vector3f())
        set(car, "wheelInfo", emptyArray<BaseVehicle.WheelInfo>())
        set(car, "parts", VehicleParts())
        return car
    }

    @JvmStatic
    fun run(): FloatArray {
        val interpolation = VehicleInterpolation()
        val pose = FloatArray(27)
        val engine = FloatArray(2)
        val resumed = GameTime.getServerTimeMills() - interpolation.delay
        val frozen = resumed - 500
        interpolation.buffer.add(point(frozen - 100, 0f))
        interpolation.buffer.add(point(frozen, 0f))
        if (!interpolation.interpolationDataGet(pose, engine, frozen - 50, interpolation))
            throw AssertionError("initial bracket")
        if (!interpolation.interpolationDataGet(pose, engine, frozen + 1, interpolation))
            throw AssertionError("starvation freeze")
        if (!interpolation.wasNull || !interpolation.buffer.isEmpty())
            throw AssertionError("native recovery state")
        interpolation.interpolationDataAdd(
            vehicle(),
            point(resumed + 500, 10f),
            resumed + interpolation.delay,
        )
        val seed = interpolation.buffer.first().time
        if (!interpolation.interpolationDataGet(pose, engine, seed + 1, interpolation))
            throw AssertionError("first recovery frame")
        val first = pose[0]
        if (!interpolation.interpolationDataGet(pose, engine, seed + 34, interpolation))
            throw AssertionError("second recovery frame")
        return floatArrayOf(first, pose[0])
    }

    @JvmStatic
    fun nonemptyBuffer() {
        val interpolation = VehicleInterpolation()
        val now = GameTime.getServerTimeMills()
        val first = point(now - 100, 5f)
        interpolation.buffer.add(first)
        val cache = FloatArray(27)
        interpolation.lastBuf1 = cache
        interpolation.lastTime = 1234
        interpolation.interpolationDataAdd(vehicle(), point(now + 500, 10f), now)
        if (
            interpolation.lastBuf1 !== cache ||
                interpolation.lastTime != 1234L ||
                !interpolation.buffer.contains(first)
        )
            throw AssertionError("nonempty buffer/cache unexpectedly reset")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        zombie.network.GameClient.client = true
        WorldSimulation.instance.offsetX = 0f
        WorldSimulation.instance.offsetY = 0f
        val baseline = run()
        if (!(baseline[0] > baseline[1]))
            throw AssertionError("baseline did not reproduce backward step")
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            NativeChecks::class.java.classLoader,
        )
        Main.main(emptyArray())
        if (!Main.ZOMBIE_SUPPORTED || !Main.VEHICLE_SUPPORTED)
            throw AssertionError("unsupported native engine")
        if (BytecodeSupport.supports("zombie/vehicles/VehicleInterpolation.class", "unknown"))
            throw AssertionError("unknown engine fingerprint accepted")
        val patched = run() // Actual woven helper prefix; no manual clearLast here.
        if (!(patched[0] <= patched[1])) throw AssertionError("patch did not remove backward step")
        println("vehicle original: ${baseline[0]} -> ${baseline[1]}")
        println("vehicle patched: ${patched[0]} -> ${patched[1]}")
        nonemptyBuffer()
        zombie.network.GameClient.client = false
        val server = run()
        if (!(server[0] > server[1])) throw AssertionError("client patch changed server behavior")
        println(
            "NATIVE_CHECKS_PASS (recovery, nonempty buffer, server guard, unsupported fingerprint)",
        )
    }
}
