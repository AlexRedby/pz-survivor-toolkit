package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Modifier
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel
import zombie.core.skinnedmodel.visual.ItemVisual
import zombie.core.skinnedmodel.visual.ItemVisuals
import zombie.inventory.InventoryItem
import zombie.ui.UI3DModel

object MakeupAvatarPreviewChecks {
    private val unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe

    private fun verify(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        verify(MakeupAvatarPreview.supported(), "native avatar bridge hash/field support is missing")
        for ((method, name) in listOf("supported" to "toolkitMakeupAvatarPreviewSupported", "preview" to "toolkitMakeupAvatarPreview")) {
            verify(MakeupAvatarPreview::class.java.declaredMethods.any {
                it.name == method && Modifier.isStatic(it.modifiers) &&
                    it.getAnnotation(LuaMethod::class.java)?.let { annotation -> annotation.global && annotation.name == name } == true
            }, "static Lua API missing: $name")
        }
        // The ordinary builder supplies the actual relocated JAR; isolated visual-copy checks
        // may run without it. Verify discovery and Lua boolean/nil conversion when supplied.
        System.getProperty("pz.test.patch.jar")?.let { jar ->
            PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", javaClass.classLoader)
            val bridge = Exposer.getClassesWithGlobalLuaMethod().firstOrNull { it.name == MakeupAvatarPreview::class.java.name }
            verify(bridge != null && Path.of(bridge.protectionDomain.codeSource.location.toURI()) == Path.of(jar),
                "ZombieBuddy did not discover avatar globals in the built JAR")
            LuaManager.platform = J2SEPlatform()
            LuaManager.env = LuaManager.platform.newTable()
            LuaManager.exposer = LuaManager.Exposer(KahluaConverterManager(), LuaManager.platform, LuaManager.env)
            Exposer.afterExposeAll()
            val thread = KahluaThread(LuaManager.platform, LuaManager.env)
            thread.debugOwnerThread = Thread.currentThread()
            verify(thread.call(LuaManager.env.rawget("toolkitMakeupAvatarPreviewSupported"), emptyArray<Any?>()) == true,
                "Lua support probe did not return true")
            verify(thread.call(LuaManager.env.rawget("toolkitMakeupAvatarPreview"), arrayOfNulls<Any>(3)) == false,
                "Lua nil argument fallback did not return false")
        }
        verify(!BytecodeSupport.supports("zombie/ui/UI3DModel.class", "changed"), "changed native bytes accepted")
        verify(!MakeupAvatarPreview.preview(null, null, null), "absent avatar/actor accepted")
        // Allocate only identity shells: no world, actor, GL, item creation callbacks or RNG.
        val ui = unsafe.allocateInstance(UI3DModel::class.java) as UI3DModel
        val model = unsafe.allocateInstance(AnimatedModel::class.java) as AnimatedModel
        UI3DModel::class.java.getDeclaredField("animatedModel").apply { isAccessible = true }.set(ui, model)
        verify(MakeupAvatarPreview.animatedModel(ui) === model, "native private model field was not read exactly")
        val old = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        val unrelated = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        fun visual(owner: InventoryItem?, kind: String): ItemVisual = ItemVisual().apply {
            itemType = kind
            inventoryItem = owner
            baseTexture = -1
            textureChoice = -1
            hue = Float.POSITIVE_INFINITY
        }
        val oldVisual = visual(old, "Base.MakeUp_Crow")
        val another = visual(unrelated, "Base.MakeUp_Crow")
        val selected = visual(null, "Base.MakeUp_LipsRed")
        val bytes = ItemVisual::class.java.getDeclaredField("blood").apply { isAccessible = true }
        bytes.set(another, byteArrayOf(3, 7))
        val source = ItemVisuals().apply { add(oldVisual); add(another) }
        val result = MakeupAvatarPreview.overlay(source, old, selected)
        verify(result.size == 2 && result[0].itemType == another.itemType && result[1].itemType == selected.itemType,
            "overlay did not replace the exact displaced visual and append preview")
        verify(source.size == 2 && source[0] === oldVisual && source[1] === another,
            "overlay mutated actor list or its ordering")
        verify(result[0] !== another && result[1] !== selected && result.all { it.inventoryItem == null },
            "overlay retained actor/preview visual or live item ownership")
        verify(another.inventoryItem === unrelated && oldVisual.inventoryItem === old,
            "overlay altered source ownership")
        verify(result[0].hue == Float.POSITIVE_INFINITY && result[0].baseTexture == -1 && result[0].textureChoice == -1,
            "copy initialized lazy cosmetic values")
        (bytes.get(result[0]) as ByteArray)[0] = 99
        verify((bytes.get(another) as ByteArray).contentEquals(byteArrayOf(3, 7)), "render copy shares mutable source blood")
        for (member in ItemVisual::class.java.declaredFields.filter { !Modifier.isStatic(it.modifiers) }) {
            member.isAccessible = true
            if (member.name == "inventoryItem" || member.name == "blood") continue
            val original = member.get(another)
            val copied = member.get(result[0])
            verify(if (original is ByteArray) copied is ByteArray && original.contentEquals(copied) && original !== copied else original == copied,
                "visual field copy differs: ${member.name}")
        }
        repeat(100) {
            val next = MakeupAvatarPreview.overlay(source, null, selected)
            verify(next.size == 3 && next[0] !== oldVisual && source.size == 2, "repeated overlay changed source")
            verify(selected.hue == Float.POSITIVE_INFINITY && selected.inventoryItem == null,
                "repeated overlay mutated preview")
        }
        println("MAKEUP_AVATAR_PREVIEW_CHECKS_PASS (native model field and detached visual isolation; no GL rendering)")
        kotlin.system.exitProcess(0)
    }
}
