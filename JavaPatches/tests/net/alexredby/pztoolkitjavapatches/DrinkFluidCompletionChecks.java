package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.LuaClosure;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.Prototype;

/** Executes the same source-based Lua regressions with the game's table semantics. */
public final class DrinkFluidCompletionChecks {
    static void filename(Prototype prototype, String path) {
        prototype.filename = path;
        for (var child : prototype.prototypes) filename(child, path);
    }
    static LuaClosure compile(String text, String path, KahluaTable environment) throws Exception {
        var closure = LuaCompiler.loadstring(text, path, environment);
        filename(closure.prototype, path);
        return closure;
    }
    public static void main(String[] args) throws Exception {
        var root = Path.of(System.getProperty("pz.test.project"));
        var platform = new J2SEPlatform();
        var environment = platform.newEnvironment();
        var thread = new KahluaThread(platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        environment.rawset("ProjectRoot", root.toString());
        environment.rawset("NativeActionRoot", Path.of("media/lua").toAbsolutePath().toString());
        environment.rawset("NativeReadText", (JavaFunction)(frame, count) -> {
            try { frame.push(Files.readString(Path.of((String)frame.get(0)))); return 1; }
            catch (Exception error) { throw new RuntimeException(error); }
        });
        environment.rawset("NativeFilenameOfClosure", (JavaFunction)(frame, count) -> {
            frame.push(frame.get(0) instanceof LuaClosure closure ? closure.prototype.filename : null);
            return 1;
        });
        environment.rawset("loadstring", (JavaFunction)(frame, count) -> {
            try { frame.push(compile((String)frame.get(0), count > 1 ? (String)frame.get(1) : "=(loadstring)", environment)); return 1; }
            catch (Exception error) { throw new RuntimeException(error); }
        });
        environment.rawset("loadfile", (JavaFunction)(frame, count) -> {
            try {
                var path = (String)frame.get(0);
                frame.push(compile(Files.readString(Path.of(path)), path, environment));
                return 1;
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        var path = root.resolve("tests/test_drink_fluid_boundary.lua");
        thread.call(compile(Files.readString(path), path.toString(), environment), new Object[]{});
        if (!Boolean.TRUE.equals(environment.rawget("TestDrinkFluidBoundaryPassed"))) {
            throw new AssertionError("Drink boundary vectors did not reach their completion marker");
        }
        System.out.println("DRINK_FLUID_COMPLETION_CHECKS_PASS (shared boundary vectors in native Kahlua)");
        System.exit(0);
    }
}
