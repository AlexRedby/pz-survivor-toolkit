package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.EnumSet;
import java.util.HashMap;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;
import zombie.Lua.KahluaNumberConverter;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ItemType;
import zombie.scripting.objects.ItemRecipe;
import zombie.scripting.objects.EvolvedRecipe;
import zombie.scripting.entity.components.crafting.CraftRecipe;
import java.util.ArrayList;
import zombie.ZomboidFileSystem;
import zombie.core.Core;
import zombie.network.GameServer;
import zombie.scripting.ScriptBucket;
import zombie.scripting.ScriptBucketCollection;
import zombie.scripting.ScriptLoadMode;
import zombie.scripting.ScriptManager;
import zombie.scripting.ScriptType;
import zombie.scripting.objects.BaseScriptObject;
import zombie.scripting.objects.ScriptModule;

/** Real native loading/resolution and built-JAR Lua exposure, without a game window. */
public final class RecipeCatalogRevisionChecks {
    private static final ScriptManager MANAGER = ScriptManager.instance;
    private static KahluaThread thread;
    private static Object revisionFunction;

    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static Field field(String name) throws Exception {
        Field result = ScriptManager.class.getDeclaredField(name);
        result.setAccessible(true);
        return result;
    }

    private static Double revision() {
        Object value = thread.call(revisionFunction, new Object[]{});
        require(value == null || value instanceof Double, "revision is not a Lua number/nil");
        return (Double)value;
    }

    private static void changed(Double before, String message) {
        Double after = revision();
        require(after != null && !after.equals(before), message);
    }

    private static ScriptBucketCollection<?> collection(String name) throws Exception {
        return (ScriptBucketCollection<?>)field(name).get(MANAGER);
    }

    private static Object lua(String source) throws Exception {
        return thread.call(LuaCompiler.loadstring(source, "catalog-revision-check", LuaManager.env), new Object[]{});
    }

    private static void cooking(boolean expected) throws Exception {
        require(Boolean.valueOf(expected).equals(lua("return TestCooking.read(TestFood)")),
            "native lifecycle revision did not refresh the actual Lua cooking index; expected " + expected);
    }

    private static void cookingReader() throws Exception {
        var classes = new Class<?>[]{ScriptManager.class, ArrayList.class, Item.class, ItemType.class,
            ItemRecipe.class, EvolvedRecipe.class, CraftRecipe.class};
        for (var type : classes) LuaManager.exposer.setExposed(type);
        for (var type : classes) LuaManager.exposer.exposeLikeJavaRecursively(type, LuaManager.env);
        LuaManager.env.rawset("TestManager", MANAGER);
        LuaManager.env.rawset("TestFoodType", ItemType.FOOD);
        LuaManager.env.rawset("TestFood", MANAGER.getItem("Base.CatalogFood"));
        lua("getScriptManager=function() return TestManager end; ItemType={FOOD=TestFoodType}; "
            + "Events={OnGameBoot={Add=function() end}}");
        Path shared = Path.of(System.getProperty("pz.test.project"))
            .resolve("PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit");
        LuaManager.env.rawset("TestCatalog", lua(Files.readString(shared.resolve("ItemRecipeCatalog.lua"))));
        lua("require=function(name) assert(name=='PZSurvivorToolkit/ItemRecipeCatalog'); return TestCatalog end");
        LuaManager.env.rawset("TestCooking", lua(Files.readString(shared.resolve("ItemCookingTags.lua"))));
    }

    private static void fixture(Path source, int time, int use) throws Exception {
        Files.writeString(source, "module Base { "
            + "craftRecipe CatalogProbe { time=" + time + ", } "
            + "evolvedrecipe CatalogMeal { BaseItem=Base.CatalogVessel, MaxItems=6, "
            + "ResultItem=Base." + (time == 19 ? "CatalogVessel" : "CatalogFood") + ", Cookable=true, } "
            + "item CatalogVessel { ItemType=base:normal, } "
            + "item CatalogFood { ItemType=base:food, IsCookable=true, HungerChange=0, "
            + "EvolvedRecipe=CatalogMeal:" + use + ", } }");
    }

    public static void main(String[] args) throws Exception {
        Core.debug = false;
        GameServer.server = true; // Native LoadFile must not require a renderer's DoFrameReady.
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"));
        ZomboidFileSystem.instance.init();
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", RecipeCatalogRevisionChecks.class.getClassLoader());
        var bridge = Exposer.getClassesWithGlobalLuaMethod().stream()
            .filter(type -> type.getName().equals(RecipeCatalogRevision.class.getName()))
            .findFirst().orElseThrow(() -> new AssertionError("revision bridge was not discovered"));
        require(Path.of(bridge.getProtectionDomain().getCodeSource().getLocation().toURI())
            .equals(Path.of(System.getProperty("pz.test.patch.jar"))), "bridge was not loaded from the built JAR");
        require(RecipeCatalogRevision.SUPPORTED, "unsupported native catalogue lifecycle bytecode");
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newEnvironment();
        var converters = new KahluaConverterManager();
        KahluaNumberConverter.install(converters);
        LuaManager.exposer = new LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env);
        Exposer.afterExposeAll();
        thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;
        revisionFunction = LuaManager.env.rawget("toolkitRecipeCatalogRevision");
        require(revisionFunction != null && revision() != null, "revision global is absent");
        require(RecipeCatalogRevision.read(false) == null, "unsupported bridge must return nil");

        Double before = revision();
        MANAGER.Reset();
        changed(before, "manager reset retained its epoch");
        var recipes = collection("craftRecipes");
        var evolved = collection("evolvedRecipes");
        var items = collection("items");
        Path source = Path.of(System.getProperty("pz.test.cache"), "catalog-probe.txt").toAbsolutePath();
        fixture(source, 11, 10);
        field("currentLoadFileMod").set(null, "pz-vanilla");
        field("currentLoadFileAbsPath").set(null, source.toString());
        field("currentLoadFileName").set(null, source.getFileName().toString());
        var origins = new HashMap<String, String>();
        origins.put(source.toString(), "pz-vanilla");
        field("tempFileToModMap").set(MANAGER, origins);
        MANAGER.LoadFile(ScriptLoadMode.Init, source.toString(), false);
        before = revision();
        recipes.LoadScripts(ScriptLoadMode.Init);
        changed(before, "standalone collection load retained its epoch");
        before = revision();
        MANAGER.moduleMap.get("Base").craftRecipes.LoadScripts(ScriptLoadMode.Reload);
        changed(before, "standalone bucket load retained its epoch");
        evolved.LoadScripts(ScriptLoadMode.Init);
        items.LoadScripts(ScriptLoadMode.Init);
        recipes.OnScriptsLoaded(ScriptLoadMode.Init);
        before = revision();
        items.OnScriptsLoaded(ScriptLoadMode.Init);
        changed(before, "standalone collection resolution retained its epoch");
        var recipe = MANAGER.getCraftRecipe("Base.CatalogProbe");
        var meal = MANAGER.getEvolvedRecipe("Base.CatalogMeal");
        require(recipe != null && recipe.getTime() == 11 && meal != null, "native fixture did not load");
        require(meal.getPossibleItems().size() == 1 && meal.getPossibleItems().get(0).getUse() == 10,
            "native item resolution did not populate evolved ingredients");
        cookingReader();
        cooking(true);
        int count = MANAGER.getAllCraftRecipes().size();
        before = revision();
        for (int i = 0; i < 5; i++) {
            MANAGER.getAllCraftRecipes(); MANAGER.getAllEvolvedRecipesList(); MANAGER.getAllRecipes();
            require(before.equals(revision()), "ordinary getters or unchanged Lua reads invalidated the epoch");
        }

        fixture(source, 17, 20);
        before = revision();
        MANAGER.ReloadScripts(EnumSet.of(ScriptType.CraftRecipe));
        changed(before, "same-count native recipe reload retained its epoch");
        require(MANAGER.getCraftRecipe("Base.CatalogProbe") == recipe
            && MANAGER.getAllCraftRecipes().size() == count && recipe.getTime() == 17,
            "native control did not reload the same recipe instance with the same count");
        cooking(true);
        fixture(source, 19, 20);
        before = revision();
        MANAGER.ReloadScripts(EnumSet.of(ScriptType.EvolvedRecipe));
        changed(before, "same-count evolved recipe reload retained its epoch");
        require(MANAGER.getEvolvedRecipe("Base.CatalogMeal") == meal
            && MANAGER.getAllEvolvedRecipesList().size() == 1, "evolved reload replaced identity or count");
        cooking(false);
        fixture(source, 17, 20);
        MANAGER.ReloadScripts(EnumSet.of(ScriptType.EvolvedRecipe));
        cooking(true);
        long mealVersion = meal.getScriptVersion();
        before = revision();
        MANAGER.ReloadScripts(EnumSet.of(ScriptType.Item));
        changed(before, "item-only native reload retained its epoch");
        require(MANAGER.getEvolvedRecipe("Base.CatalogMeal") == meal && meal.getScriptVersion() == mealVersion
            && meal.getPossibleItems().size() == 1 && meal.getPossibleItems().get(0).getUse() == 20,
            "item-only native reload did not change resolved ingredients at unchanged recipe identity/version");
        cooking(true);
        fixture(source, 17, 0);
        MANAGER.ReloadScripts(EnumSet.of(ScriptType.Item));
        require(meal.getScriptVersion() == mealVersion && meal.getPossibleItems().get(0).getUse() == 0,
            "item-only native control changed the recipe version or failed to change ingredient use");
        cooking(false);

        before = revision(); MANAGER.LoadedAfterLua();
        changed(before, "after-Lua resolution retained its epoch");
        before = revision(); MANAGER.PostTileDefinitions();
        changed(before, "post-tile resolution retained its epoch");
        before = revision(); MANAGER.PostWorldDictionaryInit();
        changed(before, "post-world resolution retained its epoch");

        // A real native collection method mutates scriptModules before this callback throws.
        var failing = new ScriptBucketCollection<BaseScriptObject>(MANAGER, ScriptType.CraftRecipe) {
            @Override public ScriptBucket<BaseScriptObject> getBucketFromModule(ScriptModule module) {
                require(revision() == null, "a partially changing catalogue exposed a persistent epoch");
                throw new IllegalStateException("expected partial registration failure");
            }
        };
        before = revision();
        try { failing.registerModule(new ScriptModule()); throw new AssertionError("failure control did not throw"); }
        catch (IllegalStateException expected) {
            require(expected.getMessage().equals("expected partial registration failure"), "unexpected registration error");
        }
        changed(before, "exceptional partial collection mutation retained its epoch");
        before = revision();
        recipes.reset();
        changed(before, "standalone collection reset retained its epoch");

        // These raw mutable views have no native lifecycle notification. This limit is explicit:
        // mods editing them must call the reader's invalidate(), rather than trusting this epoch.
        before = revision();
        require(!meal.getItemsList().isEmpty(), "raw-mutation control has no resolved entry");
        meal.getItemsList().clear();
        require(before.equals(revision()), "raw metadata mutation control unexpectedly became a lifecycle operation");
        Object lua = thread.call(LuaCompiler.loadstring(
            "local a=toolkitRecipeCatalogRevision(); return type(a)=='number' and a==toolkitRecipeCatalogRevision()",
            "catalog-revision-lua-probe", LuaManager.env), new Object[]{});
        require(Boolean.TRUE.equals(lua), "built-JAR zero-argument Lua global was not stable");
        System.out.println("RECIPE_CATALOG_REVISION_CHECKS_PASS (native same-count/in-place recipe reload, item-only evolved resolution, stable getters, partial exceptional mutation, lifecycle resolution, unsupported nil, built-JAR Kahlua and actual Lua cooking cache)");
        System.exit(0);
    }
}
