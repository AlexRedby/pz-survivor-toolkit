package net.alexredby.pztoolkitjavapatches;

import zombie.characters.IsoPlayer;
import zombie.characters.IsoGameCharacter;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlend;
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker.PickResults;
import zombie.core.skinnedmodel.advancedanimation.AnimLayer;
import zombie.core.skinnedmodel.advancedanimation.AnimNode;
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode;
import se.krka.kahlua.integration.annotations.LuaMethod;

/** Adds the native injury dimension to the cart's directional blend, per actor. */
public final class CartInjury {
    private static final PickResults picks = new PickResults();

    record Blend(float amount, String forward, Anim2DBlend first, Anim2DBlend second,
                 Anim2DBlend third, float a, float b, float c) {
        float weight(String name) {
            return (first != null && name.equals(first.animName) ? a : 0)
                + (second != null && name.equals(second.animName) ? b : 0)
                + (third != null && name.equals(third.animName) ? c : 0);
        }
    }

    @LuaMethod(name="toolkitCartInjurySupported", global=true)
    public static boolean supported(IsoPlayer player) {
        if (!Main.CART_INJURY_SUPPORTED || player == null) return false;
        return amount(player.getVariableFloat("WalkInjury", 0)) == 0
            || blend(player, CartLegPace.pivotNode(player)) != null;
    }

    static float amount(float injury) {
        return Float.isFinite(injury) ? Math.min(1, Math.abs(injury) / .15f) : 0;
    }

    static String forward(String name) {
        return switch (name) {
            case "ToolkitCartPivotWalk", "ToolkitWoodCartPivotWalk" -> "Bob_Walk";
            case "ToolkitCartPivotRun" -> "Bob_Run";
            case "ToolkitCartPivotSprint" -> "Bob_Sprint";
            default -> null;
        };
    }

    static Blend blend(IsoPlayer player, AnimNode cart) {
        if (player == null || cart == null || !Main.CART_INJURY_SUPPORTED) return null;
        float injury = player.getVariableFloat("WalkInjury", 0), amount = amount(injury);
        if (amount == 0) return null;
        String forward = forward(cart.name);
        if (forward == null) return null;
        String stateName = forward.equals("Bob_Walk") ? "movement" : forward.equals("Bob_Run") ? "run" : "sprint";
        var animator = player.getAdvancedAnimator();
        if (animator == null || animator.animSet == null) return null;
        var state = animator.animSet.states.get(stateName);
        if (state == null) return null;
        String nativeName = stateName.equals("movement") ? "defaultWalk" : stateName.equals("run") ? "defaultRun" : "defaultSprint";
        AnimNode nativeNode = null;
        for (var node : state.nodes) if (nativeName.equals(node.name)) { nativeNode = node; break; }
        if (nativeNode == null || nativeNode.blend2dPicker == null || nativeNode.blendTris == null
            || nativeNode.blendTris.isEmpty()) return null;
        float speed = player.getVariableFloat("WalkSpeed", 0);
        if (!Float.isFinite(speed)) return null;
        nativeNode.blend2dPicker.Pick(injury, speed, picks);
        if (picks.numNodes < 1 || picks.numNodes > 3) return null;
        float a = weight(picks.scale1), b = picks.numNodes > 1 ? weight(picks.scale2) : 0,
            c = picks.numNodes > 2 ? weight(picks.scale3) : 0;
        if (!Float.isFinite(a + b + c) || a + b + c < 1e-6f) return null;
        var first = picks.node1;
        var second = picks.numNodes > 1 ? picks.node2 : null;
        var third = picks.numNodes > 2 ? picks.node3 : null;
        if (!contains(cart, first, a) || !contains(cart, second, b) || !contains(cart, third, c)) return null;
        return new Blend(amount, forward, first, second, third, a, b, c);
    }

    private static float weight(float value) {
        return !Float.isFinite(value) ? Float.NaN : value < 1e-4f ? 0 : Math.min(1, value);
    }

    private static boolean contains(AnimNode cart, Anim2DBlend nativeBlend, float weight) {
        if (weight == 0) return true;
        if (nativeBlend == null) return false;
        for (var blend : cart.blends2d) if (nativeBlend.animName.equals(blend.animName))
            return CartLegPace.validClip(cart, nativeBlend.animName);
        return false;
    }

    /** Follow effective rendered weights, including outgoing injured nodes during healing. */
    static float poseWeight(IsoGameCharacter character) {
        if (character == null || !Main.CART_INJURY_SUPPORTED) return 0;
        var animator = character.getAdvancedAnimator();
        if (animator == null || animator.getRootLayer() == null) return 0;
        float total = 0;
        for (var node : animator.getRootLayer().getLiveAnimNodes()) {
            if (forward(node.getName()) == null) continue;
            for (var track : node.getMainAnimationTracks()) {
                if (!switch (track.getName()) {
                    case "Bob_WalkLightLimpL", "Bob_WalkLightLimpR", "Bob_WalkHeavyLimpL", "Bob_WalkHeavyLimpR",
                         "Bob_RunLightLimpL", "Bob_RunLightLimpR" -> true;
                    default -> false;
                }) continue;
                float weight = track.getBlendWeight();
                if (Float.isFinite(weight) && weight > 0) total += weight;
            }
        }
        // Native injured Sprint can contain only ordinary Run/Sprint clips.
        return Math.max(amount(character.getVariableFloat("WalkInjury", 0)), Math.min(1, total));
    }

    static float walkMagnitude(IsoPlayer player, float speed) {
        var blend = blend(player, CartLegPace.pivotNode(player));
        return blend == null ? speed : speed + blend.amount * (1 - speed);
    }

    /** Native refreshes active field weights first; outgoing fields retain their exact blend. */
    public static void apply(AnimLayer layer, LiveAnimNode node) {
        if (!(layer.getVariableSource() instanceof IsoPlayer player)
            || !player.getVariableBoolean("ToolkitCartMotion") || !node.isActive()) return;
        var blend = blend(player, node.getSourceNode());
        if (blend == null) return;
        float forward = 0;
        for (var track : node.getMainAnimationTracks())
            if (blend.forward.equals(track.getName())) forward += track.getBlendFieldWeight();
        if (!Float.isFinite(forward) || forward <= 0) return;
        // Missing/differently loaded tracks must not consume the forward mass.
        for (var name : new String[]{blend.first == null ? null : blend.first.animName,
                blend.second == null ? null : blend.second.animName, blend.third == null ? null : blend.third.animName}) {
            if (name == null || blend.weight(name) == 0) continue;
            boolean found = false;
            for (var track : node.getMainAnimationTracks()) if (name.equals(track.getName()) && track.getClip() != null) { found = true; break; }
            if (!found) return;
        }
        for (var track : node.getMainAnimationTracks()) {
            float change = forward * blend.amount * (blend.weight(track.getName())
                - (blend.forward.equals(track.getName()) ? 1 : 0));
            if (change != 0) track.setBlendFieldWeight(Math.max(0, track.getBlendFieldWeight() + change));
        }
    }

    private CartInjury() {}
}
