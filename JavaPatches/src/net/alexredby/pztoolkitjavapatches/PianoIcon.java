package net.alexredby.pztoolkitjavapatches;

import me.zed_0xff.zombie_buddy.Patch;
import zombie.core.textures.Texture;
import zombie.scripting.entity.GameEntityScript;
import zombie.scripting.entity.components.crafting.CraftRecipeComponentScript;
import zombie.scripting.entity.components.crafting.CraftRecipe;

/** Java entry points retain patch annotations and advice-local write-back. */
public final class PianoIcon {
    public static final boolean SUPPORTED = PianoIconLogic.SUPPORTED;
    public static final String TILE = PianoIconLogic.TILE;

    private PianoIcon() { }

    public static void prepare() { PianoIconLogic.prepare(); }

    public static void loaded(GameEntityScript entity, String body, boolean supported) throws Exception {
        PianoIconLogic.loaded(entity, body, supported);
    }

    public static boolean headless(CraftRecipeComponentScript component, boolean supported) {
        return PianoIconLogic.headless(component, supported);
    }

    public static Texture resolve(CraftRecipeComponentScript component, boolean supported) throws Exception {
        return PianoIconLogic.resolve(component, supported);
    }

    public static Texture beginScripts(CraftRecipe recipe, boolean supported) throws Exception {
        return PianoIconLogic.beginScripts(recipe, supported);
    }

    public static void endScripts(CraftRecipe recipe, Texture texture) throws IllegalAccessException {
        PianoIconLogic.endScripts(recipe, texture);
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
