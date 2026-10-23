package net.alexredby.pztoolkitjavapatches

import zombie.pathfind.VehiclePoly

object CartFootprintTest {
    private fun check(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun hull(angle: Double, length: Double, offset: Double): VehiclePoly {
        val p = VehiclePoly()
        val tx = Math.cos(angle)
        val ty = Math.sin(angle)
        val nx = ty
        val ny = -tx
        p.x1 = (-tx * length + nx * offset).toFloat()
        p.y1 = (-ty * length + ny * offset).toFloat()
        p.x2 = (tx * length + nx * offset).toFloat()
        p.y2 = (ty * length + ny * offset).toFloat()
        p.x3 = (tx * length + nx * (offset + 2)).toFloat()
        p.y3 = (ty * length + ny * (offset + 2)).toFloat()
        p.x4 = (-tx * length + nx * (offset + 2)).toFloat()
        p.y4 = (-ty * length + ny * (offset + 2)).toFloat()
        p.borders[0].set(p.x1, p.y1)
        p.borders[1].set(p.x2, p.y2)
        p.borders[2].set(p.x3, p.y3)
        p.borders[3].set(p.x4, p.y4)
        return p
    }

    private fun vehicleChecks(axle: Double) {
        val p = hull(0.0, 2.0, 0.0)
        check(
            CartFootprint.vehicleBlocked(p, 0.0, -1.0, 0.0, -1.0),
            "stationary point inside a vehicle must collide",
        )
        check(
            CartFootprint.vehicleBlocked(p, -1.0, -1.0, 1.0, -1.0),
            "segment wholly inside a hull must collide",
        )
        check(
            CartFootprint.vehicleBlocked(p, 0.0, 1.0, 0.0, -3.0),
            "crossing a vehicle with both endpoints outside must collide",
        )
        check(
            CartFootprint.vehicleBlocked(p, -3.0, 0.299, 3.0, 0.299),
            "vehicle edge needs the full .3 rail radius",
        )
        check(
            !CartFootprint.vehicleBlocked(p, -3.0, 0.301, 3.0, 0.301),
            "vehicle clearance must not inflate beyond .3",
        )
        check(
            !CartFootprint.vehicleBlocked(p, 2.25, 0.25, 2.25, 0.25),
            "vehicle corner uses a round cap, not an oversized box",
        )
        check(
            CartFootprint.vehicleBlocked(p, 2.2, 0.2, 2.2, 0.2),
            "stationary point near a hull corner must collide",
        )
        for (angle in doubleArrayOf(Math.PI / 6, Math.PI / 4, -Math.PI / 4)) for (origin in
            doubleArrayOf(0.0, 8192.0, 10825.5, 16384.0)) {
            val poly = hull(angle, 50.0, 0.0)
            poly.x1 = (poly.x1 + origin).toFloat()
            poly.x2 = (poly.x2 + origin).toFloat()
            poly.x3 = (poly.x3 + origin).toFloat()
            poly.x4 = (poly.x4 + origin).toFloat()
            poly.y1 = (poly.y1 + origin).toFloat()
            poly.y2 = (poly.y2 + origin).toFloat()
            poly.y3 = (poly.y3 + origin).toFloat()
            poly.y4 = (poly.y4 + origin).toFloat()
            poly.borders[0].set(poly.x1, poly.y1)
            poly.borders[1].set(poly.x2, poly.y2)
            poly.borders[2].set(poly.x3, poly.y3)
            poly.borders[3].set(poly.x4, poly.y4)
            val vehicle =
                object : CartFootprint.Query {
                    override fun blocked(x1: Double, y1: Double, x2: Double, y2: Double): Boolean =
                        CartFootprint.vehicleBlocked(poly, x1, y1, x2, y2)

                    override fun tangent(axis: Int): Double =
                        if (axis < 2) super<CartFootprint.Query>.tangent(axis)
                        else angle + (axis - 2) * Math.PI / 2
                }
            val nx = Math.sin(angle)
            val ny = -Math.cos(angle)
            var x = (origin - 0.345 * nx).toFloat().toDouble()
            var y = (origin - 0.345 * ny).toFloat().toDouble()
            var heading = angle
            var slid = false
            for (step in 0 until 120) {
                var dx = 0.08 * Math.signum(nx)
                var dy = 0.0
                val fraction =
                    CartFootprint.limit(
                        vehicle,
                        x,
                        y,
                        heading,
                        dx,
                        dy,
                        axle,
                        CartFootprint.FAST_FRONT,
                    )
                val slide =
                    CartFootprint.slide(
                        vehicle,
                        x,
                        y,
                        heading,
                        dx,
                        dy,
                        CartFootprint.FAST_FRONT,
                        fraction,
                        -0.025,
                        0.025,
                    )
                if (slide == null) {
                    dx = (x + dx * fraction).toFloat().toDouble() - x
                    dy = (y + dy * fraction).toFloat().toDouble() - y
                    val allowed =
                        CartFootprint.limit(
                            vehicle,
                            x,
                            y,
                            heading,
                            dx,
                            dy,
                            axle,
                            CartFootprint.FAST_FRONT,
                        )
                    dx = (x + dx * allowed).toFloat().toDouble() - x
                    dy = (y + dy * allowed).toFloat().toDouble() - y
                    val turn = CartSteeringMath.acceptedTurn(heading, axle, dx, dy)
                    check(
                        Math.hypot(dx, dy) > 0 &&
                            CartFootprint.rigidLimit(
                                vehicle,
                                x,
                                y,
                                heading,
                                dx,
                                dy,
                                heading + turn,
                                CartFootprint.FAST_FRONT,
                            ) == 1.0,
                        "the preferred rolling fallback must still make safe representable progress",
                    )
                    x += dx
                    y += dy
                    heading = CartSteeringMath.wrap(heading + turn)
                    continue
                }
                slid = true
                check(
                    Math.abs(CartSteeringMath.wrap(slide.target - angle)) < 1e-12,
                    "world-coordinate rounding must not change the retained hull tangent",
                )
                check(
                    Math.abs(slide.normalX - nx) < 1e-6 && Math.abs(slide.normalY - ny) < 1e-6,
                    "the contact guide must retain the real vehicle normal, not a tile axis",
                )
                check(
                    Math.abs(slide.x * nx + slide.y * ny) <
                        Math.max(1e-5, (2 * Math.ulp(x.toFloat())).toDouble()),
                    "vehicle slide must reject inward travel within world precision",
                )
                check(
                    CartFootprint.rigidLimit(
                        vehicle,
                        x,
                        y,
                        heading,
                        slide.x,
                        slide.y,
                        heading + slide.turn,
                        CartFootprint.FAST_FRONT,
                    ) == 1.0,
                    "every committed vehicle slide must pass the float-rounded swept envelope: angle=$angle step=$step x=$x y=$y heading=$heading slide=$slide",
                )
                x += slide.x
                y += slide.y
                heading = CartSteeringMath.wrap(heading + slide.turn)
            }
            check(
                slid,
                "axis-aligned input must exercise sliding along every tested vehicle yaw and world origin",
            )
            check(
                CartFootprint.followWall(
                    vehicle,
                    x,
                    y,
                    heading,
                    0.0,
                    angle,
                    nx,
                    ny,
                    CartFootprint.FAST_FRONT,
                ) == (nx > 0),
                "vehicle guidance must retain only input pressing into the contacted side",
            )
        }
    }

    private fun blockedProbeChecks(axle: Double) {
        val x = 10825.5f
        val y = 10142.5f
        val front = CartFootprint.WALK_FRONT
        val nose = x + front - 0.28
        val closed = booleanArrayOf(true)
        val queries = intArrayOf(0)
        val contact = CartFootprint.Query { x1, _, x2, _ ->
            queries[0]++
            closed[0] && Math.max(x1, x2) >= nose + 0.0003
        }
        check(
            CartFootprint.clear(contact, x.toDouble(), y.toDouble(), 0.0, front),
            "contact probe starts with a clear cart footprint",
        )
        check(
            CartSteeringHooks.blockedProbe(contact, x, y, 0.0, 0.03, 0.0, axle, front),
            "less than two world-coordinate ULPs of permitted travel is a hard stop",
        )
        check(
            CartSteeringHooks.blockedProbe(contact, x, y, 0.0, 0.03, 0.0, axle, front) &&
                CartFootprint.clear(contact, x.toDouble(), y.toDouble(), 0.0, front) &&
                queries[0] > 0,
            "repeated queries must retain the contact position without moving the cart",
        )
        closed[0] = false
        check(
            !CartSteeringHooks.blockedProbe(contact, x, y, 0.0, 0.03, 0.0, axle, front),
            "opening the obstacle must release the brace without an existing root budget",
        )
        closed[0] = true
        check(
            !CartSteeringHooks.blockedProbe(contact, x, y, 0.0, -0.03, 0.0, axle, front),
            "a cart at wall contact can reverse away immediately",
        )
        val partial = CartFootprint.Query { x1, _, x2, _ -> Math.max(x1, x2) >= nose + 0.012 }
        val fraction =
            CartFootprint.limit(partial, x.toDouble(), y.toDouble(), 0.0, 0.03, 0.0, axle, front)
        check(
            fraction > 0 &&
                fraction < 1 &&
                !CartSteeringHooks.blockedProbe(partial, x, y, 0.0, 0.03, 0.0, axle, front),
            "partial representable travel must not settle a moving cart into idle",
        )
        val parallel = CartFootprint.Query { x1, _, x2, _ -> Math.max(x1, x2) >= x + 0.041 }
        check(
            !CartSteeringHooks.blockedProbe(parallel, x, y, Math.PI / 2, 0.0, 0.03, axle, front),
            "clear travel parallel to the wall must retain its native slide",
        )
        val overlap = CartFootprint.Query { x1, _, x2, _ -> Math.max(x1, x2) >= nose - 0.01 }
        check(
            !CartFootprint.clear(overlap, x.toDouble(), y.toDouble(), 0.0, front),
            "escape probe starts in an overlapped footprint",
        )
        check(
            CartSteeringHooks.blockedProbe(overlap, x, y, 0.0, 0.03, 0.0, axle, front) &&
                CartSteeringHooks.blockedProbe(overlap, x, y, 0.0, 0.0, 0.03, axle, front),
            "an overlapped nose must not push forward or sweep sideways",
        )
        check(
            !CartSteeringHooks.blockedProbe(overlap, x, y, 0.0, -0.03, 0.0, axle, front),
            "an overlapped cart retains its existing backward escape",
        )
    }

    private fun effortContactChecks(axle: Double) {
        for (origin in floatArrayOf(8192f, 10825.5f)) {
            val x = origin
            val y = 10142.5f
            val front = CartFootprint.WALK_FRONT
            val nose = x + front - 0.28
            val closed = booleanArrayOf(true)
            val wall = CartFootprint.Query { x1, _, x2, _ ->
                closed[0] && Math.max(x1, x2) >= nose + 0.0003
            }
            for (frame in 0 until 240) {
                val accepted = if (frame % 2 == 0) 0.0 else Math.ulp(x).toDouble()
                check(
                    CartSteeringHooks.braceContact(
                        wall,
                        x,
                        y,
                        0.0,
                        0.03,
                        0.0,
                        axle,
                        front,
                        accepted,
                        true,
                    ),
                    "continuous forward contact must keep effort through zero/one-ULP accepted jitter",
                )
            }
            closed[0] = false
            check(
                !CartSteeringHooks.braceContact(wall, x, y, 0.0, 0.03, 0.0, axle, front, 0.0, true),
                "opening the obstacle releases effort even with a static zero-root stance",
            )
            closed[0] = true
            check(
                !CartSteeringHooks.braceContact(
                    wall,
                    x,
                    y,
                    0.0,
                    0.03,
                    0.0,
                    axle,
                    front,
                    0.012,
                    true,
                ),
                "real accepted tangent/partial travel must not enter a stationary effort pose",
            )
            check(
                !CartSteeringHooks.braceContact(
                    wall,
                    x,
                    y,
                    0.0,
                    -0.03,
                    0.0,
                    axle,
                    front,
                    0.0,
                    false,
                ) &&
                    !CartSteeringHooks.braceContact(
                        wall,
                        x,
                        y,
                        0.0,
                        0.03,
                        0.0,
                        axle,
                        front,
                        0.0,
                        false,
                    ),
                "reverse, released input, braking and stationary-turn gates release forward effort",
            )
            check(
                !CartSteeringHooks.braceContact(
                    wall,
                    x,
                    y,
                    0.0,
                    0.03,
                    0.0,
                    axle,
                    front,
                    Double.NaN,
                    true,
                ),
                "invalid accepted distance cannot invent contact effort",
            )
            val tiny = CartSteeringMath.step(0.0, 0.0, Math.ulp(x).toDouble(), 1.0 / 60, 0.0)
            check(
                !CartSteeringHooks.blockedStep(tiny, x, y, 0.0),
                "cosmetic contact tolerance must not redefine an accepted one-ULP physical step as blocked",
            )
        }
    }

    private fun relativeReverseContactChecks(axle: Double) {
        val dt = 1.0 / 60
        val front = CartFootprint.WALK_FRONT
        for (origin in doubleArrayOf(0.0, 8192.0, 10825.5, 16384.0)) for (normal in
            intArrayOf(-1, 1)) for (side in intArrayOf(-1, 1)) for (released in
            booleanArrayOf(false, true)) {
            val localHeading = side * if (released) 1.7 else 1.575
            val heading = if (normal > 0) localHeading else Math.PI - localHeading
            val yaw = normal * side
            var x = (origin + normal * 1.6599903106689453).toFloat().toDouble()
            val y = origin.toFloat().toDouble()
            val wall = CartFootprint.Query { x1, _, x2, _ ->
                Math.max(normal * (x1 - origin), normal * (x2 - origin)) + 0.3 >= 2
            }
            // Start at the nearest representable clear position without waiving the envelope.
            var retreat = 0
            while (!CartFootprint.clear(wall, x, y, heading, front) && retreat < 4) {
                x =
                    Math.nextAfter(
                            x.toFloat(),
                            if (normal > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                        )
                        .toDouble()
                retreat++
            }
            val context = "$origin/$normal/$side/released=$released"
            check(
                CartFootprint.clear(wall, x, y, heading, front),
                "reverse contact must start clear: $context",
            )
            val target = heading + Math.PI + if (released) 0.0 else yaw * Math.PI / 4
            val requested =
                CartSteeringMath.woodenStep(
                    heading,
                    target,
                    0.02,
                    dt,
                    0.0,
                    axle,
                    0.0,
                    true,
                    CartSteeringMath.Step(),
                )
            val fraction =
                CartFootprint.limit(wall, x, y, heading, requested.x(), requested.y(), axle, front)
            check(
                fraction < 1,
                "reverse contact regression must exercise the blocked path: $context",
            )
            val slide =
                CartFootprint.steeredSlide(
                    wall,
                    x,
                    y,
                    heading,
                    requested.x(),
                    requested.y(),
                    front,
                    fraction,
                    if (released) 0.0 else requested.turn(),
                )
            check(
                slide != null && Math.hypot(slide.x, slide.y) > 0.01,
                "relative contact must retain clear manual reverse progress: $context",
            )
            val accepted = slide ?: throw NullPointerException()
            check(
                if (released) accepted.turn == 0.0
                else
                    accepted.turn * yaw >= 0 &&
                        Math.abs(accepted.turn) <= Math.abs(requested.turn()) + 1e-12,
                "relative contact must not introduce opposite or released yaw: $context slide=$slide",
            )
            check(
                CartFootprint.rigidLimit(
                    wall,
                    x,
                    y,
                    heading,
                    accepted.x,
                    accepted.y,
                    heading + accepted.turn,
                    front,
                ) == 1.0,
                "relative reverse correction must retain native-coordinate swept clearance: $context",
            )
            check(
                Math.abs(accepted.x) < 1e-9,
                "relative contact must remove inward travel instead of inventing an automatic escape: $context",
            )
        }
    }

    private fun relativeBlockedTurnContactChecks(axle: Double) {
        val dt = 1.0 / 60
        val front = CartFootprint.FAST_FRONT
        for (origin in doubleArrayOf(0.0, 8192.0, 10825.5, 16384.0)) for (normal in
            intArrayOf(-1, 1)) for (side in intArrayOf(-1, 1)) {
            val localHeading = side * 0.7
            val heading = if (normal > 0) localHeading else Math.PI - localHeading
            val yaw = -normal * side
            val contact = 2 - 0.3 - (front - 0.28) * Math.cos(localHeading) - 0.00001
            var x = (origin + normal * contact).toFloat().toDouble()
            val y = origin.toFloat().toDouble()
            val wall = CartFootprint.Query { x1, _, x2, _ ->
                Math.max(normal * (x1 - origin), normal * (x2 - origin)) + 0.3 >= 2
            }
            var retreat = 0
            while (!CartFootprint.clear(wall, x, y, heading, front) && retreat < 4) {
                x =
                    Math.nextAfter(
                            x.toFloat(),
                            if (normal > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                        )
                        .toDouble()
                retreat++
            }
            val context = "$origin/$normal/$side"
            check(
                CartFootprint.clear(wall, x, y, heading, front),
                "blocked-turn contact must start clear: $context",
            )
            val requested =
                CartSteeringMath.woodenStep(
                    heading,
                    heading + yaw * Math.PI / 4,
                    0.02,
                    dt,
                    0.0,
                    axle,
                    0.0,
                    false,
                    CartSteeringMath.Step(),
                )
            val fraction =
                CartFootprint.rigidLimit(
                    wall,
                    x,
                    y,
                    heading,
                    requested.x(),
                    requested.y(),
                    heading + requested.turn(),
                    front,
                )
            check(fraction < 1, "blocked-turn regression must contact the wall: $context")
            check(
                CartFootprint.rigidLimit(wall, x, y, heading, 0.0, requested.y(), heading, front) ==
                    1.0,
                "straight tangent must remain clear when the requested yaw is blocked: $context",
            )
            val slide =
                CartFootprint.steeredSlide(
                    wall,
                    x,
                    y,
                    heading,
                    requested.x(),
                    requested.y(),
                    front,
                    fraction,
                    requested.turn(),
                )
            check(
                slide != null && Math.abs(slide.y) > 0.01,
                "collision-blocked yaw must not discard clear tangent progress: $context slide=$slide",
            )
            val accepted = slide ?: throw NullPointerException()
            check(
                accepted.turn * yaw >= 0 &&
                    Math.abs(accepted.turn) <= Math.abs(requested.turn()) + 1e-12,
                "blocked yaw may stop but must not reverse steering: $context",
            )
            check(
                CartFootprint.rigidLimit(
                    wall,
                    x,
                    y,
                    heading,
                    accepted.x,
                    accepted.y,
                    heading + accepted.turn,
                    front,
                ) == 1.0,
                "blocked-yaw fallback must retain its complete swept clearance: $context",
            )
        }
    }

    private fun relativeWallGuideChecks() {
        for (origin in doubleArrayOf(8192.0, 10825.5, 16384.0)) for (normal in
            intArrayOf(-1, 1)) for (direction in intArrayOf(-1, 1)) {
            val x = (origin + normal * 1.6).toFloat().toDouble()
            val y = origin.toFloat().toDouble()
            val tangent = direction * Math.PI / 2
            val near = tangent - normal * direction * 0.04
            val away = tangent + normal * direction * 0.04
            val wall = CartFootprint.Query { x1, _, x2, _ ->
                Math.max(normal * (x1 - origin), normal * (x2 - origin)) + 0.3 >= 2
            }
            val empty = CartFootprint.Query { _, _, _, _ -> false }
            val context = "$origin/$normal/$direction"
            for (heading in doubleArrayOf(near, tangent, away)) check(
                CartFootprint.clear(wall, x, y, heading, CartFootprint.FAST_FRONT),
                "relative guide regression must retain a clear cart envelope: $context",
            )
            check(
                CartFootprint.followWall(
                    wall,
                    x,
                    y,
                    near,
                    near,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    CartFootprint.FAST_FRONT,
                    true,
                ),
                "relative contact must finish aligning from within the old pressure cutoff: $context",
            )
            check(
                CartFootprint.followWall(
                    wall,
                    x,
                    y,
                    tangent,
                    tangent,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    CartFootprint.FAST_FRONT,
                    true,
                ),
                "relative tangent contact must retain its established guide: $context",
            )
            check(
                !CartFootprint.followWall(
                    wall,
                    x,
                    y,
                    away,
                    away,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    CartFootprint.FAST_FRONT,
                    true,
                ),
                "relative outward intent must release wall guidance immediately: $context",
            )
            check(
                !CartFootprint.followWall(
                    empty,
                    x,
                    y,
                    near,
                    near,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    CartFootprint.FAST_FRONT,
                    true,
                ) &&
                    !CartFootprint.followWall(
                        empty,
                        x,
                        y,
                        tangent,
                        tangent,
                        tangent,
                        normal.toDouble(),
                        0.0,
                        CartFootprint.FAST_FRONT,
                        true,
                    ),
                "relative guidance must end when the wall ends: $context",
            )
            check(
                !CartFootprint.followWall(
                    wall,
                    x - normal,
                    y,
                    near,
                    near,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    CartFootprint.FAST_FRONT,
                    true,
                ),
                "relative guidance must end after leaving wall contact: $context",
            )
            check(
                !CartFootprint.followWall(
                    wall,
                    x,
                    y,
                    near,
                    near,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    CartFootprint.FAST_FRONT,
                ) &&
                    !CartFootprint.followWall(
                        wall,
                        x,
                        y,
                        tangent,
                        tangent,
                        tangent,
                        normal.toDouble(),
                        0.0,
                        CartFootprint.FAST_FRONT,
                    ),
                "absolute guidance must preserve its existing pressure threshold: $context",
            )
            val pressing = tangent - normal * direction * 0.08
            check(
                CartFootprint.followWall(
                    wall,
                    x,
                    y,
                    tangent,
                    pressing,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    CartFootprint.FAST_FRONT,
                ),
                "absolute guidance must still accept pressure above its established cutoff: $context",
            )
        }
    }

    @JvmRecord
    private data class WallWalk(
        val contactFrames: Int,
        val acquisitions: Int,
        val releases: Int,
        val sideFlips: Int,
        val progress: Double,
        val heading: Double,
    ) {
        override fun toString(): String =
            "WallWalk[contactFrames=$contactFrames, acquisitions=$acquisitions, releases=$releases, sideFlips=$sideFlips, progress=$progress, heading=$heading]"
    }

    /**
     * Exercise the relative Forward feedback loop, rather than only a single slide or guide
     * predicate.
     */
    private fun relativeWallWalk(
        axle: Double,
        normal: Int,
        direction: Int,
        distance: Double,
    ): WallWalk {
        val origin = 10825.5
        var y = 10142.5
        val front = CartFootprint.WALK_FRONT
        val dt = 1.0 / 60
        var heading = if (normal > 0) direction * 0.6 else Math.PI - direction * 0.6
        val tangent = direction * Math.PI / 2
        var x =
            (origin + normal * (1.7 - (front - 0.28) * Math.cos(0.6) - 0.00001))
                .toFloat()
                .toDouble()
        val wall = CartFootprint.Query { x1, _, x2, _ ->
            Math.max(normal * (x1 - origin), normal * (x2 - origin)) + 0.3 >= 2
        }
        var retreat = 0
        while (!CartFootprint.clear(wall, x, y, heading, front) && retreat < 4) {
            x =
                Math.nextAfter(
                        x.toFloat(),
                        if (normal > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                    )
                    .toDouble()
            retreat++
        }
        val context = "$normal/$direction/$distance"
        check(
            CartFootprint.clear(wall, x, y, heading, front),
            "relative wall Walk must start clear: $context",
        )
        val startY = y
        var wallHeading = Double.NaN
        var wallRate = 0.0
        var contactFrames = 0
        var acquisitions = 0
        var releases = 0
        var sideFlips = 0
        var previousSide = 0
        for (frame in 0 until 600) {
            val hadGuide = java.lang.Double.isFinite(wallHeading)
            // Forward with released steering follows accepted yaw, while contact alignment keeps
            // its own rate.
            val target = heading
            val guided =
                hadGuide &&
                    CartFootprint.followWall(
                        wall,
                        x,
                        y,
                        heading,
                        target,
                        wallHeading,
                        normal.toDouble(),
                        0.0,
                        front,
                        true,
                    )
            if (hadGuide && !guided) releases++
            if (!guided) wallHeading = Double.NaN
            val requested =
                CartSteeringMath.woodenStep(
                    heading,
                    if (guided) wallHeading else target,
                    distance,
                    dt,
                    0.0,
                    axle,
                    if (guided) wallRate else 0.0,
                    false,
                    CartSteeringMath.Step(),
                )
            var dx = requested.x().toFloat().toDouble()
            var dy = requested.y().toFloat().toDouble()
            var turn = requested.turn()
            if (guided) {
                val inward = Math.max(0.0, dx * normal)
                val rounding = Math.ulp(x.toFloat()).toDouble()
                val contact =
                    CartFootprint.contactStep(
                        wall,
                        x,
                        y,
                        heading,
                        dx,
                        dy,
                        turn,
                        normal.toDouble(),
                        0.0,
                        front,
                    )
                check(
                    contact != null,
                    "established relative contact must return a checked step: $context frame=$frame",
                )
                dx = contact.x
                dy = contact.y
                turn = contact.turn
                contactFrames++
                check(
                    dx * normal <= inward + rounding && dx * normal >= -rounding,
                    "contact alignment may accept requested inward travel but must not invent advance or automatic backoff: $context frame=$frame",
                )
            } else {
                val fraction =
                    CartFootprint.rigidLimit(wall, x, y, heading, dx, dy, heading + turn, front)
                val slide =
                    CartFootprint.steeredSlide(wall, x, y, heading, dx, dy, front, fraction, turn)
                if (slide == null) {
                    dx *= fraction
                    dy *= fraction
                    turn *= fraction
                } else {
                    dx = slide.x
                    dy = slide.y
                    turn = slide.turn
                    if (
                        CartFootprint.pressingWall(
                            target,
                            slide.target,
                            slide.normalX,
                            slide.normalY,
                        )
                    ) {
                        wallHeading = slide.target
                        acquisitions++
                    }
                }
            }
            // Native commits root XY as floats before the post-update yaw and gait hooks run.
            var actualX = (x + dx).toFloat().toDouble() - x
            var actualY = (y + dy).toFloat().toDouble() - y
            val planned = dx * dx + dy * dy
            turn *=
                if (planned > 0)
                    Math.max(0.0, Math.min(1.0, (actualX * dx + actualY * dy) / planned))
                else 0.0
            val allowed =
                CartFootprint.rigidLimit(
                    wall,
                    x,
                    y,
                    heading,
                    actualX,
                    actualY,
                    heading + turn,
                    front,
                )
            actualX = (x + actualX * allowed).toFloat().toDouble() - x
            actualY = (y + actualY * allowed).toFloat().toDouble() - y
            turn *= allowed
            check(
                CartFootprint.rigidLimit(
                    wall,
                    x,
                    y,
                    heading,
                    actualX,
                    actualY,
                    heading + turn,
                    front,
                ) == 1.0,
                "every relative wall Walk step needs float-coordinate swept clearance: $context frame=$frame",
            )
            check(
                turn * normal * direction >= -1e-12,
                "relative contact alignment must not reverse yaw: $context frame=$frame",
            )
            x += actualX
            y += actualY
            heading = CartSteeringMath.wrap(heading + turn)
            wallRate = if (java.lang.Double.isFinite(wallHeading)) turn / dt else 0.0
            val length = Math.hypot(actualX, actualY)
            if (length > 1e-6) {
                val stepX =
                    0.8 * (-actualX * Math.sin(heading) + actualY * Math.cos(heading)) / length
                // One world-coordinate ULP can perturb an almost-forward gait; catch the large
                // opposite Strafe changes.
                val side = if (Math.abs(stepX) > 0.1) if (stepX > 0) 1 else -1 else 0
                if (side != 0) {
                    if (previousSide != 0 && side != previousSide) sideFlips++
                    previousSide = side
                }
            }
        }
        return WallWalk(
            contactFrames,
            acquisitions,
            releases,
            sideFlips,
            (y - startY) * direction,
            Math.abs(CartSteeringMath.wrap(tangent - heading)),
        )
    }

    private fun relativeWallWalkChecks(axle: Double) {
        for (normal in intArrayOf(-1, 1)) for (direction in intArrayOf(-1, 1)) for (distance in
            doubleArrayOf(0.02, 0.023)) {
            val context = "$normal/$direction/$distance"
            val walk = relativeWallWalk(axle, normal, direction, distance)
            println("CART_WALL_WALK $context $walk")
            check(
                walk.contactFrames > 20 && walk.progress > 2,
                "relative wall Walk must exercise sustained moving contact: $context $walk",
            )
            // As yaw accelerates, handle rotation can overtake tangent translation and cross local
            // sideways zero once.
            // Repeated reversals are the shaking regression, rather than that single geometric
            // crossover.
            check(
                walk.sideFlips <= 1,
                "relative wall Walk must not repeatedly reverse native Strafe directions: $context $walk",
            )
            check(
                walk.acquisitions == 1 && walk.releases == 0,
                "relative wall Walk must retain the same straight-wall contact throughout alignment: $context $walk",
            )
            check(
                walk.heading < 0.01,
                "relative wall Walk must finish its gradual tangent alignment: $context $walk",
            )
        }
    }

    private fun contactRoundingChecks(axle: Double) {
        val originX = 10825.5
        val originY = 10142.5
        val front = CartFootprint.WALK_FRONT
        val dt = 1.0 / 60
        for (angle in doubleArrayOf(-0.7, -0.3, 0.3, 0.7, 2.4)) {
            val nx = -Math.sin(angle)
            val ny = Math.cos(angle)
            val tx = Math.cos(angle)
            val ty = Math.sin(angle)
            val offset = 1.7 - (front - 0.28) * Math.sin(0.6) - 0.0001
            var x = (originX + offset * nx).toFloat().toDouble()
            var y = (originY + offset * ny).toFloat().toDouble()
            var heading = angle + 0.6
            var rate = 0.0
            val wall = CartFootprint.Query { x1, y1, x2, y2 ->
                Math.max(
                    (x1 - originX) * nx + (y1 - originY) * ny,
                    (x2 - originX) * nx + (y2 - originY) * ny,
                ) + 0.3 >= 2
            }
            var retreat = 0
            while (!CartFootprint.clear(wall, x, y, heading, front) && retreat < 4) {
                x =
                    Math.nextAfter(
                            x.toFloat(),
                            if (nx > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                        )
                        .toDouble()
                y =
                    Math.nextAfter(
                            y.toFloat(),
                            if (ny > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                        )
                        .toDouble()
                retreat++
            }
            check(
                CartFootprint.clear(wall, x, y, heading, front),
                "diagonal contact must start clear: $angle",
            )
            for (frame in 0 until 120) {
                val request =
                    CartSteeringMath.woodenStep(
                        heading,
                        angle,
                        0.02,
                        dt,
                        0.0,
                        axle,
                        rate,
                        false,
                        CartSteeringMath.Step(),
                    )
                val contact =
                    CartFootprint.contactStep(
                        wall,
                        x,
                        y,
                        heading,
                        request.x(),
                        request.y(),
                        request.turn(),
                        nx,
                        ny,
                        front,
                    )
                val rounding = (Math.ulp(x.toFloat()) + Math.ulp(y.toFloat())).toDouble()
                val inward = Math.max(0.0, request.x() * nx + request.y() * ny)
                check(
                    contact != null &&
                        java.lang.Double.isFinite(contact.x + contact.y + contact.turn),
                    "diagonal contact must return finite movement: $angle frame=$frame",
                )
                check(
                    contact.x * nx + contact.y * ny <= inward + rounding &&
                        contact.x * nx + contact.y * ny >= -rounding,
                    "diagonal rounding must not invent inward progress or automatic backoff: $angle frame=$frame",
                )
                check(
                    Math.abs((contact.x - request.x()) * tx + (contact.y - request.y()) * ty) <=
                        rounding,
                    "diagonal contact must preserve its full tangent within native coordinate precision: $angle frame=$frame",
                )
                check(
                    CartFootprint.rigidLimit(
                        wall,
                        x,
                        y,
                        heading,
                        contact.x,
                        contact.y,
                        heading + contact.turn,
                        front,
                    ) == 1.0,
                    "diagonal contact must retain the complete rounded swept clearance: $angle frame=$frame",
                )
                x += contact.x
                y += contact.y
                heading = CartSteeringMath.wrap(heading + contact.turn)
                rate = contact.turn / dt
            }
        }
    }

    private fun contactCornerChecks(axle: Double) {
        val originX = 10825.5
        val originY = 10142.5
        val dt = 1.0 / 60
        for (front in
            doubleArrayOf(CartFootprint.WALK_FRONT, CartFootprint.FAST_FRONT)) for (normal in
            intArrayOf(-1, 1)) for (direction in intArrayOf(-1, 1)) {
            val heading = if (normal > 0) direction * 0.7 else Math.PI - direction * 0.7
            val tangent = direction * Math.PI / 2
            var x =
                (originX + normal * (1.7 - (front - 0.28) * Math.cos(0.7) - 0.0001))
                    .toFloat()
                    .toDouble()
            val y = originY.toFloat().toDouble()
            val request =
                CartSteeringMath.woodenStep(
                    heading,
                    tangent,
                    0.02,
                    dt,
                    0.0,
                    axle,
                    0.0,
                    false,
                    CartSteeringMath.Step(),
                )
            val along = (y + request.y()).toFloat().toDouble() - y
            // The established wall stays beside the cart; a second wall blocks only the yaw sweep
            // at its nose.
            val ceiling = (front - 0.28) * Math.sin(0.7) + along * direction + 0.3 + 0.0002
            val corner = CartFootprint.Query { x1, y1, x2, y2 ->
                Math.max(normal * (x1 - originX), normal * (x2 - originX)) + 0.3 >= 2 ||
                    Math.max(direction * (y1 - originY), direction * (y2 - originY)) + 0.3 >=
                        ceiling
            }
            var retreat = 0
            while (!CartFootprint.clear(corner, x, y, heading, front) && retreat < 4) {
                x =
                    Math.nextAfter(
                            x.toFloat(),
                            if (normal > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                        )
                        .toDouble()
                retreat++
            }
            val context = "$front/$normal/$direction"
            check(
                CartFootprint.clear(corner, x, y, heading, front),
                "corner contact must start clear: $context",
            )
            check(
                CartFootprint.followWall(
                    corner,
                    x,
                    y,
                    heading,
                    heading,
                    tangent,
                    normal.toDouble(),
                    0.0,
                    front,
                    true,
                ),
                "corner fallback must start with a valid established Forward wall guide: $context",
            )
            check(
                CartFootprint.rigidLimit(corner, x, y, heading, 0.0, along, heading, front) == 1.0,
                "corner must leave the full tangent clear without yaw: $context",
            )
            check(
                CartFootprint.rigidLimit(
                    corner,
                    x,
                    y,
                    heading,
                    0.0,
                    along,
                    heading + request.turn(),
                    front,
                ) < 1,
                "corner regression must exercise the yaw-blocked fallback: $context",
            )
            val contact =
                CartFootprint.contactStep(
                    corner,
                    x,
                    y,
                    heading,
                    request.x(),
                    request.y(),
                    request.turn(),
                    normal.toDouble(),
                    0.0,
                    front,
                )
            check(
                contact != null &&
                    contact.turn == 0.0 &&
                    Math.abs(contact.y - along) <= Math.ulp(y.toFloat()),
                "blocked yaw must preserve clear tangent travel: $context $contact",
            )
            check(
                contact.x == 0.0,
                "corner fallback must not invent inward travel or automatic reverse: $context",
            )
            check(
                CartFootprint.rigidLimit(
                    corner,
                    x,
                    y,
                    heading,
                    contact.x,
                    contact.y,
                    heading,
                    front,
                ) == 1.0,
                "corner fallback must retain the complete swept clearance: $context",
            )
        }
    }

    private fun javaContracts() {
        val query = CartFootprint.Query { _, _, _, _ -> false }
        check(
            CartFootprint.Query::class
                .java
                .getMethod("tangent", Int::class.javaPrimitiveType)
                .isDefault && query.tangent(1) == Math.PI / 2 && query.tangent(2).isNaN(),
            "Query must retain its Java SAM and real default tangent",
        )
        val slide = CartFootprint.Slide(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
        check(
            CartFootprint.Slide::class.java.isRecord &&
                CartFootprint.Slide::class.java.superclass == Record::class.java &&
                CartFootprint.Slide::class.java.getMethod("x").invoke(slide) == 1.0 &&
                slide.toString() ==
                    "Slide[x=1.0, y=2.0, turn=3.0, target=4.0, normalX=5.0, normalY=6.0]",
            "Slide must retain Java record component accessors and formatting",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        javaContracts()
        val empty = CartFootprint.Query { _, _, _, _ -> false }
        val axle = CartSteeringMath.woodenAxle(0f, 0f)
        blockedProbeChecks(axle)
        effortContactChecks(axle)
        relativeReverseContactChecks(axle)
        relativeBlockedTurnContactChecks(axle)
        relativeWallGuideChecks()
        relativeWallWalkChecks(axle)
        contactRoundingChecks(axle)
        contactCornerChecks(axle)
        for (heading in doubleArrayOf(0.0, 0.3, Math.PI / 2, Math.PI, -Math.PI / 2)) for (dx in
            doubleArrayOf(-0.2, 0.0, 0.2)) for (dy in doubleArrayOf(-0.2, 0.0, 0.2)) check(
            CartFootprint.limit(empty, 10825.5, 10142.5, heading, dx, dy, axle, 1.62) == 1.0,
            "clear world must retain the native movement budget",
        )
        val eastWall = CartFootprint.Query { x1, _, x2, _ -> Math.max(x1, x2) + 0.3 >= 2 }
        for (front in doubleArrayOf(CartFootprint.WALK_FRONT, CartFootprint.FAST_FRONT)) {
            val allowed = CartFootprint.limit(eastWall, 0.0, 0.0, 0.0, 1.5, 0.0, axle, front)
            check(allowed > 0 && allowed < 1, "frontal wall must shorten a crossing step")
            check(
                1.5 * allowed + front + 0.02 < 2 && 1.5 * allowed + front + 0.02 > 1.99,
                "clip must stop at the checked front cap rather than freeze early",
            )
            check(
                CartFootprint.clear(eastWall, 1.5 * allowed, 0.0, 0.0, front),
                "clipped footprint remains clear",
            )
            check(
                CartFootprint.limit(eastWall, 1.5 * allowed, 0.0, 0.0, -0.1, 0.0, axle, front) ==
                    1.0,
                "a valid stopped cart can immediately reverse away",
            )
        }
        check(
            CartFootprint.clear(eastWall, 0.5, 0.0, 0.0, CartFootprint.WALK_FRONT) &&
                !CartFootprint.clear(eastWall, 0.5, 0.0, 0.0, CartFootprint.FAST_FRONT),
            "gait promotion needs its larger envelope even before root motion",
        )
        val passage = CartFootprint.Query { _, y1, _, y2 ->
            Math.max(Math.abs(y1), Math.abs(y2)) + 0.3 >= 0.5
        }
        check(
            CartFootprint.limit(passage, 0.0, 0.0, 0.0, 2.0, 0.0, axle, 1.62) == 1.0,
            "the conservative footprint still fits a centered one-tile passage",
        )
        check(
            !CartFootprint.clear(passage, 0.0, 0.0, Math.PI / 4, 1.62),
            "a diagonal cart must not fit through a narrower opening",
        )
        val sideWall = CartFootprint.Query { _, y1, _, y2 -> Math.max(y1, y2) + 0.3 >= 0.345 }
        val pivot =
            CartSteeringMath.stationaryStep(
                0.0,
                Math.PI / 2,
                0.5,
                0.1,
                0.0,
                axle,
                1.6,
                CartSteeringMath.Step(),
            )
        val turnFraction =
            CartFootprint.limit(sideWall, 0.0, 0.0, 0.0, pivot.x(), pivot.y(), axle, 1.62)
        check(turnFraction < 1, "sideways nose sweep must clip a turn into the wall")
        val h =
            CartSteeringMath.acceptedTurn(
                0.0,
                axle,
                pivot.x() * turnFraction,
                pivot.y() * turnFraction,
            )
        check(
            CartFootprint.clear(
                sideWall,
                pivot.x() * turnFraction,
                pivot.y() * turnFraction,
                h,
                1.62,
            ),
            "accepted clipped turn remains inside the clear envelope",
        )
        val slideFraction =
            CartFootprint.limit(eastWall, 1.65, 0.0, Math.PI / 2, 0.1, 0.0, axle, 1.26)
        check(slideFraction < 1, "native wall sliding must recheck the resulting rolling yaw")
        val closed = booleanArrayOf(true)
        val door = CartFootprint.Query { x1, y1, x2, y2 ->
            closed[0] && eastWall.blocked(x1, y1, x2, y2)
        }
        check(
            CartFootprint.limit(door, 0.0, 0.0, 0.0, 1.5, 0.0, axle, 1.26) < 1,
            "closed door blocks the cart",
        )
        closed[0] = false
        check(
            CartFootprint.limit(door, 0.0, 0.0, 0.0, 1.5, 0.0, axle, 1.26) == 1.0,
            "opening the same door releases the cart",
        )
        val rearOnly = CartFootprint.Query { _, y1, _, _ -> Math.abs(y1) > 0.03 }
        check(
            !CartFootprint.clear(rearOnly, 0.0, 0.0, 0.0, 1.26),
            "both rail starts must participate in validation",
        )
        check(
            CartFootprint.limit(eastWall, 1.0, 0.0, 0.0, 0.1, 0.0, axle, 1.26) == 0.0,
            "ordinary forward clipping must not waive an existing overlap",
        )
        for (bad in doubleArrayOf(Double.NaN, Double.POSITIVE_INFINITY)) check(
            CartFootprint.limit(empty, 0.0, 0.0, 0.0, bad, 0.0, axle, 1.26) == 0.0,
            "invalid movement fails closed",
        )
        check(
            CartFootprint.limit(empty, 0.0, 0.0, 0.0, 100.0, 0.0, axle, 1.26) == 0.0,
            "unbounded sweeps fail closed",
        )
        val roundedWall = CartFootprint.Query { x1, _, x2, _ ->
            Math.max(x1.toFloat(), x2.toFloat()) >= (10828 - 0.3).toFloat()
        }
        for (example in
            arrayOf(
                doubleArrayOf(
                    10826.4599609375,
                    -0.590038008344458,
                    0.10638530070086012,
                    0.09627626195628909,
                ),
                doubleArrayOf(
                    10827.5673828125,
                    1.562924403531673,
                    -0.0006353829521685839,
                    0.10575318336486816,
                ),
            )) {
            val x = example[0]
            val y = 10142.5
            val heading = example[1]
            var dx = example[2]
            var dy = example[3]
            repeat(2) {
                val fraction = CartFootprint.limit(roundedWall, x, y, heading, dx, dy, axle, 1.62)
                dx = (x + dx * fraction).toFloat().toDouble() - x
                dy = (y + dy * fraction).toFloat().toDouble() - y
                check(
                    CartFootprint.clear(
                        roundedWall,
                        x + dx,
                        y + dy,
                        heading + CartSteeringMath.acceptedTurn(heading, axle, dx, dy),
                        1.62,
                    ),
                    "rounded world coordinates and their resulting yaw must remain clear after each pass",
                )
            }
        }
        for (heading in doubleArrayOf(0.0, 0.3, Math.PI / 2, Math.PI, -Math.PI / 2)) for (dx in
            doubleArrayOf(-0.2, 0.0, 0.2)) for (dy in doubleArrayOf(-0.2, 0.0, 0.2)) for (target in
            doubleArrayOf(heading, heading + Math.PI / 2, heading - Math.PI)) check(
            CartFootprint.rigidLimit(empty, 10825.5, 10142.5, heading, dx, dy, target, 1.62) == 1.0,
            "native rigid routes must retain independent displacement and facing in open space",
        )
        check(
            CartFootprint.rigidLimit(sideWall, 0.0, 0.0, 0.0, 0.0, 0.0, Math.PI / 2, 1.62) < 1,
            "a pure native yaw must sweep its nose even with no root movement",
        )
        val yaw = CartFootprint.rigidLimit(sideWall, 0.0, 0.0, 0.0, 0.0, 0.0, Math.PI / 2, 1.62)
        check(
            CartFootprint.clear(sideWall, 0.0, 0.0, Math.PI / 2 * yaw, 1.62),
            "clipped native yaw must retain a clear pose",
        )
        check(
            CartFootprint.rigidLimit(eastWall, 0.648, 0.0, 0.0, 0.0, -0.1, 0.0, 1.26) == 1.0,
            "native lateral displacement must not invent rolling yaw into a nearby wall",
        )
        val rigidSlide = CartFootprint.rigidLimit(sideWall, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.62)
        check(
            rigidSlide > 0 && rigidSlide < 1,
            "actual native slide still needs a footprint translation sweep",
        )
        for (bad in doubleArrayOf(Double.NaN, Double.POSITIVE_INFINITY)) check(
            CartFootprint.rigidLimit(empty, 0.0, 0.0, 0.0, 0.0, 0.0, bad, 1.26) == 0.0,
            "invalid native yaw fails closed",
        )
        for (sign in doubleArrayOf(-1.0, 1.0)) for (front in
            doubleArrayOf(CartFootprint.WALK_FRONT, CartFootprint.FAST_FRONT)) {
            val x = (2 - front - 0.022).toFloat().toDouble()
            val dx = 0.08
            val dy = 0.04 * sign
            val fraction = CartFootprint.limit(eastWall, x, 0.0, 0.0, dx, dy, axle, front)
            val slide =
                CartFootprint.slide(eastWall, x, 0.0, 0.0, dx, dy, front, fraction, -0.025, 0.025)
            check(
                slide != null && slide.x == 0.0 && Math.abs(slide.y - dy) < 1e-8,
                "wall contact must preserve the full available tangent: $sign/$front fraction=$fraction slide=$slide",
            )
            val accepted = slide ?: throw NullPointerException()
            check(
                accepted.turn * sign > 0 && Math.abs(accepted.turn) <= 0.025,
                "contact should guide the cart toward the wall tangent within its turn-rate budget",
            )
            check(
                CartFootprint.rigidLimit(
                    eastWall,
                    x,
                    0.0,
                    0.0,
                    accepted.x,
                    accepted.y,
                    accepted.turn,
                    front,
                ) == 1.0,
                "the deflected translation and yaw must retain a fully swept clear envelope",
            )
            val corner = CartFootprint.Query { x1, y1, x2, y2 ->
                eastWall.blocked(x1, y1, x2, y2) || Math.max(y1 * sign, y2 * sign) + 0.3 >= 0.342
            }
            val blocked =
                CartFootprint.slide(corner, x, 0.0, 0.0, dx, dy, front, 0.0, -0.025, 0.025)
            check(
                blocked == null || Math.abs(blocked.y) < Math.abs(dy),
                "a second wall must stop the tangent too",
            )
            check(
                CartFootprint.slide(empty, x, 0.0, 0.0, dx, dy, front, 1.0, -0.025, 0.025) == null,
                "unobstructed rolling must retain its original path and yaw",
            )
            check(
                CartFootprint.slide(eastWall, x, 0.0, 0.0, dx, 0.0, front, 0.0, -0.025, 0.025) ==
                    null,
                "head-on intent must not invent a sideways escape",
            )
        }
        // Repeat at native world precision: each wall-guided step must commit its checked float XY
        // and yaw.
        for (sign in doubleArrayOf(-1.0, 1.0)) {
            var x = 10826.0
            var y = 10142.5
            var heading = sign * 0.6
            val wall = CartFootprint.Query { x1, _, x2, _ -> Math.max(x1, x2) + 0.3 >= 10828 }
            var slid = false
            for (step in 0 until 240) {
                var dx = 0.04
                var dy = 0.02 * sign
                val fraction = CartFootprint.limit(wall, x, y, heading, dx, dy, axle, 1.62)
                val slide =
                    CartFootprint.slide(wall, x, y, heading, dx, dy, 1.62, fraction, -0.025, 0.025)
                val turn: Double
                if (slide == null) {
                    dx = (x + dx * fraction).toFloat().toDouble() - x
                    dy = (y + dy * fraction).toFloat().toDouble() - y
                    turn = CartSteeringMath.acceptedTurn(heading, axle, dx, dy)
                } else {
                    dx = slide.x
                    dy = slide.y
                    turn = slide.turn
                    slid = true
                }
                check(
                    CartFootprint.rigidLimit(wall, x, y, heading, dx, dy, heading + turn, 1.62) ==
                        1.0,
                    "repeated rounded wall slides must retain a fully checked sweep",
                )
                x += dx
                y += dy
                heading = CartSteeringMath.wrap(heading + turn)
            }
            check(slid, "native-coordinate contact must actually exercise the deflection path")
        }
        val heading = Math.PI / 4
        val dt = 1.0 / 60
        val previousRate = -0.5
        val front = CartFootprint.FAST_FRONT
        val wallX = Math.cos(heading) * (front - 0.28) + 0.301
        val closeWall = CartFootprint.Query { x1, _, x2, _ -> Math.max(x1, x2) + 0.3 >= wallX }
        val approach =
            CartSteeringMath.woodenStep(
                heading,
                0.0,
                0.02,
                dt,
                0.0,
                axle,
                previousRate,
                CartSteeringMath.Step(),
            )
        val fraction =
            CartFootprint.limit(
                closeWall,
                0.0,
                0.0,
                heading,
                approach.x(),
                approach.y(),
                axle,
                front,
            )
        val redirected =
            CartFootprint.slide(
                closeWall,
                0.0,
                0.0,
                heading,
                approach.x(),
                approach.y(),
                front,
                fraction,
                (previousRate - 6 * dt) * dt,
                (previousRate + 6 * dt) * dt,
            )
        check(
            redirected == null ||
                redirected.turn == 0.0 ||
                Math.abs(redirected.turn / dt - previousRate) <= 6 * dt + 1e-9,
            "wall guidance must brake an incoming turn before reversing its angular velocity",
        )
        check(
            redirected == null ||
                CartFootprint.rigidLimit(
                    closeWall,
                    0.0,
                    0.0,
                    heading,
                    redirected.x,
                    redirected.y,
                    heading + redirected.turn,
                    front,
                ) == 1.0,
            "angular braking must not bypass the swept tangent checks",
        )
        val parallelX = 1.65.toFloat().toDouble()
        check(
            CartFootprint.followWall(
                eastWall,
                parallelX,
                0.0,
                Math.PI / 2,
                Math.PI / 4,
                Math.PI / 2,
                1.0,
                0.0,
                front,
            ),
            "diagonal pressure into a nearby wall must retain the contact tangent",
        )
        check(
            !CartFootprint.followWall(
                empty,
                parallelX,
                0.0,
                Math.PI / 2,
                Math.PI / 4,
                Math.PI / 2,
                1.0,
                0.0,
                front,
            ),
            "a wall guide must end when the obstacle ends",
        )
        for (target in doubleArrayOf(Math.PI * 3 / 4, -Math.PI / 4, Math.PI / 2)) check(
            !CartFootprint.followWall(
                eastWall,
                parallelX,
                0.0,
                Math.PI / 2,
                target,
                Math.PI / 2,
                1.0,
                0.0,
                front,
            ),
            "away, opposite and wall-parallel input must release the contact-only guide",
        )
        vehicleChecks(axle)
        println(
            "CART_FOOTPRINT_PASS (native budget, wall/door/vehicle contact, brace probes, passage, swept turn, slide, promotion, rear caps)",
        )
    }
}
