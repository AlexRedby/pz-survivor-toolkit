package net.alexredby.pztoolkitjavapatches;

import java.io.ByteArrayOutputStream;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.io.IOException;
import java.io.Reader;
import java.io.StringReader;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Locale;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.LuaClosure;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;
import zombie.ZomboidFileSystem;
import zombie.gameStates.ChooseGameInfo;

public final class CleanUIFoodAgeChecks {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static Field field(Class<?> type, String name) throws Exception {
        Field field = type.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    private static Object scope() throws Exception {
        return ((ThreadLocal<?>) field(CleanUIFoodAge.class, "LOADING").get(null)).get();
    }

    private static String text(Reader reader) throws IOException {
        StringBuilder result = new StringBuilder();
        char[] buffer = new char[8192];
        for (int count; (count = reader.read(buffer)) >= 0;) result.append(buffer, 0, count);
        return result.toString();
    }

    private static byte[] compiled(String source) throws IOException {
        return dump(LuaCompiler.loadis(new StringReader(source), "ISInventoryPane.lua", LuaManager.env));
    }

    private static byte[] dump(LuaClosure closure) throws IOException {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        closure.prototype.dump(result);
        return result.toByteArray();
    }

    private static final class DelayedFailureStream extends InputStream {
        private final String source;
        private boolean failed;
        private int position;
        private int closes;
        private DelayedFailureStream(String source) { this.source = source; }
        private void failIfReached() throws IOException {
            if (position >= 8192 && !failed) {
                failed = true;
                throw new IOException("delayed fixture IO");
            }
        }
        @Override public int read() throws IOException {
            failIfReached();
            return position == source.length() ? -1 : source.charAt(position++);
        }
        @Override public int read(byte[] buffer, int offset, int length) throws IOException {
            if (length == 0) return 0;
            failIfReached();
            if (position == source.length()) return -1;
            int count = Math.min(length, Math.min(source.length() - position,
                failed ? Integer.MAX_VALUE : 8192 - position));
            for (int index = 0; index < count; index++) buffer[offset + index] = (byte) source.charAt(position++);
            return count;
        }
        @Override public void close() { closes++; }
    }

    private record CompilerObservation(LuaClosure closure, Throwable failure, boolean ioDiagnostic) { }

    private static CompilerObservation observeReaderFailure(String source, boolean scoped) throws Exception {
        DelayedFailureStream stream = new DelayedFailureStream(source);
        ByteArrayOutputStream diagnostics = new ByteArrayOutputStream();
        PrintStream previousError = System.err;
        LuaClosure closure = null;
        Throwable failure = null;
        System.setErr(new PrintStream(diagnostics, true, StandardCharsets.UTF_8));
        try (Reader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.US_ASCII))) {
            CleanUIFoodAge.Scope previous = scoped ? CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, true) : null;
            try { closure = LuaCompiler.loadis(reader, "ISInventoryPane.lua", LuaManager.env); }
            finally { if (scoped) CleanUIFoodAge.end(previous); }
        } catch (IOException | RuntimeException observed) {
            failure = observed;
        } finally { System.setErr(previousError); }
        require(stream.closes == 1 && scope() == null, "error-order original Reader close/TLS cleanup");
        return new CompilerObservation(closure, failure,
            diagnostics.toString(StandardCharsets.UTF_8).contains("java.io.IOException: delayed fixture IO"));
    }

    private static void readerErrorOrderChecks() throws Exception {
        for (String prefix : new String[]{"return ]", "return 1"}) {
            String source = prefix + " ".repeat(20000) + "\n";
            CompilerObservation ordinary = observeReaderFailure(source, false);
            CompilerObservation owned = observeReaderFailure(source, true);
            require((ordinary.failure == null) == (owned.failure == null), "capture changed native syntax/IO outcome");
            if (ordinary.failure != null) {
                require(ordinary.failure.getClass() == owned.failure.getClass()
                    && java.util.Objects.equals(ordinary.failure.getMessage(), owned.failure.getMessage()),
                    "capture changed native syntax/IO failure order");
            }
            require((ordinary.closure == null) == (owned.closure == null)
                && ordinary.ioDiagnostic == owned.ioDiagnostic, "capture changed native IO reachability");
            if (prefix.equals("return ]")) {
                require(ordinary.failure instanceof se.krka.kahlua.vm.KahluaException && !ordinary.ioDiagnostic,
                    "malformed prefix did not fail before delayed IO");
            } else {
                // The native lexer logs reached IOException and treats it as EOF.
                require(ordinary.closure != null && ordinary.ioDiagnostic, "native valid-prefix IO-as-EOF not reached");
                require(Arrays.equals(dump(ordinary.closure), dump(owned.closure)),
                    "capture changed the native valid-prefix prototype after IO");
            }
        }
        System.out.println("CLEANUI_READER_ERROR_ORDER_PASS (woven native syntax-before-IO and reachable IO-as-EOF parity)");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        ZomboidFileSystem files = ZomboidFileSystem.instance;
        files.setCacheDir(System.getProperty("pz.test.cache"));
        files.init();
        Path root = Path.of(System.getProperty("pz.test.cache"), "mods/CleanUI");
        Path version = root.resolve("42");
        Path pane = version.resolve(CleanUIFoodAge.TARGET);
        Files.createDirectories(pane.getParent());
        Files.createDirectories(root.resolve("common"));
        Files.writeString(root.resolve("common/mod.info"), "id=CleanUI\n");
        Files.writeString(version.resolve("mod.info"), "id=CleanUI\nmodversion=fixture\n");
        Files.writeString(pane, "return verifyScope()\n");
        files.setModIdToDir("CleanUI", root.toString());
        require(Path.of(ChooseGameInfo.getModDetails("CleanUI").getVersionDir()).equals(version), "native active version not selected");
        files.getModIDs().add("CleanUI");
        files.activeFileMap.put(CleanUIFoodAge.TARGET.toLowerCase(Locale.ROOT), pane.toString());
        require(CleanUIFoodAge.SUPPORTED, "unsupported installed loader/compiler bytecode");
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newEnvironment();
        LuaManager.thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new LuaCaller(new KahluaConverterManager());

        String unknown = "return 'unknown source'\n";
        require(CleanUIFoodAge.transformSource(unknown) == unknown, "unknown source changed");
        require(CleanUIFoodAge.transformSource(null) == null, "null source changed");
        Reader bomb = new Reader() {
            @Override public int read(char[] b, int o, int n) { throw new AssertionError("noncandidate reader consumed"); }
            @Override public void close() { throw new AssertionError("borrowed reader closed"); }
        };
        require(CleanUIFoodAge.compilerInput(bomb, "ISInventoryPane.lua", true) == bomb, "unscoped reader changed");
        var unsupported = CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, false);
        try {
            require(CleanUIFoodAge.compilerInput(bomb, "ISInventoryPane.lua", true) == bomb, "unsupported native loader consumed source");
        } finally { CleanUIFoodAge.end(unsupported); }
        files.getModIDs().remove("CleanUI");
        var inactive = CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, true);
        try {
            require(CleanUIFoodAge.compilerInput(bomb, "ISInventoryPane.lua", true) == bomb, "inactive CleanUI consumed source");
        } finally {
            CleanUIFoodAge.end(inactive);
            files.getModIDs().add("CleanUI");
        }
        Path foreign = root.resolve("OtherInventoryPane.lua");
        Files.writeString(foreign, "return 0\n");
        files.activeFileMap.put(CleanUIFoodAge.TARGET.toLowerCase(Locale.ROOT), foreign.toString());
        var overridden = CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, true);
        try {
            require(CleanUIFoodAge.compilerInput(bomb, "ISInventoryPane.lua", true) == bomb, "foreign active provider consumed source");
        } finally {
            CleanUIFoodAge.end(overridden);
            files.activeFileMap.put(CleanUIFoodAge.TARGET.toLowerCase(Locale.ROOT), pane.toString());
        }
        var previous = CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, true);
        try {
            require(CleanUIFoodAge.compilerInput(bomb, "Other.lua", true) == bomb, "unrelated compiler name consumed");
            require(CleanUIFoodAge.compilerInput(bomb, "ISInventoryPane.lua", false) == bomb, "unsupported compiler consumed");
            require(text(CleanUIFoodAge.compilerInput(new StringReader(unknown), "ISInventoryPane.lua", true)).equals(unknown), "unknown source lost its consumed prefix");
            require(CleanUIFoodAge.compilerInput(bomb, "ISInventoryPane.lua", true) == bomb, "same load claimed twice");
        } finally { CleanUIFoodAge.end(previous); }

        String oversized = "x".repeat(1024 * 1024 + 13);
        previous = CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, true);
        try {
            require(text(CleanUIFoodAge.compilerInput(new StringReader(oversized), "ISInventoryPane.lua", true)).equals(oversized), "oversized source lost prefix/tail");
        } finally { CleanUIFoodAge.end(previous); }
        previous = CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, true);
        IOException failure = new IOException("fixture read failure");
        try {
            Reader broken = new Reader() {
                @Override public int read(char[] b, int o, int n) throws IOException { throw failure; }
                @Override public void close() { throw new AssertionError("reader closed before native owner"); }
            };
            try {
                Reader prepared = CleanUIFoodAge.compilerInput(broken, "ISInventoryPane.lua", true);
                require(prepared.read(new char[0], 0, 0) == 0, "zero-length replay consumed read failure");
                prepared.read();
                throw new AssertionError("read failure swallowed after consuming replay");
            } catch (IOException observed) { require(observed == failure, "read failure replaced"); }
        } finally { CleanUIFoodAge.end(previous); }

        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", CleanUIFoodAgeChecks.class.getClassLoader());
        readerErrorOrderChecks();
        Path inner = version.resolve("media/lua/client/inner.lua");
        Files.writeString(inner, "return innerProbe()\n");
        files.activeFileMap.put("media/lua/client/inner.lua", inner.toString());
        LuaManager.env.rawset("innerProbe", (JavaFunction) (frame, count) -> {
            try {
                require(scope() != null && !field(CleanUIFoodAge.Scope.class, "candidate").getBoolean(scope()), "unrelated nested load inherited candidate scope");
                frame.push(19.0);
                return 1;
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        LuaManager.env.rawset("verifyScope", (JavaFunction) (frame, count) -> {
            try {
                Object active = scope();
                require(active != null && field(CleanUIFoodAge.Scope.class, "candidate").getBoolean(active), "woven RunLua did not verify selected mod input");
                require(field(CleanUIFoodAge.Scope.class, "claimed").getBoolean(active), "woven Reader compiler advice did not claim the input");
                require(Double.valueOf(19).equals(LuaManager.RunLua("media/lua/client/inner.lua", false)), "nested RunLua failed");
                require(scope() == active, "nested load did not restore its parent scope");
                try { LuaManager.RunLua(null, false); } catch (NullPointerException expected) { }
                require(scope() == active, "throwing nested load did not restore its parent scope");
                require(CleanUIFoodAge.compilerInput(bomb, "ISInventoryPane.lua", true) == bomb, "dynamic compiler reused consumed load scope");
                frame.push(71.0);
                return 1;
            } catch (Exception error) { throw new RuntimeException(error); }
        });
        require(Double.valueOf(71).equals(LuaManager.RunLua(CleanUIFoodAge.TARGET, false)), "woven native RunLua fixture failed");
        require(scope() == null, "native RunLua leaked thread scope");
        require(Double.valueOf(71).equals(LuaManager.RunLua(CleanUIFoodAge.TARGET, false)), "cached RunLua result changed");
        require(scope() == null, "cached RunLua leaked scope");

        String external = System.getenv("PZ_CLEANUI_SOURCE");
        if (external != null && !external.isBlank()) {
            Path externalRoot = Path.of(external);
            Path externalPane = externalRoot.resolve("42.19").resolve(CleanUIFoodAge.TARGET);
            String original = Files.readString(externalPane);
            String fixed = CleanUIFoodAge.transformSource(original);
            require(fixed != original, "external CleanUI source differs from reviewed input");
            require(CleanUIFoodAge.transformSource(fixed) == fixed, "already-corrected input changed");
            byte[] originalCode = compiled(original);
            byte[] expectedCode = compiled(fixed);
            require(!Arrays.equals(originalCode, expectedCode), "correction did not alter compiled prototype");
            Files.writeString(pane, original);
            previous = CleanUIFoodAge.begin(CleanUIFoodAge.TARGET, true);
            try {
                LuaClosure actual = LuaCompiler.loadis(new StringReader(original), "ISInventoryPane.lua", LuaManager.env);
                require(Arrays.equals(dump(actual), expectedCode), "woven compiler did not write back corrected Reader argument");
            } finally { CleanUIFoodAge.end(previous); }
            require(Arrays.equals(compiled(original), originalCode), "compiler transformed input outside native load scope");
            require(Files.readString(externalPane).equals(original), "Workshop source changed");
            System.out.println("CLEANUI_FOOD_AGE_REVIEWED_SOURCE_PASS (woven Reader prototype, unscoped unchanged, Workshop unchanged)");
        } else System.out.println("CLEANUI_FOOD_AGE_REVIEWED_SOURCE_SKIP (set PZ_CLEANUI_SOURCE for installed reviewed-source prototype check)");
        System.out.println("CLEANUI_FOOD_AGE_CHECKS_PASS (native RunLua and Reader hooks, nested/cached/throwing scope cleanup, unknown/oversized replay, read failure)");
    }
}
