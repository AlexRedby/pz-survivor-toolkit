import net.alexredby.cartlab.ClockTime.TimelineClockSchedule

object ClockTimeCheck {
    @JvmStatic
    fun main(args: Array<String>) {
        val schedule = TimelineClockSchedule()
        check(schedule.due(100, 1, 2, 42, 0.0)) { "First request" }
        repeat(1000) { check(!schedule.due(101L + it, 1, 2, 42, it / 1000.0)) { "Tick spam" } }
        check(schedule.due(2_000_000_100, 1, 2, 42, 2000.0)) { "Minimum spacing" }
        check(!schedule.due(4_000_000_100, 3, 2, 42, 4000.0) && schedule.closed) {
            "Connection fence"
        }
        check(!schedule.due(6_000_000_100, 1, 2, 42, 6000.0)) { "No old epoch revival" }
        repeat(4) { changed ->
            val subject = TimelineClockSchedule()
            check(subject.due(100, 1, 2, 42, 0.0))
            check(
                !subject.due(
                    if (changed == 3) 99 else 2_000_000_100,
                    1,
                    if (changed == 0) 3 else 2,
                    if (changed == 1) 43 else 42,
                    if (changed == 2) -1.0 else 2000.0,
                ),
            ) {
                "Actor/cart/time fence"
            }
            check(subject.closed) { "Terminal fence" }
        }
        val delayed = TimelineClockSchedule()
        check(delayed.due(100, 1, 2, 42, 0.0))
        delayed.prepared(1_000_000_100)
        check(!delayed.due(2_000_000_100, 1, 2, 42, 2000.0)) { "Actual prepared timestamp spacing" }
        check(delayed.due(3_000_000_100, 1, 2, 42, 3000.0)) { "Spacing after actual preparation" }
        val cap = TimelineClockSchedule()
        repeat(14) {
            check(cap.due(it * 2_000_000_000L, 1, 2, 42, it * 2000.0)) { "Finite cap input" }
        }
        check(!cap.due(28_000_000_000, 1, 2, 42, 26000.0) && cap.count == 14) { "Finite cap" }
        val deadline = TimelineClockSchedule()
        check(deadline.due(100, 1, 2, 42, 0.0))
        check(!deadline.due(33_000_000_100, 1, 2, 42, 1000.0)) { "Monotonic deadline" }
        val invalid = TimelineClockSchedule()
        check(!invalid.due(100, 1, 2, 42, Double.NaN) && invalid.closed) {
            "Nonfinite experiment input"
        }
        val scope =
            zombie.network.packets.INetworkPacket::class
                .java
                .getDeclaredMethod(
                    "send",
                    zombie.network.IConnection::class.java,
                    zombie.network.PacketTypes.PacketType::class.java,
                    Array<Any>::class.java,
                )
        check(java.lang.reflect.Modifier.isStatic(scope.modifiers)) {
            "Native explicit connection API"
        }
        zombie.network.packets.service.TimeSyncPacket::class.java.getDeclaredField("clientTime")
        zombie.GameWindow::class.java.getDeclaredField("gameThread")
        println("CLOCK_TIME_CHECK_PASS")
    }
}
