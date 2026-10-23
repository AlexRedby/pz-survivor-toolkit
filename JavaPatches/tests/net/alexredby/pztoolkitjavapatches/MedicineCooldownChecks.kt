package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.nio.file.Path
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.LuaManager
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.network.GameClient
import zombie.network.GameServer

object MedicineCooldownChecks {
    private fun verify(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        val player = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        val timer = field(IsoGameCharacter::class.java, "effectiveEdibleBuffTimer")
        timer.setFloat(player, 57.25f)
        GameClient.client = false

        // Discover and activate the built bridge before any direct call or constant reference.
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            MedicineCooldownChecks::class.java.classLoader,
        )
        val bridge =
            Exposer.getClassesWithGlobalLuaMethod().firstOrNull {
                it.name == "net.alexredby.pztoolkitjavapatches.MedicineCooldown"
            } ?: throw AssertionError("ZombieBuddy did not discover the annotated bridge")
        verify(
            Path.of(bridge.protectionDomain.codeSource.location.toURI()) ==
                Path.of(System.getProperty("pz.test.patch.jar")),
            "bridge did not come from the built JAR",
        )
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newTable()
        val converters = KahluaConverterManager()
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        Exposer.afterExposeAll()
        val function = LuaManager.env.rawget("toolkitMedicineCooldown")
        verify(function != null, "ZombieBuddy did not register the Lua global")
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.thread = thread
        verify(
            thread.call(function, arrayOf<Any?>(player)) == 57.25,
            "real Kahlua bridge did not return the exact native value",
        )
        verify(
            thread.call(function, arrayOf<Any?>(null)) == null,
            "Kahlua did not preserve a missing character as nil",
        )
        GameClient.client = true
        verify(
            thread.call(function, arrayOf<Any?>(player)) == null,
            "Kahlua did not preserve unavailable as nil",
        )
        GameClient.client = false
        verify(timer.getFloat(player) == 57.25f, "Lua bridge changed native cooldown")

        verify(MedicineCooldown.SUPPORTED, "current native character hash is unsupported")
        for (value in
            floatArrayOf(
                0f,
                -0.0f,
                .03125f,
                123.456f,
                280f,
                Float.MAX_VALUE,
                -1f,
                Float.NaN,
                Float.POSITIVE_INFINITY,
                Float.NEGATIVE_INFINITY,
            )) {
            timer.setFloat(player, value)
            val result = MedicineCooldown.cooldown(player)
            verify(
                if (value.isFinite() && value >= 0f)
                    result?.toRawBits() == value.toDouble().toRawBits()
                else result == null,
                "native cooldown was estimated, rounded or accepted invalid data: $value",
            )
            verify(
                timer.getFloat(player).toRawBits() == value.toRawBits(),
                "getter changed native cooldown",
            )
        }
        timer.setFloat(player, 57.25f)
        verify(MedicineCooldown.read(player, false) == null, "unsupported bytecode exposed a value")
        verify(MedicineCooldown.cooldown(null) == null, "null character exposed a value")
        GameServer.server = true
        verify(
            MedicineCooldown.cooldown(player) == 57.25,
            "authoritative Host server did not expose its exact cooldown",
        )
        GameClient.client = true
        verify(
            MedicineCooldown.cooldown(player) == null,
            "MP client exposed a non-authoritative cooldown",
        )
        verify(timer.getFloat(player) == 57.25f, "unavailable reads changed native cooldown")
        GameClient.client = false
        GameServer.server = false
        println(
            "MEDICINE_COOLDOWN_CHECKS_PASS (native field, no writes, invalid/unsupported/client/nil, ZombieBuddy scan and Kahlua)",
        )
        kotlin.system.exitProcess(0)
    }
}
