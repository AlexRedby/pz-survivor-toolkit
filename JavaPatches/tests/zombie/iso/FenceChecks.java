package zombie.iso;

import java.io.*;
import java.lang.reflect.Field;
import java.lang.instrument.Instrumentation;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.bytebuddy.jar.asm.*;
import net.alexredby.pztoolkitjavapatches.FenceValidation;
import se.krka.kahlua.j2se.KahluaTableImpl;
import zombie.core.TilePropertyAliasMap;
import zombie.Lua.Event;
import zombie.Lua.LuaEventManager;
import zombie.Lua.LuaManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;
import zombie.debug.*;
import zombie.iso.sprite.IsoSpriteManager;

public final class FenceChecks {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static KahluaTableImpl table() { return new KahluaTableImpl(new LinkedHashMap<>()); }
    static String line(DataInputStream input) throws IOException {
        var bytes = new ByteArrayOutputStream();
        for (int c; (c = input.read()) != 10;) { if (c < 0) throw new EOFException(); bytes.write(c); }
        return bytes.toString(StandardCharsets.UTF_8).trim();
    }
    static int number(DataInputStream input) throws IOException { return Integer.reverseBytes(input.readInt()); }

    static Map<String, Map<String, String>> tileProperties() throws IOException {
        var result = new HashMap<String, Map<String, String>>();
        for (String file : new String[]{"newtiledefinitions.tiles", "tiledefinitions_noiseworks.patch.tiles"}) {
            try (var input = new DataInputStream(new BufferedInputStream(Files.newInputStream(Path.of("media", file))))) {
                require(new String(input.readNBytes(4), StandardCharsets.US_ASCII).equals("tdef"), "tile magic");
                require(number(input) == 1, "tile version");
                int sets = number(input);
                for (int s = 0; s < sets; s++) {
                    String set = line(input); line(input); number(input); number(input); number(input);
                    int tiles = number(input);
                    for (int t = 0; t < tiles; t++) {
                        var properties = result.computeIfAbsent(set + "_" + t, key -> new HashMap<>());
                        int count = number(input);
                        for (int p = 0; p < count; p++) {
                            String name = line(input), value = line(input);
                            if (name.equals("ThumpSound") || name.equals("FenceTypeLow")) properties.put(name, value);
                        }
                    }
                }
                require(input.read() == -1, "unparsed tile data");
            }
        }
        return result;
    }

    static KahluaTableImpl[] nativeTables() throws IOException {
        var result = new KahluaTableImpl[]{table(), table()};
        String source = Files.readString(Path.of("media/lua/server/Items/BrokenFences.lua"));
        Pattern row = Pattern.compile("^(tiles|debris)\\[\"([^\"]+)\"\\] = \\{(.*)\\}.*$", Pattern.MULTILINE);
        Pattern field = Pattern.compile("(self|left|right|north|south|west|east) = \\{([^}]+)\\}");
        Pattern value = Pattern.compile("\"([^\"]+)\"");
        var rows = row.matcher(source);
        while (rows.find()) {
            var entry = table(); var fields = field.matcher(rows.group(3));
            while (fields.find()) {
                var values = table(); var names = value.matcher(fields.group(2)); int i = 0;
                while (names.find()) values.rawset(++i, names.group(1));
                entry.rawset(fields.group(1), values);
            }
            result[rows.group(1).equals("tiles") ? 0 : 1].rawset(rows.group(2), entry);
        }
        require(result[0].size() == 42 && result[1].size() > 0, "native fence table coverage changed");
        return result;
    }

    static List<Map<?, ?>> snapshot(BrokenFences fences) throws Exception {
        var result = new ArrayList<Map<?, ?>>();
        for (String name : new String[]{"unbrokenMap", "brokenLeftMap", "brokenRightMap", "allMap"}) {
            Field field = BrokenFences.class.getDeclaredField(name); field.setAccessible(true);
            result.add(new HashMap<>((Map<?, ?>)field.get(fences)));
        }
        return result;
    }
    static Map<String, List<?>> contents(List<Map<?, ?>> maps) throws Exception {
        var result = new TreeMap<String, List<?>>();
        for (int i = 0; i < maps.size(); i++) for (var entry : maps.get(i).entrySet()) {
            var values = new ArrayList<Object>();
            for (String name : new String[]{"self", "left", "right", "debrisN", "debrisS", "debrisW", "debrisE"}) {
                Field field = entry.getValue().getClass().getDeclaredField(name); field.setAccessible(true);
                Object value = field.get(entry.getValue()); values.add(value == null ? null : new ArrayList<>((List<?>)value));
            }
            result.put(i + ":" + entry.getKey(), values);
        }
        return result;
    }
    static void register(BrokenFences fences, String name) {
        var row = table(); var entries = table(); entries.rawset(name, row); fences.addBrokenTiles(entries);
    }

    static void eventDispatch(BrokenFences fences, ByteArrayOutputStream log, String sound) throws Exception {
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", FenceChecks.class.getClassLoader());
        require(net.alexredby.pztoolkitjavapatches.Main.FENCE_SUPPORTED, "unsupported event hook");
        var env = table();
        LuaManager.platform = new J2SEPlatform(); LuaManager.env = env;
        LuaManager.thread = new KahluaThread(LuaManager.platform, env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new LuaCaller(new KahluaConverterManager());
        int[] calls = {0};
        env.rawset("finish", (JavaFunction)(frame, count) -> {
            if (count > 0 && frame.get(0) == IsoSpriteManager.instance) {
                calls[0]++;
                IsoSpriteManager.instance.getSprite("toolkit-event-fence").getProperties().set("ThumpSound", sound);
            }
            return 0;
        });
        var loaded = new Event("OnLoadedTileDefinitions", 0);
        loaded.callbacks.add(LuaCompiler.loadstring("finish(...)", "FenceChecks", env));
        var unrelated = new Event("ToolkitUnrelated", 1);
        LuaEventManager.setEvents(new ArrayList<>(List.of(loaded, unrelated)),
            new HashMap<>(Map.of(loaded.name, loaded, unrelated.name, unrelated)));
        fences.Reset(); log.reset(); register(fences, "toolkit-event-fence");
        LuaEventManager.triggerEvent("ToolkitUnrelated", IsoSpriteManager.instance);
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", new Object());
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions");
        require(log.size() == 0 && calls[0] == 0, "wrong event/manager/arity drained validation: " + log);
        LuaManager.env = null;
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance);
        require(log.size() == 0 && calls[0] == 0, "null environment dispatched callback");
        LuaManager.env = env;
        var worker = new Thread(() -> LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance));
        worker.start(); worker.join();
        require(calls[0] == 0 && log.size() == 0, "queued event validated before callbacks: " + log);
        LuaEventManager.RunQueuedEvents();
        require(calls[0] == 1 && log.size() == 0, "callback properties were not applied before validation: " + log);
        register(fences, "toolkit-event-late-invalid");
        require(log.toString().contains("toolkit-event-late-invalid"), "actual queued event did not mark ready");
        fences.Reset(); log.reset(); register(fences, "toolkit-event-direct-invalid");
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance);
        require(calls[0] == 2 && log.toString().contains("toolkit-event-direct-invalid"), "actual direct event did not validate after callbacks");
        loaded.callbacks.clear();
        fences.Reset(); log.reset(); register(fences, "carpentry_02_48"); register(fences, "carpentry_02_49");
        LuaEventManager.triggerEvent("ToolkitUnrelated", IsoSpriteManager.instance);
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", new Object());
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions");
        LuaManager.env = null;
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance);
        LuaManager.env = env;
        var owner = LuaManager.thread; LuaManager.thread = null;
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance);
        LuaManager.thread = owner;
        var emptyWorker = new Thread(() -> LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance));
        emptyWorker.start(); emptyWorker.join();
        require(log.size() == 0, "empty-consumer fallback drained on wrong event/manager/environment/thread: " + log);
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance);
        String emptyLog = log.toString();
        require(emptyLog.lines().filter(s -> s.contains("Missing ThumpSound for breakable object")).count() == 2
            && emptyLog.contains("carpentry_02_48") && emptyLog.contains("carpentry_02_49"),
            "native empty-consumer event did not drain both pending fences: " + emptyLog);
        register(fences, "toolkit-empty-event-late-invalid");
        require(log.toString().contains("toolkit-empty-event-late-invalid"), "empty-consumer event did not mark ready");
        String completed = log.toString();
        LuaEventManager.triggerEvent("OnLoadedTileDefinitions", IsoSpriteManager.instance);
        require(log.toString().equals(completed), "repeat empty-consumer completion validated twice");
    }

    static void cold() throws Exception {
        Instrumentation instrumentation = Accessor.tryGet(Loader.class, "g_instrumentation", (Instrumentation)null);
        require(instrumentation != null, "instrumentation unavailable");
        for (Class<?> type : instrumentation.getAllLoadedClasses())
            require(!type.getName().equals("zombie.iso.BrokenFences"), "cold check started after fences loaded");
        require(FenceValidation.install(true), "cold install failed");
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        var logger = DebugLog.getInstance(); var log = new ByteArrayOutputStream();
        logger.setStdOut(log); logger.setStdErr(log); DebugType.Sound.setLogSeverity(LogSeverity.Error);
        try {
            var fences = new BrokenFences(); register(fences, "toolkit-cold-fence");
            require(log.size() == 0, "cold load retained native premature validation");
            FenceValidation.tilesLoaded(); require(log.toString().contains("toolkit-cold-fence"), "cold deferred validation lost");
        } finally { logger.setStdOut(System.out); logger.setStdErr(System.err); }
        System.out.println("FENCE_COLD_CHECKS_PASS (unloaded class transformer, deferred registration, real validation)");
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].equals("cold")) { cold(); return; }
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        var data = tileProperties(); var tables = nativeTables();
        var aliases = new LinkedHashMap<String, ArrayList<String>>();
        for (String key : new String[]{"ThumpSound", "FenceTypeLow"}) {
            var values = new TreeSet<String>();
            for (var properties : data.values()) if (properties.containsKey(key)) values.add(properties.get(key));
            if (key.equals("FenceTypeLow")) values.add("toolkit-invalid-low");
            aliases.put(key, new ArrayList<>(values));
        }
        TilePropertyAliasMap.instance.Generate(aliases);
        var logger = DebugLog.getInstance(); var log = new ByteArrayOutputStream();
        logger.setStdOut(log); logger.setStdErr(log); DebugType.Sound.setLogSeverity(LogSeverity.Error);
        try {
            var nativeFences = new BrokenFences(); nativeFences.addBrokenTiles(tables[0]); nativeFences.addDebrisTiles(tables[1]);
            var baseline = contents(snapshot(nativeFences));
            long early = log.toString().lines().filter(s -> s.contains("Missing ThumpSound for breakable object")).count();
            require(early == 42, "native early validation count " + early);
            require(!FenceValidation.install(false), "unsupported guard accepted");
            byte[] original;
            try (var input = FenceChecks.class.getClassLoader().getResourceAsStream("zombie/iso/BrokenFences.class")) { original = input.readAllBytes(); }
            var weave = FenceValidation.class.getDeclaredMethod("weave", byte[].class); weave.setAccessible(true);
            byte[] unknown = original.clone(); unknown[unknown.length - 1] ^= 1;
            require(weave.invoke(null, (Object)unknown) == null, "unknown transformed bytes accepted");
            ClassReader changedReader = new ClassReader(original); ClassWriter changedWriter = new ClassWriter(changedReader, 0);
            changedReader.accept(new ClassVisitor(Opcodes.ASM9, changedWriter) {
                @Override public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                    return new MethodVisitor(Opcodes.ASM9, super.visitMethod(access, name, descriptor, signature, exceptions)) {
                        @Override public void visitLdcInsn(Object value) { super.visitLdcInsn(value.equals("VERSION") ? "MODIFIED_VERSION" : value); }
                    };
                }
            }, 0);
            require(weave.invoke(null, (Object)changedWriter.toByteArray()) == null, "modified native registration accepted");
            require(FenceValidation.install(true) && FenceValidation.install(true), "transformer install/retransform failed");
            var fences = new BrokenFences(); fences.Reset(); log.reset();
            fences.addBrokenTiles(tables[0]); fences.addDebrisTiles(tables[1]);
            require(log.size() == 0, "premature validation remains: " + log);
            var before = snapshot(fences); require(contents(before).equals(baseline), "registration/debris changed");
            for (String name : tables[0].delegate.keySet().stream().map(Object::toString).toList()) {
                var sprite = IsoSpriteManager.instance.getSprite(name);
                for (var property : data.getOrDefault(name, Map.of()).entrySet()) sprite.getProperties().set(property.getKey(), property.getValue());
            }
            FenceValidation.tilesLoaded();
            String real = log.toString();
            require(real.lines().filter(s -> s.contains("Missing ThumpSound for breakable object")).count() == 2
                && real.contains("carpentry_02_48") && real.contains("carpentry_02_49"), "unexpected real diagnostics: " + real);
            var after = snapshot(fences);
            require(contents(after).equals(baseline), "validation changed maps/debris");
            for (int i = 0; i < before.size(); i++) for (var key : before.get(i).keySet())
                require(before.get(i).get(key) == after.get(i).get(key), "native Tile identity changed");
            log.reset(); register(fences, "toolkit-missing-fence");
            var invalid = IsoSpriteManager.instance.getSprite("toolkit-invalid-fence"); invalid.getProperties().set("FenceTypeLow", "toolkit-invalid-low");
            register(fences, "toolkit-invalid-fence");
            require(log.toString().contains("toolkit-missing-fence") && log.toString().contains("toolkit-invalid-fence"), "late invalid fences suppressed");
            log.reset(); register(fences, "fencing_01_1"); require(log.size() == 0, "late valid fence rejected");
            fences.Reset(); log.reset(); register(fences, "toolkit-reset-fence"); require(log.size() == 0, "Reset left validator ready");
            FenceValidation.tilesLoaded(); require(log.toString().contains("toolkit-reset-fence"), "reload lost pending validation");
            log.reset(); FenceValidation.tilesLoaded(); require(log.size() == 0, "ready event validated pending twice");
            String sound = data.values().stream().map(properties -> properties.get("ThumpSound")).filter(Objects::nonNull).findFirst().orElseThrow();
            eventDispatch(fences, log, sound);
        } finally { logger.setStdOut(System.out); logger.setStdErr(System.err); }
        System.out.println("FENCE_CHECKS_PASS (native tables/maps/debris/Tile identities preserved, 42 premature errors deferred to 2 genuine errors from native tiles, missing/invalid/late/reset/reload unsupported bytes and actual callback/queued/direct/empty-consumer event dispatch)");
    }
}
