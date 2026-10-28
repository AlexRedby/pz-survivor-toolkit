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
        var onCreate = LuaManager.env.rawget("toolkitRecipeOnCreate");
        require(function != null && RecipeItemProperties.SUPPORTED, "recipe metadata global or native bytecode support missing");
        require(onCreate != null, "recipe creation metadata global missing");
        var thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        thread.debugOwnerThread = Thread.currentThread();
        LuaManager.thread = thread;
        thread.call(LuaCompiler.loadstring("TestPredicateCalls=0; TestCreateCalls=0; PZTest={onItem=function() "
            + "TestPredicateCalls=TestPredicateCalls+1; error('item predicate must not execute') end, onCreate=function() "
            + "TestCreateCalls=TestCreateCalls+1; error('recipe creation must not execute') end}",
            "recipe-predicate-probe", LuaManager.env), new Object[]{});

        var plain = new CraftRecipe();
        var tested = new CraftRecipe();
        tested.Load("PZTestRecipe", "craftRecipe PZTestRecipe { OnTest=PZTest.onItem, }");
        var milk = new CraftRecipe();
        milk.Load("MakeMilkFromPowderBucket", "craftRecipe MakeMilkFromPowderBucket { OnCreate=RecipeCodeOnCreate.makeMilkFromPowder, }");
        var replaced = new CraftRecipe();
        replaced.Load("MakeMilkFromPowderBucket", "craftRecipe MakeMilkFromPowderBucket { OnCreate=PZTest.onCreate, }");
        require(tested.hasLuaCall(CraftRecipe.LuaCall.OnTest), "native loader did not retain the mod OnTest callback");
        for (int i = 0; i < 3; i++) {
            require(Boolean.FALSE.equals(thread.call(function, new Object[]{plain})), "plain recipe acquired an item test");
            require(Boolean.TRUE.equals(thread.call(function, new Object[]{tested})), "mod OnTest was not detected");
            require(thread.call(function, new Object[]{null}) == null, "nil recipe metadata must remain unknown");
            require("RecipeCodeOnCreate.makeMilkFromPowder".equals(thread.call(onCreate, new Object[]{milk})),
                "native milk callback metadata differs");
            require("PZTest.onCreate".equals(thread.call(onCreate, new Object[]{replaced})),
                "replacement callback metadata was ignored");
            require(thread.call(onCreate, new Object[]{plain}) == null, "plain recipe acquired creation metadata");
            require(thread.call(onCreate, new Object[]{null}) == null, "nil recipe creation metadata must remain unknown");
        }
        require(RecipeItemProperties.read(tested, false) == null, "unsupported bytecode exposed callback metadata");
        require(RecipeItemProperties.readOnCreate(milk, false) == null, "unsupported bytecode exposed creation metadata");
        require("PZTest.onItem".equals(tested.getLuaCallString(CraftRecipe.LuaCall.OnTest)), "metadata read changed the callback");
        require(((Number)LuaManager.env.rawget("TestPredicateCalls")).intValue() == 0, "metadata read executed the callback");
        require(((Number)LuaManager.env.rawget("TestCreateCalls")).intValue() == 0, "metadata read executed creation callback");
        System.out.println("RECIPE_ITEM_PROPERTIES_CHECKS_PASS (native loaded OnTest/OnCreate, pure metadata, nil/unsupported, replacement callback, built-JAR globals and Kahlua)");
        System.exit(0);
    }
}
