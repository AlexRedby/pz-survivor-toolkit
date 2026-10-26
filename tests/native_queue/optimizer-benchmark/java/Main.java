package net.alexredby.drivingperf;

import java.io.BufferedWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import me.zed_0xff.zombie_buddy.Patch;
import org.joml.Vector3f;
import org.lwjglx.opengl.Display;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.GameWindow;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.core.Core;
import zombie.core.PerformanceSettings;
import zombie.core.physics.CarController;
import zombie.iso.IsoWorld;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.vehicles.BaseVehicle;

/** Disposable SP input and timing probe. No installed game/profile is accepted. */
public final class Main {
    private static final int CAPACITY = 120000;
    private static final long[] swapNs = new long[CAPACITY], frameNs = new long[CAPACITY], cpuNs = new long[CAPACITY];
    private static final int[] swapPhase = new int[CAPACITY], framePhase = new int[CAPACITY];
    private static final Object swapLock = new Object();
    private static int swaps, frames;
    private static volatile int phase; // 1 stationary, 2 approach, 3 measured, 4 finished, -1 failed
    private static volatile boolean overflow;
    private static BaseVehicle owned;
    private static IsoPlayer actor;
    private static Path cache;
    private static Thread ownerThread;
    private static double startX, startY, forwardX, forwardY, speed, approach, distance, stationary;
    private static long began, phaseAt, lastLog, offSpeedAt, totalOffSpeedNs;
    private static double zoom;
    private static int width, height, framebufferWidth, framebufferHeight, minimumVisibleZombies;
    private static int zombieSamples, populatedZombieSamples, maxVisibleZombies, speedDips, pendingContacts;
    private static volatile int contacts;
    private static double headingError, previousHeadingError, filteredYawRate, steeringInput, maxLateral, maxHeading;
    private static long lastSteerNs;
    private static boolean collisionFlag, fullThrottle;
    private static String vehicleScript;
    private static double maxActualSpeed;
    private static String failure;
    private static boolean dumped;
    private static final Vector3f direction = new Vector3f();

    public static void main(String[] args) {
        System.out.println("[DRIVING_PERF] probe loaded; explicit disposable-cache/vehicle gate required");
    }

    private static void gate() throws Exception {
        String expected = System.getProperty("pz.drivingPerf.cachedir", "");
        if (expected.isBlank() || GameClient.client || GameServer.server)
            throw new IllegalStateException("Explicit isolated SP cache required");
        Path actual = Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath();
        if (!Path.of(expected).toRealPath().equals(actual)
                || !Files.isRegularFile(actual.resolve("Lua/DrivingBench-run.txt"))
                || !IsoWorld.instance.getWorld().startsWith("PZDrivingBench-"))
            throw new IllegalStateException("Wrong disposable benchmark world/cache");
        cache = actual;
    }

    @LuaMethod(name="drivingPerfSetZoom", global=true)
    public static void setZoom(IsoPlayer player, double zoomFactor) throws Exception {
        gate();
        if (player == null || !Double.isFinite(zoomFactor) || zoomFactor < 1.5 || zoomFactor > 2.5)
            throw new IllegalArgumentException("Expected benchmark zoom 1.5..2.5");
        Core.getInstance().setAutoZoom(player.getPlayerNum(), false);
        Core.getInstance().offscreenBuffer.setZoomAndTargetZoom(player.getPlayerNum(), (float)zoomFactor);
    }

    @LuaMethod(name="drivingPerfBegin", global=true)
    public static String begin(IsoPlayer player, double targetKmh, double stationarySeconds,
                               double approachTiles, double measuredTiles, double zoomFactor, double minVisibleZombies,
                               boolean useFullThrottle, String expectedVehicleScript) throws Exception {
        if (owned != null) throw new IllegalStateException("One benchmark per JVM");
        gate();
        if (!Double.isFinite(targetKmh) || !Double.isFinite(stationarySeconds)
                || !Double.isFinite(approachTiles) || !Double.isFinite(measuredTiles)
                || !Double.isFinite(zoomFactor) || zoomFactor < 1.5 || zoomFactor > 2.5
                || !Double.isFinite(minVisibleZombies) || minVisibleZombies < 0 || minVisibleZombies > 1000
                || minVisibleZombies != Math.floor(minVisibleZombies)
                || (useFullThrottle ? targetKmh < 80 || targetKmh > 200 : targetKmh < 10 || targetKmh > 60)
                || stationarySeconds < 3 || stationarySeconds > 60
                || approachTiles < 10 || approachTiles > 500 || measuredTiles < 20 || measuredTiles > 1500)
            throw new IllegalArgumentException("Out-of-range benchmark parameters");
        if (!"Base.CarNormal".equals(expectedVehicleScript) && !"Base.SportsCar".equals(expectedVehicleScript))
            throw new IllegalArgumentException("Only native Base.CarNormal/Base.SportsCar benchmark vehicles are reviewed");
        BaseVehicle vehicle = player == null ? null : player.getVehicle();
        if (vehicle == null || !vehicle.isDriver(player) || vehicle.getSeat(player) != 0
                || vehicle.getModData().rawget("PZDrivingBenchFixture") == null
                || !expectedVehicleScript.equals(vehicle.getScriptName()) || !vehicle.isEngineRunning()
                || Math.abs(vehicle.getCurrentSpeedKmHour()) > .5f)
            throw new IllegalStateException("Owned, stationary, running starter car required");
        if (PerformanceSettings.instance.getFramerate() != 144 || Core.getInstance().getOptionVSync())
            throw new IllegalStateException("Benchmark requires actual cap144 and VSync off");
        actor = player; owned = vehicle; ownerThread = Thread.currentThread();
        fullThrottle = useFullThrottle; vehicleScript = expectedVehicleScript;
        startX = vehicle.getX(); startY = vehicle.getY();
        vehicle.getForwardVector(direction);
        double length = Math.hypot(direction.x, direction.z);
        if (length < .99) throw new IllegalStateException("Invalid horizontal forward vector");
        forwardX = direction.x / length; forwardY = direction.z / length;
        speed = targetKmh; stationary = stationarySeconds; approach = approachTiles; distance = measuredTiles;
        zoom = zoomFactor; minimumVisibleZombies = (int)minVisibleZombies;
        setZoom(player, zoomFactor);
        width = Core.getInstance().getScreenWidth(); height = Core.getInstance().getScreenHeight();
        framebufferWidth = Display.getFramebufferWidth(); framebufferHeight = Display.getFramebufferHeight();
        StageProfiler.start(cache, ownerThread);
        began = phaseAt = System.nanoTime();
        phase = 1;
        System.out.println(String.format(Locale.ROOT, "[DRIVING_PERF] BEGIN sql=%d x=%.4f y=%.4f fx=%.6f fy=%.6f speed=%.2f stationary=%.2f approach=%.2f distance=%.2f width=%d height=%d framebuffer=%dx%d zoom=%.3f cap=%d vsync=%s min_visible_zombies=%d throttle_mode=%s vehicle_script=%s native_script_max_speed=%.3f effective_vehicle_max_speed=%.3f engine_force=%.3f minimum_approach_kmh=%.3f actual_speed_kmh=%.3f controller=bounded-pd-heading1.8-lateral0.16-yawrate0.35-limit0.45 zombie_semantics=alive-loaded,nearby-radius50,on-screen-square,visible-player-flag-and-on-screen,active-nearby-not-useless-not-fake-dead",
                vehicle.getSqlId(), startX, startY, forwardX, forwardY, speed, stationary, approach, distance,
                Core.getInstance().getScreenWidth(), Core.getInstance().getScreenHeight(),
                Display.getFramebufferWidth(), Display.getFramebufferHeight(), Core.getInstance().getZoom(player.getPlayerNum()),
                PerformanceSettings.instance.getFramerate(), Core.getInstance().getOptionVSync(), minimumVisibleZombies,
                fullThrottle ? "full-throttle-forward-held" : "cruise", vehicleScript, vehicle.getScript().maxSpeed,
                vehicle.getMaxSpeed(), vehicle.getScript().getEngineForce(), fullThrottle ? speed : 0,
                Math.abs(vehicle.getCurrentSpeedKmHour())));
        return "stationary";
    }

    private static void fail(String reason) {
        if (phase == -1) return;
        failure = reason; phase = -1;
        if (owned != null) { owned.setRegulator(false); owned.setRegulatorSpeed(0); }
        // The runner terminates on FAIL. Flush the recording in finish() before publishing that marker.
        System.out.println("[DRIVING_PERF] STOPPING invalid_route=" + reason);
    }

    @LuaMethod(name="drivingPerfTick", global=true)
    public static String tick() {
        if (owned == null || Thread.currentThread() != ownerThread) throw new IllegalStateException("Benchmark not owned by this thread");
        if (phase == -1) return "failed";
        if (phase == 4) return "done";
        if (overflow) { fail("Timing buffer overflow"); return "failed"; }
        if (Math.abs(Core.getInstance().getZoom(actor.getPlayerNum()) - zoom) > .001f
                || Core.getInstance().getScreenWidth() != width || Core.getInstance().getScreenHeight() != height
                || Display.getFramebufferWidth() != framebufferWidth || Display.getFramebufferHeight() != framebufferHeight
                || PerformanceSettings.instance.getFramerate() != 144 || Core.getInstance().getOptionVSync()) {
            fail("Camera/viewport/frame-cap/VSync changed"); return "failed";
        }
        if (actor.isDead() || actor.getVehicle() != owned || !owned.isDriver(actor) || !owned.isEngineRunning()
                || !vehicleScript.equals(owned.getScriptName())) {
            fail("Driver/engine changed"); return "failed";
        }
        long now = System.nanoTime();
        double dx = owned.getX() - startX, dy = owned.getY() - startY;
        double progress = dx * forwardX + dy * forwardY, lateral = dx * -forwardY + dy * forwardX;
        double kmh = Math.abs(owned.getCurrentSpeedKmHour());
        maxActualSpeed = Math.max(maxActualSpeed, kmh);
        boolean colliding = owned.jniIsCollide;
        if (colliding && !collisionFlag) { contacts++; pendingContacts++; }
        collisionFlag = colliding;
        maxLateral = Math.max(maxLateral, Math.abs(lateral));
        maxHeading = Math.max(maxHeading, Math.abs(headingError));
        // Contacts are part of the explicitly populated driving workload. They are
        // generic physics contacts, not an inferred count of zombies struck.
        // Route, driver, engine and sustained speed-loss guards remain authoritative.
        if (Math.abs(lateral) > 1.5 || progress < -1 || colliding && minimumVisibleZombies == 0) {
            fail("Route deviation/collision progress=" + progress + " lateral=" + lateral + " collision=" + colliding); return "failed";
        }
        var square = owned.getSquare();
        var floor = square == null ? null : square.getFloor();
        String sprite = floor == null || floor.getSprite() == null ? null : floor.getSprite().getName();
        if (square == null || !square.isOutside() || sprite == null || !sprite.contains("street")) {
            fail("Vehicle left loaded street at " + owned.getX() + "," + owned.getY() + " sprite=" + sprite); return "failed";
        }
        if ((now - began) / 1e9 > stationary + 180) { fail("Route timeout"); return "failed"; }
        if (phase == 1 && (now - phaseAt) / 1e9 >= stationary) {
            phase = 2; phaseAt = now;
            System.out.println("[DRIVING_PERF] APPROACH");
        }
        if (phase == 2 && progress >= approach) {
            if (fullThrottle ? kmh < speed : Math.abs(kmh - speed) > Math.max(2, speed * .1)) {
                fail("Speed insufficient/unsettled at measurement gate: actual=" + kmh + " gate=" + speed
                        + " mode=" + (fullThrottle ? "full-throttle" : "cruise")); return "failed";
            }
            phaseAt = now; phase = 3;
            System.out.println(String.format(Locale.ROOT, "[DRIVING_PERF] MEASURE x=%.4f y=%.4f progress=%.4f speed=%.4f", owned.getX(), owned.getY(), progress, kmh));
        }
        // Brief streaming/simulation stalls are measurement targets: retain every frame.
        // A sustained speed deviation changes the route workload and invalidates this run.
        boolean speedDeviation = fullThrottle ? kmh < 30 : Math.abs(kmh - speed) > Math.max(4, speed * .2);
        if (phase == 3 && speedDeviation) {
            if (offSpeedAt == 0) {
                offSpeedAt = now; speedDips++;
                System.out.println(String.format(Locale.ROOT,
                        "[DRIVING_PERF] SPEED_DIP state=begin progress=%.4f speed=%.4f collision=%s loaded_square=true cause=unclassified-streaming-or-simulation",
                        progress, kmh, owned.jniIsCollide));
            } else if (now - offSpeedAt > 2_000_000_000L) {
                fail("Measured sustained " + (fullThrottle ? "crawl below 30 km/h" : "speed deviation")
                        + " for over 2 seconds: " + kmh); return "failed";
            }
        } else if (offSpeedAt != 0) {
            totalOffSpeedNs += now - offSpeedAt;
            System.out.println(String.format(Locale.ROOT,
                    "[DRIVING_PERF] SPEED_DIP state=recovered progress=%.4f speed=%.4f seconds=%.6f",
                    progress, kmh, (now-offSpeedAt)/1e9));
            offSpeedAt = 0;
        }
        if (phase == 3 && progress >= approach + distance) {
            if (minimumVisibleZombies > 0 && populatedZombieSamples < 3) {
                fail("Insufficient measured visible/active zombie samples: " + populatedZombieSamples + "/" + zombieSamples
                        + " minimum_visible=" + minimumVisibleZombies + " max_visible=" + maxVisibleZombies);
                return "failed";
            }
            phase = 4; owned.setRegulator(false); owned.setRegulatorSpeed(0);
            System.out.println(String.format(Locale.ROOT, "[DRIVING_PERF] END x=%.4f y=%.4f progress=%.4f speed=%.4f seconds=%.6f lateral=%.6f speed_dips=%d off_speed_seconds=%.6f populated_zombie_samples=%d zombie_samples=%d max_visible_zombies=%d contacts=%d max_lateral=%.6f max_heading_deg=%.6f throttle_mode=%s max_actual_speed_kmh=%.3f",
                    owned.getX(), owned.getY(), progress, kmh, (now-phaseAt)/1e9, lateral, speedDips,
                    (totalOffSpeedNs + (offSpeedAt == 0 ? 0 : now-offSpeedAt))/1e9,
                    populatedZombieSamples, zombieSamples, maxVisibleZombies, contacts, maxLateral, Math.toDegrees(maxHeading),
                    fullThrottle ? "full-throttle-forward-held" : "cruise", maxActualSpeed));
            return "done";
        }
        if (now - lastLog >= 1_000_000_000L) {
            lastLog = now;
            System.out.println(String.format(Locale.ROOT, "[DRIVING_PERF] ROUTE phase=%d elapsed=%.3f progress=%.4f lateral=%.4f speed=%.4f x=%.4f y=%.4f heading_error_deg=%.6f yaw_rate_deg_s=%.6f steering_input=%.5f contacts=%d contacts_interval=%d contact_kind=generic-physics-contact throttle_mode=%s forward_input=%s regulator=%s",
                    phase, (now-began)/1e9, progress, lateral, kmh, owned.getX(), owned.getY(),
                    Math.toDegrees(headingError), Math.toDegrees(filteredYawRate), steeringInput, contacts, pendingContacts,
                    fullThrottle ? "full-throttle-forward-held" : "cruise", owned.getController().clientControls.forward,
                    owned.isRegulator()));
            pendingContacts = 0;
            zombieCounts();
        }
        return phase == 1 ? "stationary" : phase == 2 ? "approach" : "measured";
    }

    /** Native flags/square projection, not proof of rendered pixels or compositor visibility. */
    private static void zombieCounts() {
        int loaded = 0, nearby = 0, screen = 0, visible = 0, activeNearby = 0;
        var zombies = IsoWorld.instance.getCell().getZombieList();
        int player = actor.getPlayerNum();
        for (int i=0; i<zombies.size(); i++) {
            var zombie = zombies.get(i);
            if (zombie == null || zombie.isDead()) continue;
            loaded++;
            double dx = zombie.getX()-owned.getX(), dy = zombie.getY()-owned.getY();
            if (dx*dx + dy*dy <= 2500) {
                nearby++;
                if (!zombie.isUseless() && !zombie.isFakeDead()) activeNearby++;
            }
            if (zombie.isOnScreen()) {
                screen++;
                if (player < zombie.isVisibleToPlayer.length && zombie.isVisibleToPlayer[player]) visible++;
            }
        }
        if (phase == 3) {
            zombieSamples++; maxVisibleZombies = Math.max(maxVisibleZombies, visible);
            if (visible >= minimumVisibleZombies && activeNearby > 0) populatedZombieSamples++;
        }
        System.out.println("[DRIVING_PERF] ZOMBIES phase=" + phase + " loaded_alive=" + loaded
                + " nearby_alive_radius50=" + nearby + " on_screen_square_alive=" + screen
                + " visible_player_flag_on_screen_alive=" + visible + " active_nearby_radius50=" + activeNearby);
    }

    /** Called after the native input poll; preserve normal Bullet drivetrain/cruise physics. */
    public static void controls(CarController controller) {
        if (owned == null || controller.vehicleObject != owned) return;
        if (Thread.currentThread() != ownerThread || GameClient.client || GameServer.server) {
            fail("Unexpected control thread/mode"); return;
        }
        var input = controller.clientControls;
        input.forward = false; input.backward = false; input.shift = false;
        input.brake = phase != 2 && phase != 3;
        if (!input.brake) {
            // Native RIGHT is +1 and LEFT is -1. The native wheel servo negates
            // this input before Bullet. Both our cross-track and heading errors
            // are right-positive, so a negative input steers them back to zero.
            owned.getForwardVector(direction);
            headingError = Math.atan2(forwardX*direction.z - forwardY*direction.x,
                    forwardX*direction.x + forwardY*direction.z);
            double lateral = (owned.getX()-startX)*-forwardY + (owned.getY()-startY)*forwardX;
            long now = System.nanoTime();
            double dt = lastSteerNs == 0 ? 0 : (now-lastSteerNs)/1e9;
            if (dt > 0 && dt < .5) {
                double delta = Math.atan2(Math.sin(headingError-previousHeadingError),
                        Math.cos(headingError-previousHeadingError));
                double rate = delta/dt;
                filteredYawRate += dt/(.15+dt)*(rate-filteredYawRate);
            } else filteredYawRate = 0;
            previousHeadingError = headingError; lastSteerNs = now;
            double command = -(1.8*headingError + .16*lateral + .35*filteredYawRate);
            steeringInput = Math.max(-.45, Math.min(.45, command));
            // CarController ignores |input|<=.1. Avoid a permanently ineffective
            // correction while retaining a small neutral band against chatter.
            if (Math.abs(steeringInput) <= .025) steeringInput = 0;
            else if (Math.abs(steeringInput) <= .1) steeringInput = Math.copySign(.1001, steeringInput);
            input.steering = (float)steeringInput;
            if (fullThrottle) {
                // Exactly the native keyboard-forward input. The native engine,
                // transmission, terrain and impacts determine achievable speed.
                input.forward = true;
                owned.setRegulator(false); owned.setRegulatorSpeed(0);
            } else { owned.setRegulatorSpeed((float)speed); owned.setRegulator(true); }
        } else {
            input.steering = 0; steeringInput = 0; lastSteerNs = 0; filteredYawRate = 0;
            owned.setRegulator(false); owned.setRegulatorSpeed(0);
        }
    }

    public static void swapped() {
        int p = phase;
        if (p != 1 && p != 2 && p != 3) return;
        synchronized (swapLock) {
            if (phase != p) return;
            if (swaps == CAPACITY) { overflow = true; return; }
            swapNs[swaps] = System.nanoTime(); swapPhase[swaps++] = p;
            StageProfiler.swapped(p, contacts);
        }
    }

    public static void frameStarting() {
        StageProfiler.frameBegin(phase, contacts, owned == null ? 0 : Math.abs(owned.getCurrentSpeedKmHour()));
    }

    public static void framed() {
        StageProfiler.frameEnd();
        int p = phase;
        if (p != 1 && p != 2 && p != 3) return;
        if (frames == CAPACITY) { overflow = true; return; }
        frameNs[frames] = System.nanoTime(); cpuNs[frames] = GameWindow.getUpdateTime(); framePhase[frames++] = p;
    }

    @LuaMethod(name="drivingPerfFinish", global=true)
    public static String finish() throws Exception {
        if (owned == null || Thread.currentThread() != ownerThread || phase != 4 && phase != -1 || dumped)
            throw new IllegalStateException("Benchmark is not ready for one-time output");
        dumped = true;
        try { StageProfiler.finish(); }
        catch (Exception problem) {
            failure = (failure == null ? "" : failure + "; ") + "stage profile: " + problem;
            phase = -1;
        }
        Path output = cache.resolve("driving-perf.csv");
        synchronized (swapLock) {
            try (BufferedWriter writer = Files.newBufferedWriter(output)) {
                writer.write("channel,phase,nano_time,cpu_work_ns\n");
                for (int i=0; i<swaps; i++) writer.write("swap,"+swapPhase[i]+","+swapNs[i]+",0\n");
                for (int i=0; i<frames; i++) writer.write("game,"+framePhase[i]+","+frameNs[i]+","+cpuNs[i]+"\n");
            }
        }
        if (phase == -1) {
            System.out.println("[DRIVING_PERF] FAIL " + failure);
            return "failed: " + failure;
        }
        int stationarySwaps = 0, approachSwaps = 0, measuredSwaps = 0;
        int stationaryFrames = 0, approachFrames = 0, measuredFrames = 0;
        for (int i=0; i<swaps; i++) {
            if (swapPhase[i] == 1) stationarySwaps++;
            else if (swapPhase[i] == 2) approachSwaps++;
            else if (swapPhase[i] == 3) measuredSwaps++;
        }
        for (int i=0; i<frames; i++) {
            if (framePhase[i] == 1) stationaryFrames++;
            else if (framePhase[i] == 2) approachFrames++;
            else if (framePhase[i] == 3) measuredFrames++;
        }
        if (Math.min(Math.min(stationarySwaps, measuredSwaps), Math.min(stationaryFrames, measuredFrames)) < 100 || overflow)
            throw new IllegalStateException("Missing/overflowed per-phase timing hooks");
        System.out.println("[DRIVING_PERF] COMPLETE swaps=" + swaps + " frames=" + frames
                + " stationary_swaps=" + stationarySwaps + " approach_swaps=" + approachSwaps + " measured_swaps=" + measuredSwaps
                + " stationary_frames=" + stationaryFrames + " approach_frames=" + approachFrames + " measured_frames=" + measuredFrames
                + " csv=" + output);
        return output.toString();
    }

    @Patch(className="zombie.core.physics.CarController", methodName="updateControls", strictMatch=true)
    public static class Controls {
        @Patch.OnExit public static void exit(@Patch.This CarController controller) { Main.controls(controller); }
    }
    @Patch(className="org.lwjglx.opengl.Display", methodName="swapBuffers", strictMatch=true)
    public static class Swap {
        @Patch.OnExit public static void exit() { Main.swapped(); }
    }
    @Patch(className="zombie.GameWindow", methodName="frameStep", strictMatch=true)
    public static class Frame {
        @Patch.OnEnter public static void enter() { Main.frameStarting(); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit() { Main.framed(); }
    }
}
