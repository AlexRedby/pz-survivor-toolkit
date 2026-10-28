package net.alexredby.vehiclelightsfixture;

import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.vehicles.BaseVehicle;
import zombie.vehicles.VehiclePart;

/** Disposable input and read-only lamp diagnostics; native transmission logic stays intact. */
public final class Main {
    public static volatile int inputMode = -1;
    private static Float originalZoom;
    private static boolean originalAutoZoom;
    private static final String[] PARTS = {
        "HeadlightLeft", "HeadlightRight", "HeadlightRearLeft", "HeadlightRearRight"
    };

    public static boolean ownedCache() {
        String cache = System.getenv("PZ_LIGHTS_TEST_CACHE");
        return cache != null && Path.of(cache).isAbsolute()
            && Path.of(cache).normalize().equals(
                Path.of(ZomboidFileSystem.instance.getCacheDir()).toAbsolutePath().normalize());
    }

    private static void disposable() {
        if (!ownedCache()) throw new IllegalStateException("Disposable lights runner cache required");
    }

    @Patch(className="zombie.iso.IsoChunkMap", methodName="CalcChunkWidth", warmUp=true)
    public static class PadChunks {
        @Patch.OnExit
        public static void exit() {
            if (!ownedCache()) return;
            zombie.iso.IsoChunkMap.chunkGridWidth = Math.max(25, zombie.iso.IsoChunkMap.chunkGridWidth);
            zombie.iso.IsoChunkMap.chunkWidthInTiles = zombie.iso.IsoChunkMap.chunkGridWidth * 8;
        }
    }

    @LuaMethod(name="lightsFixtureInput", global=true)
    public static void input(int mode) {
        disposable();
        if (mode < -1 || mode > 3) throw new IllegalArgumentException("Input mode must be -1 through 3");
        inputMode = mode;
    }

    public static boolean fixtureKey(int key) {
        String binding = switch (inputMode) {
            case 1 -> "Backward";
            case 2 -> "Forward";
            case 3 -> "Brake";
            default -> null;
        };
        return binding != null && key == Core.getInstance().getKey(binding);
    }

    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDown", warmUp=true, strictMatch=true)
    public static class Keys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) {
            fixture = inputMode >= 0 && ownedCache();
            return fixture;
        }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) {
            if (fixture) result = fixtureKey(key);
        }
    }

    @Patch(className="zombie.input.GameKeyboard", methodName="isKeyDownRaw", warmUp=true, strictMatch=true)
    public static class RawKeys {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture) {
            fixture = inputMode >= 0 && ownedCache();
            return fixture;
        }
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) int key, @Patch.Local("fixture") boolean fixture,
                                @Patch.Return(readOnly=false) boolean result) {
            if (fixture) result = fixtureKey(key);
        }
    }

    @LuaMethod(name="lightsFixtureCamera", global=true)
    public static void camera(double zoom) {
        disposable();
        if (!Double.isFinite(zoom) || zoom <= 0 || zoom > Float.MAX_VALUE)
            throw new IllegalArgumentException("Zoom must be a positive finite float");
        Core core = Core.getInstance();
        if (originalZoom == null) {
            originalZoom = core.getZoom(0);
            originalAutoZoom = core.offscreenBuffer.autoZoom[0];
        }
        core.offscreenBuffer.autoZoom[0] = false;
        core.offscreenBuffer.setZoomAndTargetZoom(0, (float) zoom);
    }

    @LuaMethod(name="lightsFixtureRestore", global=true)
    public static void restore() {
        disposable();
        inputMode = -1;
        if (originalZoom != null) {
            Core core = Core.getInstance();
            core.offscreenBuffer.autoZoom[0] = originalAutoZoom;
            core.offscreenBuffer.setZoomAndTargetZoom(0, originalZoom);
            originalZoom = null;
        }
    }

    @LuaMethod(name="lightsFixtureMotionIdle", global=true)
    public static boolean motionIdle() {
        disposable();
        IsoPlayer player = IsoPlayer.getInstance();
        var deferred = player.getDeferredMovement(new zombie.iso.Vector2());
        return !player.isPlayerMoving() && !player.pressedMovement(false) && !player.hasPath()
            && deferred.x == 0 && deferred.y == 0;
    }

    @LuaMethod(name="lightsFixtureMotionProbe", global=true)
    public static String motionProbe() {
        disposable();
        IsoPlayer player = IsoPlayer.getInstance();
        var deferred = player.getDeferredMovement(new zombie.iso.Vector2());
        return "moving=" + player.isPlayerMoving() + " pressed=" + player.pressedMovement(false)
            + " path=" + player.hasPath() + " deferred=" + deferred.x + "," + deferred.y
            + " state=" + player.getCurrentStateName() + " input=" + inputMode;
    }

    @LuaMethod(name="lightsFixtureOriginError", global=true)
    public static double originError(String id, double x, double z) {
        disposable();
        BaseVehicle vehicle = IsoPlayer.getInstance().getVehicle();
        var expected = vehicle.getWorldPos((float)x,0,(float)z,new org.joml.Vector3f());
        var torch = zombie.characters.IsoGameCharacter.TorchInfo.alloc();
        try {
            torch.set(vehicle.getPartById(id));
            return Math.hypot(torch.x-expected.x,torch.y-expected.y);
        } finally { zombie.characters.IsoGameCharacter.TorchInfo.release(torch); }
    }

    private static float screen(String id, boolean x) {
        disposable();
        var torch = zombie.characters.IsoGameCharacter.TorchInfo.alloc();
        try {
            torch.set(IsoPlayer.getInstance().getVehicle().getPartById(id));
            float value = x ? zombie.iso.IsoUtils.XToScreenExact(torch.x,torch.y,torch.z,0)
                : zombie.iso.IsoUtils.YToScreenExact(torch.x,torch.y,torch.z,0);
            return value / Core.getInstance().getZoom(0);
        } finally { zombie.characters.IsoGameCharacter.TorchInfo.release(torch); }
    }

    @LuaMethod(name="lightsFixtureOriginScreenX", global=true)
    public static float screenX(String id) { return screen(id,true); }
    @LuaMethod(name="lightsFixtureOriginScreenY", global=true)
    public static float screenY(String id) { return screen(id,false); }

    private static String light(BaseVehicle vehicle, String id) {
        VehiclePart part = vehicle.getPartById(id);
        if (part == null || part.getLight() == null) return "null";
        var light = part.getLight();
        return "{\"distance\":" + light.dist + ",\"intensity\":" + light.intensity
            + ",\"dot\":" + light.dot + ",\"offsetX\":" + light.offset.x + ",\"offsetY\":" + light.offset.y
            + ",\"effectiveDistance\":" + part.getLightDistance() + ",\"condition\":" + part.getCondition()
            + ",\"r\":" + light.r + ",\"g\":" + light.g + ",\"b\":" + light.b
            + ",\"active\":" + light.active + "}";
    }

    @LuaMethod(name="lightsFixtureProbe", global=true)
    public static String probe() {
        disposable();
        IsoPlayer player = IsoPlayer.getInstance();
        BaseVehicle vehicle = player == null ? null : player.getVehicle();
        if (vehicle == null) return "{\"vehicle\":false}";
        StringBuilder out = new StringBuilder("{\"vehicle\":true,\"driver\":")
            .append(vehicle.isDriver(player)).append(",\"transmission\":\"")
            .append(vehicle.getTransmissionNumberLetter()).append("\",\"headlights\":")
            .append(vehicle.getHeadlightsOn()).append(",\"battery\":").append(vehicle.getBatteryCharge());
        for (String id : PARTS) out.append(",\"").append(id).append("\":").append(light(vehicle, id));
        out.append(",\"spillSources\":[");
        boolean first = true;
        for (var source : zombie.iso.IsoWorld.instance.getCell().getLamppostPositions()) {
            if (Math.abs(source.x - vehicle.getX()) > 8 || Math.abs(source.y - vehicle.getY()) > 8) continue;
            if (!first) out.append(',');
            first = false;
            out.append("{\"id\":").append(source.id).append(",\"x\":").append(source.x)
                .append(",\"y\":").append(source.y).append(",\"radius\":").append(source.radius)
                .append(",\"r\":").append(source.r).append(",\"rJNI\":").append(source.rJni)
                .append(",\"activeJNI\":").append(source.activeJni).append(",\"inBounds\":").append(source.isInBounds()).append(",\"active\":").append(source.active).append(",\"life\":").append(source.life).append('}');
        }
        return out.append("]}").toString();
    }

    public static void main(String[] args) { System.out.println("[VEHICLE_LIGHTS] HELPER_READY"); }
}
