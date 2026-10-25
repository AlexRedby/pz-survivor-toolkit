package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.util.HashMap
import org.lwjgl.util.vector.Vector3f
import sun.misc.Unsafe
import zombie.GameTime
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.ModelManager
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlend
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendPicker
import zombie.core.skinnedmodel.advancedanimation.Anim2DBlendTriangle
import zombie.core.skinnedmodel.advancedanimation.AnimLayer
import zombie.core.skinnedmodel.advancedanimation.AnimNode
import zombie.core.skinnedmodel.advancedanimation.AnimState
import zombie.core.skinnedmodel.advancedanimation.AnimTransition
import zombie.core.skinnedmodel.advancedanimation.AnimationSet
import zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot
import zombie.core.skinnedmodel.advancedanimation.LiveAnimNode
import zombie.core.skinnedmodel.animation.AnimationClip
import zombie.core.skinnedmodel.animation.AnimationPlayer
import zombie.core.skinnedmodel.animation.AnimationTrack
import zombie.core.skinnedmodel.animation.BoneAxis
import zombie.core.skinnedmodel.animation.Keyframe
import zombie.core.skinnedmodel.model.ModelMesh
import zombie.core.skinnedmodel.model.SkinningData
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.InventoryContainer
import zombie.iso.Vector2
import zombie.iso.objects.IsoWorldInventoryObject

object CartSteeringHooksTest {
    private class Keys : zombie.characters.component.CharacterInputComponent() {
        @JvmField var forward = false
        @JvmField var backward = false
        @JvmField var left = false
        @JvmField var right = false

        override fun isForwardKeyDown(): Boolean = forward

        override fun isBackwardKeyDown(): Boolean = backward

        override fun isLeftKeyDown(): Boolean = left

        override fun isRightKeyDown(): Boolean = right

        fun set(travel: Int, steering: Int) {
            forward = travel > 0
            backward = travel < 0
            left = steering < 0
            right = steering > 0
        }
    }

    // Skip world/renderer constructors, as the existing NativeChecks fixture does.
    private class Player : IsoPlayer(null, null, 0, 0, 0) {
        @JvmField var blocked = 0
        @JvmField var pivot = false
        @JvmField var brace = false
        @JvmField var woodBrake = false
        @JvmField var brakeSprint = false
        @JvmField var moving = false
        @JvmField var run = false
        @JvmField var sprint = false
        @JvmField var pathActive = false
        @JvmField var npc = false
        @JvmField var keyboard = false
        @JvmField var aim = false
        @JvmField var autoWalk = false
        @JvmField var keys: Keys? = null

        // The existing world-direction cases describe the preserved absolute analog-input contract.
        override fun getInputMode(): zombie.characters.CharacterInputMode =
            if (keyboard) zombie.characters.CharacterInputMode.KEYBOARD
            else zombie.characters.CharacterInputMode.GAMEPAD

        override fun isAimControlActive(): Boolean = aim

        override fun isAiming(): Boolean = aim

        override fun isAutoWalk(): Boolean = autoWalk

        override fun getCharacterInputComponent():
            zombie.characters.component.CharacterInputComponent? = keys

        @JvmField var nativePath: zombie.pathfind.PathFindBehavior2? = null
        @JvmField var finder: zombie.ai.astar.AStarPathFinderResult? = null
        @JvmField var machine: zombie.ai.StateMachine? = null
        @JvmField
        var actions: java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction?>? = null

        override fun getCharacterActions():
            java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction?> =
            actions
                ?: java.util.Stack<zombie.characters.CharacterTimedActions.BaseAction?>().also {
                    actions = it
                }

        @JvmField var animationUpdate: Runnable? = null
        @JvmField var walkSpeed = 0f
        @JvmField var injury = 0f
        @JvmField var slowFactor = 0f

        override fun getSlowFactor(): Float = slowFactor

        @JvmField var stepX = 0f
        @JvmField var stepY = 0f
        @JvmField var legPace = 0f
        @JvmField var actualX = 0f
        @JvmField var actualY = 0f
        @JvmField var inputX = 0f
        @JvmField var inputY = 0f
        @JvmField var inventory: ItemContainer? = null
        @JvmField var primary: InventoryItem? = null
        @JvmField var secondary: InventoryItem? = null
        @JvmField var animator: AdvancedAnimator? = null

        override fun getAdvancedAnimator(): AdvancedAnimator? = animator

        override fun getAnimationPlayer(): AnimationPlayer? = null

        override fun isRunning(): Boolean = run

        override fun isSprinting(): Boolean = sprint

        override fun isAllowRun(): Boolean = true

        override fun isAllowSprint(): Boolean = true

        override fun getVariableFloat(name: String?, fallback: Float): Float =
            when (name ?: throw NullPointerException()) {
                "WalkSpeed" -> walkSpeed
                "WalkInjury" -> injury
                "ToolkitCartStepX" -> stepX
                "ToolkitCartStepY" -> stepY
                "ToolkitCartLegPace" -> legPace
                else -> fallback
            }

        override fun clearVariable(name: String?) {
            if ((name ?: throw NullPointerException()).equals("ToolkitCartLegPace")) legPace = 0f
            if (name.equals("ToolkitCartWoodBrake")) woodBrake = false
        }

        override fun isLocalPlayer(): Boolean = blocked != 8

        override fun isDead(): Boolean = blocked == 1

        override fun hasHitReaction(): Boolean = blocked == 2

        override fun isKnockedDown(): Boolean = blocked == 3

        override fun isGettingUp(): Boolean = blocked == 4 || super.isGettingUp()

        override fun getStateMachine(): zombie.ai.StateMachine =
            machine ?: zombie.ai.StateMachine(this).also { machine = it }

        override fun isAnimationUpdatingThisFrame(): Boolean {
            animationUpdate?.run()
            return false
        }

        override fun setCurrentSquareFromPosition() {}

        override fun isGrappling(): Boolean = blocked == 5

        override fun isBeingGrappled(): Boolean = blocked == 6

        override fun isRagdollSimulationActive(): Boolean = blocked == 7

        override fun hasPath(): Boolean = pathActive || blocked == 9

        override fun isNpc(): Boolean = npc

        override fun getPathFindBehavior2(): zombie.pathfind.PathFindBehavior2? = nativePath

        override fun getFinder(): zombie.ai.astar.AStarPathFinderResult? = finder

        override fun getVariableBoolean(name: String?): Boolean =
            when (name ?: throw NullPointerException()) {
                "ToolkitCartMotion" -> blocked != 10
                "ToolkitCartPivot" -> pivot
                "ToolkitCartBrace" -> brace
                "ToolkitCartWoodBrake" -> woodBrake
                "ToolkitCartBrakeSprint" -> brakeSprint
                else -> false
            }

        override fun getPrimaryHandItem(): InventoryItem? = primary

        override fun getSecondaryHandItem(): InventoryItem? = secondary

        override fun getInventory(): ItemContainer? = inventory

        override fun getForwardDirectionX(): Float = 1f

        override fun getForwardDirectionY(): Float = 0f

        override fun getX(): Float = actualX

        override fun getY(): Float = actualY

        override fun getAnimForwardDirection(out: Vector2?): Vector2 =
            (out ?: throw NullPointerException()).set(1f, 0f)

        override fun getInputMoveVector(out: Vector2?): Vector2 =
            (out ?: throw NullPointerException()).set(inputX, inputY)

        override fun isJustMoved(): Boolean = moving

        override fun setTargetAndCurrentDirection(x: Float, y: Float) {}

        override fun setVariable(name: String?, value: Boolean): IAnimationVariableSlot? {
            if ((name ?: throw NullPointerException()).equals("ToolkitCartPivot")) pivot = value
            if (name.equals("ToolkitCartBrace")) brace = value
            if (name.equals("ToolkitCartWoodBrake")) woodBrake = value
            if (name.equals("ToolkitCartBrakeSprint")) brakeSprint = value
            return null
        }

        override fun setVariable(name: String?, value: Float): IAnimationVariableSlot? {
            if ((name ?: throw NullPointerException()).equals("ToolkitCartStepX")) stepX = value
            if (name.equals("ToolkitCartStepY")) stepY = value
            if (name.equals("ToolkitCartLegPace")) legPace = value
            return null
        }
    }

    private fun type(cart: InventoryContainer, fullType: String) {
        val dot = fullType.indexOf('.')
        cart.setModule(fullType.substring(0, dot))
        cart.setType(fullType.substring(dot + 1))
        cart.worldScale = 1f
    }

    private fun check(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    private fun field(obj: Any?, name: String): Field {
        val field = (obj ?: throw NullPointerException()).javaClass.getDeclaredField(name)
        field.isAccessible = true
        return field
    }

    private fun accept(player: Player, movement: Vector2?) {
        val step = movement ?: throw NullPointerException()
        player.actualX += step.x
        player.actualY += step.y
        CartSteeringHooks.heading(player)
    }

    private fun releaseAfterNativeGaitReset(player: Player, input: IsoPlayer.InputState) {
        // IsoPlayer clears these flags before UpdateInputState, then finalizes the new gait
        // afterward.
        player.run = false
        player.sprint = false
        player.inputX = 0f
        player.inputY = 0f
        input.setRunning(false)
        input.sprinting = false
        CartSteeringHooks.input(player, input)
    }

    private fun brakeAnimation(player: Player): LiveAnimNode {
        val animator = AdvancedAnimator()
        player.animator = animator
        val layer = AnimLayer.alloc(player, animator)
        val root = AdvancedAnimator::class.java.getDeclaredField("rootLayer")
        root.isAccessible = true
        root.set(animator, layer)
        val source = AnimNode()
        source.name = "ToolkitCartIdle"
        val node = LiveAnimNode.alloc(layer, source)
        val outgoing = AnimNode()
        outgoing.name = "ToolkitCartPivotSprint"
        val track = AnimationTrack.alloc()
        track.startClip(AnimationClip(2f, emptyList(), "Bob_SprintToStop2h_Heavy", true), false, 0f)
        node.startTransitionIn(outgoing, AnimTransition(), track)
        layer.getLiveAnimNodes().add(node)
        return node
    }

    private fun adjacentBrakeRelease(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val time = GameTime.getInstance()
        val oldFps = time.fpsMultiplier
        try {
            for (fps in intArrayOf(30, 60, 144)) for (sprint in
                booleanArrayOf(false, true)) for (order in
                arrayOf(
                    "together",
                    "modifier-first",
                    "modifier-delayed",
                    "direction-first",
                    "walk-on",
                )) {
                time.fpsMultiplier = 60f / fps
                val dt = time.getRealworldSecondsSinceLastUpdate().toDouble()
                CartSteeringHooks.reset(player)
                player.actualX = 0f
                player.actualY = 0f
                player.inputX = .5f
                player.inputY = .5f
                player.moving = true
                player.run = false
                player.sprint = false
                input.setRunning(!sprint)
                input.sprinting = sprint
                CartSteeringHooks.input(player, input)
                player.run = !sprint
                player.sprint = sprint
                accept(player, CartSteeringHooks.movement(player, (.2 * dt).toFloat(), 0f))
                val state = states[player]
                if (order.startsWith("modifier-") || order.equals("walk-on")) {
                    val frames = if (order.equals("modifier-delayed") && fps == 144) 4 else 1
                    for (frame in 0 until frames) {
                        player.run = false
                        player.sprint = false
                        input.setRunning(false)
                        input.sprinting = false
                        CartSteeringHooks.input(player, input)
                        check(
                            input.isRunning() == !sprint && input.sprinting == sprint,
                            "modifier-first must retain its native fast node within 50ms: $fps/$sprint/$frame",
                        )
                        player.run = input.isRunning()
                        player.sprint = input.sprinting
                        accept(player, CartSteeringHooks.movement(player, (.2 * dt).toFloat(), 0f))
                    }
                    if (order.equals("walk-on")) {
                        var elapsed = dt
                        do {
                            player.run = false
                            player.sprint = false
                            input.setRunning(false)
                            input.sprinting = false
                            CartSteeringHooks.input(player, input)
                            elapsed += dt
                            check(
                                (input.isRunning() || input.sprinting) == (elapsed <= .05) &&
                                    !player.woodBrake,
                                "holding direction after modifier release must enter Walk after at most 50ms: $fps/$elapsed",
                            )
                            player.run = input.isRunning()
                            player.sprint = input.sprinting
                            accept(
                                player,
                                CartSteeringHooks.movement(player, (.1 * dt).toFloat(), 0f),
                            )
                        } while (input.isRunning() || input.sprinting)
                        releaseAfterNativeGaitReset(player, input)
                        check(
                            !player.woodBrake,
                            "a later deliberate Walk release must not replay the fast stop",
                        )
                        continue
                    }
                } else if (order.equals("direction-first")) {
                    player.run = false
                    player.sprint = false
                    player.inputX = 0f
                    player.inputY = 0f
                    CartSteeringHooks.input(player, input)
                    check(
                        player.woodBrake,
                        "direction-first must arm the stop before releasing the modifier",
                    )
                    player.moving = false
                    player.run = !sprint
                    player.sprint = sprint
                    accept(player, CartSteeringHooks.movement(player, (.2 * dt).toFloat(), 0f))
                }
                releaseAfterNativeGaitReset(player, input)
                player.moving = false
                check(
                    player.woodBrake && field(state, "braking").getBoolean(state),
                    "both release orders and same-frame release must retain the native heavy stop: $fps/$sprint/$order",
                )
                val step = CartSteeringHooks.movement(player, .3f, 0f)
                check(
                    Math.abs(step.getLength() - .2 * dt) < 1e-7,
                    "release order must preserve the last accepted speed cap",
                )
                accept(player, step)
            }
            time.fpsMultiplier = 6f
            CartSteeringHooks.reset(player)
            player.actualX = 0f
            player.actualY = 0f
            player.inputX = .5f
            player.inputY = .5f
            player.moving = true
            player.run = false
            player.sprint = false
            input.setRunning(true)
            input.sprinting = false
            CartSteeringHooks.input(player, input)
            player.run = true
            accept(player, CartSteeringHooks.movement(player, .02f, 0f))
            player.run = false
            input.setRunning(false)
            CartSteeringHooks.input(player, input)
            check(
                !input.isRunning() && !input.sprinting,
                "a slow frame must not extend modifier release beyond the 50ms coalescing window",
            )
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = oldFps
        }
    }

    private fun residualBrake(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val time = GameTime.getInstance()
        val oldFps = time.fpsMultiplier
        try {
            for (fps in intArrayOf(30, 60, 144)) for (sprint in
                booleanArrayOf(false, true)) for (load in doubleArrayOf(0.0, 1.0)) for (lead in
                doubleArrayOf(.1, .3)) {
                time.fpsMultiplier = 60f / fps
                val dt = time.getRealworldSecondsSinceLastUpdate().toDouble()
                CartSteeringHooks.reset(player)
                player.animator = null
                player.actualX = 0f
                player.actualY = 0f
                player.inputX = .5f
                player.inputY = .5f
                player.moving = true
                input.setRunning(!sprint)
                input.sprinting = sprint
                CartSteeringHooks.input(player, input)
                player.run = !sprint
                player.sprint = sprint
                accept(player, CartSteeringHooks.movement(player, (.8 * dt).toFloat(), 0f))
                val state = states[player]
                val pace = field(state, "pace").get(state) as CartLegPace.Ramp
                pace.reset(.8)
                var elapsed = 0.0
                while (elapsed < lead) {
                    pace.update(.3, dt, load, true)
                    elapsed += dt
                }
                // A finalized native Walk node must retain the measured residual, without fast
                // input injection.
                field(state, "fastMoving").setBoolean(state, false)
                field(state, "sprintMomentum").setBoolean(state, true)
                field(state, "momentumSprint").setBoolean(state, sprint)
                field(state, "fastPace").setDouble(state, .8)
                field(state, "nativeSpeed").setDouble(state, pace.speed)
                field(state, "actualDistance").setDouble(state, pace.speed * dt)
                field(state, "load").setDouble(state, load)
                val speed = pace.speed
                releaseAfterNativeGaitReset(player, input)
                check(
                    player.woodBrake && player.brakeSprint == sprint,
                    "brief finalized Walk must select the residual fast stop: $fps/$sprint/$lead",
                )
                check(
                    Math.abs(field(state, "brakeLimit").getDouble(state) - speed) < 1e-7,
                    "braking must start from remaining speed, not the old fast speed",
                )
                val idle = brakeAnimation(player)
                player.moving = false
                CartSteeringHooks.heading(player)
                val duration = .65 + .35 * speed / .8
                check(
                    Math.abs(idle.getTransitionInTrack().getSpeedDelta() - 1 / duration) < 1e-6,
                    "lower residual speed must shorten the authored stop without restarting full-speed inertia",
                )
                val step = CartSteeringHooks.movement(player, 1f, 0f)
                check(
                    Math.abs(step.getLength() - speed * dt) < 1e-7,
                    "stop root cannot accelerate the remaining motion",
                )
                CartSteeringHooks.reset(player)
                check(
                    !player.brakeSprint && !player.woodBrake,
                    "reset must retire both stop selectors",
                )
            }
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = oldFps
        }
    }

    private fun residualBrakeEdges(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val dt = GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble()
        for (slowdown in floatArrayOf(0f, .5f, .9f)) {
            CartSteeringHooks.reset(player)
            player.slowFactor = slowdown
            player.inputX = .5f
            player.inputY = .5f
            player.moving = true
            input.setRunning(true)
            input.sprinting = false
            CartSteeringHooks.input(player, input)
            player.run = true
            var step = CartSteeringHooks.movement(player, (.8 * dt).toFloat(), 0f)
            step.scale(1 - slowdown)
            accept(player, step)
            releaseAfterNativeGaitReset(player, input)
            player.moving = false
            step = CartSteeringHooks.movement(player, 1f, 0f)
            step.scale(1 - slowdown)
            check(
                Math.abs(step.getLength() - .8 * dt * (1 - slowdown)) < 1e-7,
                "native slowdown must not be applied twice by the release cap: $slowdown",
            )
        }
        CartSteeringHooks.reset(player)
        player.slowFactor = 0f
        player.actualX = 0f
        player.actualY = 0f
        player.inputX = .5f
        player.inputY = .5f
        player.moving = true
        input.setRunning(true)
        CartSteeringHooks.input(player, input)
        player.run = true
        accept(player, CartSteeringHooks.movement(player, (.8 * dt).toFloat(), 0f))
        var state = states[player]
        val pace = field(state, "pace").get(state) as CartLegPace.Ramp
        pace.reset(.8)
        releaseAfterNativeGaitReset(player, input)
        player.moving = false
        brakeAnimation(player)
        CartSteeringHooks.heading(player)
        val clips = HashMap<String, AnimationClip>()
        for (name in arrayOf("Bob_Idle", "Bob_Walk", "Bob_Run")) {
            val start = Keyframe()
            val end = Keyframe()
            start.boneName = "Translation_Data"
            end.boneName = "Translation_Data"
            start.position = Vector3f()
            end.position = Vector3f(0f, 0f, if (name.equals("Bob_Idle")) 0f else -1f)
            end.time = 1f
            clips[name] = AnimationClip(1f, listOf(start, end), name, true)
        }
        val node = AnimNode()
        node.name = "ToolkitCartPivotRun"
        node.deferredBoneName = "Translation_Data"
        node.deferredBoneAxis = BoneAxis.Y
        for (xy in arrayOf(floatArrayOf(0f, 0f), floatArrayOf(0f, 1f), floatArrayOf(1f, 0f))) {
            val blend = Anim2DBlend()
            blend.animName = if (xy[0] == 0f && xy[1] == 0f) "Bob_Idle" else "Bob_Run"
            blend.posX = xy[0]
            blend.posY = xy[1]
            node.blends2d.add(blend)
        }
        val triangle = Anim2DBlendTriangle()
        triangle.node1 = node.blends2d[0]
        triangle.node2 = node.blends2d[1]
        triangle.node3 = node.blends2d[2]
        node.blendTris.add(triangle)
        node.blend2dPicker = Anim2DBlendPicker()
        node.blend2dPicker.SetPickTriangles(node.blendTris)
        val animator = player.animator ?: throw NullPointerException()
        animator.animSet = AnimationSet()
        val run = AnimState()
        run.nodes.add(node)
        animator.animSet.states["run"] = run
        val mesh = unsafe.allocateInstance(ModelMesh::class.java) as ModelMesh
        mesh.skinningData =
            SkinningData(clips, emptyList(), emptyList(), emptyList(), emptyList(), HashMap())
        val model = ModelManager::class.java.getDeclaredField("animModel")
        model.isAccessible = true
        val previous = model.get(ModelManager.instance)
        try {
            model.set(ModelManager.instance, mesh)
            pace.reset(.2)
            player.inputX = .5f
            player.inputY = .5f
            player.moving = true
            input.setRunning(true)
            CartSteeringHooks.input(player, input)
            player.run = true
            accept(player, CartSteeringHooks.movement(player, (.2 * dt).toFloat(), 0f))
            check(
                CartLegPace.targetSpeed(player, player.stepX, player.stepY).isFinite(),
                "Run resume must use calibrated native clips",
            )
            check(
                pace.speed > .2 && pace.speed < .5,
                "Run resume must accelerate from remaining stop speed through heading",
            )
            pace.reset(.8)
            var partial = CartSteeringHooks.movement(player, .04f, 0f)
            field(state, "cartBlocked").setBoolean(state, true)
            partial.scale(.5f)
            accept(player, partial)
            check(
                pace.speed > .75,
                "partial wall contact must preserve the moving gait rather than reset its pace every frame",
            )
            val contactStartX = player.actualX
            val contactStartY = player.actualY
            player.actualX = 10825.5f
            player.actualY = 10142.5f
            pace.reset(.8)
            partial = CartSteeringHooks.movement(player, .04f, 0f)
            field(state, "cartBlocked").setBoolean(state, true)
            partial.set(Math.ulp(player.actualX), 0f)
            accept(player, partial)
            check(
                pace.speed > .75,
                "one representable world-coordinate step is movement, not a hard collision stop",
            )
            player.actualX = contactStartX
            player.actualY = contactStartY
            val referenceSpeed = CartLegPace.targetSpeed(player, player.stepX, player.stepY)
            field(state, "wallHeading").setDouble(state, 0.0)
            field(state, "wallNormalY").setDouble(state, 1.0)
            field(state, "target").setDouble(state, Math.PI / 4)
            pace.reset(referenceSpeed * Math.sqrt(.5))
            for (frame in 0 until 4) {
                field(state, "hasInput").setBoolean(state, true)
                CartSteeringHooks.heading(player)
                check(
                    Math.abs(pace.speed - referenceSpeed * Math.sqrt(.5)) < 1e-6,
                    "wall guidance must remove inward speed through cadence exactly once",
                )
            }
            field(state, "wallHeading").setDouble(state, Double.NaN)
            field(state, "target").setDouble(state, 0.0)
            val walkNode = AnimNode()
            walkNode.name = CartLegPace.pivotName(cart.getFullType(), false, false)
            walkNode.deferredBoneName = node.deferredBoneName
            walkNode.deferredBoneAxis = node.deferredBoneAxis
            walkNode.blends2d.addAll(node.blends2d)
            walkNode.blendTris.addAll(node.blendTris)
            walkNode.blend2dPicker = node.blend2dPicker
            val movement = AnimState()
            movement.nodes.add(walkNode)
            animator.animSet.states["movement"] = movement
            val outgoing = AnimNode()
            outgoing.name = "ToolkitCartPivotSprint"
            outgoing.deferredBoneName = node.deferredBoneName
            outgoing.deferredBoneAxis = node.deferredBoneAxis
            val live = LiveAnimNode.alloc(animator.getRootLayer(), outgoing)
            val outgoingTrack = AnimationTrack.alloc()
            outgoingTrack.startClip(clips["Bob_Walk"], true, 0f)
            outgoingTrack.setBlendFieldWeight(1f)
            live.addMainTrack(outgoingTrack)
            animator.getRootLayer().getLiveAnimNodes().add(live)
            for (fast in booleanArrayOf(false, true)) {
                field(state, "brace").setDouble(state, 1.0)
                pace.reset(0.0)
                player.moving = false
                player.stepY = 0f
                val wheel = CartSteeringHooks.wheelPhase(player)
                input.setRunning(fast)
                CartSteeringHooks.input(player, input)
                player.run = fast
                CartSteeringHooks.heading(player)
                check(
                    player.stepY > 0 && player.stepY < .2 && pace.speed > 0,
                    "cleared obstruction must restore a native root budget even before accepted movement",
                )
                val visualSpeed = field(state, "visualSpeed").getFloat(state)
                check(
                    visualSpeed > 0 &&
                        visualSpeed < pace.speed &&
                        Math.abs(visualSpeed - outgoingTrack.getSpeedDelta()) < 1e-6,
                    "brace snapshot must retain the actual outgoing native track budget, not its unscaled ramp",
                )
                check(
                    CartSteeringHooks.wheelPhase(player) == wheel,
                    "query-only brace release must not spin the wheel",
                )
                var previousSpeed = pace.speed
                for (frame in 0 until 90) {
                    input.setRunning(fast)
                    CartSteeringHooks.input(player, input)
                    player.run = fast
                    player.moving = true
                    accept(
                        player,
                        CartSteeringHooks.movement(
                            player,
                            (pace.speed * player.stepY * dt).toFloat(),
                            0f,
                        ),
                    )
                    check(
                        pace.speed >= previousSpeed - 1e-7 && pace.speed - previousSpeed < .15,
                        "Walk/Run restart must retain its acceleration ramp when brace reaches zero: $fast",
                    )
                    previousSpeed = pace.speed
                }
                check(
                    field(state, "brace").getDouble(state) == 0.0 &&
                        Math.abs(player.stepY - (if (fast) 1.0 else .8)) < 1e-5,
                    "clear travel must leave bracing and recover a full stride",
                )
            }
            field(state, "sprintMomentum").setBoolean(state, false)
            player.run = false
            player.sprint = false
            outgoingTrack.setSpeedDelta(.37f)
            CartSteeringHooks.input(player, input)
            CartSteeringHooks.heading(player)
            check(
                field(state, "visualSpeed").getFloat(state) == -1f &&
                    outgoingTrack.getSpeedDelta() == .37f,
                "ordinary calibrated Walk must leave outgoing native cadence without a root override",
            )
            for (kind in
                arrayOf("SaucedCarts.ShoppingCart", "SaucedWheelbarrow.WheelbarrowMetal")) {
                type(cart, kind)
                CartSteeringHooks.heading(player)
                state = states[player]
                check(
                    field(state, "visualSpeed").getFloat(state) == -1f,
                    "legacy cart cadence must not publish a synthetic root budget: $kind",
                )
            }
        } finally {
            CartSteeringHooks.reset(player)
            model.set(ModelManager.instance, previous)
        }
    }

    private fun slalomClearance(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        CartSteeringHooks.input(player, IsoPlayer.InputState())
        val state = states[player]
        val bank = field(state, "bank").get(state)
        val pressure = Math.toRadians(7.0)
        val before = CartSteeringHooks.wheelPhase(player)
        field(bank, "pressure").setDouble(bank, pressure)
        check(
            CartSteeringHooks.lean(player) == 0.0 &&
                CartSteeringHooks.clearanceLean(player) == pressure,
            "neutral slalom bank must retain independent handle clearance",
        )
        val travel =
            CartSteeringMath.woodenAxle(pressure.toFloat(), 0f) -
                CartSteeringMath.woodenAxle(0f, 0f)
        check(
            Math.abs(CartSteeringHooks.wheelPhase(player) - CartWheelSpin.advance(before, travel)) <
                1e-6,
            "wheel roll must follow retained cart clearance through neutral bank",
        )
        field(state, "lean").setDouble(state, -pressure / 2)
        check(
            CartSteeringHooks.lean(player) < 0 &&
                CartSteeringHooks.clearanceLean(player) == pressure,
            "opposite bank must not change the retained pressure into a signed offset",
        )
        CartSteeringHooks.reset(player)
        check(CartSteeringHooks.clearanceLean(player) == 0.0, "reset must retire slalom clearance")
    }

    private fun brakeControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val time = GameTime.getInstance()
        val oldFps = time.fpsMultiplier
        try {
            for (fps in intArrayOf(30, 60, 144)) {
                time.fpsMultiplier = 60f / fps
                val dt = time.getRealworldSecondsSinceLastUpdate().toDouble()
                CartSteeringHooks.reset(player)
                type(cart, "SaucedWheelbarrow.WheelbarrowWood")
                player.actualX = 0f
                player.actualY = 0f
                player.inputX = .5f
                player.inputY = .5f
                player.moving = true
                player.run = false
                player.sprint = false
                input.sprinting = true
                CartSteeringHooks.input(player, input)
                player.sprint = true
                accept(player, CartSteeringHooks.movement(player, (.2 * dt).toFloat(), 0f))
                val phase = CartSteeringHooks.wheelPhase(player)
                releaseAfterNativeGaitReset(player, input)
                val state = states[player]
                check(
                    !player.run &&
                        !player.sprint &&
                        player.woodBrake &&
                        field(state, "braking").getBoolean(state),
                    "native input-reset ordering must arm wooden braking from the last finalized fast gait: $fps",
                )
                player.moving = false
                player.sprint = false
                for (tick in 0 until 3) {
                    val step = CartSteeringHooks.movement(player, .3f, 0f)
                    check(
                        Math.abs(step.getLength() - .2 * dt) < 1e-7 &&
                            step.x > 0 &&
                            Math.abs(step.y) < 1e-7,
                        "heavy stop must retain release speed cap without accelerating or compounding it: $fps/$tick",
                    )
                    accept(player, step)
                }
                check(
                    CartSteeringHooks.wheelPhase(player) < phase,
                    "accepted no-input coasting must spin the wooden wheel",
                )
                player.inputX = .5f
                player.inputY = .5f
                player.moving = true
                CartSteeringHooks.input(player, input)
                check(
                    !player.woodBrake && !field(state, "braking").getBoolean(state),
                    "new movement input must release the brake guard immediately",
                )
                val resumed = CartSteeringHooks.movement(player, .03f, 0f)
                check(
                    resumed.getLength() > .02,
                    "new input must release the previous stop movement cap",
                )
                accept(player, resumed)
                input.sprinting = true
                CartSteeringHooks.input(player, input)
                player.sprint = true
                accept(player, CartSteeringHooks.movement(player, .01f, 0f))
                releaseAfterNativeGaitReset(player, input)
                check(player.woodBrake, "second release must be eligible for an independent stop")
                var tick = 0
                while (tick < Math.ceil(.35 / dt)) {
                    CartSteeringHooks.heading(player)
                    tick++
                }
                check(
                    !player.woodBrake && !field(state, "braking").getBoolean(state),
                    "missing native stop clip must release the brake after its creation grace",
                )
                CartSteeringHooks.reset(player)
                check(
                    !player.woodBrake && !states.containsKey(player),
                    "reset must clear armed braking and its variable",
                )
            }
            time.fpsMultiplier = 1f
            for (event in
                arrayOf(
                    "resume",
                    "resume-full",
                    "blocked",
                    "replace",
                    "finish",
                    "reverse-rest-frame",
                )) {
                CartSteeringHooks.reset(player)
                player.animator = null
                type(cart, "SaucedWheelbarrow.WheelbarrowWood")
                player.primary = cart
                player.secondary = cart
                cart.setItemContainer(null)
                if (event.equals("resume-full")) {
                    val contents = ItemContainer()
                    contents.setType("floor")
                    contents.setCapacity(10)
                    val ballast =
                        unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
                    ballast.setModule("Base")
                    ballast.setType("Ballast")
                    ballast.setName("Ballast")
                    ballast.setActualWeight(10f)
                    contents.getItems().add(ballast)
                    cart.setItemContainer(contents)
                }
                player.actualX = 0f
                player.actualY = 0f
                player.inputX = .5f
                player.inputY = .5f
                player.moving = true
                player.run = false
                player.sprint = false
                input.sprinting = true
                CartSteeringHooks.input(player, input)
                player.sprint = true
                accept(player, CartSteeringHooks.movement(player, .01f, 0f))
                val state = states[player]
                val pace = field(state, "pace").get(state) as CartLegPace.Ramp
                pace.reset(.4)
                val idle = brakeAnimation(player)
                val stop = idle.getTransitionInTrack()
                releaseAfterNativeGaitReset(player, input)
                player.sprint = false
                player.moving = false
                for (tick in 0 until 40) CartSteeringHooks.heading(player)
                check(
                    player.woodBrake && CartSteeringHooks.fastPoseWeight(player) == 1f,
                    "live native stop must retain grip clearance beyond the old .4s tail",
                )
                check(
                    Math.abs(
                        stop.getSpeedDelta() - (if (event.equals("resume-full")) 1 / 1.12 else 1.0),
                    ) < 1e-6,
                    "full cargo must settle 12 percent longer while retaining the authored stop sequence",
                )
                if (event.startsWith("resume")) {
                    accept(player, CartSteeringHooks.movement(player, .005f, 0f))
                    check(
                        Math.abs(pace.speed - .2) < 1e-6,
                        "coasting root must seed resumed Sprint pace instead of resetting it to zero",
                    )
                    val phase = stop.getCurrentTimeValue()
                    val cadence = stop.getSpeedDelta()
                    player.inputX = .5f
                    player.inputY = .5f
                    player.moving = true
                    CartSteeringHooks.input(player, input)
                    check(
                        idle.getTransitionInTrack() === stop && stop.getUseDeferredMovement(),
                        "resume must retain native stop root and pose throughout its visual fade",
                    )
                    check(
                        stop.getCurrentTimeValue() == phase && stop.getSpeedDelta() == cadence,
                        "resume must retain the authored stop phase and cadence",
                    )
                    val capped = CartSteeringHooks.movement(player, .05f, 0f)
                    check(
                        Math.abs(capped.getLength() - .01) < 1e-7,
                        "native visual fade must retain the release-speed cap after braking ends",
                    )
                    accept(player, capped)
                    idle.stopTransitionIn()
                    val released = CartSteeringHooks.movement(player, .05f, 0f)
                    check(
                        released.getLength() > .04,
                        "completed native fade must release the old brake cap",
                    )
                    accept(player, released)
                } else if (event.equals("blocked")) {
                    CartSteeringHooks.movement(player, .05f, 0f)
                    CartSteeringHooks.heading(player)
                    check(
                        !stop.getUseDeferredMovement(),
                        "blocked collision must disable stop root without replaying its budget",
                    )
                } else if (event.equals("replace")) {
                    val replacement =
                        unsafe.allocateInstance(InventoryContainer::class.java)
                            as InventoryContainer
                    type(replacement, "SaucedWheelbarrow.WheelbarrowMetal")
                    replacement.setContainer(player.inventory)
                    player.primary = replacement
                    player.secondary = replacement
                    CartSteeringHooks.input(player, input)
                    check(
                        idle.getTransitionInTrack() == null,
                        "wood-to-metal identity change must hard-clean the old native stop",
                    )
                } else if (event.equals("finish")) {
                    idle.stopTransitionIn()
                    CartSteeringHooks.heading(player)
                    check(
                        !field(states[player], "braking").getBoolean(states[player]),
                        "a completed native transition must release the cart brake state",
                    )
                } else {
                    pace.reset(0.0)
                    field(state, "actualDistance").setDouble(state, 0.0)
                    player.inputX = -.5f
                    player.inputY = -.5f
                    player.moving = true
                    input.setRunning(true)
                    input.sprinting = true
                    CartSteeringHooks.input(player, input)
                    val reversal = field(state, "reversal").get(state) as CartSteeringMath.Reversal
                    check(
                        reversal.active &&
                            reversal.braking &&
                            reversal.direction == 1 &&
                            reversal.requested == -1,
                        "zero root frame inside a live stop must not bypass the reversal neutral phase",
                    )
                    check(
                        !input.isRunning() && !input.sprinting,
                        "rest-frame reverse must still clamp fast input",
                    )
                    val forward = CartSteeringHooks.movement(player, .05f, 0f)
                    check(
                        forward.x > 0 && Math.abs(forward.y) < 1e-7,
                        "remaining stop root must keep the old forward direction until reversal actually settles",
                    )
                    accept(player, forward)
                }
                check(
                    !player.woodBrake,
                    "stop cancellation must clear the XML selection guard: $event",
                )
                CartSteeringHooks.reset(player)
                check(
                    idle.getTransitionInTrack() == null,
                    "reset must hard-clean any visual stop tail",
                )
                player.primary = cart
                player.secondary = cart
                player.animator = null
            }
            cart.setItemContainer(null)
            for (entry in
                arrayOf(
                    arrayOf("SaucedWheelbarrow.WheelbarrowWood", "walk"),
                    arrayOf("SaucedWheelbarrow.WheelbarrowWood", "run"),
                    arrayOf("SaucedWheelbarrow.WheelbarrowMetal", "sprint"),
                    arrayOf("SaucedCarts.ShoppingCart", "sprint"),
                )) {
                val kind = entry[0]
                val gait = entry[1]
                type(cart, kind)
                player.inputX = .5f
                player.inputY = .5f
                player.moving = true
                player.run = false
                player.sprint = false
                input.setRunning(gait.equals("run"))
                input.sprinting = gait.equals("sprint")
                CartSteeringHooks.input(player, input)
                player.run = gait.equals("run")
                player.sprint = gait.equals("sprint")
                accept(player, CartSteeringHooks.movement(player, .02f, 0f))
                releaseAfterNativeGaitReset(player, input)
                check(
                    player.woodBrake ==
                        (kind.startsWith("SaucedWheelbarrow.") && !gait.equals("walk")),
                    "only finalized fast wheelbarrow movement can arm a stop after the native flags reset: $kind/$gait",
                )
                CartSteeringHooks.reset(player)
            }
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = oldFps
        }
    }

    private fun pathControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.walkSpeed = .8f
        val nativePath = zombie.pathfind.PathFindBehavior2(player)
        player.nativePath = nativePath
        val finder = zombie.ai.astar.AStarPathFinderResult()
        player.finder = finder
        val input = IsoPlayer.InputState()
        CartSteeringHooks.heading(player)
        val manual = states[player]
        check(
            field(manual, "visualSpeed").getFloat(manual) == -1f,
            "missing native clips must leave cadence without a root override",
        )
        field(manual, "braking").setBoolean(manual, true)
        field(manual, "stationaryRoot").setBoolean(manual, true)
        player.brace = true
        val reversal = field(manual, "reversal").get(manual) as CartSteeringMath.Reversal
        reversal.request(-1, false)
        player.pathActive = true
        player.inputX = -.5f
        player.inputY = .5f
        input.setRunning(true)
        input.sprinting = true
        CartSteeringHooks.input(player, input)
        val path = states[player]
        check(
            path !== manual &&
                field(path, "path").getBoolean(path) &&
                !field(path, "braking").getBoolean(path) &&
                !field(path, "stationaryRoot").getBoolean(path),
            "native path must discard manual brake, stationary turn and reversal state",
        )
        check(!player.brace, "native path handoff retained a manual effort stance")
        check(
            input.isRunning() && input.sprinting && !field(path, "hasInput").getBoolean(path),
            "path mode must leave native gait untouched and ignore keyboard steering",
        )
        player.moving = true
        field(path, "visualSpeed").setFloat(path, .7f)
        var step = CartSteeringHooks.movement(player, .02f, 0f)
        check(
            step.x > .019 && Math.abs(step.y) < 1e-6,
            "native path delta must own intent despite opposing keyboard input",
        )
        accept(player, step)
        val before = field(path, "heading").getDouble(path)
        step = CartSteeringHooks.movement(player, 0f, .02f)
        check(
            step.x == 0f && step.y == .02f,
            "native path must preserve its exact world delta instead of creating a pursuit arc",
        )
        accept(player, step)
        check(
            field(path, "heading").getDouble(path) == before &&
                !player.pivot &&
                player.legPace == 0f,
            "path following must retain native yaw/cadence and leave manual pivot variables released",
        )
        check(
            field(path, "visualSpeed").getFloat(path) == -1f,
            "native path must release the prior root override",
        )
        for (gx in doubleArrayOf(-2.0, 0.0, 2.0)) for (gy in doubleArrayOf(-2.0, 0.0, 2.0)) {
            player.actualX = 0f
            player.actualY = 0f
            var tick = 0
            while (tick < 500 && Math.hypot(gx - player.actualX, gy - player.actualY) > .01) {
                val dx = gx - player.actualX
                val dy = gy - player.actualY
                val distance = Math.hypot(dx, dy)
                val budget = Math.min(.02, distance)
                step =
                    CartSteeringHooks.movement(
                        player,
                        (dx / distance * budget).toFloat(),
                        (dy / distance * budget).toFloat(),
                    )
                accept(player, step)
                tick++
            }
            check(
                Math.hypot(gx - player.actualX, gy - player.actualY) < .01,
                "native route endpoint convergence must survive every open-space target direction: $gx/$gy",
            )
        }
        CartSteeringHooks.beginPath(player)
        field(path, "cartBlocked").setBoolean(path, true)
        check(
            CartSteeringHooks.pathResult(
                player,
                zombie.pathfind.PathFindBehavior2.BehaviorResult.Succeeded,
            ) === zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed,
            "native same-call success must not bypass a cart-blocked step",
        )
        check(
            finder.progress === zombie.ai.astar.AStarPathFinder.PathFindProgress.failed,
            "cart obstruction must reach native Failed, not silently cancel a waiting queue",
        )
        CartSteeringHooks.beginPath(player)
        check(
            CartSteeringHooks.pathResult(
                player,
                zombie.pathfind.PathFindBehavior2.BehaviorResult.Working,
            ) === zombie.pathfind.PathFindBehavior2.BehaviorResult.Working,
            "new native update must release old per-call obstruction",
        )
        type(cart, "SaucedWheelbarrow.WheelbarrowMetal")
        check(CartSteeringHooks.enabled(player), "metal native path lost wheelbarrow clearance")
        for (kind in arrayOf("SaucedCarts.ShoppingCart")) {
            type(cart, kind)
            check(
                !CartSteeringHooks.enabled(player),
                "other carts must retain native path behavior: $kind",
            )
        }
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.npc = true
        check(!CartSteeringHooks.enabled(player), "NPC movement must remain native")
        player.npc = false
        player.blocked = 8
        check(!CartSteeringHooks.enabled(player), "remote path must remain native")
        player.blocked = 0
        player.pathActive = false
        nativePath.cancel()
        field(path, "pending").setBoolean(path, true)
        CartSteeringHooks.input(player, input)
        check(
            states[player] === path,
            "same-call path stop must retain its last pending collision acceptance",
        )
        CartSteeringHooks.heading(player)
        CartSteeringHooks.input(player, input)
        check(
            states[player] !== path && !field(states[player], "path").getBoolean(states[player]),
            "path cancellation must discard native target and restore fresh manual input ownership",
        )
        CartSteeringHooks.reset(player)
    }

    private fun wovenPathControls(unsafe: Unsafe, states: Map<*, *>) {
        Main.main(emptyArray())
        check(
            Main.CART_SUPPORTED,
            "woven path regression requires the supported native fingerprint",
        )
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            CartSteeringHooksTest::class.java.classLoader,
        )
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.walkSpeed = .8f
        player.pathActive = true
        val nativePath = zombie.pathfind.PathFindBehavior2(player)
        player.nativePath = nativePath
        val finder = zombie.ai.astar.AStarPathFinderResult()
        player.finder = finder
        finder.progress = zombie.ai.astar.AStarPathFinder.PathFindProgress.failed
        check(
            nativePath.update() === zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed,
            "real woven update() must reach both public path advice hooks without an access error",
        )
        val state = states[player]
        check(
            state != null && field(state, "path").getBoolean(state),
            "real woven path entry must acquire the local wooden cart state",
        )
        field(state, "cartBlocked").setBoolean(state, true)
        check(
            nativePath.update(1f) === zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed &&
                !field(state, "cartBlocked").getBoolean(state),
            "real woven update(float) must reset per-call obstruction and preserve native failure",
        )
        CartSteeringHooks.reset(player)
        player.blocked = 8
        check(
            nativePath.update() === zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed &&
                nativePath.update(1f) === zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed &&
                !states.containsKey(player),
            "woven path advice must leave remote native failure/state untouched",
        )
    }

    private fun wovenProtectedControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.walkSpeed = .8f
        player.reqMovement = Vector2()
        CartWheelSpin.record(cart, 0f, 0f, 0f, org.joml.Matrix4f().scale(76.5f), .7)
        val heading =
            zombie.characters.IsoGameCharacter::class.java.getDeclaredMethod("postUpdateAnimating")
        heading.isAccessible = true
        heading.invoke(player)
        val previous = states[player]
        check(
            previous != null && player.pivot,
            "woven heading must acquire the held cart before impact",
        )
        field(previous, "brace").setDouble(previous, 1.0)
        player.stepX = .5f
        player.stepY = .5f
        player.legPace = 1f
        player.woodBrake = true
        player.brakeSprint = true
        val current = field(player.getStateMachine(), "currentState")
        player.animationUpdate = Runnable {
            try {
                current.set(
                    player.getStateMachine(),
                    zombie.ai.states.CollideWithWallState.instance(),
                )
            } catch (error: IllegalAccessException) {
                throw AssertionError(error)
            }
        }
        heading.invoke(player)
        player.animationUpdate = null
        check(
            !states.containsKey(player) &&
                !player.pivot &&
                player.stepX == 0f &&
                player.stepY == 0f &&
                player.legPace == 0f &&
                !player.woodBrake &&
                !player.brakeSprint,
            "woven exit must clear cart variables when native animation enters collision after the entry hook",
        )
        for (state in
            listOf(
                zombie.ai.states.CollideWithWallState.instance(),
                zombie.ai.states.PlayerGetUpState.instance(),
            )) {
            current.set(player.getStateMachine(), state)
            check(
                !CartSteeringHooks.enabled(player),
                "native collision/getup states must retain animation ownership",
            )
            check(
                !player.hasHitReaction() &&
                    !player.isKnockedDown() &&
                    !player.isRagdollSimulationActive(),
                "collision/getup regression must exercise the explicit native state guards",
            )
            player.setNextX(0f)
            player.setNextY(0f)
            player.moveUnmodded(.02f, -.01f)
            check(
                player.reqMovement.x == .02f &&
                    player.reqMovement.y == -.01f &&
                    player.getNextX() == .02f &&
                    player.getNextY() == -.01f,
                "woven movement must preserve the native collision/getup root vector",
            )
            heading.invoke(player)
            check(
                !states.containsKey(player) &&
                    !player.pivot &&
                    player.stepX == 0f &&
                    player.stepY == 0f &&
                    player.legPace == 0f &&
                    !player.woodBrake &&
                    !player.brakeSprint,
                "woven heading must release cart steering and brake variables during native recovery",
            )
            check(
                CartSteeringHooks.wheelPhase(player).isNaN(),
                "native recovery must suspend held wheel preparation",
            )
        }
        current.set(player.getStateMachine(), null)
        heading.invoke(player)
        val resumed = states[player]
        check(
            CartSteeringHooks.enabled(player) &&
                resumed != null &&
                resumed !== previous &&
                player.pivot &&
                field(resumed, "brace").getDouble(resumed) == 0.0 &&
                !field(resumed, "pending").getBoolean(resumed),
            "native recovery exit must acquire fresh steering without the old brace or pending step",
        )
        check(
            Math.abs(CartSteeringHooks.wheelPhase(player) - .7) < 1e-6,
            "native recovery must retain the same cart item's recorded wheel phase",
        )
        CartSteeringHooks.finish(player)
        check(
            states[player] === resumed,
            "eligible frame exit must preserve the existing cart state",
        )
        CartSteeringHooks.reset(player)
        player.stepX = .25f
        CartSteeringHooks.finish(player)
        check(
            player.stepX == .25f && !states.containsKey(player),
            "unowned frame exit must not clear presentation variables",
        )
    }

    private fun direction(player: Player, heading: Double) {
        player.inputX = ((Math.cos(heading) - Math.sin(heading)) / 2).toFloat()
        player.inputY = ((Math.cos(heading) + Math.sin(heading)) / 2).toFloat()
    }

    private fun keyboardControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        player.keyboard = true
        val keys = Keys()
        player.keys = keys
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val time = GameTime.getInstance()
        val old = time.fpsMultiplier
        try {
            time.fpsMultiplier = 1f
            for (kind in
                arrayOf(
                    "SaucedCarts.ShoppingCart",
                    "SaucedWheelbarrow.WheelbarrowWood",
                    "SaucedWheelbarrow.WheelbarrowMetal",
                )) {
                type(cart, kind)
                for (initial in doubleArrayOf(0.0, .7, -2.4)) for (travel in
                    intArrayOf(-1, 0, 1)) for (sign in intArrayOf(-1, 0, 1)) {
                    CartSteeringHooks.reset(player)
                    player.actualX = 0f
                    player.actualY = 0f
                    player.moving = false
                    keys.set(travel, sign)
                    CartSteeringHooks.heading(player)
                    val state = states[player]
                    field(state, "heading").setDouble(state, initial)
                    val move = CartSteeringHooks.keyboardMovement(player, Vector2(0f, -1.95f))!!
                    if (travel == 0 && sign == 0) {
                        check(
                            move.getLengthSquared() == 0f,
                            "idle keyboard has no native movement intent",
                        )
                        continue
                    }
                    val desired = CartSteeringMath.keyboardTarget(initial, travel, sign)
                    check(
                        Math.abs(
                            CartSteeringMath.wrap(
                                Math.atan2(
                                    (move.y - move.x).toDouble(),
                                    (move.y + move.x).toDouble(),
                                ) - desired,
                            ),
                        ) < 1e-6,
                        "native movement must follow relative keyboard intent: $kind/$travel/$sign",
                    )
                    check(
                        Math.abs(move.getLength() - 1.95) < 1e-6,
                        "relative keys retain the native input magnitude",
                    )
                    input.setRunning(true)
                    input.sprinting = true
                    CartSteeringHooks.input(player, input)
                    if (travel <= 0)
                        check(
                            !input.isRunning() && !input.sprinting,
                            "reverse and pivot must use walking: $kind",
                        )
                    player.moving = true
                    CartSteeringHooks.heading(player)
                    CartSteeringHooks.movement(player, .02f, 0f)
                    CartSteeringHooks.heading(player)
                    check(
                        field(state, "heading").getDouble(state) == initial,
                        "native refused keyboard movement must not rotate the cart",
                    )
                    var turned = 0.0
                    repeat(360) {
                        CartSteeringHooks.input(player, input)
                        val before = field(state, "heading").getDouble(state)
                        val step = CartSteeringHooks.movement(player, .02f, 0f)
                        check(
                            step.getLength() <= .020001,
                            "keyboard cannot invent a native stride budget",
                        )
                        if (travel != 0) {
                            val forward = step.x * Math.cos(before) + step.y * Math.sin(before)
                            check(
                                forward * travel > 0,
                                "forward/reverse travel sign must remain explicit: $kind/$travel/$sign",
                            )
                        }
                        accept(player, step)
                        turned +=
                            CartSteeringMath.wrap(field(state, "heading").getDouble(state) - before)
                    }
                    val yaw = sign * if (travel < 0) -1 else 1
                    check(
                        if (sign == 0) Math.abs(turned) < 1e-5 else turned * yaw > Math.PI,
                        "held steering must keep turning beyond a fixed world direction: $kind/$travel/$sign/$turned",
                    )
                    keys.set(travel, 0)
                    CartSteeringHooks.input(player, input)
                    if (travel == 0) player.moving = false
                    val before = field(state, "heading").getDouble(state)
                    accept(player, CartSteeringHooks.movement(player, .02f, 0f))
                    val after = field(state, "heading").getDouble(state)
                    check(
                        Math.abs(CartSteeringMath.wrap(after - before)) < .03,
                        "steering release must settle without a world-direction snap",
                    )
                    if (travel == 0)
                        check(
                            player.stepX == 0f && player.stepY == 0f,
                            "released pivot must return to idle",
                        )
                }
                keys.forward = true
                keys.backward = true
                keys.left = true
                keys.right = true
                check(
                    CartSteeringHooks.keyboardMovement(player, Vector2(0f, -1.95f))!!
                        .getLengthSquared() == 0f,
                    "opposite keys cancel instead of inheriting native key priority",
                )
                CartSteeringHooks.input(player, input)
                check(
                    !field(states[player], "wantsMove").getBoolean(states[player]),
                    "opposite keys release cart intent",
                )
                keys.set(1, 1)
                for (gate in
                    arrayOf("controller", "aim", "autowalk", "path", "remote", "disabled")) {
                    player.keyboard = gate != "controller"
                    player.aim = gate == "aim"
                    player.pathActive = gate == "path"
                    player.autoWalk = gate == "autowalk"
                    player.blocked = if (gate == "remote") 8 else if (gate == "disabled") 10 else 0
                    val original = Vector2(.3f, -.4f)
                    check(
                        CartSteeringHooks.keyboardMovement(player, original) === original &&
                            original.x == .3f &&
                            original.y == -.4f,
                        "relative keyboard must leave native input untouched: $gate",
                    )
                }
                player.keyboard = true
                player.aim = false
                player.autoWalk = false
                player.pathActive = false
                player.blocked = 0
            }
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = old
        }
    }

    private fun keyboardReleaseControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.keyboard = true
        val keys = Keys()
        player.keys = keys
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val time = GameTime.getInstance()
        val old = time.fpsMultiplier
        try {
            for (fps in intArrayOf(30, 60, 144)) for (travel in intArrayOf(-1, 0, 1)) for (sign in
                intArrayOf(-1, 1)) for (opposite in booleanArrayOf(false, true)) {
                time.fpsMultiplier = 60f / fps
                CartSteeringHooks.reset(player)
                player.actualX = 0f
                player.actualY = 0f
                player.moving = true
                keys.set(travel, sign)
                CartSteeringHooks.input(player, input)
                val state = states[player]
                // Native animation may plan several frames between fresh input callbacks.
                repeat(fps) { accept(player, CartSteeringHooks.movement(player, .02f, 0f)) }
                val before = field(state, "heading").getDouble(state)
                val lean = CartSteeringHooks.lean(player)
                check(
                    Math.abs(before) > .1,
                    "held relative steering must survive sparse native input updates",
                )
                keys.set(travel, 0)
                if (opposite) {
                    keys.left = true
                    keys.right = true
                }
                repeat(fps / 2) { frame ->
                    accept(player, CartSteeringHooks.movement(player, .02f, 0f))
                    check(
                        Math.abs(
                            CartSteeringMath.wrap(
                                field(state, "heading").getDouble(state) - before,
                            ),
                        ) < 1e-5,
                        "released/cancelled relative steering retained accepted yaw: $fps/$travel/$sign/$opposite",
                    )
                    if (frame == 0 && travel != 0 && Math.abs(lean) > 1e-6)
                        check(
                            Math.abs(CartSteeringHooks.lean(player)) > 0 &&
                                Math.abs(CartSteeringHooks.lean(player)) < Math.abs(lean),
                            "keyboard yaw release must preserve the smooth bank return",
                        )
                }
            }
            CartSteeringHooks.reset(player)
            player.keyboard = false
            player.inputX = .5f
            player.inputY = .5f
            CartSteeringHooks.input(player, input)
            val state = states[player]
            field(state, "turnRate").setDouble(state, 1.0)
            field(state, "target").setDouble(state, -.01)
            CartSteeringHooks.movement(player, .02f, 0f)
            val requested = field(state, "requested").get(state) as CartSteeringMath.Step
            check(
                requested.turn() > 0,
                "absolute/gamepad steering must retain its existing angular smoothing",
            )
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = old
        }
    }

    private fun keyboardWorldReleaseControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.keyboard = true
        val keys = Keys()
        player.keys = keys
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val time = GameTime.getInstance()
        val old = time.fpsMultiplier
        try {
            time.fpsMultiplier = 1f
            for (origin in floatArrayOf(8192f, 10825.5f, 16384f)) for (initial in
                doubleArrayOf(-.7, .7, -1.3, 1.3)) for (budget in
                floatArrayOf(.002f, .005f, .02f)) {
                CartSteeringHooks.reset(player)
                player.actualX = origin
                player.actualY = origin
                player.moving = true
                keys.set(-1, 1)
                CartSteeringHooks.input(player, input)
                val state = states[player]
                field(state, "heading").setDouble(state, initial)
                field(state, "turnRate").setDouble(state, -1.0)
                // Release steering between input callbacks, retaining deliberate reverse travel.
                keys.set(-1, 0)
                repeat(240) { frame ->
                    val step = CartSteeringHooks.movement(player, budget, 0f)
                    check(
                        step.getLength() <= budget + 1e-7,
                        "released reverse cannot invent a native stride budget",
                    )
                    accept(player, step)
                    val drift =
                        Math.abs(
                            CartSteeringMath.wrap(
                                field(state, "heading").getDouble(state) - initial,
                            ),
                        )
                    check(
                        drift <= .025,
                        "released reverse must retain yaw at native world precision: $origin/$initial/$budget/$frame drift=$drift",
                    )
                }
                check(
                    Math.hypot(
                        (player.actualX - origin).toDouble(),
                        (player.actualY - origin).toDouble(),
                    ) > budget * 100,
                    "yaw stability must preserve deliberate reverse progress",
                )
            }
            // Collision-displaced analog movement retains its existing rolling-yaw contract.
            for (gate in arrayOf("controller", "aim", "autowalk")) {
                CartSteeringHooks.reset(player)
                player.keyboard = gate != "controller"
                player.aim = gate == "aim"
                player.autoWalk = gate == "autowalk"
                player.actualX = 10825.5f
                player.actualY = 10825.5f
                player.moving = true
                keys.set(-1, 0)
                CartSteeringHooks.heading(player)
                val state = states[player]
                val initial = .7
                field(state, "heading").setDouble(state, initial)
                direction(player, initial)
                CartSteeringHooks.input(player, input)
                val axle =
                    CartSteeringMath.woodenAxle(
                        CartSteeringHooks.clearanceLean(player).toFloat(),
                        CartLegPace.woodenGaitShift(player),
                    )
                CartSteeringHooks.movement(player, .02f, 0f)
                val x = player.actualX
                val y = player.actualY
                player.actualX += .015f
                player.actualY += .003f
                val expected =
                    CartSteeringMath.acceptedTurn(
                        initial,
                        axle,
                        (player.actualX - x).toDouble(),
                        (player.actualY - y).toDouble(),
                    )
                CartSteeringHooks.heading(player)
                check(
                    Math.abs(
                        CartSteeringMath.wrap(field(state, "heading").getDouble(state) - initial) -
                            expected,
                    ) < 1e-9,
                    "relative release correction must retain native collision yaw for $gate",
                )
            }
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = old
        }
    }

    private fun shoppingRearAxleControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedCarts.ShoppingCart")
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val keys = Keys()
        player.keys = keys
        val time = GameTime.getInstance()
        val old = time.fpsMultiplier
        try {
            time.fpsMultiplier = 1f
            for (scale in floatArrayOf(.6f, 1f, 1.7f)) for (sign in intArrayOf(-1, 1)) {
                cart.worldScale = scale
                player.keyboard = true
                keys.set(0, sign)
                CartSteeringHooks.reset(player)
                player.actualX = 0f
                player.actualY = 0f
                player.moving = false
                CartSteeringHooks.heading(player)
                val state = states[player]
                val axle = CartShopping.axle(scale)
                direction(player, sign * Math.PI / 2)
                CartSteeringHooks.input(player, input)
                player.moving = true
                CartSteeringHooks.heading(player)
                check(
                    sign * player.stepX < 0 && player.stepY == 0f,
                    "shopping handle steps opposite the stationary yaw",
                )
                CartSteeringHooks.movement(player, .02f, 0f)
                CartSteeringHooks.heading(player)
                check(
                    field(state, "heading").getDouble(state) == 0.0,
                    "blocked shopping turn cannot rotate",
                )
                repeat(30) {
                    CartSteeringHooks.input(player, input)
                    accept(player, CartSteeringHooks.movement(player, .02f, 0f))
                    val h = field(state, "heading").getDouble(state)
                    check(
                        Math.hypot(
                            player.actualX + axle * Math.cos(h) - axle,
                            player.actualY + axle * Math.sin(h),
                        ) < 1e-5,
                        "shopping stationary turn must hold the rear axle, not a virtual front pivot",
                    )
                }
                check(
                    sign * field(state, "heading").getDouble(state) > .1,
                    "shopping stationary turn must make progress",
                )
                player.keyboard = false
                for (reverse in booleanArrayOf(false, true)) {
                    CartSteeringHooks.reset(player)
                    player.actualX = 0f
                    player.actualY = 0f
                    player.moving = true
                    CartSteeringHooks.heading(player)
                    direction(player, (if (reverse) Math.PI else 0.0) + sign * .3)
                    CartSteeringHooks.input(player, input)
                    val movement = CartSteeringHooks.movement(player, .02f, 0f)
                    check(movement.getLength() <= .020001f, "shopping steering cannot add speed")
                    accept(player, movement)
                    val h = field(states[player], "heading").getDouble(states[player])
                    val dx = player.actualX + axle * (Math.cos(h) - 1)
                    val dy = player.actualY + axle * Math.sin(h)
                    check(
                        Math.abs(-dx * Math.sin(h / 2) + dy * Math.cos(h / 2)) < 1e-6,
                        "shopping moving/reverse rear axle must roll without lateral travel",
                    )
                }
            }
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = old
        }
    }

    private fun stationaryControls(unsafe: Unsafe, states: Map<*, *>) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.walkSpeed = .8f
        val input = IsoPlayer.InputState()
        val time = GameTime.getInstance()
        val old = time.fpsMultiplier
        try {
            for (fps in intArrayOf(30, 60, 144)) for (sign in intArrayOf(-1, 1)) {
                time.fpsMultiplier = 60f / fps
                CartSteeringHooks.reset(player)
                player.moving = false
                player.inputX = 0f
                player.inputY = 0f
                player.actualX = 0f
                player.actualY = 0f
                CartSteeringHooks.heading(player)
                val state = states[player]
                direction(player, sign * Math.PI / 2)
                input.setRunning(true)
                input.sprinting = true
                CartSteeringHooks.input(player, input)
                check(
                    field(state, "stationary").getBoolean(state) &&
                        !input.isRunning() &&
                        !input.sprinting,
                    "side input from rest must select walking-only stationary turn",
                )
                player.moving = true
                CartSteeringHooks.heading(player)
                check(
                    sign * player.stepX < 0 && player.stepY == 0f,
                    "stationary bootstrap must select a native pure lateral step",
                )
                // Native collision refuses a whole step: yaw and wheel phase must remain unchanged.
                CartSteeringHooks.movement(player, .02f, 0f)
                CartSteeringHooks.heading(player)
                check(
                    field(state, "heading").getDouble(state) == 0.0 &&
                        CartSteeringHooks.wheelPhase(player) == 0.0,
                    "blocked stationary movement cannot rotate or spin the cart",
                )
                var frame = 0
                while (frame < fps * 4 && field(state, "stationary").getBoolean(state)) {
                    CartSteeringHooks.input(player, input)
                    accept(player, CartSteeringHooks.movement(player, (1.1 / fps).toFloat(), 0f))
                    val h = field(state, "heading").getDouble(state)
                    check(
                        Math.hypot(
                            player.actualX + 1.0084944326 * Math.cos(h) - 1.0084944326,
                            player.actualY + 1.0084944326 * Math.sin(h),
                        ) < 1e-5,
                        "accepted stationary steps must orbit the front axle",
                    )
                    frame++
                }
                check(
                    !field(state, "stationary").getBoolean(state),
                    "held side input must complete the turn",
                )
                check(
                    Math.abs(
                        CartSteeringMath.wrap(
                            field(state, "heading").getDouble(state) - sign * Math.PI / 2,
                        ),
                    ) < Math.toRadians(.5),
                    "stationary exit must face the requested direction",
                )
                input.setRunning(true)
                input.sprinting = true
                CartSteeringHooks.input(player, input)
                check(
                    input.isRunning() && input.sprinting,
                    "aligned exit must release native fast-gait input",
                )
                val forward = CartSteeringHooks.movement(player, .02f, 0f)
                check(
                    Math.hypot(forward.x.toDouble(), forward.y.toDouble()) > .019,
                    "held input must resume rolling after the pivot",
                )
                accept(player, forward)
                // A new side input while already moving remains the existing rolling arc.
                direction(player, 0.0)
                CartSteeringHooks.input(player, input)
                check(
                    !field(state, "stationary").getBoolean(state),
                    "moving turns must not park the wheel",
                )
                CartSteeringHooks.reset(player)
                player.moving = false
                direction(player, sign * Math.PI / 2)
                CartSteeringHooks.input(player, input)
                player.moving = true
                CartSteeringHooks.heading(player)
                accept(player, CartSteeringHooks.movement(player, .02f, 0f))
                player.inputX = 0f
                player.inputY = 0f
                CartSteeringHooks.input(player, input)
                player.moving = false
                val before = field(states[player], "heading").getDouble(states[player])
                val tail = CartSteeringHooks.movement(player, .02f, 0f)
                check(
                    tail.getLength() == 0f,
                    "released strafe root must not become an unwanted forward step",
                )
                accept(player, tail)
                check(
                    field(states[player], "heading").getDouble(states[player]) == before &&
                        player.stepX == 0f &&
                        player.stepY == 0f,
                    "released stationary turn must return to planted idle",
                )
                direction(player, before + Math.PI)
                CartSteeringHooks.input(player, input)
                val reverse = CartSteeringHooks.movement(player, .02f, 0f)
                check(
                    reverse.x * Math.cos(before) + reverse.y * Math.sin(before) < -.019,
                    "backward input after release must preserve existing reverse travel",
                )
                accept(player, reverse)
            }
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = old
        }
    }

    private fun nativeBudget(
        player: Player,
        node: AnimNode,
        clips: Map<String, AnimationClip>,
        dt: Double,
    ): Double {
        val pick =
            node.blend2dPicker.Pick(player.stepX, player.stepY, Anim2DBlendPicker.PickResults())
        var rootX = 0.0
        var rootY = 0.0
        for (i in 0 until pick.numNodes) {
            val blend = if (i == 0) pick.node1 else if (i == 1) pick.node2 else pick.node3
            val weight = if (i == 0) pick.scale1 else if (i == 1) pick.scale2 else pick.scale3
            if (weight < 1e-4f) continue
            val clip = clips[blend.animName]!!
            val root = clip.getTotalTranslation("Translation_Data", BoneAxis.Y, Vector2())
            rootX += (Math.min(1f, weight) * root.x / clip.getDuration()).toDouble()
            rootY += (Math.min(1f, weight) * root.y / clip.getDuration()).toDouble()
        }
        return player.legPace * Math.hypot(rootX, rootY) * dt
    }

    private fun forwardWalkBudget(
        player: Player,
        states: Map<*, *>,
        node: AnimNode,
        clips: Map<String, AnimationClip>,
    ) {
        player.walkSpeed = .56f
        player.run = false
        player.sprint = false
        player.moving = true
        for (fps in intArrayOf(30, 60, 144)) {
            GameTime.getInstance().fpsMultiplier = 60f / fps
            val dt = GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble()
            CartSteeringHooks.reset(player)
            player.actualX = 0f
            player.actualY = 0f
            CartSteeringHooks.heading(player)
            val state = states[player]
            // Use the real accepted-step producer and production picker/cadence. There is no
            // pending displacement here, so the existing native start budget provides the field.
            var filtered = false
            repeat(fps * 2) { frame ->
                field(state, "heading").setDouble(state, 0.0)
                field(state, "target")
                    .setDouble(state, (if (frame / (fps / 3) % 2 == 0) 1 else -1) * Math.PI / 2)
                field(state, "hasInput").setBoolean(state, true)
                CartSteeringHooks.heading(player)
                val requested = field(state, "requested").get(state) as CartSteeringMath.Step
                val length = Math.hypot(requested.x(), requested.y())
                val rawX = (player.walkSpeed * requested.y() / length).toFloat()
                val rawY = (player.walkSpeed * requested.x() / length).toFloat()
                val desired = CartLegPace.targetSpeed(player, rawX, rawY)
                check(
                    desired.isFinite() && desired > 0,
                    "forward Walk must retain the native requested root calibration",
                )
                check(
                    Math.abs(
                        Math.hypot(player.stepX.toDouble(), player.stepY.toDouble()) -
                            Math.hypot(rawX.toDouble(), rawY.toDouble()),
                    ) < 1e-7,
                    "filtered Walk must preserve the requested stride radius",
                )
                check(
                    Math.abs(nativeBudget(player, node, clips, dt) / dt - desired) < 2e-6,
                    "effective native picker must retain the raw requested root budget: $fps/$frame",
                )
                filtered = filtered || Math.abs(player.stepX - rawX) > .001f
                check(
                    field(state, "visualSpeed").getFloat(state) == -1f,
                    "ordinary Walk filtering must leave the native outgoing movement budget in control",
                )
            }
            check(filtered, "slalom fixture must exercise a different effective native field: $fps")
            // A Run frame owns its field immediately, and the next Walk begins from its own raw
            // field.
            player.run = true
            field(state, "hasInput").setBoolean(state, true)
            CartSteeringHooks.heading(player)
            player.run = false
            field(state, "sprintMomentum").setBoolean(state, false)
            field(state, "target").setDouble(state, Math.PI / 2)
            field(state, "hasInput").setBoolean(state, true)
            CartSteeringHooks.heading(player)
            var requested = field(state, "requested").get(state) as CartSteeringMath.Step
            var length = Math.hypot(requested.x(), requested.y())
            check(
                Math.abs(player.stepX - player.walkSpeed * requested.y() / length) < 1e-7 &&
                    Math.abs(player.stepY - player.walkSpeed * requested.x() / length) < 1e-7,
                "Run/Walk boundary must reset the visual field: $fps",
            )
            // An outgoing fast pose must not disable continuity inside the current Walk gait.
            val layer = AnimLayer.alloc(player, player.animator)
            val root = AdvancedAnimator::class.java.getDeclaredField("rootLayer")
            root.isAccessible = true
            val previousRoot = root.get(player.animator)
            root.set(player.animator, layer)
            val source = AnimNode()
            source.name = "ToolkitCartPivotRun"
            val outgoing = LiveAnimNode.alloc(layer, source)
            val track = AnimationTrack.alloc()
            track.startClip(clips["Bob_Walk"], true, 0f)
            outgoing.addMainTrack(track)
            layer.getLiveAnimNodes().add(outgoing)
            try {
                for (weight in floatArrayOf(.4f, 0f)) {
                    track.setBlendWeight(weight)
                    field(state, "target").setDouble(state, -Math.PI / 2)
                    field(state, "hasInput").setBoolean(state, true)
                    CartSteeringHooks.heading(player)
                    requested = field(state, "requested").get(state) as CartSteeringMath.Step
                    length = Math.hypot(requested.x(), requested.y())
                    check(
                        Math.abs(player.stepX - player.walkSpeed * requested.y() / length) > .001f,
                        "outgoing fast-pose weights must not interrupt the current gait filter: $fps/$weight",
                    )
                }
            } finally {
                root.set(player.animator, previousRoot)
            }
        }
    }

    private fun forwardFastBudget(
        player: Player,
        states: Map<*, *>,
        clips: MutableMap<String, AnimationClip>,
    ) {
        val project = java.nio.file.Path.of(System.getProperty("pz.test.project", "."))
        val media = project.resolve("PZSurvivorToolkit/42/media")
        val nodes = ArrayList<AnimNode>()
        for (mode in arrayOf("run", "sprint")) {
            val node =
                AnimNode.Parse(
                    media.resolve("AnimSets/player/$mode/toolkit_cart_pivot_$mode.xml").toString(),
                )
            check(
                node != null && node.blend2dPicker != null,
                "fast regression must use the production native gait picker",
            )
            val animState = AnimState()
            animState.nodes.add(node)
            player.animator!!.animSet.states[mode] = animState
            nodes.add(node)
            for (blend in node.blends2d) if (!clips.containsKey(blend.animName)) {
                val folder =
                    if (blend.animName.startsWith("Toolkit_")) media.resolve("anims_X/Bob")
                    else java.nio.file.Path.of("media/anims_X/Bob")
                clips[blend.animName] = importClip(folder.resolve(blend.animName + ".x"))
            }
            val nativeName = if (mode == "run") "Bob_Run" else "Bob_Sprint"
            if (!clips.containsKey(nativeName))
                clips[nativeName] =
                    importClip(java.nio.file.Path.of("media/anims_X/Bob/$nativeName.x"))
        }
        player.walkSpeed = .8f
        player.moving = true
        for (fps in intArrayOf(30, 60, 144)) for (sprint in booleanArrayOf(false, true)) {
            player.run = !sprint
            player.sprint = sprint
            GameTime.getInstance().fpsMultiplier = 60f / fps
            val dt = GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble()
            CartSteeringHooks.reset(player)
            player.actualX = 0f
            player.actualY = 0f
            CartSteeringHooks.heading(player)
            val state = states[player]
            val pace = field(state, "pace").get(state) as CartLegPace.Ramp
            pace.reset(CartLegPace.targetSpeed(player, 0f, 1f).toDouble())
            val node = nodes[if (sprint) 1 else 0]
            var filtered = false
            // Exercise the incoming production picker and its imported root clips below the
            // cadence cap. This is not a whole-animation/deferred-movement blend integration test.
            repeat(fps * 2) { frame ->
                field(state, "heading").setDouble(state, 0.0)
                field(state, "target")
                    .setDouble(state, (if (frame / (fps / 3) % 2 == 0) 1 else -1) * Math.PI / 4)
                field(state, "hasInput").setBoolean(state, true)
                CartSteeringHooks.heading(player)
                val requested = field(state, "requested").get(state) as CartSteeringMath.Step
                val length = Math.hypot(requested.x(), requested.y())
                val rawX = (requested.y() / length).toFloat()
                val rawY = (requested.x() / length).toFloat()
                val desired = CartLegPace.targetSpeed(player, rawX, rawY)
                check(
                    desired.isFinite() && desired > 0 && player.legPace < 2.49f,
                    "fast fixture must use calibrated root motion in a feasible uncapped field: $fps/$sprint/$frame",
                )
                check(
                    Math.abs(Math.hypot(player.stepX.toDouble(), player.stepY.toDouble()) - 1) <
                        1e-7,
                    "fast gait filtering must retain a full stride radius",
                )
                check(
                    Math.abs(nativeBudget(player, node, clips, dt) / dt - desired) < 2e-6,
                    "effective fast picker cadence must retain the raw desired budget: $fps/$sprint/$frame",
                )
                filtered = filtered || Math.abs(player.stepX - rawX) > .001f
            }
            check(
                filtered,
                "ordinary forward fast movement must use a continuous effective field: $fps/$sprint",
            )
            player.run = sprint
            player.sprint = !sprint
            field(state, "target").setDouble(state, -Math.PI / 4)
            field(state, "hasInput").setBoolean(state, true)
            CartSteeringHooks.heading(player)
            val requested = field(state, "requested").get(state) as CartSteeringMath.Step
            val length = Math.hypot(requested.x(), requested.y())
            check(
                Math.abs(player.stepX - requested.y() / length) < 1e-7 &&
                    Math.abs(player.stepY - requested.x() / length) < 1e-7,
                "Run/Sprint boundary must begin from the incoming gait's raw field: $fps/$sprint",
            )
        }
        player.run = false
        player.sprint = false
    }

    private fun nativeStart(
        player: Player,
        states: Map<*, *>,
        input: IsoPlayer.InputState,
        target: Double,
    ): Any? {
        CartSteeringHooks.reset(player)
        player.moving = false
        player.inputX = 0f
        player.inputY = 0f
        player.actualX = 10825.5f
        player.actualY = 10142.5f
        CartSteeringHooks.heading(player)
        val state = states[player]
        val initial = Math.PI / 4
        field(state, "heading").setDouble(state, initial)
        field(state, "target").setDouble(state, initial)
        direction(player, target)
        CartSteeringHooks.input(player, input)
        player.moving = true
        CartSteeringHooks.heading(player)
        return state
    }

    private fun nativeFrame(
        player: Player,
        input: IsoPlayer.InputState,
        node: AnimNode,
        clips: Map<String, AnimationClip>,
        dt: Double,
    ) {
        CartSteeringHooks.input(player, input)
        check(
            CartLegPace.targetSpeed(player, player.stepX, player.stepY).isFinite(),
            "direction transitions must retain native clip calibration",
        )
        val budget = nativeBudget(player, node, clips, dt)
        val step = CartSteeringHooks.movement(player, budget.toFloat(), 0f)
        check(
            step.getLength() <= budget + 1e-7,
            "direction transitions cannot invent native root distance",
        )
        accept(player, step)
    }

    private fun nativeDirectionChanges(
        player: Player,
        states: Map<*, *>,
        input: IsoPlayer.InputState,
        node: AnimNode,
        clips: Map<String, AnimationClip>,
    ) {
        val initial = Math.PI / 4
        for (walkSpeed in floatArrayOf(.56f, .3575f)) for (fps in
            intArrayOf(30, 60, 144)) for (sign in intArrayOf(-1, 1)) {
            player.walkSpeed = walkSpeed
            GameTime.getInstance().fpsMultiplier = 60f / fps
            val dt = GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble()
            val context = "$fps/$sign/$walkSpeed"
            var state = nativeStart(player, states, input, initial + sign * Math.PI / 2)
            repeat(fps / 3) { nativeFrame(player, input, node, clips, dt) }
            val halfway = field(state, "heading").getDouble(state)
            check(
                sign * CartSteeringMath.wrap(halfway - initial) > 0,
                "mid-turn fixture must actually turn: $context",
            )
            direction(player, initial - sign * Math.PI / 2)
            var changed = false
            var frame = 0
            while (frame < fps * 6 && field(state, "stationary").getBoolean(state)) {
                nativeFrame(player, input, node, clips, dt)
                if (Math.signum(player.stepX) == sign.toFloat()) changed = true
                if (field(state, "stationary").getBoolean(state))
                    check(
                        Math.abs(player.stepX) == 1f && player.stepY == 0f,
                        "mid-turn changes must retain full lateral strides: $context",
                    )
                frame++
            }
            check(
                changed &&
                    !field(state, "stationary").getBoolean(state) &&
                    Math.abs(
                        CartSteeringMath.wrap(
                            initial - sign * Math.PI / 2 - field(state, "heading").getDouble(state),
                        ),
                    ) < Math.toRadians(.5),
                "left/right mid-turn change must finish at the new heading: $context",
            )
            state = nativeStart(player, states, input, initial + sign * Math.PI / 2)
            repeat(fps / 3) { nativeFrame(player, input, node, clips, dt) }
            player.inputX = 0f
            player.inputY = 0f
            CartSteeringHooks.input(player, input)
            player.moving = false
            val released = field(state, "heading").getDouble(state)
            repeat(fps / 4) { nativeFrame(player, input, node, clips, dt) }
            check(
                field(state, "heading").getDouble(state) == released &&
                    player.stepX == 0f &&
                    player.stepY == 0f,
                "released native strafe must stay planted: $context",
            )
            direction(player, released + sign * Math.PI / 2)
            CartSteeringHooks.input(player, input)
            player.moving = true
            CartSteeringHooks.heading(player)
            check(
                field(state, "stationary").getBoolean(state),
                "restart must reacquire a stationary turn: $context",
            )
            frame = 0
            while (frame < fps * 6 && field(state, "stationary").getBoolean(state)) {
                nativeFrame(player, input, node, clips, dt)
                frame++
            }
            check(
                !field(state, "stationary").getBoolean(state) &&
                    Math.abs(
                        CartSteeringMath.wrap(
                            released + sign * Math.PI / 2 -
                                field(state, "heading").getDouble(state),
                        ),
                    ) < Math.toRadians(.5),
                "released turn must restart and finish with native root: $context",
            )
            state = nativeStart(player, states, input, initial + sign * Math.PI / 2)
            for (quarter in 1..2) {
                frame = 0
                while (frame < fps * 6 && field(state, "stationary").getBoolean(state)) {
                    nativeFrame(player, input, node, clips, dt)
                    frame++
                }
                check(
                    !field(state, "stationary").getBoolean(state) &&
                        Math.abs(
                            CartSteeringMath.wrap(
                                initial + sign * quarter * Math.PI / 2 -
                                    field(state, "heading").getDouble(state),
                            ),
                        ) < Math.toRadians(.5),
                    "two native quarter-turns must reach 180 degrees: $context/$quarter",
                )
                player.inputX = 0f
                player.inputY = 0f
                CartSteeringHooks.input(player, input)
                player.moving = false
                CartSteeringHooks.heading(player)
                if (quarter == 1) {
                    direction(player, initial + sign * Math.PI)
                    CartSteeringHooks.input(player, input)
                    player.moving = true
                    CartSteeringHooks.heading(player)
                    check(
                        field(state, "stationary").getBoolean(state),
                        "second quarter-turn must pivot from rest: $context",
                    )
                }
            }
            state = nativeStart(player, states, input, initial + sign * Math.PI / 2)
            repeat(fps / 3) { nativeFrame(player, input, node, clips, dt) }
            val pivotHeading = field(state, "heading").getDouble(state)
            direction(player, pivotHeading + Math.PI)
            val reversal = field(state, "reversal").get(state) as CartSteeringMath.Reversal
            val pace = field(state, "pace").get(state) as CartLegPace.Ramp
            for (desired in intArrayOf(-1, 1)) {
                direction(player, pivotHeading + if (desired < 0) Math.PI else 0.0)
                var neutral = 0.0
                var switched = false
                for (tick in 0 until fps * 4) {
                    val old = reversal.direction
                    nativeFrame(player, input, node, clips, dt)
                    if (pace.speed == 0.0 && field(state, "actualDistance").getDouble(state) < 1e-6)
                        neutral += dt
                    else neutral = 0.0
                    if (reversal.direction != old) {
                        check(
                            neutral >= .08 - 1e-7 &&
                                pace.speed == 0.0 &&
                                field(state, "actualDistance").getDouble(state) < 1e-6,
                            "stationary pivot sign flip must pass through a full native stop: $context/$desired",
                        )
                        switched = true
                    }
                    if (
                        reversal.direction == desired &&
                            !reversal.active &&
                            Math.abs(player.stepY) > .1
                    )
                        break
                }
                check(
                    switched &&
                        reversal.direction == desired &&
                        !reversal.active &&
                        Math.signum(player.stepY) == desired.toFloat(),
                    "pivot/reverse/forward must restart the requested native gait: $context/$desired",
                )
            }
            direction(player, pivotHeading + Math.PI)
            CartSteeringHooks.input(player, input)
            check(
                reversal.braking,
                "moving reversal cancellation fixture must be braking: $context",
            )
            nativeFrame(player, input, node, clips, dt)
            direction(player, pivotHeading)
            CartSteeringHooks.input(player, input)
            check(
                !reversal.braking && reversal.direction == 1,
                "returning to outgoing input must cancel the sign flip: $context",
            )
            frame = 0
            while (frame < fps * 2 && reversal.active) {
                nativeFrame(player, input, node, clips, dt)
                check(
                    reversal.direction == 1 && player.stepY >= 0,
                    "cancelled reversal cannot leak a backward stride: $context",
                )
                frame++
            }
            check(
                !reversal.active && reversal.direction == 1 && player.stepY > 0,
                "cancelled reversal must recover the outgoing native gait: $context",
            )
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun importClip(path: java.nio.file.Path): AnimationClip {
        check(java.nio.file.Files.isRegularFile(path), "missing animation clip: $path")
        val params = zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams.create()
        params.scene =
            jassimp.Jassimp.importFile(
                path.toString(),
                java.util.EnumSet.of(
                    jassimp.AiPostProcessSteps.MAKE_LEFT_HANDED,
                    jassimp.AiPostProcessSteps.REMOVE_REDUNDANT_MATERIALS,
                ),
            )
        params.mode = zombie.core.skinnedmodel.model.jassimp.JAssImpImporter.LoadMode.AnimationOnly
        params.animBonesScaleModifier = 1f
        params.animBonesRotateModifier = null
        val skeleton =
            zombie.core.skinnedmodel.model.jassimp.ImportedSkeleton.process(
                zombie.core.skinnedmodel.model.jassimp.ImportedSkeletonParams.create(
                    params,
                    params.scene.getMeshes()[0],
                ),
            )
        val clips = field(skeleton, "clips").get(skeleton) as Map<String, AnimationClip>
        check(clips.size == 1, "fixture animation must contain exactly one clip: $path")
        return clips.values.iterator().next()
    }

    private fun stationaryCadence(unsafe: Unsafe, states: Map<*, *>, shopping: Boolean = false) {
        val player = unsafe.allocateInstance(Player::class.java) as Player
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        type(
            cart,
            if (shopping) "SaucedCarts.ShoppingCart" else "SaucedWheelbarrow.WheelbarrowWood",
        )
        player.walkSpeed = .8f
        val project = java.nio.file.Path.of(System.getProperty("pz.test.project", "."))
        val media = project.resolve("PZSurvivorToolkit/42/media")
        val node =
            AnimNode.Parse(
                media
                    .resolve(
                        "AnimSets/player/movement/" +
                            if (shopping) "toolkit_cart_pivot_walk.xml"
                            else "toolkit_cart_wood_pivot_walk.xml",
                    )
                    .toString(),
            )
        check(
            node != null &&
                node.name.equals(CartLegPace.pivotName(cart.getFullType(), false, false)) &&
                node.blend2dPicker != null,
            "stationary regression must load the current production walking node",
        )
        val clips = HashMap<String, AnimationClip>()
        val nativeFolder = java.nio.file.Path.of("media/anims_X/Bob")
        for (blend in node.blends2d) {
            val folder =
                if (blend.animName.startsWith("Toolkit_")) media.resolve("anims_X/Bob")
                else nativeFolder
            clips[blend.animName] = importClip(folder.resolve(blend.animName + ".x"))
        }
        // Raw desired-speed calibration and outgoing fixtures still use the stock source.
        for (name in listOf("Bob_Walk", "Bob_WalkBwdNoAim1Hand")) clips[name] =
            importClip(nativeFolder.resolve("$name.x"))
        val nativeSide = importClip(nativeFolder.resolve("Bob_StrafeNoAim_Left.x"))
        val nativeSideSpeed =
            (nativeSide.getTranslationLength("Translation_Data", BoneAxis.Y) /
                    nativeSide.getDuration())
                .toDouble()
        check(nativeSideSpeed > 0, "native reference must contain measured lateral root motion")
        val animator = AdvancedAnimator()
        player.animator = animator
        animator.animSet = AnimationSet()
        val movement = AnimState()
        movement.nodes.add(node)
        movement.nodes.add(
            AnimNode.Parse(
                nativeFolder
                    .resolve("../../AnimSets/player/movement/defaultWalk.xml")
                    .normalize()
                    .toString(),
            ),
        )
        animator.animSet.states["movement"] = movement
        val mesh = unsafe.allocateInstance(ModelMesh::class.java) as ModelMesh
        mesh.skinningData = SkinningData(clips, listOf(), listOf(), listOf(), listOf(), HashMap())
        val model = ModelManager::class.java.getDeclaredField("animModel")
        model.isAccessible = true
        val oldModel = model.get(ModelManager.instance)
        val input = IsoPlayer.InputState()
        val keys = Keys()
        player.keys = keys
        player.keyboard = shopping
        val time = GameTime.getInstance()
        val oldFps = time.fpsMultiplier
        try {
            model.set(ModelManager.instance, mesh)
            for (injury in floatArrayOf(0f, .00001f)) for (walkSpeed in
                floatArrayOf(.56f, .3575f)) for (fps in intArrayOf(30, 60, 144)) for (sign in
                intArrayOf(-1, 1)) {
                player.injury = injury
                player.walkSpeed = walkSpeed
                time.fpsMultiplier = 60f / fps
                val dt = time.getRealworldSecondsSinceLastUpdate().toDouble()
                CartSteeringHooks.reset(player)
                player.moving = false
                player.inputX = 0f
                player.inputY = 0f
                player.actualX = 10825.5f
                player.actualY = 10142.5f
                CartSteeringHooks.heading(player)
                val state = states[player]
                val initial = Math.PI / 4
                val target = initial + sign * Math.PI / 2
                field(state, "heading").setDouble(state, initial)
                field(state, "target").setDouble(state, initial)
                if (shopping) keys.set(0, sign)
                direction(player, target)
                CartSteeringHooks.input(player, input)
                player.moving = true
                CartSteeringHooks.heading(player)
                check(
                    CartLegPace.targetSpeed(player, player.stepX, player.stepY).isFinite(),
                    "stationary feedback regression must use calibrated native animation clips",
                )
                var rounded = false
                var maxPace = 0f
                var frame = 0
                while (frame < fps * 6 && field(state, "stationary").getBoolean(state)) {
                    if (
                        shopping &&
                            Math.abs(
                                CartSteeringMath.wrap(
                                    field(state, "heading").getDouble(state) - initial,
                                ),
                            ) >= Math.PI / 2
                    ) {
                        keys.set(0, 0)
                        CartSteeringHooks.input(player, input)
                        player.moving = false
                        CartSteeringHooks.heading(player)
                        break
                    }
                    CartSteeringHooks.input(player, input)
                    check(
                        Math.abs(player.stepX) == 1f && player.stepY == 0f,
                        "stationary turns must retain the full native lateral stride",
                    )
                    val budget = nativeBudget(player, node, clips, dt)
                    // Compare the same native movement budget after the authored stride changed
                    // length.
                    // Raw cadence must decrease for a longer step while cargo and response stay
                    // identical.
                    val nativeEquivalentPace = (budget / dt / nativeSideSpeed).toFloat()
                    maxPace = Math.max(maxPace, nativeEquivalentPace)
                    check(
                        nativeEquivalentPace < if (walkSpeed > .5) 1.35 else .86,
                        "cargo must affect full-stride cadence instead of fast idle-blended shuffling",
                    )
                    val before = field(state, "heading").getDouble(state)
                    val x = player.actualX
                    val y = player.actualY
                    val shortFrame = shopping && frame == fps / 3
                    val supplied = if (shortFrame) 0.0 else budget
                    val plannedBefore = field(state, "stationaryRate").getDouble(state)
                    val step = CartSteeringHooks.movement(player, supplied.toFloat(), 0f)
                    if (shopping) {
                        val plannedAfter = field(state, "stationaryRate").getDouble(state)
                        if (shortFrame) {
                            check(
                                step.getLength() == 0f,
                                "missing shopping root cannot invent motion",
                            )
                            check(
                                Math.abs(plannedAfter) >= Math.abs(plannedBefore),
                                "missing shopping root cannot restart the angular ramp",
                            )
                        } else if (
                            frame > fps / 2 &&
                                Math.abs(CartSteeringMath.wrap(target - before)) > .45
                        ) {
                            check(
                                step.getLength() > budget * .9,
                                "shopping sidestep cadence must follow the actual orbit instead of wasting most of its stride",
                            )
                        }
                    }
                    check(
                        step.getLength() <= supplied + 1e-7,
                        "stationary steering cannot invent native root distance",
                    )
                    accept(player, step)
                    val after = field(state, "heading").getDouble(state)
                    if (player.actualX == x && player.actualY == y) {
                        rounded = true
                        check(
                            Math.abs(CartSteeringMath.wrap(after - before)) < 1e-12,
                            "rounded native root cannot rotate the cart",
                        )
                    }
                    check(
                        after.isFinite(),
                        "native stationary feedback must retain a finite heading",
                    )
                    frame++
                }
                check(
                    !field(state, "stationary").getBoolean(state) &&
                        (if (shopping)
                            Math.abs(
                                CartSteeringMath.wrap(
                                    field(state, "heading").getDouble(state) - initial,
                                ),
                            ) >= Math.PI / 2
                        else
                            Math.abs(
                                CartSteeringMath.wrap(
                                    target - field(state, "heading").getDouble(state),
                                ),
                            ) < Math.toRadians(.5)),
                    "calibrated stationary root must finish at world coordinates: $fps/$sign shopping=$shopping speed=$walkSpeed heading=${field(state, "heading").getDouble(state)} target=$target pace=${player.legPace} rate=${field(state, "stationaryRate").getDouble(state)}",
                )
                if (!shopping)
                    check(
                        maxPace > if (walkSpeed > .5) 1.2 else .78,
                        "larger full steps must preserve the responsive native turn budget",
                    )
                if (fps == 144)
                    check(rounded, "high-FPS regression must exercise sub-ULP native root frames")
                player.inputX = 0f
                player.inputY = 0f
                CartSteeringHooks.input(player, input)
                player.moving = false
                CartSteeringHooks.heading(player)
            }
            player.injury = 0f
            if (!shopping) {
                forwardWalkBudget(player, states, node, clips)
                forwardFastBudget(player, states, clips)
                nativeDirectionChanges(player, states, input, node, clips)
            }
        } finally {
            CartSteeringHooks.reset(player)
            time.fpsMultiplier = oldFps
            model.set(ModelManager.instance, oldModel)
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        CartLocomotionBlendChecks.check()
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val tiny =
            CartSteeringMath.step(0.0, 0.0, .0002, 1.0 / 60, 0.0, 1.0, CartSteeringMath.Step())
        check(
            !CartSteeringHooks.blockedStep(tiny, 10825.5f, 10142.5f, 0.0),
            "float-rounded first Sprint step must not restart its acceleration forever",
        )
        val wall = CartSteeringMath.step(0.0, 0.0, .02, 1.0 / 60, 0.0, 1.0, CartSteeringMath.Step())
        check(
            CartSteeringHooks.blockedStep(wall, 10825.5f, 10142.5f, 0.0),
            "a real blocked budget must release Sprint momentum",
        )
        check(
            !CartSteeringHooks.blockedStep(wall, 10825.5f, 10142.5f, .5),
            "accepted movement must retain its momentum",
        )
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe")
        unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        val player = unsafe.allocateInstance(Player::class.java) as Player
        player.walkSpeed = .8f
        val cart = unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        player.inventory = ItemContainer()
        player.primary = cart
        player.secondary = cart
        cart.setContainer(player.inventory)
        val stateField = CartSteeringHooks::class.java.getDeclaredField("states")
        stateField.isAccessible = true
        val states = stateField.get(null) as Map<*, *>
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        val nativeInput = IsoPlayer.InputState()
        nativeInput.sprinting = true
        CartSteeringHooks.input(player, nativeInput)
        val captured = states[player]
        val intent = field(captured, "sprintRequested")
        val identity = field(captured, "cart")
        check(
            intent.getBoolean(captured) && identity.get(captured) === cart,
            "first Sprint intent must acquire the correct cart before native Run fallback",
        )
        CartSteeringHooks.heading(player)
        check(
            states[player] === captured && !intent.getBoolean(captured),
            "heading must consume intent without replacing the newly acquired state",
        )
        nativeInput.sprinting = false
        CartSteeringHooks.input(player, nativeInput)
        check(!intent.getBoolean(captured), "native eligibility denial must clear Sprint intent")
        player.brace = true
        player.blocked = 1
        nativeInput.sprinting = true
        CartSteeringHooks.input(player, nativeInput)
        check(
            !states.containsKey(player),
            "ineligible input must release state rather than retain Sprint intent",
        )
        check(!player.brace, "death/protected reset retained the effort animation gate")
        player.blocked = 0
        for (kind in
            arrayOf(
                "SaucedWheelbarrow.WheelbarrowWood",
                "SaucedWheelbarrow.WheelbarrowMetal",
                "SaucedCarts.ShoppingCart",
            )) {
            type(cart, kind)
            for (heading in doubleArrayOf(0.0, Math.PI / 2, -Math.PI / 2, Math.PI)) {
                for (degrees in intArrayOf(0, 45, 90, 134, 136, 180, -45, -90, -134, -136)) {
                    CartSteeringHooks.reset(player)
                    CartSteeringHooks.heading(player)
                    val state = states[player]
                    val yaw = field(state, "heading")
                    yaw.setDouble(state, heading)
                    val world = heading + Math.toRadians(degrees.toDouble())
                    // Inverse of native world=(input.y+input.x,input.y-input.x).
                    player.inputX = ((Math.cos(world) - Math.sin(world)) / 2).toFloat()
                    player.inputY = ((Math.cos(world) + Math.sin(world)) / 2).toFloat()
                    nativeInput.setRunning(true)
                    nativeInput.sprinting = true
                    CartSteeringHooks.input(player, nativeInput)
                    val reverse = kind.startsWith("SaucedWheelbarrow.") && Math.abs(degrees) > 135
                    val stationary =
                        kind.startsWith("SaucedWheelbarrow.") && Math.abs(degrees) > 20 && !reverse
                    val clamped = reverse || stationary
                    check(
                        nativeInput.isRunning() != clamped && nativeInput.sprinting != clamped,
                        "wooden reverse and stationary turns must reject Run/Sprint: $kind/$heading/$degrees",
                    )
                    check(
                        intent.getBoolean(state) == !clamped,
                        "Sprint capture must follow the clamped native input",
                    )
                }
            }
        }
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        for (oldDirection in intArrayOf(1, -1)) {
            CartSteeringHooks.reset(player)
            CartSteeringHooks.heading(player)
            val state = states[player]
            val reversalField = field(state, "reversal")
            val reversal = reversalField.get(state) as CartSteeringMath.Reversal
            val paceField = field(state, "pace")
            (paceField.get(state) as CartLegPace.Ramp).reset(1.0)
            val target = field(state, "target")
            target.setDouble(state, if (oldDirection < 0) Math.PI else 0.0)
            reversal.direction = oldDirection
            reversal.requested = oldDirection
            val desired = if (oldDirection > 0) Math.PI else 0.0
            player.inputX = ((Math.cos(desired) - Math.sin(desired)) / 2).toFloat()
            player.inputY = ((Math.cos(desired) + Math.sin(desired)) / 2).toFloat()
            nativeInput.setRunning(true)
            nativeInput.sprinting = true
            CartSteeringHooks.input(player, nativeInput)
            check(
                reversal.active &&
                    reversal.braking &&
                    reversal.direction == oldDirection &&
                    reversal.requested == -oldDirection,
                "moving reversal must retain the outgoing direction until braking finishes",
            )
            check(
                !nativeInput.isRunning() && !nativeInput.sprinting,
                "pending reversal must reject fast gait in both directions",
            )
            val braking = CartSteeringHooks.movement(player, .02f, 0f)
            check(
                braking.x * oldDirection > 0 && Math.abs(braking.y) < 1e-6,
                "braking must preserve outgoing rolling direction",
            )
            player.moving = true
            // This fixture deliberately has no native animation calibration.
            CartSteeringHooks.heading(player)
            check(
                !reversal.active && !reversal.braking && reversal.direction == -oldDirection,
                "missing clip calibration must release the outgoing direction rather than trap braking",
            )
            (paceField.get(state) as CartLegPace.Ramp).reset(1.0)
            reversal.request(oldDirection, false)
            player.inputX = 0f
            player.inputY = 0f
            CartSteeringHooks.input(player, nativeInput)
            check(
                !reversal.active && !reversal.braking && reversal.requested == 0,
                "release must cancel a pending sign flip",
            )
            CartSteeringHooks.reset(player)
            CartSteeringHooks.heading(player)
            val fresh = states[player]
            val resetReversal = reversalField.get(fresh) as CartSteeringMath.Reversal
            check(
                fresh !== state && !resetReversal.active && resetReversal.direction == 1,
                "reset must discard reversal state",
            )
        }
        CartSteeringHooks.reset(player)
        player.inputX = 0f
        player.inputY = 0f
        player.moving = false
        val gates =
            arrayOf(
                "dead",
                "hit reaction",
                "knocked down",
                "getting up",
                "grappling",
                "being grappled",
                "ragdoll",
                "remote",
                "path",
                "motion disabled",
                "unsupported cart",
                "one hand",
                "other inventory",
                "world item",
            )
        for (kind in
            arrayOf(
                "SaucedCarts.ShoppingCart",
                "SaucedWheelbarrow.WheelbarrowWood",
                "SaucedWheelbarrow.WheelbarrowMetal",
            )) {
            type(cart, kind)
            check(CartSteeringHooks.supportedCart(player), "supported cart rejected: $kind")
        }
        for (gate in 1..gates.size) {
            player.blocked = 0
            type(cart, "SaucedCarts.ShoppingCart")
            player.secondary = cart
            cart.setContainer(player.inventory)
            cart.setWorldItem(null)
            CartSteeringHooks.heading(player)
            check(
                player.pivot && states.containsKey(player),
                "eligible cart did not acquire steering",
            )
            player.stepX = .5f
            player.stepY = .5f
            player.blocked = gate
            if (gate == 11) type(cart, "Base.Bag_Schoolbag")
            if (gate == 12) player.secondary = null
            if (gate == 13) cart.setContainer(ItemContainer())
            if (gate == 14)
                cart.setWorldItem(
                    unsafe.allocateInstance(IsoWorldInventoryObject::class.java)
                        as IsoWorldInventoryObject,
                )
            val actual = CartSteeringHooks.movement(player, .02f, -.01f)
            check(actual.x == .02f && actual.y == -.01f, gates[gate - 1] + " redirected movement")
            CartSteeringHooks.heading(player)
            check(
                !player.pivot &&
                    player.stepX == 0f &&
                    player.stepY == 0f &&
                    player.legPace == 0f &&
                    !states.containsKey(player),
                gates[gate - 1] + " retained steering state",
            )
        }
        CartSteeringHooks.reset(player)
        check(!states.containsKey(player), "repeated reset retained state")
        player.blocked = 0
        player.secondary = cart
        cart.setContainer(player.inventory)
        cart.setWorldItem(null)
        for (kind in
            arrayOf("SaucedWheelbarrow.WheelbarrowWood", "SaucedWheelbarrow.WheelbarrowMetal")) {
            type(cart, kind)
            CartSteeringHooks.heading(player)
            val state = states[player]
            val pending = field(state, "pending")
            pending.setBoolean(state, true)
            player.actualX = .02f
            player.actualY = .01f
            CartSteeringHooks.heading(player)
            val heading = field(state, "heading")
            val axle = if (kind.endsWith("Wood")) 1.0084944326 else 1.002699624
            check(
                Math.abs(
                    heading.getDouble(state) -
                        CartSteeringMath.acceptedTurn(
                            0.0,
                            axle,
                            player.actualX.toDouble(),
                            player.actualY.toDouble(),
                        ),
                ) < 1e-10,
                "native collision displacement must determine wheel yaw: $kind",
            )
            run {
                val before = CartSteeringHooks.wheelPhase(player)
                check(before < 0, "accepted forward travel spins the wooden wheel")
                val rawPhase = field(state, "wheelPhase")
                val acceptedPhase = rawPhase.getDouble(state)
                CartSteeringHooks.heading(player)
                check(
                    rawPhase.getDouble(state) == acceptedPhase,
                    "heading without accepted movement cannot spin the wheel twice",
                )
                val replacement =
                    unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
                type(replacement, kind)
                replacement.setContainer(player.inventory)
                player.primary = replacement
                player.secondary = replacement
                CartSteeringHooks.heading(player)
                check(
                    CartSteeringHooks.wheelPhase(player) == 0.0,
                    "new wooden cart inherited the old cart phase",
                )
                player.primary = cart
                player.secondary = cart
            }
            CartSteeringHooks.reset(player)
            player.actualX = 0f
            player.actualY = 0f
        }
        val continuityPlayer = unsafe.allocateInstance(Player::class.java) as Player
        continuityPlayer.inventory = ItemContainer()
        val continuityCart =
            unsafe.allocateInstance(InventoryContainer::class.java) as InventoryContainer
        type(continuityCart, "SaucedWheelbarrow.WheelbarrowWood")
        continuityCart.setContainer(continuityPlayer.inventory)
        continuityPlayer.primary = continuityCart
        continuityPlayer.secondary = continuityCart
        val wheelPose = org.joml.Matrix4f().scale(76.5f)
        CartWheelSpin.record(continuityCart, 0f, 0f, 0f, wheelPose, .8)
        CartSteeringHooks.heading(continuityPlayer)
        check(
            Math.abs(CartSteeringHooks.wheelPhase(continuityPlayer) - .8) < 1e-6,
            "steering lost the same item's world phase",
        )
        val wheelSlot = zombie.core.skinnedmodel.model.ModelSlotRenderData()
        wheelSlot.y = -.02f
        val followed = CartSteeringHooks.wheelPhase(continuityPlayer, wheelSlot, wheelPose)
        val expected = .8 - .02 / CartWheelSpin.WORLD_RADIUS
        check(
            Math.abs(followed - expected) < 1e-6 &&
                Math.abs(CartSteeringHooks.wheelPhase(continuityPlayer) - expected) < 1e-6,
            "first held render did not rebase the exact final handoff travel",
        )
        check(
            CartSteeringHooks.wheelPhase(continuityPlayer, wheelSlot, wheelPose) == followed,
            "repeated render spun wheel twice",
        )
        CartSteeringHooks.reset(continuityPlayer)
        CartSteeringHooks.heading(continuityPlayer)
        check(
            Math.abs(CartSteeringHooks.wheelPhase(continuityPlayer) - expected) < 1e-6,
            "state reset discarded rendered item phase",
        )
        CartSteeringHooks.reset(continuityPlayer)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.moving = true
        player.walkSpeed = .25f
        for (gait in 0 until 3) {
            player.run = gait == 1
            player.sprint = gait == 2
            CartSteeringHooks.heading(player)
            val state = states[player]
            val pending = field(state, "pending")
            pending.setBoolean(state, true)
            player.actualX = .02f
            player.actualY = 0f
            CartSteeringHooks.heading(player)
            check(
                Math.abs(
                    Math.hypot(player.stepX.toDouble(), player.stepY.toDouble()) -
                        if (gait == 0) .25 else 1.0,
                ) < 1e-6,
                "native run speed was incorrectly reused as an idle blend: gait=$gait",
            )
            CartSteeringHooks.reset(player)
            player.actualX = 0f
        }
        CartSteeringHooks.reset(player)
        type(cart, "SaucedWheelbarrow.WheelbarrowWood")
        player.moving = false
        player.run = true
        player.sprint = false
        CartSteeringHooks.heading(player)
        check(
            CartSteeringHooks.fastPoseWeight(player) == 1f,
            "running must acquire clearance through its native pose fade",
        )
        player.run = false
        repeat(12) { CartSteeringHooks.heading(player) }
        check(
            CartSteeringHooks.fastPoseWeight(player) == 1f,
            "stop clearance must survive the outgoing running track",
        )
        repeat(9) { CartSteeringHooks.heading(player) }
        val fading = CartSteeringHooks.fastPoseWeight(player)
        check(fading > 0 && fading < 1, "clearance must fade smoothly after the native handoff")
        repeat(6) { CartSteeringHooks.heading(player) }
        check(
            CartSteeringHooks.fastPoseWeight(player) == 0f,
            "ordinary walking must release fast-pose clearance",
        )
        player.run = true
        CartSteeringHooks.heading(player)
        CartSteeringHooks.reset(player)
        check(
            CartSteeringHooks.fastPoseWeight(player) == 0f,
            "reset must release delayed pose clearance",
        )
        player.run = false
        CartSteeringHooks.heading(player)
        val side = field(states[player], "sideClearance")
        side.setFloat(states[player], -.06f)
        CartSteeringHooks.heading(player)
        val sideFade = CartSteeringHooks.sideClearance(player)
        check(
            sideFade > -.06 && sideFade < 0,
            "native heading must release side clearance gradually once per update",
        )
        CartSteeringHooks.reset(player)
        check(
            CartSteeringHooks.sideClearance(player) == 0f,
            "reset cannot leak side clearance into the next cart",
        )
        pathControls(unsafe, states)
        keyboardControls(unsafe, states)
        keyboardReleaseControls(unsafe, states)
        keyboardWorldReleaseControls(unsafe, states)
        shoppingRearAxleControls(unsafe, states)
        stationaryControls(unsafe, states)
        stationaryCadence(unsafe, states)
        stationaryCadence(unsafe, states, true)
        brakeControls(unsafe, states)
        residualBrake(unsafe, states)
        residualBrakeEdges(unsafe, states)
        adjacentBrakeRelease(unsafe, states)
        slalomClearance(unsafe, states)
        wovenPathControls(unsafe, states)
        wovenProtectedControls(unsafe, states)
        println(
            "CART_STEERING_HOOKS_PASS (combat, local, path, scope, ownership, reset, native direction transitions)",
        )
    }
}
