package toolkit.basewalking;

import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.io.BufferedWriter;
import me.zed_0xff.zombie_buddy.Patch;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.network.GameServer;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;

/** Test-only observer. No movement, UI, frame-cap, focus or rendering changes. */
public final class Main {
    private static volatile int phase;
    private static volatile boolean active;
    private static Thread owner;
    private static long clockOrigin;
    private static Path cache;
    private static boolean started, finished, frameAdviceObserved, swapAdviceObserved;
    private static final ItemContainer[] floorScopes=new ItemContainer[64];
    private static int floorDepth;
    private static boolean floorObserved;
    private static final long[][] floorCalls=new long[3][3], floorNs=new long[3][3], floorMaxNs=new long[3][3];

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
        owner=Thread.currentThread();cache=actual;clockOrigin=System.nanoTime();started=true;phase=1;active=true;
        // Lua calls this during OnTick. The next frameStep entry opens the first
        // complete sample; no half-frame is created for this current callback.
        System.out.println("[BASE_WALKING_PROFILE] BEGIN next_frame=true phase=1 nano="+System.nanoTime());
        return true;
    }

    @LuaMethod(name="baseWalkingProfileFrameId", global=true)
    public static double frameId() {
        return active && Thread.currentThread()==owner ? StageProfiler.currentFrameId() : 0;
    }

    @LuaMethod(name="baseWalkingProfileClockMs", global=true)
    public static double clockMs() {
        // Begin already verified the owned cache/marker. No filesystem probes in a timed callback.
        if (!active || finished || Thread.currentThread()!=owner || !Boolean.getBoolean("pz.baseWalking.enabled"))
            throw new IllegalStateException("Active owned MainThread profile required");
        return (System.nanoTime()-clockOrigin)/1_000_000.0;
    }

    @LuaMethod(name="baseWalkingInventoryScope", global=true)
    public static void inventoryScope(boolean entering, ItemContainer floor) {
        clockMs(); // Same explicit active owned-client/MainThread guard.
        if (entering) {
            if (floor==null || !"floor".equals(floor.getType()) || floorDepth==floorScopes.length)
                throw new IllegalStateException("Expected bounded floor observation scope");
            floorScopes[floorDepth++]=floor;floorObserved=true;
        } else {
            if (floorDepth==0) throw new IllegalStateException("Unbalanced floor observation scope");
            floorScopes[--floorDepth]=null;
        }
    }

    public static long floorEnter(ItemContainer container) {
        return active && Thread.currentThread()==owner && floorDepth>0
            && container==floorScopes[floorDepth-1] ? System.nanoTime() : 0;
    }
    public static void floorExit(int method, long start) {
        if (start==0) return;
        long elapsed=System.nanoTime()-start;
        int index=phase-1;
        floorCalls[index][method]++;floorNs[index][method]+=elapsed;
        floorMaxNs[index][method]=Math.max(floorMaxNs[index][method],elapsed);
    }
    private static void writeFloorProfile() throws Exception {
        if (!floorObserved) return;
        try (BufferedWriter out=Files.newBufferedWriter(cache.resolve("base-walking-inventory-floor.csv"))) {
            out.write("phase,method,calls,inclusive_ns,max_inclusive_ns\n");
            String[] methods={"AddItem(InventoryItem)","clear()","removeItemsFromProcessItems()"};
            for (int p=0;p<3;p++) for (int method=0;method<3;method++)
                out.write((p+1)+","+methods[method]+","+floorCalls[p][method]+","+floorNs[p][method]+","+floorMaxNs[p][method]+"\n");
        }
        System.out.println("[BASE_WALKING_PROFILE] INVENTORY_FLOOR csv="+cache.resolve("base-walking-inventory-floor.csv")
            +" unclosed_scopes="+floorDepth);
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
        writeFloorProfile();
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

    // B42 signatures are validated by the observer adapter's ItemContainer hash.
    @Patch(className="zombie.inventory.ItemContainer", methodName="AddItem", strictMatch=true)
    public static class FloorAddItem {
        @Patch.OnEnter public static void enter(@Patch.This ItemContainer container, @Patch.Argument(0) InventoryItem item,
                @Patch.Local("baseWalkingFloorStart") long start) { start=Main.floorEnter(container); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingFloorStart") long start) { Main.floorExit(0,start); }
    }
    @Patch(className="zombie.inventory.ItemContainer", methodName="clear", strictMatch=true)
    public static class FloorClear {
        @Patch.OnEnter public static void enter(@Patch.This ItemContainer container,
                @Patch.Local("baseWalkingFloorStart") long start) { start=Main.floorEnter(container); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingFloorStart") long start) { Main.floorExit(1,start); }
    }
    @Patch(className="zombie.inventory.ItemContainer", methodName="removeItemsFromProcessItems", strictMatch=true)
    public static class FloorRemoveProcessItems {
        @Patch.OnEnter public static void enter(@Patch.This ItemContainer container,
                @Patch.Local("baseWalkingFloorStart") long start) { start=Main.floorEnter(container); }
        @Patch.OnExit(onThrowable=Throwable.class) public static void exit(@Patch.Local("baseWalkingFloorStart") long start) { Main.floorExit(2,start); }
    }
}
