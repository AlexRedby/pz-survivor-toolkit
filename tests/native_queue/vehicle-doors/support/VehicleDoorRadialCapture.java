package net.alexredby.nativechecks;

import zombie.ui.*;
import java.lang.reflect.Field;
import java.util.List;

import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.nio.file.Files;
import java.nio.file.Path;

/** Test-only native selection; never moves or captures the desktop pointer. */
public final class VehicleDoorRadialCapture {
    private static RadialMenu selected;
    private static int previous;
    private static final Field HIGHLIGHT = field("highlight");
    private static final Field SLICES = field("slices");

    private static Field field(String name) {
        try {
            Field field = RadialMenu.class.getDeclaredField(name);
            field.setAccessible(true);
            return field;
        } catch (ReflectiveOperationException failure) {
            throw new ExceptionInInitializerError(failure);
        }
    }

    private static int highlight(RadialMenu menu) {
        try { return HIGHLIGHT.getInt(menu); }
        catch (IllegalAccessException failure) { throw new IllegalStateException(failure); }
    }

    private static void highlight(RadialMenu menu, int value) {
        try { HIGHLIGHT.setInt(menu, value); }
        catch (IllegalAccessException failure) { throw new IllegalStateException(failure); }
    }

    private static int sliceCount(RadialMenu menu) {
        try { return ((List<?>)SLICES.get(menu)).size(); }
        catch (IllegalAccessException failure) { throw new IllegalStateException(failure); }
    }

    public static void main(String[] args) throws Exception {
        VirtualMachine vm = VirtualMachine.attach(args[0]);
        try { vm.loadAgent(args[1], args[2]); }
        finally { vm.detach(); }
    }

    private static synchronized void restore() {
        if (selected == null) return;
        highlight(selected, previous);
        selected = null;
        System.out.println("[VEHICLE_DOORS] RADIAL_SELECTION_RESTORED");
    }

    public static synchronized void agentmain(String argument, Instrumentation ignored) throws Exception {
        if (argument.equals("stop")) { restore(); return; }
        if (selected != null) throw new IllegalStateException("A radial capture is already selected");
        Path cache = Path.of(argument).toAbsolutePath().normalize();
        int index = Integer.parseInt(Files.readString(cache.resolve("Lua/vehicle-doors-radial-index.txt")).trim()) - 1;
        RadialMenu candidate = null;
        for (UIElementInterface element : UIManager.getUI().toArray(UIElementInterface[]::new)) {
            if (element instanceof RadialMenu menu && menu.isReallyVisible()) {
                if (candidate != null) throw new IllegalStateException("Multiple visible native radials");
                candidate = menu;
            }
        }
        if (candidate == null || index < 0 || index >= sliceCount(candidate))
            throw new IllegalStateException("The requested native radial slice is unavailable");
        previous = highlight(candidate);
        selected = candidate;
        highlight(candidate, index);
        System.out.println("[VEHICLE_DOORS] RADIAL_SELECTION index=" + (index + 1));
        Thread cleanup = new Thread(() -> {
            try {
                long deadline = System.nanoTime() + 15_000_000_000L;
                while (!Files.exists(cache.resolve("Lua/vehicle-doors-radial-restore.txt")) && System.nanoTime() < deadline)
                    Thread.sleep(25);
            } catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
            finally { restore(); }
        }, "vehicle-door-radial-capture");
        cleanup.setDaemon(true);
        cleanup.start();
    }
}
