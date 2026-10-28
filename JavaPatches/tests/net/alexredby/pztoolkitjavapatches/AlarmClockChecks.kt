package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.util.ArrayList
import java.util.HashSet
import me.zed_0xff.zombie_buddy.Exposer
import me.zed_0xff.zombie_buddy.PatchEngine
import sun.misc.Unsafe
import zombie.GameTime
import zombie.audio.DummySoundEmitter
import zombie.characters.IsoPlayer
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.AlarmClock
import zombie.inventory.types.AlarmClockClothing
import zombie.inventory.types.IAlarmClock
import zombie.iso.IsoCell
import zombie.iso.IsoGridSquare
import zombie.iso.IsoWorld
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.packets.SyncPlayerAlarmClockPacket
import zombie.network.packets.SyncWorldAlarmClockPacket
import zombie.scripting.objects.CharacterTrait

object AlarmClockChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var time: GameTime
    private var checks = 0

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).also { it.isAccessible = true }

    private fun require(value: Boolean, reason: String) {
        checks++
        if (!value) throw AssertionError(reason)
    }

    private class Player : IsoPlayer(null) {
        var deaf = false

        override fun isDead(): Boolean = false

        override fun hasTrait(trait: CharacterTrait?): Boolean =
            deaf && trait == CharacterTrait.DEAF

        override fun getHearDistanceModifier(): Float = 1f
    }

    private class Emitter : DummySoundEmitter() {
        var played = 0

        override fun playSoundImpl(name: String?, square: IsoGridSquare?): Long {
            played++
            return 42
        }

        override fun isPlaying(id: Long): Boolean = id == 42L
    }

    private fun make(type: Class<*>, hour: Int, minute: Int): IAlarmClock {
        val alarm = unsafe.allocateInstance(type)
        field(type, "alarmSet").setBoolean(alarm, true)
        field(type, "alarmHour").setInt(alarm, hour)
        field(type, "alarmMinutes").setInt(alarm, minute)
        field(type, "ringSince").setDouble(alarm, -1.0)
        field(type, "ringSound").setLong(alarm, -1)
        field(type, "forceDontRing").setInt(alarm, -1)
        field(type, "soundRadius").setInt(alarm, 40)
        val container = ItemContainer()
        container.setSourceGrid(unsafe.allocateInstance(IsoGridSquare::class.java) as IsoGridSquare)
        field(InventoryItem::class.java, "container").set(alarm, container)
        return alarm as IAlarmClock
    }

    private fun ringing(alarm: IAlarmClock): Boolean =
        field(alarm.javaClass, "ringSince").getDouble(alarm) >= 0

    private fun at(alarm: IAlarmClock, day: Int, hour: Int, minute: Int) {
        time.setNightsSurvived(day)
        time.setTimeOfDay(hour + (minute + .1f) / 60)
        alarm.update()
    }

    private fun sync(
        alarm: IAlarmClock,
        world: Boolean,
        stop: Boolean,
        hour: Int,
        minute: Int,
        enabled: Boolean,
    ) {
        val packet: Any = if (world) SyncWorldAlarmClockPacket() else SyncPlayerAlarmClockPacket()
        val type = packet.javaClass
        field(type, "stopRinging").setBoolean(packet, stop)
        field(type, "alarmHour").setInt(packet, hour)
        field(type, "alarmMinutes").setInt(packet, minute)
        field(type, "alarmSet").setBoolean(packet, enabled)
        field(type, "forceDontRing").setInt(packet, -1)
        val update = type.getDeclaredMethod("updateAlarmClock", IAlarmClock::class.java)
        update.isAccessible = true
        update.invoke(packet, alarm)
    }

    private fun cases(type: Class<*>) {
        var alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        at(alarm, 0, 8, 20)
        require(ringing(alarm), "$type catches skipped ten-minute window")
        val since = field(type, "ringSince").getDouble(alarm)
        at(alarm, 0, 8, 21)
        require(
            field(type, "ringSince").getDouble(alarm) == since,
            "updates must not restart ring timer",
        )
        for (world in booleanArrayOf(false, true)) {
            sync(alarm, world, false, 8, 10, true)
            alarm.update()
            require(
                field(type, "ringSince").getDouble(alarm) == since,
                "unchanged native setting packet preserves active ring",
            )
        }
        at(alarm, 0, 8, 51)
        require(!ringing(alarm), "native timeout retained after catch-up")
        at(alarm, 0, 9, 1)
        require(!ringing(alarm), "timeout must not replay same daily alarm")
        at(alarm, 1, 8, 20)
        require(ringing(alarm), "next daily occurrence still rings")
        alarm.stopRinging()
        at(alarm, 1, 8, 21)
        require(!ringing(alarm), "explicit silence persists")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        at(alarm, 0, 8, 11)
        at(alarm, 1, 8, 20)
        require(
            ringing(alarm) && field(type, "ringSince").getDouble(alarm) == time.getWorldAgeHours(),
            "expired previous-day ring cannot swallow a crossed new daily occurrence",
        )
        alarm = make(type, 7, 10)
        at(alarm, 0, 6, 59)
        at(alarm, 1, 7, 20)
        require(ringing(alarm), "native nights-survived rollover at 07:00 retains catch-up")

        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        sync(alarm, false, false, 8, 10, true)
        at(alarm, 0, 8, 20)
        require(ringing(alarm), "same schedule packet before catch-up must preserve interval")
        sync(alarm, false, true, 0, 0, false)
        alarm.update()
        require(!ringing(alarm), "explicit stop packet silences ring")

        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 11)
        alarm.stopRinging()
        sync(alarm, true, false, 8, 10, true)
        at(alarm, 0, 8, 12)
        require(
            !ringing(alarm),
            "duplicate packet must not retrigger a silenced exact-window alarm",
        )
        sync(alarm, true, false, 8, 10, false)
        sync(alarm, true, false, 8, 10, true)
        alarm.update()
        require(ringing(alarm), "explicit disable then enable can rearm in the current window")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        alarm.setAlarmSet(false)
        at(alarm, 0, 8, 20)
        require(!ringing(alarm), "disabled alarm cannot catch up")
        alarm.setAlarmSet(true)
        at(alarm, 0, 8, 21)
        require(!ringing(alarm), "re-enable does not replay past occurrence")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 20)
        require(!ringing(alarm), "initial observation cannot replay old alarm")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        time.setTimeOfDay(8.5f)
        alarm.setMinute(20)
        at(alarm, 0, 8, 31)
        require(!ringing(alarm), "edit does not apply old observation to a new schedule")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        at(alarm, 0, 7, 50)
        at(alarm, 0, 8, 20)
        require(ringing(alarm), "backward time establishes new baseline")
        alarm = make(type, 0, 0)
        at(alarm, 0, 23, 59)
        at(alarm, 0, 0, 10)
        require(ringing(alarm), "midnight crossing uses monotonic world age")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        at(alarm, 0, 8, 11)
        alarm.stopRinging()
        at(alarm, 0, 8, 9)
        at(alarm, 0, 8, 11)
        require(!ringing(alarm), "backward correction must not forget a silenced daily occurrence")
        alarm = make(type, 8, 15)
        at(alarm, 0, 8, 14)
        at(alarm, 0, 8, 25)
        require(ringing(alarm), "raw minute schedule also catches crossed trigger")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        (alarm as InventoryItem).getContainer().setSourceGrid(null)
        at(alarm, 0, 8, 20)
        require(!ringing(alarm), "unlocated alarm cannot make a detached sound")
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        sync(alarm, true, false, 9, 0, true)
        at(alarm, 0, 9, 10)
        require(!ringing(alarm), "changed packet establishes a new schedule baseline")

        // Exercise the actual native sound callback with its normal sound-start path and hearing
        // guard.
        alarm = make(type, 8, 10)
        at(alarm, 0, 8, 9)
        at(alarm, 0, 8, 20)
        val player = unsafe.allocateInstance(Player::class.java) as Player
        field(zombie.iso.IsoMovingObject::class.java, "current")
            .set(player, (alarm as InventoryItem).getContainer().getSourceGrid())
        IsoPlayer.numPlayers = 1
        IsoPlayer.players[0] = player
        val emitter = Emitter()
        AlarmClockReliability.consume()
        alarm.javaClass
            .getMethod("updateSound", zombie.audio.BaseSoundEmitter::class.java)
            .invoke(alarm, emitter)
        require(
            emitter.played == 1 && AlarmClockReliability.consume(),
            "ordinary native sound start emits one speed-reset event, plays=${emitter.played} square=${player.getCurrentSquare()}",
        )
        alarm.javaClass
            .getMethod("updateSound", zombie.audio.BaseSoundEmitter::class.java)
            .invoke(alarm, emitter)
        require(
            emitter.played == 1 && !AlarmClockReliability.consume(),
            "ongoing ring does not duplicate sound or reset events",
        )
        val source = player.getCurrentSquare()
        player.deaf = true
        require(
            !AlarmClockReliability.inHearingRange(player, source, 40),
            "deaf player cannot hear alarm",
        )
        player.deaf = false
        val distant = unsafe.allocateInstance(IsoGridSquare::class.java) as IsoGridSquare
        distant.x = 41
        require(
            !AlarmClockReliability.inHearingRange(player, distant, 40),
            "distant player cannot hear alarm",
        )
        distant.x = 0
        distant.z = 4
        require(
            !AlarmClockReliability.inHearingRange(player, distant, 40),
            "distant floor cannot hear alarm",
        )
        require(
            !AlarmClockReliability.inHearingRange(null, source, 40),
            "missing player cannot hear alarm",
        )
        IsoPlayer.players[0] = null
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        time = GameTime()
        GameTime.setInstance(time)
        zombie.Lua.LuaManager.platform = se.krka.kahlua.j2se.J2SEPlatform()
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.ZomboidFileSystem.instance.base.set(java.io.File("."))
        zombie.Lua.LuaManager.env = zombie.Lua.LuaManager.platform.newEnvironment()
        zombie.Lua.LuaManager.env.rawset("Events", zombie.Lua.LuaManager.platform.newTable())
        zombie.Lua.LuaManager.thread =
            se.krka.kahlua.vm.KahluaThread(
                zombie.Lua.LuaManager.platform,
                zombie.Lua.LuaManager.env,
            )
        zombie.Lua.LuaManager.thread.debugOwnerThread = Thread.currentThread()
        val converters = se.krka.kahlua.converter.KahluaConverterManager()
        zombie.Lua.LuaManager.caller = se.krka.kahlua.integration.LuaCaller(converters)
        zombie.Lua.LuaManager.exposer =
            zombie.Lua.LuaManager.Exposer(
                converters,
                zombie.Lua.LuaManager.platform,
                zombie.Lua.LuaManager.env,
            )
        GameClient.client = true
        GameServer.server = false
        IsoWorld.instance.currentCell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        field(IsoCell::class.java, "processItems")
            .set(IsoWorld.instance.currentCell, ArrayList<InventoryItem>())
        field(IsoCell::class.java, "processItemsRemove")
            .set(IsoWorld.instance.currentCell, HashSet<InventoryItem>())
        val nativeAlarm = make(AlarmClock::class.java, 8, 10)
        at(nativeAlarm, 0, 8, 9)
        at(nativeAlarm, 0, 8, 20)
        require(!ringing(nativeAlarm), "unpatched positive control must reproduce skipped alarm")
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            AlarmClockChecks::class.java.classLoader,
        )
        require(AlarmClockReliability.SUPPORTED, "native alarm hashes supported")
        require(
            Exposer.getClassesWithGlobalLuaMethod().contains(AlarmClockReliability::class.java),
            "ZombieBuddy discovers Lua bridge",
        )
        Exposer.afterExposeAll()
        val consume = zombie.Lua.LuaManager.env.rawget("toolkitConsumeAlarmRing")
        require(
            consume != null &&
                java.lang.Boolean.FALSE.equals(
                    zombie.Lua.LuaManager.thread.call(consume, arrayOf<Any>()),
                ),
            "Lua bridge exposed with native boolean result",
        )
        cases(AlarmClock::class.java)
        cases(AlarmClockClothing::class.java)
        // The native standalone and server paths must retain world sound production for zombies.
        GameClient.client = false
        IsoPlayer.numPlayers = 0
        GameServer.udpEngine =
            unsafe.allocateInstance(zombie.core.raknet.UdpEngine::class.java)
                as zombie.core.raknet.UdpEngine
        field(zombie.core.raknet.UdpEngine::class.java, "connections")
            .set(GameServer.udpEngine, ArrayList<zombie.core.raknet.UdpConnection>())
        val sounds =
            field(zombie.WorldSoundManager::class.java, "soundList")
                .get(zombie.WorldSoundManager.instance) as List<*>
        for (server in booleanArrayOf(false, true)) {
            GameServer.server = server
            for (type in arrayOf(AlarmClock::class.java, AlarmClockClothing::class.java)) {
                val alarm = make(type, 8, 10)
                val previous = sounds.size
                at(alarm, 0, 8, 9)
                at(alarm, 0, 8, 20)
                require(
                    ringing(alarm) && sounds.size == previous + 1,
                    "standalone/server native world sound survives catch-up: $server $type",
                )
                alarm.stopRinging()
                at(alarm, 0, 8, 21)
                require(
                    !ringing(alarm),
                    "standalone/server stop remains final for daily occurrence",
                )
            }
        }
        GameServer.server = false
        for (type in arrayOf(AlarmClock::class.java, AlarmClockClothing::class.java)) {
            val raw = make(type, 8, 15)
            at(raw, 0, 8, 14)
            at(raw, 0, 8, 15)
            require(ringing(raw), "SP raw-minute native start retained")
            raw.stopRinging()
            at(raw, 0, 8, 15)
            require(!ringing(raw), "SP raw-minute alarm must not retrigger after stop")
            at(raw, 0, 8, 16)
            at(raw, 0, 8, 15)
            require(
                !ringing(raw),
                "SP correction into the trigger minute must retain explicit silence",
            )
        }
        println(
            "ALARM_CLOCK_CHECKS_PASS ($checks checks, both woven native clock classes and setting packets)",
        )
        System.exit(0)
    }
}
