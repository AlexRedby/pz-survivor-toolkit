package net.alexredby.pztoolkitjavapatches

object CartSteeringMathTest {
    private const val L = 0.8

    private fun check(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun close(actual: Double, expected: Double, message: String) {
        check(Math.abs(actual - expected) < 1e-10, "$message: $actual != $expected")
    }

    private fun rolling(
        heading: Double,
        turn: Double,
        axle: Double,
        side: Double,
        dx: Double,
        dy: Double,
    ) {
        val next = heading + turn
        val mid = heading + turn / 2
        val wheelX =
            dx + axle * (Math.cos(next) - Math.cos(heading)) -
                side * (Math.sin(next) - Math.sin(heading))
        val wheelY =
            dy +
                axle * (Math.sin(next) - Math.sin(heading)) +
                side * (Math.cos(next) - Math.cos(heading))
        close(
            -wheelX * Math.sin(mid) + wheelY * Math.cos(mid),
            0.0,
            "actual wheel displacement stays in its rolling plane",
        )
    }

    private fun wheelbarrowChecks() {
        // Actual calibrated contact positions after native horizontal model-to-world scale 1.5.
        for (geometry in
            arrayOf(
                doubleArrayOf(1.0224308175, .033440793),
                doubleArrayOf(1.1691522, -.0017422512),
            )) {
            val axle = geometry[0]
            val side = geometry[1]
            val empty =
                CartSteeringMath.step(
                    0.0,
                    Math.PI / 2,
                    .03,
                    1.0 / 60,
                    0.0,
                    axle,
                    CartSteeringMath.Step(),
                )
            val full =
                CartSteeringMath.step(
                    0.0,
                    Math.PI / 2,
                    .03,
                    1.0 / 60,
                    1.0,
                    axle,
                    CartSteeringMath.Step(),
                )
            check(
                empty.turn() > full.turn() && full.turn() > 0,
                "wheelbarrow load tightens steering",
            )
            for (heading in doubleArrayOf(0.0, .3, Math.PI / 2, Math.PI, -Math.PI / 2)) {
                for (budget in doubleArrayOf(0.0, .0001, .03, .5)) {
                    for (degrees in -180..180) {
                        val step =
                            CartSteeringMath.step(
                                heading,
                                heading + Math.toRadians(degrees.toDouble()),
                                budget,
                                1.0 / 60,
                                .7,
                                axle,
                                CartSteeringMath.Step(),
                            )
                        close(
                            Math.hypot(step.x(), step.y()),
                            budget,
                            "wheelbarrow preserves native walking budget",
                        )
                        check(
                            Math.abs(step.travel()) >= budget * .5 - 1e-12,
                            "wheelbarrow keeps rolling instead of parking its wheel",
                        )
                        rolling(heading, step.turn(), axle, side, step.x(), step.y())
                        close(
                            CartSteeringMath.acceptedTurn(heading, axle, step.x(), step.y()),
                            step.turn(),
                            "fully accepted step keeps planned yaw",
                        )
                        close(
                            CartSteeringMath.acceptedTurn(heading, axle, 0.0, 0.0),
                            0.0,
                            "fully blocked wheelbarrow cannot yaw",
                        )
                        for (fraction in doubleArrayOf(.1, .5)) {
                            val dx = step.x() * fraction
                            val dy = step.y() * fraction
                            rolling(
                                heading,
                                CartSteeringMath.acceptedTurn(heading, axle, dx, dy),
                                axle,
                                side,
                                dx,
                                dy,
                            )
                        }
                    }
                }
                for (slide in
                    arrayOf(
                        doubleArrayOf(.02, 0.0),
                        doubleArrayOf(0.0, -.02),
                        doubleArrayOf(-.01, .015),
                    )) rolling(
                    heading,
                    CartSteeringMath.acceptedTurn(heading, axle, slide[0], slide[1]),
                    axle,
                    side,
                    slide[0],
                    slide[1],
                )
            }
            val reverse =
                CartSteeringMath.step(
                    0.0,
                    Math.PI,
                    .03,
                    1.0 / 60,
                    0.0,
                    axle,
                    CartSteeringMath.Step(),
                )
            close(reverse.x(), -.03, "wheelbarrow can back away from a wall")
            close(reverse.y(), 0.0, "straight reverse stays on wheel axis")
            close(reverse.turn(), 0.0, "straight reverse cannot make a U-turn")
            for (sign in intArrayOf(-1, 1)) for (load in intArrayOf(0, 1)) {
                val speed = if (load == 0) 1.3 else .83
                var reference: DoubleArray? = null
                for (fps in intArrayOf(30, 60, 144)) {
                    var heading = 0.0
                    var x = 0.0
                    var y = 0.0
                    var settled = 0
                    var previousTravel = 0.0
                    for (frame in 0 until fps * 4) {
                        val step =
                            CartSteeringMath.step(
                                heading,
                                sign * Math.PI / 2,
                                speed / fps,
                                1.0 / fps,
                                load.toDouble(),
                                axle,
                                CartSteeringMath.Step(),
                            )
                        rolling(heading, step.turn(), axle, side, step.x(), step.y())
                        x += step.x()
                        y += step.y()
                        heading += step.turn()
                        check(sign * y >= -.58, "initial outside handle step stays below .58 tiles")
                        check(
                            sign * heading <= Math.PI / 2,
                            "wheelbarrow cannot overshoot the held direction",
                        )
                        if (frame > 0)
                            check(
                                Math.abs(step.travel() - previousTravel) < .3 * speed / fps,
                                "settling does not abruptly release sideways motion",
                            )
                        previousTravel = step.travel()
                        if (settled == 0 && heading == sign * Math.PI / 2) settled = frame + 1
                    }
                    check(
                        settled > 0 && settled <= fps * (if (load == 0) 2 else 3),
                        "wheelbarrow reaches 90 degrees in two seconds empty or three loaded",
                    )
                    check(sign * y > 0, "wheelbarrow rolls into held turn")
                    val baseline = reference
                    if (baseline == null) reference = doubleArrayOf(heading, x, y)
                    else {
                        check(
                            Math.abs(heading - baseline[0]) < .002,
                            "wheelbarrow yaw is stable across FPS",
                        )
                        check(
                            Math.hypot(x - baseline[1], y - baseline[2]) < .015,
                            "wheelbarrow rolling trajectory is stable across FPS",
                        )
                    }
                }
            }
        }
        close(CartSteeringMath.acceptedTurn(0.0, 0.0, .02, .01), 0.0, "invalid axle cannot steer")
    }

    private fun wallClockChecks() {
        val cadence = .7
        val motionScale = 1.6
        val worldSpeed = cadence * motionScale
        val normalDt = 1.0 / 60
        close(
            CartSteeringMath.wallStepSeconds(worldSpeed * normalDt, cadence, motionScale, normalDt),
            normalDt,
            "steady wall cadence keeps the original steering interval and includes native motion scale",
        )
        close(
            CartSteeringMath.wallStepSeconds(0.0, cadence, motionScale, normalDt),
            0.0,
            "zero root budget cannot advance wall yaw",
        )
        close(
            CartSteeringMath.wallStepSeconds(Double.NaN, cadence, motionScale, normalDt),
            0.0,
            "invalid root budget cannot advance wall yaw",
        )
        close(
            CartSteeringMath.wallStepSeconds(1.0, cadence, motionScale, normalDt),
            .1,
            "deferred wall clock keeps the existing interval cap",
        )
        for (speed in doubleArrayOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY, 1e-12)) close(
            CartSteeringMath.wallStepSeconds(.02, speed, motionScale, normalDt),
            normalDt,
            "missing or vanishing native cadence falls back to current time",
        )
        for (scale in doubleArrayOf(0.0, -1.0, Double.NaN, Double.POSITIVE_INFINITY)) close(
            CartSteeringMath.wallStepSeconds(.02, cadence, scale, normalDt),
            normalDt,
            "invalid motion scale falls back without introducing a new movement budget",
        )
        close(
            CartSteeringMath.wallStepSeconds(.02, 0.0, motionScale, Double.NaN),
            0.0,
            "nonfinite fallback time is safe",
        )
        close(
            CartSteeringMath.wallStepSeconds(.02, 0.0, motionScale, -1.0),
            0.0,
            "negative fallback time is safe",
        )
        close(
            CartSteeringMath.wallStepSeconds(.02, 0.0, motionScale, 1.0),
            .1,
            "fallback time retains the existing cap",
        )
        // native01 Walk-slide grounding rows 62.20-62.55s: root distance follows the preceding
        // animator interval.
        val currentDt =
            doubleArrayOf(.016669, .021717, .011625, .016658, .025816, .007516, .016668, .016667)
        for (sign in intArrayOf(-1, 1)) for (load in intArrayOf(0, 1)) {
            var heading = 0.0
            var referenceHeading = 0.0
            var wrongHeading = 0.0
            var rate = 0.0
            var referenceRate = 0.0
            var wrongRate = 0.0
            var previousCurvature = 0.0
            var previousWrongCurvature = 0.0
            var trend = 0
            var wrongTrend = 0
            var curvatureReversals = 0
            var wrongCurvatureReversals = 0
            val axle = 1.13599443394
            val target = sign * Math.PI / 4
            for (frame in 0 until 160) {
                val index = frame % currentDt.size
                val producerDt = currentDt[(index + currentDt.size - 1) % currentDt.size]
                val distance = worldSpeed * producerDt
                val seconds =
                    CartSteeringMath.wallStepSeconds(
                        distance,
                        cadence,
                        motionScale,
                        currentDt[index],
                    )
                val step =
                    CartSteeringMath.woodenStep(
                        heading,
                        target,
                        distance,
                        seconds,
                        load.toDouble(),
                        axle,
                        rate,
                        false,
                        CartSteeringMath.Step(),
                    )
                val reference =
                    CartSteeringMath.woodenStep(
                        referenceHeading,
                        target,
                        distance,
                        producerDt,
                        load.toDouble(),
                        axle,
                        referenceRate,
                        false,
                        CartSteeringMath.Step(),
                    )
                val wrong =
                    CartSteeringMath.woodenStep(
                        wrongHeading,
                        target,
                        distance,
                        currentDt[index],
                        load.toDouble(),
                        axle,
                        wrongRate,
                        false,
                        CartSteeringMath.Step(),
                    )
                close(
                    step.turn(),
                    reference.turn(),
                    "deferred root cadence preserves spatial yaw against its producer-interval reference",
                )
                close(step.x(), reference.x(), "deferred root cadence preserves rolling X")
                close(step.y(), reference.y(), "deferred root cadence preserves rolling Y")
                check(step.turn() * sign >= 0, "a continuous wall guide must not reverse its yaw")
                val curvature = Math.abs(step.turn()) / distance
                val wrongCurvature = Math.abs(wrong.turn()) / distance
                val nextTrend =
                    if (Math.abs(curvature - previousCurvature) > .01)
                        (if (curvature > previousCurvature) 1 else -1)
                    else 0
                val nextWrongTrend =
                    if (Math.abs(wrongCurvature - previousWrongCurvature) > .01)
                        (if (wrongCurvature > previousWrongCurvature) 1 else -1)
                    else 0
                if (nextTrend != 0) {
                    if (trend != 0 && trend != nextTrend) curvatureReversals++
                    trend = nextTrend
                }
                if (nextWrongTrend != 0) {
                    if (wrongTrend != 0 && wrongTrend != nextWrongTrend) wrongCurvatureReversals++
                    wrongTrend = nextWrongTrend
                }
                previousCurvature = curvature
                previousWrongCurvature = wrongCurvature
                heading = CartSteeringMath.wrap(heading + step.turn())
                referenceHeading = CartSteeringMath.wrap(referenceHeading + reference.turn())
                wrongHeading = CartSteeringMath.wrap(wrongHeading + wrong.turn())
                // The next guide rate must use the same spatial interval, rather than reintroducing
                // wall-clock jitter.
                rate = step.turn() / seconds
                referenceRate = reference.turn() / producerDt
                wrongRate = wrong.turn() / currentDt[index]
            }
            check(
                curvatureReversals <= 1,
                "wall curvature may accelerate then settle, without repeated clock-induced reversals",
            )
            check(
                wrongCurvatureReversals > 5,
                "lagged-budget regression must expose the original current-dt curvature chatter",
            )
            close(heading, target, "irregular native cadence still completes the guided turn")
        }
    }

    private fun woodenArc() {
        val axle = 1.0224308175
        for (load in intArrayOf(0, 1)) for (sign in intArrayOf(-1, 1)) {
            var reference: DoubleArray? = null
            for (fps in intArrayOf(30, 60, 144)) {
                val speed = if (load == 0) 1.3 else .83
                var h = 0.0
                var x = 0.0
                var y = 0.0
                var settled = 0.0
                for (frame in 0 until fps * 4) {
                    val step =
                        CartSteeringMath.step(
                            h,
                            sign * Math.PI / 2,
                            speed / fps,
                            1.0 / fps,
                            load.toDouble(),
                            axle,
                            45.0,
                            CartSteeringMath.Step(),
                        )
                    val chord = 2 * axle * Math.sin(step.turn() / 2)
                    check(
                        Math.abs(step.travel()) >= Math.abs(chord) - 1e-10,
                        "wooden wheel keeps advancing at least as far as the sideways handle movement",
                    )
                    close(
                        Math.hypot(step.x(), step.y()),
                        speed / fps,
                        "wooden arc preserves walking speed",
                    )
                    rolling(h, step.turn(), axle, .033440793, step.x(), step.y())
                    val bank = CartSteeringMath.rollingLean(step.turn(), step.travel(), 1.0 / fps)
                    check(
                        sign * bank >= 0 && Math.abs(bank) <= Math.toRadians(7.0),
                        "wooden bank follows its turn within the calibrated grip range",
                    )
                    x += step.x()
                    y += step.y()
                    h += step.turn()
                    check(sign * y >= -.47, "wooden arc avoids a large outside lunge")
                    if (settled == 0.0 && h == sign * Math.PI / 2) settled = (frame + 1.0) / fps
                }
                check(
                    settled > 0 && settled < (if (load == 0) 2.3 else 3.6),
                    "rolling arc still responds promptly",
                )
                val baseline = reference
                if (baseline == null) reference = doubleArrayOf(x, y, h)
                else
                    check(
                        Math.hypot(x - baseline[0], y - baseline[1]) < .015 &&
                            Math.abs(h - baseline[2]) < .002,
                        "wooden arc is frame-rate independent",
                    )
            }
        }
        close(CartSteeringMath.rollingLean(.01, 0.0, 1.0 / 60), 0.0, "blocked wheel cannot bank")
        close(CartSteeringMath.rollingLean(0.0, .03, 1.0 / 60), 0.0, "straight wheel cannot sway")
        close(CartSteeringMath.rollingLean(.01, .02, 0.0), 0.0, "paused wheel cannot bank")
        close(
            CartSteeringMath.rollingLean(.01, -.02, 1.0 / 60),
            -CartSteeringMath.rollingLean(.01, .02, 1.0 / 60),
            "reverse bank follows rolling direction",
        )
        close(
            CartSteeringMath.rollingLean(.01, .02, 1.0 / 60),
            CartSteeringMath.rollingLean(.02, .04, 1.0 / 30),
            "bank is frame-rate independent",
        )
    }

    private fun woodenTransitions() {
        for (fps in intArrayOf(30, 60, 144)) {
            var bank = CartSteeringMath.Bank()
            val dt = 1.0 / fps
            val cap = Math.toRadians(7.0)
            for (frame in 0 until fps * 2) {
                bank.update(cap, dt)
                close(
                    Math.max(bank.pressure, Math.abs(bank.angle)),
                    bank.angle,
                    "single-sided bank must preserve the accepted pose",
                )
            }
            var minimum = cap
            for (frame in 0 until fps * 3) {
                bank.update(if ((frame / (fps / 3)) % 2 == 0) -cap else cap, dt)
                check(
                    bank.pressure >= 0 && bank.pressure <= cap + 1e-12,
                    "slalom pressure must retain the clearance envelope without exceeding seven degrees",
                )
                if (Math.abs(bank.angle) < Math.toRadians(1.0))
                    minimum = Math.min(minimum, bank.pressure)
            }
            check(
                minimum > Math.toRadians(3.5),
                "changing bank must not retract the handles through neutral",
            )
            for (frame in 0 until fps) bank.update(0.0, dt)
            check(bank.pressure < .00035, "straight input must release slalom pressure promptly")
            val pressure = bank.pressure
            bank.update(cap, 0.0)
            close(bank.pressure, pressure, "pause cannot change clearance pressure")
            bank = CartSteeringMath.Bank()
            for (frame in 0 until fps * 2) bank.update(
                Math.toRadians((if (frame % 2 == 0) 1 else -1).toDouble()),
                dt,
            )
            check(
                Math.max(bank.pressure, Math.abs(bank.angle)) < Math.toRadians(.01),
                "alternating coordinate noise must not accumulate clearance pressure",
            )
        }
        for (sign in intArrayOf(-1, 1)) {
            close(
                CartSteeringMath.woodenBankExtra(Math.toRadians((sign * 3).toDouble()).toFloat())
                    .toDouble(),
                0.0,
                "small bank preserves the accepted arm pose",
            )
            check(
                Math.abs(
                    CartSteeringMath.woodenBankExtra(
                        Math.toRadians((sign * 5).toDouble()).toFloat(),
                    ) - .5,
                ) < 1e-6,
                "extra arm compensation reaches its midpoint smoothly",
            )
            close(
                CartSteeringMath.woodenBankExtra(Math.toRadians((sign * 7).toDouble()).toFloat())
                    .toDouble(),
                1.0,
                "seven-degree bank has full shoulder/elbow compensation",
            )
            check(
                Math.abs(
                    CartSteeringMath.woodenShift(
                        Math.toRadians((sign * 7).toDouble()).toFloat(),
                        -.12f,
                    ) + .205f,
                ) < 1e-7,
                "strong bank keeps the selected longitudinal hand clearance and native gait shift",
            )
            for (edge in intArrayOf(3, 7)) {
                val before =
                    CartSteeringMath.woodenBankExtra(Math.toRadians(sign * (edge - .001)).toFloat())
                val after =
                    CartSteeringMath.woodenBankExtra(Math.toRadians(sign * (edge + .001)).toFloat())
                check(
                    Math.abs(after - before) < 1e-6,
                    "shoulder/elbow compensation has no velocity corner at its endpoints",
                )
            }
        }
        val axle = 1.0224308175
        for (load in intArrayOf(0, 1)) for (sign in intArrayOf(-1, 1)) {
            var reference: DoubleArray? = null
            for (fps in intArrayOf(30, 60, 144)) {
                val dt = 1.0 / fps
                val speed = if (load == 0) 1.3 else .83
                var h = 0.0
                var x = 0.0
                var y = 0.0
                var rate = 0.0
                var settled = 0.0
                val bank = CartSteeringMath.Bank()
                val step = CartSteeringMath.Step()
                for (frame in 0 until fps * 4) {
                    CartSteeringMath.woodenStep(
                        h,
                        sign * Math.PI / 2,
                        speed * dt,
                        dt,
                        load.toDouble(),
                        axle,
                        rate,
                        step,
                    )
                    val nextRate = step.turn() / dt
                    if (frame == 0)
                        check(
                            Math.abs(nextRate) <= 6 * dt + 1e-10,
                            "wood turn builds pressure instead of jumping to full yaw rate",
                        )
                    check(
                        Math.abs(nextRate - rate) <= 8 * dt + .015,
                        "entry and exit have bounded angular acceleration",
                    )
                    rate = nextRate
                    close(
                        Math.hypot(step.x(), step.y()),
                        speed * dt,
                        "smooth steering preserves native speed",
                    )
                    rolling(h, step.turn(), axle, .033440793, step.x(), step.y())
                    val before = bank.angle
                    bank.update(CartSteeringMath.rollingLean(step.turn(), step.travel(), dt), dt)
                    check(
                        sign * bank.angle >= -1e-10 && Math.abs(bank.angle) <= Math.toRadians(7.0),
                        "bank stays inside held turn without overshoot",
                    )
                    check(
                        Math.abs(bank.angle - before) < .7 * dt,
                        "hand pressure transition stays continuous",
                    )
                    h += step.turn()
                    x += step.x()
                    y += step.y()
                    check(
                        sign * h <= Math.PI / 2 + 1e-10,
                        "smooth turn cannot overshoot the held heading",
                    )
                    if (settled == 0.0 && Math.abs(h - sign * Math.PI / 2) < 1e-9)
                        settled = (frame + 1.0) / fps
                }
                check(
                    settled > 0 && settled < (if (load == 0) 2.5 else 3.8),
                    "smoothing keeps wooden steering responsive",
                )
                val baseline = reference
                if (baseline == null) reference = doubleArrayOf(x, y)
                else
                    check(
                        Math.hypot(x - baseline[0], y - baseline[1]) < .035,
                        "smooth wood trajectory is stable across FPS",
                    )
                // A quick opposite input must pass through zero turn rate, not flip its sign at
                // full speed.
                rate = sign * .45
                CartSteeringMath.woodenStep(
                    h,
                    h - sign * Math.PI / 2,
                    speed * dt,
                    dt,
                    load.toDouble(),
                    axle,
                    rate,
                    step,
                )
                check(
                    sign * step.turn() > 0 && Math.abs(step.turn() / dt - rate) <= 6 * dt + 1e-10,
                    "quick reversal releases previous steering pressure first",
                )
            }
        }
        var reference = 0.0
        for (fps in intArrayOf(30, 60, 144)) {
            val bank = CartSteeringMath.Bank()
            val dt = 1.0 / fps
            close(bank.update(.18, 0.0), 0.0, "pause cannot change bank")
            for (i in 0 until fps) bank.update(.18, dt)
            if (reference == 0.0) reference = bank.angle
            else close(bank.angle, reference, "bank dynamics are frame-rate independent")
            check(
                bank.angle > .179 && bank.angle <= .18,
                "bank reaches pressure promptly without oscillating",
            )
            for (i in 0 until fps / 2) bank.update(0.0, dt)
            check(
                bank.angle >= 0 && bank.angle < .004,
                "stopping smoothly rights the cart within half a second",
            )
            for (i in 0 until fps) bank.update(-.18, dt)
            check(bank.angle < -.179 && bank.angle >= -.18, "opposite bank remains bounded")
        }
    }

    private fun reversalChecks() {
        check(
            CartSteeringMath.directionIntent(0.0, Math.toRadians(136.0), 0) == -1,
            "initial reverse keeps the native135 boundary",
        )
        check(
            CartSteeringMath.directionIntent(0.0, Math.toRadians(136.0), 1) == 1,
            "forward intent cannot chatter inside the deadband",
        )
        check(
            CartSteeringMath.directionIntent(0.0, Math.toRadians(141.0), 1) == -1,
            "forward intent enters reverse beyond140 degrees",
        )
        check(
            CartSteeringMath.directionIntent(0.0, Math.toRadians(134.0), -1) == -1,
            "reverse intent stays latched inside the deadband",
        )
        check(
            CartSteeringMath.directionIntent(0.0, Math.toRadians(129.0), -1) == 1,
            "reverse exits below130 degrees",
        )
        for (reverse in booleanArrayOf(false, true)) {
            val step =
                CartSteeringMath.woodenStep(
                    0.0,
                    Math.toRadians(134.0),
                    .02,
                    1.0 / 60,
                    0.0,
                    1.1,
                    0.0,
                    reverse,
                    CartSteeringMath.Step(),
                )
            check(
                (step.travel() < 0) == reverse,
                "latched travel sign must not be reclassified at135 degrees",
            )
            close(
                Math.hypot(step.x(), step.y()),
                .02,
                "latched reversal retains the native movement budget",
            )
            rolling(0.0, step.turn(), 1.1, 0.0, step.x(), step.y())
        }
        for (sign in intArrayOf(-1, 1)) for (fps in intArrayOf(10, 30, 60, 144)) for (load in
            doubleArrayOf(0.0, 1.0)) {
            val mode = CartSteeringMath.Reversal()
            mode.direction = sign
            val pace = CartLegPace.Ramp()
            pace.reset(3.0)
            check(mode.request(-sign, false), "a moving sign change must brake first")
            var previous = pace.speed
            var zeroTime = 0.0
            var crossed = false
            for (frame in 0 until fps * 4) {
                val braking = mode.braking
                var speed = pace.update(if (braking) 0.0 else .8, 1.0 / fps, load)
                if (braking && pace.settled(0.0)) {
                    pace.reset(0.0)
                    speed = 0.0
                }
                if (braking) {
                    check(speed <= previous + 1e-10, "braking cannot accelerate the old direction")
                    if (speed == 0.0 && previous == 0.0) zeroTime += 1.0 / fps
                    mode.stopped(1.0 / fps, speed == 0.0, previous == 0.0)
                    if (!mode.braking) {
                        check(
                            zeroTime >= .08 - 1e-10,
                            "native needs an evaluated neutral pose before changing sign",
                        )
                        check(
                            speed == 0.0 && mode.direction == -sign,
                            "direction changes only at exactly zero root speed",
                        )
                        crossed = true
                    }
                } else
                    check(
                        speed >= previous - 1e-10 && speed <= .8,
                        "new direction accelerates without overshoot",
                    )
                previous = speed
            }
            check(
                crossed && pace.settled(.8),
                "both loaded directions must complete at every supported FPS",
            )
        }
        val mode = CartSteeringMath.Reversal()
        mode.request(-1, false)
        mode.stopped(.1, true, false)
        check(
            mode.direction == 1 && mode.braking,
            "collision/root disagreement cannot commit a sign change",
        )
        mode.request(1, false)
        check(
            mode.active && !mode.braking && mode.direction == 1,
            "repeated input can resume the original direction while braking",
        )
        mode.request(-1, false)
        mode.request(0, false)
        check(
            !mode.active && !mode.braking && mode.direction == 1,
            "released input cannot leave a delayed reverse request",
        )
        mode.request(-1, true)
        check(
            mode.direction == -1 && !mode.active,
            "starting backwards from rest needs no artificial brake",
        )
    }

    private fun stationaryChecks() {
        for (fps in intArrayOf(30, 60, 144)) for (sign in intArrayOf(-1, 1)) for (load in
            doubleArrayOf(0.0, 1.0)) {
            var heading = .3
            val initial = heading
            var x = 0.0
            var y = 0.0
            var rate = 0.0
            val axle = 1.01
            val dt = 1.0 / fps
            val step = CartSteeringMath.Step()
            for (frame in 0 until fps * 4) {
                val budget = (if (load == 0.0) 1.3 else .83) * dt
                CartSteeringMath.stationaryStep(
                    heading,
                    initial + sign * Math.PI / 2,
                    budget,
                    dt,
                    load,
                    axle,
                    rate,
                    step,
                )
                check(
                    Math.hypot(step.x(), step.y()) <= budget + 1e-12,
                    "stationary turn cannot invent native root movement",
                )
                close(step.travel(), 0.0, "stationary turn keeps the wheel planted")
                close(
                    CartSteeringMath.acceptedTurn(heading, axle, step.x(), step.y()),
                    step.turn(),
                    "accepted chord determines stationary yaw",
                )
                check(
                    sign * step.turn() >= 0,
                    "stationary turn cannot move in the opposite direction",
                )
                x += step.x()
                y += step.y()
                heading += step.turn()
                rate = step.turn() / dt
                close(
                    x + axle * Math.cos(heading),
                    axle * Math.cos(initial),
                    "stationary wheel X stays fixed",
                )
                close(
                    y + axle * Math.sin(heading),
                    axle * Math.sin(initial),
                    "stationary wheel Y stays fixed",
                )
            }
            close(
                heading,
                initial + sign * Math.PI / 2,
                "stationary turn finishes at every cargo/FPS",
            )
            CartSteeringMath.stationaryStep(heading, heading + 1, 0.0, dt, load, axle, rate, step)
            check(
                step.x() == 0.0 && step.y() == 0.0 && step.turn() == 0.0,
                "without a native step the planted character cannot yaw",
            )
            CartSteeringMath.stationaryStep(heading, heading, 1.0, dt, load, axle, .4, step)
            check(step.turn() == 0.0, "release consumes no residual strafe budget")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        stationaryChecks()
        reversalChecks()
        val idle = CartSteeringMath.step(0.0, Math.PI / 2, 0.0, 1.0 / 60, 0.0)
        check(idle.turn() == 0.0 && idle.x() == 0.0 && idle.y() == 0.0, "idle cannot spin")
        val pivot = CartSteeringMath.step(0.0, Math.PI / 2, 0.03, 1.0 / 60, 0.0)
        close(pivot.travel(), 0.0, "lateral cart intent keeps axle stationary")
        close(pivot.x() + L * Math.cos(pivot.turn()), L, "pivot axle X")
        close(pivot.y() + L * Math.sin(pivot.turn()), 0.0, "pivot axle Y")
        check(pivot.y() < 0 && pivot.turn() > 0, "handle sidesteps opposite cart yaw")
        val fast = CartSteeringMath.step(0.0, Math.PI / 2, 0.08, 1.0 / 60, 0.0)
        val full = CartSteeringMath.step(0.0, Math.PI / 2, 0.08, 1.0 / 60, 1.0)
        check(fast.turn() > full.turn() && full.turn() > 0, "cargo limits yaw")
        check(!CartSteeringMath.reversing(0.0, Math.PI * .75), "135 degrees remains a forward arc")
        check(
            CartSteeringMath.reversing(0.0, Math.PI),
            "opposite input requests reverse, not an instant U-turn",
        )
        wheelbarrowChecks()
        woodenArc()
        wallClockChecks()
        woodenTransitions()
        val reverse = CartSteeringMath.step(0.0, Math.PI, 0.03, 1.0 / 60, 0.0)
        close(reverse.x(), -0.03, "reverse escapes head-on wall")
        close(reverse.y(), 0.0, "reverse stays on axis")
        close(reverse.turn(), 0.0, "reverse cannot spin into U-turn")
        close(CartSteeringMath.acceptedFraction(pivot, 0.0, 0.0), 0.0, "wall stops yaw")
        close(
            CartSteeringMath.acceptedFraction(pivot, pivot.x() / 2, pivot.y() / 2),
            0.5,
            "partial collision scales yaw",
        )
        close(
            CartSteeringMath.acceptedFraction(pivot, -pivot.y(), pivot.x()),
            0.0,
            "perpendicular wall slide cannot steer",
        )
        val reusable = CartSteeringMath.Step()
        for (load in doubleArrayOf(-1.0, 0.0, 0.5, 1.0, 2.0)) for (budget in
            doubleArrayOf(0.0, 0.0001, 0.03, 0.5)) {
            for (degrees in -180..180) {
                check(
                    CartSteeringMath.step(
                        0.7,
                        0.7 + Math.toRadians(degrees.toDouble()),
                        budget,
                        1.0 / 60,
                        load,
                        reusable,
                    ) === reusable,
                    "result reused",
                )
                check(
                    Math.hypot(reusable.travel(), 2 * L * Math.sin(reusable.turn() / 2)) <=
                        budget + 1e-12,
                    "translation and yaw share native budget",
                )
                check(
                    Math.hypot(reusable.x(), reusable.y()) <= budget + 1e-12,
                    "no displacement/speed gain",
                )
                val next = 0.7 + reusable.turn()
                close(
                    reusable.x() + L * Math.cos(next) - L * Math.cos(0.7),
                    reusable.travel() * Math.cos(0.7 + reusable.turn() / 2),
                    "rolling axle X",
                )
                close(
                    reusable.y() + L * Math.sin(next) - L * Math.sin(0.7),
                    reusable.travel() * Math.sin(0.7 + reusable.turn() / 2),
                    "rolling axle Y",
                )
            }
        }
        for (fps in intArrayOf(30, 60, 144)) {
            var h = 0.0
            var x = 0.0
            var y = 0.0
            for (i in 0 until fps) {
                val step = CartSteeringMath.step(h, h + Math.PI / 2, 1.8 / fps, 1.0 / fps, 0.0)
                x += step.x()
                y += step.y()
                h += step.turn()
            }
            close(h, 2.25, "frame-independent pivot yaw")
            close(x + L * Math.cos(h), L, "frame-independent fixed axle X")
            close(y + L * Math.sin(h), 0.0, "frame-independent fixed axle Y")
        }
        for (fps in intArrayOf(30, 60, 144)) {
            var h = 0.0
            var previousTravel = 0.0
            var travelled = 0.0
            var flat = 0
            for (frame in 0 until fps * 4) {
                val step = CartSteeringMath.step(h, Math.PI / 2, 1.8 / fps, 1.0 / fps, 0.0)
                h += step.turn()
                travelled += step.travel()
                if (step.travel() < 1e-8) flat++
                check(
                    step.travel() + 1e-10 >= previousTravel,
                    "turn rolls progressively, without stopping",
                )
                check(
                    step.travel() - previousTravel < 0.16 * 1.8 / fps,
                    "no sudden pivot-to-forward release",
                )
                previousTravel = step.travel()
            }
            check(flat <= 1, "cart cannot stay parked while turning")
            check(travelled > 4 && h > Math.PI / 2 - 0.01, "held turn becomes forward rolling")
        }
        for ((distance, seconds) in arrayOf(Double.NaN to .1, .1 to Double.NaN)) {
            CartSteeringMath.step(0.0, Math.PI / 4, .03, .1, 0.0, reusable)
            check(
                CartSteeringMath.step(0.0, Math.PI / 2, distance, seconds, 0.0, reusable) ===
                    reusable &&
                    reusable.x() == 0.0 &&
                    reusable.y() == 0.0 &&
                    reusable.turn() == 0.0 &&
                    reusable.travel() == 0.0,
                "unknown distance or time must clear the reused result",
            )
        }
        val pausedBank = CartSteeringMath.Bank()
        pausedBank.update(.18, .1)
        val bankState =
            doubleArrayOf(
                pausedBank.angle,
                pausedBank.velocity,
                pausedBank.pressure,
                pausedBank.pressureVelocity,
            )
        pausedBank.update(-.18, Double.NaN)
        check(
            bankState.contentEquals(
                doubleArrayOf(
                    pausedBank.angle,
                    pausedBank.velocity,
                    pausedBank.pressure,
                    pausedBank.pressureVelocity,
                ),
            ),
            "unknown time must leave every bank state component unchanged",
        )
        CartSteeringMath.step(0.0, Math.PI / 2, 0.0, 1.0 / 60, 0.0, reusable)
        check(
            reusable.x() == 0.0 &&
                reusable.y() == 0.0 &&
                reusable.turn() == 0.0 &&
                reusable.travel() == 0.0,
            "idle clears reused result",
        )
        println("CART_STEERING_MATH_PASS (pivot, reverse, budget, cargo, FPS, collision)")
    }
}
