import java.lang.reflect.*
import java.util.*
import net.alexredby.cartlab.NativeTime.NativeWeakMap
import net.alexredby.cartlab.ObserverAssociation
import net.alexredby.cartlab.ObserverParams

// Actual native jar plus diagnostic instrumentation, without a game/world/socket.
object ObserverParamsCheck {
    private var testSeedInstalled: Boolean = false
    var seedPending: Boolean = false
    var seedInput: ObserverAssociation.ObserverPacket? = null
    var seedApply: Long = 0
    var seededPending: Any? = null
    private val UNSAFE: sun.misc.Unsafe

    object Agent {
        @JvmStatic
        fun premain(args: String?, instrumentation: java.lang.instrument.Instrumentation?) {
            ObserverParams.observerParamsInstall(instrumentation)
            ObserverParamsCheck.installTestSeed(instrumentation)
        }
    }

    // Test-only load hook: never installed by the normal diagnostic bootstrap.
    @Synchronized
    @JvmStatic
    fun installTestSeed(instrumentation: java.lang.instrument.Instrumentation?) {
        if (testSeedInstalled) return
        net.bytebuddy.agent.builder.AgentBuilder.Default()
            .disableClassFormatChanges()
            .with(net.bytebuddy.agent.builder.AgentBuilder.DescriptionStrategy.Default.POOL_ONLY)
            .with(net.bytebuddy.agent.builder.AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
            .type(net.bytebuddy.matcher.ElementMatchers.named("zombie.ai.State"))
            .transform(
                { builder, type, loader, module, domain ->
                    builder.visit(
                        net.bytebuddy.asm.Advice.to(SeedPendingAdvice::class.java)
                            .on(net.bytebuddy.matcher.ElementMatchers.named("loadFrom")),
                    )
                },
            )
            .installOn(instrumentation)
        testSeedInstalled = true
    }

    object SeedPendingAdvice {
        @net.bytebuddy.asm.Advice.OnMethodExit
        @Throws(Exception::class)
        @JvmStatic
        fun exit(@net.bytebuddy.asm.Advice.Argument(1) actor: zombie.characters.IsoGameCharacter?) {
            if (ObserverParamsCheck.seedPending) ObserverParamsCheck.seed(actor)
        }
    }

    @Throws(Exception::class)
    @JvmStatic
    fun seed(actor: zombie.characters.IsoGameCharacter?) {
        val applyingField = ObserverAssociation::class.java.getDeclaredField("observerApplying")
        applyingField.setAccessible(true)
        val applying =
            (applyingField.get(null) as ThreadLocal<*>).get() as ObserverAssociation.ObserverApply
        check(
            applying != null && applying.input === seedInput,
            "Exact original native apply missing at test seed",
        )
        seedApply = checkNotNull(applying).generation
        val map = raw(actor as Owner)
        val life = inspected(map)
        val snapshot =
            helper("opSnapshot", ObserverParams.OPLife::class.java, java.lang.Boolean.TYPE)!!
                .invoke(null, life, true)
        check(snapshot != null, "Partial native snapshot refused")
        val ctor =
            ObserverParams.OPCommit::class
                .java
                .getDeclaredConstructor(
                    ObserverAssociation.ObserverPacket::class.java,
                    java.lang.Long.TYPE,
                    java.lang.Long.TYPE,
                    ObserverParams.OPSnapshot::class.java,
                )
        ctor.setAccessible(true)
        val source = ctor.newInstance(seedInput, seedApply, life.revision, snapshot)
        val loaded = ObserverParams.OPCommit::class.java.getDeclaredField("loadedParamMask")
        loaded.setAccessible(true)
        loaded.setInt(source, 119)
        val pendingType = Class.forName("net.alexredby.cartlab.ObserverParams\$OPPending")
        val pendingCtor = pendingType.getDeclaredConstructor(ObserverParams.OPCommit::class.java)
        pendingCtor.setAccessible(true)
        seededPending = pendingCtor.newInstance(source)
        val pending = ObserverParams.OPLife::class.java.getDeclaredField("pending")
        pending.setAccessible(true)
        pending.set(life, seededPending)
    }

    class Network : zombie.characters.component.NetworkComponent() {
        override fun isRemote() = true

        override fun updateNetworkAI() = Unit

        override fun getNetworkAI(): zombie.characters.NetworkCharacterAI? =
            (ecsOwnerEntity as Owner).ai
    }

    class AI(owner: Owner) : zombie.characters.NetworkPlayerAI(owner) {
        override fun getRelatedPlayer(): zombie.characters.IsoPlayer =
            character as zombie.characters.IsoPlayer

        override fun getBooleanDebugOptions():
            zombie.debug.options.Multiplayer.DebugFlagsOG.IsoGameCharacterOG? = null
    }

    class Owner : zombie.characters.IsoPlayer(null, null, 0, 0, 0) {
        lateinit var components:
            HashMap<
                Class<out zombie.characters.ecs.ECSComponent>,
                zombie.characters.ecs.ECSComponent,
            >
        lateinit var actions: Stack<zombie.characters.CharacterTimedActions.BaseAction>
        var ai: zombie.characters.NetworkPlayerAI? = null

        override fun getECSComponentMap():
            HashMap<
                Class<out zombie.characters.ecs.ECSComponent>,
                zombie.characters.ecs.ECSComponent,
            > = components

        override fun getCharacterActions():
            Stack<zombie.characters.CharacterTimedActions.BaseAction> = actions

        override fun getX() = 10f

        override fun getY() = 20f

        override fun getZ() = 0f

        override fun getVariableFloat(name: String?, fallback: Float) = fallback

        override fun getNetworkCharacterAI(): zombie.characters.NetworkPlayerAI? = ai

        override fun getPrimaryHandItem(): zombie.inventory.InventoryItem? = null

        override fun getSecondaryHandItem(): zombie.inventory.InventoryItem? = null

        override fun resetModelNextFrame() = Unit

        override fun setHideWeaponModel(value: Boolean) = Unit

        override fun setVariable(
            key: String?,
            value: String?,
        ): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? = null

        override fun setVariable(
            key: String?,
            value: Boolean,
        ): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? = null
    }

    init {
        try {
            val field = sun.misc.Unsafe::class.java.getDeclaredField("theUnsafe")
            field.setAccessible(true)
            UNSAFE = field.get(null) as sun.misc.Unsafe
        } catch (e: Exception) {
            throw ExceptionInInitializerError(e)
        }
    }

    private fun inspected(map: Any?): ObserverParams.OPLife =
        checkNotNull(ObserverParams.observerParamsInspect(map))

    @JvmStatic
    fun check(value: Boolean, message: String?) {
        if (!value) throw AssertionError(message)
    }

    @Throws(Exception::class)
    @JvmStatic
    fun field(receiver: Any?, clazz: Class<*>, name: String): Any? {
        val field = clazz.getDeclaredField(name)
        field.setAccessible(true)
        return field.get(receiver)
    }

    @Throws(Exception::class)
    @JvmStatic
    fun helper(name: String, vararg types: Class<*>): Method {
        val method = ObserverParams::class.java.getDeclaredMethod(name, *types)
        method.setAccessible(true)
        return method
    }

    @Throws(Exception::class)
    @JvmStatic
    fun owner(): Owner {
        val owner = UNSAFE.allocateInstance(Owner::class.java) as Owner
        owner.components = HashMap()
        owner.actions = Stack()
        val component = zombie.characters.component.StateMachineComponent(owner)
        component.setECSOwnerEntity(owner)
        check(owner.getStateMachineComponent() === component, "Native component attachment failed")
        return owner
    }

    @SuppressWarnings("unchecked")
    @Throws(Exception::class)
    @JvmStatic
    fun raw(owner: Owner): MutableMap<zombie.ai.State.Param<*>, Any?> {
        return (field(
                owner.getStateMachineComponent(),
                zombie.characters.component.StateMachineComponent::class.java,
                "stateMachineParams",
            )
                as Map<*, *>)
            .get(zombie.ai.states.PlayerActionsState::class.java)
            as MutableMap<zombie.ai.State.Param<*>, Any?>
    }

    @Throws(Exception::class)
    @JvmStatic
    fun variables(): zombie.network.fields.Variables {
        val vars = zombie.network.fields.Variables()
        val bb = java.nio.ByteBuffer.allocate(256)
        bb.putInt(1)
        zombie.GameWindow.WriteString(bb, "PerformingAction")
        zombie.GameWindow.WriteString(bb, "CartPickup")
        bb.flip()
        vars.parse(zombie.core.network.ByteBufferReader(bb), null)
        check(!bb.hasRemaining(), "Variables parse left bytes")
        return vars
    }

    @JvmStatic
    fun fill(owner: Owner, vars: zombie.network.fields.Variables) {
        owner.set(zombie.ai.states.PlayerActionsState.STAGE, zombie.ai.State.Stage.Enter)
        owner.set(zombie.ai.states.PlayerActionsState.VARIABLES, vars)
        owner.set(zombie.ai.states.PlayerActionsState.PRIMARY, "Cart")
        owner.set(zombie.ai.states.PlayerActionsState.SECONDARY, "")
        owner.set(zombie.ai.states.PlayerActionsState.OVERRIDE, true)
        owner.set(zombie.ai.states.PlayerActionsState.RELOAD_SPEED, 1f)
        owner.set(zombie.ai.states.PlayerActionsState.SITONGROUND, false)
    }

    @Throws(Exception::class)
    @JvmStatic
    fun artificialCommit(life: ObserverParams.OPLife): ObserverParams.OPCommit {
        val snapshot = helper("opSnapshot", ObserverParams.OPLife::class.java).invoke(null, life)
        check(snapshot != null, "Fresh native map failed deep snapshot")
        val constructor =
            ObserverParams.OPCommit::class
                .java
                .getDeclaredConstructor(
                    ObserverAssociation.ObserverPacket::class.java,
                    java.lang.Long.TYPE,
                    java.lang.Long.TYPE,
                    ObserverParams.OPSnapshot::class.java,
                )
        constructor.setAccessible(true)
        val committed = constructor.newInstance(null, 17L, life.revision, snapshot)
        life.committed = committed
        return committed
    }

    @Throws(Exception::class)
    @JvmStatic
    fun unchanged(
        life: ObserverParams.OPLife,
        committed: ObserverParams.OPCommit,
        owner: Owner,
    ): Boolean {
        return helper(
                "opUnchanged",
                ObserverParams.OPLife::class.java,
                ObserverParams.OPCommit::class.java,
                zombie.characters.IsoGameCharacter::class.java,
            )!!
            .invoke(null, life, committed, owner) as Boolean
    }

    @Throws(Exception::class)
    @JvmStatic
    fun main(args: Array<String>) {
        var args = args
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        if (args.size >= 2 && args[0].equals("late-load")) {
            val loader = Class.forName("me.zed_0xff.zombie_buddy.Loader")
            val phase = Class.forName("me.zed_0xff.zombie_buddy.Loader\$Phase")
            val mainField = phase.getDeclaredField("MAIN")
            mainField.setAccessible(true)
            val main = mainField.get(null)
            val load =
                loader.getDeclaredMethod(
                    "loadJar",
                    java.nio.file.Path::class.java,
                    String::class.java,
                    String::class.java,
                    phase,
                )
            load.setAccessible(true)
            check(
                load.invoke(
                    null,
                    java.nio.file.Path.of(args[1]),
                    "net.alexredby.cartlab",
                    null,
                    main,
                ) == true,
                "Faithful MAIN phase CartLab load failed",
            )
            args = java.util.Arrays.copyOfRange(args, 2, args.size)
            System.out.println(
                "OBSERVER_PARAMS_LATE_BOOTSTRAP_PASS (Rand initialized by test entry; real Loader.loadJar MAIN before first native actor/map)",
            )
        }

        check(ObserverParams.observerParamsHealthy(), "Premain installer failed")
        if (args.size > 0 && args[0].equals("fail-cleanup")) {
            val parent =
                ObserverParams.observerParamsEnter("check-parent", null, arrayOf<Any?>(Any()))
            val child =
                ObserverParams.observerParamsEnter("check-child", null, arrayOf<Any?>(Any()))
            check(
                ObserverParams.observerParamsEnter(
                    "zombie.ai.State.loadFrom(Ljava/util/Map;Lzombie/characters/IsoGameCharacter;)V",
                    zombie.ai.states.PlayerActionsState.instance(),
                    arrayOf<Any?>(null, "wrong-type"),
                ) == null,
                "Invalid diagnostic entry accepted",
            )
            ObserverParams.observerParamsExit(child, null)
            ObserverParams.observerParamsExit(parent, null)
            check(!ObserverParams.observerParamsHealthy(), "Diagnostic failure not sealed")
            for (name in arrayOf<String?>("opFrames", "opLoads", "opConsumers")) {
                val f = ObserverParams::class.java.getDeclaredField(name)
                f.setAccessible(true)
                check(
                    (f.get(null) as ThreadLocal<*>).get() == null,
                    "Failure retained strong ThreadLocal: " + name,
                )
            }
            System.out.println("OBSERVER_PARAMS_FAIL_CLEANUP_PASS")
            return
        }

        if (args.size > 0 && args[0].equals("pending-default")) {
            if (!testSeedInstalled) {
                val instrumentation =
                    me.zed_0xff.zombie_buddy.Loader::class
                        .java
                        .getDeclaredField("g_instrumentation")
                instrumentation.setAccessible(true)
                installTestSeed(instrumentation.get(null) as java.lang.instrument.Instrumentation)
            }
            val source = owner()
            val action = zombie.characters.CharacterTimedActions.BaseAction(source)
            action.setOverrideHandModelsString("Cart", null, false)
            source.actions.add(action)
            val outgoing = zombie.network.packets.actions.StatePacket()
            outgoing.setData(
                source,
                zombie.ai.states.PlayerActionsState.instance(),
                zombie.ai.State.Stage.Enter,
            )
            val wire =
                field(outgoing, zombie.network.packets.actions.StatePacket::class.java, "params")
                    as zombie.network.PZNetKahluaTableImpl
            val bytes = java.nio.ByteBuffer.allocate(2048)
            wire.save(bytes)
            bytes.flip()
            val parsed = zombie.network.PZNetKahluaTableImpl(LinkedHashMap())
            parsed.load(zombie.core.network.ByteBufferReader(bytes), null)
            val receiver = owner()
            receiver.ai = AI(receiver)
            Network().setECSOwnerEntity(receiver)
            zombie.network.GameClient.client = true
            val packet = zombie.network.packets.actions.StatePacket()
            (field(packet, zombie.network.packets.actions.StatePacket::class.java, "characterId")
                    as zombie.network.fields.character.CharacterID)
                .set(receiver)
            (field(packet, zombie.network.packets.actions.StatePacket::class.java, "state")
                    as zombie.network.fields.StateID)
                .set(zombie.ai.states.PlayerActionsState.instance())
            val stage =
                zombie.network.packets.actions.StatePacket::class.java.getDeclaredField("stage")
            stage.setAccessible(true)
            stage.set(packet, zombie.ai.State.Stage.Enter)
            (field(packet, zombie.network.packets.actions.StatePacket::class.java, "params")
                    as zombie.network.PZNetKahluaTableImpl)
                .delegate
                .putAll(parsed.delegate)
            val tag =
                ObserverAssociation.observerAssociationTag(
                    "1|01234567-89ab-cdef-0123-456789abcdef|1|2|3|4|5|6",
                )
            val ctor =
                ObserverAssociation.ObserverPacket::class
                    .java
                    .getDeclaredConstructor(
                        zombie.network.packets.actions.StatePacket::class.java,
                        zombie.characters.IsoPlayer::class.java,
                        ObserverAssociation.ObserverTag::class.java,
                    )
            ctor.setAccessible(true)
            seedInput = ctor.newInstance(packet, receiver, tag)
            seedInput!!.processed = true
            val records = ObserverAssociation::class.java.getDeclaredField("observerPackets")
            records.setAccessible(true)
            (records.get(null)
                    as
                    NativeWeakMap<
                        zombie.network.packets.actions.StatePacket,
                        ObserverAssociation.ObserverPacket,
                    >)
                .put(packet, checkNotNull(seedInput))
            val applying = ObserverAssociation.observerApplyEnter(packet)
            check(applying != null, "Original apply scope disabled")
            seedApply = checkNotNull(applying).generation
            seedPending = true
            try {
                packet.apply()
            } finally {
                seedPending = false
                ObserverAssociation.observerApplyExit(applying, null)
            }
            check(seededPending != null, "Test-only load hook did not seed partial provenance")
            val defaults = checkNotNull(seededPending).javaClass.getDeclaredField("defaultMask")
            defaults.setAccessible(true)
            check(
                defaults.getInt(seededPending) == 8,
                "Exact native default supplier not witnessed",
            )
            val map = raw(receiver)
            val life = inspected(map)
            check(
                !life.tainted &&
                    map.size == 7 &&
                    "".equals(map.get(zombie.ai.states.PlayerActionsState.SECONDARY)),
                "Native apply default did not materialize empty secondary",
            )
            check(life.committed == null, "Test without a transport created a committed source")
            check(
                checkNotNull(receiver.networkCharacterAI).getAction() != null &&
                    checkNotNull(receiver.networkCharacterAI).getAction().chr === receiver,
                "Native apply did not construct and assign actual BaseAction",
            )
            check(
                ObserverParams.observerParamsHealthy(),
                "Pending native default diagnostic failed",
            )
            System.out.println(
                "OBSERVER_PARAMS_PENDING_DEFAULT_PASS (actual native StatePacket.apply/setParams/defaultSupplier/constructor/setAction; nativeDefaultMask=8; no transport => no boundload)",
            )
            return
        }
        if (args.size > 0 && args[0].equals("null-roundtrip")) {
            val source = owner()
            val action = zombie.characters.CharacterTimedActions.BaseAction(source)
            action.setOverrideHandModelsString("Cart", null, false)
            source.actions.add(action)
            val packet = zombie.network.packets.actions.StatePacket()
            packet.setData(
                source,
                zombie.ai.states.PlayerActionsState.instance(),
                zombie.ai.State.Stage.Enter,
            )
            val outgoing =
                field(packet, zombie.network.packets.actions.StatePacket::class.java, "params")
                    as zombie.network.PZNetKahluaTableImpl
            val sourceMap = raw(source)
            check(
                sourceMap.size == 7 &&
                    sourceMap.containsKey(zombie.ai.states.PlayerActionsState.SECONDARY) &&
                    sourceMap.get(zombie.ai.states.PlayerActionsState.SECONDARY) == null,
                "Native source did not produce present-null secondary",
            )
            check(
                !outgoing.delegate.containsKey("secondary"),
                "Native packet retained null secondary",
            )
            val bytes = java.nio.ByteBuffer.allocate(2048)
            outgoing.save(bytes)
            val end = bytes.position()
            bytes.flip()
            val parsed = zombie.network.PZNetKahluaTableImpl(LinkedHashMap())
            parsed.load(zombie.core.network.ByteBufferReader(bytes), null)
            check(
                bytes.position() == end && !parsed.delegate.containsKey("secondary"),
                "Wire unexpectedly retained secondary",
            )
            val receiver = owner()
            receiver.clear(zombie.ai.states.PlayerActionsState::class.java)
            zombie.ai.states.PlayerActionsState.instance().loadFrom(parsed.delegate, receiver)
            val loaded = raw(receiver)
            val life = inspected(loaded)
            check(
                loaded.size == 6 &&
                    !loaded.containsKey(zombie.ai.states.PlayerActionsState.SECONDARY),
                "Native receiver load inserted omitted secondary",
            )
            check(
                zombie.ai.states.PlayerActionsState.SECONDARY.fromDelegate(parsed.delegate) == null,
                "Native fromDelegate did not accept omitted/null",
            )
            val revision = life.revision
            val value = receiver.get(zombie.ai.states.PlayerActionsState.SECONDARY)
            check(
                value.isEmpty() &&
                    loaded.containsKey(zombie.ai.states.PlayerActionsState.SECONDARY) &&
                    life.revision > revision,
                "Native secondary default transition not observed",
            )
            System.out.println(
                "OBSERVER_PARAMS_NULL_ROUNDTRIP_PASS sourceSlots=7 sourceSecondary=null packetSlots=" +
                    outgoing.delegate.size +
                    " wireSlots=" +
                    parsed.delegate.size +
                    " receiverLoadedSlots=6 fromDelegate=null consumerSecondary=emptyString consumerSlots=" +
                    loaded.size +
                    " defaultRevisionAdvanced=true",
            )
            return
        }
        val first = owner()
        var vars = variables()
        fill(first, vars)
        val map = raw(first)
        val life = inspected(map)
        check(life != null && !life.tainted, "Native lambda birth or allowed getter path lost")
        check(map.size == 7, "Native fill lacks seven distinct params")
        var committed = artificialCommit(life)
        check(unchanged(life, committed, first), "Fresh committed value identities not retained")
        var before = life.revision
        first.set(zombie.ai.states.PlayerActionsState.PRIMARY, "Cart")
        check(
            life.revision > before && life.committed == null && !unchanged(life, committed, first),
            "Same-value native Param.set failed invalidation",
        )
        committed = artificialCommit(life)
        before = life.revision
        first.remove(zombie.ai.states.PlayerActionsState.PRIMARY)
        check(
            life.revision > before && life.committed == null,
            "Native Param.remove failed invalidation",
        )
        first.set(zombie.ai.states.PlayerActionsState.PRIMARY, "Cart")
        first.remove(zombie.ai.states.PlayerActionsState.SITONGROUND)
        before = life.revision
        check(!first.get(zombie.ai.states.PlayerActionsState.SITONGROUND), "Native default changed")
        check(
            life.revision > before &&
                map.containsKey(zombie.ai.states.PlayerActionsState.SITONGROUND),
            "Native inserting Param.get failed invalidation",
        )
        committed = artificialCommit(life)
        before = life.revision
        first.get(zombie.ai.states.PlayerActionsState.SITONGROUND)
        check(
            life.revision == before && unchanged(life, committed, first),
            "Existing Param.get invalidated unchanged map",
        )
        var nested =
            inspected(field(vars, zombie.network.fields.Variables::class.java, "variables"))
        check(nested != null && !nested.tainted, "Variables constructor birth lost")
        before = nested.revision
        vars.clear()
        check(
            nested.revision > before && !unchanged(life, committed, first),
            "Direct native Variables.clear failed invalidation",
        )
        // An untrusted map return permits all mutation routes, including same-value restoration.
        vars = variables()
        fill(first, vars)
        committed = artificialCommit(life)
        val escaped = first.getStateMachineParams(zombie.ai.states.PlayerActionsState::class.java)
        check(
            life.tainted && !unchanged(life, committed, first),
            "External params getter did not permanently taint",
        )
        escaped.put(zombie.ai.states.PlayerActionsState.PRIMARY, "Cart")
        first.clear(zombie.ai.states.PlayerActionsState::class.java)
        fill(first, variables())
        check(
            life.tainted &&
                helper("opSnapshot", ObserverParams.OPLife::class.java).invoke(null, life) == null,
            "Clear/refill healed escaped params map",
        )
        val second = owner()
        vars = variables()
        fill(second, vars)
        val secondLife = inspected(raw(second))
        committed = artificialCommit(secondLife)
        val nestedMap = vars.get()
        nested = inspected(nestedMap)
        check(
            nested.tainted && !unchanged(secondLife, committed, second),
            "Nested mutable map escape failed taint",
        )
        nestedMap.replaceAll({ key, value -> value })
        vars.clear()
        check(nested.tainted, "Native clear healed nested escape")
        val third = owner()
        vars = variables()
        fill(third, vars)
        val thirdLife = inspected(raw(third))
        before = thirdLife.revision
        val incoming = LinkedHashMap<Any?, Any?>()
        incoming.put("primary", "Other")
        zombie.ai.states.PlayerActionsState.instance().loadFrom(incoming, third)
        check(
            thirdLife.revision > before && thirdLife.committed == null && !thirdLife.tainted,
            "Untagged native load did not invalidate",
        )
        // Missing native map birth is never adopted from a later getter.
        val foreign =
            UNSAFE.allocateInstance(zombie.network.fields.Variables::class.java)
                as zombie.network.fields.Variables
        val f = zombie.network.fields.Variables::class.java.getDeclaredField("variables")
        f.setAccessible(true)
        val preexisting = HashMap<String?, String?>()
        f.set(foreign, preexisting)
        check(
            foreign.get() === preexisting && inspected(preexisting).tainted,
            "Preexisting Variables map adopted without birth",
        )
        check(
            ObserverParams.observerParamsHealthy(),
            "Monitoring failed during native regression checks",
        )
        System.out.println(
            "OBSERVER_PARAMS_CHECK_PASS (native births, seven parameters, same-value set, remove, inserting/read-only get, untagged load, direct nested clear, permanent outer/nested escape, unknown birth)",
        )
    }
}
