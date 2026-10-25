package net.alexredby.cartlab

import java.lang.reflect.Field
import java.util.ArrayDeque
import java.util.LinkedHashMap
import me.zed_0xff.zombie_buddy.Patch
import net.alexredby.cartlab.Multiplayer.TIMELINE
import net.alexredby.cartlab.Multiplayer.mpJsonString
import net.alexredby.cartlab.Multiplayer.timelineBoundConnectionToken
import net.alexredby.cartlab.Multiplayer.timelineBoundOwner
import net.alexredby.cartlab.Multiplayer.timelineClockConnection
import net.alexredby.cartlab.Multiplayer.timelineClosing
import net.alexredby.cartlab.Multiplayer.timelineError
import net.alexredby.cartlab.Multiplayer.timelineEvent
import net.alexredby.cartlab.Multiplayer.timelineFailed
import net.alexredby.cartlab.Multiplayer.timelineFlushClock
import net.alexredby.cartlab.Multiplayer.timelineOwner
import net.alexredby.cartlab.NativeTime.nativeTimeIdentity
import net.alexredby.cartlab.NativeTime.nativeTimeProcess
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.GameWindow
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes
import zombie.network.packets.INetworkPacket
import zombie.network.packets.service.TimeSyncPacket

/** Explicit disposable experiment only. Ordinary cart_timeline remains passive. */
object ClockTime {
    private val TIME_ALIGNMENT = System.getenv("PZ_CART_TIME_ALIGNMENT") == "true"

    class TimelineClockSchedule {
        private var connection = 0L
        private var actor = 0L
        private var start = 0L
        private var last = 0L
        private var cart = 0
        var count = 0
            private set

        var closed = false
            private set

        private var previousElapsed = -1.0

        fun due(now: Long, endpoint: Long, owner: Long, item: Int, elapsed: Double): Boolean {
            if (closed) return false
            if (
                !elapsed.isFinite() || elapsed < 0 || elapsed > 26000 || endpoint <= 0 || owner <= 0
            ) {
                closed = true
                return false
            }
            if (count == 0) {
                connection = endpoint
                actor = owner
                cart = item
                start = now
            } else if (
                endpoint != connection ||
                    owner != actor ||
                    item != cart ||
                    now < last ||
                    elapsed < previousElapsed
            ) {
                closed = true
                return false
            }
            if (now - start < 0 || now - start > 32_000_000_000L || count >= CAP) {
                closed = true
                return false
            }
            previousElapsed = elapsed
            if (count > 0 && now - last < 2_000_000_000L) return false
            last = now
            count++
            return true
        }

        fun prepared(now: Long) {
            if (count > 0 && !closed) {
                if (now < last) closed = true else last = now
            }
        }

        fun stop() {
            closed = true
        }

        companion object {
            const val CAP = 14
        }
    }

    private val timelineClockSchedule = TimelineClockSchedule()
    private val timelineFixtureClock = ThreadLocal<Boolean>()

    private data class TimelineClockRequest(
        val sent: Long,
        val observed: Long,
        val connection: Long,
        val guid: String,
        val token: Int,
        val ordinal: Long,
        val origin: String,
        val fixtureOrdinal: Int,
    ) {
        fun fields() =
            ",\"nativeProcessEpoch\":${mpJsonString(nativeTimeProcess)},\"clientSendNs\":$sent" +
                ",\"observedMonoNs\":$observed,\"connectionEpoch\":$connection,\"connectionGUID\":${mpJsonString(guid)}" +
                ",\"connectionToken\":$token,\"clockRequestOrdinal\":$ordinal,\"clockRequestOrigin\":${mpJsonString(origin)},\"fixtureRequestOrdinal\":$fixtureOrdinal"
    }

    private data class TimelineClockKey(val connection: Long, val sent: Long)

    private val timelineClockRequests = LinkedHashMap<TimelineClockKey, TimelineClockRequest>()
    private val timelinePendingRequests = ArrayDeque<TimelineClockRequest>()
    private var timelineRequestOrdinal = 0L
    private var timelineRequestDropped = 0
    private var timelineClockClientTimeField: Field? = null

    @JvmStatic fun timelineRequestsPending() = timelinePendingRequests.isNotEmpty()

    @JvmStatic fun initialize() = Unit

    @JvmStatic
    fun timelineClockRequested(packet: TimeSyncPacket?) {
        synchronized(Main::class.java) {
            if (
                !TIMELINE ||
                    timelineClosing ||
                    timelineFailed ||
                    GameServer.server ||
                    !GameClient.client
            )
                return
            try {
                val connection = GameClient.connection ?: return
                val field =
                    timelineClockClientTimeField
                        ?: packet!!.javaClass.getDeclaredField("clientTime").apply {
                            isAccessible = true
                            timelineClockClientTimeField = this
                        }
                val sent = field.getLong(packet)
                val epoch = nativeTimeIdentity(connection, false)
                val fixture = timelineFixtureClock.get() == true
                val request =
                    TimelineClockRequest(
                        sent,
                        System.nanoTime(),
                        epoch,
                        java.lang.Long.toUnsignedString(connection.getConnectedGUID()),
                        System.identityHashCode(connection),
                        ++timelineRequestOrdinal,
                        if (fixture) "fixture" else "native",
                        if (fixture) timelineClockSchedule.count else 0,
                    )
                if (request.fixtureOrdinal > 0) timelineClockSchedule.prepared(sent)
                val key = TimelineClockKey(epoch, sent)
                check(!timelineClockRequests.containsKey(key)) {
                    "Duplicate native TimeSync request identity"
                }
                if (timelineClockRequests.size == 256) {
                    timelineClockRequests.remove(timelineClockRequests.keys.iterator().next())
                    timelineRequestDropped++
                }
                if (timelinePendingRequests.size == 256) {
                    timelinePendingRequests.removeFirst()
                    timelineRequestDropped++
                }
                timelineClockRequests[key] = request
                timelinePendingRequests.addLast(request)
                val owner = timelineBoundOwner?.get()
                if (
                    owner != null &&
                        timelineBoundConnectionToken == System.identityHashCode(connection)
                )
                    timelineFlushClock(owner)
            } catch (error: Throwable) {
                timelineError(error)
            }
        }
    }

    fun timelineClockRequestFields(connection: UdpConnection, sent: Long): String {
        val epoch = nativeTimeIdentity(connection, false)
        val request = timelineClockRequests[TimelineClockKey(epoch, sent)]
        return ",\"nativeProcessEpoch\":${mpJsonString(nativeTimeProcess)},\"clockRequestConnectionEpoch\":$epoch" +
            ",\"clockRequestObserved\":${request != null},\"clockRequestOrdinal\":${request?.ordinal ?: 0}" +
            ",\"clockRequestOrigin\":${mpJsonString(request?.origin ?: "unobserved")},\"clockRequestDropped\":$timelineRequestDropped"
    }

    fun timelineFlushRequests(owner: IsoPlayer) {
        while (timelinePendingRequests.isNotEmpty()) {
            timelineEvent(
                "clock-request",
                owner,
                timelinePendingRequests.removeFirst().fields() +
                    ",\"clockRequestDropped\":$timelineRequestDropped",
            )
        }
    }

    @Patch(
        className = "zombie.network.packets.service.TimeSyncPacket",
        methodName = "setData",
        warmUp = true,
    )
    object TimelineClockRequestStamp {
        @JvmStatic
        @Patch.OnExit(suppress = Throwable::class)
        fun exit(@Patch.This packet: TimeSyncPacket) {
            timelineClockRequested(packet)
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartMPTimingSample", global = true)
    fun timelineSampleClock(owner: IsoPlayer?, cart: Int, elapsed: Double): Boolean {
        if (!TIME_ALIGNMENT) return false
        if (timelineClosing || timelineFailed) {
            timelineClockSchedule.stop()
            return false
        }
        val self = IsoPlayer.getInstance()
        val connection = GameClient.connection
        if (
            !TIMELINE ||
                GameServer.server ||
                !GameClient.client ||
                connection == null ||
                !GameClient.instance.connected ||
                self == null ||
                !self.isLocalPlayer() ||
                (self.getUsername() != "client1" && self.getUsername() != "client2") ||
                Thread.currentThread() !== GameWindow.gameThread ||
                timelineClockConnection.get() != null ||
                !timelineOwner(owner) ||
                owner == null ||
                owner.isDead() ||
                owner.getPrimaryHandItem() == null ||
                owner.getPrimaryHandItem().getID() != cart ||
                owner.getSecondaryHandItem() !== owner.getPrimaryHandItem()
        ) {
            timelineClockSchedule.stop()
            error("Owned game-thread cart timing fixture required")
        }
        val requestAt = System.nanoTime()
        if (
            !timelineClockSchedule.due(
                requestAt,
                nativeTimeIdentity(connection, false),
                nativeTimeIdentity(owner, true),
                cart,
                elapsed,
            )
        )
            return false
        timelineEvent(
            "clock-experiment-request",
            owner,
            ",\"fixtureRequestOrdinal\":${timelineClockSchedule.count},\"fixtureRequestMonoNs\":$requestAt,\"fixtureRequestCap\":${TimelineClockSchedule.CAP},\"fixtureElapsedMs\":$elapsed" +
                ",\"nativeProcessEpoch\":${mpJsonString(nativeTimeProcess)},\"connectionEpoch\":${nativeTimeIdentity(connection, false)}",
        )
        if (timelineFailed) return false
        timelineFixtureClock.set(true)
        try {
            INetworkPacket.send(connection, PacketTypes.PacketType.TimeSync)
        } finally {
            timelineFixtureClock.remove()
        }
        return true
    }
}
