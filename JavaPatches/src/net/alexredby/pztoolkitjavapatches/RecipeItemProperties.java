package net.alexredby.pztoolkitjavapatches;

import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.scripting.entity.components.crafting.CraftRecipe;

/** Inspect callback metadata without executing a recipe or creating an item. */
public final class RecipeItemProperties {
    static final boolean SUPPORTED = BytecodeSupport.supports(
        "zombie/scripting/entity/components/crafting/CraftRecipe.class",
        "a5c076d53e68f5cdfcc5bc17239aee1fb2072766471c29070ca84b30bd63c5de");

    @LuaMethod(name="toolkitRecipeHasItemTest", global=true)
    public static Boolean hasItemTest(CraftRecipe recipe) {
        return read(recipe, SUPPORTED);
    }

    static Boolean read(CraftRecipe recipe, boolean supported) {
        return supported && recipe != null ? Boolean.valueOf(recipe.hasLuaCall(CraftRecipe.LuaCall.OnTest)) : null;
    }

    private RecipeItemProperties() {}
}
