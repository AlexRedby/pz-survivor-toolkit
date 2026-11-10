import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.util.Collections;
import java.util.Set;
import java.util.WeakHashMap;

/** Drain only the proved native Host child's otherwise unread stderr pipe. */
public final class ToolkitHostOutput {
    private static final Set<Process> attached = Collections.newSetFromMap(new WeakHashMap<>());
    private final Thread thread;
    private volatile IOException failure;

    public static ToolkitHostOutput start(Process process, ProcessHandle child, PrintStream target) {
        long owner = ProcessHandle.current().pid();
        if (process == null || child == null || target == null || process.pid() != child.pid()
                || !child.parent().map(parent -> parent.pid() == owner).orElse(false)
                || !process.toHandle().parent().map(parent -> parent.pid() == owner).orElse(false)) {
            throw new IllegalStateException("Native Host stderr process differs from the proved child/owner");
        }
        synchronized (attached) {
            if (!attached.add(process)) throw new IllegalStateException("Host stderr drain already attached");
        }
        return new ToolkitHostOutput(process.getErrorStream(), child.pid(), target);
    }

    private ToolkitHostOutput(InputStream source, long pid, PrintStream target) {
        thread = new Thread(() -> {
            try (source) {
                source.transferTo(target);
                target.flush();
                if (target.checkError()) throw new IOException("Host stderr destination failed");
            } catch (IOException error) {
                failure = error;
                target.println("\n[QUEUE_TEST] FAIL host stderr " + error);
                error.printStackTrace(target);
                target.flush();
            }
        }, "toolkit-owned-host-stderr-" + pid);
        thread.setDaemon(true);
        thread.start();
    }

    /** Call after child exit, while the owner's captured log is still open. */
    public void await(long timeoutMillis) throws IOException, InterruptedException {
        thread.join(timeoutMillis);
        if (thread.isAlive()) throw new IOException("Host stderr drain did not reach EOF");
        if (failure != null) throw new IOException("Host stderr drain failed", failure);
    }
}
