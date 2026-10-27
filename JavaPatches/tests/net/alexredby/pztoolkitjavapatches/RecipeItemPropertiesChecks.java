package net.alexredby.pztoolkitjavapatches;

import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Exposer;
import me.zed_0xff.zombie_buddy.PatchEngine;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.KahluaThread;
import zombie.Lua.LuaManager;
import zombie.core.Core;
import zombie.scripting.entity.components.crafting.CraftRecipe;

public final class RecipeItemPropertiesChecks {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        Core.debug = false;
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", RecipeItemPropertiesChecks.class.getClassLoader());
        var bridge = Exposer.getClassesWithGlobalLuaMethod().stream()
            .filter(type -> type.getName().equals("net.alexredby.pztoolkitjavapatches.RecipeItemProperties"))
            .findFirst().orElseThrow(() -> new AssertionError("ZombieBuddy did not discover the recipe bridge"));
        require(Path.of(bridge.getProtectionDomain().getCodeSource().getLocation().toURI())
            .equals(Path.of(System.getProperty("pz.test.patch.jar"))), "bridge was not loaded from the built JAR");
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newEnvironment();
        LuaManager.exposer = new LuaManager.Exposer(new KahluaConverterManager(), LuaManager.platform, LuaManager.env);
        Exposer.afterExposeAll();
        var function = LuaManager.env.rawget("toolkitRecipeHasItemTest");
        require(function != null && RecipeItemProperties.SUPPORTED, "recipe metadata global or native bytecode support missing");
        var thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;
        thread.call(LuaCompiler.loadstring("TestPredicateCalls=0; PZTest={onItem=function() "
            + "TestPredicateCalls=TestPredicateCalls+1; error('item predicate must not execute') end}",
            "recipe-predicate-probe", LuaManager.env), new Object[]{});

        var plain = new CraftRecipe();
        var tested = new CraftRecipe();
        tested.Load("PZTestRecipe", "craftRecipe PZTestRecipe { OnTest=PZTest.onItem, }");
        require(tested.hasLuaCall(CraftRecipe.LuaCall.OnTest), "native loader did not retain the mod OnTest callback");
        for (int i = 0; i < 3; i++) {
            require(Boolean.FALSE.equals(thread.call(function, new Object[]{plain})), "plain recipe acquired an item test");
            require(Boolean.TRUE.equals(thread.call(function, new Object[]{tested})), "mod OnTest was not detected");
            require(thread.call(function, new Object[]{null}) == null, "nil recipe metadata must remain unknown");
        }
        require(RecipeItemProperties.read(tested, false) == null, "unsupported bytecode exposed callback metadata");
        require("PZTest.onItem".equals(tested.getLuaCallString(CraftRecipe.LuaCall.OnTest)), "metadata read changed the callback");
        require(((Number)LuaManager.env.rawget("TestPredicateCalls")).intValue() == 0, "metadata read executed the callback");
        System.out.println("RECIPE_ITEM_PROPERTIES_CHECKS_PASS (native loaded mod OnTest, pure metadata, nil/unsupported, built-JAR global and Kahlua)");
        System.exit(0);
    }
}
