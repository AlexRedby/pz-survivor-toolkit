import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.Prototype;

/** Compile with the installed game's compiler; never execute or initialize the game. */
public final class KahluaCompileCheck {
    private static int count;
    private static int maxUpvalues;
    private static int maxStack;
    private static void inspect(Prototype prototype) {
        count++;
        maxUpvalues = Math.max(maxUpvalues, prototype.numUpvalues);
        maxStack = Math.max(maxStack, prototype.maxStacksize);
        if (prototype.prototypes != null) {
            for (Prototype child : prototype.prototypes) inspect(child);
        }
    }
    public static void main(String[] paths) throws Exception {
        if (paths.length == 0) throw new IllegalArgumentException("Pass Lua source paths");
        LuaCompiler.rewriteEvents = false;
        boolean failed = false;
        for (String value : paths) {
            Path path = Path.of(value);
            byte[] bytes = Files.readAllBytes(path);
            String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
            try (Reader reader = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
                count = maxUpvalues = maxStack = 0;
                inspect(LuaCompiler.loadis(reader, path.toString(), null).prototype);
                System.out.printf("PASS %s sha256=%s functions=%d maxUpvalues=%d maxStack=%d%n",
                        path, hash, count, maxUpvalues, maxStack);
            } catch (Exception problem) {
                failed = true;
                System.err.printf("FAIL %s sha256=%s %s: %s%n", path, hash,
                        problem.getClass().getName(), problem.getMessage());
            }
        }
        if (failed) System.exit(1);
    }
}
