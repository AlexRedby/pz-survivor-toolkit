package net.alexredby.pztoolkitjavapatches

/** Gait-field checks shared with the native steering-hook regression. */
object CartLocomotionBlendChecks {
    private fun check(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    @JvmStatic
    fun check() {
        for (gait in intArrayOf(CartLocomotionBlend.WALK, CartLocomotionBlend.RUN, CartLocomotionBlend.SPRINT)) {
            var previousX = Float.NaN
            var previousY = Float.NaN
            for (fps in intArrayOf(30, 60, 144)) {
                val blend = CartLocomotionBlend()
                blend.update(-.6f, .8f, 1.0 / fps, gait)
                var oldX = blend.x
                for (frame in 0 until fps) {
                    blend.update(.6f, .8f, 1.0 / fps, gait)
                    check(Math.abs(Math.hypot(blend.x.toDouble(), blend.y.toDouble()) - 1) < 1e-7 && blend.y > 0,
                        "gait steering changes must retain stride radius and forward travel: $gait/$fps")
                    check(blend.x >= oldX && blend.x <= .600001f,
                        "gait steering interpolation must not overshoot or reverse its response: $gait/$fps")
                    if (frame == 0) check(blend.x < 0, "one native frame must not flip the entire walking field: $fps")
                    oldX = blend.x
                    if (frame == fps / 3 - 1 && fps % 3 == 0) {
                        if (previousX.isFinite())
                            check(Math.abs(blend.x - previousX) < 2e-7 && Math.abs(blend.y - previousY) < 2e-7,
                                "equal elapsed time must yield the same gait field at different native frame rates")
                        previousX = blend.x; previousY = blend.y
                    }
                }
                check(Math.abs(blend.x - .6f) < 1e-6 && Math.abs(blend.y - .8f) < 1e-6,
                    "steady gait must recover its exact requested direction: $gait/$fps")
                blend.update(-.6f, .8f, 0.0, gait)
                check(Math.abs(blend.x - .6f) < 1e-6, "zero time must not advance the visual field")
                blend.update(-.6f, .8f, Double.NaN, gait)
                check(Math.abs(blend.x - .6f) < 1e-6, "unknown time must not advance the visual field")
                // Idle, reversal and special gait ownership must discard any old forward direction.
                for (target in arrayOf(floatArrayOf(0f, 0f), floatArrayOf(.3f, -.4f), floatArrayOf(.5f, 0f))) {
                    blend.update(-.6f, .8f, 1.0 / fps, gait)
                    blend.update(target[0], target[1], 1.0 / fps, gait)
                    check(blend.x == target[0] && blend.y == target[1], "non-forward fields must pass through unchanged")
                    blend.update(.6f, .8f, 1.0 / fps, gait)
                    check(blend.x == .6f && blend.y == .8f, "forward restart must discard the preceding field direction")
                }
                blend.update(-.6f, .8f, 1.0 / fps, 0)
                check(blend.x == -.6f && blend.y == .8f, "another pose owner must receive the raw field")
                blend.update(.6f, .8f, 1.0 / fps, gait)
                check(blend.x == .6f && blend.y == .8f, "a completed pose owner must not leave a filtered direction behind")
                blend.update(Float.NaN, .8f, 1.0 / fps, gait)
                blend.update(-.6f, .8f, 1.0 / fps, gait)
                check(blend.x == -.6f && blend.y == .8f, "invalid input must not poison the next native Walk field")
                for (incoming in intArrayOf(CartLocomotionBlend.WALK, CartLocomotionBlend.RUN, CartLocomotionBlend.SPRINT)) {
                    blend.update(-.6f, .8f, 1.0 / fps, gait)
                    blend.update(.6f, .8f, 1.0 / fps, incoming)
                    if (incoming != gait)
                        check(blend.x == .6f && blend.y == .8f, "a different native gait must begin from its own raw field")
                }
            }
        }
    }
}
