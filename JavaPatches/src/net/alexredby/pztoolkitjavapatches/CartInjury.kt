package net.alexredby.pztoolkitjavapatches

import me.zed_0xff.zombie_buddy.Patch
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlend
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker.PickResults
import zombie.core.skinnedmodel.advancedanimation.AnimLayer
import zombie.core.skinnedmodel.advancedanimation.AnimNode
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode

/** Adds the native injury dimension to the cart's directional blend, per actor. */
@Patch(
    className = "zombie.core.skinnedmodel.advancedanimation.AnimLayer",
    methodName = "applyBlendField",
    warmUp = true,
    strictMatch = true,
)
object CartInjury {
    private val picks = PickResults()

    @JvmRecord
    data class Blend(
        val amount: Float,
        val forward: String,
        val first: Anim2DBlend?,
        val second: Anim2DBlend?,
        val third: Anim2DBlend?,
        val a: Float,
        val b: Float,
        val c: Float,
    ) {
        fun weight(name: String?): Float =
            (if (first != null && name == first.animName) a else 0f) +
                (if (second != null && name == second.animName) b else 0f) +
                (if (third != null && name == third.animName) c else 0f)
    }

    @JvmStatic
    @LuaMethod(name = "toolkitCartInjurySupported", global = true)
    fun supported(player: IsoPlayer?): Boolean {
        if (!Main.CART_INJURY_SUPPORTED || player == null) return false
        return amount(player.getVariableFloat("WalkInjury", 0f)) == 0f ||
            blend(player, CartLegPace.pivotNode(player)) != null
    }

    @JvmStatic
    fun amount(injury: Float): Float =
        if (injury.isFinite()) Math.min(1f, Math.abs(injury) / .15f) else 0f

    private fun forward(name: String?): String? =
        when (name) {
            "ToolkitCartPivotWalk",
            "ToolkitWoodCartPivotWalk" -> "Toolkit_CartPivot_Walk"
            "ToolkitCartPivotRun" -> "Toolkit_CartPivot_Run"
            "ToolkitCartPivotSprint" -> "Toolkit_CartPivot_Sprint"
            else -> null
        }

    @JvmStatic
    fun nativeNode(player: IsoPlayer?, cart: AnimNode?): AnimNode? {
        if (player == null || cart == null) return null
        val forward = forward(cart.name) ?: return null
        val stateName =
            if (forward == "Toolkit_CartPivot_Walk") "movement"
            else if (forward == "Toolkit_CartPivot_Run") "run" else "sprint"
        val animator = player.getAdvancedAnimator()
        if (animator == null || animator.animSet == null) return null
        val state = animator.animSet.states[stateName] ?: return null
        val nativeName =
            if (stateName == "movement") "defaultWalk"
            else if (stateName == "run") "defaultRun" else "defaultSprint"
        return state.nodes.firstOrNull { nativeName == it.name }
    }

    @JvmStatic
    fun blend(player: IsoPlayer?, cart: AnimNode?): Blend? {
        if (player == null || cart == null || !Main.CART_INJURY_SUPPORTED) return null
        val injury = player.getVariableFloat("WalkInjury", 0f)
        val amount = amount(injury)
        if (amount == 0f) return null
        val forward = forward(cart.name) ?: return null
        val nativeNode = nativeNode(player, cart) ?: return null
        if (
            nativeNode.blend2dPicker == null ||
                nativeNode.blendTris == null ||
                nativeNode.blendTris.isEmpty()
        )
            return null
        val speed = player.getVariableFloat("WalkSpeed", 0f)
        if (!speed.isFinite()) return null
        nativeNode.blend2dPicker.Pick(injury, speed, picks)
        if (picks.numNodes < 1 || picks.numNodes > 3) return null
        val a = weight(picks.scale1)
        val b = if (picks.numNodes > 1) weight(picks.scale2) else 0f
        val c = if (picks.numNodes > 2) weight(picks.scale3) else 0f
        if (!(a + b + c).isFinite() || a + b + c < 1e-6f) return null
        val first = picks.node1
        val second = if (picks.numNodes > 1) picks.node2 else null
        val third = if (picks.numNodes > 2) picks.node3 else null
        if (!contains(cart, first, a) || !contains(cart, second, b) || !contains(cart, third, c))
            return null
        return Blend(amount, forward, first, second, third, a, b, c)
    }

    private fun weight(value: Float): Float =
        if (!value.isFinite()) Float.NaN else if (value < 1e-4f) 0f else Math.min(1f, value)

    private fun contains(cart: AnimNode, nativeBlend: Anim2DBlend?, weight: Float): Boolean {
        if (weight == 0f) return true
        if (nativeBlend == null) return false
        for (blend in cart.blends2d) if (nativeBlend.animName == blend.animName)
            return CartLegPace.validClip(cart, nativeBlend.animName)
        return false
    }

    /** Follow effective rendered weights, including outgoing injured nodes during healing. */
    @JvmStatic
    fun poseWeight(character: IsoGameCharacter?): Float {
        if (character == null || !Main.CART_INJURY_SUPPORTED) return 0f
        val animator = character.getAdvancedAnimator()
        if (animator == null || animator.getRootLayer() == null) return 0f
        var total = 0f
        for (node in animator.getRootLayer().getLiveAnimNodes()) {
            if (forward(node.getName()) == null) continue
            for (track in node.getMainAnimationTracks()) {
                when (track.getName()) {
                    "Bob_WalkLightLimpL",
                    "Bob_WalkLightLimpR",
                    "Bob_WalkHeavyLimpL",
                    "Bob_WalkHeavyLimpR",
                    "Bob_RunLightLimpL",
                    "Bob_RunLightLimpR" -> Unit
                    else -> continue
                }
                val weight = track.getBlendWeight()
                if (weight.isFinite() && weight > 0) total += weight
            }
        }
        // Native injured Sprint can contain only ordinary Run/Sprint clips.
        return Math.max(amount(character.getVariableFloat("WalkInjury", 0f)), Math.min(1f, total))
    }

    @JvmStatic
    fun walkMagnitude(player: IsoPlayer?, speed: Float): Float {
        val blend = blend(player, CartLegPace.pivotNode(player))
        return if (blend == null) speed else speed + blend.amount * (1 - speed)
    }

    /** Native refreshes active field weights first; outgoing fields retain their exact blend. */
    @JvmStatic
    @Patch.OnExit
    fun apply(@Patch.This layer: AnimLayer, @Patch.Argument(0) node: LiveAnimNode) {
        val player = layer.getVariableSource() as? IsoPlayer ?: return
        if (!player.getVariableBoolean("ToolkitCartMotion") || !node.isActive()) return
        val blend = blend(player, node.getSourceNode()) ?: return
        var forward = 0f
        for (track in node.getMainAnimationTracks()) if (blend.forward == track.getName())
            forward += track.getBlendFieldWeight()
        if (!forward.isFinite() || forward <= 0) return
        // Missing/differently loaded tracks must not consume the forward mass.
        for (name in
            arrayOf(blend.first?.animName, blend.second?.animName, blend.third?.animName)) {
            if (name == null || blend.weight(name) == 0f) continue
            var found = false
            for (track in node.getMainAnimationTracks()) if (
                name == track.getName() && track.getClip() != null
            ) {
                found = true
                break
            }
            if (!found) return
        }
        for (track in node.getMainAnimationTracks()) {
            val change =
                forward *
                    blend.amount *
                    (blend.weight(track.getName()) -
                        (if (blend.forward == track.getName()) 1f else 0f))
            if (change != 0f)
                track.setBlendFieldWeight(Math.max(0f, track.getBlendFieldWeight() + change))
        }
    }
}
