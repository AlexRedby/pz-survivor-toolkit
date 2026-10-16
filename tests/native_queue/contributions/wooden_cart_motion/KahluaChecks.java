import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;

public final class KahluaChecks {
    public static void main(String[] args) throws Exception {
        var platform=J2SEPlatform.getInstance();
        var environment=platform.newEnvironment();
        var thread=new KahluaThread(System.out,platform,environment);
        thread.debugOwnerThread=Thread.currentThread();
        Object[] result;
        environment.rawset("ProjectRoot",Path.of(args[0]).toAbsolutePath().toString());
        environment.rawset("dofile",(JavaFunction)(frame,count)->{
            try(var reader=Files.newBufferedReader(Path.of((String)frame.get(0)))) {
                var closure=LuaCompiler.loadis(reader,(String)frame.get(0),environment);
                return frame.push(frame.getThread().call(closure,new Object[0]));
            } catch(java.io.IOException error) {throw new RuntimeException(error);}
        });
        try(var reader=Files.newBufferedReader(Path.of(args[0],"tests/test_cart_obstacles.lua"))) {
            result=thread.pcall(LuaCompiler.loadis(reader,"test_cart_obstacles.lua",environment),new Object[0]);
            if(!Boolean.TRUE.equals(result[0])) throw new AssertionError(Arrays.toString(result));
        }
        System.out.println("KAH_LUA_CART_OBSTACLES_PASS (stock game VM, stub world, no native launch)");
    }
}
