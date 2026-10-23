package net.alexredby.pztoolkitjavapatches

import org.joml.Matrix4f
import org.joml.Vector3f
import org.joml.Vector3fc
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.HelperFunctions
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData
import zombie.inventory.InventoryItem
import zombie.scripting.ScriptManager
import zombie.scripting.objects.ModelScript

/** Keep held carts rigid and on the floor without changing shared attachments. */
internal object CartGrounding {
    // Contacts are calibrated to these eight meshes; recalibrate after their geometry changes.
    private val SHOP_CONTACT: Vector3fc = Vector3f(110.0467f, 8.371053f, .98356926f)
    private val WOOD_CONTACT: Vector3fc = Vector3f(-2.1228965e-4f, -.004435286f, -4.0280633e-5f)
    private val METAL_CONTACT: Vector3fc = Vector3f(-23.5423f, -23.2973f, -2.97487f)

    @JvmStatic
    fun contact(model: String?): Vector3fc? =
        when (model) {
            "ShoppingCartModel",
            "ShoppingCartPartialModel",
            "ShoppingCartFullModel",
            "ShoppingCartFlashlightModel",
            "ShoppingCartFlashlightPartialModel",
            "ShoppingCartFlashlightFullModel" -> SHOP_CONTACT
            "WheelbarrowWood" -> WOOD_CONTACT
            "WheelbarrowMetal" -> METAL_CONTACT
            else -> null
        }

    private fun cartModel(type: String, model: String?): Boolean =
        when (type) {
            "SaucedCarts.ShoppingCart" -> contact(model) === SHOP_CONTACT
            "SaucedWheelbarrow.WheelbarrowWood" -> "WheelbarrowWood" == model
            "SaucedWheelbarrow.WheelbarrowMetal" -> "WheelbarrowMetal" == model
            else -> false
        }

    private fun cartModel(type: String, model: ModelScript?): Boolean =
        model != null &&
            model.getModule() != null &&
            "Base" == model.getModule().name &&
            cartModel(type, model.getName())

    @JvmStatic
    fun resolvedModel(item: InventoryItem): ModelScript? {
        val reference = item.getStaticModel() ?: return null
        val model = ScriptManager.instance.getModelScript(reference)
        return if (cartModel(item.getFullType(), model)) model else null
    }

    @JvmStatic
    fun sameModel(item: InventoryItem, reference: String?): Boolean {
        val expected = resolvedModel(item)
        return expected != null &&
            reference != null &&
            expected === ScriptManager.instance.getModelScript(reference)
    }

    /** ModData can update the remote item's fill model after native equipped models were cached. */
    @JvmStatic
    fun refreshRemoteModel(player: IsoPlayer) {
        if (
            player.isLocalPlayer() ||
                !CartSteeringHooks.supportedCart(player) ||
                player.getVariableBoolean("IsPerformingAnAction") ||
                !player.getCharacterActions().isEmpty() ||
                player.forceNullOverride ||
                player.isHideWeaponModel() ||
                player.isHideEquippedHandR() ||
                player.overridePrimaryHandModel != null &&
                    !player.overridePrimaryHandModel.isEmpty() ||
                player.overrideSecondaryHandModel != null &&
                    !player.overrideSecondaryHandModel.isEmpty()
        )
            return
        val instance = player.primaryHandModel ?: return
        if (instance.modelScript == null) return
        val item = player.getPrimaryHandItem()
        val expected = resolvedModel(item)
        if (
            expected != null &&
                expected !== instance.modelScript &&
                cartModel(item.getFullType(), instance.modelScript)
        )
            player.resetEquippedHandsModels()
    }

    private class Matrices {
        val transform = Matrix4f()
        val attachment = Matrix4f()
        val delta = Matrix4f()
        val spine = Vector3f()
        val reference = org.lwjgl.util.vector.Matrix4f()
        val bone = HelperFunctions.TransformResult_QPS()
        val rotation = org.lwjgl.util.vector.Quaternion()
    }

    private val matrices = ThreadLocal.withInitial(::Matrices)

    @JvmStatic
    fun lowerHandles(transform: Matrix4f, model: String?) {
        if ("WheelbarrowWood" != model && "WheelbarrowMetal" != model) return
        val point = contact(model)!!
        val x =
            transform.m00() * point.x() +
                transform.m10() * point.y() +
                transform.m20() * point.z() +
                transform.m30()
        val y =
            transform.m01() * point.x() +
                transform.m11() * point.y() +
                transform.m21() * point.z() +
                transform.m31()
        val z =
            transform.m02() * point.x() +
                transform.m12() * point.y() +
                transform.m22() * point.z() +
                transform.m32()
        // Lower the handles around the tire; do not pitch the actor's torso with the cart.
        val profile = CartWheelbarrow.forModel(model)!!
        matrices
            .get()
            .attachment
            .translation(x, y, z)
            .rotateX(Math.toRadians(profile.handleLoweringDegrees().toDouble()).toFloat())
            .translate(-x, -y, -z)
            .mul(transform, transform)
        // Keep the native hips fixed while positioning each profile within the two arm links'
        // reach.
        transform.m32(transform.m32() + profile.neutralAdvance())
    }

    @JvmStatic
    fun referencePose(
        clip: AnimationClip?,
        skeleton: SkinningData?,
        boneName: String?,
        out: Matrix4f?,
    ): Boolean {
        if (clip == null || skeleton == null || boneName == null) return false
        val index = skeleton.boneIndices[boneName] ?: return false
        val state = matrices.get()
        val rotation = state.rotation
        state.reference.setIdentity()
        var bone = skeleton.getBoneAt(index)
        while (bone != null) {
            val frames = clip.getBoneFramesAt(bone.index)
            if (frames == null || frames.isEmpty()) return false
            val frame = frames[0]
            // Native blended bones discard FBX scale (Dummy01 is exported at 0.01).
            rotation.set(frame.rotation)
            HelperFunctions.CreateFromQuaternion(rotation, state.bone.result)
            HelperFunctions.setPosition(state.bone.result, frame.position)
            org.lwjgl.util.vector.Matrix4f.mul(state.reference, state.bone.result, state.reference)
            bone = bone.parent
        }
        PZMath.convertMatrix(state.reference, out).transpose()
        return out!!.isFinite
    }

    @JvmStatic
    fun rigid(data: ModelInstanceRenderData, clip: AnimationClip?, out: Matrix4f): Boolean {
        val instance = data.modelInstance
        if (data.parent == null || instance.parent == null || instance.parent.animPlayer == null)
            return false
        val parent = instance.parent
        var attachment = parent.getAttachmentById(instance.attachmentNameParent)
        if (attachment == null) attachment = parent.getAttachmentById(instance.parentBoneName)
        val bone = if (attachment == null) instance.parentBoneName else attachment.getBone()
        // Use the authored cart idle pose, never an arbitrary moving arm frame.
        if (!referencePose(clip, parent.animPlayer.getSkinningData(), bone, out)) return false
        val scratch = matrices.get().attachment
        out.mul(scratch.set(data.parent.xfrm).transpose())
        if (attachment != null)
            out.mul(ModelInstanceRenderData.makeAttachmentTransform(attachment, scratch))
        attachment = instance.getAttachmentById(instance.attachmentNameSelf)
        if (attachment == null) attachment = instance.getAttachmentById(instance.parentBoneName)
        if (attachment != null) {
            ModelInstanceRenderData.makeAttachmentTransform(attachment, scratch)
            if (ModelInstanceRenderData.invertAttachmentSelfTransform) scratch.invert()
            out.mul(scratch)
        }
        ModelInstanceRenderData.postMultiplyMeshTransform(out, instance.model.mesh)
        out.scale(instance.scale)
        return out.isFinite
    }

    @JvmStatic
    fun ground(transform: Matrix4f, low: Vector3fc, high: Vector3fc): Boolean {
        var lowest = Float.POSITIVE_INFINITY
        for (i in 0 until 8) {
            val x = if (i and 1 == 0) low.x() else high.x()
            val y = if (i and 2 == 0) low.y() else high.y()
            val z = if (i and 4 == 0) low.z() else high.z()
            lowest =
                Math.min(
                    lowest,
                    transform.m01() * x +
                        transform.m11() * y +
                        transform.m21() * z +
                        transform.m31(),
                )
        }
        return ground(transform, lowest)
    }

    @JvmStatic
    fun ground(transform: Matrix4f, low: Vector3fc, high: Vector3fc, contact: Vector3fc?): Boolean =
        if (!validContact(low, high, contact)) ground(transform, low, high)
        else
            ground(
                transform,
                transform.m01() * contact!!.x() +
                    transform.m11() * contact.y() +
                    transform.m21() * contact.z() +
                    transform.m31(),
            )

    private fun validContact(low: Vector3fc, high: Vector3fc, contact: Vector3fc?): Boolean =
        contact != null &&
            java.lang.Float.isFinite(contact.x()) &&
            java.lang.Float.isFinite(contact.y()) &&
            java.lang.Float.isFinite(contact.z()) &&
            contact.x() >= low.x() &&
            contact.x() <= high.x() &&
            contact.y() >= low.y() &&
            contact.y() <= high.y() &&
            contact.z() >= low.z() &&
            contact.z() <= high.z()

    private fun ground(transform: Matrix4f, lowest: Float): Boolean {
        if (!java.lang.Float.isFinite(lowest) || Math.abs(lowest) >= 1) return false
        transform.m31(transform.m31() - lowest + .008f)
        return true
    }

    @JvmStatic
    fun align(
        transform: Matrix4f,
        low: Vector3fc,
        high: Vector3fc,
        lean: Float,
        delta: Matrix4f,
    ): Boolean = align(transform, low, high, null, lean, delta)

    @JvmStatic
    fun align(
        transform: Matrix4f,
        low: Vector3fc,
        high: Vector3fc,
        contact: Vector3fc?,
        lean: Float,
        delta: Matrix4f,
    ): Boolean {
        if (!java.lang.Float.isFinite(lean)) return false
        val height = transform.m31()
        if (!ground(transform, low, high, contact)) return false
        delta.translation(0f, transform.m31() - height, 0f)
        if (lean != 0f) {
            val centerX =
                if (validContact(low, high, contact))
                    transform.m00() * contact!!.x() +
                        transform.m10() * contact.y() +
                        transform.m20() * contact.z() +
                        transform.m30()
                else
                    transform.m00() * (low.x() + high.x()) * .5f +
                        transform.m10() * (low.y() + high.y()) * .5f +
                        transform.m20() * (low.z() + high.z()) * .5f +
                        transform.m30()
            val roll = matrices.get().attachment
            // Bank around the measured contact, not a box center that moves the tire sideways.
            roll.translation(centerX, .008f, 0f).rotateZ(lean).translate(-centerX, -.008f, 0f)
            roll.mul(transform, transform)
            roll.mul(delta, delta)
        }
        return true
    }

    @JvmStatic
    fun woodenLowest(transform: Matrix4f): Float =
        wheelbarrowLowest(transform, CartWheelbarrow.WOOD)

    @JvmStatic
    fun wheelbarrowLowest(transform: Matrix4f, profile: CartWheelbarrow): Float {
        val centerY =
            transform.m01() * profile.centerX() +
                transform.m11() * profile.centerY() +
                transform.m21() * profile.centerZ() +
                transform.m31()
        return centerY -
            profile.radius() *
                Math.hypot(transform.m11().toDouble(), transform.m21().toDouble()).toFloat() -
            profile.halfWidth() * Math.abs(transform.m01())
    }

    @JvmStatic
    fun alignWood(transform: Matrix4f, lean: Float, gaitShift: Float, delta: Matrix4f): Boolean =
        alignWood(transform, lean, Math.abs(lean), gaitShift, delta)

    @JvmStatic
    fun alignWood(
        transform: Matrix4f,
        lean: Float,
        pressure: Float,
        gaitShift: Float,
        delta: Matrix4f,
    ): Boolean = alignWheelbarrow(transform, CartWheelbarrow.WOOD, lean, pressure, gaitShift, delta)

    @JvmStatic
    fun alignWheelbarrow(
        transform: Matrix4f,
        profile: CartWheelbarrow,
        lean: Float,
        pressure: Float,
        gaitShift: Float,
        delta: Matrix4f,
    ): Boolean {
        if (
            !java.lang.Float.isFinite(lean) ||
                !java.lang.Float.isFinite(pressure) ||
                pressure < Math.abs(lean) ||
                !java.lang.Float.isFinite(gaitShift) ||
                gaitShift < -.24f ||
                gaitShift > 0
        )
            return false
        // The running torso moves forward; follow its native blend without lifting the handles.
        transform.m32(transform.m32() + profile.motionShift(pressure, gaitShift))
        var height = transform.m31()
        if (!ground(transform, wheelbarrowLowest(transform, profile))) return false
        delta.translation(0f, transform.m31() - height, 0f)
        val centerX =
            transform.m00() * profile.centerX() +
                transform.m10() * profile.centerY() +
                transform.m20() * profile.centerZ() +
                transform.m30()
        val roll = matrices.get().attachment
        roll.translation(centerX, .008f, 0f).rotateZ(lean).translate(-centerX, -.008f, 0f)
        roll.mul(transform, transform)
        roll.mul(delta, delta)
        // The rotating tire is a cylinder, not one fixed polygon vertex; its rim must clear the
        // floor at every phase.
        height = transform.m31()
        if (!ground(transform, wheelbarrowLowest(transform, profile))) return false
        delta.m31(delta.m31() + transform.m31() - height)
        return true
    }

    /** Blender-authored envelope parameterized by native outgoing Loot weight. */
    @JvmStatic
    fun inventoryEntryAdvance(outgoingWeight: Float): Float =
        CartEquipClearanceCurve.sample(1 - outgoingWeight)

    private fun inventoryEntryAdvance(
        player: IsoPlayer,
        data: ModelInstanceRenderData,
        model: String?,
    ): Float {
        if (
            "WheelbarrowWood" != model ||
                player.getVariableBoolean("IsPerformingAnAction") ||
                data.modelInstance.parent == null ||
                data.modelInstance.parent.animPlayer == null
        )
            return 0f
        val animation = data.modelInstance.parent.animPlayer
        if (animation.getMultiTrack() == null) return 0f
        var weight = 0f
        for (track in animation.getMultiTrack().getTracks()) {
            if ("Bob_IdleLooting_Mid" == track.getName() && track.getLayerIdx() == 1) {
                val blend = track.getBlendWeight()
                if (java.lang.Float.isFinite(blend)) weight = Math.max(weight, blend)
            }
        }
        return inventoryEntryAdvance(weight)
    }

    /**
     * Native equip can expose its hand model before the next Lua motion refresh or network pose.
     */
    @JvmStatic
    fun heldPresentationReady(player: IsoPlayer): Boolean {
        val item = player.getPrimaryHandItem()
        if (
            !CartTransition.wooden(item) ||
                item !is zombie.inventory.types.InventoryContainer ||
                player.getSecondaryHandItem() !== item ||
                item.getWorldItem() != null ||
                "cart" != player.getVariableString("Weapon") ||
                resolvedModel(item) == null ||
                player.isNpc() ||
                player.isDead() ||
                player.isAiming() ||
                player.isSneaking() ||
                player.hasHitReaction() ||
                player.isKnockedDown() ||
                player.isGettingUp() ||
                player.isGrappling() ||
                player.isBeingGrappled() ||
                player.isRagdollSimulationActive() ||
                player.getVehicle() != null ||
                player.isCurrentState(zombie.ai.states.CollideWithWallState.instance()) ||
                Math.abs(player.getVariableFloat("WalkInjury", 0f)) >= .15f ||
                player.getVariableBoolean("ToolkitWoodCartAction") ||
                player.forceNullOverride ||
                player.isHideWeaponModel() ||
                player.isHideEquippedHandR() ||
                player.overridePrimaryHandModel != null &&
                    !player.overridePrimaryHandModel.isEmpty() ||
                player.overrideSecondaryHandModel != null &&
                    !player.overrideSecondaryHandModel.isEmpty()
        )
            return false
        // Remote equipment packets own the exact hand snapshot; they need not populate that
        // avatar's inventory.
        if (player.isLocalPlayer()) {
            if (player.getInventory() == null || item.getContainer() !== player.getInventory())
                return false
        } else if (!CartMotionSync.connected()) return false
        val actions = player.getCharacterActions()
        if (actions.isEmpty()) return !player.getVariableBoolean("IsPerformingAnAction")
        if (actions.size != 1) return false
        val action = actions[0]
        if (
            action !is zombie.characters.CharacterTimedActions.LuaTimedActionNew ||
                action.chr !== player ||
                !action.isStarted() ||
                !action.finished() ||
                action.forceStop ||
                "ISCartEquipAction" != action.getMetaType()
        )
            return false
        val table = action.getTable()
        // The client's Lua complete callback is server-only, so its table.completed is not a
        // receipt.
        if (table == null || table.rawget("character") !== player) return false
        val id = table.rawget("cartId")
        return id is Number && id.toDouble() == item.getID().toDouble()
    }

    @JvmStatic
    fun render(slot: ModelSlotRenderData) {
        if (Main.CART_TRANSITION_SUPPORTED) CartImpactPose.render(slot)
        CartWheelSpin.prepare(slot, Double.NaN)
        CartShoppingWheels.clear(slot)
        if (CartTransition.render(slot)) return
        val player = slot.character as? IsoPlayer ?: return
        val handoff = CartTransition.pickupHandoff(player)
        if (!handoff && !CartMotionSync.visualEnabled(player) && !heldPresentationReady(player))
            return
        val expected = resolvedModel(player.getPrimaryHandItem()) ?: return
        val name = expected.getName()
        val profile = CartWheelbarrow.forModel(name)
        val clip = ModelManager.instance.getAnimationClip("Bob_Cart_Idle")
        for (data in slot.modelData) {
            val instance = data.modelInstance
            if (
                instance.parent == null ||
                    instance.modelScript !== expected ||
                    instance.model == null ||
                    instance.model.mesh == null
            )
                continue
            val state = matrices.get()
            val transform = state.transform
            val rigid = rigid(data, clip, transform)
            if (rigid) {
                lowerHandles(transform, name)
                transform.m32(transform.m32() - inventoryEntryAdvance(player, data, name))
            }
            val lean =
                if (handoff) 0f
                else
                    (if (player.isLocalPlayer()) CartSteeringHooks.lean(player)
                        else CartMotionSync.lean(player))
                        .toFloat()
            val pressure =
                if (handoff) 0f
                else
                    (if (player.isLocalPlayer()) CartSteeringHooks.clearanceLean(player)
                        else CartMotionSync.pressure(player))
                        .toFloat()
            if (
                rigid &&
                    when {
                        CartShopping.model(name) ->
                            CartShopping.align(
                                transform,
                                CartTransition.model(player.getPrimaryHandItem()),
                                player.getPrimaryHandItem().worldScale,
                                state.delta,
                            )
                        profile != null ->
                            alignWheelbarrow(
                                transform,
                                profile,
                                lean,
                                pressure,
                                if (handoff) 0f
                                else
                                    CartLegPace.woodenGaitShift(
                                        player,
                                        if (
                                            CartGrip.nativeSpine(slot, instance.parent, state.spine)
                                        )
                                            state.spine
                                        else null,
                                    ),
                                state.delta,
                            )
                        else ->
                            align(
                                transform,
                                instance.model.mesh.minXyz,
                                instance.model.mesh.maxXyz,
                                contact(instance.modelScript.getName()),
                                lean,
                                state.delta,
                            )
                    }
            ) {
                // A failed arm solve must not replace the grounded cart with the moving hand
                // attachment.
                CartGrip.render(slot, instance.parent, clip, state.delta, name, transform)
                data.xfrm.set(transform).transpose()
                if (profile != null) CartEmergencyDrop.capture(player, slot, transform)
                if (CartShopping.model(name))
                    CartShoppingWheels.prepare(slot, player.getPrimaryHandItem(), data, transform)
                else
                    CartWheelSpin.prepare(
                        slot,
                        if (player.isLocalPlayer())
                            CartSteeringHooks.wheelPhase(player, slot, transform)
                        else
                            CartWheelSpin.follow(
                                player.getPrimaryHandItem(),
                                slot.x,
                                slot.y,
                                slot.animPlayerAngle,
                                transform,
                            ),
                    )
            } else {
                transform.set(data.xfrm).transpose()
                if (ground(transform, instance.model.mesh.minXyz, instance.model.mesh.maxXyz))
                    data.xfrm.set(transform).transpose()
            }
        }
    }
}
