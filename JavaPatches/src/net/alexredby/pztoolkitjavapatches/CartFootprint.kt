package net.alexredby.pztoolkitjavapatches

import java.awt.geom.Line2D
import java.util.ArrayList
import zombie.characters.IsoPlayer
import zombie.pathfind.PolygonalMap2
import zombie.pathfind.VehiclePoly

/** Conservative wooden-cart envelope; the native world remains the obstacle oracle. */
internal object CartFootprint {
    // shortcut: original wooden mesh/rigs and +/-7deg bank; recalibrate if the mesh or authored
    // pose changes.
    const val WALK_FRONT = 1.26
    const val FAST_FRONT = 1.62
    // Native wall queries already add radius .3; only the tilted body needs extra width.
    private const val RAIL = 0.04
    private const val NOSE_INSET = 0.28
    private const val TAPER = 0.30

    fun interface Query {
        fun blocked(x1: Double, y1: Double, x2: Double, y2: Double): Boolean

        fun tangent(axis: Int): Double = if (axis < 2) axis * Math.PI / 2 else Double.NaN
    }

    @JvmStatic
    fun world(player: IsoPlayer?): Query {
        val actor = player ?: throw NullPointerException()
        val z = Math.floor(actor.getZ().toDouble()).toInt()
        val vehicles = ArrayList<VehiclePoly>()
        for (vehicle in actor.getCell().getVehicles()) if (
            vehicle.addedToWorld &&
                vehicle.getScript() != null &&
                Math.floor(vehicle.getZ().toDouble()) == z.toDouble()
        )
            vehicles.add(vehicle.getPoly())
        return object : Query {
            private var contact: VehiclePoly? = null

            override fun tangent(axis: Int): Double {
                if (axis < 2) return super<Query>.tangent(axis)
                val poly = contact ?: return Double.NaN
                return if (axis == 2)
                    Math.atan2((poly.y2 - poly.y1).toDouble(), (poly.x2 - poly.x1).toDouble())
                else Math.atan2((poly.y3 - poly.y2).toDouble(), (poly.x3 - poly.x2).toDouble())
            }

            override fun blocked(x1: Double, y1: Double, x2: Double, y2: Double): Boolean {
                // Native vehicle queries use .15 rather than the wall query's .3 radius.
                for (poly in vehicles) if (vehicleBlocked(poly, x1, y1, x2, y2)) {
                    contact = poly
                    return true
                }
                val map = PolygonalMap2.instance
                // The line query checks only its destination. Validate the rear cap as well.
                if (!map.canStandAt(x1.toFloat(), y1.toFloat(), z, actor, false, false)) return true
                if (x1 == x2 && y1 == y2) return false
                // Short overloads ignore doors; the explicit zero mask includes them.
                return map.lineClearCollide(
                    x1.toFloat(),
                    y1.toFloat(),
                    x2.toFloat(),
                    y2.toFloat(),
                    z,
                    actor,
                    PolygonalMap2.LCC_ZERO,
                )
            }
        }
    }

    @JvmStatic
    fun vehicleBlocked(p: VehiclePoly?, x1: Double, y1: Double, x2: Double, y2: Double): Boolean {
        val poly = p ?: throw NullPointerException()
        if (
            Math.max(x1, x2) + 0.3 <
                Math.min(Math.min(poly.x1, poly.x2), Math.min(poly.x3, poly.x4)) ||
                Math.min(x1, x2) - 0.3 >
                    Math.max(Math.max(poly.x1, poly.x2), Math.max(poly.x3, poly.x4)) ||
                Math.max(y1, y2) + 0.3 <
                    Math.min(Math.min(poly.y1, poly.y2), Math.min(poly.y3, poly.y4)) ||
                Math.min(y1, y2) - 0.3 >
                    Math.max(Math.max(poly.y1, poly.y2), Math.max(poly.y3, poly.y4))
        )
            return false
        return poly.containsPoint(x1.toFloat(), y1.toFloat()) ||
            poly.containsPoint(x2.toFloat(), y2.toFloat()) ||
            near(
                x1,
                y1,
                x2,
                y2,
                poly.x1.toDouble(),
                poly.y1.toDouble(),
                poly.x2.toDouble(),
                poly.y2.toDouble(),
            ) ||
            near(
                x1,
                y1,
                x2,
                y2,
                poly.x2.toDouble(),
                poly.y2.toDouble(),
                poly.x3.toDouble(),
                poly.y3.toDouble(),
            ) ||
            near(
                x1,
                y1,
                x2,
                y2,
                poly.x3.toDouble(),
                poly.y3.toDouble(),
                poly.x4.toDouble(),
                poly.y4.toDouble(),
            ) ||
            near(
                x1,
                y1,
                x2,
                y2,
                poly.x4.toDouble(),
                poly.y4.toDouble(),
                poly.x1.toDouble(),
                poly.y1.toDouble(),
            )
    }

    private fun near(
        ax: Double,
        ay: Double,
        bx: Double,
        by: Double,
        cx: Double,
        cy: Double,
        dx: Double,
        dy: Double,
    ): Boolean =
        Line2D.linesIntersect(ax, ay, bx, by, cx, cy, dx, dy) ||
            Line2D.ptSegDistSq(ax, ay, bx, by, cx, cy) <= 0.09 ||
            Line2D.ptSegDistSq(ax, ay, bx, by, dx, dy) <= 0.09 ||
            Line2D.ptSegDistSq(cx, cy, dx, dy, ax, ay) <= 0.09 ||
            Line2D.ptSegDistSq(cx, cy, dx, dy, bx, by) <= 0.09

    /** Read-only source-point check against the same four native-radius segment capsules. */
    @JvmStatic
    fun contains(forward: Double, lateral: Double, front: Double, reserve: Double): Boolean {
        if (
            !java.lang.Double.isFinite(forward + lateral + front + reserve) ||
                front <= NOSE_INSET + TAPER ||
                reserve < 0 ||
                reserve >= 0.3
        )
            return false
        val length = front - NOSE_INSET
        val radius = 0.3 - reserve
        for (side in -1..1 step 2) {
            val rail = side * RAIL
            if (
                Line2D.ptSegDistSq(0.0, rail, length - TAPER, rail, forward, lateral) <=
                    radius * radius ||
                    Line2D.ptSegDistSq(length - TAPER, rail, length, 0.0, forward, lateral) <=
                        radius * radius
            )
                return true
        }
        return false
    }

    @JvmStatic
    fun clear(query: Query?, x: Double, y: Double, heading: Double, front: Double): Boolean {
        val cos = Math.cos(heading)
        val sin = Math.sin(heading)
        val length = front - NOSE_INSET
        for (side in -1..1 step 2) {
            val rearX = x - sin * side * RAIL
            val rearY = y + cos * side * RAIL
            val shoulderX = rearX + cos * (length - TAPER)
            val shoulderY = rearY + sin * (length - TAPER)
            if (
                (query ?: throw NullPointerException()).blocked(
                    rearX,
                    rearY,
                    shoulderX,
                    shoulderY,
                ) || query.blocked(shoulderX, shoulderY, x + cos * length, y + sin * length)
            )
                return false
        }
        return true
    }

    private fun sweep(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        dx: Double,
        dy: Double,
        axle: Double,
        front: Double,
        from: Double,
        to: Double,
        turn: Double,
        rolling: Boolean,
    ): Boolean {
        val ax = (x + dx * from).toFloat().toDouble()
        val ay = (y + dy * from).toFloat().toDouble()
        val bx = (x + dx * to).toFloat().toDouble()
        val by = (y + dy * to).toFloat().toDouble()
        // Native position rounding can change rolling yaw; verify the coordinates we will actually
        // commit.
        val a =
            heading +
                if (rolling) CartSteeringMath.acceptedTurn(heading, axle, ax - x, ay - y)
                else turn * from
        val b =
            heading +
                if (rolling) CartSteeringMath.acceptedTurn(heading, axle, bx - x, by - y)
                else turn * to
        if (!clear(query, bx, by, b, front)) return false
        for (side in -1..1 step 2) for (end in 0..2) {
            val length = if (end == 0) 0.0 else front - NOSE_INSET - if (end == 1) TAPER else 0.0
            val offset = if (end == 2) 0.0 else side * RAIL
            val x1 = ax + Math.cos(a) * length - Math.sin(a) * offset
            val y1 = ay + Math.sin(a) * length + Math.cos(a) * offset
            val x2 = bx + Math.cos(b) * length - Math.sin(b) * offset
            val y2 = by + Math.sin(b) * length + Math.cos(b) * offset
            if ((query ?: throw NullPointerException()).blocked(x1, y1, x2, y2)) return false
        }
        return true
    }

    /**
     * Shorten only the supplied displacement, using its actual rolling yaw after native sliding.
     */
    @JvmStatic
    fun limit(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        dx: Double,
        dy: Double,
        axle: Double,
        front: Double,
    ): Double =
        limit(
            query,
            x,
            y,
            heading,
            dx,
            dy,
            axle,
            front,
            CartSteeringMath.acceptedTurn(heading, axle, dx, dy),
            true,
            false,
        )

    /**
     * Native routes own displacement and facing independently, including turns without root motion.
     */
    @JvmStatic
    fun rigidLimit(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        dx: Double,
        dy: Double,
        target: Double,
        front: Double,
    ): Double =
        limit(
            query,
            x,
            y,
            heading,
            dx,
            dy,
            0.0,
            front,
            CartSteeringMath.wrap(target - heading),
            false,
            false,
        )

    private fun limit(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        dx: Double,
        dy: Double,
        axle: Double,
        front: Double,
        turn: Double,
        rolling: Boolean,
        wholeStep: Boolean,
    ): Double {
        val distance = Math.hypot(dx, dy)
        if (
            !java.lang.Double.isFinite(x + y + distance + turn + heading + front) ||
                rolling && !(axle > 0)
        )
            return 0.0
        if (!clear(query, x, y, heading, front)) return 0.0
        if (distance == 0.0 && turn == 0.0) return 1.0
        val steps = Math.max(1, Math.ceil((distance + Math.abs(turn) * front) / 0.04).toInt())
        if (steps > if (rolling) 128 else 256) return 0.0
        var previous = 0.0
        for (step in 1..steps) {
            val next = step / steps.toDouble()
            if (!sweep(query, x, y, heading, dx, dy, axle, front, previous, next, turn, rolling)) {
                if (wholeStep) return 0.0
                var low = previous
                var high = next
                repeat(12) {
                    val mid = (low + high) / 2
                    if (
                        sweep(
                            query,
                            x,
                            y,
                            heading,
                            dx,
                            dy,
                            axle,
                            front,
                            previous,
                            mid,
                            turn,
                            rolling,
                        )
                    )
                        low = mid
                    else high = mid
                }
                return low
            }
            previous = next
        }
        return 1.0
    }

    @JvmStatic
    fun pressingWall(target: Double, tangent: Double, normalX: Double, normalY: Double): Boolean =
        Math.cos(target) * normalX + Math.sin(target) * normalY > 0.05 &&
            Math.cos(target - tangent) > 0.1

    @JvmStatic
    fun followWall(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        target: Double,
        tangent: Double,
        normalX: Double,
        normalY: Double,
        front: Double,
    ): Boolean = followWall(query, x, y, heading, target, tangent, normalX, normalY, front, false)

    @JvmStatic
    fun followWall(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        target: Double,
        tangent: Double,
        normalX: Double,
        normalY: Double,
        front: Double,
        relative: Boolean,
    ): Boolean {
        // Forward-only relative intent follows the accepted heading. Keep established contact
        // through tangent alignment; an away-steering request or the end of the wall releases it.
        val pressing =
            if (relative)
                Math.cos(target) * normalX + Math.sin(target) * normalY >= -1e-6 &&
                    Math.cos(target - tangent) > 0.1
            else pressingWall(target, tangent, normalX, normalY)
        return pressing &&
            rigidLimit(query, x, y, heading, normalX * 0.25, normalY * 0.25, heading, front) < 1
    }

    @JvmRecord
    data class Slide(
        val x: Double,
        val y: Double,
        val turn: Double,
        val target: Double,
        val normalX: Double,
        val normalY: Double,
    ) {
        override fun toString(): String =
            "Slide[x=$x, y=$y, turn=$turn, target=$target, normalX=$normalX, normalY=$normalY]"
    }

    /** Preserve the full tangent while filling only the space opened by the planned yaw. */
    @JvmStatic
    fun contactStep(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        dx: Double,
        dy: Double,
        turn: Double,
        normalX: Double,
        normalY: Double,
        front: Double,
    ): Slide {
        val inward = Math.max(0.0, dx * normalX + dy * normalY)
        val tx = dx - inward * normalX
        val ty = dy - inward * normalY
        val full = contactRounded(x, y, tx, ty, inward, turn, normalX, normalY)
        if (contactClear(query, x, y, heading, full, front)) return full
        var tangent = contactRounded(x, y, tx, ty, 0.0, turn, normalX, normalY)
        if (!contactClear(query, x, y, heading, tangent, front)) {
            // A corner can stop yaw while leaving tangent travel available.
            tangent = contactRounded(x, y, tx, ty, 0.0, 0.0, normalX, normalY)
            val allowed = rigidLimit(query, x, y, heading, tangent.x, tangent.y, heading, front)
            tangent =
                contactRounded(
                    x,
                    y,
                    tangent.x * allowed,
                    tangent.y * allowed,
                    0.0,
                    0.0,
                    normalX,
                    normalY,
                )
            return if (contactClear(query, x, y, heading, tangent, front)) tangent
            else Slide(0.0, 0.0, 0.0, heading, normalX, normalY)
        }
        var low = 0.0
        var high = inward
        repeat(12) {
            val mid = (low + high) / 2
            val candidate = contactRounded(x, y, tx, ty, mid, turn, normalX, normalY)
            if (contactClear(query, x, y, heading, candidate, front)) {
                low = mid
                tangent = candidate
            } else high = mid
        }
        return tangent
    }

    private fun contactClear(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        step: Slide,
        front: Double,
    ): Boolean =
        // The outer normal search needs only acceptance; do not bisect a rejected path again.
        limit(
            query,
            x,
            y,
            heading,
            step.x,
            step.y,
            0.0,
            front,
            CartSteeringMath.wrap(step.turn),
            false,
            true,
        ) == 1.0

    private fun contactRounded(
        x: Double,
        y: Double,
        tx: Double,
        ty: Double,
        inward: Double,
        turn: Double,
        nx: Double,
        ny: Double,
    ): Slide {
        var sx = (x + tx + inward * nx).toFloat().toDouble() - x
        var sy = (y + ty + inward * ny).toFloat().toDouble() - y
        // Nearest float rounding must not invent additional inward movement.
        if (sx * nx + sy * ny > inward + 1e-12) {
            val outwardX =
                Math.nextAfter(
                        (x + sx).toFloat(),
                        if (nx > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                    )
                    .toDouble() - x
            val outwardY =
                Math.nextAfter(
                        (y + sy).toFloat(),
                        if (ny > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                    )
                    .toDouble() - y
            if (Math.abs((outwardX - sx) * nx) >= Math.abs((outwardY - sy) * ny)) sx = outwardX
            else sy = outwardY
        }
        return Slide(sx, sy, turn, Math.atan2(sy, sx), nx, ny)
    }

    /** Relative keys own yaw; blocked steering may stop while clear tangent travel continues. */
    @JvmStatic
    fun steeredSlide(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        dx: Double,
        dy: Double,
        front: Double,
        fraction: Double,
        turn: Double,
    ): Slide? = slide(query, x, y, heading, dx, dy, front, fraction, turn, turn)

    /** Deflect along a clear wall/vehicle edge, within the existing turn-rate budget. */
    @JvmStatic
    fun slide(
        query: Query?,
        x: Double,
        y: Double,
        heading: Double,
        dx: Double,
        dy: Double,
        front: Double,
        fraction: Double,
        minTurn: Double,
        maxTurn: Double,
    ): Slide? {
        if (
            fraction >= 1 ||
                !java.lang.Double.isFinite(dx + dy + minTurn + maxTurn) ||
                minTurn > maxTurn
        )
            return null
        var best = (dx * dx + dy * dy) * fraction
        var result: Slide? = null
        val oracle = query ?: throw NullPointerException()
        val vehicleAxis0 = oracle.tangent(2)
        val vehicleAxis1 = oracle.tangent(3)
        for (axis in 0..3) {
            val angle =
                if (axis < 2) oracle.tangent(axis)
                else if (axis == 2) vehicleAxis0 else vehicleAxis1
            if (!java.lang.Double.isFinite(angle)) continue
            val tx = if (axis == 0) 1.0 else if (axis == 1) 0.0 else Math.cos(angle)
            val ty = if (axis == 0) 0.0 else if (axis == 1) 1.0 else Math.sin(angle)
            val along = dx * tx + dy * ty
            val normal = -dx * ty + dy * tx
            if (Math.abs(along) < 1e-12 || Math.abs(normal) < 1e-12) continue
            var sx = tx * along
            var sy = ty * along
            val nx = -ty * Math.signum(normal)
            val ny = tx * Math.signum(normal)
            var target = Math.atan2(sy, sx)
            if (dx * Math.cos(heading) + dy * Math.sin(heading) < 0) target += Math.PI
            sx = (x + sx).toFloat().toDouble() - x
            sy = (y + sy).toFloat().toDouble() - y
            // Nearest rounding otherwise creeps a diagonal tangent into the hull each frame.
            if (sx * nx + sy * ny > 1e-12) {
                val outwardX =
                    Math.nextAfter(
                            (x + sx).toFloat(),
                            if (nx > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                        )
                        .toDouble() - x
                val outwardY =
                    Math.nextAfter(
                            (y + sy).toFloat(),
                            if (ny > 0) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY,
                        )
                        .toDouble() - y
                if (Math.abs((outwardX - sx) * nx) >= Math.abs((outwardY - sy) * ny)) sx = outwardX
                else sy = outwardY
            }
            val turn = Math.max(minTurn, Math.min(maxTurn, CartSteeringMath.wrap(target - heading)))
            var allowed = rigidLimit(query, x, y, heading, sx, sy, heading + turn, front)
            var acceptedTurn = turn * allowed
            if (acceptedTurn < minTurn || acceptedTurn > maxTurn) {
                // Contact can stop angular motion while the clear tangent keeps moving.
                allowed = rigidLimit(query, x, y, heading, sx, sy, heading, front)
                acceptedTurn = 0.0
            }
            sx = (x + sx * allowed).toFloat().toDouble() - x
            sy = (y + sy * allowed).toFloat().toDouble() - y
            if (rigidLimit(query, x, y, heading, sx, sy, heading + acceptedTurn, front) < 1)
                continue
            val progress = sx * dx + sy * dy
            if (progress > best + 1e-12) {
                best = progress
                result = Slide(sx, sy, acceptedTurn, target, nx, ny)
            }
        }
        return result
    }
}
