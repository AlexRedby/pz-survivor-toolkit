package net.alexredby.pztoolkitjavapatches

/** Shopping-cart axle pivot and rolling wheelbarrow arc; native collision stays authoritative. */
object CartSteeringMath {
    class Step() {
        private var x = 0.0
        private var y = 0.0
        private var turn = 0.0
        private var travel = 0.0

        fun x(): Double = x

        fun y(): Double = y

        fun turn(): Double = turn

        fun travel(): Double = travel

        @JvmSynthetic
        internal fun set(x: Double, y: Double, turn: Double, travel: Double): Step {
            this.x = x
            this.y = y
            this.turn = turn
            this.travel = travel
            return this
        }
    }

    class Bank() {
        @JvmField var angle = 0.0
        @JvmField var velocity = 0.0
        @JvmField var pressure = 0.0
        @JvmField var pressureVelocity = 0.0

        fun update(target: Double, seconds: Double): Double {
            if (!(seconds > 0)) return angle
            // Critical damping starts and releases hand pressure without a first-frame angular
            // jerk.
            val frequency = 1 / .085
            var offset = angle - target
            var rate = velocity + frequency * offset
            val decay = Math.exp(-frequency * seconds)
            angle = target + (offset + rate * seconds) * decay
            velocity = (velocity - frequency * rate * seconds) * decay
            // Retain clearance through a bank reversal without rectifying raw coordinate noise.
            val magnitude = Math.abs(angle)
            offset = pressure - magnitude
            rate = pressureVelocity + frequency * offset
            pressure = magnitude + (offset + rate * seconds) * decay
            pressureVelocity = (pressureVelocity - frequency * rate * seconds) * decay
            return angle
        }
    }

    class Reversal() {
        @JvmField var direction = 1
        @JvmField var requested = 0
        @JvmField var active = false
        @JvmField var braking = false
        @JvmField var neutral = 0.0

        fun request(intent: Int, atRest: Boolean): Boolean {
            requested = intent
            if (intent == 0) {
                active = false
                braking = false
                neutral = 0.0
                return false
            }
            if (!active && atRest) {
                direction = intent
                return false
            }
            if (intent != direction && !braking) {
                active = true
                braking = true
                neutral = 0.0
                return true
            }
            if (intent == direction && braking) {
                braking = false
                neutral = 0.0
            }
            return false
        }

        fun stopped(seconds: Double, rootStopped: Boolean, actualStopped: Boolean) {
            if (!active || !braking) return
            if (!rootStopped || !actualStopped) {
                neutral = 0.0
                return
            }
            neutral += Math.max(0.0, Math.min(.1, seconds))
            // The native picker must evaluate its Idle center before the travel sign changes.
            if (neutral >= .08) {
                direction = requested
                braking = false
                neutral = 0.0
            }
        }
    }

    @JvmStatic fun wrap(angle: Double): Double = Math.atan2(Math.sin(angle), Math.cos(angle))

    @JvmStatic
    fun keyboardTarget(heading: Double, travel: Int, steering: Int): Double =
        heading +
            (if (travel < 0) Math.PI else 0.0) +
            steering * (if (travel < 0) -1 else 1) * (if (travel == 0) Math.PI / 2 else Math.PI / 4)

    @JvmStatic
    fun reversing(heading: Double, target: Double): Boolean =
        Math.abs(wrap(target - heading)) > Math.PI * .75

    @JvmStatic
    fun directionIntent(heading: Double, target: Double, previous: Int): Int {
        val threshold =
            Math.toRadians((if (previous < 0) 130 else if (previous > 0) 140 else 135).toDouble())
        return if (Math.abs(wrap(target - heading)) > threshold) -1 else 1
    }

    /** Two fixed rear wheels constrain the rear axle; the front casters follow their arcs. */
    @JvmStatic
    fun shoppingStep(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axle: Double,
        reverse: Boolean,
        result: Step,
    ): Step =
        rollingStep(heading, target, distance, seconds, load, axle, 0.0, reverse, false, result)

    @JvmStatic
    fun step(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axleDistance: Double,
        result: Step?,
    ): Step = step(heading, target, distance, seconds, load, axleDistance, 52.0, result)

    @JvmStatic
    fun step(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axleDistance: Double,
        lateralDegrees: Double,
        result: Step?,
    ): Step =
        step(
            heading,
            target,
            distance,
            seconds,
            load,
            axleDistance,
            lateralDegrees,
            reversing(heading, target),
            result,
        )

    @JvmStatic
    fun step(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axleDistance: Double,
        lateralDegrees: Double,
        reverse: Boolean,
        result: Step?,
    ): Step {
        return rollingStep(
            heading,
            target,
            distance,
            seconds,
            load,
            axleDistance,
            lateralDegrees,
            reverse,
            true,
            result ?: throw NullPointerException(),
        )
    }

    private fun rollingStep(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axle: Double,
        lateralDegrees: Double,
        reverse: Boolean,
        wheelbarrow: Boolean,
        result: Step,
    ): Step {
        if (!(distance > 0) || !(seconds > 0) || !axle.isFinite() || axle <= 0)
            return result.set(0.0, 0.0, 0.0, 0.0)
        val boundedLoad = Math.max(0.0, Math.min(1.0, load))
        var error = wrap(target - heading)
        if (reverse) error = wrap(error + Math.PI)
        var limit =
            if (wheelbarrow)
                2 *
                    Math.asin(
                        Math.min(
                            1.0,
                            distance * Math.sin(Math.toRadians(lateralDegrees - 2 * boundedLoad)) /
                                (2 * axle),
                        ),
                    )
            else distance * Math.abs(Math.sin(error)) / axle
        limit =
            Math.min(
                limit,
                Math.min(0.1, seconds) *
                    (if (wheelbarrow) 1.6 - 0.3 * boundedLoad else 3.8 - boundedLoad),
            )
        // Square-root easing settles in finite time instead of crawling through a sine tail.
        if (wheelbarrow)
            limit *= Math.min(1.0, Math.sqrt(Math.abs(error) * seconds / (limit * 0.1)))
        val turn = Math.max(-limit, Math.min(limit, error))
        if (wheelbarrow) {
            val half = turn / 2
            val sideways = 2 * axle * Math.sin(half)
            var travel = Math.sqrt(Math.max(0.0, distance * distance - sideways * sideways))
            if (reverse) travel = -travel
            // The handles step outside so the front wheel stays in its rolling plane.
            return result.set(
                travel * Math.cos(heading + half) + sideways * Math.sin(heading + half),
                travel * Math.sin(heading + half) - sideways * Math.cos(heading + half),
                turn,
                travel,
            )
        }
        // Handle translation and the turn chord are perpendicular, not additive costs.
        val chord = 2 * axle * Math.sin(turn / 2)
        var travel = Math.sqrt(Math.max(0.0, distance * distance - chord * chord))
        // A time-limited yaw must not jump from a pure pivot to most of a forward stride.
        // Release rolling travel continuously as the handles align with the requested direction.
        travel = Math.min(travel, distance * Math.abs(Math.cos(error)))
        if (reverse) travel = -travel
        val next = heading + turn
        return result.set(
            travel * Math.cos(heading + turn / 2) - axle * (Math.cos(next) - Math.cos(heading)),
            travel * Math.sin(heading + turn / 2) - axle * (Math.sin(next) - Math.sin(heading)),
            turn,
            travel,
        )
    }

    /** Derive wheelbarrow yaw from the displacement native collisions actually accepted. */
    @JvmStatic
    fun acceptedTurn(
        heading: Double,
        axleDistance: Double,
        actualX: Double,
        actualY: Double,
    ): Double {
        if (!(axleDistance > 0)) return 0.0
        val cos = Math.cos(heading)
        val sin = Math.sin(heading)
        val forward = actualX * cos + actualY * sin
        val sideways = -actualX * sin + actualY * cos
        return 2 * Math.atan2(-sideways, 2 * axleDistance - forward)
    }

    @JvmStatic
    fun rollingLean(turn: Double, forward: Double, seconds: Double): Double {
        if (!(seconds > 0) || !turn.isFinite() || !forward.isFinite()) return 0.0
        // Accepted motion drives load transfer; the native anchored torso's handle reach limits the
        // bank.
        val cap = Math.toRadians(7.0)
        return Math.max(
            -cap,
            Math.min(cap, Math.atan(1.5 * forward * turn / (5 * seconds * seconds))),
        )
    }

    @JvmStatic
    fun woodenTurnAmount(bank: Float): Float {
        val x = Math.min(1.0, Math.abs(bank) / Math.toRadians(2.5)).toFloat()
        return Math.sin(x * Math.PI / 2).toFloat()
    }

    @JvmStatic
    fun woodenBankExtra(bank: Float): Float {
        val x =
            Math.max(0.0, Math.min(1.0, (Math.toDegrees(Math.abs(bank).toDouble()) - 3) / 4))
                .toFloat()
        return x * x * (3 - 2 * x)
    }

    @JvmStatic
    fun woodenShift(bank: Float, gaitShift: Float): Float =
        -.065f * woodenTurnAmount(bank) - .020f * woodenBankExtra(bank) + gaitShift

    @JvmStatic
    fun woodenAxle(bank: Float, gaitShift: Float): Double =
        // The same longitudinal hand-clearance shift must move the steering axle and rolling wheel.
        1.0084944326 - 1.5 * woodenShift(bank, gaitShift)

    /**
     * Spatial clock for an established wall guide; native root distance already includes the
     * animator motion scale.
     */
    @JvmStatic
    fun wallStepSeconds(
        distance: Double,
        clipSpeed: Double,
        motionScale: Double,
        currentDt: Double,
    ): Double {
        if (!distance.isFinite() || distance <= 0) return 0.0
        val nativeSpeed = clipSpeed * motionScale
        if (
            clipSpeed.isFinite() &&
                clipSpeed > 0 &&
                motionScale.isFinite() &&
                motionScale > 0 &&
                nativeSpeed.isFinite() &&
                nativeSpeed > 1e-6
        )
            return Math.min(.1, distance / nativeSpeed)
        return if (currentDt.isFinite()) Math.max(0.0, Math.min(.1, currentDt)) else 0.0
    }

    @JvmStatic
    fun woodenStep(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axle: Double,
        previousRate: Double,
        result: Step?,
    ): Step =
        woodenStep(
            heading,
            target,
            distance,
            seconds,
            load,
            axle,
            previousRate,
            reversing(heading, target),
            result,
        )

    @JvmStatic
    fun woodenStep(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axle: Double,
        previousRate: Double,
        reverse: Boolean,
        result: Step?,
    ): Step {
        val output = step(heading, target, distance, seconds, load, axle, 50.0, reverse, result)
        if (!(distance > 0) || !(seconds > 0)) return output
        val dt = Math.min(.1, seconds)
        var desiredRate = output.turn() / dt
        var error = wrap(target - heading)
        if (reverse) error = wrap(error + Math.PI)
        // Leave one step of braking distance so the final heading clamp cannot snap the yaw rate to
        // zero.
        val stoppingRate = Math.sqrt(12 * Math.abs(error) + 36 * dt * dt) - 6 * dt
        desiredRate = Math.copySign(Math.min(Math.abs(desiredRate), stoppingRate), desiredRate)
        val rate = previousRate + Math.max(-6 * dt, Math.min(6 * dt, desiredRate - previousRate))
        val limit =
            2 *
                Math.asin(
                    Math.min(
                        1.0,
                        distance *
                            Math.sin(Math.toRadians(45 - 2 * Math.max(0.0, Math.min(1.0, load)))) /
                            (2 * axle),
                    ),
                )
        var turn = Math.max(-limit, Math.min(limit, rate * dt))
        if (turn * error >= 0 && Math.abs(turn) > Math.abs(error)) turn = error
        val sideways = 2 * axle * Math.sin(turn / 2)
        var travel = Math.sqrt(Math.max(0.0, distance * distance - sideways * sideways))
        if (reverse) travel = -travel
        return output.set(
            travel * Math.cos(heading + turn / 2) + sideways * Math.sin(heading + turn / 2),
            travel * Math.sin(heading + turn / 2) - sideways * Math.cos(heading + turn / 2),
            turn,
            travel,
        )
    }

    /** A native sidestep budget moves the handles around the cart's rolling axle. */
    @JvmStatic
    fun stationaryStep(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axle: Double,
        previousRate: Double,
        result: Step?,
    ): Step =
        stationaryStep(heading, target, distance, seconds, load, axle, previousRate, result, false)

    @JvmStatic
    fun shoppingStationaryStep(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axle: Double,
        previousRate: Double,
        result: Step?,
    ): Step =
        stationaryStep(heading, target, distance, seconds, load, axle, previousRate, result, true)

    /** Planned angular cadence survives short native budgets; it does not authorize movement. */
    @JvmStatic
    fun stationaryRate(
        heading: Double,
        target: Double,
        seconds: Double,
        load: Double,
        previousRate: Double,
        shopping: Boolean,
    ): Double {
        if (!(seconds > 0)) return 0.0
        val dt = Math.min(.1, seconds)
        val error = wrap(target - heading)
        if (Math.abs(error) < 1e-12) return 0.0
        val acceleration = if (shopping) 8.0 else 6.0
        val stoppingRate =
            Math.sqrt(2 * acceleration * Math.abs(error) + acceleration * acceleration * dt * dt) -
                acceleration * dt
        val boundedLoad = Math.max(0.0, Math.min(1.0, load))
        val maximum = if (shopping) 2.2 - .4 * boundedLoad else 1.6 - .3 * boundedLoad
        val desired = Math.copySign(Math.min(maximum, stoppingRate), error)
        return previousRate +
            Math.max(
                -acceleration * dt,
                Math.min(acceleration * dt, desired - previousRate),
            )
    }

    private fun stationaryStep(
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        axle: Double,
        previousRate: Double,
        result: Step?,
        shopping: Boolean,
    ): Step {
        if (!(distance > 0) || !(seconds > 0) || !(axle > 0))
            return (result ?: throw NullPointerException()).set(0.0, 0.0, 0.0, 0.0)
        val dt = Math.min(.1, seconds)
        val error = wrap(target - heading)
        if (Math.abs(error) < 1e-12)
            return (result ?: throw NullPointerException()).set(0.0, 0.0, 0.0, 0.0)
        val rate = stationaryRate(heading, target, seconds, load, previousRate, shopping)
        val limit = 2 * Math.asin(Math.min(1.0, distance / (2 * axle)))
        var turn = Math.max(-limit, Math.min(limit, rate * dt))
        if (turn * error >= 0 && Math.abs(turn) > Math.abs(error)) turn = error
        return (result ?: throw NullPointerException()).set(
            -axle * (Math.cos(heading + turn) - Math.cos(heading)),
            -axle * (Math.sin(heading + turn) - Math.sin(heading)),
            turn,
            0.0,
        )
    }

    /** Wall slides cannot count sideways displacement as forward steering progress. */
    @JvmStatic
    fun acceptedFraction(requested: Step?, actualX: Double, actualY: Double): Double {
        val step = requested ?: throw NullPointerException()
        val lengthSquared = step.x() * step.x() + step.y() * step.y()
        if (!(lengthSquared > 0)) return 0.0
        return Math.max(
            0.0,
            Math.min(1.0, (actualX * step.x() + actualY * step.y()) / lengthSquared),
        )
    }
}
