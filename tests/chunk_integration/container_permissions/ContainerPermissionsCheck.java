import java.io.StringReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.lang.management.ManagementFactory;
import com.sun.management.ThreadMXBean;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;

/** Executes external selected Lua using the game's actual Kahlua implementation; no GUI. */
public final class ContainerPermissionsCheck {
    static KahluaThread thread;
    static KahluaTable env;
    static Object execute(String text, String name) throws Exception {
        return thread.call(LuaCompiler.loadis(new StringReader(text), name, env), null, null, null);
    }
    public static void main(String[] args) throws Exception {
        J2SEPlatform platform = J2SEPlatform.getInstance();
        env = platform.newTable(); platform.setupEnvironment(env);
        thread = new KahluaThread(platform, env); thread.debugOwnerThread = Thread.currentThread();
        env.rawset("StockPermissions", execute(Files.readString(Path.of(args[0])), "stock-Permissions.lua"));
        env.rawset("Permissions", execute(Files.readString(Path.of(args[1])), "Permissions.lua"));
        env.rawset("InventoryPageSource", Files.readString(Path.of(args[3])));
        env.rawset("AutoLockSource", Files.readString(Path.of(args[4])));
        execute(Files.readString(Path.of(args[2])), "checks.lua");
        System.out.println("CONTAINER_PERMISSIONS_CHECK_PASS");
        if (args.length < 6) return;
        int iterations = Integer.parseInt(args[5]);
        Object loop = execute("return function(n) local sum = 0; for i=1,n do sum = sum + workload(i) end; return sum end", "benchmark.lua");
        ThreadMXBean bean = (ThreadMXBean)ManagementFactory.getThreadMXBean();
        long tid = Thread.currentThread().threadId();
        for (String workload : new String[]{"single", "four-consumer"}) {
            execute("workload = workloads['" + workload + "']", "select-workload.lua");
            for (int warm = 0; warm < 6; warm++) thread.call(loop, (double)iterations, null, null);
            Object consumed = null;
            for (int round = 0; round < 5; round++) {
                long alloc = bean.getThreadAllocatedBytes(tid), cpu = bean.getCurrentThreadCpuTime(), wall = System.nanoTime();
                consumed = thread.call(loop, (double)iterations, null, null);
                wall = System.nanoTime() - wall; cpu = bean.getCurrentThreadCpuTime() - cpu; alloc = bean.getThreadAllocatedBytes(tid) - alloc;
                System.out.printf("RESULT %s %d %d %d %d %d%n", workload, round, iterations, wall, cpu, alloc);
            }
            System.out.println("CONSUMED " + workload + " " + consumed);
        }
    }
}
