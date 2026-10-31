package net.alexredby.pztoolkitjavapatches;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.Reader;
import java.io.StringReader;
import java.lang.reflect.Field;
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

    private static byte[] compiled(String source, String name) throws IOException {
        return dump(LuaCompiler.loadis(new StringReader(source), name, LuaManager.env));
    }

    private static String basename(String target) { return target.substring(target.lastIndexOf('/') + 1); }

    private static String collapsedBlock(String source) {
        int start = source.indexOf("            if count == 1 and self.collapsed ~= nil and v.name ~= nil and self.collapsed[v.name] then\n");
        int end = source.indexOf("            if count == CleanUI_Vanilla_ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER + 1 then\n", start);
        require(start >= 0 && end > start, "reviewed vanilla collapsed block boundary changed");
        return source.substring(start, end);
    }

    private static Object lua(String source) throws IOException {
        return LuaManager.thread.call(LuaCompiler.loadstring(source, "food-age-dispatch-check", LuaManager.env), new Object[0]);
    }

    private static void dispatchChecks(String original, String fixed) throws IOException {
        String before = collapsedBlock(original), after = collapsedBlock(fixed);
        require(original.replace(before, after).equals(fixed), "vanilla transform changed unrelated renderer side effects");
        String setup = "local Calls=0; local item={updateAge=function() Calls=Calls+1 end}; "
            + "local v={name='food',items={item,item,item}}; local self={collapsed={food=true}}; "
            + "local count=1; local function instanceof() return true end; ";
        String dispatch = " for pass=1,1 do " + after + " end; return Calls";
        for (String namespace : new String[] {"nil", "function() error('foreign global') end", "{}",
                "{protocol=2,enhancedSourceSha256='" + CleanUIFoodAge.INPUT_SHA256 + "',updateCollapsedStack=function() error('protocol') end}",
                "{protocol=1,enhancedSourceSha256='unknown',updateCollapsedStack=function() error('source') end}",
                "{protocol=1,enhancedSourceSha256='" + CleanUIFoodAge.INPUT_SHA256 + "',updateCollapsedStack=false}"}) {
            require(Double.valueOf(3).equals(lua(setup + "CleanUI_ToolkitFoodAge=" + namespace + ";" + dispatch)),
                "unknown/absent updater did not retain original vanilla duplicate-header loop: " + namespace);
        }
        require(Double.valueOf(10).equals(lua(setup + "CleanUI_ToolkitFoodAge={protocol=1,enhancedSourceSha256='"
            + CleanUIFoodAge.INPUT_SHA256 + "',updateCollapsedStack=function(group,admitted) "
            + "if group~=v or admitted~=true then error('vanilla admission changed') end; Calls=Calls+10 end};" + dispatch)),
            "reviewed public updater did not receive exact group and conservative admission");
        LuaManager.env.rawset("CleanUI_ToolkitFoodAge", null);
    }

    private static byte[] dump(LuaClosure closure) throws IOException {
        ByteArrayOutputStream result = new ByteArrayOutputStream();
        closure.prototype.dump(result);
        return result.toByteArray();
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
        Path vanillaPane = version.resolve(CleanUIFoodAge.VANILLA_TARGET);
        Files.createDirectories(pane.getParent());
        Files.createDirectories(vanillaPane.getParent());
        Files.createDirectories(root.resolve("common"));
        Files.writeString(root.resolve("common/mod.info"), "id=CleanUI\n");
        Files.writeString(version.resolve("mod.info"), "id=CleanUI\nmodversion=fixture\n");
        Files.writeString(pane, "return verifyScope()\n");
        Files.writeString(vanillaPane, "return verifyScope()\n");
        files.setModIdToDir("CleanUI", root.toString());
        require(Path.of(ChooseGameInfo.getModDetails("CleanUI").getVersionDir()).equals(version), "native active version not selected");
        files.getModIDs().add("CleanUI");
        files.activeFileMap.put(CleanUIFoodAge.TARGET.toLowerCase(Locale.ROOT), pane.toString());
        files.activeFileMap.put(CleanUIFoodAge.VANILLA_TARGET.toLowerCase(Locale.ROOT), vanillaPane.toString());
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
        for (String target : new String[] {CleanUIFoodAge.TARGET, CleanUIFoodAge.VANILLA_TARGET}) {
            String name = basename(target);
            require(CleanUIFoodAge.transformSource(target, unknown) == unknown, "unknown target input changed");
            var parent = CleanUIFoodAge.begin(target, true);
            try {
                require(target.equals(field(CleanUIFoodAge.Scope.class, "target").get(scope())), "candidate target identity lost");
                String other = target.equals(CleanUIFoodAge.TARGET) ? basename(CleanUIFoodAge.VANILLA_TARGET) : basename(CleanUIFoodAge.TARGET);
                require(CleanUIFoodAge.compilerInput(bomb, other, true) == bomb, "other target compiler claimed scope");
                require(text(CleanUIFoodAge.compilerInput(new StringReader(unknown), name, true)).equals(unknown), "target replay failed");
                require(CleanUIFoodAge.compilerInput(bomb, name, true) == bomb, "target scope claimed twice");
            } finally { CleanUIFoodAge.end(parent); }
        }
        files.activeFileMap.put(CleanUIFoodAge.VANILLA_TARGET.toLowerCase(Locale.ROOT), pane.toString());
        var wrongVanillaProvider = CleanUIFoodAge.begin(CleanUIFoodAge.VANILLA_TARGET, true);
        try {
            require(CleanUIFoodAge.compilerInput(bomb, basename(CleanUIFoodAge.VANILLA_TARGET), true) == bomb,
                "vanilla foreign provider consumed source");
        } finally { CleanUIFoodAge.end(wrongVanillaProvider); }
        files.activeFileMap.put(CleanUIFoodAge.VANILLA_TARGET.toLowerCase(Locale.ROOT), vanillaPane.toString());
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
                CleanUIFoodAge.compilerInput(broken, "ISInventoryPane.lua", true);
                throw new AssertionError("read failure swallowed after consuming source");
            } catch (IOException observed) { require(observed == failure, "read failure replaced"); }
        } finally { CleanUIFoodAge.end(previous); }

        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", CleanUIFoodAgeChecks.class.getClassLoader());
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
        for (String target : new String[] {CleanUIFoodAge.TARGET, CleanUIFoodAge.VANILLA_TARGET}) {
            require(Double.valueOf(71).equals(LuaManager.RunLua(target, false)), "woven native RunLua fixture failed: " + target);
            require(scope() == null, "native RunLua leaked thread scope");
            require(Double.valueOf(71).equals(LuaManager.RunLua(target, false)), "cached RunLua result changed: " + target);
            require(scope() == null, "cached RunLua leaked scope");
        }

        String external = System.getenv("PZ_CLEANUI_SOURCE");
        if (external != null && !external.isBlank()) {
            Path externalRoot = Path.of(external);
            String enhancedOriginal = Files.readString(externalRoot.resolve("42.19").resolve(CleanUIFoodAge.TARGET));
            String enhancedFixed = CleanUIFoodAge.transformSource(enhancedOriginal);
            require(enhancedFixed.contains("updateCollapsedStack = CleanUI_updateCollapsedFoodStackAge,"), "export is not the exact enhanced helper");
            for (String target : new String[] {CleanUIFoodAge.TARGET, CleanUIFoodAge.VANILLA_TARGET}) {
                Path externalPane = externalRoot.resolve("42.19").resolve(target);
                Path localPane = version.resolve(target);
                String name = basename(target);
                String original = Files.readString(externalPane);
                String fixed = CleanUIFoodAge.transformSource(target, original);
                String otherTarget = target.equals(CleanUIFoodAge.TARGET) ? CleanUIFoodAge.VANILLA_TARGET : CleanUIFoodAge.TARGET;
                require(fixed != original, "external CleanUI source differs from reviewed input: " + target);
                require(CleanUIFoodAge.transformSource(otherTarget, original) == original, "source crossed target scope");
                require(CleanUIFoodAge.transformSource("unknown", original) == original, "unknown target transformed source");
                require(CleanUIFoodAge.transformSource(target, fixed) == fixed, "already-corrected input changed");
                String modified = original + "\n";
                require(CleanUIFoodAge.transformSource(target, modified) == modified, "modified source accepted");
                byte[] originalCode = compiled(original, name);
                byte[] expectedCode = compiled(fixed, name);
                require(!Arrays.equals(originalCode, expectedCode), "correction did not alter compiled prototype");
                Files.writeString(localPane, original);
                previous = CleanUIFoodAge.begin(target, true);
                try {
                    LuaClosure actual = LuaCompiler.loadis(new StringReader(original), name, LuaManager.env);
                    require(Arrays.equals(dump(actual), expectedCode), "woven compiler did not write back corrected Reader argument");
                } finally { CleanUIFoodAge.end(previous); }
                previous = CleanUIFoodAge.begin(otherTarget, true);
                try {
                    require(text(CleanUIFoodAge.compilerInput(new StringReader(original), basename(otherTarget), true)).equals(original),
                        "reviewed source transformed under other target identity");
                } finally { CleanUIFoodAge.end(previous); }
                require(Arrays.equals(compiled(original, name), originalCode), "compiler transformed input outside native load scope");
                require(Files.readString(externalPane).equals(original), "Workshop source changed");
                if (target.equals(CleanUIFoodAge.VANILLA_TARGET)) dispatchChecks(original, fixed);
            }
            System.out.println("CLEANUI_FOOD_AGE_REVIEWED_SOURCE_PASS (woven Reader prototype, unscoped unchanged, Workshop unchanged)");
        } else System.out.println("CLEANUI_FOOD_AGE_REVIEWED_SOURCE_SKIP (set PZ_CLEANUI_SOURCE for installed reviewed-source prototype check)");
        System.out.println("CLEANUI_FOOD_AGE_CHECKS_PASS (native RunLua and Reader hooks, nested/cached/throwing scope cleanup, unknown/oversized replay, read failure)");
    }
}
