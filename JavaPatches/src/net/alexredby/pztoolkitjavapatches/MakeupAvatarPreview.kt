package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.lang.reflect.Modifier
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoGameCharacter
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel
import zombie.core.skinnedmodel.visual.ItemVisual
import zombie.core.skinnedmodel.visual.ItemVisuals
import zombie.inventory.InventoryItem
import zombie.scripting.objects.ItemBodyLocation
import zombie.ui.UI3DModel

/** An avatar overlay. It never wears, creates, consumes or transmits an inventory item. */
object MakeupAvatarPreview {
    private fun field(owner: Class<*>, name: String, type: Class<*>): Field? =
        try {
            owner.getDeclaredField(name).takeIf { it.type == type && it.trySetAccessible() }
        } catch (_: ReflectiveOperationException) {
            null
        } catch (_: RuntimeException) {
            null
        }

    private val nativeSupported =
        BytecodeSupport.supports("zombie/ui/UI3DModel.class", "c71f4d2ce3c7de6c1e36b39810e9314e94284cbc6f675f822230eb2a1297e936") &&
            BytecodeSupport.supports("zombie/core/skinnedmodel/advancedanimation/AnimatedModel.class", "dc3f94c826174f8f522b9c900efee75c62fc99519f348f644b185106bb668dd8") &&
            BytecodeSupport.supports("zombie/core/skinnedmodel/visual/ItemVisual.class", "eeea202e9991aa5f67bd8c1ee53115a3ade92631faed7160c1b445ca8cf2dca9") &&
            BytecodeSupport.supports("zombie/inventory/InventoryItem.class", "b45d4438636509d992aaa7b7505ef8323cd898947efc27bf1f7e762951d6643d")
    private val modelField = field(UI3DModel::class.java, "animatedModel", AnimatedModel::class.java)
    private val visualsField = field(AnimatedModel::class.java, "itemVisuals", ItemVisuals::class.java)
    private val visualField = field(InventoryItem::class.java, "visual", ItemVisual::class.java)
    private val visualFields =
        try {
            ItemVisual::class.java.declaredFields.filter { !Modifier.isStatic(it.modifiers) }
                .takeIf { fields -> fields.size == 15 && fields.all { it.trySetAccessible() } }
        } catch (_: RuntimeException) {
            null
        }

    @JvmField
    val SUPPORTED = nativeSupported && modelField != null && visualsField != null && visualField != null && visualFields != null

    @JvmStatic
    @LuaMethod(name = "toolkitMakeupAvatarPreviewSupported", global = true)
    fun supported(): Boolean = SUPPORTED

    internal fun animatedModel(ui: UI3DModel): AnimatedModel? =
        if (SUPPORTED && ui.javaClass == UI3DModel::class.java) modelField?.get(ui) as? AnimatedModel else null

    // ItemVisual.copyFrom initializes the SOURCE's lazy cosmetic values. Read exact pinned
    // fields instead, cloning mutable arrays and dropping its live InventoryItem backlink.
    internal fun copyVisual(source: ItemVisual): ItemVisual {
        check(SUPPORTED && source.javaClass == ItemVisual::class.java)
        val result = ItemVisual()
        for (member in checkNotNull(visualFields)) {
            val value = member.get(source)
            member.set(result, when (value) {
                is ByteArray -> value.clone()
                is InventoryItem -> null
                else -> value
            })
        }
        return result
    }

    internal fun overlay(source: ItemVisuals, displaced: InventoryItem?, preview: ItemVisual): ItemVisuals =
        ItemVisuals().apply {
            for (visual in source) {
                if (displaced == null || visual.inventoryItem !== displaced) add(copyVisual(visual))
            }
            add(copyVisual(preview))
        }

    /** Call after native setCharacter. The caller initializes the preview visual once on selection. */
    @JvmStatic
    @LuaMethod(name = "toolkitMakeupAvatarPreview", global = true)
    fun preview(ui: UI3DModel?, actor: IsoGameCharacter?, selected: InventoryItem?): Boolean {
        if (!SUPPORTED || ui == null || actor == null) return false
        return try {
            val model = animatedModel(ui) ?: return false
            if (ui.character !== actor || model.javaClass != AnimatedModel::class.java) return false
            // Native prerender has already restored the unmodified actor avatar.
            if (selected == null) return true
            val location = selected.bodyLocation
            if (location != ItemBodyLocation.MAKE_UP_FULL_FACE && location != ItemBodyLocation.MAKE_UP_EYES &&
                location != ItemBodyLocation.MAKE_UP_EYES_SHADOW && location != ItemBodyLocation.MAKE_UP_LIPS) return false
            if (selected.container != null) return false
            val selectedVisual = visualField?.get(selected) as? ItemVisual ?: return false
            val original = visualsField?.get(model) as? ItemVisuals ?: return false
            val visuals = overlay(original, actor.getWornItem(location), selectedVisual)
            // Reuse native setCharacter's OWN copied HumanVisual. Passing the same object
            // also avoids copyFrom's lazy reads of the actor's appearance on every frame.
            model.setModelData(model.visual, visuals)
            true
        } catch (_: ReflectiveOperationException) {
            false
        } catch (_: RuntimeException) {
            false
        }
    }
}
