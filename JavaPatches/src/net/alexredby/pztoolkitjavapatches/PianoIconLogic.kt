package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Collections
import java.util.HexFormat
import java.util.WeakHashMap
import zombie.core.textures.Texture
import zombie.entity.ComponentType
import zombie.scripting.ScriptParser
import zombie.scripting.entity.GameEntityScript
import zombie.scripting.entity.components.crafting.CraftRecipe
import zombie.scripting.entity.components.crafting.CraftRecipeComponentScript
import zombie.scripting.entity.components.spriteconfig.SpriteConfigScript

object PianoIconLogic {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/scripting/entity/GameEntityScript.class",
            "2863b3af3a0dcef1163268da1469aaba2104a90c2def4f625811e8364cecab29",
        ) &&
            BytecodeSupport.supports(
                "zombie/scripting/entity/components/crafting/CraftRecipeComponentScript.class",
                "aa63d944d55d20277de6d28b032367c4badf39161efc04bbae4a003306675258",
            ) &&
            BytecodeSupport.supports(
                "zombie/scripting/entity/components/crafting/CraftRecipe.class",
                "a5c076d53e68f5cdfcc5bc17239aee1fb2072766471c29070ca84b30bd63c5de",
            ) &&
            BytecodeSupport.supports(
                "zombie/scripting/entity/components/spriteconfig/SpriteConfigScript.class",
                "f80f3e287cf1945ca220b4c8daf5c67daa35f26906c9f72bbde8f99b88b8eb02",
            ) &&
            BytecodeSupport.supports(
                "zombie/scripting/ScriptParser.class",
                "5f33328e2551fd40797697c15a9381b770fb547ac027f199e7dfc9172ac78f87",
            ) &&
            BytecodeSupport.supports(
                "zombie/core/textures/Texture.class",
                "2f4fba9ad6c33a9ba0763a68d16164833a682f7645e61a061f70bfdca33c1f8f",
            )

    const val TILE = "recreational_01_28"
    private val nativeRecipes =
        Collections.synchronizedMap(WeakHashMap<CraftRecipeComponentScript?, State>())

    // Checking support must not resolve game classes before the startup preloads.
    private object IconField {
        val value: Field? = iconField()
    }

    private class State {
        val loader: Thread = Thread.currentThread()
        var corrected = false
    }

    @JvmStatic
    fun prepare() {
        if (SUPPORTED) {
            GameEntityScript::class.java.name
            CraftRecipeComponentScript::class.java.name
            CraftRecipe::class.java.name
        }
    }

    private fun iconField(): Field? =
        try {
            CraftRecipe::class.java.getDeclaredField("iconName").apply { isAccessible = true }
        } catch (error: ReflectiveOperationException) {
            null
        } catch (error: RuntimeException) {
            null
        }

    @JvmStatic
    fun loaded(entity: GameEntityScript?, body: String?, supported: Boolean) {
        nativeRecipes.keys.removeIf { component ->
            (component ?: throw NullPointerException()).parent === entity
        }
        if (
            !supported ||
                entity == null ||
                body == null ||
                entity.moduleName != "Base" ||
                entity.name != "Piano" ||
                entity.modID != "pz-vanilla"
        )
            return
        val parsed = ScriptParser.parse(body)
        val block = parsed.getBlock("entity", "Piano")
        if (parsed.children.size != 1 || block == null) return
        val canonical = StringBuilder()
        block.prettyPrint(0, canonical)
        // Only the complete shipped B42.21 entity, including its recipe and all four faces.
        val hash =
            HexFormat.of()
                .formatHex(
                    MessageDigest.getInstance("SHA-256")
                        .digest(
                            canonical.toString().toByteArray(StandardCharsets.UTF_8),
                        ),
                )
        if (hash != "f6c9951020208becfe1f41c13baabc21c93da0bb7d7cbc8bf1e3766ee3635854") return
        val recipe =
            entity.getComponentScriptFor<CraftRecipeComponentScript>(ComponentType.CraftRecipe)
        if (recipe != null && recipe.craftRecipe.iconName == null) nativeRecipes[recipe] = State()
    }

    private fun eligible(component: CraftRecipeComponentScript?, supported: Boolean): State? {
        val state = nativeRecipes[component]
        if (
            !supported ||
                component == null ||
                state == null ||
                state.loader !== Thread.currentThread()
        )
            return null
        val entity = component.parent as? GameEntityScript ?: return null
        if (
            entity.moduleName != "Base" ||
                entity.name != "Piano" ||
                entity.modID != "pz-vanilla" ||
                entity.componentScripts.size != 2 ||
                entity.getComponentScriptFor<CraftRecipeComponentScript>(
                    ComponentType.CraftRecipe,
                ) !== component ||
                entity.containsComponent(ComponentType.UiConfig)
        )
            return null
        val recipe = component.craftRecipe
        if (recipe.name != "Piano") return null
        val sprites = entity.getComponentScriptFor<SpriteConfigScript>(ComponentType.SpriteConfig)
        if (sprites == null || sprites.allTileNames.isEmpty() || TILE != sprites.allTileNames[0])
            return null
        return state
    }

    @JvmStatic
    fun headless(component: CraftRecipeComponentScript?, supported: Boolean): Boolean {
        if (!zombie.network.GameServer.server || zombie.network.ServerGUI.isCreated()) return false
        val state = eligible(component, supported)
        return state != null &&
            !state.corrected &&
            (component ?: throw NullPointerException()).craftRecipe.iconName == null &&
            component.craftRecipe.iconTexture == null
    }

    @JvmStatic
    fun resolve(component: CraftRecipeComponentScript?, supported: Boolean): Texture? {
        val state = eligible(component, supported)
        if (state == null || IconField.value == null) return null
        val recipe = (component ?: throw NullPointerException()).craftRecipe
        if (if (state.corrected) TILE != recipe.iconName else recipe.iconName != null) return null
        val texture = Texture.getSharedTexture(TILE)
        if (
            texture == null ||
                texture.isFailure ||
                texture.isDestroyed ||
                texture.width <= 0 ||
                texture.height <= 0 ||
                recipe.iconTexture != null && recipe.iconTexture !== texture
        )
            return null
        if (!state.corrected) {
            val translation = recipe.translationName
            // Native OnScriptsLoaded prepends Item_; apply the missing world-tile metadata after
            // that stage.
            recipe.Load(
                recipe.name,
                ScriptParser.parse("component CraftRecipe { Icon = $TILE, }")
                    .getBlock("component", "CraftRecipe"),
            )
            recipe.overrideTranslationName(translation)
            recipe.overrideIconTexture(texture)
            state.corrected = true
            println("[PZToolkitJavaPatches] Piano recipe icon corrected: $TILE")
        }
        return recipe.iconTexture
    }

    @JvmStatic
    fun beginScripts(recipe: CraftRecipe?, supported: Boolean): Texture? {
        if (!supported) return null
        val field = IconField.value ?: return null
        if (recipe == null || TILE != recipe.iconName) return null
        synchronized(nativeRecipes) {
            for ((component, state) in nativeRecipes) {
                if (
                    !state.corrected ||
                        (component ?: throw NullPointerException()).craftRecipe !== recipe
                )
                    continue
                val texture = resolve(component, true) ?: return null
                // This native stage calls no Lua/external callbacks; keep its input/prop validation
                // intact.
                field.set(recipe, null)
                return texture
            }
        }
        return null
    }

    @JvmStatic
    fun endScripts(recipe: CraftRecipe?, texture: Texture?) {
        if (texture == null) return
        val field = IconField.value ?: throw NullPointerException()
        field.set(recipe, TILE)
        (recipe ?: throw NullPointerException()).overrideIconTexture(texture)
    }
}
