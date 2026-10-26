package net.alexredby.pztoolkitjavapatches

import java.util.WeakHashMap
import zombie.GameTime
import zombie.ai.states.CollideWithWallState
import zombie.characters.CharacterInputMode
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator
import zombie.inventory.types.InventoryContainer
import zombie.iso.Vector2

/** Per-player cart steering; original movement still performs collisions. */
internal object CartSteeringHooks {
    private val states = WeakHashMap<IsoPlayer, State>()
    private val passthrough = ThreadLocal.withInitial(::Vector2)

    private class State {
        var heading = 0.0
        var target = 0.0
        var load = 0.0
        var lean = 0.0
        var wheelPhase = 0.0
        var wheelOrigin = 0.0
        var turnRate = 0.0
        var stationaryRate = 0.0
        val bank = CartSteeringMath.Bank()
        val pace = CartLegPace.Ramp()
        val gaitBlend = CartLocomotionBlend()
        val reversal = CartSteeringMath.Reversal()
        var brakeTarget = 0.0
        var actualDistance = 0.0
        var fastPoseTail = 0.0
        var nativeSpeed = 0.0
        var brakeLimit = 0.0
        var brakeWait = 0.0
        var brakePace = 0.0
        var fastReleaseWait = 0.0
        var fastPace = 0.0
        var brakeDuration = 1.0
        var brace = 0.0
        var visualSpeed = -1f
        var sideClearance = 0f
        var cart: zombie.inventory.InventoryItem? = null
        var startX = 0f
        var startY = 0f
        var wheelRendered = false
        var stationary = false
        var stationaryRoot = false
        var cartBlocked = false
        var recovering = false
        var path = false
        var relative = false
        var footprintFront = CartFootprint.WALK_FRONT
        var slideTurn = Double.NaN
        var wallHeading = Double.NaN
        var wallNormalX = 0.0
        var wallNormalY = 0.0
        var wallTurnRate = 0.0
        var wallStepSeconds = 0.0
        var moving = false
        var pending = false
        var sprintMomentum = false
        var sprintRequested = false
        var hasInput = false
        var wantsMove = false
        var braking = false
        var brakeSeen = false
        var fastMoving = false
        var sprintMoving = false
        var momentumSprint = false
        val requested = CartSteeringMath.Step()
        val braceProbe = CartSteeringMath.Step()
        val result = Vector2()
        val input = Vector2()
    }

    @JvmStatic
    fun supportedCart(player: IsoPlayer?): Boolean {
        val owner = player ?: throw NullPointerException()
        val cart = owner.getPrimaryHandItem()
        if (
            cart !is InventoryContainer ||
                owner.getSecondaryHandItem() !== cart ||
                cart.getContainer() !== owner.getInventory() ||
                cart.getWorldItem() != null
        )
            return false
        return when (cart.getFullType() ?: throw NullPointerException()) {
            "SaucedCarts.ShoppingCart",
            "SaucedWheelbarrow.WheelbarrowWood",
            "SaucedWheelbarrow.WheelbarrowMetal" -> true
            else -> false
        }
    }

    @JvmStatic
    fun enabled(player: IsoPlayer?): Boolean {
        val owner = player ?: throw NullPointerException()
        return owner.isLocalPlayer() &&
            !owner.isNpc() &&
            owner.getVariableBoolean("ToolkitCartMotion") &&
            !owner.isDead() &&
            !owner.hasHitReaction() &&
            !owner.isKnockedDown() &&
            !owner.isGettingUp() &&
            !owner.isGrappling() &&
            !owner.isBeingGrappled() &&
            !owner.isRagdollSimulationActive() &&
            !owner.isCurrentState(CollideWithWallState.instance()) &&
            supportedCart(owner) &&
            (!pathMode(owner) || wooden(owner)) &&
            owner.getPrimaryHandItem() is InventoryContainer
    }

    @JvmStatic
    private fun pathMode(player: IsoPlayer): Boolean {
        val path = player.getPathFindBehavior2()
        return player.hasPath() || path != null && path.isMovingUsingPathFind()
    }

    @JvmStatic
    private fun state(player: IsoPlayer): State {
        var state = states[player]
        if (
            state == null ||
                state.cart !== player.getPrimaryHandItem() ||
                state.path != pathMode(player) && !state.pending
        ) {
            if (state != null) reset(player)
            state = State()
            state.cart = player.getPrimaryHandItem()
            state.path = pathMode(player)
            state.wheelOrigin = CartWheelSpin.itemPhase(state.cart)
            val facing = player.getAnimForwardDirection(Vector2())
            state.heading = Math.atan2(facing.y.toDouble(), facing.x.toDouble())
            states[player] = state
        }
        return state
    }

    @JvmStatic
    private fun keyboard(player: IsoPlayer): Boolean =
        player.getInputMode() === CharacterInputMode.KEYBOARD &&
            !player.isAimControlActive() &&
            !player.isAutoWalk()

    @JvmStatic
    private fun travel(player: IsoPlayer): Int {
        val input = player.getCharacterInputComponent()
        return (if (input.isForwardKeyDown()) 1 else 0) - (if (input.isBackwardKeyDown()) 1 else 0)
    }

    @JvmStatic
    private fun steering(player: IsoPlayer): Int {
        val input = player.getCharacterInputComponent()
        return (if (input.isRightKeyDown()) 1 else 0) - (if (input.isLeftKeyDown()) 1 else 0)
    }

    @JvmStatic
    private fun relativeTarget(player: IsoPlayer, state: State) {
        val steering = steering(player)
        state.target = CartSteeringMath.keyboardTarget(state.heading, travel(player), steering)
        if (steering == 0) {
            state.turnRate = 0.0
            state.stationaryRate = 0.0
            state.stationary = false
        }
    }

    /** Keep native input gating and stride length, with cart-relative keyboard directions. */
    @JvmStatic
    fun keyboardMovement(player: IsoPlayer?, move: Vector2?): Vector2? {
        if (
            !enabled(player) ||
                pathMode(player ?: throw NullPointerException()) ||
                !keyboard(player)
        )
            return move
        val travel = travel(player)
        val steering = steering(player)
        if (travel == 0 && steering == 0) return (move ?: throw NullPointerException()).set(0f, 0f)
        val target = CartSteeringMath.keyboardTarget(state(player).heading, travel, steering)
        val result = move ?: throw NullPointerException()
        val length = result.getLength() / Math.sqrt(2.0)
        return result.set(
            (length * (Math.cos(target) - Math.sin(target))).toFloat(),
            (length * (Math.cos(target) + Math.sin(target))).toFloat(),
        )
    }

    @JvmStatic
    fun input(player: IsoPlayer?, input: IsoPlayer.InputState?) {
        if (!enabled(player)) {
            if (states.containsKey(player)) reset(player)
            return
        }
        val owner = player ?: throw NullPointerException()
        val state = state(owner)
        if (state.path) return
        val keyboard = keyboard(owner)
        if (state.relative && !keyboard) {
            state.stationary = false
            state.stationaryRoot = false
        }
        state.relative = keyboard
        val travel = if (keyboard) travel(owner) else 0
        val steering = if (keyboard) steering(owner) else 0
        var desired =
            if (keyboard) CartSteeringMath.keyboardTarget(state.heading, travel, steering) else 0.0
        if (keyboard && !wooden(owner)) {
            state.hasInput = true
            state.wantsMove = travel != 0 || steering != 0
            state.target = desired
            state.reversal.direction = if (travel < 0) -1 else 1
            state.stationary = travel == 0 && steering != 0
            if (state.stationary && !state.stationaryRoot) state.stationaryRate = 0.0
            if (state.stationary) state.stationaryRoot = true
            else if (state.wantsMove) state.stationaryRoot = false
            if (state.stationaryRoot || travel < 0) {
                (input ?: throw NullPointerException()).setRunning(false)
                input.sprinting = false
            }
        }
        if (wooden(owner)) {
            val wasMoving = state.wantsMove
            val move = owner.getInputMoveVector(state.input)
            // Native input is in screen axes; steering heading is in world axes.
            if (!keyboard)
                desired = Math.atan2((move.y - move.x).toDouble(), (move.y + move.x).toDouble())
            state.hasInput = true
            state.wantsMove =
                if (keyboard) travel != 0 || steering != 0 else move.getLengthSquared() > 1e-8
            val controls = input ?: throw NullPointerException()
            if (controls.isRunning() || controls.sprinting) state.fastReleaseWait = 0.0
            else {
                val dt = GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble()
                state.fastReleaseWait += Math.max(0.0, dt)
                if (
                    wasMoving &&
                        state.wantsMove &&
                        state.fastMoving &&
                        dt > 0 &&
                        state.fastReleaseWait <= .05 &&
                        state.reversal.direction > 0 &&
                        !state.reversal.active &&
                        state.actualDistance > 1e-6 &&
                        owner.isAllowRun() &&
                        (!state.sprintMoving || owner.isAllowSprint())
                ) {
                    // Coalesce near-simultaneous key releases before the native fast node loses its
                    // stop transition.
                    controls.setRunning(!state.sprintMoving)
                    controls.sprinting = state.sprintMoving
                }
            }
            if (state.wantsMove) {
                state.braking = false
                owner.setVariable("ToolkitCartWoodBrake", false)
                owner.setVariable("ToolkitCartBrakeSprint", false)
            } else if (
                CartInjury.amount(owner.getVariableFloat("WalkInjury", 0f)) == 0f &&
                    wasMoving &&
                    (state.fastMoving || state.sprintMomentum) &&
                    state.reversal.direction > 0 &&
                    !state.reversal.active &&
                    state.actualDistance > 1e-6 &&
                    state.nativeSpeed.isFinite() &&
                    state.nativeSpeed > 0
            ) {
                state.braking = true
                state.brakeSeen = false
                state.brakeWait = 0.0
                state.brakeLimit = state.nativeSpeed
                state.brakePace = state.pace.speed
                val remaining =
                    if (state.fastMoving || state.fastPace <= 0) 1.0
                    else Math.max(0.0, Math.min(1.0, state.pace.speed / state.fastPace))
                state.brakeDuration = .65 + .35 * remaining
                owner.setVariable(
                    "ToolkitCartBrakeSprint",
                    if (state.fastMoving) state.sprintMoving else state.momentumSprint,
                )
                owner.setVariable("ToolkitCartWoodBrake", true)
            }
            var intent = 0
            if (state.wantsMove)
                intent =
                    if (keyboard) (if (travel == 0) state.reversal.direction else travel)
                    else
                        CartSteeringMath.directionIntent(
                            state.heading,
                            desired,
                            state.reversal.requested,
                        )
            val stop = CartLegPace.brakeTrack(owner)
            val atRest =
                state.pace.speed < 1e-3 &&
                    state.actualDistance < 1e-6 &&
                    (stop == null || !stop.getUseDeferredMovement())
            if (state.reversal.request(intent, atRest)) state.brakeTarget = state.target
            if (keyboard) state.stationary = travel == 0 && steering != 0 && !state.reversal.active
            else if (!state.wantsMove || intent < 0 || state.reversal.active)
                state.stationary = false
            else if (
                !wasMoving &&
                    !state.moving &&
                    atRest &&
                    Math.abs(CartSteeringMath.wrap(desired - state.heading)) > Math.toRadians(20.0)
            )
                state.stationary = true
            if (state.stationary && !state.stationaryRoot) state.stationaryRate = 0.0
            if (state.stationary) state.stationaryRoot = true
            else if (state.wantsMove && !state.reversal.braking) state.stationaryRoot = false
            if (state.wantsMove) state.target = desired
            if (
                state.stationaryRoot ||
                    intent < 0 ||
                    state.reversal.direction < 0 ||
                    state.reversal.active
            ) {
                controls.setRunning(false)
                controls.sprinting = false
            }
            if (
                (controls.isRunning() || controls.sprinting) &&
                    owner.getCurrentSquare() != null &&
                    !CartFootprint.clear(
                        CartFootprint.world(owner),
                        owner.getX().toDouble(),
                        owner.getY().toDouble(),
                        state.heading,
                        (CartWheelbarrow.forItem(owner.getPrimaryHandItem())
                                ?: throw NullPointerException())
                            .fastFront(),
                    )
            ) {
                // A stopped cart must not enter a wall just because Run expands its visual
                // clearance.
                controls.setRunning(false)
                controls.sprinting = false
            }
        }
        state.sprintRequested = (input ?: throw NullPointerException()).sprinting
    }

    @JvmStatic
    fun fastPoseWeight(player: IsoPlayer?): Float {
        val owner = player ?: throw NullPointerException()
        if (!owner.isLocalPlayer()) return CartMotionSync.fastWeight(owner)
        val state = states[owner] ?: return 0f
        val t = Math.min(1.0, state.fastPoseTail / .1).toFloat()
        return t * t * (3 - 2 * t)
    }

    @JvmStatic
    fun sideClearance(player: IsoPlayer?): Float {
        val owner = player ?: throw NullPointerException()
        if (!owner.isLocalPlayer()) return CartMotionSync.sideClearance(owner)
        return states[owner]?.sideClearance ?: 0f
    }

    @JvmStatic
    private fun footprintFront(player: IsoPlayer, state: State): Double =
        if (
            player.isRunning() ||
                player.isSprinting() ||
                state.fastPoseTail > 0 ||
                CartLegPace.woodenFastShift(player) < 0
        )
            (CartWheelbarrow.forItem(player.getPrimaryHandItem()) ?: throw NullPointerException())
                .fastFront()
        else
            (CartWheelbarrow.forItem(player.getPrimaryHandItem()) ?: throw NullPointerException())
                .front()

    @JvmStatic
    fun lean(player: IsoPlayer?): Double {
        val owner = player ?: throw NullPointerException()
        if (!owner.isLocalPlayer()) return CartMotionSync.lean(owner)
        val state = states[owner]
        return if (state != null && enabled(owner) && wheelbarrow(owner)) state.lean else 0.0
    }

    @JvmStatic
    fun clearanceLean(player: IsoPlayer?): Double {
        val owner = player ?: throw NullPointerException()
        if (!owner.isLocalPlayer()) return CartMotionSync.pressure(owner)
        val state = states[owner]
        return if (state != null && enabled(owner) && wooden(owner))
            Math.max(Math.abs(state.lean), state.bank.pressure)
        else 0.0
    }

    @JvmStatic
    fun wheelPhase(player: IsoPlayer?): Double {
        val state = states[player]
        return if (
            state != null && enabled(player) && wooden(player ?: throw NullPointerException())
        ) {
            if (state.path) CartWheelSpin.itemPhase(state.cart)
            else
                CartWheelSpin.advance(
                    CartWheelbarrow.forItem(state.cart),
                    state.wheelOrigin + state.wheelPhase,
                    CartSteeringMath.woodenAxle(
                        clearanceLean(player).toFloat(),
                        CartLegPace.woodenGaitShift(player),
                    ) - CartSteeringMath.woodenAxle(0f, 0f),
                )
        } else Double.NaN
    }

    @JvmStatic
    fun wheelPhase(
        player: IsoPlayer?,
        slot: zombie.core.skinnedmodel.model.ModelSlotRenderData?,
        cart: org.joml.Matrix4f?,
    ): Double {
        val state = states[player]
        if (state != null && state.path && enabled(player)) {
            val frame = slot ?: throw NullPointerException()
            return CartWheelSpin.follow(state.cart, frame.x, frame.y, frame.animPlayerAngle, cart)
        }
        var phase = wheelPhase(player)
        if (state == null || !phase.isFinite()) return phase
        if (!state.wheelRendered) {
            val frame = slot ?: throw NullPointerException()
            val followed =
                CartWheelSpin.follow(state.cart, frame.x, frame.y, frame.animPlayerAngle, cart)
            if (!followed.isFinite()) return Double.NaN
            state.wheelOrigin += Math.IEEEremainder(followed - phase, Math.PI * 2)
            state.wheelRendered = true
            phase = followed
        }
        val frame = slot ?: throw NullPointerException()
        CartWheelSpin.record(state.cart, frame.x, frame.y, frame.animPlayerAngle, cart, phase)
        return phase
    }

    @JvmStatic
    private fun wheelbarrow(player: IsoPlayer): Boolean =
        player.getPrimaryHandItem().getFullType().startsWith("SaucedWheelbarrow.")

    @JvmStatic
    private fun wooden(player: IsoPlayer): Boolean =
        CartWheelbarrow.forItem(player.getPrimaryHandItem()) != null

    @JvmStatic
    private fun axle(player: IsoPlayer): Double =
        when (player.getPrimaryHandItem().getFullType() ?: throw NullPointerException()) {
            // Actual grounded wheel vertices; Model.vectorToWorldCoords scales model Z by -1.5.
            "SaucedWheelbarrow.WheelbarrowWood" ->
                CartSteeringMath.woodenAxle(
                    clearanceLean(player).toFloat(),
                    CartLegPace.woodenGaitShift(player),
                )
            "SaucedWheelbarrow.WheelbarrowMetal" ->
                CartWheelbarrow.METAL.axle() -
                    1.5 *
                        CartWheelbarrow.METAL.motionShift(
                            clearanceLean(player).toFloat(),
                            CartLegPace.woodenGaitShift(player),
                        )
            "SaucedCarts.ShoppingCart" ->
                CartShopping.axle(
                    player.getPrimaryHandItem().worldScale,
                    CartShoppingStance.shift(player),
                )
            else -> 0.0
        }

    private fun stationaryStep(player: IsoPlayer, state: State, distance: Double, dt: Double) {
        val target = if (state.stationary) state.target else state.heading
        if (CartShopping.item(state.cart))
            CartSteeringMath.shoppingStationaryStep(
                state.heading,
                target,
                distance,
                dt,
                state.load,
                axle(player),
                state.stationaryRate,
                state.requested,
            )
        else
            CartSteeringMath.stationaryStep(
                state.heading,
                target,
                distance,
                dt,
                state.load,
                axle(player),
                state.stationaryRate,
                state.requested,
            )
    }

    private fun rollingStep(
        player: IsoPlayer,
        heading: Double,
        target: Double,
        distance: Double,
        seconds: Double,
        load: Double,
        reverse: Boolean,
        result: CartSteeringMath.Step,
    ): CartSteeringMath.Step =
        if (wheelbarrow(player))
            CartSteeringMath.step(
                heading,
                target,
                distance,
                seconds,
                load,
                axle(player),
                52.0,
                reverse,
                result,
            )
        else
            CartSteeringMath.shoppingStep(
                heading,
                target,
                distance,
                seconds,
                load,
                axle(player),
                reverse,
                result,
            )

    @JvmStatic
    private fun load(player: IsoPlayer): Double {
        val contents =
            (player.getPrimaryHandItem() as InventoryContainer? ?: throw NullPointerException())
                .getInventory() ?: return 0.0
        val capacity = contents.getEffectiveCapacity(player)
        val load = if (capacity > 0) (contents.getCapacityWeight() / capacity).toDouble() else 0.0
        return if (load.isFinite()) Math.max(0.0, Math.min(1.0, load)) else 0.0
    }

    @JvmStatic
    fun blockedStep(
        requested: CartSteeringMath.Step?,
        x: Float,
        y: Float,
        fraction: Double,
    ): Boolean {
        // The first slow steps can round to zero in the world's float coordinates.
        val step = requested ?: throw NullPointerException()
        return Math.hypot(step.x(), step.y()) > 2 * Math.max(Math.ulp(x), Math.ulp(y)) &&
            fraction < 1e-6
    }

    @JvmStatic
    fun blockedProbe(
        query: CartFootprint.Query?,
        x: Float,
        y: Float,
        heading: Double,
        dx: Double,
        dy: Double,
        axle: Double,
        front: Double,
    ): Boolean {
        if (!(dx + dy + heading).isFinite()) return true
        if (!CartFootprint.clear(query, x.toDouble(), y.toDouble(), heading, front))
            return dx * Math.cos(heading) + dy * Math.sin(heading) >= 0
        val fraction =
            CartFootprint.limit(query, x.toDouble(), y.toDouble(), heading, dx, dy, axle, front)
        val slide =
            CartFootprint.slide(
                query,
                x.toDouble(),
                y.toDouble(),
                heading,
                dx,
                dy,
                front,
                fraction,
                -.04,
                .04,
            )
        val distance =
            if (slide == null) Math.hypot(dx, dy) * fraction else Math.hypot(slide.x, slide.y)
        return distance <= Math.max(1e-6, (2 * Math.max(Math.ulp(x), Math.ulp(y))).toDouble())
    }

    @JvmStatic
    fun braceTravel(x: Float, y: Float, accepted: Double): Boolean =
        accepted.isFinite() &&
            accepted >= 0 &&
            accepted <= Math.max(1e-6, (2 * Math.max(Math.ulp(x), Math.ulp(y))).toDouble())

    /**
     * Cosmetic contact tolerates coordinate jitter; accepted movement and collision results stay
     * untouched.
     */
    @JvmStatic
    fun braceContact(
        query: CartFootprint.Query?,
        x: Float,
        y: Float,
        heading: Double,
        dx: Double,
        dy: Double,
        axle: Double,
        front: Double,
        accepted: Double,
        forward: Boolean,
    ): Boolean =
        forward &&
            braceTravel(x, y, accepted) &&
            blockedProbe(query, x, y, heading, dx, dy, axle, front)

    /**
     * Hook 1: at IsoPlayer.moveUnmodded(FF)V entry, replace its two arguments with this returned
     * vector. Continue the original method, including slowFactor. Read result.x/y immediately; the
     * vector belongs to this player's state.
     */
    @JvmStatic
    fun movement(player: IsoPlayer?, x: Float, y: Float): Vector2 {
        var state = states[player]
        if (!enabled(player)) return passthrough.get().set(x, y)
        val owner = player ?: throw NullPointerException()
        if (pathMode(owner) || state != null && state.path) state = state(owner)
        if (state == null) return passthrough.get().set(x, y)
        if (state.cart !== owner.getPrimaryHandItem()) {
            reset(owner)
            return passthrough.get().set(x, y)
        }
        // Only the native locomotion call should be redirected; do not double-plan.
        if (state.pending) return passthrough.get().set(x, y)
        state.startX = owner.getX()
        state.startY = owner.getY()
        var distance = Math.hypot(x.toDouble(), y.toDouble())
        if (state.path) return pathMovement(owner, state, x, y)
        // Relative intent follows the accepted yaw, even between native input updates.
        if (state.relative && keyboard(owner)) relativeTarget(owner, state)
        val dt =
            Math.max(
                0.0,
                Math.min(
                    .1,
                    GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble(),
                ),
            )
        if (state.braking || state.brakeLimit > 0 && CartLegPace.brakeTrack(owner) != null)
            distance = Math.min(distance, state.brakeLimit * dt)
        if (dt > 0) {
            // Seed a resumed Sprint from the coasting speed without changing the stop's cadence.
            if (state.braking && state.brakeLimit > 0)
                state.pace.reset(
                    state.brakePace *
                        Math.max(0.0, Math.min(1.0, distance / (dt * state.brakeLimit))),
                )
        }
        state.load = load(owner)
        val query =
            if (wooden(owner) && owner.getCurrentSquare() != null) CartFootprint.world(owner)
            else null
        if (query != null) state.footprintFront = footprintFront(owner, state)
        val footprintClear =
            query != null &&
                CartFootprint.clear(
                    query,
                    state.startX.toDouble(),
                    state.startY.toDouble(),
                    state.heading,
                    state.footprintFront,
                )
        val guided =
            state.wallHeading.isFinite() &&
                state.wantsMove &&
                !state.braking &&
                (!state.relative || keyboard(owner) && travel(owner) > 0) &&
                !state.stationaryRoot &&
                !state.reversal.active &&
                state.reversal.direction > 0 &&
                footprintClear &&
                CartFootprint.followWall(
                    query,
                    state.startX.toDouble(),
                    state.startY.toDouble(),
                    state.heading,
                    state.target,
                    state.wallHeading,
                    state.wallNormalX,
                    state.wallNormalY,
                    state.footprintFront,
                    state.relative,
                )
        if (!guided) state.wallHeading = Double.NaN
        // Deferred native movement may belong to an earlier animation update. Align contact
        // yaw with its travelled budget, rather than a different current-frame time interval.
        state.wallStepSeconds =
            if (guided && state.relative)
                CartSteeringMath.wallStepSeconds(
                    distance,
                    state.visualSpeed.toDouble(),
                    AdvancedAnimator.motionScale.toDouble(),
                    dt,
                )
            else dt
        val rollingTarget =
            if (guided) state.wallHeading
            else if (state.reversal.braking) state.brakeTarget
            else if (state.wantsMove) state.target
            else state.heading + (if (state.reversal.direction < 0) Math.PI else 0.0)
        if (state.stationaryRoot) {
            stationaryStep(owner, state, distance, dt)
            // A short extracted stride must not restart the shopping turn's acceleration.
            // Heading still advances only by collision-accepted native root movement.
            state.stationaryRate =
                if (CartShopping.item(state.cart))
                    CartSteeringMath.stationaryRate(
                        state.heading,
                        if (state.stationary) state.target else state.heading,
                        dt,
                        state.load,
                        state.stationaryRate,
                        true,
                    )
                else if (dt > 0) state.requested.turn() / dt else 0.0
        } else if (wooden(owner))
            CartSteeringMath.woodenStep(
                state.heading,
                rollingTarget,
                distance,
                if (guided) state.wallStepSeconds
                else GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble(),
                state.load,
                axle(owner),
                if (guided) state.wallTurnRate else state.turnRate,
                state.reversal.direction < 0,
                state.requested,
            )
        else
            rollingStep(
                owner,
                state.heading,
                if (state.relative || state.moving) state.target else state.heading,
                distance,
                GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble(),
                state.load,
                if (state.relative) state.reversal.direction < 0
                else state.moving && CartSteeringMath.reversing(state.heading, state.target),
                state.requested,
            )
        state.pending = true
        state.result.set(state.requested.x().toFloat(), state.requested.y().toFloat())
        state.cartBlocked = guided
        state.recovering = false
        // Native float-coordinate rounding is not a steering input. Keep relative yaw coupled
        // to the planned arc and scale it only by accepted travel, using the same swept oracle.
        val steered = state.relative && wooden(owner)
        state.slideTurn = if (steered) state.requested.turn() else Double.NaN
        if (query != null) {
            if (!footprintClear) {
                // An equipped/door-overlapped cart may back out, without sweeping its nose
                // sideways.
                state.recovering = true
                val reverse =
                    Math.min(
                        0.0,
                        state.result.x * Math.cos(state.heading) +
                            state.result.y * Math.sin(state.heading),
                    )
                state.result.set(
                    (reverse * Math.cos(state.heading)).toFloat(),
                    (reverse * Math.sin(state.heading)).toFloat(),
                )
                state.cartBlocked = reverse == 0.0
            } else if (guided && steered) {
                val contact =
                    CartFootprint.contactStep(
                        query,
                        state.startX.toDouble(),
                        state.startY.toDouble(),
                        state.heading,
                        state.result.x.toDouble(),
                        state.result.y.toDouble(),
                        state.requested.turn(),
                        state.wallNormalX,
                        state.wallNormalY,
                        state.footprintFront,
                    )
                state.result.set(contact.x.toFloat(), contact.y.toFloat())
                state.slideTurn = contact.turn
            } else {
                val fraction =
                    if (steered)
                        CartFootprint.rigidLimit(
                            query,
                            state.startX.toDouble(),
                            state.startY.toDouble(),
                            state.heading,
                            state.result.x.toDouble(),
                            state.result.y.toDouble(),
                            state.heading + state.requested.turn(),
                            state.footprintFront,
                        )
                    else
                        CartFootprint.limit(
                            query,
                            state.startX.toDouble(),
                            state.startY.toDouble(),
                            state.heading,
                            state.result.x.toDouble(),
                            state.result.y.toDouble(),
                            axle(owner),
                            state.footprintFront,
                        )
                val guideCap = Math.min((1.6 - .3 * state.load) * dt, distance / axle(owner))
                val guideBase = Math.max(-guideCap, Math.min(guideCap, state.turnRate * dt))
                val slide =
                    if (steered)
                        CartFootprint.steeredSlide(
                            query,
                            state.startX.toDouble(),
                            state.startY.toDouble(),
                            state.heading,
                            state.result.x.toDouble(),
                            state.result.y.toDouble(),
                            state.footprintFront,
                            fraction,
                            state.requested.turn(),
                        )
                    else
                        CartFootprint.slide(
                            query,
                            state.startX.toDouble(),
                            state.startY.toDouble(),
                            state.heading,
                            state.result.x.toDouble(),
                            state.result.y.toDouble(),
                            state.footprintFront,
                            fraction,
                            Math.max(-guideCap, guideBase - 6 * dt * dt),
                            Math.min(guideCap, guideBase + 6 * dt * dt),
                        )
                if (slide == null) {
                    state.result.scale(fraction.toFloat())
                    state.slideTurn *= fraction
                } else {
                    val nx = slide.normalX
                    val ny = slide.normalY
                    if (
                        state.wantsMove &&
                            !state.braking &&
                            !state.stationaryRoot &&
                            !state.reversal.active &&
                            state.reversal.direction > 0 &&
                            CartFootprint.pressingWall(state.target, slide.target, nx, ny)
                    ) {
                        state.wallHeading = slide.target
                        state.wallNormalX = nx
                        state.wallNormalY = ny
                    }
                    state.result.set(slide.x.toFloat(), slide.y.toFloat())
                    state.slideTurn = slide.turn
                }
                state.cartBlocked = state.cartBlocked or (fraction < 1)
            }
        }
        return state.result
    }

    @JvmStatic
    private fun pathMovement(player: IsoPlayer, state: State, x: Float, y: Float): Vector2 {
        state.wallHeading = Double.NaN
        val facing = player.getAnimForwardDirection(state.input)
        state.heading = Math.atan2(facing.y.toDouble(), facing.x.toDouble())
        state.pending = true
        state.result.set(x, y)
        state.footprintFront = footprintFront(player, state)
        state.cartBlocked = false
        state.recovering = false
        if (player.getCurrentSquare() != null) {
            val query = CartFootprint.world(player)
            if (
                !CartFootprint.clear(
                    query,
                    state.startX.toDouble(),
                    state.startY.toDouble(),
                    state.heading,
                    state.footprintFront,
                )
            ) {
                state.recovering = true
                val reverse =
                    Math.min(0.0, x * Math.cos(state.heading) + y * Math.sin(state.heading))
                state.result.set(
                    (reverse * Math.cos(state.heading)).toFloat(),
                    (reverse * Math.sin(state.heading)).toFloat(),
                )
                state.cartBlocked = reverse == 0.0
            } else {
                val allowed =
                    CartFootprint.rigidLimit(
                        query,
                        state.startX.toDouble(),
                        state.startY.toDouble(),
                        state.heading,
                        x.toDouble(),
                        y.toDouble(),
                        state.heading,
                        state.footprintFront,
                    )
                state.result.scale(allowed.toFloat())
                state.cartBlocked = allowed < 1
            }
        }
        if (state.cartBlocked) failPath(player)
        return state.result
    }

    @JvmStatic
    fun beginPath(character: IsoGameCharacter?) {
        if (character is IsoPlayer && enabled(character) && pathMode(character))
            state(character).cartBlocked = false
    }

    @JvmStatic
    private fun failPath(player: IsoPlayer) {
        val path = player.getPathFindBehavior2()
        if (path != null && pathMode(player)) path.Failed(player)
    }

    @JvmStatic
    fun pathResult(
        character: IsoGameCharacter?,
        result: zombie.pathfind.PathFindBehavior2.BehaviorResult?,
    ): zombie.pathfind.PathFindBehavior2.BehaviorResult? {
        if (character !is IsoPlayer || !enabled(character) || !pathMode(character)) return result
        val state = state(character)
        state.footprintFront = footprintFront(character, state)
        var blocked = state.cartBlocked
        if (
            result === zombie.pathfind.PathFindBehavior2.BehaviorResult.Succeeded &&
                character.getCurrentSquare() != null
        ) {
            val facing = character.getAnimForwardDirection(state.input)
            val heading = Math.atan2(facing.y.toDouble(), facing.x.toDouble())
            val target =
                Math.atan2(
                    character.getForwardDirectionY().toDouble(),
                    character.getForwardDirectionX().toDouble(),
                )
            blocked =
                blocked or
                    (CartFootprint.rigidLimit(
                        CartFootprint.world(character),
                        character.getX().toDouble(),
                        character.getY().toDouble(),
                        heading,
                        0.0,
                        0.0,
                        target,
                        state.footprintFront,
                    ) < 1)
            if (blocked)
                character.setTargetAndCurrentDirection(
                    Math.cos(heading).toFloat(),
                    Math.sin(heading).toFloat(),
                )
        }
        if (blocked) {
            failPath(character)
            return zombie.pathfind.PathFindBehavior2.BehaviorResult.Failed
        }
        return result
    }

    @JvmStatic
    private fun pathHeading(player: IsoPlayer, state: State) {
        val facing = player.getAnimForwardDirection(state.input)
        val heading =
            if (state.pending) state.heading
            else Math.atan2(facing.y.toDouble(), facing.x.toDouble())
        val target =
            Math.atan2(
                player.getForwardDirectionY().toDouble(),
                player.getForwardDirectionX().toDouble(),
            )
        val dt =
            Math.max(
                0.0,
                Math.min(
                    .1,
                    GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble(),
                ),
            )
        state.sideClearance =
            CartLegPace.releaseSideShift(
                state.sideClearance,
                CartLegPace.woodenSideShift(player),
                dt,
            )
        state.fastPoseTail =
            if (
                player.isRunning() || player.isSprinting() || CartLegPace.brakeTrack(player) != null
            )
                .4
            else Math.max(0.0, state.fastPoseTail - dt)
        state.footprintFront = footprintFront(player, state)
        if (player.getCurrentSquare() != null) {
            val query = CartFootprint.world(player)
            if (state.pending && !state.recovering) {
                val dx = (player.getX() - state.startX).toDouble()
                val dy = (player.getY() - state.startY).toDouble()
                val allowed =
                    CartFootprint.rigidLimit(
                        query,
                        state.startX.toDouble(),
                        state.startY.toDouble(),
                        heading,
                        dx,
                        dy,
                        heading,
                        state.footprintFront,
                    )
                if (allowed < 1) {
                    player.setX((state.startX + dx * allowed).toFloat())
                    player.setY((state.startY + dy * allowed).toFloat())
                    player.setNextX(player.getX())
                    player.setNextY(player.getY())
                    player.setCurrentSquareFromPosition()
                    player.setMovingSquareNow()
                    state.cartBlocked = true
                }
            }
            val rotation =
                CartFootprint.rigidLimit(
                    query,
                    player.getX().toDouble(),
                    player.getY().toDouble(),
                    heading,
                    0.0,
                    0.0,
                    target,
                    state.footprintFront,
                ) < 1
            if (rotation) {
                // Restore the clear pose before native animation can rotate its nose through an
                // obstacle.
                player.setTargetAndCurrentDirection(
                    Math.cos(heading).toFloat(),
                    Math.sin(heading).toFloat(),
                )
                state.cartBlocked = true
            }
        }
        if (state.cartBlocked) failPath(player)
        state.pending = false
    }

    /**
     * Hook 2: IsoGameCharacter.postUpdateAnimating()V ENTRY. Its caller already ran
     * IsoMovingObject.postupdate() collisions. Capture native input-facing before overriding it,
     * then animate only the accepted part of the arc.
     */
    @JvmStatic
    fun heading(character: IsoGameCharacter?) {
        if (character !is IsoPlayer) return
        val player = character
        if (!player.isLocalPlayer() && states.containsKey(player)) reset(player)
        if (CartMotionSync.update(player)) return
        val existing = states[player]
        if (!enabled(player)) {
            if (existing != null) reset(player)
            return
        }
        var state = state(player)
        if (CartInjury.amount(player.getVariableFloat("WalkInjury", 0f)) > 0f && state.braking) {
            CartLegPace.cancelBrake(player, true)
            state.braking = false
            state.brakeLimit = 0.0
            state.sprintMomentum = false
            state.momentumSprint = false
            player.setVariable("ToolkitCartWoodBrake", false)
            player.setVariable("ToolkitCartBrakeSprint", false)
        }
        state.visualSpeed = -1f
        if (state.path) {
            player.setVariable("ToolkitCartBrace", false)
            pathHeading(player, state)
            publish(player, state)
            return
        }
        player.setVariable("ToolkitCartPivot", true)
        val desired =
            Math.atan2(
                player.getForwardDirectionY().toDouble(),
                player.getForwardDirectionX().toDouble(),
            )
        state = state(player)
        // Native clears the gait flags before UpdateInputState; retain the last finalized gait for
        // release.
        state.fastMoving = player.isRunning() || player.isSprinting()
        state.sprintMoving = player.isSprinting()
        val sprintRequested =
            state.sprintRequested &&
                (CartInjury.amount(player.getVariableFloat("WalkInjury", 0f)) == 0f ||
                    player.isSprinting())
        state.sprintRequested = false
        state.load = load(player)
        var actualX = 0.0
        var actualY = 0.0
        var acceptedTurn = 0.0
        var blocked = false
        if (state.pending) {
            actualX = (player.getX() - state.startX).toDouble()
            actualY = (player.getY() - state.startY).toDouble()
            var slideTurn = state.slideTurn
            if (slideTurn.isFinite()) {
                val planned =
                    (state.result.x * state.result.x + state.result.y * state.result.y).toDouble()
                slideTurn *=
                    if (planned > 0)
                        Math.max(
                            0.0,
                            Math.min(
                                1.0,
                                (actualX * state.result.x + actualY * state.result.y) / planned,
                            ),
                        )
                    else 0.0
            }
            if (wooden(player) && !state.recovering && player.getCurrentSquare() != null) {
                val query = CartFootprint.world(player)
                val allowed =
                    if (slideTurn.isFinite())
                        CartFootprint.rigidLimit(
                            query,
                            state.startX.toDouble(),
                            state.startY.toDouble(),
                            state.heading,
                            actualX,
                            actualY,
                            state.heading + slideTurn,
                            state.footprintFront,
                        )
                    else
                        CartFootprint.limit(
                            query,
                            state.startX.toDouble(),
                            state.startY.toDouble(),
                            state.heading,
                            actualX,
                            actualY,
                            axle(player),
                            state.footprintFront,
                        )
                if (allowed < 1) {
                    player.setX((state.startX + actualX * allowed).toFloat())
                    player.setY((state.startY + actualY * allowed).toFloat())
                    player.setNextX(player.getX())
                    player.setNextY(player.getY())
                    player.setCurrentSquareFromPosition()
                    player.setMovingSquareNow()
                    actualX = (player.getX() - state.startX).toDouble()
                    actualY = (player.getY() - state.startY).toDouble()
                    state.cartBlocked = true
                }
                slideTurn *= allowed
            }
            val fraction = CartSteeringMath.acceptedFraction(state.requested, actualX, actualY)
            blocked =
                state.cartBlocked && actualX == 0.0 && actualY == 0.0 ||
                    blockedStep(state.requested, state.startX, state.startY, fraction)
            val turn =
                if (state.recovering) 0.0
                else if (slideTurn.isFinite()) slideTurn
                else if (wheelbarrow(player))
                    CartSteeringMath.acceptedTurn(state.heading, axle(player), actualX, actualY)
                else state.requested.turn() * fraction
            if (wooden(player)) {
                val mid = state.heading + turn / 2
                val rolling =
                    actualX * Math.cos(mid) + actualY * Math.sin(mid) -
                        2 *
                            (CartWheelbarrow.forItem(state.cart) ?: throw NullPointerException())
                                .lateral() *
                            Math.sin(turn / 2)
                state.wheelPhase =
                    CartWheelSpin.advance(
                        CartWheelbarrow.forItem(state.cart),
                        state.wheelPhase,
                        rolling,
                    )
            }
            acceptedTurn = turn
            state.heading = CartSteeringMath.wrap(state.heading + turn)
            state.pending = false
        }
        val dt =
            Math.max(
                0.0,
                Math.min(
                    .1,
                    GameTime.getInstance().getRealworldSecondsSinceLastUpdate().toDouble(),
                ),
            )
        if (wooden(player))
            state.sideClearance =
                CartLegPace.releaseSideShift(
                    state.sideClearance,
                    CartLegPace.woodenSideShift(player),
                    dt,
                )
        val stop = if (wooden(player)) CartLegPace.brakeTrack(player) else null
        if (state.braking) {
            state.brakeWait += dt
            if (stop != null && !state.brakeSeen) {
                // A loaded cart takes slightly longer to settle, with the same authored foot
                // sequence.
                stop.setSpeedDelta((1 / (state.brakeDuration * (1 + .12 * state.load))).toFloat())
                state.brakeSeen = true
            }
            if (
                blocked ||
                    state.brakeSeen && stop == null ||
                    !state.brakeSeen && state.brakeWait > .3
            ) {
                if (blocked) {
                    CartLegPace.cancelBrake(player, false)
                    CartLegPace.applySpeed(player, 0f, 0f, 0f)
                    state.visualSpeed = 0f
                }
                state.braking = false
                player.setVariable("ToolkitCartWoodBrake", false)
            }
        }
        // The native start/stop pose can outlive the last running track; release its clearance
        // gradually.
        if (wooden(player))
            state.fastPoseTail =
                if (player.isRunning() || player.isSprinting() || stop != null) .4
                else Math.max(0.0, state.fastPoseTail - dt)
        state.actualDistance = Math.hypot(actualX, actualY)
        if (dt > 0 && !state.braking) {
            // Native applies slowdown after this hook's budget; do not count it twice in the stop
            // cap.
            val factor = (1 - player.getSlowFactor()).toDouble()
            state.nativeSpeed = if (factor > 0) state.actualDistance / (dt * factor) else 0.0
        }
        val travel = actualX * Math.cos(state.heading) + actualY * Math.sin(state.heading)
        val bank =
            if (state.stationaryRoot) 0.0
            else if (wooden(player)) CartSteeringMath.rollingLean(acceptedTurn, travel, dt)
            else if (wheelbarrow(player) && dt > 0)
                Math.max(-.10, Math.min(.10, Math.signum(travel) * acceptedTurn / dt * .065))
            else 0.0
        state.turnRate = if (dt > 0) acceptedTurn / dt else 0.0
        // Contact alignment has its own rate; releasing steering must still stop free/reverse yaw.
        state.wallTurnRate =
            if (state.wallHeading.isFinite() && state.wallStepSeconds > 0)
                acceptedTurn / state.wallStepSeconds
            else 0.0
        if (blocked) state.stationaryRate = 0.0
        if (wooden(player)) state.lean = state.bank.update(bank, dt)
        else state.lean += (bank - state.lean) * (1 - Math.exp(-dt / .08))
        state.moving = player.isJustMoved()
        if (state.relative && keyboard(player)) relativeTarget(player, state)
        else if (!state.hasInput && (!wooden(player) || !state.stationaryRoot))
            state.target = if (state.moving) desired else state.heading
        state.hasInput = false
        var hardStop = false
        var effort = false
        val forward =
            state.wantsMove &&
                state.reversal.direction > 0 &&
                (!state.relative || keyboard(player) && travel(player) > 0)
        if (
            wooden(player) &&
                state.wantsMove &&
                !state.stationaryRoot &&
                !state.reversal.active &&
                !state.braking &&
                player.getCurrentSquare() != null &&
                (state.actualDistance < 1e-6 && (blocked || state.brace > 0) ||
                    forward && braceTravel(player.getX(), player.getY(), state.actualDistance))
        ) {
            // Query the intended step even at zero root speed; this never moves the player or
            // wheel.
            CartSteeringMath.woodenStep(
                state.heading,
                state.target,
                .03,
                1.0 / 60,
                state.load,
                axle(player),
                state.turnRate,
                state.reversal.direction < 0,
                state.braceProbe,
            )
            val query = CartFootprint.world(player)
            effort =
                braceContact(
                    query,
                    player.getX(),
                    player.getY(),
                    state.heading,
                    state.braceProbe.x(),
                    state.braceProbe.y(),
                    axle(player),
                    state.footprintFront,
                    state.actualDistance,
                    forward,
                )
            hardStop =
                effort ||
                    state.actualDistance < 1e-6 &&
                        blockedProbe(
                            query,
                            player.getX(),
                            player.getY(),
                            state.heading,
                            state.braceProbe.x(),
                            state.braceProbe.y(),
                            axle(player),
                            state.footprintFront,
                        )
        }
        player.setVariable("ToolkitCartBrace", effort)
        state.brace = Math.max(0.0, Math.min(1.0, state.brace + (if (hardStop) dt else -dt) / .16))
        val bracePose =
            state.brace > 0 && state.wantsMove && !state.stationaryRoot && !state.reversal.active
        var length = Math.hypot(actualX, actualY)
        if (
            state.stationary &&
                Math.abs(CartSteeringMath.wrap(state.target - state.heading)) < Math.toRadians(.5)
        ) {
            state.stationary = false
            state.stationaryRoot = false
        }
        if ((state.moving || bracePose) && length < 1e-6) {
            // Idle/blocked clips need intent to generate their first root-motion budget.
            if (wooden(player))
                CartSteeringMath.woodenStep(
                    state.heading,
                    if (state.reversal.braking) state.brakeTarget else state.target,
                    .03,
                    1.0 / 60,
                    state.load,
                    axle(player),
                    state.turnRate,
                    state.reversal.direction < 0,
                    state.requested,
                )
            else
                rollingStep(
                    player,
                    state.heading,
                    state.target,
                    .03,
                    1.0 / 60,
                    state.load,
                    if (state.relative) state.reversal.direction < 0
                    else CartSteeringMath.reversing(state.heading, state.target),
                    state.requested,
                )
            actualX = state.requested.x()
            actualY = state.requested.y()
            length = Math.hypot(actualX, actualY)
        }
        if (state.stationaryRoot) {
            // Keep the full native stride; idle blending shortens it into rapid shuffling.
            stationaryStep(player, state, 1.0, dt)
            player.setVariable(
                "ToolkitCartStepX",
                if (state.moving && state.stationary)
                    (-Math.signum(state.requested.turn())).toFloat()
                else 0f,
            )
            player.setVariable("ToolkitCartStepY", 0f)
        } else if ((!state.moving && !bracePose) || length < 1e-6) {
            player.setVariable("ToolkitCartStepX", 0f)
            player.setVariable("ToolkitCartStepY", 0f)
        } else {
            val cos = Math.cos(state.heading)
            val sin = Math.sin(state.heading)
            // Native WalkSpeed blends two moving clips too. Keep the forward stride at full
            // radius, even at WalkSpeed=0; cadence alone spends the native gait's root budget.
            // Reverse retains its separate authored slowdown and injury envelope.
            val localY = actualX * cos + actualY * sin
            val pace =
                if (player.isRunning() || player.isSprinting() || localY >= 0) 1.0
                else
                    CartInjury.walkMagnitude(
                            player,
                            Math.max(0f, Math.min(1f, player.getVariableFloat("WalkSpeed", .8f))),
                        )
                        .toDouble()
            player.setVariable(
                "ToolkitCartStepX",
                (pace * (-actualX * sin + actualY * cos) / length).toFloat(),
            )
            player.setVariable(
                "ToolkitCartStepY",
                (pace * (actualX * cos + actualY * sin) / length).toFloat(),
            )
        }
        var stepX = player.getVariableFloat("ToolkitCartStepX", 0f)
        var stepY = player.getVariableFloat("ToolkitCartStepY", 0f)
        var target =
            if (
                wooden(player) ||
                    state.stationaryRoot && CartShopping.item(state.cart) ||
                    CartInjury.blend(player, CartLegPace.pivotNode(player)) != null
            )
                if (state.stationaryRoot) CartLegPace.maneuverSpeed(player, stepX, stepY)
                else CartLegPace.targetSpeed(player, stepX, stepY)
            else Float.NaN
        // Keep the requested native speed above independent of the visual picker direction.
        // Publish that same effective field to the native animator, cadence solve and Host peers.
        val gait =
            if (player.isSprinting()) CartLocomotionBlend.SPRINT
            else if (player.isRunning()) CartLocomotionBlend.RUN else CartLocomotionBlend.WALK
        val forwardGait =
            wooden(player) &&
                state.moving &&
                !blocked &&
                !state.stationaryRoot &&
                !state.reversal.active &&
                !state.braking &&
                stop == null &&
                state.brace == 0.0 &&
                !state.recovering &&
                target.isFinite()
        state.gaitBlend.update(stepX, stepY, dt, if (forwardGait) gait else 0)
        stepX = state.gaitBlend.x
        stepY = state.gaitBlend.y
        player.setVariable("ToolkitCartStepX", stepX)
        player.setVariable("ToolkitCartStepY", stepY)
        // Drop inward input through native cadence once, preserving full strides and the movement
        // budget.
        val wallScale =
            if (
                state.wallHeading.isFinite() &&
                    state.wantsMove &&
                    !state.reversal.active &&
                    !state.stationaryRoot &&
                    CartFootprint.pressingWall(
                        state.target,
                        state.wallHeading,
                        state.wallNormalX,
                        state.wallNormalY,
                    )
            )
                Math.max(0.0, Math.cos(state.target - state.wallHeading)).toFloat()
            else 1f
        target *= wallScale
        if (state.stationaryRoot) {
            // Cargo slows the full stride's cadence instead of reducing its spatial amplitude.
            target *=
                CartInjury.walkMagnitude(
                    player,
                    Math.max(0f, Math.min(1f, player.getVariableFloat("WalkSpeed", .8f))),
                )
            state.sprintMomentum = false
            if (target.isFinite()) {
                // Feed next frame's native cadence, rather than moving planted feet with a
                // synthetic budget.
                val speed =
                    if (dt > 0)
                        Math.min(
                            target.toDouble(),
                            Math.hypot(state.requested.x(), state.requested.y()) / dt,
                        )
                    else 0.0
                state.pace.reset(speed)
                CartLegPace.applySpeed(player, speed.toFloat(), stepX, stepY)
                state.visualSpeed = speed.toFloat()
                if (state.reversal.braking)
                    state.reversal.stopped(dt, speed == 0.0, state.actualDistance < 1e-6)
            } else {
                state.pace.reset(0.0)
                CartLegPace.apply(player, CartLegPace.scale(player, stepX, stepY))
                if (state.reversal.braking)
                    state.reversal.stopped(dt, true, state.actualDistance < 1e-6)
            }
        } else if (state.braking) {
            // The authored stop owns deceleration; freezing its outgoing gait would break the
            // blend.
            state.sprintMomentum = false
        } else if (bracePose && target.isFinite()) {
            state.sprintMomentum = !hardStop
            if (hardStop) state.pace.reset(0.0)
            else target = state.pace.update(target.toDouble(), dt, state.load, true).toFloat()
            state.visualSpeed =
                CartLegPace.brace(player, target, stepX, stepY, state.brace, hardStop)
        } else if (target.isFinite()) {
            if (blocked) state.pace.reset(0.0)
            // Native uses Run for the first Sprint frame, before isSprinting becomes true.
            if (state.fastMoving || sprintRequested && state.moving) {
                if (
                    player.isRunning() &&
                        !sprintRequested &&
                        !state.sprintMomentum &&
                        CartLegPace.brakeTrack(player) == null
                )
                    state.pace.reset(target.toDouble())
                state.sprintMomentum = true
                state.momentumSprint = player.isSprinting() || sprintRequested
            }
            if (state.reversal.active) {
                state.sprintMomentum = false
                var speed =
                    state.pace.update(
                        if (state.reversal.braking) 0.0 else target.toDouble(),
                        dt,
                        state.load,
                    )
                if (state.reversal.braking && state.pace.settled(0.0)) {
                    state.pace.reset(0.0)
                    speed = 0.0
                }
                val radius = if (target > 1e-6) Math.min(1f, (speed / target).toFloat()) else 0f
                stepX *= radius
                stepY *= radius
                player.setVariable("ToolkitCartStepX", stepX)
                player.setVariable("ToolkitCartStepY", stepY)
                CartLegPace.applySpeed(player, speed.toFloat(), stepX, stepY)
                state.visualSpeed = speed.toFloat()
                if (state.reversal.braking)
                    state.reversal.stopped(dt, speed == 0.0, state.actualDistance < 1e-6)
                else if (state.pace.settled(target.toDouble())) state.reversal.active = false
            } else if (state.sprintMomentum) {
                val speed = state.pace.update(target.toDouble(), dt, state.load, true)
                CartLegPace.applySpeed(player, speed.toFloat(), stepX, stepY)
                state.visualSpeed = speed.toFloat()
                if (state.fastMoving) state.fastPace = speed
                else if (Math.abs(speed - target) <= Math.max(1e-3, target * .02))
                    state.sprintMomentum = false
            } else {
                state.pace.reset(target.toDouble())
                if (wallScale < 1) {
                    CartLegPace.applySpeed(player, target, stepX, stepY)
                    state.visualSpeed = target
                } else CartLegPace.apply(player, CartLegPace.scale(player, stepX, stepY))
            }
        } else {
            state.sprintMomentum = false
            state.pace.reset(0.0)
            // Without calibrated clips, fall back without trapping the old travel direction.
            state.reversal.active = false
            state.reversal.braking = false
            state.reversal.neutral = 0.0
            if (state.reversal.requested != 0) state.reversal.direction = state.reversal.requested
            CartLegPace.apply(player, CartLegPace.scale(player, stepX, stepY))
        }
        // Scoped cart AnimNodes own maxTorsoTwist; native animation rewrites it.
        player.setTargetAndCurrentDirection(
            Math.cos(state.heading).toFloat(),
            Math.sin(state.heading).toFloat(),
        )
        publish(player, state)
    }

    @JvmStatic
    private fun publish(player: IsoPlayer, state: State) {
        CartMotionSync.publish(
            player,
            state.lean,
            Math.max(Math.abs(state.lean), state.bank.pressure),
            state.sideClearance,
            fastPoseWeight(player),
            state.visualSpeed.toDouble(),
        )
    }

    /**
     * Native player packets are built before postUpdateAnimating restores the accepted cart yaw.
     */
    @JvmStatic
    fun networkHeading(player: IsoPlayer?): Float {
        val state = states[player]
        return if (
            state != null &&
                enabled(player) &&
                state.cart === (player ?: throw NullPointerException()).getPrimaryHandItem()
        )
            state.heading.toFloat()
        else Float.NaN
    }

    /** Native animation updates can enter a protected state after the heading entry hook. */
    @JvmStatic
    fun finish(character: IsoGameCharacter?) {
        if (character is IsoPlayer) {
            if (states.containsKey(character) && !enabled(character)) reset(character)
            CartShoppingTurn.update(character)
        }
    }

    /** Death/menu cleanup discards pending state and releases only our own variables. */
    @JvmStatic
    fun reset(player: IsoPlayer?) {
        CartMotionSync.reset(player)
        CartShoppingTurn.reset(player)
        CartLegPace.cancelBrake(player, true)
        states.remove(player)
        val owner = player ?: throw NullPointerException()
        owner.setVariable("ToolkitCartBrace", false)
        owner.setVariable("ToolkitCartWoodBrake", false)
        owner.setVariable("ToolkitCartBrakeSprint", false)
        owner.clearVariable("ToolkitCartLegPace")
        owner.setVariable("ToolkitCartPivot", false)
        owner.setVariable("ToolkitCartStepX", 0f)
        owner.setVariable("ToolkitCartStepY", 0f)
    }
}
