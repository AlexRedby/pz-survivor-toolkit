package zombie.ui;

import com.sun.tools.attach.VirtualMachine;
import java.lang.instrument.Instrumentation;
import java.nio.file.Files;
import java.nio.file.Path;

/** Test-only native selection; never moves or captures the desktop pointer. */
public final class VehicleDoorRadialCapture {
    private static RadialMenu selected;
    private static int previous;

    public static void main(String[] args) throws Exception {
        VirtualMachine vm = VirtualMachine.attach(args[0]);
        try { vm.loadAgent(args[1], args[2]); }
        finally { vm.detach(); }
    }

    private static synchronized void restore() {
        if (selected == null) return;
        selected.highlight = previous;
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
        if (candidate == null || index < 0 || index >= candidate.slices.size())
            throw new IllegalStateException("The requested native radial slice is unavailable");
        previous = candidate.highlight;
        selected = candidate;
        candidate.highlight = index;
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
