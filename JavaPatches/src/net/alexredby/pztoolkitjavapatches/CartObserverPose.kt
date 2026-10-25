package net.alexredby.pztoolkitjavapatches

/** A bounded cosmetic actor/cart pose; never writes native movement or network state. */
internal object CartObserverPose {
    const val MAX_OFFSET = .75
    const val RELEASE_SECONDS = .12
    const val RELEASE_SPEED = .6
    const val ANCHOR_RECOVERY = .10

    @JvmRecord
    data class Pose(val x: Double, val y: Double, val heading: Double) {
        override fun toString() = "Pose[x=$x, y=$y, heading=$heading]"
    }

    private fun rounded(x: Double, y: Double, heading: Double) =
        Pose(x.toFloat().toDouble(), y.toFloat().toDouble(), CartSteeringMath.wrap(heading))

    private fun clear(query: CartFootprint.Query, pose: Pose, front: Double) =
        CartFootprint.clear(query, pose.x, pose.y, pose.heading, front)

    private fun distance(a: Pose, b: Pose) = Math.hypot(a.x - b.x, a.y - b.y)

    private fun cost(a: Pose, b: Pose, front: Double): Double {
        val yaw = CartSteeringMath.wrap(a.heading - b.heading) * front
        return Math.pow(a.x - b.x, 2.0) + Math.pow(a.y - b.y, 2.0) + yaw * yaw
    }

    private fun directions(query: CartFootprint.Query, raw: Pose, previous: Pose?): DoubleArray {
        val angles = DoubleArray(14)
        var count = 0
        for (axis in 0 until 4) {
            val tangent = query.tangent(axis)
            if (tangent.isFinite()) {
                angles[count++] = tangent + Math.PI / 2
                angles[count++] = tangent - Math.PI / 2
            }
        }
        if (previous != null && distance(raw, previous) > 1e-6)
            angles[count++] = Math.atan2(previous.y - raw.y, previous.x - raw.x)
        angles[count++] = raw.heading + Math.PI
        for (corner in 0 until 4) angles[count++] = Math.PI / 4 + corner * Math.PI / 2
        return angles.copyOf(count)
    }

    /**
     * Recover a slightly predicted-overlapping actor cap without crossing the physical wall core.
     */
    private fun anchor(query: CartFootprint.Query, raw: Pose): Pose? {
        if (!query.blocked(raw.x, raw.y, raw.x, raw.y)) return raw
        // Native oracles inflate the actor by .3. A clear point within .1 stays on its local side.
        var best: Pose? = null
        var nearest = ANCHOR_RECOVERY
        for (angle in directions(query, raw, null)) {
            val dx = Math.cos(angle)
            val dy = Math.sin(angle)
            var low = 0.0
            for (step in 1..5) {
                var high = ANCHOR_RECOVERY * step / 5
                var candidate = rounded(raw.x + dx * high, raw.y + dy * high, raw.heading)
                if (distance(raw, candidate) > ANCHOR_RECOVERY) {
                    high -= 2 * Math.max(Math.ulp(raw.x.toFloat()), Math.ulp(raw.y.toFloat()))
                    candidate = rounded(raw.x + dx * high, raw.y + dy * high, raw.heading)
                }
                if (
                    distance(raw, candidate) > ANCHOR_RECOVERY ||
                        query.blocked(candidate.x, candidate.y, candidate.x, candidate.y)
                ) {
                    low = high
                    continue
                }
                repeat(10) {
                    val mid = (low + high) / 2
                    val probe = rounded(raw.x + dx * mid, raw.y + dy * mid, raw.heading)
                    if (query.blocked(probe.x, probe.y, probe.x, probe.y)) low = mid
                    else {
                        high = mid
                        candidate = probe
                    }
                }
                if (distance(raw, candidate) <= nearest) {
                    best = candidate
                    nearest = distance(raw, candidate)
                }
                break
            }
        }
        return best
    }

    /** Closest sampled outward ray, refined against the same native footprint oracle. */
    private fun project(
        query: CartFootprint.Query,
        raw: Pose,
        previous: Pose?,
        anchor: Pose,
        front: Double,
    ): Pose? {
        if (clear(query, raw, front)) return raw
        var best: Pose? = null
        var bestDistance = MAX_OFFSET + .001
        // Every projection stays reachable from a clear anchor on the actor's local side.
        val angles = directions(query, raw, previous)
        for (direction in angles.indices) {
            val dx = Math.cos(angles[direction])
            val dy = Math.sin(angles[direction])
            var low = 0.0
            var high = 0.0
            var found: Pose? = null
            for (step in 1..5) {
                high = Math.min(bestDistance, MAX_OFFSET) * step / 5
                var candidate = rounded(raw.x + dx * high, raw.y + dy * high, raw.heading)
                // A diagonal .75 displacement can round outside the radius at map coordinates.
                if (distance(raw, candidate) > MAX_OFFSET) {
                    high -= 2 * Math.max(Math.ulp(raw.x.toFloat()), Math.ulp(raw.y.toFloat()))
                    candidate = rounded(raw.x + dx * high, raw.y + dy * high, raw.heading)
                }
                if (
                    distance(raw, candidate) <= MAX_OFFSET &&
                        !query.blocked(anchor.x, anchor.y, candidate.x, candidate.y) &&
                        clear(query, candidate, front)
                ) {
                    found = candidate
                    break
                }
                low = high
            }
            var accepted = found ?: continue
            repeat(10) {
                val mid = (low + high) / 2
                val candidate = rounded(raw.x + dx * mid, raw.y + dy * mid, raw.heading)
                if (
                    !query.blocked(anchor.x, anchor.y, candidate.x, candidate.y) &&
                        clear(query, candidate, front)
                ) {
                    high = mid
                    accepted = candidate
                } else low = mid
            }
            // A subpixel margin avoids a rounding-driven contact toggle every frame.
            val padded =
                rounded(raw.x + dx * (high + .003), raw.y + dy * (high + .003), raw.heading)
            if (
                distance(raw, padded) <= MAX_OFFSET &&
                    !query.blocked(anchor.x, anchor.y, padded.x, padded.y) &&
                    clear(query, padded, front)
            )
                accepted = padded
            val distance = distance(raw, accepted)
            if (distance < bestDistance) {
                best = accepted
                bestDistance = distance
            }
        }
        return best
    }

    private fun step(query: CartFootprint.Query, from: Pose, target: Pose, front: Double): Pose {
        val fraction =
            CartFootprint.rigidLimit(
                query,
                from.x,
                from.y,
                from.heading,
                target.x - from.x,
                target.y - from.y,
                target.heading,
                front,
            )
        val result =
            rounded(
                from.x + (target.x - from.x) * fraction,
                from.y + (target.y - from.y) * fraction,
                from.heading + CartSteeringMath.wrap(target.heading - from.heading) * fraction,
            )
        return if (clear(query, result, front)) result else from
    }

    class State {
        private var accepted: Pose? = null
        private var rawPrevious: Pose? = null

        fun clear() {
            accepted = null
            rawPrevious = null
        }

        fun update(
            query: CartFootprint.Query?,
            x: Double,
            y: Double,
            heading: Double,
            front: Double,
            seconds: Double,
        ): Pose? {
            if (
                query == null ||
                    !(x + y + heading + front + seconds).isFinite() ||
                    front < 1 ||
                    front > 2 ||
                    seconds < 0
            ) {
                clear()
                return null
            }
            val raw = rounded(x, y, heading)
            var previous = accepted
            val anchor = anchor(query, raw)
            if (anchor == null) {
                clear()
                return null
            }
            // A teleport, new geometry or larger gait envelope invalidates the old anchor.
            if (
                previous != null &&
                    (distance(previous, raw) > MAX_OFFSET ||
                        query.blocked(anchor.x, anchor.y, previous.x, previous.y) ||
                        !CartObserverPose.clear(query, previous, front))
            )
                previous = null
            var target: Pose?
            if (previous != null && rawPrevious != null) {
                val previousRaw = rawPrevious ?: throw NullPointerException()
                val dt = Math.min(seconds, .1)
                val dx = previous.x - previousRaw.x
                val dy = previous.y - previousRaw.y
                val offset = Math.hypot(dx, dy)
                var decay = Math.exp(-dt / RELEASE_SECONDS)
                // Only free cosmetic release is rate-limited; native travel remains unrestricted.
                if (offset > 1e-9) decay = Math.max(decay, 1 - RELEASE_SPEED * dt / offset)
                target = rounded(raw.x + dx * decay, raw.y + dy * decay, raw.heading)
                if (
                    distance(raw, target) > MAX_OFFSET ||
                        !CartObserverPose.clear(query, target, front)
                ) {
                    target =
                        if (raw == rawPrevious) previous
                        else project(query, raw, previous, anchor, front)
                }
            } else target = project(query, raw, null, anchor, front)
            if (target == null) {
                clear()
                return null
            }
            var result = target
            if (previous != null) {
                result = step(query, previous, target, front)
                if (cost(result, target, front) > 1e-10) {
                    // Try both safe orders when rotation pushes the long nose through a corner.
                    val translated =
                        step(query, previous, rounded(target.x, target.y, previous.heading), front)
                    val translationFirst = step(query, translated, target, front)
                    val rotated =
                        step(
                            query,
                            previous,
                            rounded(previous.x, previous.y, target.heading),
                            front,
                        )
                    val rotationFirst = step(query, rotated, target, front)
                    if (cost(translationFirst, target, front) < cost(result, target, front))
                        result = translationFirst
                    if (cost(rotationFirst, target, front) < cost(result, target, front))
                        result = rotationFirst
                }
            }
            if (
                distance(raw, result) > MAX_OFFSET || !CartObserverPose.clear(query, result, front)
            ) {
                clear()
                return null
            }
            accepted = result
            rawPrevious = raw
            return result
        }
    }
}
