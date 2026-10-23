package net.alexredby.pztoolkitjavapatches

/** Continuous forward-gait picker direction, independent of accepted cart movement. */
internal class CartLocomotionBlend() {
    companion object {
        const val WALK = 1
        const val RUN = 2
        const val SPRINT = 3
        private const val RESPONSE_SECONDS = .05
    }

    private var angle = 0.0
    private var gait = 0
    @JvmField var x = 0f
    @JvmField var y = 0f

    fun update(targetX: Float, targetY: Float, seconds: Double, forwardGait: Int) {
        x = targetX
        y = targetY
        val radius = Math.hypot(targetX.toDouble(), targetY.toDouble())
        if (forwardGait < WALK || forwardGait > SPRINT || !radius.isFinite() ||
            radius < 1e-6 || !(targetY > 1e-6f)) {
            gait = 0
            return
        }
        // Interpolate the direction, not the Cartesian coordinates: opposite steering
        // must pass through a full forward stride rather than a shorter idle blend.
        val target = Math.atan2(targetX.toDouble(), targetY.toDouble())
        if (gait != forwardGait) { angle = target; gait = forwardGait; return }
        if (seconds.isFinite() && seconds > 0)
            angle += (target - angle) * -Math.expm1(-Math.min(.1, seconds) / RESPONSE_SECONDS)
        // Both angles are in the forward half-plane; there is no wrapped/sign-flip path.
        x = (radius * Math.sin(angle)).toFloat()
        y = (radius * Math.cos(angle)).toFloat()
    }
}
