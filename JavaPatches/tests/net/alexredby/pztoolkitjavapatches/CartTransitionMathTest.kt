package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f

object CartTransitionMathTest {
    private fun check(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun close(a: Number, b: Number, epsilon: Double, message: String) {
        check(Math.abs(a.toDouble() - b.toDouble()) <= epsilon, "$message: $a != $b")
    }

    private fun pose(yaw: Float) =
        CartTransitionMath.Placement(10.23f, -7.68f, 2.00475f, 0f, yaw, 0f, .8503f)

    private fun phase(fraction: Double, setdown: Boolean): CartTransitionMath.Progress =
        CartTransitionMath.progress(fraction, setdown)
            ?: throw AssertionError("finite progress rejected: $fraction")

    private fun model(): Matrix4f =
        Matrix4f().translation(.04f, -.02f, .03f).rotateX(Math.toRadians(90.0).toFloat()).scale(90f)

    private fun roundtrips() {
        val model = model()
        val before = Matrix4f(model)
        for (yaw in
            floatArrayOf(
                0f,
                45f,
                90f,
                135f,
                180f,
                225f,
                270f,
                315f,
                17.3f,
                -53.2f,
                359.99f,
            )) for (actorAngle in floatArrayOf(0f, .17f, 1.7f, -2.3f)) for (tilt in
            arrayOf(floatArrayOf(0f, 0f), floatArrayOf(13f, -21f), floatArrayOf(-34f, 72f))) {
            val pose =
                CartTransitionMath.Placement(
                    10.23f,
                    -7.68f,
                    2.00475f,
                    tilt[0],
                    yaw,
                    tilt[1],
                    .8503f,
                )
            val actor = Matrix4f()
            check(
                CartTransitionMath.worldToActor(pose, model, 9.8f, -8.4f, 2f, actorAngle, actor),
                "world pose accepted",
            )
            val actorBefore = Matrix4f(actor)
            val result =
                CartTransitionMath.actorToWorldPlacement(actor, model, 9.8f, -8.4f, 2f, actorAngle)
                    ?: throw AssertionError("uniform pose decomposed at $yaw")
            close(result.x, pose.x, .00001, "world X roundtrip")
            close(result.y, pose.y, .00001, "world Y roundtrip")
            close(result.z, pose.z, .00001, "world Z roundtrip")
            close(result.worldScale, pose.worldScale, .00001, "scale roundtrip")
            val second = Matrix4f()
            check(
                CartTransitionMath.worldToActor(result, model, 9.8f, -8.4f, 2f, actorAngle, second),
                "reverse pose accepted",
            )
            check(
                actor.equals(second, .0001f),
                "native X/Z/Y Euler roundtrip at $yaw tilt ${tilt[0]}",
            )
            check(actor == actorBefore, "inverse does not mutate transform")
            val point = Vector3f(.002f, -.003f, .004f)
            val local = actor.transformPosition(point, Vector3f())
            val c = Math.cos(actorAngle.toDouble())
            val s = Math.sin(actorAngle.toDouble())
            val actualX = 9.8 - 1.5 * (c * local.x + s * local.z)
            val actualY = -8.4 + 1.5 * (-s * local.x + c * local.z)
            val world =
                Matrix4f()
                    .rotationXYZ(
                        Math.toRadians(pose.xRotation.toDouble()).toFloat(),
                        Math.toRadians(pose.zRotation.toDouble()).toFloat(),
                        Math.toRadians(pose.yRotation.toDouble()).toFloat(),
                    )
                    .mul(model)
                    .scale(pose.worldScale)
            val expected = world.transformPosition(point, Vector3f())
            close(actualX, pose.x + 1.5 * expected.x, .00001, "same native world X")
            close(actualY, pose.y - 1.5 * expected.z, .00001, "same native world Y")
            close(
                2 + local.y * 1.5 / 2.44949,
                pose.z + expected.y * 1.5 / 2.44949,
                .00001,
                "same native world height",
            )
        }
        check(model == before, "world conversion does not mutate mesh/attachment matrix")
    }

    private fun timingAndBlend() {
        val from = Matrix4f().translation(.1f, .2f, -.3f).rotateX(.2f).scale(76.5f)
        val to = Matrix4f().translation(-.4f, .8f, .7f).rotateY(2.8f).scale(90f)
        val fromBefore = Matrix4f(from)
        val toBefore = Matrix4f(to)
        val actual = Matrix4f()
        var previous = -1.0
        var last = phase(0.0, false)
        for (i in 0..1000) {
            val p = i / 1000.0
            val amount = CartTransitionMath.smooth(p)
            check(amount >= previous && amount >= 0 && amount <= 1, "monotonic bounded easing")
            previous = amount
            val phase = phase(p, false)
            check(phase.crouch >= last.crouch, "continuous body lowering")
            check(
                phase.center >= 0 &&
                    phase.center <= 1 &&
                    phase.balance >= 0 &&
                    phase.balance <= 1 &&
                    phase.hinge >= 0 &&
                    phase.hinge <= 1 &&
                    phase.knees >= 0 &&
                    phase.knees <= 1,
                "bounded stance correction",
            )
            check(
                phase.reach >= last.reach && phase.grip >= last.grip && phase.lift >= last.lift,
                "monotonic phases",
            )
            check(
                phase.grip == 0.0 || CartTransitionMath.smooth(phase.reach) > .95,
                "fingers close only within the final few millimetres of reach",
            )
            check(phase.lift == 0.0 || phase.grip == 1.0, "grip finishes before lift")
            val inverse = phase(1 - p, true)
            close(phase.crouch, inverse.crouch, 1e-12, "setdown standing reverses crouch")
            close(phase.center, inverse.center, 1e-12, "setdown reverses centering")
            close(phase.balance, inverse.balance, 1e-12, "setdown reverses weight shift")
            close(phase.hinge, inverse.hinge, 1e-12, "setdown reverses hip hinge")
            close(phase.knees, inverse.knees, 1e-12, "setdown reverses knee bend")
            close(phase.reach, inverse.reach, 1e-12, "setdown reach reverses pickup")
            close(phase.grip, inverse.grip, 1e-12, "setdown release reverses grip")
            close(phase.lift, inverse.lift, 1e-12, "setdown lower reverses lift")
            check(CartTransitionMath.blend(from, to, p, actual), "rigid blend accepted")
            close(
                actual.getColumn(0, Vector3f()).length(),
                76.5 + (90 - 76.5) * p,
                .00004,
                "uniform blended scale",
            )
            val x = actual.getColumn(0, Vector3f()).normalize()
            val y = actual.getColumn(1, Vector3f()).normalize()
            close(x.dot(y), 0, .00001, "slerp adds no shear")
            last = phase
        }
        check(
            CartTransitionMath.blend(from, to, 0.0, actual) && actual == from,
            "exact first endpoint",
        )
        check(
            CartTransitionMath.blend(from, to, 1.0, actual) && actual == to,
            "exact final endpoint",
        )
        close(CartTransitionMath.smooth(.00001) / .00001, 0, .00000001, "zero starting velocity")
        close(
            (1 - CartTransitionMath.smooth(.99999)) / .00001,
            0,
            .00000001,
            "zero finishing velocity",
        )
        check(from == fromBefore && to == toBefore, "blend does not mutate endpoints")
        var t = .24
        while (t < .44) {
            val before = phase(t, false)
            val after = phase(t + .0001, false)
            check(
                after.crouch > before.crouch && after.reach > before.reach,
                "body bending and reaching must move together without a crouch wait",
            )
            t += .001
        }
        check(
            phase(.44, false).grip > 0 && phase(.48, false).grip == 1.0,
            "only final finger closure remains once the body has reached the handles",
        )
        check(
            phase(0.0, true) == CartTransitionMath.Progress(1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0),
            "setdown starts holding",
        )
        check(
            phase(1.0, true) == CartTransitionMath.Progress(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
            "setdown ends released",
        )
        t = 0.0
        while (t <= .44) {
            val phase = phase(t, false)
            close(phase.knees, phase.crouch, 1e-12, "knees and torso descend together")
            close(
                phase.balance,
                phase.crouch,
                1e-12,
                "pelvis must not finish retreating before the torso bends",
            )
            t += .001
        }
        check(phase(.20, false).balance < .5, "no early full pelvis retreat")
        check(
            phase(.10, false).center == 1.0 && phase(.44, false).balance == 1.0,
            "centering leads the bend and weight shift follows it",
        )
        close(
            phase(.000001, false).balance / .000001,
            0,
            .000001,
            "zero starting weight-shift velocity",
        )
        val coarseVelocity = phase(.9999, false).balance / .0001
        val fineVelocity = phase(.999999, false).balance / .000001
        check(
            fineVelocity < coarseVelocity * .2,
            "weight-shift velocity tends to zero at the endpoint",
        )
    }

    private fun stances() {
        val left = Vector3f(.00172237f, .00541905f, -.00342593f)
        val right = Vector3f(-.00172238f, .00541905f, -.00342593f)
        val held =
            Matrix4f()
                .translation(-.0060535767f, .097179376f, -.34652624f)
                .rotateX(Math.toRadians(74.24).toFloat())
                .scale(76.5f)
        val model = model()
        val modelBefore = Matrix4f(model)
        val heldBefore = Matrix4f(held)
        val leftBefore = Vector3f(left)
        val rightBefore = Vector3f(right)
        for (yaw in floatArrayOf(0f, 45f, 90f, 135f, 180f, 225f, 270f, 315f, 23.7f)) {
            val pose = pose(yaw)
            val stance =
                CartTransitionMath.stance(pose, model, held, left, right)
                    ?: throw AssertionError("stance exists")
            val ground = Matrix4f()
            check(
                CartTransitionMath.worldToActor(
                    pose,
                    model,
                    stance.x,
                    stance.y,
                    stance.z,
                    stance.slotAngle,
                    ground,
                ),
                "stance projection",
            )
            val a = ground.transformPosition(left, Vector3f())
            val b = ground.transformPosition(right, Vector3f())
            val hA = held.transformPosition(left, Vector3f())
            val hB = held.transformPosition(right, Vector3f())
            close(
                (a.x + b.x) * .5,
                (hA.x + hB.x) * .5,
                .00001,
                "handle center aligned horizontally X",
            )
            close(
                (a.z + b.z) * .5,
                (hA.z + hB.z) * .5,
                .00001,
                "handle center aligned horizontally Z",
            )
            val d = a.sub(b).normalize()
            val hD = hA.sub(hB).normalize()
            close(d.x, hD.x, .00001, "ordered handles preserve facing X")
            close(d.z, hD.z, .00001, "ordered handles preserve facing Z")
        }
        check(
            model == modelBefore &&
                held == heldBefore &&
                left == leftBefore &&
                right == rightBefore,
            "stance has no input mutation",
        )
    }

    private fun recovery() {
        for (setdown in booleanArrayOf(false, true)) for (start in
            doubleArrayOf(0.0, .001, .15, .38, .44, .48, .55, .88, 1.0)) {
            val duration = .4 + .2 * start
            close(
                CartTransitionMath.recover(start, 0.0, setdown),
                start,
                0.0,
                "recovery starts at the interrupted pose",
            )
            close(
                CartTransitionMath.recover(start, -1.0, setdown),
                start,
                0.0,
                "early clock cannot advance recovery",
            )
            close(
                CartTransitionMath.recover(start, duration, setdown),
                0,
                0.0,
                "recovery reaches the exact native endpoint",
            )
            close(
                CartTransitionMath.recover(start, .600001, setdown),
                0,
                0.0,
                "recovery always ends within 600 ms",
            )
            var previous = start
            for (i in 0..1000) {
                val current = CartTransitionMath.recover(start, duration * i / 1000, setdown)
                check(
                    current.isFinite() && current >= 0 && current <= previous,
                    "recovery is finite, bounded and monotonic",
                )
                for (direction in booleanArrayOf(false, true)) {
                    val phase = phase(current, direction)
                    for (value in
                        doubleArrayOf(
                            phase.crouch,
                            phase.reach,
                            phase.grip,
                            phase.lift,
                            phase.center,
                            phase.balance,
                            phase.hinge,
                            phase.knees,
                        )) check(
                        value.isFinite() && value >= 0 && value <= 1,
                        "reverse pose dimensions remain finite and bounded",
                    )
                    check(
                        phase.lift == 0.0 || phase.grip == 1.0,
                        "recovery preserves grip before moving the cart",
                    )
                    check(
                        phase.grip == 0.0 || CartTransitionMath.smooth(phase.reach) > .95,
                        "recovery preserves reach before finger contact",
                    )
                }
                previous = current
            }
            val step = duration * .00001
            close(
                (start - CartTransitionMath.recover(start, step, setdown)) / step,
                0,
                .000001,
                "recovery starts without a velocity jump",
            )
            close(
                CartTransitionMath.recover(start, duration - step, setdown) / step,
                0,
                .000001,
                "recovery settles without endpoint velocity",
            )
        }
        close(
            CartTransitionMath.recover(-1.0, 0.0, false),
            0,
            0.0,
            "negative recovery progress clamps to released",
        )
        close(
            CartTransitionMath.recover(2.0, 0.0, false),
            1,
            0.0,
            "overshot recovery progress clamps to held",
        )
        for (invalid in
            doubleArrayOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            check(
                CartTransitionMath.recover(invalid, .1, false).isNaN(),
                "nonfinite recovery origin rejected",
            )
            check(
                CartTransitionMath.recover(.5, invalid, false).isNaN(),
                "nonfinite recovery clock rejected",
            )
        }
    }

    private fun recoveryRelease() {
        close(
            CartTransitionMath.recoveryRelease(.8, .88, true),
            10.0 / 11,
            1e-12,
            "late pickup releases the hip with recovered progress instead of freezing it through a second easing",
        )
        close(
            CartTransitionMath.recoveryRelease(.8, .88, false),
            160000.0 / 161051,
            1e-12,
            "setdown preserves the existing eased recovery weight",
        )
        for (pickup in booleanArrayOf(true, false)) for (start in doubleArrayOf(.15, .55, .88)) {
            val duration = .4 + .2 * start
            var previous = 1.0
            close(
                CartTransitionMath.recoveryRelease(start, start, pickup),
                1,
                0.0,
                "body recovery preserves the captured first frame",
            )
            close(
                CartTransitionMath.recoveryRelease(0.0, start, pickup),
                0,
                0.0,
                "body recovery reaches the native endpoint",
            )
            var frame = 0
            while (frame <= Math.ceil(duration * 60)) {
                val progress = CartTransitionMath.recover(start, frame / 60.0, !pickup)
                val weight = CartTransitionMath.recoveryRelease(progress, start, pickup)
                check(
                    weight.isFinite() && weight >= 0 && weight <= 1 && weight <= previous,
                    "60 Hz body recovery weights must remain finite, bounded and monotonic",
                )
                previous = weight
                frame++
            }
            close(previous, 0, 0.0, "60 Hz body recovery finishes within the existing duration")
            close(
                CartTransitionMath.recoveryRelease(
                    CartTransitionMath.recover(start, .600001, !pickup),
                    start,
                    pickup,
                ),
                0,
                0.0,
                "body recovery cannot extend the 600 ms lifetime",
            )
            val step = duration * .00001
            close(
                (1 -
                    CartTransitionMath.recoveryRelease(
                        CartTransitionMath.recover(start, step, !pickup),
                        start,
                        pickup,
                    )) / step,
                0,
                .00001,
                "body recovery starts without a velocity jump",
            )
            close(
                CartTransitionMath.recoveryRelease(
                    CartTransitionMath.recover(start, duration - step, !pickup),
                    start,
                    pickup,
                ) / step,
                0,
                .00001,
                "body recovery finishes without endpoint velocity",
            )
            close(
                CartTransitionMath.recoveryRelease(-1.0, start, pickup),
                0,
                0.0,
                "negative body progress clamps to native endpoint",
            )
            close(
                CartTransitionMath.recoveryRelease(start + 1, start, pickup),
                1,
                0.0,
                "overshot body progress clamps to captured pose",
            )
        }
        for (pickup in booleanArrayOf(true, false)) {
            for (invalid in
                doubleArrayOf(
                    0.0,
                    -1.0,
                    Double.NaN,
                    Double.POSITIVE_INFINITY,
                    Double.NEGATIVE_INFINITY,
                )) check(
                CartTransitionMath.recoveryRelease(.5, invalid, pickup).isNaN(),
                "invalid body recovery origin rejected",
            )
            for (invalid in
                doubleArrayOf(
                    Double.NaN,
                    Double.POSITIVE_INFINITY,
                    Double.NEGATIVE_INFINITY,
                )) check(
                CartTransitionMath.recoveryRelease(invalid, .5, pickup).isNaN(),
                "nonfinite body recovery progress rejected",
            )
        }
    }

    private fun recoveryClearance() {
        for (start in doubleArrayOf(0.0, .15, .48, .55, .88, 1.0)) {
            val duration = .4 + .2 * start
            val lift = phase(start, false).lift
            close(
                CartTransitionMath.recoveryClearance(start, 0.0),
                0,
                0.0,
                "clearance preserves the captured first pose",
            )
            close(
                CartTransitionMath.recoveryClearance(start, duration),
                0,
                0.0,
                "clearance reaches the native endpoint on time",
            )
            close(
                CartTransitionMath.recoveryClearance(start, duration / 2),
                lift / 4,
                1e-12,
                "clearance is bounded by the captured lift",
            )
            close(
                CartTransitionMath.recoveryClearance(start, -1.0),
                0,
                0.0,
                "clearance cannot start before cancellation",
            )
            close(
                CartTransitionMath.recoveryClearance(start, .600001),
                0,
                0.0,
                "clearance cannot extend the recovery lifetime",
            )
            var previous = 0.0
            var frame = 0
            while (frame <= Math.ceil(duration * 60)) {
                val weight = CartTransitionMath.recoveryClearance(start, frame / 60.0)
                check(
                    weight.isFinite() && weight >= 0 && weight <= lift / 4 + 1e-12,
                    "60 Hz clearance must remain finite and bounded",
                )
                check(
                    Math.abs(weight - previous) <= lift / (60 * duration) + 1e-12,
                    "clearance moved farther than one frame of its bounded trajectory",
                )
                if (lift == 0.0)
                    close(weight, 0, 0.0, "grounded pickup cannot acquire a clearance detour")
                previous = weight
                frame++
            }
            close(previous, 0, 0.0, "60 Hz clearance finishes within the existing deadline")
        }
        for (invalid in
            doubleArrayOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            check(
                CartTransitionMath.recoveryClearance(invalid, .1).isNaN(),
                "nonfinite clearance origin rejected",
            )
            check(
                CartTransitionMath.recoveryClearance(.88, invalid).isNaN(),
                "nonfinite clearance clock rejected",
            )
        }
        close(
            CartTransitionMath.recoveryClearance(-1.0, .1),
            0,
            0.0,
            "negative clearance origin clamps to grounded pickup",
        )
        close(
            CartTransitionMath.recoveryClearance(2.0, .3),
            .25,
            1e-12,
            "overshot clearance origin clamps to full lift",
        )
    }

    private fun recoveryPoseSteps() {
        for (setdown in booleanArrayOf(false, true)) for (start in
            doubleArrayOf(.15, .55, .88, 1.0)) {
            val duration = .4 + .2 * start
            var elapsed = 0.0
            while (elapsed < duration) {
                val before = phase(CartTransitionMath.recover(start, elapsed, setdown), setdown)
                val after =
                    phase(CartTransitionMath.recover(start, elapsed + 1.0 / 30, setdown), setdown)
                val balance = after.balance - before.balance
                val height =
                    CartTransitionMath.nativeHeight(after, .5566668, .26, .561988) -
                        CartTransitionMath.nativeHeight(before, .5566668, .26, .561988) -
                        .03 * balance
                val spineStep = Math.hypot(height, .16 * balance)
                check(
                    spineStep < .05,
                    "late recovery bunched the squat into one 33 ms pose step: $spineStep",
                )
                check(
                    recoveryWrist(before).distance(recoveryWrist(after)) < .07,
                    "late setdown bunched reaching or wheel lift into one 33 ms wrist step",
                )
                check(
                    Math.abs(
                        CartTransitionMath.smooth(after.reach) -
                            CartTransitionMath.smooth(before.reach),
                    ) < .30,
                    "late37 advanced over a third of hand contact in one frame",
                )
                elapsed += .001
            }
        }
    }

    private fun recoveryWrist(phase: CartTransitionMath.Progress): Vector3f {
        // Native36 anchors are a pacing proxy, not a rendered-frame replay.
        val reach = CartTransitionMath.smooth(phase.reach)
        val balance = phase.balance
        val lift = phase.lift
        return Vector3f(
            (.11 + .055 * reach).toFloat(),
            ((.50 - .03 * balance) * (1 - reach) + (.315 + .199 * lift) * reach).toFloat(),
            ((-.13 + .04 * balance) * (1 - reach) + (.013 - .031 * lift) * reach).toFloat(),
        )
    }

    private fun nativeHeight() {
        val idle = .56
        val low = .02
        val cart = .57
        close(
            CartTransitionMath.nativeHeight(phase(0.0, false), idle, low, cart),
            idle,
            0.0,
            "released height is native idle",
        )
        close(
            CartTransitionMath.nativeHeight(phase(1.0, false), idle, low, cart),
            cart,
            0.0,
            "held height is native cart idle",
        )
        close(
            CartTransitionMath.nativeHeight(phase(.44, false), idle, low, cart),
            .9 * idle + .1 * low,
            1e-12,
            "grounded crouch uses only the authored tenth of the low pose",
        )
        val mixed = CartTransitionMath.Progress(1.0, 1.0, 1.0, .5, 0.0, 0.0, 0.0, 0.0)
        close(
            CartTransitionMath.nativeHeight(mixed, idle, low, cart),
            .45 * idle + .05 * low + .5 * cart,
            1e-12,
            "lift reduces low and idle weights together in the 2D blend triangle",
        )
        for (setdown in booleanArrayOf(false, true)) for (start in doubleArrayOf(.55, .88)) {
            val offset = .008
            val first =
                CartTransitionMath.nativeHeight(phase(start, setdown), idle, low, cart) + offset
            val endpoint = CartTransitionMath.nativeHeight(phase(0.0, setdown), idle, low, cart)
            var previous = first
            for (i in 0..1000) {
                val elapsed = .601 * i / 1000
                val progress = CartTransitionMath.recover(start, elapsed, setdown)
                val target =
                    CartTransitionMath.nativeHeight(phase(progress, setdown), idle, low, cart) +
                        offset * progress / start
                val live = first + (endpoint - first) * CartTransitionMath.smooth(elapsed / .2)
                check(
                    target.isFinite() && Math.abs(target - live) < .2,
                    "native blend-out compensation stays within its safe correction bound",
                )
                check(
                    Math.abs(target - previous) < .001,
                    "native blend-out does not introduce a recovery height jump",
                )
                if (i == 0)
                    close(
                        target,
                        first,
                        1e-12,
                        "height recovery starts at the measured native pose",
                    )
                if (i == 1000)
                    close(
                        target,
                        endpoint,
                        1e-12,
                        "calibration offset fades completely at the native endpoint",
                    )
                previous = target
            }
        }
    }

    private fun invalid() {
        val sentinel = Matrix4f().translation(9f, 8f, 7f)
        val out = Matrix4f(sentinel)
        for (invalid in
            arrayOf(
                Matrix4f().scale(0f),
                Matrix4f().m00(Float.NaN),
                Matrix4f().m03(.1f),
                Matrix4f().scale(-1f, 1f, 1f),
                Matrix4f().scale(1f, 2f, 1f),
                Matrix4f().m10(.1f),
            )) {
            check(
                !CartTransitionMath.blend(invalid, Matrix4f(), .4, out),
                "invalid rigid transform rejected",
            )
            check(out == sentinel, "failure preserves output")
            check(
                CartTransitionMath.actorToWorldPlacement(invalid, Matrix4f(), 0f, 0f, 0f, 0f) ==
                    null,
                "inverse rejects invalid residual",
            )
        }
        check(
            !CartTransitionMath.worldToActor(pose(0f), Matrix4f().scale(0f), 0f, 0f, 0f, 0f, out),
            "singular model rejected",
        )
        check(
            !CartTransitionMath.worldToActor(pose(0f), model(), Float.NaN, 0f, 0f, 0f, out),
            "nonfinite actor rejected",
        )
        check(
            !CartTransitionMath.worldToActor(
                CartTransitionMath.Placement(0f, 0f, 0f, 0f, 0f, 0f, -1f),
                model(),
                0f,
                0f,
                0f,
                0f,
                out,
            ),
            "negative scale rejected",
        )
        check(
            !CartTransitionMath.blend(Matrix4f(), Matrix4f(), Double.NaN, out),
            "nonfinite blend rejected",
        )
        check(
            CartTransitionMath.smooth(Double.NaN).isNaN() &&
                CartTransitionMath.progress(Double.NaN, false) == null,
            "nonfinite timing rejected",
        )
        check(
            CartTransitionMath.stance(pose(0f), model(), Matrix4f(), Vector3f(), Vector3f()) ==
                null,
            "coincident handles rejected",
        )
        check(out == sentinel, "all validation failures preserve output")
    }

    private fun shopping() {
        val basis = Matrix4f().rotateX(.18f).scale(.00215f, .00161f, .10497f)
        val a = Matrix4f().translation(.1f, .2f, -.4f).rotateY(.3f).mul(basis)
        val b = Matrix4f().translation(.3f, .21f, -.5f).rotateY(.4f).mul(basis)
        for (step in 0..100) {
            val t = step / 100.0
            val out = Matrix4f()
            check(
                CartTransitionMath.blendModel(a, b, basis, t, out),
                "nonuniform imported basis rejected",
            )
            val residual = Matrix4f(out).mul(Matrix4f(basis).invert())
            close(residual.getColumn(0, Vector3f()).length(), 1, .00001, "mesh X scale changed")
            close(residual.getColumn(1, Vector3f()).length(), 1, .00001, "mesh Y scale changed")
            close(residual.getColumn(2, Vector3f()).length(), 1, .00001, "mesh Z scale changed")
            val p =
                CartShopping.progress(t, false)
                    ?: throw AssertionError("standing progress rejected")
            val reverse =
                CartShopping.progress(1 - t, true)
                    ?: throw AssertionError("standing reverse progress rejected")
            check(
                p.crouch == 0.0 && p.hinge == 0.0 && p.balance == 0.0 && p.knees == 0.0,
                "standing action crouched",
            )
            close(p.reach, reverse.reach, 1e-12, "standing reversal lost hand contact timing")
        }
        val held =
            CartShopping.held(Matrix4f())
                ?: throw AssertionError("shopping held calibration rejected")
        val imported = Matrix4f(held).setTranslation(0f, 0f, 0f)
        val left = Vector3f()
        val right = Vector3f()
        CartGrip.handle("ShoppingCartModel", true, left)
        CartGrip.handle("ShoppingCartModel", false, right)
        for (degrees in 0 until 360 step 15) {
            val angle = Math.toRadians(degrees.toDouble()).toFloat()
            val placement =
                CartTransition.shoppingDropPlacement(held, imported, 10f, 20f, 2f, angle, 1f)
                    ?: throw AssertionError("shopping drop yaw rejected")
            check(
                placement.zRotation >= 0 && placement.zRotation < 360,
                "shopping drop yaw rejected",
            )
            val stance =
                CartTransitionMath.stance(placement, imported, held, left, right)
                    ?: throw AssertionError("nonuniform shopping handle stance rejected")
            close(stance.x, 10, .00001, "shopping approach lost centered X")
            close(stance.y, 20, .00001, "shopping approach lost centered Y")
            close(
                CartSteeringMath.wrap((stance.slotAngle - angle).toDouble()),
                0,
                .00001,
                "shopping approach reversed facing",
            )
        }
        check(
            CartTransitionMath.stance(pose(0f), imported, null, left, right) == null,
            "null held pose accepted",
        )
        check(
            CartShopping.progress(Double.NaN, false) == null,
            "nonfinite shopping progress accepted",
        )
        val out = Matrix4f().translation(5f, 6f, 7f)
        val before = Matrix4f(out)
        check(
            !CartTransitionMath.blendModel(a, b, Matrix4f().scale(0f), .5, out),
            "singular mesh basis accepted",
        )
        check(out == before, "invalid model blend changed output")
        check(
            !CartTransitionMath.blendModel(a, Matrix4f(b).scale(1f, 2f, 1f), basis, .5, out),
            "residual shear accepted",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        shopping()
        roundtrips()
        timingAndBlend()
        stances()
        recovery()
        recoveryRelease()
        recoveryClearance()
        recoveryPoseSteps()
        nativeHeight()
        invalid()
        println(
            "PASS cart transition world/actor roundtrips, native Euler order, rigid interpolation, phase reversal and handle stance",
        )
    }
}
