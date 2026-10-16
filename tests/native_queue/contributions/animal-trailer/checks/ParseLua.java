import java.nio.file.Files;
import java.nio.file.Path;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

/** Compile fixture Lua without executing it or starting the game. */
public final class ParseLua {
    public static void main(String[] paths) throws Exception {
        for (String path : paths) {
            try (var input = Files.newBufferedReader(Path.of(path))) {
                LuaCompiler.loadis(input, Path.of(path).getFileName().toString(), null);
            }
        }
        System.out.println("LUA_SYNTAX_PASS files=" + paths.length);
    }
}
