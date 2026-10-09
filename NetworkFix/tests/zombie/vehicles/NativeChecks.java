package zombie.vehicles;

import java.lang.reflect.Field;
import sun.misc.Unsafe;
import zombie.GameTime;
import zombie.core.physics.Transform;
import zombie.core.physics.WorldSimulation;
import org.joml.Vector3f;

public final class NativeChecks {
    static VehicleInterpolationData point(long time, float x) {
        VehicleInterpolationData p = new VehicleInterpolationData();
        p.time = time; p.x = x; p.qw = 1;
        return p;
    }
    static void set(Object target, String name, Object value) throws Exception {
        Field f = BaseVehicle.class.getDeclaredField(name); f.setAccessible(true); f.set(target, value);
    }
    static BaseVehicle vehicle() throws Exception {
        Field uf = Unsafe.class.getDeclaredField("theUnsafe"); uf.setAccessible(true);
        BaseVehicle car = (BaseVehicle) ((Unsafe)uf.get(null)).allocateInstance(BaseVehicle.class);
        Transform transform = new Transform(); transform.setIdentity();
        set(car, "jniTransform", transform);
        set(car, "jniLinearVelocity", new Vector3f());
        set(car, "wheelInfo", new BaseVehicle.WheelInfo[0]);
        set(car, "parts", new VehicleParts());
        return car;
    }
    static float[] run() throws Exception {
        VehicleInterpolation v = new VehicleInterpolation();
        float[] pose = new float[27], engine = new float[2];
        long resumed = GameTime.getServerTimeMills() - v.delay;
        long frozen = resumed - 500;
        v.buffer.add(point(frozen - 100, 0));
        v.buffer.add(point(frozen, 0));
        if (!v.interpolationDataGet(pose, engine, frozen - 50, v)) throw new AssertionError("initial bracket");
        if (!v.interpolationDataGet(pose, engine, frozen + 1, v)) throw new AssertionError("starvation freeze");
        if (!v.wasNull || !v.buffer.isEmpty()) throw new AssertionError("native recovery state");
        v.interpolationDataAdd(vehicle(), point(resumed + 500, 10), resumed + v.delay);
        long seed = v.buffer.first().time;
        if (!v.interpolationDataGet(pose, engine, seed + 1, v)) throw new AssertionError("first recovery frame");
        float first = pose[0];
        if (!v.interpolationDataGet(pose, engine, seed + 34, v)) throw new AssertionError("second recovery frame");
        return new float[]{first, pose[0]};
    }
    static void nonemptyBuffer() throws Exception {
        VehicleInterpolation v = new VehicleInterpolation();
        long now = GameTime.getServerTimeMills();
        VehicleInterpolationData first = point(now - 100, 5);
        v.buffer.add(first);
        float[] cache = new float[27];
        v.lastBuf1 = cache; v.lastTime = 1234;
        v.interpolationDataAdd(vehicle(), point(now + 500, 10), now);
        if (v.lastBuf1 != cache || v.lastTime != 1234 || !v.buffer.contains(first))
            throw new AssertionError("nonempty buffer/cache unexpectedly reset");
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        zombie.network.GameClient.client = true;
        WorldSimulation.instance.offsetX = 0;
        WorldSimulation.instance.offsetY = 0;
        float[] baseline = run();
        if (!(baseline[0] > baseline[1])) throw new AssertionError("baseline did not reproduce backward step");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pznetworkfix", NativeChecks.class.getClassLoader());
        net.alexredby.pznetworkfix.Main.main(new String[0]);
        if (!net.alexredby.pznetworkfix.Main.ZOMBIE_SUPPORTED || !net.alexredby.pznetworkfix.Main.VEHICLE_SUPPORTED)
            throw new AssertionError("unsupported native engine");
        if (net.alexredby.pznetworkfix.Main.supports("zombie/vehicles/VehicleInterpolation.class", "unknown"))
            throw new AssertionError("unknown engine fingerprint accepted");
        float[] patched = run(); // Actual woven helper prefix; no manual clearLast here.
        if (!(patched[0] <= patched[1])) throw new AssertionError("patch did not remove backward step");
        System.out.println("vehicle original: " + baseline[0] + " -> " + baseline[1]);
        System.out.println("vehicle patched: " + patched[0] + " -> " + patched[1]);
        nonemptyBuffer();
        zombie.network.GameClient.client = false;
        float[] server = run();
        if (!(server[0] > server[1])) throw new AssertionError("client patch changed server behavior");
        System.out.println("NATIVE_CHECKS_PASS (recovery, nonempty buffer, server guard, unsupported fingerprint)");
    }
}
