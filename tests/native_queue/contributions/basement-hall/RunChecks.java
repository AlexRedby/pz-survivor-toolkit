import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;

/** Execute fixture protocol checks in Kahlua without initializing the game. */
public final class RunChecks {
    public static void main(String[] args) throws Exception {
        var platform = J2SEPlatform.getInstance();
        for (String selectedCase : new String[] {"fresh", "reload", "native-control"}) {
            var environment = platform.newEnvironment();
            environment.rawset("fixtureSource", Files.readString(Path.of(args[0])));
            environment.rawset("fixtureCase", selectedCase);
            try (var input = Files.newBufferedReader(Path.of(args[1]))) {
                var chunk = LuaCompiler.loadis(input, args[1], environment);
                var thread = new KahluaThread(platform, environment);
                thread.debugOwnerThread = Thread.currentThread();
                var result = thread.pcall(chunk, new Object[0]);
                if (result.length == 0 || !Boolean.TRUE.equals(result[0]))
                    throw new AssertionError(java.util.Arrays.toString(result));
            }
        }
        System.out.println("BASEMENT_HALL_PROTOCOL_PASS");
    }
}
