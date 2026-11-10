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
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicInteger;
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

/** Actual native Kahlua compilation and callbacks; no game or mod files are rewritten. */
public final class NativeIgnitionSourceChecks {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static Field field(Class<?> owner, String name) throws Exception {
        Field value = owner.getDeclaredField(name); value.setAccessible(true); return value;
    }
    private static Object scope() throws Exception {
        return ((ThreadLocal<?>) field(NativeIgnitionSource.class, "LOADING").get(null)).get();
    }
    private static String basename(String target) { return target.substring(target.lastIndexOf('/') + 1); }
    private static String text(Reader reader) throws IOException {
        StringBuilder result = new StringBuilder(); char[] buffer = new char[8192];
        for (int count; (count = reader.read(buffer)) >= 0;) result.append(buffer, 0, count);
        return result.toString();
    }
    private static byte[] compiled(String source, String name) throws IOException {
        LuaClosure closure = LuaCompiler.loadis(new StringReader(source), name, LuaManager.env);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream(); closure.prototype.dump(bytes); return bytes.toByteArray();
    }
    private static Object lua(String source) throws IOException {
        return LuaManager.thread.call(LuaCompiler.loadstring(source, "native-ignition-differential", LuaManager.env), new Object[0]);
    }
    private static final String SETUP = """
        local calls={}
        local function record(value) calls[#calls+1]=value end
        require=function() end
        ISBaseTimedAction={derive=function(self,name)
            local class={Type=name};class.__index=class;return setmetatable(class,{__index=self})
        end,perform=function() record('base-perform');if mode=='base-error' then error('base failure',0) end end}
        isServer=function() return true end
        IsoObjectChange={STATE='state'}
        sendRemoveItemFromContainer=function() record('send-remove') end
        local rolls=0
        ZombRand=function() rolls=rolls+1;return rolls==1 and 1 or 0 end
        local container={setDrawDirty=function(self,dirty)
            record('dirty:'..tostring(dirty));if mode=='dirty-error' then error('dirty failure',0) end
        end}
        local item={container=container,
            getContainer=function(self)
                if mode=='getter-error' then error('getter failure',0) end
                return self.container
            end,
            setJobDelta=function(self,delta)
                record('item-job:'..tostring(delta));if mode=='job-error' then error('job failure',0) end
            end}
        local inventory={Remove=function(self,value) record('remove');value.container=nil end}
        local character={getInventory=function() return inventory end,
            stopOrTriggerSound=function() record('stop-sound') end,
            removeFromHands=function() record('remove-hands') end,
            getEmitter=function() return {isPlaying=function() return true end,
                stopOrTriggerSoundByName=function() record('stop-kindle-sound') end} end}
        local target={fuel=0,lit=false,
            addFuel=function(self,value) record('fuel:'..tostring(value));self.fuel=self.fuel+value end,
            lightFire=function(self) record('light');self.lit=true end,
            hasFuel=function(self) return self.fuel>0 end,
            isLit=function(self) return self.lit end,
            turnOn=function(self) record('turn-on');self.lit=true end,
            sendObjectChange=function() record('send-state') end}
        SCampfireSystem={instance={getLuaObjectAt=function() return target end}}
        local plank={setJobDelta=function(self,delta) record('plank-job:'..tostring(delta)) end}
        local lighter={UseAndSync=function() record('lighter-use') end}
        """;
    private static String run(String source, String className, String mode) throws IOException {
        String tail = """
            local action=setmetatable({character=character,item=item,plank=plank,lighter=lighter,
                campfire={x=1,y=2,z=0},bbq=target,sound=7,fuelAmt=5,
                netAction={getProgress=function() return .5 end,
                    forceComplete=function() record('force-complete') end}},CLASS)
            if mode=='nil-item' then action.item=nil end
            local ok,problem=pcall(function()
                if mode=='consumed' then
                    if KINDLE then action:animEvent('CheckLit',nil) else assert(action:complete()==true) end
                end
                action:perform()
                if mode=='ordinary' then assert(action:complete()==true) end
            end)
            return (ok and 'ok' or tostring(problem))..'|'..table.concat(calls,',')
            """.replace("CLASS", className).replace("KINDLE", className.endsWith("Kindle") ? "true" : "false");
        return (String) lua("local mode='" + mode + "'\n" + SETUP + source + "\n" + tail);
    }
    private static void differential(String target, String original, String fixed) throws IOException {
        String className = basename(target).replace(".lua", "");
        String statement = original.lines().filter(line -> line.contains("self.item:getContainer():setDrawDirty(true)")).findFirst().orElseThrow();
        String indent = statement.substring(0, statement.indexOf("self"));
        String changed = indent + "local container = self.item:getContainer()" + (original.contains("\r\n") ? "\r\n" : "\n") + indent + "if container then container:setDrawDirty(true) end";
        require(original.replace(statement, changed).equals(fixed), "unrelated native source changed: " + target);
        require(run(original, className, "ordinary").equals(run(fixed, className, "ordinary")), "ordinary callback effects differ: " + target);
        String failure = run(original, className, "consumed");
        String completed = run(fixed, className, "consumed");
        require(failure.contains("setDrawDirty") && !failure.startsWith("ok|"), "original did not expose consumed container failure: " + failure);
        require(completed.startsWith("ok|") && completed.contains("base-perform"), "patched native completion lost queue advancement: " + completed);
        require(completed.contains("remove") && completed.contains("send-remove"), "authoritative native consumption disappeared: " + completed);
        if (className.endsWith("Kindle")) {
            require(completed.contains("force-complete") && completed.contains("plank-job:0"), "native broken-stick callback effects lost");
            require(run(original, className, "nil-item").equals(run(fixed, className, "nil-item")), "native optional Kindle item branch changed");
        } else {
            require(completed.contains("lighter-use") && completed.contains("fuel:5")
                && completed.contains("item-job:0"), "literature authoritative effects lost: " + completed);
            require(!run(fixed, className, "nil-item").startsWith("ok|"), "nil native item error was swallowed");
        }
        for (String mode : new String[]{"getter-error", "dirty-error", "job-error", "base-error"}) {
            String before = run(original, className, mode), after = run(fixed, className, mode);
            require(!after.startsWith("ok|") && before.equals(after), "unrelated native error/effects changed: " + mode + ": " + before + " / " + after);
        }
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        ZomboidFileSystem files = ZomboidFileSystem.instance;
        files.setCacheDir(System.getProperty("pz.test.cache")); files.init();
        require(NativeIgnitionSource.SUPPORTED, "unsupported native loader/compiler/filesystem bytes");
        LuaManager.platform = new J2SEPlatform(); LuaManager.env = LuaManager.platform.newEnvironment();
        LuaManager.thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new LuaCaller(new KahluaConverterManager());
        Reader bomb = new Reader() {
            @Override public int read(char[] b, int o, int n) { throw new AssertionError("foreign Reader consumed"); }
            @Override public void close() { throw new AssertionError("borrowed Reader closed"); }
        };
        require(NativeIgnitionSource.compilerInput(bomb, "ISBBQLightFromLiterature.lua", true) == bomb, "unscoped compiler changed");
        require(NativeIgnitionSource.transformSource("unknown", "return 1") == "return 1", "unknown target changed");
        require(NativeIgnitionSource.transformSource(NativeIgnitionSource.BBQ_KINDLE, null) == null, "null source changed");
        for (String target : NativeIgnitionSource.TARGETS) {
            Path nativeFile = files.getMediaRootFile().toPath().resolve(target.substring("media/".length())).toAbsolutePath();
            byte[] bytes = Files.readAllBytes(nativeFile); String original = Files.readString(nativeFile);
            String fixed = NativeIgnitionSource.transformSource(target, original), name = basename(target), key = target.toLowerCase(Locale.ROOT);
            require(fixed != original, "installed native source differs from reviewed digest: " + target);
            require(NativeIgnitionSource.transformSource(target, fixed) == fixed, "already patched source changed");
            String changed = original + "\n";
            require(NativeIgnitionSource.transformSource(target, changed) == changed, "unknown source hash accepted");
            for (String other : NativeIgnitionSource.TARGETS) if (!other.equals(target))
                require(NativeIgnitionSource.transformSource(other, original) == original, "source crossed target scope");
            files.activeFileMap.put(key, nativeFile.toString());
            var previous = NativeIgnitionSource.begin(target, false);
            try { require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "unsupported loader consumed input"); }
            finally { NativeIgnitionSource.end(previous); }
            Path override = Path.of(System.getProperty("pz.test.cache"), "mods/Override").resolve(target);
            Files.createDirectories(override.getParent()); Files.writeString(override, original);
            files.activeFileMap.put(key, override.toString());
            for (String request : new String[]{target, nativeFile.toString(), override.toString()}) {
                previous = NativeIgnitionSource.begin(request, true);
                try { require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "mod provider claimed native input: " + request); }
                finally { NativeIgnitionSource.end(previous); }
            }
            files.activeFileMap.put(key, nativeFile.toString());
            previous = NativeIgnitionSource.begin(target, true);
            try {
                files.activeFileMap.put(key, override.toString());
                require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "stale native scope consumed override Reader");
                files.activeFileMap.put(key, nativeFile.toString());
                require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "rejected provider scope was reusable");
            } finally { files.activeFileMap.put(key, nativeFile.toString()); NativeIgnitionSource.end(previous); }
            Boolean previousIgnore = files.ignoreActiveFileMap.get();
            previous = NativeIgnitionSource.begin(target, true);
            try {
                files.ignoreActiveFileMap.set(true);
                require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "changed ignore mode consumed Reader");
            } finally { files.ignoreActiveFileMap.set(previousIgnore); NativeIgnitionSource.end(previous); }
            files.ignoreActiveFileMap.set(true);
            previous = NativeIgnitionSource.begin(target, true);
            try { require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "ignored active provider consumed Reader"); }
            finally { files.ignoreActiveFileMap.set(previousIgnore); NativeIgnitionSource.end(previous); }
            previous = NativeIgnitionSource.begin(override.toString(), true);
            try { require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "foreign absolute request accepted"); }
            finally { NativeIgnitionSource.end(previous); }
            previous = NativeIgnitionSource.begin(target, true);
            try {
                require(NativeIgnitionSource.compilerInput(bomb, "/foreign/" + name, true) == bomb, "foreign compiler label consumed");
                require(NativeIgnitionSource.compilerInput(bomb, name, false) == bomb, "unsupported compiler consumed");
                require(text(NativeIgnitionSource.compilerInput(new StringReader(changed), name, true)).equals(changed), "unknown source replay changed");
                require(NativeIgnitionSource.compilerInput(bomb, name, true) == bomb, "scope claimed twice");
            } finally { NativeIgnitionSource.end(previous); }
            differential(target, original, fixed);
            require(Arrays.equals(bytes, Files.readAllBytes(nativeFile)), "physical native source modified");
        }
        // Use actual RunLua + woven compiler advice. A native module's require
        // observes the compiler's claimed scope before any callback semantics run.
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", NativeIgnitionSourceChecks.class.getClassLoader());
        Path inner = Path.of(System.getProperty("pz.test.cache"), "inner.lua");
        Files.writeString(inner, "return ignitionInnerProbe()\n"); files.activeFileMap.put("ignition-inner.lua", inner.toString());
        AtomicReference<Throwable> probeFailure = new AtomicReference<>();
        AtomicInteger probes = new AtomicInteger();
        LuaManager.env.rawset("ignitionInnerProbe", (JavaFunction) (frame, count) -> {
            try {
                require(scope() != null && field(NativeIgnitionSource.Scope.class, "target").get(scope()) == null, "nested unrelated load inherited native scope");
                frame.push(19.0); return 1;
            } catch (Throwable failure) { probeFailure.set(failure); throw new RuntimeException(failure); }
        });
        LuaManager.env.rawset("ignitionScopeProbe", (JavaFunction) (frame, count) -> {
            try {
                Object active = scope();
                probes.incrementAndGet();
                require(active != null && field(NativeIgnitionSource.Scope.class, "target").get(active) != null
                    && field(NativeIgnitionSource.Scope.class, "claimed").getBoolean(active), "woven native Reader scope not claimed");
                LuaManager.loaded.remove("ignition-inner.lua");
                require(Double.valueOf(19).equals(LuaManager.RunLua("ignition-inner.lua", false)), "nested RunLua failed");
                require(scope() == active, "nested RunLua lost parent scope");
                try { LuaManager.RunLua(null, false); } catch (NullPointerException expected) { }
                require(scope() == active, "throwing nested RunLua lost parent scope");
                return 0;
            } catch (Throwable failure) { probeFailure.set(failure); throw new RuntimeException(failure); }
        });
        lua("require=function() ignitionScopeProbe() end");
        for (String target : NativeIgnitionSource.TARGETS) {
            String original = Files.readString(Path.of(target)), fixed = NativeIgnitionSource.transformSource(target, original), name = basename(target);
            byte[] expected = compiled(fixed, name), ordinary = compiled(original, name);
            require(!Arrays.equals(expected, ordinary), "transformation did not alter prototype");
            var previous = NativeIgnitionSource.begin(target, true);
            try { require(Arrays.equals(compiled(original, name), expected), "woven Reader argument not replaced"); }
            finally { NativeIgnitionSource.end(previous); }
            require(Arrays.equals(compiled(original, name), ordinary), "unscoped input changed");
            int beforeProbes = probes.get();
            LuaManager.loaded.remove(target); LuaManager.RunLua(target, false);
            require(probes.get() == beforeProbes + 1, "native RunLua did not execute scoped require");
            require(probeFailure.get() == null, "woven native load scope failed: " + probeFailure.get());
            require(scope() == null, "RunLua leaked native scope");
            LuaManager.RunLua(target, false);
            require(probes.get() == beforeProbes + 1 && scope() == null, "cached RunLua executed again or leaked scope");
        }
        require(scope() == null, "compiler scope leaked");
        System.out.println("NATIVE_IGNITION_SOURCE_CHECKS_PASS (native provider/hash gates, scoped compiler advice, unchanged callbacks and consumed-container differential)");
    }
}
