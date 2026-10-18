package net.alexredby.pztoolkitjavapatches;

import java.nio.charset.StandardCharsets;
import java.lang.reflect.Field;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.HexFormat;
import java.util.Map;
import java.util.WeakHashMap;
import zombie.core.textures.Texture;
import zombie.entity.ComponentType;
import zombie.scripting.ScriptParser;
import zombie.scripting.entity.GameEntityScript;
import zombie.scripting.entity.components.crafting.CraftRecipeComponentScript;
import zombie.scripting.entity.components.crafting.CraftRecipe;
import zombie.scripting.entity.components.spriteconfig.SpriteConfigScript;

public final class PianoIcon {
    public static final String TILE = "recreational_01_28";
    private static final Map<CraftRecipeComponentScript, State> nativeRecipes =
        Collections.synchronizedMap(new WeakHashMap<>());
    private static final Field ICON_NAME = iconField();

    private static final class State {
        final Thread loader = Thread.currentThread();
        boolean corrected;
    }

    private PianoIcon() { }

    private static Field iconField() {
        try {
            var field = CraftRecipe.class.getDeclaredField("iconName");
            field.setAccessible(true);
            return field;
        } catch (ReflectiveOperationException | RuntimeException error) {
            return null;
        }
    }

    public static void loaded(GameEntityScript entity, String body, boolean supported) throws Exception {
        nativeRecipes.keySet().removeIf(component -> component.getParent() == entity);
        if (!supported || entity == null || body == null || !"Base".equals(entity.getModuleName())
            || !"Piano".equals(entity.getName()) || !"pz-vanilla".equals(entity.getModID())) return;
        var parsed = ScriptParser.parse(body);
        var block = parsed.getBlock("entity", "Piano");
        if (parsed.children.size() != 1 || block == null) return;
        var canonical = new StringBuilder();
        block.prettyPrint(0, canonical);
        // Only the complete shipped B42.21 entity, including its recipe and all four faces.
        String hash = HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(
            canonical.toString().getBytes(StandardCharsets.UTF_8)));
        if (!hash.equals("f6c9951020208becfe1f41c13baabc21c93da0bb7d7cbc8bf1e3766ee3635854")) return;
        CraftRecipeComponentScript recipe = entity.getComponentScriptFor(ComponentType.CraftRecipe);
        if (recipe != null && recipe.getCraftRecipe().getIconName() == null) nativeRecipes.put(recipe, new State());
    }

    private static State eligible(CraftRecipeComponentScript component, boolean supported) {
        State state = nativeRecipes.get(component);
        if (!supported || component == null || state == null || state.loader != Thread.currentThread()
            || !(component.getParent() instanceof GameEntityScript entity)
            || !"Base".equals(entity.getModuleName()) || !"Piano".equals(entity.getName())
            || !"pz-vanilla".equals(entity.getModID()) || entity.getComponentScripts().size() != 2
            || entity.getComponentScriptFor(ComponentType.CraftRecipe) != component
            || entity.containsComponent(ComponentType.UiConfig)) return null;
        var recipe = component.getCraftRecipe();
        if (!"Piano".equals(recipe.getName())) return null;
        SpriteConfigScript sprites = entity.getComponentScriptFor(ComponentType.SpriteConfig);
        if (sprites == null || sprites.getAllTileNames().isEmpty()
            || !TILE.equals(sprites.getAllTileNames().get(0))) return null;
        return state;
    }

    public static boolean headless(CraftRecipeComponentScript component, boolean supported) {
        if (!zombie.network.GameServer.server || zombie.network.ServerGUI.isCreated()) return false;
        State state = eligible(component, supported);
        return state != null && !state.corrected && component.getCraftRecipe().getIconName() == null
            && component.getCraftRecipe().getIconTexture() == null;
    }

    public static Texture resolve(CraftRecipeComponentScript component, boolean supported) throws Exception {
        State state = eligible(component, supported);
        if (state == null || ICON_NAME == null) return null;
        var recipe = component.getCraftRecipe();
        if (state.corrected ? !TILE.equals(recipe.getIconName()) : recipe.getIconName() != null) return null;
        var texture = Texture.getSharedTexture(TILE);
        if (texture == null || texture.isFailure() || texture.isDestroyed()
            || texture.getWidth() <= 0 || texture.getHeight() <= 0
            || recipe.getIconTexture() != null && recipe.getIconTexture() != texture) return null;
        if (!state.corrected) {
            String translation = recipe.getTranslationName();
            // Native OnScriptsLoaded prepends Item_; apply the missing world-tile metadata after that stage.
            recipe.Load(recipe.getName(), ScriptParser.parse("component CraftRecipe { Icon = " + TILE + ", }")
                .getBlock("component", "CraftRecipe"));
            recipe.overrideTranslationName(translation);
            recipe.overrideIconTexture(texture);
            state.corrected = true;
            System.out.println("[PZToolkitJavaPatches] Piano recipe icon corrected: " + TILE);
        }
        return recipe.getIconTexture();
    }

    public static Texture beginScripts(CraftRecipe recipe, boolean supported) throws Exception {
        if (!supported || ICON_NAME == null || recipe == null || !TILE.equals(recipe.getIconName())) return null;
        synchronized (nativeRecipes) {
            for (var entry : nativeRecipes.entrySet()) {
                if (!entry.getValue().corrected || entry.getKey().getCraftRecipe() != recipe) continue;
                var texture = resolve(entry.getKey(), true);
                if (texture == null) return null;
                // This native stage calls no Lua/external callbacks; keep its input/prop validation intact.
                ICON_NAME.set(recipe, null);
                return texture;
            }
        }
        return null;
    }

    public static void endScripts(CraftRecipe recipe, Texture texture) throws IllegalAccessException {
        if (texture == null) return;
        ICON_NAME.set(recipe, TILE);
        recipe.overrideIconTexture(texture);
    }
}
