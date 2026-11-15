package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Method
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.vm.LuaClosure
import zombie.Lua.LuaManager
import zombie.characters.IsoPlayer

/** A fresh negative fact about the selected WPANC capture, never an event/edit certificate. */
object QueueHandEventFacts {
    @JvmField internal val SUPPORTED = LuaFactApi.SUPPORTED && arrayOf(
        "zombie/characters/IsoPlayer.class" to "643585044a88ad1b29e8d5173774f66085c685c363ed10a89c0b79018de2874e",
        "zombie/characters/IsoGameCharacter.class" to "1ccabc492ba130f51486bf38a8400334545852253bbac9c46fff71242ab672f6",
        "zombie/iso/IsoMovingObject.class" to "70c0249c3bdb7b4c4fc335e644c74bc98c37aa0e4bfdc0665a75521460ea0900",
        "zombie/iso/IsoObject.class" to "7a99d06875c19ff132940d7192b414496537076e83474db0abc0cb38de6be70a",
        "se/krka/kahlua/vm/UpValue.class" to "505d77406e1d50884bec438e37afd1ec0a37f4431b649744a96add479a897745",
        "se/krka/kahlua/vm/Prototype.class" to "5e31f0809512e9cfbc9a8fff5a932e35cdc7f1ebb4a0ea146a2f9a207a23fcf4",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    // Native compiler output from the selected R5_AimState.lua. The source creation
    // sites bind primary/secondary slot 3 and markUpdated slot 0 to root register 9.
    internal const val PRIMARY = "120f5a9ca69ede731c33fab5f38d2a46f5c6d9aa2c92b198eeb2a9346e83698a"
    internal const val SECONDARY = "1790ecf60c6036ad702cfc9f0c4a08f5cf510d97128d26b3a804f7d5520465c8"
    internal const val UPDATED = "e61143b702c849ba70423e19d4397d280381b9efaca325c735e11b5a995b5922"
    private val readMethod = QueueHandEventFacts::class.java.getMethod("trackingAbsent", Any::class.java, Any::class.java, Any::class.java, Any::class.java)
    private val checkMethod = QueueHandEventFacts::class.java.getMethod("apiMatches", Any::class.java)
    private fun plain(value: Any?): KahluaTableImpl? = LuaFactApi.plain(value)
    private fun canonical(function: Any?, method: Method): Boolean = SUPPORTED && LuaFactApi.canonical(function, method)
    private fun entry(name: String, method: Method, args: Array<Any?>): Boolean =
        SUPPORTED && LuaFactApi.entry(name, method, args)
    @JvmStatic @LuaMethod(name = "toolkitArcheryTrackingApiMatches", global = true)
    fun apiMatches(function: Any?): Boolean = try {
        entry("toolkitArcheryTrackingApiMatches", checkMethod, arrayOf(function))
            && canonical(function, readMethod)
            && plain(LuaManager.env)?.delegate?.get("toolkitArcheryTrackingAbsent") === function
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    @JvmStatic @LuaMethod(name = "toolkitArcheryTrackingAbsent", global = true)
    fun trackingAbsent(actor: Any?, primary: Any?, secondary: Any?, updated: Any?): Boolean? = try {
        if (actor?.javaClass != IsoPlayer::class.java || (primary as? LuaClosure)?.env !== LuaManager.env ||
            !entry("toolkitArcheryTrackingAbsent", readMethod, arrayOf(actor, primary, secondary, updated))) null
        else read(actor, primary, secondary, updated, SUPPORTED, true)
    } catch (_: Exception) { null } catch (_: AssertionError) { null }

    private fun closure(value: Any?, hash: String, upvalues: Int): LuaClosure? {
        val closure = value as? LuaClosure ?: return null
        val p = closure.prototype
        // Bound before hashing; do not cache proof of publicly mutable prototype arrays.
        if (p.numParams != 2 || p.isVararg || p.numUpvalues != upvalues || closure.upvalues.size != upvalues
            || p.prototypes.isNotEmpty() || p.code.size !in 1..512 || p.constants.size > 64
            || p.constants.any { it is String && it.length > 256 }
            || LuaPrototypeFingerprint.leaf(p) != hash) return null
        return closure
    }
    /** Test-only plain key seam; this cannot admit a table through the production Lua API. */
    internal fun readTestKey(key: KahluaTableImpl, primary: Any?, secondary: Any?, updated: Any?, supported: Boolean, owner: Boolean): Boolean? =
        if (plain(key) == null) null else read(key, primary, secondary, updated, supported, owner)

    private fun read(key: Any?, primary: Any?, secondary: Any?, updated: Any?, supported: Boolean, owner: Boolean): Boolean? = try {
        if (!supported || !owner || key == null) null else {
            val p = closure(primary, PRIMARY, 8)
            val s = closure(secondary, SECONDARY, 6)
            val u = closure(updated, UPDATED, 2)
            if (p == null || s == null || u == null || p.env !== s.env || p.env !== u.env) null else {
                val capture = p.upvalues[3]
                if (capture == null || capture !== s.upvalues[3] || capture !== u.upvalues[0]) null else {
                    // clearTracking replaces the table in this cell. Always read the live cell;
                    // never retain its table, actor value, or a previous negative observation.
                    val tracking = plain(capture.getValue())
                    if (tracking == null) null else !tracking.delegate.containsKey(key)
                }
            }
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }
}
