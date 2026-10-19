package net.alexredby.pztoolkitjavapatches;

import java.nio.charset.StandardCharsets;
import java.lang.reflect.Field;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.HexFormat;
import java.util.Map;
import java.util.WeakHashMap;
import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.textures.Texture;
import zombie.entity.ComponentType;
import zombie.scripting.ScriptParser;
import zombie.scripting.entity.GameEntityScript;
import zombie.scripting.entity.components.crafting.CraftRecipeComponentScript;
import zombie.scripting.entity.components.crafting.CraftRecipe;
import zombie.scripting.entity.components.spriteconfig.SpriteConfigScript;

public final class PianoIcon {
    public static final boolean SUPPORTED = BytecodeSupport.supports("zombie/scripting/entity/GameEntityScript.class",
            "2863b3af3a0dcef1163268da1469aaba2104a90c2def4f625811e8364cecab29")
        && BytecodeSupport.supports("zombie/scripting/entity/components/crafting/CraftRecipeComponentScript.class",
            "aa63d944d55d20277de6d28b032367c4badf39161efc04bbae4a003306675258")
        && BytecodeSupport.supports("zombie/scripting/entity/components/crafting/CraftRecipe.class",
            "a5c076d53e68f5cdfcc5bc17239aee1fb2072766471c29070ca84b30bd63c5de")
        && BytecodeSupport.supports("zombie/scripting/entity/components/spriteconfig/SpriteConfigScript.class",
            "f80f3e287cf1945ca220b4c8daf5c67daa35f26906c9f72bbde8f99b88b8eb02")
        && BytecodeSupport.supports("zombie/scripting/ScriptParser.class",
            "5f33328e2551fd40797697c15a9381b770fb547ac027f199e7dfc9172ac78f87")
        && BytecodeSupport.supports("zombie/core/textures/Texture.class",
            "2f4fba9ad6c33a9ba0763a68d16164833a682f7645e61a061f70bfdca33c1f8f");

    public static final String TILE = "recreational_01_28";
    private static final Map<CraftRecipeComponentScript, State> nativeRecipes =
        Collections.synchronizedMap(new WeakHashMap<>());
    // Checking support must not resolve game classes before the startup preloads.
    private static final class IconField {
        static final Field VALUE = iconField();
    }

    private static final class State {
        final Thread loader = Thread.currentThread();
        boolean corrected;
    }

    private PianoIcon() { }

    public static void prepare() {
        if (SUPPORTED) {
            zombie.scripting.entity.GameEntityScript.class.getName();
            zombie.scripting.entity.components.crafting.CraftRecipeComponentScript.class.getName();
            zombie.scripting.entity.components.crafting.CraftRecipe.class.getName();
        }
    }

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
        if (state == null || IconField.VALUE == null) return null;
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
        if (!supported || IconField.VALUE == null || recipe == null || !TILE.equals(recipe.getIconName())) return null;
        synchronized (nativeRecipes) {
            for (var entry : nativeRecipes.entrySet()) {
                if (!entry.getValue().corrected || entry.getKey().getCraftRecipe() != recipe) continue;
                var texture = resolve(entry.getKey(), true);
                if (texture == null) return null;
                // This native stage calls no Lua/external callbacks; keep its input/prop validation intact.
                IconField.VALUE.set(recipe, null);
                return texture;
            }
        }
        return null;
    }

    public static void endScripts(CraftRecipe recipe, Texture texture) throws IllegalAccessException {
        if (texture == null) return;
        IconField.VALUE.set(recipe, TILE);
        recipe.overrideIconTexture(texture);
    }

    @Patch(className="zombie.scripting.entity.GameEntityScript", methodName="Load", strictMatch=true)
    public static class NativePianoDefinition {
        @Patch.OnExit
        public static void exit(@Patch.This zombie.scripting.entity.GameEntityScript entity,
                                @Patch.Argument(0) String name, @Patch.Argument(1) String body) throws Exception {
            PianoIcon.loaded(entity, body, PianoIcon.SUPPORTED);
        }
    }

    @Patch(className="zombie.scripting.entity.components.crafting.CraftRecipeComponentScript", methodName="getIconTexture", strictMatch=true)
    public static class NativePianoIcon {
        @Patch.OnEnter(skipOn=true)
        public static boolean enter(@Patch.This zombie.scripting.entity.components.crafting.CraftRecipeComponentScript component,
                                    @Patch.Local("toolkitPianoIcon") zombie.core.textures.Texture texture,
                                    @Patch.Local("toolkitPianoHandled") boolean handled) throws Exception {
            handled = PianoIcon.headless(component, PianoIcon.SUPPORTED);
            if (!handled) texture = PianoIcon.resolve(component, PianoIcon.SUPPORTED);
            handled = handled || texture != null;
            return handled;
        }

        @Patch.OnExit
        public static void exit(@Patch.Local("toolkitPianoIcon") zombie.core.textures.Texture texture,
                                @Patch.Local("toolkitPianoHandled") boolean handled,
                                @Patch.Return(readOnly=false) zombie.core.textures.Texture result) {
            if (handled) result = texture;
        }
    }

    @Patch(className="zombie.scripting.entity.components.crafting.CraftRecipe", methodName="OnScriptsLoaded", strictMatch=true)
    public static class NativePianoIconLifecycle {
        @Patch.OnEnter
        public static void enter(@Patch.This zombie.scripting.entity.components.crafting.CraftRecipe recipe,
                                 @Patch.Argument(0) zombie.scripting.ScriptLoadMode mode,
                                 @Patch.Local("toolkitPianoTexture") zombie.core.textures.Texture texture) throws Exception {
            texture = PianoIcon.beginScripts(recipe, PianoIcon.SUPPORTED);
        }

        @Patch.OnExit(onThrowable=Throwable.class)
        public static void exit(@Patch.This zombie.scripting.entity.components.crafting.CraftRecipe recipe,
                                @Patch.Local("toolkitPianoTexture") zombie.core.textures.Texture texture) throws Exception {
            PianoIcon.endScripts(recipe, texture);
        }
    }
}
