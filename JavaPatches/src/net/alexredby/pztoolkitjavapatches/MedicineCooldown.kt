package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import me.zed_0xff.zombie_buddy.Accessor
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoGameCharacter
import zombie.network.GameClient

/** Read the authoritative native cooldown without reconstructing its random starting value. */
object MedicineCooldown {
    @JvmField
    internal val SUPPORTED = BytecodeSupport.supports("zombie/characters/IsoGameCharacter.class",
        "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b")

    private val timerField: Field? = if (SUPPORTED) {
        Accessor.findField(IsoGameCharacter::class.java, "effectiveEdibleBuffTimer")
    } else null

    @JvmStatic
    @LuaMethod(name = "toolkitMedicineCooldown", global = true)
    fun cooldown(character: IsoGameCharacter?): Double? = read(character, SUPPORTED)

    @JvmStatic
    @JvmName("read")
    internal fun read(character: IsoGameCharacter?, supported: Boolean): Double? {
        if (!supported || GameClient.client || character == null || timerField == null) return null
        val value = Accessor.tryGet<Float>(character, timerField, null) ?: return null
        return if (value.isFinite() && value >= 0f) value.toDouble() else null
    }
}
