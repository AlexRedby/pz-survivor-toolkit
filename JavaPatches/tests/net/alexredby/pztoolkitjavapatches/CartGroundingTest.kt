package net.alexredby.pztoolkitjavapatches

import java.util.HashMap
import java.util.Stack
import org.joml.Matrix4f
import org.joml.Vector3f
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.math.PZMath
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.animation.Keyframe
import zombie.core.skinnedmodel.model.Model
import zombie.core.skinnedmodel.model.ModelInstance
import zombie.core.skinnedmodel.model.ModelInstanceRenderData
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.core.skinnedmodel.model.ModelSlotRenderData
import zombie.core.skinnedmodel.model.SkinningData
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.InventoryContainer
import zombie.scripting.objects.ModelAttachment
import zombie.scripting.objects.ModelScript

object CartGroundingTest {
    private fun model(moduleName: String, name: String): ModelScript {
        val manager = zombie.scripting.ScriptManager.instance
        var module = manager.moduleMap[moduleName]
        if (module == null) {
            module = zombie.scripting.objects.ScriptModule()
            module.name = moduleName
            manager.moduleMap[moduleName] = module
            manager.moduleList.add(module)
            val field = manager.javaClass.getDeclaredField("models")
            field.isAccessible = true
            (field.get(manager) as zombie.scripting.ScriptBucketCollection<*>).registerModule(
                module,
            )
        }
        val existing = manager.getModelScript("$moduleName.$name")
        if (existing != null) return existing
        val model = ModelScript()
        model.name = name
        model.InitLoadPP(name)
        model.setModule(module)
        manager.addModelScript(model)
        return model
    }

    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        @JvmField var cart: InventoryItem? = null
        @JvmField var inventory: ItemContainer? = null
        @JvmField var remote = false
        @JvmField var action = false
        @JvmField var motionDisabled = false
        @JvmField var splitHands = false
        @JvmField var aiming = false
        @JvmField var sneaking = false
        @JvmField var dead = false
        @JvmField var weapon: String? = null
        @JvmField var injury = 0f
        @JvmField var resets = 0
        @JvmField var actions: Stack<zombie.characters.CharacterTimedActions.BaseAction?>? = Stack()
        @JvmField var machine: zombie.ai.StateMachine? = null

        override fun isLocalPlayer(): Boolean = !remote

        override fun resetEquippedHandsModels() {
            resets++
        }

        override fun getCharacterActions():
            Stack<zombie.characters.CharacterTimedActions.BaseAction?> {
            val current = actions
            if (current != null) return current
            return Stack<zombie.characters.CharacterTimedActions.BaseAction?>().also {
                actions = it
            }
        }

        override fun isNpc(): Boolean = false

        override fun isAiming(): Boolean = aiming

        override fun isSneaking(): Boolean = sneaking

        override fun getVariableFloat(name: String?, fallback: Float): Float =
            if ("WalkInjury".equals(name)) injury else fallback

        override fun getVariableString(name: String?): String? =
            if ("Weapon".equals(name)) weapon else null

        override fun clearVariable(name: String?) {}

        override fun getVariableBoolean(name: String?): Boolean =
            !motionDisabled && "ToolkitCartMotion".equals(name) ||
                action && "IsPerformingAnAction".equals(name)

        override fun isDead(): Boolean = dead

        override fun hasHitReaction(): Boolean = false

        override fun isKnockedDown(): Boolean = false

        override fun isGettingUp(): Boolean = false

        override fun isGrappling(): Boolean = false

        override fun isBeingGrappled(): Boolean = false

        override fun isRagdollSimulationActive(): Boolean = false

        override fun getStateMachine(): zombie.ai.StateMachine =
            machine ?: zombie.ai.StateMachine(this).also { machine = it }

        override fun hasPath(): Boolean = false

        override fun getPrimaryHandItem(): InventoryItem? = cart

        override fun getSecondaryHandItem(): InventoryItem? = if (splitHands) null else cart

        override fun getInventory(): ItemContainer? = inventory

        override fun getAdvancedAnimator():
            zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator? = null
    }

    private class Cart : InventoryItem(null, null, null, null as String?) {
        override fun getWorldStaticModel(): String? = getStaticModel()
    }

    private class World : zombie.iso.objects.IsoWorldInventoryObject(null as zombie.iso.IsoCell?) {
        override fun invalidateRenderChunkLevel(flags: Long) {}
    }

    private fun field(obj: Any, owner: Class<*>, name: String, value: Any?) {
        val f = owner.getDeclaredField(name)
        f.isAccessible = true
        f.set(obj, value)
    }

    private fun handoff(player: Player, item: InventoryItem, unsafe: Unsafe) {
        val type = Class.forName("net.alexredby.pztoolkitjavapatches.CartTransition\$State")
        val state = unsafe.allocateInstance(type)
        field(state, type, "item", item)
        field(state, type, "pickup", true)
        field(state, type, "rendered", true)
        field(state, type, "action", 123L)
        field(state, type, "lastRender", System.nanoTime())
        field(state, type, "updated", System.nanoTime())
        field(state, type, "world", unsafe.allocateInstance(World::class.java))
        val action =
            unsafe.allocateInstance(zombie.characters.CharacterTimedActions.BaseAction::class.java)
                as zombie.characters.CharacterTimedActions.BaseAction
        action.chr = player
        field(state, type, "actionOwner", action)
        val states = CartTransition::class.java.getDeclaredField("states")
        states.isAccessible = true
        @Suppress("UNCHECKED_CAST") val active = states.get(null) as MutableMap<IsoPlayer, Any>
        active[player] = state
        CartTransition.end(player)
        val pending = CartTransition::class.java.getDeclaredField("pickupHandoffs")
        pending.isAccessible = true
        @Suppress("UNCHECKED_CAST") val handoffs = pending.get(null) as Map<IsoPlayer, Any>
        val token = handoffs[player] ?: throw NullPointerException()
        field(token, token.javaClass, "performed", true)
        field(token, token.javaClass, "held", item)
    }

    private class Instance : ModelInstance() {
        @JvmField var attachment: ModelAttachment? = null

        override fun getAttachmentById(id: String?): ModelAttachment? {
            val current = attachment
            return if (current != null && current.getId().equals(id)) current else null
        }
    }

    private fun frame(
        bone: Int,
        time: Float,
        x: Float,
        y: Float,
        z: Float,
        angle: Float,
    ): Keyframe {
        val result =
            Keyframe(
                org.lwjgl.util.vector.Vector3f(x, y, z),
                org.lwjgl.util.vector.Quaternion(
                    0f,
                    Math.sin((angle / 2).toDouble()).toFloat(),
                    0f,
                    Math.cos((angle / 2).toDouble()).toFloat(),
                ),
                org.lwjgl.util.vector.Vector3f(1f, 1f, 1f),
            )
        result.bone = bone
        result.boneName = if (bone == 0) "root" else "prop"
        result.time = time
        return result
    }

    private fun nativeExportPose() {
        // Captured Bob_Cart_Idle locals and live Prop1 model pose from B42.21, not the scaled raw
        // track.
        val dummy = frame(0, 0f, 0f, 0f, 0f, 0f)
        dummy.boneName = "Dummy01"
        dummy.rotation.set(-.7071068f, 0f, 0f, .7071067f)
        dummy.scale.set(.01f, .010000001f, .010000001f)
        val root = frame(1, 0f, 0f, 1.4341615e-8f, -.0880282f, 0f)
        root.boneName = "Bip01"
        root.rotation.set(.7071069f, 0f, 0f, .70710665f)
        val prop = frame(2, 0f, -.071653344f, .67678964f, -.17752668f, 0f)
        prop.boneName = "Bip01_Prop1"
        prop.rotation.set(-.5689081f, -.41993275f, .568908f, .41993314f)
        prop.scale.set(.9999997f, .99999976f, .9999998f)
        val idle = AnimationClip(1f, listOf(dummy, root, prop), "Bob_Cart_Idle", true)
        val identity = org.lwjgl.util.vector.Matrix4f()
        val boneMatrices = listOf(identity, identity, identity)
        val skeleton =
            SkinningData(
                HashMap(),
                boneMatrices,
                boneMatrices,
                boneMatrices,
                listOf(-1, 0, 1),
                HashMap(mapOf("Dummy01" to 0, "Bip01" to 1, "Bip01_Prop1" to 2)),
            )
        val expected =
            Matrix4f()
                .set(
                    -1.4305115e-6f,
                    .95561385f,
                    -.29462528f,
                    0f,
                    -8.34465e-7f,
                    -.29462644f,
                    -.95561385f,
                    0f,
                    -1.0000011f,
                    -5.960458e-8f,
                    -2.3841856e-7f,
                    0f,
                    -.07165334f,
                    .5887615f,
                    -.17752649f,
                    1f,
                )
        val actual = Matrix4f()
        if (
            !CartGrounding.referencePose(idle, skeleton, "Bip01_Prop1", actual) ||
                !actual.equals(expected, .00001f)
        )
            throw AssertionError(
                "real idle export does not match native live unit-scale pose: $actual",
            )
    }

    private fun rigidPose() {
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe")
        unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        val idle =
            AnimationClip(
                1f,
                listOf(
                    frame(0, 0f, .2f, 0f, -.1f, .15f),
                    frame(1, 0f, .3f, .4f, .5f, -.4f),
                    frame(0, 1f, .8f, .2f, -.5f, .6f),
                    frame(1, 1f, -.1f, .6f, .4f, .5f),
                ),
                "Bob_Cart_Idle",
                true,
            )
        val identity = org.lwjgl.util.vector.Matrix4f()
        val skeleton =
            SkinningData(
                HashMap(),
                listOf(identity, identity),
                listOf(identity, identity),
                listOf(identity, identity),
                listOf(-1, 0),
                HashMap(mapOf("root" to 0, "prop" to 1)),
            )
        val player = unsafe.allocateInstance(AnimationPlayer::class.java) as AnimationPlayer
        val skinningField = AnimationPlayer::class.java.getDeclaredField("skinningData")
        skinningField.isAccessible = true
        skinningField.set(player, skeleton)
        val track = AnimationTrack.alloc()
        val reference = Matrix4f()
        try {
            track.startClip(idle, true, 0f)
            track.UpdateKeyframes(0f)
            val nativePose =
                PZMath.convertMatrix(
                        player.getUnweightedModelTransform(
                            track,
                            1,
                            org.lwjgl.util.vector.Matrix4f(),
                        ),
                        Matrix4f(),
                    )
                    .transpose()
            if (
                !CartGrounding.referencePose(idle, skeleton, "prop", reference) ||
                    !reference.equals(nativePose, .00001f)
            )
                throw AssertionError("reference disagrees with native authored idle pose")
            track.moveCurrentTimeValueTo(.5f)
            track.UpdateKeyframes(0f)
            if (
                !CartGrounding.referencePose(idle, skeleton, "prop", Matrix4f()) ||
                    reference.equals(
                        PZMath.convertMatrix(
                                player.getUnweightedModelTransform(
                                    track,
                                    1,
                                    org.lwjgl.util.vector.Matrix4f(),
                                ),
                                Matrix4f(),
                            )
                            .transpose(),
                        .00001f,
                    )
            )
                throw AssertionError("fixture must contain moving arms")
        } finally {
            track.release()
        }
        for (frame in idle.getKeyframes()) {
            frame.scale.set(if (frame.bone == 0) .01f else .8f, .01f, .02f)
            frame.rotation.scale(2f)
        }
        val authoredRotation = idle.getKeyframes()[0].rotation.w
        val exported = Matrix4f()
        if (
            !CartGrounding.referencePose(idle, skeleton, "prop", exported) ||
                !exported.equals(reference, .00001f)
        )
            throw AssertionError(
                "FBX export scale collapsed the cart instead of native unit bone scale",
            )
        if (idle.getKeyframes()[0].rotation.w != authoredRotation)
            throw AssertionError("shared clip quaternion changed")
        if (
            CartGrounding.referencePose(idle, skeleton, "missing", Matrix4f()) ||
                CartGrounding.referencePose(null, skeleton, "prop", Matrix4f())
        )
            throw AssertionError("missing reference accepted")
        val parent = Instance()
        parent.animPlayer = player
        parent.attachment = ModelAttachment("parent")
        parent.attachment!!.setBone("prop")
        parent.attachment!!.getOffset().set(.05f, 0f, .08f)
        val instance = Instance()
        instance.parent = parent
        instance.parentBoneName = "prop"
        instance.attachmentNameParent = "parent"
        instance.attachmentNameSelf = "self"
        instance.scale = .9f
        instance.attachment = ModelAttachment("self")
        instance.attachment!!.getOffset().set(.1f, .2f, -.3f)
        instance.attachment!!.getRotate().set(0f, 15f, 0f)
        instance.attachment!!.setScale(.85f)
        instance.model = unsafe.allocateInstance(Model::class.java) as Model
        val meshField = Model::class.java.getField("mesh")
        meshField.isAccessible = true
        meshField.set(instance.model, unsafe.allocateInstance(ModelMesh::class.java))
        val data = ModelInstanceRenderData()
        data.modelInstance = instance
        data.parent = AnimatedModel.AnimatedModelInstanceRenderData()
        val authoredParent =
            ModelInstanceRenderData.makeAttachmentTransform(parent.attachment, Matrix4f())
        val authoredSelf =
            ModelInstanceRenderData.makeAttachmentTransform(instance.attachment, Matrix4f())
        val self = Matrix4f(authoredSelf)
        if (ModelInstanceRenderData.invertAttachmentSelfTransform) self.invert()
        for (degree in 0 until 360 step 15) {
            val root = Matrix4f().rotateY(Math.toRadians(degree.toDouble()).toFloat())
            data.parent.xfrm.set(root).transpose()
            val expected =
                Matrix4f(reference).mul(root).mul(authoredParent).mul(self).scale(instance.scale)
            data.xfrm.translation(degree * .01f, -.1f, .2f).rotateXYZ(.1f, .2f, .3f)
            val actual = Matrix4f()
            if (!CartGrounding.rigid(data, idle, actual) || !actual.equals(expected, .00001f))
                throw AssertionError("moving arm pose changed rigid cart at $degree")
        }
        if (
            !authoredParent.equals(
                ModelInstanceRenderData.makeAttachmentTransform(parent.attachment, Matrix4f()),
            ) ||
                !authoredSelf.equals(
                    ModelInstanceRenderData.makeAttachmentTransform(
                        instance.attachment,
                        Matrix4f(),
                    ),
                )
        )
            throw AssertionError("shared attachment changed")
        // The rigid cart must survive an unavailable body palette instead of following the animated
        // arm/AABB fallback.
        val character = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        character.inventory = ItemContainer()
        character.cart = cart
        cart.setContainer(character.inventory)
        cart.setModule("SaucedWheelbarrow")
        cart.setType("WheelbarrowWood")
        cart.setStaticModel("Base.WheelbarrowWood")
        instance.modelScript = model("Base", "WheelbarrowWood")
        val body = ModelInstanceRenderData()
        body.modelInstance = parent
        val slot = ModelSlotRenderData()
        slot.character = character
        slot.modelData.add(body)
        slot.modelData.add(data)
        val mesh = instance.model.mesh
        val minimum = ModelMesh::class.java.getField("minXyz")
        val maximum = ModelMesh::class.java.getField("maxXyz")
        minimum.isAccessible = true
        maximum.isAccessible = true
        minimum.set(mesh, Vector3f(-.01f))
        maximum.set(mesh, Vector3f(.01f))
        val animationModel = ModelManager::class.java.getDeclaredField("animModel")
        animationModel.isAccessible = true
        val previousModel = animationModel.get(ModelManager.instance)
        val animations = unsafe.allocateInstance(ModelMesh::class.java) as ModelMesh
        animations.skinningData = skeleton
        skeleton.animationClips["Bob_Cart_Idle"] = idle
        try {
            animationModel.set(ModelManager.instance, animations)
            data.parent.xfrm.identity()
            val expected = Matrix4f()
            val delta = Matrix4f()
            if (!CartGrounding.rigid(data, idle, expected))
                throw AssertionError("render fixture has no rigid reference")
            CartGrounding.lowerHandles(expected, "WheelbarrowWood")
            if (!CartGrounding.alignWood(expected, 0f, 0f, delta))
                throw AssertionError("render fixture cannot ground its wheel")
            if (CartGrip.render(slot, parent, idle, delta, "WheelbarrowWood", expected))
                throw AssertionError("render fixture must reject IK without a body palette")
            for (arm in floatArrayOf(-.3f, -.1f, 0f, .2f, .4f)) {
                data.xfrm
                    .translation(arm, .3f + arm * .2f, -.2f - arm)
                    .rotateXYZ(arm, arm * .5f, -arm)
                    .transpose()
                val fallback = Matrix4f(data.xfrm).transpose()
                if (
                    !CartGrounding.ground(fallback, mesh.minXyz, mesh.maxXyz) ||
                        fallback.equals(expected, .00001f)
                )
                    throw AssertionError(
                        "render fixture does not distinguish native arm fallback from the rigid cart",
                    )
                CartGrounding.render(slot)
                val actual = Matrix4f(data.xfrm).transpose()
                if (
                    !actual.equals(expected, .00001f) ||
                        Math.abs(CartGrounding.woodenLowest(actual) - .008f) > .000001f
                )
                    throw AssertionError(
                        "failed IK restored the moving arm cart or lost wheel grounding: $arm",
                    )
            }
            // Inventory equip's first frame already owns both hands/Weapon but Lua has not
            // refreshed motion yet.
            character.motionDisabled = true
            character.weapon = "cart"
            val firstExpected = Matrix4f()
            if (!CartGrounding.rigid(data, idle, firstExpected))
                throw AssertionError("first equip has no rigid reference")
            CartGrounding.lowerHandles(firstExpected, "WheelbarrowWood")
            CartGrounding.alignWood(firstExpected, 0f, 0f, Matrix4f())
            data.xfrm.translation(-.011584065f, .045023113f, -.21670187f).rotateX(.5f).transpose()
            CartGrounding.render(slot)
            if (
                !Matrix4f(data.xfrm).transpose().equals(firstExpected, .00001f) ||
                    CartMotionSync.visualEnabled(character) ||
                    !character.motionDisabled ||
                    character.cart !== cart ||
                    cart.getContainer() !== character.inventory
            )
                throw AssertionError(
                    "first inventory equip exposed the native attachment or changed native ownership/motion",
                )
            character.motionDisabled = false
            data.xfrm.translation(.3f, .9f, .1f).rotateX(-.4f).transpose()
            CartGrounding.render(slot)
            if (!Matrix4f(data.xfrm).transpose().equals(firstExpected, .00001f))
                throw AssertionError("Lua motion refresh changed the first-frame rigid target")
            character.weapon = null
            // Reproduce the native successful-pickup gap: an authoritative held cart exists,
            // while ordinary motion is disabled and native attachment data is high/pitched.
            character.motionDisabled = true
            parent.attachment = null
            instance.attachment = null
            instance.attachmentNameParent = null
            instance.attachmentNameSelf = null
            instance.parentBoneName = "prop"
            instance.scale = 1f
            val worldMesh = unsafe.allocateInstance(ModelMesh::class.java) as ModelMesh
            val ready = unsafe.allocateInstance(Class.forName("zombie.asset.Asset\$PRIVATE"))
            field(ready, ready.javaClass, "currentState", zombie.asset.Asset.State.READY)
            field(worldMesh, zombie.asset.Asset::class.java, "priv", ready)
            field(mesh, zombie.asset.Asset::class.java, "priv", ready)
            val worldModel = unsafe.allocateInstance(Model::class.java) as Model
            field(worldModel, Model::class.java, "mesh", worldMesh)
            val worldScript = model("Base", "ShoppingCartModel")
            worldScript.scale = 1f
            worldScript.setModelManagerKey("handoff-shopping-world")
            val loaded = ModelManager::class.java.getDeclaredField("modelMap")
            loaded.isAccessible = true
            @Suppress("UNCHECKED_CAST")
            val loadedModels = loaded.get(ModelManager.instance) as MutableMap<String, Model>
            val oldWorld = loadedModels.put(worldScript.getModelManagerKey(), worldModel)
            try {
                for (name in arrayOf("WheelbarrowWood", "WheelbarrowMetal", "ShoppingCartModel")) {
                    val item = unsafe.allocateInstance(Cart::class.java) as Cart
                    item.worldScale = 1f
                    item.setModule(
                        if (name.startsWith("Wheelbarrow")) "SaucedWheelbarrow" else "SaucedCarts",
                    )
                    item.setType(if (name.startsWith("Wheelbarrow")) name else "ShoppingCart")
                    item.setStaticModel(name)
                    item.setContainer(character.inventory)
                    character.cart = item
                    instance.modelScript = model("Base", name)
                    val profile = CartWheelbarrow.forModel(name)
                    val held =
                        if (profile == null)
                            CartShopping.held(Matrix4f()) ?: throw NullPointerException()
                        else profile.held(Matrix4f())
                    mesh.transform = Matrix4f(reference).invert().mul(held).transpose()
                    worldMesh.transform =
                        (CartShopping.worldModel(Matrix4f()) ?: throw NullPointerException())
                            .transpose()
                    val neutral = Matrix4f()
                    val correction = Matrix4f()
                    if (!CartGrounding.rigid(data, idle, neutral))
                        throw AssertionError("handoff has no native rigid reference")
                    CartGrounding.lowerHandles(neutral, name)
                    if (
                        !(if (profile == null)
                            CartShopping.align(neutral, CartTransition.model(item), 1f, correction)
                        else
                            CartGrounding.alignWheelbarrow(
                                neutral,
                                profile,
                                0f,
                                0f,
                                0f,
                                correction,
                            ))
                    )
                        throw AssertionError("handoff neutral reference refused: $name")
                    val raw = Matrix4f(held).rotateLocalX(1.1f).translateLocal(0f, .6f, .4f)
                    data.xfrm.set(raw).transpose()
                    CartGrounding.render(slot)
                    if (!Matrix4f(data.xfrm).transpose().equals(raw, .00001f))
                        throw AssertionError(
                            "disabled motion without a pickup token rewrote native transform",
                        )
                    handoff(character, item, unsafe)
                    if (
                        !CartTransition.pickupHandoff(character) ||
                            CartMotionSync.visualEnabled(character)
                    )
                        throw AssertionError(
                            "fresh completion did not isolate render bridge from motion",
                        )
                    for (frame in 0 until 3) {
                        data.xfrm.set(raw).transpose()
                        CartGrounding.render(slot)
                        if (!Matrix4f(data.xfrm).transpose().equals(neutral, .00003f))
                            throw AssertionError(
                                "completion exposed high/pitched native attachment for $name frame=$frame",
                            )
                    }
                    if (
                        character.cart !== item ||
                            item.getContainer() !== character.inventory ||
                            item.getWorldItem() != null ||
                            !character.motionDisabled
                    )
                        throw AssertionError("render bridge changed native authority or locomotion")
                    CartTransition.end(character)
                }
            } finally {
                if (oldWorld == null) loadedModels.remove(worldScript.getModelManagerKey())
                else loadedModels[worldScript.getModelManagerKey()] = oldWorld
            }
        } finally {
            animationModel.set(ModelManager.instance, previousModel)
        }
    }

    private fun presentationReadiness() {
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe")
        unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        val player = unsafe.allocateInstance(Player::class.java) as Player
        player.motionDisabled = true
        player.weapon = "cart"
        player.inventory = ItemContainer()
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.cart = cart
        cart.setModule("SaucedWheelbarrow")
        cart.setType("WheelbarrowWood")
        cart.setStaticModel("Base.WheelbarrowWood")
        cart.setContainer(player.inventory)
        model("Base", "WheelbarrowWood")
        model("Base", "WheelbarrowMetal")
        if (!CartGrounding.heldPresentationReady(player) || CartMotionSync.visualEnabled(player))
            throw AssertionError("first authoritative equip still waits for the Lua motion refresh")
        player.splitHands = true
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("one-hand snapshot admitted")
        player.splitHands = false
        player.weapon = ""
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("missing native cart Weapon admitted")
        player.weapon = "cart"
        cart.setStaticModel("Base.WheelbarrowMetal")
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("foreign static model admitted")
        cart.setStaticModel("Base.WheelbarrowWood")
        cart.setContainer(ItemContainer())
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("local foreign-container cart admitted")
        cart.setContainer(player.inventory)
        for (state in arrayOf("aiming", "sneaking", "dead")) {
            field(player, Player::class.java, state, true)
            if (CartGrounding.heldPresentationReady(player))
                throw AssertionError("unsafe presentation admitted: $state")
            field(player, Player::class.java, state, false)
        }
        player.injury = .15f
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("unsupported injured gait admitted")
        player.injury = 0f
        player.forceNullOverride = true
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("native null model override replaced")
        player.forceNullOverride = false
        player.overridePrimaryHandModel = "foreign"
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("foreign action model replaced")
        player.overridePrimaryHandModel = null
        player.action = true
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("unidentified active action admitted")
        val action =
            unsafe.allocateInstance(
                zombie.characters.CharacterTimedActions.LuaTimedActionNew::class.java,
            ) as zombie.characters.CharacterTimedActions.LuaTimedActionNew
        action.chr = player
        action.setTime(30)
        action.setCurrentTime(0f)
        field(action, action.javaClass, "started", true)
        (action as zombie.characters.CharacterTimedActions.BaseAction).started = true
        val table = se.krka.kahlua.j2se.KahluaTableImpl(HashMap())
        val metatable = se.krka.kahlua.j2se.KahluaTableImpl(HashMap())
        metatable.rawset("Type", "ISCartEquipAction")
        table.setMetatable(metatable)
        table.rawset("character", player)
        table.rawset("cartId", cart.getID().toDouble())
        field(action, action.javaClass, "table", table)
        player.getCharacterActions().push(action)
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("unfinished equip admitted")
        action.setCurrentTime(30f)
        if (!CartGrounding.heldPresentationReady(player))
            throw AssertionError("exact finished equip still blocked by native stack lag")
        table.rawset("cartId", cart.getID().toDouble() + 1)
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("finished foreign-cart equip admitted")
        table.rawset("cartId", cart.getID().toDouble())
        metatable.rawset("Type", "ISOtherAction")
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("unrelated finished action admitted")
        metatable.rawset("Type", "ISCartEquipAction")
        action.forceStop = true
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("stopped equip admitted")
        action.forceStop = false
        player.getCharacterActions().push(action)
        if (CartGrounding.heldPresentationReady(player))
            throw AssertionError("multi-action stack admitted")
        player.getCharacterActions().clear()
        player.action = false
        player.remote = true
        cart.setContainer(null)
        player.inventory = null
        val oldClient = zombie.network.GameClient.client
        val oldConnected = zombie.network.GameClient.instance.connected
        val oldConnection = zombie.network.GameClient.connection
        try {
            zombie.network.GameClient.client = true
            zombie.network.GameClient.instance.connected = true
            zombie.network.GameClient.connection =
                unsafe.allocateInstance(zombie.core.raknet.UdpConnection::class.java)
                    as zombie.core.raknet.UdpConnection
            if (
                !CartGrounding.heldPresentationReady(player) || CartMotionSync.visualEnabled(player)
            )
                throw AssertionError(
                    "exact remote equipment waited for inventory or a motion packet",
                )
            zombie.network.GameClient.instance.connected = false
            if (CartGrounding.heldPresentationReady(player))
                throw AssertionError("disconnected remote admitted")
        } finally {
            zombie.network.GameClient.client = oldClient
            zombie.network.GameClient.instance.connected = oldConnected
            zombie.network.GameClient.connection = oldConnection
        }
    }

    private fun capturedContacts() {
        // Actual VBO minima and final matrices captured together in B42.21 before the contact fix.
        val models = arrayOf("ShoppingCartModel", "WheelbarrowWood", "WheelbarrowMetal")
        val points =
            arrayOf(
                Vector3f(110.0467f, 8.371053f, .98356926f),
                Vector3f(-2.1228965e-4f, -.004435286f, -4.0280633e-5f),
                Vector3f(-23.5423f, -23.2973f, -2.97487f),
            )
        val minima = floatArrayOf(.045946702f, .03383575f, .054394957f)
        val captured =
            arrayOf(
                Matrix4f()
                    .set(
                        -5.080325e-10f,
                        7.381783e-10f,
                        .104969054f,
                        -.0016536561f,
                        -2.2194229e-4f,
                        .0016076594f,
                        -6.051497e-8f,
                        .05691298f,
                        -.0021531826f,
                        -1.6571165e-4f,
                        -1.0280073e-8f,
                        -.44702002f,
                        0f,
                        0f,
                        0f,
                        1f,
                    )
                    .transpose(),
                Matrix4f()
                    .set(
                        76.5f,
                        2.8023098e-5f,
                        -2.4333809e-5f,
                        -.0060535767f,
                        -4.1037783e-5f,
                        30.694286f,
                        -70.07218f,
                        .16715112f,
                        -9.11952e-6f,
                        70.07218f,
                        30.694283f,
                        -.41188842f,
                        0f,
                        0f,
                        0f,
                        1f,
                    )
                    .transpose(),
                Matrix4f()
                    .set(
                        .0091743395f,
                        2.9182563e-9f,
                        3.3606993e-9f,
                        .21714664f,
                        -4.9214974e-9f,
                        .008403477f,
                        .003681045f,
                        .2611238f,
                        -1.0936676e-9f,
                        -.0036810448f,
                        .008403477f,
                        -.8401939f,
                        0f,
                        0f,
                        0f,
                        1f,
                    )
                    .transpose(),
            )
        val low = Vector3f(-1000f)
        val high = Vector3f(1000f)
        for (i in models.indices) {
            val contact = CartGrounding.contact(models[i])
            if (contact == null || !points[i].equals(contact))
                throw AssertionError("wrong calibrated contact for ${models[i]}")
            if (Math.abs(captured[i].transformPosition(Vector3f(points[i])).y - minima[i]) > 1e-6f)
                throw AssertionError(
                    "captured matrix disagrees with actual VBO minimum for ${models[i]}",
                )
            val after = Matrix4f(captured[i])
            val delta = Matrix4f()
            if (
                !CartGrounding.align(after, low, high, contact, 0f, delta) ||
                    Math.abs(after.transformPosition(Vector3f(points[i])).y - .008f) > 1e-6f ||
                    Math.abs(delta.m31() - (.008f - minima[i])) > 1e-6f
            )
                throw AssertionError("actual wheel geometry still floats for ${models[i]}")
            val expected = Matrix4f(captured[i])
            expected.m31(after.m31())
            if (!after.equals(expected))
                throw AssertionError(
                    "contact correction changed orientation/scale for ${models[i]}",
                )
            val pitched = Matrix4f(captured[i])
            CartGrounding.lowerHandles(pitched, models[i])
            val tire = captured[i].transformPosition(Vector3f(contact))
            if (i == 1) tire.z += .05f
            if (i == 2) tire.z += .10f
            if (pitched.transformPosition(Vector3f(contact)).distance(tire) > 1e-6f)
                throw AssertionError("lowering handles moved wheel contact for ${models[i]}")
            if (i == 0 && !pitched.equals(captured[i]))
                throw AssertionError("shopping cart was pitched")
            if (i > 0) {
                val rawHandle =
                    if (i == 1) Vector3f(.00172237f, .00541905f, -.00342593f)
                    else Vector3f(-7.409948f, 6.614635f, 82.79839f)
                val handle = captured[i].transformPosition(Vector3f(rawHandle))
                val lowered = pitched.transformPosition(Vector3f(rawHandle))
                if (
                    if (i == 1) Math.abs(handle.y - lowered.y - .0857464f) > .00001f
                    else handle.y - lowered.y < .11f || handle.y - lowered.y > .15f
                )
                    throw AssertionError("handles not lowered to a relaxed arm height")
                if (
                    if (i == 1)
                        !CartGrounding.alignWood(pitched, 0f, 0f, delta) ||
                            Math.abs(CartGrounding.woodenLowest(pitched) - .008f) > 1e-6f
                    else
                        !CartGrounding.align(pitched, low, high, contact, 0f, delta) ||
                            Math.abs(pitched.transformPosition(Vector3f(contact)).y - .008f) > 1e-6f
                )
                    throw AssertionError("pitched tire not grounded")
                if (Math.abs(delta.m12()) > 1e-6f || Math.abs(delta.m21()) > 1e-6f)
                    throw AssertionError("cart pitch leaked into the actor's torso")
                // The old and new observed wooden tire vertices bracket the new lowest polygon
                // edge.
                if (
                    i == 1 &&
                        pitched
                            .transformPosition(
                                Vector3f(-2.1228965e-4f, -.004627711f, -1.199774e-4f),
                            )
                            .y < .008f - 1e-6f
                )
                    throw AssertionError("lowered handles put the old tire contact underground")
            }
            for (lean in floatArrayOf(-.1f, .1f)) {
                if (!CartGrounding.align(after.set(captured[i]), low, high, contact, lean, delta))
                    throw AssertionError("lean rejected")
                val wheel = after.transformPosition(Vector3f(contact))
                val fixed = captured[i].transformPosition(Vector3f(contact))
                fixed.y = .008f
                if (wheel.distance(fixed) > 1e-6f)
                    throw AssertionError("bank moved the actual tire contact for ${models[i]}")
                val handle = Vector3f(points[i]).add(.001f, .002f, .003f)
                val cartHandle = after.transformPosition(Vector3f(handle))
                delta.transformPosition(captured[i].transformPosition(handle))
                if (handle.distance(cartHandle) > 1e-5f)
                    throw AssertionError("contact correction separated grip and cart")
            }
        }
        for (model in
            arrayOf(
                "ShoppingCartPartialModel",
                "ShoppingCartFullModel",
                "ShoppingCartFlashlightModel",
                "ShoppingCartFlashlightPartialModel",
                "ShoppingCartFlashlightFullModel",
            )) if (!points[0].equals(CartGrounding.contact(model)))
            throw AssertionError("shop variant not calibrated: $model")
        if (
            CartGrounding.contact("ShoppingCartModelExtra") != null ||
                CartGrounding.contact(null) != null
        )
            throw AssertionError("unverified model accepted")
        low.set(-.35f, 0f, -.6f)
        high.set(.35f, 1f, .6f)
        val fallback = Matrix4f().translation(0f, -.15f, 0f)
        CartGrounding.ground(fallback, low, high)
        for (invalid in
            arrayOf(
                Vector3f(Float.NaN, 0f, 0f),
                Vector3f(0f, Float.POSITIVE_INFINITY, 0f),
                Vector3f(10f, 0f, 0f),
            )) {
            val actual = Matrix4f().translation(0f, -.15f, 0f)
            if (!CartGrounding.ground(actual, low, high, invalid) || !actual.equals(fallback))
                throw AssertionError("invalid/outside calibrated contact did not use AABB fallback")
        }
    }

    private fun metalHeldCalibration() {
        val profile = CartWheelbarrow.METAL
        val actual =
            Matrix4f()
                .set(
                    .0091743395f,
                    -4.9214974e-9f,
                    -1.0936676e-9f,
                    0f,
                    2.9182563e-9f,
                    .008403477f,
                    -.0036810448f,
                    0f,
                    3.3606993e-9f,
                    .003681045f,
                    .008403477f,
                    0f,
                    .21714664f,
                    .25123572f,
                    -.8401939f,
                    1f,
                )
        CartGrounding.lowerHandles(actual, profile.model())
        if (
            !CartGrounding.alignWheelbarrow(actual, profile, 0f, 0f, 0f, Matrix4f()) ||
                !actual.equals(profile.held(Matrix4f()), .000002f)
        )
            throw AssertionError("metal transition endpoint differs from native rigid held pose")
        val wheel = actual.transformPosition(profile.center(Vector3f()))
        if (Math.abs(-1.5 * wheel.z - profile.axle()) > .000001)
            throw AssertionError("metal steering axle differs from rendered tire")
        if (Math.abs(profile.axle() + 1.5 * profile.pickupStanceBack() - 1.117308812) > .000001)
            throw AssertionError("metal held stance changed the accepted grounded pickup approach")
        for (pressure in floatArrayOf(0f, Math.toRadians(7.0).toFloat())) for (gait in
            floatArrayOf(0f, -.24f)) {
            val moving = profile.held(Matrix4f())
            val delta = Matrix4f()
            if (!CartGrounding.alignWheelbarrow(moving, profile, 0f, pressure, gait, delta))
                throw AssertionError("metal gait calibration refused")
            val target = Matrix4f()
            CartGrip.target(profile.model(), true, false, delta, moving, target, pressure)
            // The former measured neutral wrist sat at Z=-.083618924 before its gait clearance was
            // added.
            // Remove this profile's gait/turn translation before comparing its neutral
            // stance. Metal intentionally uses 1.15 times the wooden clearance.
            if (target.m32() - profile.motionShift(pressure, gait) - (-.083618924f) < .075f)
                throw AssertionError("metal motion lost the requested closer hand position")
        }
    }

    private fun metalBankGait() {
        val profile = CartWheelbarrow.METAL
        val source = profile.held(Matrix4f())
        for (bank in
            floatArrayOf(
                Math.toRadians(-7.0).toFloat(),
                0f,
                Math.toRadians(7.0).toFloat(),
            )) for (gait in floatArrayOf(0f, -.24f)) {
            val actual = Matrix4f(source)
            val delta = Matrix4f()
            val pressure = Math.abs(bank)
            if (
                !CartGrounding.alignWheelbarrow(actual, profile, bank, pressure, gait, delta) ||
                    !actual.isFinite() ||
                    Math.abs(CartGrounding.wheelbarrowLowest(actual, profile) - .008f) > .00001f
            )
                throw AssertionError(
                    "metal wheel lost cylindrical floor support: bank=$bank gait=$gait",
                )
            // Independently sample both sidewalls around the calibrated tire, including every spin
            // phase.
            for (side in floatArrayOf(-profile.halfWidth(), profile.halfWidth())) for (degree in
                0 until 360 step 5) {
                val phase = Math.toRadians(degree.toDouble()).toFloat()
                val rim =
                    profile
                        .center(Vector3f())
                        .add(
                            side,
                            profile.radius() * Math.cos(phase.toDouble()).toFloat(),
                            profile.radius() * Math.sin(phase.toDouble()).toFloat(),
                        )
                if (actual.transformPosition(rim).y < .008f - .00001f)
                    throw AssertionError(
                        "banked metal tire penetrates floor: bank=$bank gait=$gait phase=$degree",
                    )
            }
            for (left in booleanArrayOf(true, false)) {
                val handle = Vector3f()
                if (!CartGrip.handle(profile.model(), left, handle))
                    throw AssertionError("metal handle calibration missing")
                val moved = delta.transformPosition(source.transformPosition(Vector3f(handle)))
                moved.z += profile.motionShift(pressure, gait)
                if (moved.distance(actual.transformPosition(handle)) > .00001f)
                    throw AssertionError(
                        "metal body/cart handle transforms separated: bank=$bank gait=$gait",
                    )
            }
        }
    }

    private fun remoteFillModel() {
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.isAccessible = true
        val unsafe = field.get(null) as Unsafe
        val player = unsafe.allocateInstance(Player::class.java) as Player
        player.remote = true
        player.inventory = ItemContainer()
        val item = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.cart = item
        item.setModule("SaucedCarts")
        item.setType("ShoppingCart")
        item.setContainer(player.inventory)
        item.setStaticModel("ShoppingCartModel")
        val cached = ModelInstance()
        cached.modelScript = model("Base", item.getStaticModel())
        val full = model("Base", "ShoppingCartFullModel")
        player.primaryHandModel = cached
        item.setStaticModel("Base.ShoppingCartFullModel")
        if (!cached.modelScript.getName().equals("ShoppingCartModel"))
            throw AssertionError("native ModData fixture unexpectedly refreshed its cached model")
        CartGrounding.refreshRemoteModel(player)
        if (
            player.resets != 1 ||
                player.primaryHandModel !== cached ||
                player.cart !== item ||
                !item.getStaticModel().equals("Base.ShoppingCartFullModel")
        )
            throw AssertionError(
                "remote fill mismatch must queue refresh without mutating models or equipment",
            )
        cached.modelScript = full
        player.resets = 0
        CartGrounding.refreshRemoteModel(player)
        if (player.resets != 0) throw AssertionError("correct remote fill model was rebuilt")
        item.setStaticModel("ShoppingCartFullModel")
        CartGrounding.refreshRemoteModel(player)
        if (player.resets != 0 || CartGrounding.resolvedModel(item) !== full)
            throw AssertionError(
                "qualified and unqualified native names resolved to different model identities",
            )
        for (gate in
            arrayOf(
                "local",
                "action",
                "stack",
                "primaryOverride",
                "secondaryOverride",
                "unknownExpected",
                "unknownActual",
                "foreignExpected",
                "foreignActual",
                "differentFamily",
                "unsupportedItem",
                "missingInstance",
            )) {
            player.remote = true
            player.action = false
            player.getCharacterActions().clear()
            player.overridePrimaryHandModel = null
            player.overrideSecondaryHandModel = null
            player.primaryHandModel = cached
            item.setModule("SaucedCarts")
            item.setType("ShoppingCart")
            item.setStaticModel("ShoppingCartFullModel")
            cached.modelScript = model("Base", "ShoppingCartModel")
            when (gate) {
                "local" -> player.remote = false
                "action" -> player.action = true
                "stack" -> player.getCharacterActions().add(null)
                "primaryOverride" -> player.overridePrimaryHandModel = "ShoppingCartModel"
                "secondaryOverride" -> player.overrideSecondaryHandModel = "Mug"
                "unknownExpected" -> item.setStaticModel("OtherCartFullModel")
                "unknownActual" -> cached.modelScript = model("Base", "OtherCartModel")
                "foreignExpected" -> {
                    model("Foreign", "ShoppingCartFullModel")
                    item.setStaticModel("Foreign.ShoppingCartFullModel")
                }
                "foreignActual" -> cached.modelScript = model("Foreign", "ShoppingCartModel")
                "differentFamily" -> {
                    item.setModule("SaucedWheelbarrow")
                    item.setType("WheelbarrowMetal")
                }
                "unsupportedItem" -> item.setType("OtherCart")
                "missingInstance" -> player.primaryHandModel = null
            }
            CartGrounding.refreshRemoteModel(player)
            if (player.resets != 0)
                throw AssertionError("remote fill refresh escaped its exact ownership gate: $gate")
        }
        for (name in
            arrayOf(
                "ShoppingCartModel",
                "ShoppingCartPartialModel",
                "ShoppingCartFullModel",
                "ShoppingCartFlashlightModel",
                "ShoppingCartFlashlightPartialModel",
                "ShoppingCartFlashlightFullModel",
                "WheelbarrowWood",
                "WheelbarrowMetal",
            )) {
            item.setModule(
                if (name.startsWith("Wheelbarrow")) "SaucedWheelbarrow" else "SaucedCarts",
            )
            item.setType(if (name.startsWith("Wheelbarrow")) name else "ShoppingCart")
            val expected = model("Base", name)
            item.setStaticModel("Base.$name")
            if (
                CartGrounding.resolvedModel(item) !== expected ||
                    !CartGrounding.sameModel(item, name) ||
                    CartGrounding.sameModel(item, "Foreign.$name")
            )
                throw AssertionError(
                    "native cart-model resolution lost its exact Base identity: $name",
                )
        }
    }

    private fun wheelbarrowProfiles() {
        for (profile in arrayOf(CartWheelbarrow.WOOD, CartWheelbarrow.METAL)) {
            if (
                CartWheelbarrow.forModel(profile.model()) !== profile ||
                    CartWheelbarrow.forType("SaucedWheelbarrow.${profile.model()}") !== profile
            )
                throw AssertionError("wheelbarrow factories lost singleton identity")
            val out = Matrix4f()
            if (profile.held(out) !== out)
                throw AssertionError("held calibration must reuse its output")
            val expected = Matrix4f(out)
            out.zero()
            if (profile.held(out) !== out || !out.equals(expected))
                throw AssertionError("held output mutation changed the stored calibration")
            val center = Vector3f()
            if (
                profile.center(center) !== center ||
                    center.x != profile.centerX() ||
                    center.y != profile.centerY() ||
                    center.z != profile.centerZ()
            )
                throw AssertionError("wheelbarrow center must reuse its output")
        }
        if (
            CartWheelbarrow.forModel(null) != null ||
                CartWheelbarrow.forType(null) != null ||
                CartWheelbarrow.forItem(null) != null ||
                CartWheelbarrow.forModel("WheelbarrowWoodExtra") != null ||
                CartWheelbarrow.forType("Foreign.WheelbarrowWood") != null
        )
            throw AssertionError("unverified wheelbarrow profile accepted")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        wheelbarrowProfiles()
        if (
            CartGrounding.inventoryEntryAdvance(0f) != 0f ||
                CartGrounding.inventoryEntryAdvance(1f) != 0f ||
                CartGrounding.inventoryEntryAdvance(Float.NaN) != 0f
        )
            throw AssertionError("Blender entry endpoints")
        val authoredEntry = CartGrounding.inventoryEntryAdvance(.22222553f)
        if (authoredEntry < .004f || authoredEntry > .0081f)
            throw AssertionError("native clothing replay correction corridor")
        for (i in 0..1000) {
            val advance = CartGrounding.inventoryEntryAdvance(i / 1000f)
            if (!advance.isFinite() || advance < 0 || advance > .0081f)
                throw AssertionError("bounded Blender curve")
        }
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        remoteFillModel()
        nativeExportPose()
        rigidPose()
        presentationReadiness()
        capturedContacts()
        metalHeldCalibration()
        metalBankGait()
        val wooden =
            Matrix4f()
                .set(
                    76.5f,
                    2.8023098e-5f,
                    -2.4333809e-5f,
                    -.0060535767f,
                    -4.1037783e-5f,
                    30.694286f,
                    -70.07218f,
                    .16715112f,
                    -9.11952e-6f,
                    70.07218f,
                    30.694283f,
                    -.41188842f,
                    0f,
                    0f,
                    0f,
                    1f,
                )
                .transpose()
        CartGrounding.lowerHandles(wooden, "WheelbarrowWood")
        val straight = Matrix4f(wooden)
        if (!CartGrounding.alignWood(straight, 0f, 0f, Matrix4f()))
            throw AssertionError("straight wooden grounding rejected")
        val expectedStraight = Matrix4f(wooden)
        expectedStraight.m31(straight.m31())
        if (!straight.equals(expectedStraight))
            throw AssertionError("zero bank changed the wooden baseline pose")
        for (degree in -7..7) {
            val lean = Math.toRadians(degree.toDouble()).toFloat()
            val pressure = Math.toRadians(7.0).toFloat()
            val retained = Matrix4f(wooden)
            val delta = Matrix4f()
            if (!CartGrounding.alignWood(retained, lean, pressure, -.12f, delta))
                throw AssertionError("slalom clearance rejected")
            val center =
                retained.transformPosition(
                    Vector3f(
                        CartWheelSpin.CENTER_X,
                        CartWheelSpin.CENTER_Y,
                        CartWheelSpin.CENTER_Z,
                    ),
                )
            if (Math.abs(-1.5 * center.z - CartSteeringMath.woodenAxle(pressure, -.12f)) > .00001)
                throw AssertionError(
                    "slalom wheel must use retained clearance, not instantaneous bank",
                )
            if (Math.abs(CartGrounding.woodenLowest(retained) - .008f) > .00001)
                throw AssertionError("retaining slalom clearance lifted the wheel")
            for (left in booleanArrayOf(true, false)) {
                val handle = Vector3f()
                CartGrip.handle("WheelbarrowWood", left, handle)
                val point = delta.transformPosition(wooden.transformPosition(Vector3f(handle)))
                point.z += CartSteeringMath.woodenShift(pressure, -.12f)
                if (point.distance(retained.transformPosition(handle)) > .00001)
                    throw AssertionError("slalom body and handle transforms disagree")
            }
        }
        var straightHandleY = 0f
        for (left in booleanArrayOf(true, false)) {
            val handle = Vector3f()
            CartGrip.handle("WheelbarrowWood", left, handle)
            straightHandleY += straight.transformPosition(handle).y / 2
        }
        for (gaitShift in
            floatArrayOf(0f, -.03f, -.05f, -.06f, -.09f, -.12f, -.18f, -.24f)) for (tick in
            -84..84) {
            val lean = Math.toRadians(tick / 12.0).toFloat()
            val actual = Matrix4f(wooden)
            val delta = Matrix4f()
            if (!CartGrounding.alignWood(actual, lean, gaitShift, delta))
                throw AssertionError("wooden bank rejected")
            var minimum = Float.POSITIVE_INFINITY
            for (degree in 0 until 360) for (side in intArrayOf(-1, 1)) {
                val angle = Math.toRadians(degree.toDouble())
                val rim =
                    Vector3f(
                        CartWheelSpin.CENTER_X + side * .00024333253f,
                        CartWheelSpin.CENTER_Y + CartWheelSpin.RADIUS * Math.cos(angle).toFloat(),
                        CartWheelSpin.CENTER_Z + CartWheelSpin.RADIUS * Math.sin(angle).toFloat(),
                    )
                minimum = Math.min(minimum, actual.transformPosition(rim).y)
            }
            if (minimum < .008f - 1e-6f || minimum > .008f + .00001f)
                throw AssertionError(
                    "spinning wooden tire must stay grounded through all wheel phases: $minimum",
                )
            var meanHandleY = 0f
            for (left in booleanArrayOf(true, false)) {
                val handle = Vector3f()
                CartGrip.handle("WheelbarrowWood", left, handle)
                val transformed =
                    delta.transformPosition(wooden.transformPosition(Vector3f(handle)))
                transformed.z += CartSteeringMath.woodenShift(lean, gaitShift)
                val expected = actual.transformPosition(handle)
                meanHandleY += expected.y / 2
                if (transformed.distance(expected) > 1e-5f)
                    throw AssertionError("wooden cart and handle transforms disagree")
            }
            if (
                Math.abs(meanHandleY - straightHandleY) >
                    (if (Math.abs(lean) <= Math.toRadians(3.0)) .0005f else .0012f)
            )
                throw AssertionError(
                    "turning lifted the mean wooden handle height: ${meanHandleY - straightHandleY}",
                )
            val center =
                actual.transformPosition(
                    Vector3f(
                        CartWheelSpin.CENTER_X,
                        CartWheelSpin.CENTER_Y,
                        CartWheelSpin.CENTER_Z,
                    ),
                )
            if (Math.abs(-1.5 * center.z - CartSteeringMath.woodenAxle(lean, gaitShift)) > .00001)
                throw AssertionError("steering axle disagrees with the actual wooden wheel center")
            if (tick == 0 && gaitShift == 0f && !actual.equals(straight))
                throw AssertionError("zero bank is not the exact walking baseline")
            val expectedRun = Matrix4f(straight)
            expectedRun.m32(expectedRun.m32() + gaitShift)
            if (tick == 0 && !actual.equals(expectedRun, .000001f))
                throw AssertionError("native Run changed the zero-bank wooden height/pitch")
        }
        val low = Vector3f(-.35f, 0f, -.6f)
        val high = Vector3f(.35f, 1f, .6f)
        for (degree in 0 until 360 step 15) {
            val before =
                Matrix4f()
                    .translation(.1f, -.15f, -.8f)
                    .rotateY(Math.toRadians(degree.toDouble()).toFloat())
                    .rotateX(.08f)
            val after = Matrix4f(before)
            if (!CartGrounding.ground(after, low, high))
                throw AssertionError("valid transform rejected")
            var lowest = Float.POSITIVE_INFINITY
            for (i in 0 until 8) {
                val point =
                    Vector3f(
                        if ((i and 1) == 0) low.x else high.x,
                        if ((i and 2) == 0) low.y else high.y,
                        if ((i and 4) == 0) low.z else high.z,
                    )
                after.transformPosition(point)
                lowest = Math.min(lowest, point.y)
            }
            if (Math.abs(lowest - .008f) > .00001f)
                throw AssertionError("cart intersects floor at $degree")
            before.m31(after.m31())
            if (!before.equals(after))
                throw AssertionError("grounding changed rotation/scale/position on floor")
        }
        val far = Matrix4f().translation(0f, -5f, 0f)
        val copy = Matrix4f(far)
        if (CartGrounding.ground(far, low, high) || !far.equals(copy))
            throw AssertionError("invalid pose was rewritten")
        for (lean in floatArrayOf(-.1f, 0f, .1f)) {
            val before = Matrix4f().translation(.2f, -.15f, -.8f)
            val grounded = Matrix4f(before)
            CartGrounding.ground(grounded, low, high)
            val groundDelta = grounded.m31() - before.m31()
            val after = Matrix4f(before)
            val delta = Matrix4f()
            if (!CartGrounding.align(after, low, high, lean, delta))
                throw AssertionError("cart lean rejected")
            val wheel = Vector3f(.2f, .008f - groundDelta, -1.1f)
            delta.transformPosition(wheel)
            if (wheel.distance(.2f, .008f, -1.1f) > .00001f)
                throw AssertionError("wheel contact moved when leaning")
            val point = Vector3f(.2f, .7f, -.1f)
            val actual = after.transformPosition(Vector3f(point))
            delta.transformPosition(before.transformPosition(point))
            if (actual.distance(point) > .00001f)
                throw AssertionError("cart and grip transforms disagree")
        }
        println("CART_GROUNDING_PASS")
    }
}
