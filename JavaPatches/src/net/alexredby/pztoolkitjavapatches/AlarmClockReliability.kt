package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.util.WeakHashMap
import me.zed_0xff.zombie_buddy.Accessor
import me.zed_0xff.zombie_buddy.Patch
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.GameTime
import zombie.characters.IsoPlayer
import zombie.inventory.types.AlarmClock
import zombie.inventory.types.AlarmClockClothing
import zombie.inventory.types.IAlarmClock
import zombie.iso.IsoGridSquare
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.scripting.objects.CharacterTrait

/**
 * Crossed alarms use the native ring path; observation never replays alarms from before loading.
 */
object AlarmClockReliability {
    @JvmField
    val SUPPORTED =
        BytecodeSupport.supports(
            "zombie/inventory/types/AlarmClock.class",
            "9193244fadff85e58581b4797e82187b5112c32e90fa0cca3e27f84f8c9a2da4",
        ) &&
            BytecodeSupport.supports(
                "zombie/inventory/types/AlarmClockClothing.class",
                "cb899fa6d4ec65440b94ff28ae83c328a4cd8422f1a88efb4df3c5a17d397568",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/SyncPlayerAlarmClockPacket.class",
                "112d7875262f824d1a2b0bd3f1a313258720cbbe37aeec6b5d9a092bf8f89e4a",
            ) &&
            BytecodeSupport.supports(
                "zombie/network/packets/SyncWorldAlarmClockPacket.class",
                "3aba27b34c0eea9fe62af6e61e8a8012067f48ec5fef8408cd041dc931f9e4cb",
            )
    private val states = WeakHashMap<IAlarmClock, State>()
    private var heard = false

    private class State(var previous: Double) {
        var handled = Double.NEGATIVE_INFINITY
        var audible = Double.NaN
    }

    private fun now(): Double = GameTime.getInstance().getWorldAgeHours()

    private fun due(alarm: IAlarmClock, now: Double): Double {
        val result =
            now - GameTime.getInstance().getTimeOfDay() + alarm.getHour() + alarm.getMinute() / 60.0
        return if (result > now) result - 24 else result
    }

    private fun valid(alarm: IAlarmClock?): Boolean =
        alarm != null &&
            alarm.getHour() >= 0 &&
            alarm.getHour() < 24 &&
            alarm.getMinute() >= 0 &&
            alarm.getMinute() < 60

    private fun field(alarm: IAlarmClock, name: String): Field =
        Accessor.findField(alarm.javaClass, name)

    private fun since(alarm: IAlarmClock): Double =
        Accessor.tryGet(alarm, field(alarm, "ringSince"), -1.0)

    private fun setSince(alarm: IAlarmClock, value: Double) {
        try {
            field(alarm, "ringSince").setDouble(alarm, value)
        } catch (error: IllegalAccessException) {
            throw IllegalStateException(error)
        }
    }

    private fun square(alarm: IAlarmClock): IsoGridSquare? =
        when (alarm) {
            is AlarmClock -> alarm.getAlarmSquare()
            is AlarmClockClothing -> alarm.getAlarmSquare()
            else -> null
        }

    @JvmStatic
    fun before(alarm: IAlarmClock?) {
        if (!SUPPORTED || alarm == null || !valid(alarm)) return
        val now = now()
        if (!java.lang.Double.isFinite(now)) return
        val state = states[alarm]
        if (!alarm.isAlarmSet() || state == null) {
            states[alarm] = State(now)
            return
        }
        if (now < state.previous) {
            // Time corrections start a new observation interval without forgetting a completed
            // ring.
            state.previous = now
        }
        val due = due(alarm, now)
        val started = since(alarm)
        if (started < 0 && due <= state.handled) {
            // Native setting packets otherwise clear the same-window stop guard and retrigger it.
            var minute = GameTime.getInstance().getMinutes()
            if (GameClient.client || GameServer.server) minute = minute / 10 * 10
            alarm.setForceDontRing(minute)
        } else if (
            (started < 0 || now > started + 0.5) &&
                due > state.handled &&
                due > state.previous &&
                square(alarm) != null
        ) {
            setSince(alarm, now)
            state.handled = due
            if (GameServer.server) {
                if (alarm is AlarmClock) alarm.syncAlarmClock()
                else (alarm as AlarmClockClothing).syncAlarmClock()
            }
        }
        state.previous = now
    }

    @JvmStatic
    fun after(alarm: IAlarmClock?) {
        if (!SUPPORTED || alarm == null || !valid(alarm)) return
        val state = states[alarm]
        if (state != null && since(alarm) >= 0) {
            state.handled = Math.max(state.handled, due(alarm, now()))
        }
    }

    @JvmStatic
    fun stop(alarm: IAlarmClock?) {
        if (!SUPPORTED || alarm == null || !valid(alarm)) return
        val state = states[alarm]
        if (state != null) {
            state.previous = now()
            if (since(alarm) >= 0) state.handled = Math.max(state.handled, due(alarm, now()))
            state.audible = Double.NaN
        }
    }

    @JvmStatic
    fun configure(alarm: IAlarmClock?) {
        if (SUPPORTED) states.remove(alarm)
    }

    // A setting packet with the same schedule carries no new configuration or ring timestamp.
    // Running its setters would silence the ring and erase the interval needed for catch-up.
    @JvmStatic
    fun unchangedSync(packet: Any?, alarm: IAlarmClock?): Boolean =
        SUPPORTED &&
            alarm != null &&
            valid(alarm) &&
            states.containsKey(alarm) &&
            !Accessor.tryGet(packet, "stopRinging", true) &&
            Accessor.tryGet(packet, "alarmSet", false) == alarm.isAlarmSet() &&
            Accessor.tryGet(packet, "alarmHour", -1) == alarm.getHour() &&
            Accessor.tryGet(packet, "alarmMinutes", -1) == alarm.getMinute()

    @JvmStatic
    fun inHearingRange(player: IsoPlayer?, source: IsoGridSquare, radius: Int): Boolean {
        if (
            player == null ||
                player.isDead() ||
                player.getCurrentSquare() == null ||
                player.hasTrait(CharacterTrait.DEAF)
        )
            return false
        val target = player.getCurrentSquare()
        if (target.z < Math.max(source.z - 3, -32) || target.z >= Math.min(source.z + 3, 31))
            return false
        val dx = (source.x - target.x).toDouble()
        val dy = (source.y - target.y).toDouble()
        val hearing = player.getHearDistanceModifier().toDouble()
        return (dx * dx + dy * dy) * hearing * hearing <= radius.toDouble() * radius
    }

    @JvmStatic
    fun sound(alarm: IAlarmClock) {
        if (!SUPPORTED || GameServer.server || since(alarm) < 0) return
        val state = states[alarm]
        if (state == null || state.audible == since(alarm)) return
        val source = square(alarm) ?: return
        val radius =
            if (alarm is AlarmClock) alarm.getSoundRadius()
            else (alarm as AlarmClockClothing).getSoundRadius()
        for (i in 0 until IsoPlayer.numPlayers) {
            if (inHearingRange(IsoPlayer.players[i], source, radius)) {
                state.audible = since(alarm)
                heard = true
                return
            }
        }
    }

    @JvmStatic
    @LuaMethod(name = "toolkitConsumeAlarmRing", global = true)
    fun consume(): Boolean {
        val value = SUPPORTED && heard
        heard = false
        return value
    }

    @Patch(className = "zombie.inventory.types.AlarmClock", methodName = "update", warmUp = true)
    object ClockUpdate {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClock) {
            before(alarm)
        }

        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This alarm: AlarmClock) {
            after(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClockClothing",
        methodName = "update",
        warmUp = true,
    )
    object WatchUpdate {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClockClothing) {
            before(alarm)
        }

        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This alarm: AlarmClockClothing) {
            after(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClock",
        methodName = "stopRinging",
        warmUp = true,
    )
    object ClockStop {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClock) {
            stop(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClockClothing",
        methodName = "stopRinging",
        warmUp = true,
    )
    object WatchStop {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClockClothing) {
            stop(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClock",
        methodName = "setAlarmSet",
        warmUp = true,
    )
    object ClockEnabled {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClock) {
            configure(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClockClothing",
        methodName = "setAlarmSet",
        warmUp = true,
    )
    object WatchEnabled {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClockClothing) {
            configure(alarm)
        }
    }

    @Patch(className = "zombie.inventory.types.AlarmClock", methodName = "setHour", warmUp = true)
    object ClockHour {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClock) {
            configure(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClockClothing",
        methodName = "setHour",
        warmUp = true,
    )
    object WatchHour {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClockClothing) {
            configure(alarm)
        }
    }

    @Patch(className = "zombie.inventory.types.AlarmClock", methodName = "setMinute", warmUp = true)
    object ClockMinute {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClock) {
            configure(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClockClothing",
        methodName = "setMinute",
        warmUp = true,
    )
    object WatchMinute {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This alarm: AlarmClockClothing) {
            configure(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClock",
        methodName = "updateSound",
        warmUp = true,
    )
    object ClockSound {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This alarm: AlarmClock) {
            sound(alarm)
        }
    }

    @Patch(
        className = "zombie.inventory.types.AlarmClockClothing",
        methodName = "updateSound",
        warmUp = true,
    )
    object WatchSound {
        @JvmStatic
        @Patch.OnExit
        fun exit(@Patch.This alarm: AlarmClockClothing) {
            sound(alarm)
        }
    }

    @Patch(
        className = "zombie.network.packets.SyncPlayerAlarmClockPacket",
        methodName = "updateAlarmClock",
        warmUp = true,
    )
    object PlayerSync {
        @JvmStatic
        @Patch.OnEnter(skipOn = true)
        fun enter(@Patch.This packet: Any?, @Patch.Argument(0) alarm: IAlarmClock?): Boolean =
            unchangedSync(packet, alarm)
    }

    @Patch(
        className = "zombie.network.packets.SyncWorldAlarmClockPacket",
        methodName = "updateAlarmClock",
        warmUp = true,
    )
    object WorldSync {
        @JvmStatic
        @Patch.OnEnter(skipOn = true)
        fun enter(@Patch.This packet: Any?, @Patch.Argument(0) alarm: IAlarmClock?): Boolean =
            unchangedSync(packet, alarm)
    }
}
