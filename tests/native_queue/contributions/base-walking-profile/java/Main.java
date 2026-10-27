package toolkit.basewalking;

import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.network.GameServer;

/** Test-only observer. No movement, UI, frame-cap, focus or rendering changes. */
public final class Main {
    private static volatile int phase;
    private static volatile boolean active;
    private static Thread owner;
    private static Path cache;
    private static boolean started, finished, frameAdviceObserved, swapAdviceObserved;

    public static void main(String[] args) {
        System.out.println("[BASE_WALKING_PROFILE] LOADED inert_until_explicit_owned_client_begin=true");
    }

    private static Path gate() throws Exception {
        String expected=System.getProperty("pz.baseWalking.cachedir", "");
        if (!Boolean.getBoolean("pz.baseWalking.enabled") || expected.isBlank() || GameServer.server
                || !"MainThread".equals(Thread.currentThread().getName()))
            throw new IllegalStateException("Explicit owned client cache/MainThread required");
        Path actual=Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath();
        Path marker=actual.resolve("Lua/smoke-user.txt");
        if (!Path.of(expected).toRealPath().equals(actual) || !Files.isRegularFile(marker, LinkOption.NOFOLLOW_LINKS)
                || Files.size(marker)==0 || Files.size(marker)>1024 || !"client1".equals(Files.readString(marker).trim()))
            throw new IllegalStateException("Wrong owned test cache or marker");
        return actual;
    }

    @LuaMethod(name="baseWalkingProfileBegin", global=true)
    public static boolean begin() throws Exception {
        if (started || finished) return false;
        Path actual=gate();
        StageProfiler.start(actual, Thread.currentThread());
        owner=Thread.currentThread();cache=actual;started=true;phase=1;active=true;
        // Lua calls this during OnTick. The next frameStep entry opens the first
        // complete sample; no half-frame is created for this current callback.
        System.out.println("[BASE_WALKING_PROFILE] BEGIN next_frame=true phase=1 nano="+System.nanoTime());
        return true;
    }

    @LuaMethod(name="baseWalkingProfileFrameId", global=true)
    public static double frameId() {
        return active && Thread.currentThread()==owner ? StageProfiler.currentFrameId() : 0;
    }

    @LuaMethod(name="baseWalkingProfilePhase", global=true)
    public static boolean setPhase(int value) throws Exception {
        if (value<1 || value>3) throw new IllegalArgumentException("Expected phase 1 stationary, 2 walking or 3 post-stationary");
        if (!active || finished || Thread.currentThread()!=owner) return false;
        if (!gate().equals(cache)) throw new IllegalStateException("Owned cache changed");
        phase=value;
        // Open frame metadata remains its frame-begin snapshot.
        System.out.println("[BASE_WALKING_PROFILE] PHASE value="+value+" nano="+System.nanoTime());
        return true;
    }

    @LuaMethod(name="baseWalkingProfileFinish", global=true)
    public static String finish() throws Exception {
        if (!started || finished || Thread.currentThread()!=owner)
            throw new IllegalStateException("One finish from the owning MainThread required");
        if (!gate().equals(cache)) throw new IllegalStateException("Owned cache changed");
        active=false;finished=true;
        // OnTick sits inside frameStep: the reviewed profiler explicitly omits
        // its unfinished closing sample. Trailing stage/frame advice becomes inert.
        StageProfiler.finish();
        String output=cache.resolve("base-walking-stages.csv").toString();
        System.out.println("[BASE_WALKING_PROFILE] COMPLETE frame_hook="+frameAdviceObserved
            +" swap_hook="+swapAdviceObserved+" csv="+output+" nano="+System.nanoTime());
        return output;
    }

    public static void frameStarting() {
        if (!active || Thread.currentThread()!=owner) return;
        if (!frameAdviceObserved) {
            frameAdviceObserved=true;
            System.out.println("[BASE_WALKING_PROFILE] HOOK_ACTIVE method=GameWindow.frameStep");
        }
        StageProfiler.frameBegin(phase, 0, 0);
    }
    public static void framed() { StageProfiler.frameEnd(); }
    public static void swapped() {
        if (!active) return;
        synchronized (Main.class) {
            if (!active) return;
            if (!swapAdviceObserved) {
                swapAdviceObserved=true;
                System.out.println("[BASE_WALKING_PROFILE] HOOK_ACTIVE method=Display.swapBuffers");
            }
        }
        StageProfiler.swapped(phase, 0);
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
