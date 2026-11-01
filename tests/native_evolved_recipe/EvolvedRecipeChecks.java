import zombie.scripting.objects.EvolvedRecipe;
import zombie.scripting.objects.Item;
import zombie.scripting.objects.ScriptModule;

/** Characterizes the installed B42 parser directly, without a game or patches. */
public final class EvolvedRecipeChecks {
    private static void require(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    private static void check(String label, String value, boolean expectedRecipe,
                              boolean expectedItem) throws Exception {
        // Each row starts with new objects: a previous true must not contaminate
        // either the absent-key or explicit-false observation.
        var recipe = new EvolvedRecipe("CookableProbe");
        require(!recipe.isCookable(), "fresh evolved recipe is already cookable");
        recipe.Load("CookableProbe", "evolvedrecipe CookableProbe { "
            + "BaseItem=Base.ProbeVessel, ResultItem=Base.ProbeFood, MaxItems=6, "
            + (value == null ? "" : "Cookable=" + value + ", ") + "}");
        require("Base.ProbeVessel".equals(recipe.getBaseItem())
            && "Base.ProbeFood".equals(recipe.getFullResultItem())
            && recipe.getMaxItems() == 6, "evolved recipe control fields did not parse");
        require(recipe.isCookable() == expectedRecipe,
            "EvolvedRecipe Cookable=" + label + ": expected " + expectedRecipe
                + ", got " + recipe.isCookable());

        // Item.IsCookable is a different property with normal Boolean parsing.
        // Exercise its public Load too, rather than a setter or fake item.
        var module = new ScriptModule();
        module.name = "Base";
        var item = new Item();
        item.setModule(module);
        require(!item.isIsCookable(), "fresh item is already cookable");
        item.Load("ProbeFood", "item ProbeFood { ItemType=base:food, "
            + (value == null ? "" : "IsCookable=" + value + ", ") + "}");
        require("ProbeFood".equals(item.getName()), "item control name did not load");
        require(item.isIsCookable() == expectedItem,
            "Item IsCookable=" + label + ": expected " + expectedItem
                + ", got " + item.isIsCookable());
        System.out.println("Cookable=" + label + " EvolvedRecipe=" + recipe.isCookable()
            + " Item.IsCookable=" + item.isIsCookable());
    }

    public static void main(String[] args) throws Exception {
        // Installed B42.21 treats presence of Cookable as true, even when its
        // value says false. These expectations document that native behavior;
        // this harness does not repair or override the parser.
        check("absent", null, false, false);
        check("true", "true", true, true);
        check("false", "false", true, false);
        System.out.println("EVOLVED_RECIPE_NATIVE_PASS");
    }
}
