package net.alexredby.pztoolkitjavapatches;

import java.io.ByteArrayOutputStream;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;
import me.zed_0xff.zombie_buddy.PatchEngine;
import zombie.ZomboidFileSystem;
import zombie.core.Core;
import zombie.debug.DebugLog;
import zombie.debug.DebugType;
import zombie.debug.LogSeverity;
import zombie.gameStates.ChooseGameInfo;
import zombie.network.GameServer;
import zombie.scripting.ScriptBucketCollection;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptParser;
import zombie.scripting.entity.components.crafting.CraftRecipe;

/** Source-backed native discovery/registry tests; live charge effects use the SP/Host suite. */
public final class DamnLibraryBatteryRecipeChecks {
    private static final ScriptManager MANAGER = ScriptManager.instance;
    private static final ZomboidFileSystem FILES = ZomboidFileSystem.instance;
    private static final List<String> TARGETS = List.of("Base." + DamnLibraryBatteryRecipes.INSERT,
        "Base." + DamnLibraryBatteryRecipes.REMOVE);
    private static final ByteArrayOutputStream LOG = new ByteArrayOutputStream();
    private static ScriptBucketCollection<?> recipes;
    private static Field owner, absolute, filename;
    private static Path target, vanilla, unrelated;
    private static String original;
    private static int cases;

    private static void require(boolean value, String reason) {
        if (!value) throw new AssertionError(reason + "\nNative log:\n" + LOG.toString(StandardCharsets.UTF_8));
    }

    private static Field field(Class<?> type, String name) throws Exception {
        Field result = type.getDeclaredField(name);
        result.setAccessible(true);
        return result;
    }

    private static void provenance(Path path, String mod) throws Exception {
        // These are the native Load/ReloadScripts caller's fields, before it invokes LoadFile.
        owner.set(null, mod);
        absolute.set(null, path.toString());
        filename.set(null, path.getFileName().toString());
    }

    private static void loadFile(ScriptLoadMode mode, Path path, String mod) throws Exception {
        provenance(path, mod);
        MANAGER.LoadFile(mode, path.toString(), mode == ScriptLoadMode.Reload);
    }

    private static void quiet() {
        String output = LOG.toString(StandardCharsets.UTF_8);
        require(!java.util.regex.Pattern.compile("(?m)^\\s*(?:ERROR|WARN(?:ING)?)\\s*:|Unknown key|Exception thrown")
                    .matcher(output).find(),
                "native recipe loading emitted diagnostics");
        require(!recipes.hasLoadErrors(), "native loader recorded a recipe error");
    }

    private static Map<String, List<Object>> snapshot() {
        var result = new TreeMap<String, List<Object>>();
        for (CraftRecipe recipe : MANAGER.getAllCraftRecipes()) {
            var fields = new ArrayList<Object>();
            fields.add(recipe.getTime());
            fields.add(recipe.getCategory());
            fields.add(List.copyOf(recipe.getTags()));
            fields.add(recipe.needToBeLearn());
            fields.add(recipe.isAllowBatchCraft());
            for (var call : CraftRecipe.LuaCall.values()) fields.add(recipe.getLuaCallString(call));
            for (var input : recipe.getInputs()) fields.add(input.getOriginalLine());
            fields.add("outputs");
            for (var output : recipe.getOutputs()) fields.add(output.getOriginalLine());
            String id = recipe.getScriptObjectFullType();
            require(result.put(id, fields) == null, "duplicate recipe list entry " + id);
            require(MANAGER.getCraftRecipe(id) == recipe && recipes.getFullType(id) == recipe,
                    "native registry/list identity mismatch " + id);
        }
        return result;
    }

    private static void absent() {
        for (String id : TARGETS) {
            require(MANAGER.getCraftRecipe(id) == null && MANAGER.getCraftRecipe(id.substring(5)) == null
                    && recipes.getFullType(id) == null
                    && MANAGER.moduleMap.get("Base").getCraftRecipe(id.substring(5)) == null,
                    "duplicate battery recipe still registered " + id);
        }
    }

    private static void nativeBatteryContract() {
        CraftRecipe insert = MANAGER.getCraftRecipe("Base.InsertBattery");
        CraftRecipe remove = MANAGER.getCraftRecipe("Base.RemoveBattery");
        require(insert != null && remove != null, "native battery recipes missing");
        require(insert.getInputCount() == 2 && insert.getOutputCount() == 0
                && insert.getInputs().get(0).isKeep() && insert.getInputs().get(0).isItemCount()
                && insert.getInputs().get(0).isEmpty()
                && insert.getInputs().get(0).getOriginalLine().contains("base:usesbattery")
                && insert.getInputs().get(1).isDestroy() && insert.getInputs().get(1).isItemCount()
                && "RecipeCodeOnCreate.torchBatteryInsert".equals(insert.getLuaCallString(CraftRecipe.LuaCall.OnCreate)),
                "native battery insertion contract changed");
        require(remove.getInputCount() == 1 && remove.getOutputCount() == 1
                && remove.getInputs().get(0).isKeep() && remove.getInputs().get(0).notEmpty()
                && remove.getInputs().get(0).isItemCount()
                && remove.getInputs().get(0).getOriginalLine().contains("InheritUsesAndEmpty")
                && remove.getInputs().get(0).getOriginalLine().contains("base:usesbattery")
                && remove.getOutputs().get(0).getOriginalLine().contains("Base.Battery"),
                "native battery removal contract changed");
    }

    private static void sources(ScriptLoadMode mode, boolean dependency, String mod) throws Exception {
        loadFile(mode, vanilla, "pz-vanilla");
        loadFile(mode, unrelated, "fixture");
        if (dependency) loadFile(mode, target, mod);
    }

    private static Map<String, List<Object>> load(boolean dependency, String mod) throws Exception {
        MANAGER.Reset();
        LOG.reset();
        sources(ScriptLoadMode.Init, dependency, mod);
        recipes.LoadScripts(ScriptLoadMode.Init);
        quiet(); nativeBatteryContract();
        return snapshot();
    }

    private static void reload(boolean dependency) throws Exception {
        LOG.reset();
        recipes.setReloadBuckets(true);
        recipes.PreReloadScripts();
        sources(ScriptLoadMode.Reload, dependency, "damnlib");
        recipes.setReloadBuckets(false);
        recipes.LoadScripts(ScriptLoadMode.Reload);
        quiet(); nativeBatteryContract();
    }

    private static void foreignReload(Path foreignRecipe, boolean first) throws Exception {
        LOG.reset();
        recipes.setReloadBuckets(true);
        recipes.PreReloadScripts();
        loadFile(ScriptLoadMode.Reload, vanilla, "pz-vanilla");
        loadFile(ScriptLoadMode.Reload, unrelated, "fixture");
        if (first) loadFile(ScriptLoadMode.Reload, foreignRecipe, "other-mod");
        loadFile(ScriptLoadMode.Reload, target, "damnlib");
        if (!first) loadFile(ScriptLoadMode.Reload, foreignRecipe, "other-mod");
        recipes.setReloadBuckets(false);
        recipes.LoadScripts(ScriptLoadMode.Reload);
        quiet(); nativeBatteryContract();
    }

    private static String token(String name) {
        String module = ScriptParser.parseTokens(ScriptParser.stripComments(original.replace("\r\n", "\n"))).get(0);
        String body = module.substring(module.indexOf('{') + 1, module.lastIndexOf('}'));
        return ScriptParser.parseTokens(body).stream().map(String::trim)
            .filter(value -> value.startsWith("craftRecipe " + name + "\n")).findFirst().orElseThrow();
    }

    private static void disableControl(boolean debug) throws Exception {
        Core.debug = debug;
        LOG.reset();
        var recipe = new CraftRecipe();
        boolean failed = false;
        try { recipe.Load("DisableControl", "craftRecipe DisableControl { enabled=false, }"); }
        catch (Exception expected) { failed = true; }
        require(!recipe.isEnabled(), "native common-field parser did not apply enabled=false");
        require(failed == debug && LOG.toString(StandardCharsets.UTF_8).contains("Unknown key 'enabled'"),
                "original common-field/craftRecipe diagnostic control stopped reproducing");
        cases++;
        LOG.reset();
    }

    public static void main(String[] args) throws Exception {
        String configured = System.getenv("PZ_DAMNLIB_RECIPES");
        if (configured == null || configured.isBlank()) {
            String root = System.getenv("PZ_DAMNLIB_ROOT");
            require(root != null && !root.isBlank(), "Set PZ_DAMNLIB_RECIPES or PZ_DAMNLIB_ROOT to the original Workshop input");
            configured = Path.of(root, "42.20", DamnLibraryBatteryRecipes.TARGET).toString();
        }
        Path input = Path.of(configured).toAbsolutePath();
        byte[] bytes = Files.readAllBytes(input);
        require(DamnLibraryBatteryRecipes.SOURCE_SHA256.equals(HexFormat.of().formatHex(
            MessageDigest.getInstance("SHA-256").digest(bytes))), "reviewed DAMN Library input changed");
        original = new String(bytes, StandardCharsets.UTF_8);
        require(DamnLibraryBatteryRecipes.SUPPORTED, "unsupported native script loader");
        require(Path.of(DamnLibraryBatteryRecipes.class.getProtectionDomain().getCodeSource().getLocation().toURI())
            .equals(Path.of(System.getProperty("pz.test.patch.jar"))), "runtime was not loaded from the built JAR");
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        FILES.setCacheDir(System.getProperty("pz.test.cache"));
        FILES.init();
        Path root = Path.of(System.getProperty("pz.test.cache"), "mods/damnlib");
        Path version = root.resolve("42");
        target = version.resolve(DamnLibraryBatteryRecipes.TARGET);
        Files.createDirectories(root.resolve("common"));
        Files.createDirectories(target.getParent());
        Files.writeString(root.resolve("common/mod.info"), "id=damnlib\n");
        Files.writeString(version.resolve("mod.info"), "id=damnlib\nmodversion=fixture\n");
        Files.write(target, bytes);
        FILES.setModIdToDir("damnlib", root.toString());
        require(Path.of(ChooseGameInfo.getModDetails("damnlib").getVersionDir()).equals(version), "active source layer differs");
        FILES.getModIDs().add("damnlib");
        FILES.activeFileMap.put(DamnLibraryBatteryRecipes.TARGET.toLowerCase(Locale.ROOT), target.toString());
        vanilla = Path.of("media/scripts/generated/recipes/recipes_electrical.txt").toAbsolutePath();
        unrelated = version.resolve("media/scripts/unrelated.txt");
        Files.writeString(unrelated, "module Base { craftRecipe " + DamnLibraryBatteryRecipes.INSERT
            + "Custom { time=71, } } module Other { craftRecipe " + DamnLibraryBatteryRecipes.INSERT + " { time=72, } }");
        owner = field(ScriptManager.class, "currentLoadFileMod");
        absolute = field(ScriptManager.class, "currentLoadFileAbsPath");
        filename = field(ScriptManager.class, "currentLoadFileName");
        recipes = (ScriptBucketCollection<?>) field(ScriptManager.class, "craftRecipes").get(MANAGER);
        GameServer.server = true; // Native LoadFile otherwise requires a live renderer's DoFrameReady.
        DebugLog.getInstance().setStdOut(LOG);
        DebugLog.getInstance().setStdErr(LOG);
        DebugType.Recipe.setLogSeverity(LogSeverity.Warning);
        DebugType.General.setLogSeverity(LogSeverity.Warning);
        Map<String, List<Object>> baseline = null, vanillaOnly = null;
        for (boolean debug : new boolean[]{false, true}) {
            disableControl(debug);
            var loaded = load(true, "damnlib");
            require(loaded.keySet().containsAll(TARGETS), "unwoven original control lost target recipes");
            if (baseline == null) baseline = loaded;
            else require(baseline.equals(loaded), "debug flag changed original recipe metadata");
            vanillaOnly = load(false, "damnlib");
        }
        require(baseline.size() - vanillaOnly.size() == 64, "full source control no longer has 64 DAMN recipes");
        var expected = new TreeMap<>(baseline);
        for (String id : TARGETS) expected.remove(id);
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", DamnLibraryBatteryRecipeChecks.class.getClassLoader());
        for (boolean debug : new boolean[]{false, true}) {
            Core.debug = debug;
            require(load(true, "damnlib").equals(expected), "woven full source changed unrelated recipe metadata");
            absent(); cases++;
            reload(true);
            require(snapshot().equals(expected), "reload changed surviving recipe metadata");
            absent(); cases++;
            require(load(false, "damnlib").equals(vanillaOnly), "absent dependency created placeholder recipes");
            absent(); cases++;
            reload(false);
            require(snapshot().equals(vanillaOnly), "absent dependency reload changed recipes");
            absent(); cases++;
        }
        Files.writeString(target, original + "\n// unknown source version\n");
        require(load(true, "damnlib").equals(baseline), "unknown-source transition control changed");
        Files.write(target, bytes);
        reload(true);
        require(snapshot().equals(expected), "recognized reload left previously registered duplicate recipes");
        absent(); cases++;
        Files.writeString(target, original + "\n// unknown source version\n");
        reload(true);
        require(snapshot().equals(baseline), "unknown reload failed to restore native recipe discovery"); cases++;
        Files.write(target, bytes);
        Path override = version.resolve("media/scripts/override.txt");
        Files.writeString(override, "module Base { craftRecipe " + DamnLibraryBatteryRecipes.INSERT
            + " { time=73, OnCreate=Foreign.keep, } }");
        Map<String, List<Object>> foreignExpected = null;
        for (boolean first : new boolean[]{false, true}) {
            require(load(true, "damnlib").equals(expected), "foreign override control failed");
            foreignReload(override, first);
            var snapshot = snapshot();
            require(MANAGER.getCraftRecipe("Base." + DamnLibraryBatteryRecipes.REMOVE) == null
                    && MANAGER.getCraftRecipe("Base." + DamnLibraryBatteryRecipes.INSERT).getTime() == 73
                    && "Foreign.keep".equals(MANAGER.getCraftRecipe("Base." + DamnLibraryBatteryRecipes.INSERT)
                        .getLuaCallString(CraftRecipe.LuaCall.OnCreate)), "foreign override was lost");
            var surviving = new TreeMap<>(snapshot);
            surviving.remove("Base." + DamnLibraryBatteryRecipes.INSERT);
            require(surviving.equals(expected), "foreign override changed unrelated recipes");
            if (foreignExpected == null) foreignExpected = snapshot;
            else require(snapshot.equals(foreignExpected), "foreign override depends on source order");
            cases++;
        }
        // Unknown prior ownership cannot justify deleting a live object before its provider
        // gets a reload turn. Fall back to native behavior until a fresh initial load.
        require(load(true, "other-mod").equals(baseline), "foreign prior-owner control changed");
        reload(true);
        require(snapshot().equals(baseline), "unowned prior recipes were removed during reload"); cases++;
        Core.debug = true;
        require(load(true, "other-mod").equals(baseline), "foreign source owner was changed"); cases++;
        FILES.getModIDs().remove("damnlib");
        require(load(true, "damnlib").equals(baseline), "inactive dependency was changed"); cases++;
        FILES.getModIDs().add("damnlib");
        Path foreign = version.resolve("media/scripts/foreign.txt");
        Files.write(foreign, bytes);
        FILES.activeFileMap.put(DamnLibraryBatteryRecipes.TARGET.toLowerCase(Locale.ROOT), foreign.toString());
        require(load(true, "damnlib").equals(baseline), "foreign active file provider was changed"); cases++;
        FILES.activeFileMap.put(DamnLibraryBatteryRecipes.TARGET.toLowerCase(Locale.ROOT), target.toString());
        Files.writeString(target, original + "\n// future source version\n");
        require(load(true, "damnlib").equals(baseline), "changed complete source was modified"); cases++;
        Files.write(target, bytes);
        require(load(true, "damnlib").equals(expected), "reviewed source was not recognized after a changed source");
        provenance(target, "damnlib");
        var module = MANAGER.moduleMap.get("Base");
        for (String name : List.of(DamnLibraryBatteryRecipes.INSERT, DamnLibraryBatteryRecipes.REMOVE)) {
            String body = token(name);
            require(DamnLibraryBatteryRecipes.skip(module, ScriptLoadMode.Init, body, true), "reviewed token not recognized");
            require(!DamnLibraryBatteryRecipes.skip(module, ScriptLoadMode.Init, body, false), "unsupported native accepted token");
            require(!DamnLibraryBatteryRecipes.skip(module, ScriptLoadMode.Init, body.replace("time = 40", "time = 41"), true),
                    "changed target token accepted");
            require(!DamnLibraryBatteryRecipes.skip(MANAGER.moduleMap.get("Other"), ScriptLoadMode.Init, body, true),
                    "different module accepted");
            filename.set(null, "other.txt");
            require(!DamnLibraryBatteryRecipes.skip(module, ScriptLoadMode.Init, body, true), "wrong filename accepted");
            provenance(target, "damnlib");
            absolute.set(null, foreign.toString());
            require(!DamnLibraryBatteryRecipes.skip(module, ScriptLoadMode.Init, body, true), "foreign loading path accepted");
            provenance(target, "damnlib");
            require(!DamnLibraryBatteryRecipes.skip(module, null, body, true)
                && !DamnLibraryBatteryRecipes.skip(null, ScriptLoadMode.Init, body, true)
                && !DamnLibraryBatteryRecipes.skip(module, ScriptLoadMode.Init, null, true), "null boundary accepted");
            cases++;
        }
        // A changed token presented under otherwise exact source ownership must still reach
        // the real woven discovery method, rather than being retired by its identifier alone.
        LOG.reset();
        MANAGER.Reset();
        loadFile(ScriptLoadMode.Init, vanilla, "pz-vanilla");
        provenance(target, "damnlib");
        MANAGER.ParseScript(ScriptLoadMode.Init, "module Base { " + token(DamnLibraryBatteryRecipes.INSERT)
            .replace("time = 40", "time = 41") + " }");
        recipes.LoadScripts(ScriptLoadMode.Init);
        require(MANAGER.getCraftRecipe("Base." + DamnLibraryBatteryRecipes.INSERT).getTime() == 41,
                "woven discovery removed a changed target token");
        quiet(); cases++;
        require(java.util.Arrays.equals(bytes, Files.readAllBytes(input)), "original Workshop input was modified");
        System.out.println("DAMN_LIBRARY_BATTERY_RECIPES_PASS (" + cases
            + " cases, full64 source, exact2 retirement, native charge flags/callback, reload,"
            + " absent/foreign/changed/unsupported, debug server diagnostics, original disable failure, built JAR)");
        System.exit(0);
    }
}
