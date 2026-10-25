import java.lang.management.ManagementFactory
import java.lang.management.ThreadInfo
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.LockSupport
import net.alexredby.cartlab.ClockTime
import net.alexredby.cartlab.Main
import net.alexredby.cartlab.Multiplayer
import net.alexredby.cartlab.NativeTime
import net.alexredby.cartlab.ObserverParams
import sun.misc.Unsafe
import zombie.network.packets.service.TimeSyncPacket

/** The former Main fragments must still serialize through the original Main class monitor. */
object ModuleMonitorCheck {
    private const val TIMEOUT_SECONDS = 5L
    private val threads = ManagementFactory.getThreadMXBean()

    @JvmStatic
    fun main(args: Array<String>) {
        check(System.getenv("PZ_CART_TIMELINE") != "true") { "Timeline must be disabled" }
        check(System.getenv("PZ_CART_OBSERVER_ASSOCIATION") != "true") {
            "Observer association must be disabled"
        }
        // Initialize every owner before observing contention, so class initialization cannot be
        // mistaken for entrypoint serialization.
        for (type in
            arrayOf(
                Main::class.java,
                Multiplayer::class.java,
                ClockTime::class.java,
                ObserverParams::class.java,
            )) {
            Class.forName(type.name, true, type.classLoader)
        }
        val unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").run {
                isAccessible = true
                get(null) as Unsafe
            }
        val packet = unsafe.allocateInstance(TimeSyncPacket::class.java) as TimeSyncPacket
        blocksOnMain("timelineStop") { Multiplayer.timelineStop() }
        blocksOnMain("timelineClockRequested") { ClockTime.timelineClockRequested(packet) }
        blocksOnMain("observerParamsComponent") {
            ObserverParams.observerParamsComponent(null, null)
        }
        weakMapKeepsItsOwnMonitor()
        println(
            "MODULE_MONITOR_CHECK_PASS: three module entrypoints share Main.class; weak map remains independent",
        )
    }

    private fun blocksOnMain(name: String, action: () -> Unit) {
        val started = CountDownLatch(1)
        val completed = CountDownLatch(1)
        val failure = AtomicReference<Throwable>()
        val worker =
            Thread(
                    {
                        started.countDown()
                        try {
                            action()
                        } catch (error: Throwable) {
                            failure.set(error)
                        } finally {
                            completed.countDown()
                        }
                    },
                    "module-monitor-$name",
                )
                .apply { isDaemon = true }
        val owner = Thread.currentThread().threadId()
        val monitor = Main::class.java
        val observed: ThreadInfo?
        try {
            observed =
                synchronized(monitor) {
                    worker.start()
                    check(started.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                        "$name did not start"
                    }
                    val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(TIMEOUT_SECONDS)
                    var info: ThreadInfo?
                    do {
                        info = threads.getThreadInfo(worker.threadId())
                        if (info?.threadState == Thread.State.BLOCKED || completed.count == 0L)
                            break
                        LockSupport.parkNanos(100_000L)
                    } while (System.nanoTime() < deadline)
                    info
                }
        } finally {
            worker.join(TimeUnit.SECONDS.toMillis(TIMEOUT_SECONDS))
        }
        check(!worker.isAlive && completed.count == 0L) {
            "$name did not finish after Main was released"
        }
        failure.get()?.let { throw AssertionError("$name failed after Main was released", it) }
        check(
            observed?.threadState == Thread.State.BLOCKED &&
                observed.lockOwnerId == owner &&
                observed.lockInfo?.identityHashCode == System.identityHashCode(monitor),
        ) {
            "$name did not block on the held Main.class monitor: $observed"
        }
    }

    private fun weakMapKeepsItsOwnMonitor() {
        val map = NativeTime.NativeWeakMap<Any, Long>()
        val key = Any()
        val completed = CountDownLatch(1)
        val failure = AtomicReference<Throwable>()
        val worker =
            Thread(
                    {
                        try {
                            map.put(key, 7L)
                        } catch (error: Throwable) {
                            failure.set(error)
                        } finally {
                            completed.countDown()
                        }
                    },
                    "module-monitor-weak-map",
                )
                .apply { isDaemon = true }
        val independent: Boolean
        try {
            independent =
                synchronized(Main::class.java) {
                    worker.start()
                    completed.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)
                }
        } finally {
            worker.join(TimeUnit.SECONDS.toMillis(TIMEOUT_SECONDS))
        }
        check(!worker.isAlive) { "Weak map operation did not finish" }
        failure.get()?.let { throw AssertionError("Weak map operation failed", it) }
        check(independent && map.get(key) == 7L) {
            "Weak map incorrectly shares Main.class monitor"
        }
    }
}
