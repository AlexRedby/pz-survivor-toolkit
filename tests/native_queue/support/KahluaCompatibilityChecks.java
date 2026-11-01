import java.io.Reader;
import java.lang.classfile.AnnotationValue;
import java.lang.classfile.ClassFile;
import java.lang.classfile.attribute.RuntimeVisibleAnnotationsAttribute;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.regex.Pattern;
import org.luaj.kahluafork.compiler.FuncState;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.vm.Prototype;

/** Compile project sources without executing them; probe only the installed standard library. */
public final class KahluaCompatibilityChecks {
    // Only standard Lua 5.1 global names belong here. Game/module names are unrestricted.
    private static final List<String> STANDARD_GLOBALS = Arrays.asList(
        "_G", "_VERSION", "assert", "collectgarbage", "dofile", "error", "gcinfo",
        "getfenv", "getmetatable", "ipairs", "load", "loadfile", "loadstring", "module",
        "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "require",
        "select", "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack",
        "xpcall", "coroutine", "debug", "io", "math", "os", "package", "string", "table");

    private static KahluaTable standardEnvironment(Path library) throws Exception {
        var platform = J2SEPlatform.getInstance();
        // newEnvironment() expects cwd/stdlib.lua, absent in installed B42 packages.
        var env = platform.newTable();
        env.rawset("_G", env);
        // Availability marker for the version string set by J2SEPlatform.setupEnvironment.
        env.rawset("_VERSION", "Kahlua");
        se.krka.kahlua.stdlib.BaseLib.register(env);
        se.krka.kahlua.j2se.MathLib.register(platform, env);
        se.krka.kahlua.stdlib.RandomLib.register(platform, env);
        se.krka.kahlua.stdlib.StringLib.register(platform, env);
        se.krka.kahlua.stdlib.CoroutineLib.register(platform, env);
        se.krka.kahlua.stdlib.OsLib.register(platform, env);
        se.krka.kahlua.stdlib.TableLib.register(platform, env);
        LuaCompiler.register(env);
        var thread = new KahluaThread(System.out, platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        try (var stream = Files.newInputStream(library)) {
            thread.call(Prototype.loadByteCode(stream, env), new Object[0]);
        }
        return env;
    }

    private static TreeSet<String> gameStandardGlobals() throws Exception {
        var names = new TreeSet<String>();
        // Read annotations only: loading GlobalObject would pull in game/native initialization.
        try (var stream = KahluaCompatibilityChecks.class.getClassLoader().getResourceAsStream(
                "zombie/Lua/LuaManager$GlobalObject.class")) {
            if (stream == null) throw new IllegalStateException("Installed game GlobalObject class is absent");
            for (var method : ClassFile.of().parse(stream.readAllBytes()).methods()) {
                for (var attribute : method.attributes()) {
                    if (!(attribute instanceof RuntimeVisibleAnnotationsAttribute annotations)) continue;
                    for (var annotation : annotations.annotations()) {
                        if (!annotation.className().stringValue().equals(
                                "Lse/krka/kahlua/integration/annotations/LuaMethod;")) continue;
                        boolean global = false;
                        String name = method.methodName().stringValue();
                        for (var element : annotation.elements()) {
                            if (element.value() instanceof AnnotationValue.OfConstant constant) {
                                if (element.name().stringValue().equals("global"))
                                    global = Boolean.TRUE.equals(constant.resolvedValue());
                                if (element.name().stringValue().equals("name"))
                                    name = constant.resolvedValue().toString();
                            }
                        }
                        if (global && STANDARD_GLOBALS.contains(name)) names.add(name);
                    }
                }
            }
        }
        return names;
    }

    private static void inspect(Prototype prototype, String function, TreeSet<String> missing,
                                List<Object> functions, List<Object> diagnostics) {
        int firstLine = 0, lastLine = 0;
        if (prototype.lines != null) for (int line : prototype.lines) {
            if (line > 0 && (firstLine == 0 || line < firstLine)) firstLine = line;
            lastLine = Math.max(lastLine, line);
        }
        functions.add(Map.of("function", function, "line", firstLine, "last_line", lastLine,
                             "upvalues", prototype.numUpvalues, "stack", prototype.maxStacksize));
        for (int pc = 0; pc < prototype.code.length; pc++) {
            int instruction = prototype.code[pc];
            int opcode = FuncState.GET_OPCODE(instruction);
            if (opcode == FuncState.OP_GETGLOBAL) {
                Object name = prototype.constants[FuncState.GETARG_Bx(instruction)];
                if (name instanceof String && missing.contains(name)) {
                    int line = prototype.lines != null && pc < prototype.lines.length ? prototype.lines[pc] : 0;
                    diagnostics.add(Map.of("kind", "missing_standard_global", "global", name,
                        "function", function, "line", line,
                        "message", "Lua standard global '" + name + "' is absent from installed Kahlua"));
                }
            }
            // SETLIST with C=0 stores a raw array-block number in the next instruction word.
            if (opcode == FuncState.OP_SETLIST && FuncState.GETARG_C(instruction) == 0) pc++;
        }
        if (prototype.prototypes != null) for (int i = 0; i < prototype.prototypes.length; i++) {
            inspect(prototype.prototypes[i], function + "/" + (i + 1), missing, functions, diagnostics);
        }
    }

    private static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Number || value instanceof Boolean) return value.toString();
        if (value instanceof Map<?, ?> map) {
            var parts = new ArrayList<String>();
            map.forEach((key, item) -> parts.add(json(key.toString()) + ":" + json(item)));
            return "{" + String.join(",", parts) + "}";
        }
        if (value instanceof Iterable<?> items) {
            var parts = new ArrayList<String>();
            items.forEach(item -> parts.add(json(item)));
            return "[" + String.join(",", parts) + "]";
        }
        var result = new StringBuilder("\"");
        for (char c : value.toString().toCharArray()) {
            if (c == '"' || c == '\\') result.append('\\').append(c);
            else if (c < 32) result.append(String.format("\\u%04x", (int)c));
            else result.append(c);
        }
        return result.append('"').toString();
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) throw new IllegalArgumentException("report.json stdlib.lbc sources.txt");
        var paths = Files.readAllLines(Path.of(args[2]), StandardCharsets.UTF_8);
        if (paths.isEmpty() || paths.stream().anyMatch(String::isEmpty))
            throw new IllegalArgumentException("Source manifest must contain one nonempty path per line");
        var environment = standardEnvironment(Path.of(args[1]));
        var gameProvided = gameStandardGlobals();
        var missing = new TreeSet<String>();
        var present = new TreeSet<String>();
        for (String name : STANDARD_GLOBALS) {
            if (environment.rawget(name) == null && !gameProvided.contains(name)) missing.add(name);
            else present.add(name);
        }
        var sources = new ArrayList<Object>();
        boolean failed = false;
        LuaCompiler.rewriteEvents = false;
        for (String sourcePath : paths) {
            var path = Path.of(sourcePath);
            var functions = new ArrayList<Object>();
            var diagnostics = new ArrayList<Object>();
            String previous = FuncState.currentFile, previousFull = FuncState.currentfullFile;
            try (Reader reader = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
                FuncState.currentFile = path.getFileName().toString();
                FuncState.currentfullFile = path.toString();
                inspect(LuaCompiler.loadis(reader, path.toString(), null).prototype,
                        "chunk", missing, functions, diagnostics);
            } catch (Exception | AssertionError problem) {
                String message = String.valueOf(problem.getMessage());
                var matcher = Pattern.compile(":(\\d+):").matcher(message);
                int line = matcher.find() ? Integer.parseInt(matcher.group(1)) : 0;
                diagnostics.add(Map.of("kind", "compile_error", "line", line, "function", "compiler",
                                      "message", problem.getClass().getSimpleName() + ": " + message));
            } finally {
                FuncState.currentFile = previous;
                FuncState.currentfullFile = previousFull;
            }
            failed |= !diagnostics.isEmpty();
            var source = new LinkedHashMap<String, Object>();
            source.put("path", path.toString());
            source.put("status", diagnostics.isEmpty() ? "passed" : "failed");
            source.put("functions", functions);
            source.put("diagnostics", diagnostics);
            sources.add(source);
        }
        var report = new LinkedHashMap<String, Object>();
        report.put("schema", 1);
        report.put("status", failed ? "failed" : "passed");
        report.put("present_standard_globals", present);
        report.put("game_supplied_standard_globals", gameProvided);
        report.put("missing_standard_globals", missing);
        report.put("sources", sources);
        Files.writeString(Path.of(args[0]), json(report) + "\n", StandardCharsets.UTF_8);
        if (failed) System.exit(1);
    }
}
