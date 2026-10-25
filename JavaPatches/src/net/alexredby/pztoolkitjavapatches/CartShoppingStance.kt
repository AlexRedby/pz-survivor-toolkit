package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.model.SkinningData

/** Give the native carrying body room behind the bar instead of bending its spine backward. */
internal object CartShoppingStance {
    private val bones =
        arrayOf(
            "Bip01_L_UpperArm",
            "Bip01_L_Forearm",
            "Bip01_L_Hand",
            "Bip01_R_UpperArm",
            "Bip01_R_Forearm",
            "Bip01_R_Hand",
        )

    private class NativePose {
        val poses = arrayOfNulls<Matrix4f>(60)
        val cart = Matrix4f()
        val delta = Matrix4f()
        val points = Array(3) { Vector3f() }
        val target = Matrix4f()
        val bar = Vector3f()
    }

    private val native = ThreadLocal.withInitial(::NativePose)
    // A cart rolls independently of the shoulder bob. Keep its bar in one actor-local place
    // while the elbows absorb walking motion; only leave it when arm geometry requires it.
    private val neutralBarZ = run {
        val held = CartShopping.held(Matrix4f()) ?: error("Missing shopping-cart geometry")
        held.transformPosition(Vector3f(-150.07166f, 343.47412f, 0f)).z - .06f
    }

    /** Shared by the render palette and game-thread AnimationPlayer snapshots. */
    @JvmStatic
    fun shift(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
    ): Float {
        if (
            poses == null ||
                actor == null ||
                delta == null ||
                !delta.isFinite ||
                cart == null ||
                !cart.isFinite
        )
            return Float.NaN
        val scratch = native.get()
        var lower = Float.NEGATIVE_INFINITY
        var upper = Float.POSITIVE_INFINITY
        val bar = scratch.bar.set(-150.07166f, 343.47412f, 0f)
        cart.transformPosition(bar)
        var desired = neutralBarZ - bar.z
        for (side in 0..1) {
            val points = scratch.points
            for (link in 0..2) {
                val bone = actor.getBone(bones[side * 3 + link]) ?: return Float.NaN
                val pose = poses.getOrNull(bone.index) ?: return Float.NaN
                if (!pose.isFinite) return Float.NaN
                pose.getTranslation(points[link])
            }
            val shoulder = points[0]
            val a = shoulder.distance(points[1])
            val b = points[1].distance(points[2])
            val target = scratch.target
            if (!CartGrip.target("ShoppingCartModel", side == 0, female, delta, cart, target))
                return Float.NaN
            // Reserve .005 model units of extension. A faster/native bent posture can also
            // need the bar farther forward to avoid folding the elbow beyond 116 degrees.
            // Reachability takes precedence when the two arms cannot satisfy both limits.
            val reach = a + b - .005f
            val x = target.m30() - shoulder.x
            val y = target.m31() - shoulder.y
            val square = reach * reach - x * x - y * y
            if (a <= 0 || b <= 0 || square < 0 || !square.isFinite()) return Float.NaN
            val radius = Math.sqrt(square.toDouble()).toFloat()
            val offset = shoulder.z - target.m32()
            lower = maxOf(lower, offset - radius)
            upper = minOf(upper, offset + radius)
            val folded = a * a + b * b + 2 * a * b * -.43837115f - x * x - y * y
            if (folded > 0) desired = minOf(desired, offset - kotlin.math.sqrt(folded))
        }
        return if (lower <= upper) desired.coerceIn(lower, upper) else Float.NaN
    }

    @JvmStatic
    fun apply(
        poses: Array<out Matrix4f?>?,
        actor: SkinningData?,
        female: Boolean,
        delta: Matrix4f?,
        cart: Matrix4f?,
        weight: Float,
    ): Boolean {
        if (!weight.isFinite() || weight !in 0f..1f) return false
        if (weight == 0f) return true
        val shift = shift(poses, actor, female, delta, cart)
        if (!shift.isFinite() || cart == null) return false
        cart.m32(cart.m32() + shift * weight)
        return true
    }

    /** Steering uses the same stance geometry as rendering, without a render-to-game cache. */
    @JvmStatic
    fun shift(player: IsoPlayer?): Float {
        if (player == null || !player.hasAnimationPlayer()) return 0f
        val animation = player.getAnimationPlayer() ?: return 0f
        if (!animation.hasSkinningData()) return 0f
        val actor = animation.getSkinningData()
        val state = native.get()
        if (actor.numBones() > state.poses.size) return 0f
        val turn = CartShoppingTurn.current(player)
        if (turn != null && capture(state, actor, animation, true)) {
            CartShoppingTurn.apply(state.poses, actor, turn)
        } else if (!capture(state, actor, animation, false)) return 0f
        val item = player.getPrimaryHandItem() ?: return 0f
        if (
            !CartShopping.item(item) ||
                CartShopping.held(state.cart, CartTransition.model(item), item.worldScale) == null
        )
            return 0f
        val shift = shift(state.poses, actor, player.isFemale(), state.delta.identity(), state.cart)
        return if (shift.isFinite()) shift else 0f
    }

    private fun capture(
        state: NativePose,
        actor: SkinningData,
        animation: AnimationPlayer,
        full: Boolean,
    ): Boolean {
        val count = if (full) actor.numBones() else bones.size
        for (i in 0 until count) {
            val bone = if (full) actor.getBoneAt(i) else actor.getBone(bones[i])
            if (bone == null || bone.index !in 0 until animation.getModelTransformsCount())
                return false
            val captured = animation.getModelTransformAt(bone.index) ?: return false
            val pose = state.poses[bone.index] ?: Matrix4f().also { state.poses[bone.index] = it }
            PZMath.convertMatrix(captured, pose).transpose()
        }
        return true
    }
}
