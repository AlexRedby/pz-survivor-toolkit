import java.io.ByteArrayOutputStream;
import java.io.StringReader;
import java.lang.management.ManagementFactory;
import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;

/** Native game Kahlua executes exact upstream sources against explicit world doubles. */
public final class FridgeCacheCheck {
    record VM(KahluaThread thread, KahluaTable env) {
        Object call(String function, Object... args) { return thread.call(env.rawget(function), args); }
    }
    static VM load(Path source) throws Exception {
        J2SEPlatform platform = new J2SEPlatform();
        KahluaTable env = platform.newEnvironment();
        KahluaThread thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        for (String name : new String[]{"fixture.lua", "TOF_Core.lua", "TOF_Light.lua", "TOF_Client.lua"}) {
            LuaClosure code = LuaCompiler.loadis(new StringReader(Files.readString(source.resolve(name))), name, env);
            ByteArrayOutputStream bytecode = new ByteArrayOutputStream();
            code.prototype.dump(bytecode);
            Files.write(source.resolve(name + ".luac"), bytecode.toByteArray());
            thread.call(code, new Object[0]);
        }
        return new VM(thread, env);
    }
    public static void main(String[] args) throws Exception {
        Path source = Path.of(args[0]);
        VM checked = load(source);
        System.out.println("VECTOR " + checked.call("fixtureCheck"));
        if (args.length==1) return;
        int count=Integer.parseInt(args[1]), rounds=Integer.parseInt(args[2]), warmup=Integer.parseInt(args[3]);
        var bean=(com.sun.management.ThreadMXBean)ManagementFactory.getThreadMXBean();
        bean.setThreadAllocatedMemoryEnabled(true); bean.setThreadCpuTimeEnabled(true);
        long tid=Thread.currentThread().threadId();
        // Exercise all runtime branches before the first timed case, including the mixed path.
        for (String label : new String[]{"warm","cold","mixed","moving"}) {
            for (int r=0;r<warmup;r++) {
                VM vm=load(source); vm.call("fixturePrepare",label);
                vm.call("fixtureLoop",label,Double.valueOf(count));
            }
        }
        for (String label : new String[]{"warm","cold","mixed","moving"}) {
            for (int r=-warmup;r<rounds;r++) {
                VM vm=load(source); vm.call("fixturePrepare",label);
                long cpu=bean.getCurrentThreadCpuTime(), allocated=bean.getThreadAllocatedBytes(tid);
                long begin=ManagementFactory.getRuntimeMXBean().getUptime(), wall=System.nanoTime();
                Object result=vm.call("fixtureLoop",label,Double.valueOf(count));
                wall=System.nanoTime()-wall;
                long end=ManagementFactory.getRuntimeMXBean().getUptime();
                cpu=bean.getCurrentThreadCpuTime()-cpu; allocated=bean.getThreadAllocatedBytes(tid)-allocated;
                if(r>=0) {
                    System.out.printf("CONSUMED %s %d %s%n",label,r,result);
                    System.out.printf("WINDOW %s %d %d %d%n",label,r,begin,end);
                    System.out.printf("MEASURE %s %d %d %d %d %d%n",label,r,count,wall,cpu,allocated);
                }
            }
        }
    }
}
