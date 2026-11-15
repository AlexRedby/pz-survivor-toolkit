import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.LuaClosure;
import se.krka.kahlua.vm.Prototype;
import zombie.Lua.LuaManager;

/** Execute the real producer/Policy contract with installed VM and closure metadata. */
public final class KahluaContractChecks {
    private static void filenames(Prototype prototype, String filename) {
        prototype.filename = filename;
        for (Prototype child : prototype.prototypes) filenames(child, filename);
    }

    private static LuaClosure compile(String source, String filename, KahluaTable environment) throws Exception {
        LuaClosure closure = LuaCompiler.loadstring(source, filename, environment);
        // Match the game's file loader; loadstring alone has no file identity.
        filenames(closure.prototype, filename.startsWith("@") ? filename.substring(1) : filename);
        return closure;
    }

    private static void execute(Path project, Path game, String variant) throws Exception {
        boolean oldPin = variant.equals("old-declaration-line");
        boolean oldEnvironment = variant.equals("old-environment-lookups");
        var platform = J2SEPlatform.getInstance();
        var environment = platform.newTable();
        environment.rawset("_G", environment);
        se.krka.kahlua.stdlib.BaseLib.register(environment);
        se.krka.kahlua.j2se.MathLib.register(platform, environment);
        se.krka.kahlua.stdlib.RandomLib.register(platform, environment);
        se.krka.kahlua.stdlib.StringLib.register(platform, environment);
        se.krka.kahlua.stdlib.CoroutineLib.register(platform, environment);
        se.krka.kahlua.stdlib.OsLib.register(platform, environment);
        se.krka.kahlua.stdlib.TableLib.register(platform, environment);
        LuaCompiler.register(environment);
        var thread = new KahluaThread(System.out, platform, environment);
        thread.debugOwnerThread = Thread.currentThread();
        try (var stream = Files.newInputStream(game.resolve("stdlib.lbc"))) {
            thread.call(Prototype.loadByteCode(stream, environment), new Object[0]);
        }
        if (environment.rawget("next") != null) throw new AssertionError("Expected stock Kahlua without next");
        environment.rawset("ProjectRoot", project.toString());
        environment.rawset("NativeActionRoot", game.resolve("media/lua").toString());
        environment.rawset("NativeKahluaTableLookup", true);
        environment.rawset("FitnessTestNativeEquipmentOnly", true);
        if (!variant.isEmpty() && !oldPin && !oldEnvironment) environment.rawset(variant, true);
        environment.rawset("NativeReadText", (JavaFunction)(frame, count) -> {
            try { return frame.push(Files.readString(Path.of((String)frame.get(0)))); }
            catch (Exception error) { throw new RuntimeException(error); }
        });
        environment.rawset("NativeFileExists", (JavaFunction)(frame, count) ->
            frame.push(Files.isRegularFile(Path.of((String)frame.get(0)))));
        environment.rawset("NativeMetatableMatches", (JavaFunction)(frame, count) ->
            frame.push(frame.get(0) instanceof KahluaTable table && table.getMetatable() == frame.get(1)));
        environment.rawset("NativeFirstLineOfClosure", (JavaFunction)(frame, count) ->
            frame.push((double)LuaManager.GlobalObject.getFirstLineOfClosure((LuaClosure)frame.get(0))));
        environment.rawset("NativeFilenameOfClosure", (JavaFunction)(frame, count) ->
            frame.push(LuaManager.GlobalObject.getFilenameOfClosure((LuaClosure)frame.get(0))));
        environment.rawset("loadfile", (JavaFunction)(frame, count) -> {
            try {
                String filename = (String)frame.get(0);
                String source = Files.readString(Path.of(filename));
                if (oldPin && filename.endsWith("/ActionQueuePolicy.lua")) {
                    String marker = "local fitnessEquipment={line=633,";
                    if (!source.contains(marker)) throw new AssertionError("Review the old-line causal control after a role change");
                    source = source.replace(marker, "local fitnessEquipment={line=632,");
                }
                if (oldEnvironment && filename.endsWith("/ActionQueueFitness.lua")) {
                    for (String[] lookup : new String[][]{
                            {"equipmentProof.kind(action)", "type(action)"},
                            {"equipmentProof.kind(mode.token)", "type(mode.token)"},
                            {"equipmentProof.queues[record.saved.player]", "ISTimedActionQueue.queues[record.saved.player]"},
                            {"equipmentProof.actor(record.saved.player:getPlayerNum())", "getSpecificPlayer(record.saved.player:getPlayerNum())"}}) {
                        if (!source.contains(lookup[0])) throw new AssertionError("Review the old-environment causal control after a producer change");
                        source = source.replace(lookup[0], lookup[1]);
                    }
                }
                return frame.push(compile(source, filename, environment));
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        environment.rawset("loadstring", (JavaFunction)(frame, count) -> {
            try {
                return frame.push(compile((String)frame.get(0), count > 1 ? (String)frame.get(1) : "fixture", environment));
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        environment.rawset("dofile", (JavaFunction)(frame, count) -> {
            try {
                String filename = (String)frame.get(0);
                return frame.push(frame.getThread().call(compile(Files.readString(Path.of(filename)), filename, environment), new Object[0]));
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        Path fixture = project.resolve("tests/test_action_queue_fitness.lua");
        Object[] result = thread.pcall(compile(Files.readString(fixture), fixture.toString(), environment), new Object[0]);
        if (oldPin) {
            if (Boolean.TRUE.equals(result[0]) || !Arrays.toString(result).contains("verified Fitness equipment lost its complete native operation contract"))
                throw new AssertionError("Old declaration-line pin did not reproduce the genuine contract refusal: " + Arrays.toString(result));
            System.out.println("FITNESS_STOCK_KAHLUA_CONTRACT_PASS old-declaration-line-rejected");
            return;
        }
        if (oldEnvironment) {
            if (Boolean.TRUE.equals(result[0]) || !Arrays.toString(result).contains("unproved equipment acquired complete-operation cancellation"))
                throw new AssertionError("Old environment reads did not reproduce the stale-queue permission: " + Arrays.toString(result));
            System.out.println("FITNESS_STOCK_KAHLUA_CONTRACT_PASS old-environment-lookups-rejected");
            return;
        }
        if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(variant + ": " + Arrays.toString(result));
        System.out.println("FITNESS_STOCK_KAHLUA_CONTRACT_PASS " + (variant.isEmpty() ? "verified-producer" : variant));
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("project-root game-java-root");
        Path project = Path.of(args[0]).toAbsolutePath(), game = Path.of(args[1]).toAbsolutePath();
        for (String variant : new String[]{"", "FitnessTestEquipmentSourceChanged", "FitnessTestEquipmentRoleChanged", "FitnessTestEquipmentOwnerChanged", "old-declaration-line", "old-environment-lookups"})
            execute(project, game, variant);
    }
}
