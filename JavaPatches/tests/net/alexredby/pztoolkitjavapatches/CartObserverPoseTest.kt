package net.alexredby.pztoolkitjavapatches

import net.alexredby.pztoolkitjavapatches.CartFootprint.Query

object CartObserverPoseTest {
    private fun check(yes: Boolean, message: String) {
        if (!yes) throw AssertionError(message)
    }

    private fun near(actual: Number, expected: Number, tolerance: Double, message: String) {
        check(
            Math.abs(actual.toDouble() - expected.toDouble()) <= tolerance,
            "$message: $actual vs $expected",
        )
    }

    private fun valid(
        state: CartObserverPose.State,
        query: Query,
        x: Number,
        y: Number,
        heading: Number,
        front: Double,
    ): CartObserverPose.Pose {
        val pose =
            state.update(query, x.toDouble(), y.toDouble(), heading.toDouble(), front, 1.0 / 60)
                ?: throw AssertionError(
                    "bounded clear pose must exist: $x,$y heading=$heading front=$front",
                )
        check(
            CartFootprint.clear(query, pose.x, pose.y, pose.heading, front),
            "accepted pose intersects obstacle",
        )
        check(
            Math.hypot(pose.x - x.toFloat(), pose.y - y.toFloat()) <= CartObserverPose.MAX_OFFSET,
            "unbounded visual displacement",
        )
        return pose
    }

    private fun historicalPrediction() {
        // Native Host left-wall captures: position-dominated and yaw-dominated overreach.
        for (sample in
            arrayOf(
                doubleArrayOf(10832.752, 10146.532, 3.914688),
                doubleArrayOf(10832.313, 10147.547, 3.4634652),
            )) {
            val wall = Query { x1, _, x2, _ -> Math.min(x1, x2) - .3 <= 10832 }
            val heading = sample[2] - Math.PI / 2
            check(
                !CartFootprint.clear(
                    wall,
                    sample[0].toFloat().toDouble(),
                    sample[1].toFloat().toDouble(),
                    heading,
                    CartFootprint.WALK_FRONT,
                ),
                "saved native pose must reproduce penetration",
            )
            val pose =
                valid(
                    CartObserverPose.State(),
                    wall,
                    sample[0],
                    sample[1],
                    heading,
                    CartFootprint.WALK_FRONT,
                )
            check(
                pose.x > sample[0],
                "left wall correction must move the complete actor away from wall",
            )
            near(pose.y, sample[1].toFloat(), .001, "wall correction must not add tangent movement")
            near(
                pose.heading,
                heading,
                1e-9,
                "initial overlap must preserve observed heading where translation suffices",
            )
        }
    }

    private fun mirroredApproachAndRelease() {
        for (origin in doubleArrayOf(0.0, 8192.0, 10825.5, 16384.0)) for (normal in
            intArrayOf(-1, 1)) {
            val wall = Query { x1, _, x2, _ ->
                Math.max(normal * (x1 - origin), normal * (x2 - origin)) + .3 >= 2
            }
            val state = CartObserverPose.State()
            val front = CartFootprint.WALK_FRONT
            val heading = if (normal > 0) Math.PI / 4 else 3 * Math.PI / 4
            for (frame in 0 until 90) valid(
                state,
                wall,
                origin + normal * (.5 + frame * .009),
                origin + frame * .012,
                heading,
                front,
            )
            val x = origin + normal * 1.301
            val y = origin + 1.068
            val contact = valid(state, wall, x, y, heading, front)
            var pose = contact
            repeat(120) {
                pose = valid(state, wall, x, y, heading, front)
                near(pose.x, contact.x, .004, "stationary contact must not oscillate")
                near(pose.y, contact.y, .004, "stationary contact must not drift sideways")
            }
            // Manual reverse releases the retained offset gradually.
            var lastOffset = Math.abs(pose.x - x.toFloat())
            check(lastOffset > .15, "test must exercise a material correction")
            for (frame in 1..180) {
                val retreat = x - normal * frame * .015
                pose = valid(state, wall, retreat, y, heading, front)
                val offset = Math.abs(pose.x - retreat.toFloat())
                check(
                    offset <= lastOffset + .004,
                    "release must decay monotonically within world-coordinate precision",
                )
                check(
                    lastOffset - offset < .065,
                    "release must not discard correction in one frame",
                )
                lastOffset = offset
            }
            check(lastOffset < .005, "clearance correction must release after leaving wall")
        }
    }

    private fun cornersAndChanges() {
        for (sx in intArrayOf(-1, 1)) for (sy in intArrayOf(-1, 1)) {
            val corner = Query { x1, y1, x2, y2 ->
                Math.max(sx * x1, sx * x2) + .3 >= 2 || Math.max(sy * y1, sy * y2) + .3 >= 2
            }
            val heading = Math.atan2(sy.toDouble(), sx.toDouble())
            val pose =
                valid(
                    CartObserverPose.State(),
                    corner,
                    sx * 1.2,
                    sy * 1.2,
                    heading,
                    CartFootprint.WALK_FRONT,
                )
            check(
                sx * pose.x < 1.2 && sy * pose.y < 1.2,
                "every corner quadrant needs joint outward correction",
            )
        }
        var closed = false
        val changed = Query { x1, _, x2, _ -> closed && Math.max(x1, x2) + .3 >= 2 }
        val state = CartObserverPose.State()
        valid(state, changed, 1, 0, 0, CartFootprint.WALK_FRONT)
        closed = true
        valid(state, changed, 1, 0, 0, CartFootprint.WALK_FRONT)
        valid(state, changed, 1, 0, 0, CartFootprint.FAST_FRONT)
        state.clear()
        var raw = valid(state, Query { _, _, _, _ -> false }, 1, 0, 0, CartFootprint.WALK_FRONT)
        near(raw.x, 1, 0.0, "reset must discard previous item/connection correction")
        check(
            state.update(
                Query { _, _, _, _ -> true },
                1.0,
                0.0,
                0.0,
                CartFootprint.WALK_FRONT,
                .016,
            ) == null,
            "fully obstructed region must fail bounded, not teleport to distant clearance",
        )
        raw = valid(state, Query { _, _, _, _ -> false }, 40, 50, 1, CartFootprint.WALK_FRONT)
        near(raw.x, 40, 0.0, "failed solve must not retain stale anchor")
        check(
            state.update(changed, Double.NaN, 0.0, 0.0, CartFootprint.WALK_FRONT, .016) == null,
            "invalid coordinate must clear state",
        )
    }

    private fun releaseRateBound() {
        for (origin in doubleArrayOf(0.0, 10825.5)) for (dt in
            doubleArrayOf(0.0, 1.0 / 120, 1.0 / 60, .049, .1, .25)) {
            val wall = Query { x1, _, x2, _ -> Math.max(x1 - origin, x2 - origin) + .3 >= 2 }
            val state = CartObserverPose.State()
            var x = origin + 1
            var y = origin
            val initial = valid(state, wall, x, y, 0, CartFootprint.WALK_FRONT)
            var before = Math.hypot(initial.x - x.toFloat(), initial.y - y.toFloat())
            repeat(5) {
                // Limit only cosmetic release; native travel is unrestricted.
                x += .02
                y += .01
                val pose =
                    state.update(
                        Query { _, _, _, _ -> false },
                        x,
                        y,
                        0.0,
                        CartFootprint.WALK_FRONT,
                        dt,
                    ) ?: throw AssertionError("release lost clear pose")
                val after = Math.hypot(pose.x - x.toFloat(), pose.y - y.toFloat())
                val tolerance =
                    2 *
                        Math.hypot(
                            Math.ulp(x.toFloat()).toDouble(),
                            Math.ulp(y.toFloat()).toDouble(),
                        ) + 1e-6
                check(
                    before - after <= CartObserverPose.RELEASE_SPEED * Math.min(dt, .1) + tolerance,
                    "free visual correction released faster than cap at dt=$dt origin=$origin",
                )
                check(after <= before + tolerance, "free release must not grow correction")
                before = after
            }
        }
    }

    private fun nativePredictedActorOverlap() {
        val wall = Query { x1, _, x2, _ -> Math.min(x1, x2) - .3 <= 10832 }
        val nativeFrames =
            arrayOf(
                doubleArrayOf(10832.345, 10146.881, 3.4556804),
                doubleArrayOf(10832.325, 10146.906, 3.4556746),
                doubleArrayOf(10832.296, 10146.944, 3.4556704),
                doubleArrayOf(10832.296, 10146.969, 3.455669),
                doubleArrayOf(10832.284, 10147.002, 3.455668),
                doubleArrayOf(10832.284, 10147.033, 3.4556675),
                doubleArrayOf(10832.291, 10147.07, 3.379479),
                doubleArrayOf(10832.309, 10147.125, 3.2449832),
                doubleArrayOf(10832.319, 10147.181, 3.1865268),
            )
        val state = CartObserverPose.State()
        var previous: CartObserverPose.Pose? = null
        for (frame in nativeFrames) {
            val pose =
                valid(
                    state,
                    wall,
                    frame[0],
                    frame[1],
                    frame[2] - Math.PI / 2,
                    CartFootprint.WALK_FRONT,
                )
            if (previous != null)
                check(
                    Math.hypot(pose.x - previous.x, pose.y - previous.y) < .16,
                    "predicted actor-cap overlap must not drop the correction or jump back",
                )
            previous = pose
        }
        valid(
            CartObserverPose.State(),
            wall,
            10832.284,
            10147.033,
            3.4556675 - Math.PI / 2,
            CartFootprint.WALK_FRONT,
        )
        val finite = Query { x1, _, x2, _ -> Math.min(x1, x2) <= .3 && Math.max(x1, x2) >= -.3 }
        state.clear()
        valid(state, Query { _, _, _, _ -> false }, .31, 0, 0, CartFootprint.WALK_FRONT)
        val pose = valid(state, finite, -.284, 0, Math.PI, CartFootprint.WALK_FRONT)
        check(pose.x < -.3, "local recovery must discard an old anchor across a newly closed wall")
        check(
            CartObserverPose.State()
                .update(finite, 0.0, 0.0, 0.0, CartFootprint.WALK_FRONT, .016) == null,
            "deep actor overlap has no justified same-side anchor and must fail bounded",
        )
    }

    private fun rotatedContact() {
        for (origin in doubleArrayOf(0.0, 10825.5)) for (angle in
            doubleArrayOf(Math.PI / 6, Math.PI / 4, -Math.PI / 4)) {
            val nx = -Math.sin(angle)
            val ny = Math.cos(angle)
            val contact =
                object : Query {
                    override fun blocked(x1: Double, y1: Double, x2: Double, y2: Double): Boolean =
                        Math.max(
                            (x1 - origin) * nx + (y1 - origin) * ny,
                            (x2 - origin) * nx + (y2 - origin) * ny,
                        ) + .3 >= 2

                    override fun tangent(axis: Int): Double =
                        if (axis < 2) super<Query>.tangent(axis)
                        else angle + (axis - 2) * Math.PI / 2
                }
            for (front in doubleArrayOf(CartFootprint.WALK_FRONT, CartFootprint.FAST_FRONT)) {
                val pose =
                    valid(
                        CartObserverPose.State(),
                        contact,
                        origin + nx * 1.1,
                        origin + ny * 1.1,
                        angle + Math.PI / 2,
                        front,
                    )
                check(
                    (pose.x - origin) * nx + (pose.y - origin) * ny < 1.1,
                    "rotated contact must correct along real hull normal",
                )
            }
        }
    }

    private fun stationaryCostAndOpening() {
        var calls = 0
        var closed = true
        val wall = Query { x1, _, x2, _ ->
            calls++
            closed && Math.min(x1, x2) - .3 <= 10832
        }
        val state = CartObserverPose.State()
        val x = 10832.752
        val y = 10146.532
        val heading = 3.914688 - Math.PI / 2
        val first = valid(state, wall, x, y, heading, CartFootprint.WALK_FRONT)
        repeat(30) {
            calls = 0
            val pose = valid(state, wall, x, y, heading, CartFootprint.WALK_FRONT)
            near(pose.x, first.x, .004, "stationary revalidation retains contact")
            check(calls < 40, "stationary contact must not repeat full projection search: $calls")
        }
        closed = false
        var pose = first
        repeat(90) { pose = valid(state, wall, x, y, heading, CartFootprint.WALK_FRONT) }
        near(pose.x, x.toFloat(), .005, "opening geometry releases an unchanged native pose")
    }

    private fun finiteWallCannotSwapSides() {
        val wall = Query { x1, _, x2, _ -> Math.min(x1, x2) <= .3 && Math.max(x1, x2) >= -.3 }
        val state = CartObserverPose.State()
        check(
            state.update(wall, .31, 0.0, Math.PI, CartFootprint.WALK_FRONT, 1.0 / 60) == null,
            "bounded projection must not jump actor through a thin wall to its nearer clear side",
        )
        var pose = valid(state, wall, .7, 0, Math.PI, CartFootprint.WALK_FRONT)
        check(pose.x > .7, "reachable-side correction must retreat on original side of finite wall")
        state.clear()
        valid(state, Query { _, _, _, _ -> false }, .31, 0, 0, CartFootprint.WALK_FRONT)
        pose = valid(state, wall, -.31, 0, Math.PI, CartFootprint.WALK_FRONT)
        near(
            pose.x,
            (-.31).toFloat(),
            0.0,
            "new obstacle must discard an old anchor across it, even within the offset limit",
        )
    }

    private fun turningAndFreeMotion() {
        val wall = Query { x1, _, x2, _ -> Math.max(x1, x2) + .3 >= 2 }
        val state = CartObserverPose.State()
        valid(state, wall, 1.5, 0, Math.PI / 2, CartFootprint.WALK_FRONT)
        for (frame in 1..60) valid(
            state,
            wall,
            1.5,
            frame * .01,
            Math.PI / 2 - frame * .012,
            CartFootprint.WALK_FRONT,
        )
        for (frame in 0 until 120) {
            val x = -5 + frame * .02
            val y = frame * .01
            val heading = CartSteeringMath.wrap(3 + frame * .02)
            val pose =
                valid(state, Query { _, _, _, _ -> false }, x, y, heading, CartFootprint.WALK_FRONT)
            near(pose.x, x.toFloat(), 0.0, "free native motion must stay unchanged")
            near(pose.y, y.toFloat(), 0.0, "free native motion must stay unchanged")
            near(pose.heading, heading, 1e-9, "angle wrap must preserve native facing")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        historicalPrediction()
        mirroredApproachAndRelease()
        cornersAndChanges()
        finiteWallCannotSwapSides()
        stationaryCostAndOpening()
        rotatedContact()
        nativePredictedActorOverlap()
        releaseRateBound()
        turningAndFreeMotion()
        println("CART_OBSERVER_POSE_PASS")
    }
}
