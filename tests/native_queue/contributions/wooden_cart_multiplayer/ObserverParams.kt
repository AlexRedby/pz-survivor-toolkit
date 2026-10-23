package net.alexredby.cartlab

import java.lang.ref.WeakReference
import java.util.IdentityHashMap
import java.util.LinkedHashMap
import net.alexredby.cartlab.Multiplayer.mpJsonString
import net.alexredby.cartlab.NativeTime.NativeWeakMap
import net.alexredby.cartlab.NativeTime.nativeTimeIdentity
import net.alexredby.cartlab.NativeTime.nativeTimeProcess
import net.alexredby.cartlab.ObserverAssociation.OBSERVER_ASSOCIATION
import net.alexredby.cartlab.ObserverAssociation.ObserverPacket
import net.alexredby.cartlab.ObserverAssociation.observerApplying
import net.alexredby.cartlab.ObserverAssociation.observerParamsConsumed
import net.alexredby.cartlab.ObserverAssociation.observerSequence
import net.alexredby.cartlab.ObserverAssociation.observerTransport
import zombie.ai.State
import zombie.ai.states.PlayerActionsState
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.characters.component.StateMachineComponent
import zombie.network.fields.Variables

object ObserverParams {
    @JvmStatic fun initialize() = Unit

    // DIAGNOSTIC ONLY. Install at normal mod load before fixture actors; never substitutes a native
    // collection or gameplay value.
    private val opMaps = NativeWeakMap<Any, OPLife>()
    private val opVariables = NativeWeakMap<Any, OPLife>()
    private val opComponents = NativeWeakMap<Any, WeakReference<IsoGameCharacter>>()
    private val opActors = NativeWeakMap<IsoGameCharacter, OPLife>()
    private val opFrames = ThreadLocal<OPFrame>()
    private val opLoads = ThreadLocal<OPLoad>()
    private val opConsumers = ThreadLocal<OPConsumer>()
    @Volatile private var opInstalled = false
    @Volatile private var opFailed = false
    private const val OP_ACTOR = "Lzombie/characters/IsoGameCharacter;"
    private const val OP_STAGE = "Lzombie/ai/State\$Stage;"

    class OPLife(
        map: Any?,
        component: Any?,
        actor: IsoGameCharacter?,
        variables: Any?,
        var tainted: Boolean,
    ) {
        val epoch = observerSequence.incrementAndGet()
        internal val map = WeakReference(map)
        internal val component = WeakReference(component)
        internal val variables = WeakReference(variables)
        internal val actor = WeakReference(actor)
        var revision = 0L
        var reason = "birth"
        var committed: OPCommit? = null
        internal var pending: OPPending? = null
    }

    class OPFrame(
        val method: String,
        val self: Any?,
        val args: Array<Any?>,
        val previous: OPFrame?,
    ) {
        internal var invalidated = false
        internal var nativeDefault = false
    }

    class OPLoad(
        val frame: OPFrame,
        val previous: OPLoad?,
        val actor: IsoGameCharacter,
        val input: ObserverPacket?,
        val apply: Long,
    ) {
        val loaded = IdentityHashMap<State.Param<*>, Any?>()
    }

    class OPSnapshot(
        val values: IdentityHashMap<State.Param<*>, Any?>,
        variables: Variables,
        val nested: OPLife,
    ) {
        val variables = WeakReference(variables)
        val nestedRevision = nested.revision
        var mask = 0
        var slots = 0
        val keys = ArrayList<String>()
        val texts = ArrayList<String>()
    }

    class OPCommit(
        val input: ObserverPacket?,
        val apply: Long,
        val revision: Long,
        val snapshot: OPSnapshot,
    ) {
        var loadedParamMask = 127
        var nativeDefaultMask = 0
        var defaultConsumerGeneration = 0L
    }

    class OPPending(val source: OPCommit) {
        val loadedMask = source.snapshot.mask
        var revision = source.revision
        var defaultMask = 0
    }

    class OPConsumer(
        val frame: OPFrame,
        val previous: OPConsumer?,
        val actor: IsoGameCharacter,
        val life: OPLife?,
    ) {
        val generation = observerSequence.incrementAndGet()
        internal val pending = life?.pending
        val committed = life?.committed ?: pending?.source
        internal var original =
            pending != null &&
                observerApplying.get()?.let {
                    it.input === pending.source.input && it.generation == pending.source.apply
                } == true
        var reads = 0
        var nestedRead = false
        var invalid = false
        var constructed: BaseAction? = null
        var assigned: BaseAction? = null
    }

    private fun opEnabled(): Boolean {
        return OBSERVER_ASSOCIATION && !opFailed
    }

    private fun opFail(error: Throwable) {
        synchronized(Main::class.java) {
            opFailed = true
            opFrames.remove()
            opLoads.remove()
            opConsumers.remove()
            System.err.println(
                "[CART_OBSERVER_PARAMS] {\"event\":\"params-error\",\"protocol\":1,\"success\":false,\"bound\":false,\"reason\":" +
                    mpJsonString(error.toString()) +
                    "}",
            )
        }
    }

    private fun opLog(
        event: String?,
        life: OPLife?,
        input: OPCommit?,
        consumer: OPConsumer?,
        reason: String,
        success: Boolean,
        bound: Boolean,
    ) {
        val fields = LinkedHashMap<String, Any?>()
        val actor = if (life == null) null else life.actor.get()
        val record = if (input == null) null else input.input
        val snapshot = if (input == null) null else input.snapshot
        fields.put("protocol", 1)
        fields.put("process", nativeTimeProcess)
        fields.put(
            "mapKind",
            if (life == null) "none"
            else if (life.variables.get() == null) "params" else "variables",
        )
        fields.put("actorEpoch", if (actor == null) 0 else nativeTimeIdentity(actor, true))
        fields.put("mapEpoch", if (life == null) 0 else life.epoch)
        fields.put("revision", if (life == null) 0 else life.revision)
        fields.put(
            "variablesEpoch",
            if (snapshot == null)
                (if (life == null) 0 else nativeTimeIdentity(life.variables.get(), false))
            else nativeTimeIdentity(snapshot.variables.get(), false),
        )
        fields.put(
            "variablesMapEpoch",
            if (snapshot == null)
                (if (life == null || life.variables.get() == null) 0 else life.epoch)
            else snapshot.nested.epoch,
        )
        fields.put(
            "variablesRevision",
            if (snapshot == null)
                (if (life == null || life.variables.get() == null) 0 else life.revision)
            else snapshot.nested.revision,
        )
        fields.put("packetEpoch", if (record == null) 0 else record.epoch)
        fields.put("applyGeneration", if (input == null) 0 else input.apply)
        fields.put("consumeGeneration", if (consumer == null) 0 else consumer.generation)
        fields.put("stateTag", if (record == null) "" else record.tag.text)
        fields.put("sourceLife", if (record == null) "" else record.tag.life)
        fields.put("loadedParamMask", if (input == null) 0 else input.loadedParamMask)
        fields.put("nativeDefaultMask", if (input == null) 0 else input.nativeDefaultMask)
        fields.put(
            "defaultConsumerGeneration",
            if (input == null) 0 else input.defaultConsumerGeneration,
        )
        fields.put(
            "actionEpoch",
            if (consumer == null) 0 else nativeTimeIdentity(consumer.assigned, false),
        )
        fields.put("success", success)
        fields.put("bound", bound)
        fields.put("reason", reason)
        fields.put("monoNs", System.nanoTime())
        val json = StringBuilder("{\"event\":").append(mpJsonString(event))
        for (entry in fields.entries) {
            val value = entry.value
            json
                .append(',')
                .append(mpJsonString(entry.key))
                .append(':')
                .append(
                    if (value is Number || value is Boolean) value
                    else mpJsonString(value as String),
                )
        }
        System.out.println("[CART_OBSERVER_PARAMS] " + json.append('}'))
    }

    private fun opName(owner: String, method: String, descriptor: String): String {
        return owner + "." + method + descriptor
    }

    // Caller identity only; original bytecode offsets are deliberately not compared after Advice
    // inlining.
    private fun opCaller(): String {
        return StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE)
            .walk(
                { stream ->
                    stream
                        .filter(
                            { frame ->
                                !frame
                                    .getClassName()
                                    .equals(ObserverParams::class.java.getName()) &&
                                    !frame
                                        .getClassName()
                                        .startsWith(ObserverParams::class.java.getName() + "$")
                            },
                        )
                        .skip(1)
                        .findFirst()
                        .map(
                            { frame ->
                                opName(
                                    frame.getClassName(),
                                    frame.getMethodName(),
                                    frame.getDescriptor(),
                                )
                            },
                        )
                        .orElse("")
                },
            )
    }

    private fun opMethod(
        actual: String,
        owner: String,
        method: String,
        descriptor: String,
    ): Boolean {
        return actual.equals(opName(owner, method, descriptor))
    }

    private fun opParams(): Array<State.Param<*>> {
        return arrayOf<State.Param<*>>(
            PlayerActionsState.STAGE,
            PlayerActionsState.VARIABLES,
            PlayerActionsState.PRIMARY,
            PlayerActionsState.SECONDARY,
            PlayerActionsState.OVERRIDE,
            PlayerActionsState.RELOAD_SPEED,
            PlayerActionsState.SITONGROUND,
        )
    }

    private fun opUnknown(
        map: Any?,
        component: Any?,
        actor: IsoGameCharacter?,
        variables: Any?,
    ): OPLife {
        var life = opMaps.get(map)
        if (life == null) {
            life = OPLife(map, component, actor, variables, true)
            life.reason = "unknown-birth"
            life.revision = observerSequence.incrementAndGet()
            opMaps.put(map, life)
            opLog("params-escape", life, null, null, "unknown-birth", true, false)
        }
        return life
    }

    private fun opInvalidate(life: OPLife?, reason: String, escape: Boolean) {
        if (life == null) return
        val old = life.committed
        val frame = opFrames.get()
        val consumer = opConsumers.get()
        val defaultWrite =
            !escape &&
                reason.startsWith("Param.get-default:") &&
                frame != null &&
                frame.nativeDefault &&
                consumer != null &&
                consumer.original &&
                consumer.pending != null &&
                life.pending === consumer.pending
        life.revision = observerSequence.incrementAndGet()
        life.reason = reason
        life.committed = null
        if (defaultWrite) life.pending!!.revision = life.revision else life.pending = null
        val newlyTainted = escape && !life.tainted
        val alreadyTainted = life.tainted
        life.tainted = life.tainted or escape
        if (
            consumer != null &&
                (consumer.life === life ||
                    consumer.committed != null && consumer.committed.snapshot.nested === life) &&
                !defaultWrite
        )
            consumer.invalid = true
        if (!alreadyTainted || old != null || newlyTainted)
            opLog(
                if (escape) "params-escape" else "params-invalidate",
                life,
                old,
                consumer,
                reason,
                true,
                false,
            )
    }

    private fun opBit(param: State.Param<*>): Int {
        val params = opParams()
        for (i in params.indices) if (params[i] === param) return 1 shl i
        return 0
    }

    @Throws(ReflectiveOperationException::class)
    private fun opCanDefault(
        frame: OPFrame,
        life: OPLife?,
        param: State.Param<*>,
        actor: IsoGameCharacter,
    ): Boolean {
        val consumer = opConsumers.get()
        val pending = if (life == null) null else life.pending
        val applying = observerApplying.get()
        val bit = opBit(param)
        if (
            (bit and 12) == 0 ||
                consumer == null ||
                !consumer.original ||
                consumer.invalid ||
                consumer.actor !== actor ||
                consumer.pending !== pending ||
                pending == null ||
                applying == null ||
                applying.input !== pending.source.input ||
                applying.generation != pending.source.apply ||
                pending.revision != life!!.revision ||
                (pending.loadedMask and bit) != 0 ||
                (pending.defaultMask and bit) != 0 ||
                frame.previous !== consumer.frame ||
                !opSnapshotMatches(life, pending.source.snapshot)
        )
            return false
        val field = State.Param::class.java.getDeclaredField("defaultSupplier")
        field.setAccessible(true)
        return frame.args[1] === field.get(param) &&
            opCaller()
                .equals(
                    "zombie.ai.State\$Param.get(Lzombie/characters/IsoGameCharacter;)Ljava/lang/Object;",
                )
    }

    private fun opCurrent(life: OPLife?, actor: IsoGameCharacter?): Boolean {
        return life != null &&
            !life.tainted &&
            life.actor.get() === actor &&
            life.component.get() != null &&
            actor!!.getStateMachineComponent() === life.component.get() &&
            (life.component.get() as StateMachineComponent).getECSOwnerEntity() === actor
    }

    @JvmStatic private fun opSnapshot(life: OPLife?) = opSnapshot(life, false)

    @JvmStatic
    private fun opSnapshot(life: OPLife?, partial: Boolean): OPSnapshot? {
        if (
            life == null ||
                life.tainted ||
                !(life.map.get() is Map<*, *>) ||
                (life.map.get() as Map<*, *>).size < 5 ||
                (life.map.get() as Map<*, *>).size > 7
        )
            return null
        val values = IdentityHashMap<State.Param<*>, Any?>()
        var mask = 0
        for (param in opParams()) {
            val value = (life.map.get() as Map<*, *>).get(param)
            if (!(life.map.get() as Map<*, *>).containsKey(param)) {
                if (!partial || (opBit(param) and 12) == 0) return null
            } else {
                values.put(param, value)
                if (value != null) mask = mask or opBit(param)
            }
        }
        if (values.size != (life.map.get() as Map<*, *>).size) return null
        val value = values.remove(PlayerActionsState.VARIABLES)
        if (!(value is Variables) || value.javaClass !== Variables::class.java) return null
        val nested = opVariables.get(value)
        if (
            nested == null ||
                nested.tainted ||
                !(nested.map.get() is Map<*, *>) ||
                (nested.map.get() as Map<*, *>).size > 64
        )
            return null
        if (
            !(values.get(PlayerActionsState.STAGE) is State.Stage) ||
                !(values.get(PlayerActionsState.OVERRIDE) is Boolean) ||
                !(values.get(PlayerActionsState.RELOAD_SPEED) is Float) ||
                !(values.get(PlayerActionsState.SITONGROUND) is Boolean)
        )
            return null
        for (param in
            arrayOf<State.Param<*>>(PlayerActionsState.PRIMARY, PlayerActionsState.SECONDARY)) if (
            values.get(param) != null && !(values.get(param) is String) ||
                !partial && !(values.get(param) is String)
        )
            return null
        val snapshot = OPSnapshot(values, value, nested)
        snapshot.mask = mask
        snapshot.slots = (life.map.get() as Map<*, *>).size
        for (entry in (nested.map.get() as Map<*, *>).entries) {
            if (!(entry.key is String) || !(entry.value is String)) return null
            snapshot.keys.add((entry.key as String))
            snapshot.texts.add((entry.value as String))
        }
        return snapshot
    }

    private fun opSnapshotMatches(life: OPLife, snapshot: OPSnapshot): Boolean {
        val nested = snapshot.nested
        if (
            life.tainted ||
                nested.tainted ||
                nested.revision != snapshot.nestedRevision ||
                !(life.map.get() is Map<*, *>) ||
                (life.map.get() as Map<*, *>).size != snapshot.slots ||
                (life.map.get() as Map<*, *>).get(PlayerActionsState.VARIABLES) !==
                    snapshot.variables.get()
        )
            return false
        for (param in opParams()) {
            if (param === PlayerActionsState.VARIABLES) continue
            if (
                (life.map.get() as Map<*, *>).containsKey(param) !=
                    snapshot.values.containsKey(param) ||
                    (life.map.get() as Map<*, *>).get(param) !== snapshot.values.get(param)
            )
                return false
        }
        if (
            !(nested.map.get() is Map<*, *>) ||
                (nested.map.get() as Map<*, *>).size != snapshot.keys.size
        )
            return false
        for (entry in (nested.map.get() as Map<*, *>).entries) {
            var found = false
            for (i in 0 until snapshot.keys.size) if (
                entry.key === snapshot.keys.get(i) && entry.value === snapshot.texts.get(i)
            ) {
                found = true
                break
            }
            if (!found) return false
        }
        return true
    }

    @JvmStatic
    private fun opUnchanged(
        life: OPLife?,
        committed: OPCommit?,
        actor: IsoGameCharacter?,
    ): Boolean {
        return committed != null &&
            opCurrent(life, actor) &&
            life!!.committed === committed &&
            life.revision == committed.revision &&
            opSnapshotMatches(life, committed.snapshot)
    }

    @JvmStatic
    fun observerParamsComponent(component: Any?, actor: Any?) {
        synchronized(Main::class.java) {
            if (!opEnabled()) return
            try {
                if (!(actor is IsoGameCharacter))
                    throw IllegalStateException("Component without actor")
                opComponents.put(component, WeakReference(actor))
            } catch (error: Throwable) {
                opFail(error)
            }
        }
    }

    @JvmStatic
    fun observerParamsVariables(variables: Any?) {
        synchronized(Main::class.java) {
            if (!opEnabled()) return
            try {
                val field = Variables::class.java.getDeclaredField("variables")
                field.setAccessible(true)
                val map = field.get(variables)
                if (opMaps.get(map) != null)
                    throw IllegalStateException("Duplicate Variables map birth")
                val life = OPLife(map, null, null, variables, false)
                opMaps.put(map, life)
                opVariables.put(variables, life)
                opLog("params-birth", life, null, null, "native-Variables-birth", true, false)
            } catch (error: Throwable) {
                opFail(error)
            }
        }
    }

    @JvmStatic
    fun observerParamsMapBirth(map: Any?) {
        synchronized(Main::class.java) {
            if (!opEnabled()) return
            try {
                var frame = opFrames.get()
                while (
                    frame != null &&
                        !frame.method.equals(
                            "zombie.characters.component.StateMachineComponent.getStateMachineParams(Ljava/lang/Class;)Ljava/util/Map;",
                        )
                ) frame = frame.previous
                if (
                    frame == null ||
                        frame.args.size != 1 ||
                        frame.args[0] !== PlayerActionsState::class.java
                )
                    return
                val ownerRef = opComponents.get(frame.self)
                val actor = if (ownerRef == null) null else ownerRef.get()
                if (actor == null || opMaps.get(map) != null) {
                    opUnknown(map, frame.self, actor, null)
                    return
                }
                val life = OPLife(map, frame.self, actor, null, false)
                opMaps.put(map, life)
                val previous = opActors.get(actor)
                if (previous != null && previous != life)
                    opInvalidate(previous, "actor-map-replaced", true)
                opActors.put(actor, life)
                opLog("params-birth", life, null, null, "native-lambda-birth", true, false)
            } catch (error: Throwable) {
                opFail(error)
            }
        }
    }

    @JvmStatic
    fun observerParamsEnter(method: String, self: Any?, args: Array<Any?>): OPFrame? {
        synchronized(Main::class.java) {
            if (!opEnabled()) return null
            try {
                val frame = OPFrame(method, self, args, opFrames.get())
                opFrames.set(frame)
                if (
                    method.equals(
                        "zombie.ai.State.loadFrom(Ljava/util/Map;Lzombie/characters/IsoGameCharacter;)V",
                    ) && self === PlayerActionsState.instance()
                ) {
                    val actor = args[1] as IsoGameCharacter
                    val life = opActors.get(actor)
                    opInvalidate(life, "loadFrom", false)
                    val apply = observerApplying.get()
                    var input: ObserverPacket? = null
                    var generation: Long = 0
                    if (apply != null && apply.input != null) {
                        val record = apply.input
                        val packet = record.packet.get()
                        if (
                            packet != null &&
                                record.owner.get() === actor &&
                                packet.getState() === self &&
                                args[0] === ObserverAssociation.observerParams(packet).delegate &&
                                record.processed &&
                                ("Enter" == record.stage) &&
                                observerTransport(record)
                        ) {
                            input = record
                            generation = apply.generation
                        }
                    }
                    opLoads.set(OPLoad(frame, opLoads.get(), actor, input, generation))
                }
                if (
                    method.equals(
                        "zombie.ai.State\$Param.set(Lzombie/characters/IsoGameCharacter;Ljava/lang/Object;)V",
                    ) ||
                        method.equals(
                            "zombie.ai.State\$Param.remove(Lzombie/characters/IsoGameCharacter;)Ljava/lang/Object;",
                        ) ||
                        method.equals(
                            "zombie.ai.State\$Param.get(Lzombie/characters/IsoGameCharacter;Ljava/util/function/Supplier;)Ljava/lang/Object;",
                        )
                ) {
                    val param = self as State.Param<*>
                    if (param.getStateClass() === PlayerActionsState::class.java) {
                        val actor = args[0] as IsoGameCharacter
                        val life = opActors.get(actor)
                        if (method.contains(".set(")) {
                            opInvalidate(life, "Param.set:" + param.getName(), false)
                            frame.invalidated = life != null
                        } else if (method.contains(".remove(")) {
                            opInvalidate(life, "Param.remove:" + param.getName(), false)
                            frame.invalidated = life != null
                        } else if (
                            life != null &&
                                life.map.get() is Map<*, *> &&
                                (life.map.get() as Map<*, *>).get(param) == null
                        ) {
                            frame.nativeDefault = opCanDefault(frame, life, param, actor)
                            opInvalidate(life, "Param.get-default:" + param.getName(), false)
                            frame.invalidated = true
                        }
                    }
                }
                if (
                    method.equals("zombie.characters.IsoGameCharacter.clear(Ljava/lang/Class;)V") &&
                        args[0] === PlayerActionsState::class.java
                )
                    opInvalidate(opActors.get(self as IsoGameCharacter), "clear", false)
                if (
                    method.startsWith("zombie.network.fields.Variables.parse(") ||
                        method.equals("zombie.network.fields.Variables.clear()V")
                )
                    opInvalidate(
                        opVariables.get(self),
                        if (method.contains(".parse(")) "Variables.parse" else "Variables.clear",
                        false,
                    )
                if (
                    method.equals(
                        "zombie.ai.states.PlayerActionsState.setParams(Lzombie/characters/IsoGameCharacter;Lzombie/ai/State\$Stage;)V",
                    ) &&
                        args[1] === State.Stage.Enter &&
                        args[0] is IsoPlayer &&
                        !(args[0] as IsoPlayer).isLocal()
                ) {
                    val consumer =
                        OPConsumer(
                            frame,
                            opConsumers.get(),
                            (args[0] as IsoPlayer),
                            opActors.get((args[0] as IsoPlayer)),
                        )
                    val caller = opCaller()
                    consumer.original =
                        consumer.original and
                            (opMethod(
                                caller,
                                "zombie.network.packets.actions.StatePacket",
                                "apply",
                                "()V",
                            ) &&
                                frame.previous != null &&
                                frame.previous.self === consumer.committed!!.input!!.packet.get())
                    if (
                        !opMethod(
                            caller,
                            "zombie.ai.states.PlayerActionsState",
                            "enter",
                            "(" + OP_ACTOR + ")V",
                        ) &&
                            !opMethod(
                                caller,
                                "zombie.network.packets.actions.StatePacket",
                                "apply",
                                "()V",
                            )
                    )
                        consumer.invalid = true
                    opConsumers.set(consumer)
                    opLog(
                        "params-consume-begin",
                        consumer.life,
                        consumer.committed,
                        consumer,
                        "native-Enter",
                        true,
                        false,
                    )
                }
                return frame
            } catch (error: Throwable) {
                opFail(error)
                return null
            }
        }
    }

    private fun opParamsGetterAllowed(
        caller: String,
        frame: OPFrame,
        self: Any?,
        args: Array<Any?>,
    ): Boolean {
        if (frame == null) return false
        if (self is StateMachineComponent)
            return opMethod(
                caller,
                "zombie.characters.IsoGameCharacter",
                "getStateMachineParams",
                "(Ljava/lang/Class;)Ljava/util/Map;",
            ) &&
                frame.previous != null &&
                frame.previous.self is IsoGameCharacter &&
                frame.previous.self.getStateMachineComponent() === self
        if (self is IsoGameCharacter) {
            if (
                caller.equals(
                    "zombie.ai.State\$Param.get(Lzombie/characters/IsoGameCharacter;Ljava/util/function/Supplier;)Ljava/lang/Object;",
                ) ||
                    caller.equals(
                        "zombie.ai.State\$Param.set(Lzombie/characters/IsoGameCharacter;Ljava/lang/Object;)V",
                    ) ||
                    caller.equals(
                        "zombie.ai.State\$Param.remove(Lzombie/characters/IsoGameCharacter;)Ljava/lang/Object;",
                    )
            )
                return frame.previous != null &&
                    frame.previous.self is State.Param<*> &&
                    frame.previous.self.getStateClass() === args[0] &&
                    frame.previous.args[0] === self
            return (caller.equals(
                "zombie.ai.State.getParams(Lzombie/characters/IsoGameCharacter;)Ljava/util/Map;",
            ) &&
                frame.previous != null &&
                frame.previous.self === PlayerActionsState.instance() &&
                frame.previous.args[0] === self) ||
                (caller.equals("zombie.characters.IsoGameCharacter.clear(Ljava/lang/Class;)V") &&
                    frame.previous != null &&
                    frame.previous.self === self &&
                    frame.previous.args[0] === args[0])
        }
        if (self === PlayerActionsState.instance())
            return (caller.equals(
                "zombie.ai.State.setParams(Lzombie/characters/IsoGameCharacter;Lzombie/ai/State\$Stage;)V",
            ) ||
                caller.equals(
                    "zombie.network.packets.actions.StatePacket.setData([Ljava/lang/Object;)V",
                )) && frame.previous != null
        return false
    }

    @JvmStatic
    fun observerParamsGetter(frame: OPFrame?, result: Any?) {
        synchronized(Main::class.java) {
            if (frame == null || !opEnabled()) return
            try {
                val method = frame.method
                val caller = opCaller()
                if (
                    method.endsWith("getStateMachineParams(Ljava/lang/Class;)Ljava/util/Map;") ||
                        method.equals(
                            "zombie.ai.State.getParams(Lzombie/characters/IsoGameCharacter;)Ljava/util/Map;",
                        )
                ) {
                    val clazz =
                        if (method.contains(".getParams(")) frame.self!!.javaClass
                        else frame.args[0] as Class<*>
                    if (clazz === PlayerActionsState::class.java && result is Map<*, *>) {
                        val actor =
                            if (frame.self is IsoGameCharacter) frame.self
                            else if (frame.args.size > 0 && frame.args[0] is IsoGameCharacter)
                                (frame.args[0] as IsoGameCharacter)
                            else null
                        var life = opMaps.get(result)
                        if (life == null) life = opUnknown(result, null, actor, null)
                        if (!opParamsGetterAllowed(caller, frame, frame.self, frame.args))
                            opInvalidate(life, "params-getter-escape:" + caller, true)
                        val parent = frame.previous
                        if (
                            parent != null &&
                                !parent.invalidated &&
                                parent.self is State.Param<*> &&
                                result is Map<*, *>
                        ) {
                            if (parent.method.contains(".set(")) {
                                opInvalidate(life, "Param.set:" + parent.self.getName(), false)
                                parent.invalidated = true
                            } else if (parent.method.contains(".remove(")) {
                                opInvalidate(life, "Param.remove:" + parent.self.getName(), false)
                                parent.invalidated = true
                            } else if (
                                parent.method.contains(".get(") && result.get(parent.self) == null
                            ) {
                                opInvalidate(
                                    life,
                                    "Param.get-default:" + parent.self.getName(),
                                    false,
                                )
                                parent.invalidated = true
                            }
                        }
                    }
                }
                if (method.equals("zombie.network.fields.Variables.get()Ljava/util/HashMap;")) {
                    var life = opVariables.get(frame.self)
                    if (life == null) {
                        life = opUnknown(result, null, null, frame.self)
                        opVariables.put(frame.self, life)
                    } else if (life.map.get() !== result)
                        opInvalidate(life, "Variables-map-replaced", true)
                    val consumer = opConsumers.get()
                    val allowed =
                        caller.equals(
                            "zombie.ai.states.PlayerActionsState.setParams(Lzombie/characters/IsoGameCharacter;Lzombie/ai/State\$Stage;)V",
                        ) && frame.previous != null && frame.previous.method.equals(caller)
                    if (
                        allowed &&
                            consumer != null &&
                            consumer.committed != null &&
                            consumer.committed.snapshot.variables.get() === frame.self
                    ) {
                        consumer.nestedRead = true
                        if (life != consumer.committed.snapshot.nested) consumer.invalid = true
                    } else if (
                        allowed &&
                            frame.previous.args[0] is IsoGameCharacter &&
                            (frame.previous.args[0] as IsoGameCharacter).isLocal()
                    )
                        opInvalidate(life, "local-Variables-producer", false)
                    else opInvalidate(life, "Variables-getter-escape:" + caller, true)
                }
                if (
                    method.equals(
                        "zombie.ai.State\$Param.get(Lzombie/characters/IsoGameCharacter;Ljava/util/function/Supplier;)Ljava/lang/Object;",
                    )
                ) {
                    val consumer = opConsumers.get()
                    if (frame.nativeDefault) {
                        val pending = if (consumer == null) null else consumer.pending
                        val param = frame.self as State.Param<*>
                        val life = if (consumer == null) null else consumer.life
                        if (
                            pending == null ||
                                checkNotNull(life).pending !== pending ||
                                pending.revision != life.revision ||
                                !(result is String) ||
                                !result.isEmpty() ||
                                !(life.map.get() is Map<*, *>) ||
                                (life.map.get() as Map<*, *>).get(param) !== result
                        ) {
                            opInvalidate(life, "native-default-result-unproven", false)
                        } else {
                            pending.defaultMask = pending.defaultMask or opBit(param)
                            pending.source.snapshot.values.put(param, result)
                            pending.source.snapshot.mask =
                                pending.source.snapshot.mask or opBit(param)
                            pending.source.snapshot.slots =
                                (checkNotNull(life).map.get() as Map<*, *>).size
                        }
                    }
                    if (
                        consumer != null &&
                            frame.args[0] === consumer.actor &&
                            consumer.committed != null
                    ) {
                        val param = frame.self as State.Param<*>
                        val snapshot = consumer.committed.snapshot
                        val expected =
                            if (param === PlayerActionsState.VARIABLES) snapshot.variables.get()
                            else snapshot.values.get(param)
                        if (result !== expected) consumer.invalid = true
                        if (param === PlayerActionsState.SITONGROUND)
                            consumer.reads = consumer.reads or 1
                        else if (param === PlayerActionsState.VARIABLES)
                            consumer.reads = consumer.reads or 2
                        else if (param === PlayerActionsState.OVERRIDE)
                            consumer.reads = consumer.reads or 4
                        else if (param === PlayerActionsState.PRIMARY)
                            consumer.reads = consumer.reads or 8
                        else if (param === PlayerActionsState.SECONDARY)
                            consumer.reads = consumer.reads or 16
                        else if (param === PlayerActionsState.RELOAD_SPEED)
                            consumer.reads = consumer.reads or 32
                    }
                }
            } catch (error: Throwable) {
                opFail(error)
            }
        }
    }

    @JvmStatic
    fun observerParamsExit(frame: OPFrame?, failure: Throwable?) {
        synchronized(Main::class.java) {
            if (frame == null) return
            try {
                if (opEnabled()) {
                    if (
                        frame.nativeDefault &&
                            failure != null &&
                            frame.args.isNotEmpty() &&
                            frame.args[0] is IsoGameCharacter
                    ) {
                        opInvalidate(
                            opActors.get(frame.args[0] as IsoGameCharacter),
                            "native-default-threw",
                            false,
                        )
                    }
                    if (
                        frame.method ==
                            "zombie.ai.State\$Param.set(Lzombie/characters/IsoGameCharacter;Ljava/lang/Object;)V"
                    ) {
                        val load = opLoads.get()
                        if (
                            failure == null &&
                                load != null &&
                                frame.args[0] === load.actor &&
                                frame.previous?.method ==
                                    "zombie.ai.State.genericsHelper(Lzombie/characters/IsoGameCharacter;Lzombie/ai/State\$Param;Ljava/lang/Object;)V"
                        ) {
                            load.loaded[frame.self as State.Param<*>] = frame.args[1]
                        }
                    }
                    val load = opLoads.get()
                    if (load != null && load.frame === frame) {
                        try {
                            val life = opActors.get(load.actor)
                            val snapshot =
                                if (
                                    failure == null &&
                                        load.input != null &&
                                        opCurrent(life, load.actor)
                                )
                                    opSnapshot(life, true)
                                else null
                            var exact = snapshot != null
                            if (exact) {
                                val map = checkNotNull(life).map.get() as Map<*, *>
                                for (param in opParams()) {
                                    val present = map.containsKey(param)
                                    if (
                                        present != load.loaded.containsKey(param) ||
                                            present && load.loaded[param] !== map[param]
                                    )
                                        exact = false
                                }
                            }
                            if (exact) {
                                val nativeLife = checkNotNull(life)
                                val nativeSnapshot = checkNotNull(snapshot)
                                val source =
                                    OPCommit(
                                        checkNotNull(load.input),
                                        load.apply,
                                        nativeLife.revision,
                                        nativeSnapshot,
                                    )
                                source.loadedParamMask = nativeSnapshot.mask
                                when {
                                    nativeSnapshot.mask == 127 -> {
                                        nativeLife.committed = source
                                        opLog(
                                            "params-load",
                                            nativeLife,
                                            source,
                                            null,
                                            "exact-apply-loadFrom",
                                            true,
                                            true,
                                        )
                                    }
                                    nativeSnapshot.mask or 12 == 127 -> {
                                        nativeLife.pending = OPPending(source)
                                        opLog(
                                            "params-load",
                                            nativeLife,
                                            source,
                                            null,
                                            "pending-native-default",
                                            true,
                                            false,
                                        )
                                    }
                                    else ->
                                        opLog(
                                            "params-load",
                                            nativeLife,
                                            null,
                                            null,
                                            "load-unbound",
                                            true,
                                            false,
                                        )
                                }
                            } else
                                opLog(
                                    "params-load",
                                    life,
                                    null,
                                    null,
                                    if (failure != null) "load-threw" else "load-unbound",
                                    failure == null,
                                    false,
                                )
                        } finally {
                            if (load.previous == null) opLoads.remove()
                            else opLoads.set(load.previous)
                        }
                    }
                    val consumer = opConsumers.get()
                    if (consumer != null && consumer.frame === frame) {
                        try {
                            val life = consumer.life
                            val pending = consumer.pending
                            val committed = consumer.committed
                            val assigned = consumer.assigned
                            val constructed = consumer.constructed
                            var originalValid = false
                            if (consumer.original && pending != null) {
                                val applying = observerApplying.get()
                                val nativeLife = checkNotNull(life)
                                originalValid =
                                    failure == null &&
                                        !consumer.invalid &&
                                        nativeLife.pending === pending &&
                                        pending.revision == nativeLife.revision &&
                                        applying != null &&
                                        applying.input === pending.source.input &&
                                        applying.generation == pending.source.apply &&
                                        pending.source.input!!.apply == pending.source.apply &&
                                        observerTransport(pending.source.input) &&
                                        opCurrent(nativeLife, consumer.actor) &&
                                        constructed != null &&
                                        constructed === assigned &&
                                        assigned.chr === consumer.actor &&
                                        consumer.actor.networkCharacterAI != null &&
                                        consumer.actor.networkCharacterAI.action === assigned &&
                                        consumer.reads % 32 == 31 &&
                                        consumer.nestedRead &&
                                        pending.loadedMask or pending.defaultMask == 127 &&
                                        pending.loadedMask and pending.defaultMask == 0 &&
                                        opSnapshotMatches(nativeLife, pending.source.snapshot)
                            }
                            val retained = observerApplying.get() == null
                            val actor = consumer.actor
                            var valid =
                                retained &&
                                    failure == null &&
                                    !consumer.invalid &&
                                    actor is IsoPlayer &&
                                    committed != null &&
                                    assigned != null &&
                                    constructed === assigned &&
                                    assigned.chr === actor &&
                                    actor.networkCharacterAI != null &&
                                    actor.networkCharacterAI.action === assigned &&
                                    consumer.reads % 32 == 31 &&
                                    consumer.nestedRead &&
                                    opUnchanged(life, committed, actor) &&
                                    committed.input!!.apply == committed.apply &&
                                    committed.input!!.applied &&
                                    committed.input!!.processed &&
                                    observerTransport(committed.input)
                            if (valid) {
                                val snapshot = checkNotNull(committed).snapshot
                                for (index in snapshot.keys.indices) {
                                    if (
                                        snapshot.keys[index] == "PerformingAction" &&
                                            snapshot.texts[index] == "Reload" &&
                                            consumer.reads and 32 == 0
                                    )
                                        valid = false
                                }
                            }
                            if (originalValid) {
                                val source = checkNotNull(pending)
                                source.source.nativeDefaultMask = source.defaultMask
                                source.source.defaultConsumerGeneration = consumer.generation
                            }
                            opLog(
                                "params-consume",
                                life,
                                committed,
                                consumer,
                                if (valid) "verified-native-Enter"
                                else if (!retained) "non-retained-apply"
                                else if (failure != null) "consumer-threw" else "consumer-unbound",
                                failure == null,
                                valid,
                            )
                            if (originalValid) {
                                val source = checkNotNull(pending)
                                val nativeLife = checkNotNull(life)
                                val snapshot = opSnapshot(nativeLife)
                                if (snapshot != null) {
                                    val promoted =
                                        OPCommit(
                                            source.source.input,
                                            source.source.apply,
                                            nativeLife.revision,
                                            snapshot,
                                        )
                                    promoted.loadedParamMask = source.loadedMask
                                    promoted.nativeDefaultMask = source.defaultMask
                                    promoted.defaultConsumerGeneration = consumer.generation
                                    nativeLife.pending = null
                                    nativeLife.committed = promoted
                                    opLog(
                                        "params-load",
                                        nativeLife,
                                        promoted,
                                        consumer,
                                        "exact-apply-native-default",
                                        true,
                                        true,
                                    )
                                }
                            } else if (consumer.original && life != null) life.pending = null
                            if (valid) {
                                val nativeCommit = checkNotNull(committed)
                                val nativeLife = checkNotNull(life)
                                observerParamsConsumed(
                                    nativeCommit.input,
                                    actor as IsoPlayer,
                                    checkNotNull(assigned),
                                    nativeCommit.apply,
                                    consumer.generation,
                                    nativeLife.epoch,
                                    nativeLife.revision,
                                )
                            }
                        } finally {
                            if (consumer.previous == null) opConsumers.remove()
                            else opConsumers.set(consumer.previous)
                        }
                    }
                }
            } catch (error: Throwable) {
                opFail(error)
            } finally {
                if (opFailed) {
                    opFrames.remove()
                    opLoads.remove()
                    opConsumers.remove()
                } else if (frame.previous == null) opFrames.remove()
                else opFrames.set(frame.previous)
            }
        }
    }

    @JvmStatic
    fun observerParamsConstructed(action: Any?) {
        synchronized(Main::class.java) {
            if (!opEnabled()) return
            try {
                val consumer = opConsumers.get()
                if (
                    consumer != null &&
                        action is BaseAction &&
                        action.chr === consumer.actor &&
                        opCaller()
                            .equals(
                                "zombie.ai.states.PlayerActionsState.setParams(Lzombie/characters/IsoGameCharacter;Lzombie/ai/State\$Stage;)V",
                            )
                ) {
                    if (consumer.constructed != null) consumer.invalid = true
                    consumer.constructed = action
                }
            } catch (error: Throwable) {
                opFail(error)
            }
        }
    }

    @JvmStatic
    fun observerParamsAssigned(ai: Any?, action: Any?, failure: Throwable?) {
        synchronized(Main::class.java) {
            if (!opEnabled()) return
            try {
                val consumer = opConsumers.get()
                if (
                    consumer != null &&
                        failure == null &&
                        ai === consumer.actor.getNetworkCharacterAI() &&
                        action === consumer.constructed &&
                        opCaller()
                            .equals(
                                "zombie.ai.states.PlayerActionsState.setParams(Lzombie/characters/IsoGameCharacter;Lzombie/ai/State\$Stage;)V",
                            )
                )
                    consumer.assigned = action as BaseAction
            } catch (error: Throwable) {
                opFail(error)
            }
        }
    }

    @JvmStatic
    fun observerParamsInspect(map: Any?): OPLife? {
        synchronized(Main::class.java) {
            return opMaps.get(map)
        }
    }

    @JvmStatic
    fun observerParamsHealthy(): Boolean {
        return opInstalled && !opFailed
    }

    object OPBoundaryAdvice {
        @net.bytebuddy.asm.Advice.OnMethodEnter
        @JvmStatic
        fun enter(
            @net.bytebuddy.asm.Advice.Origin("#t.#m#d") method: String,
            @net.bytebuddy.asm.Advice.This(optional = true) self: Any?,
            @net.bytebuddy.asm.Advice.AllArguments args: Array<Any?>,
        ): OPFrame? {
            return ObserverParams.observerParamsEnter(method, self, args)
        }

        @net.bytebuddy.asm.Advice.OnMethodExit(onThrowable = Throwable::class)
        @JvmStatic
        fun exit(
            @net.bytebuddy.asm.Advice.Enter frame: OPFrame?,
            @net.bytebuddy.asm.Advice.Thrown failure: Throwable?,
        ) {
            ObserverParams.observerParamsExit(frame, failure)
        }
    }

    object OPGetterAdvice {
        @net.bytebuddy.asm.Advice.OnMethodEnter
        @JvmStatic
        fun enter(
            @net.bytebuddy.asm.Advice.Origin("#t.#m#d") method: String,
            @net.bytebuddy.asm.Advice.This self: Any?,
            @net.bytebuddy.asm.Advice.AllArguments args: Array<Any?>,
        ): OPFrame? {
            return ObserverParams.observerParamsEnter(method, self, args)
        }

        @net.bytebuddy.asm.Advice.OnMethodExit(onThrowable = Throwable::class)
        @JvmStatic
        fun exit(
            @net.bytebuddy.asm.Advice.Enter frame: OPFrame?,
            @net.bytebuddy.asm.Advice.Return(
                typing = net.bytebuddy.implementation.bytecode.assign.Assigner.Typing.DYNAMIC,
            )
            result: Any?,
            @net.bytebuddy.asm.Advice.Thrown failure: Throwable?,
        ) {
            if (failure == null) ObserverParams.observerParamsGetter(frame, result)
            ObserverParams.observerParamsExit(frame, failure)
        }
    }

    object OPMapBirthAdvice {
        @net.bytebuddy.asm.Advice.OnMethodExit
        @JvmStatic
        fun exit(@net.bytebuddy.asm.Advice.Return map: Any?) {
            ObserverParams.observerParamsMapBirth(map)
        }
    }

    object OPVariablesBirthAdvice {
        @net.bytebuddy.asm.Advice.OnMethodExit
        @JvmStatic
        fun exit(@net.bytebuddy.asm.Advice.This self: Any?) {
            ObserverParams.observerParamsVariables(self)
        }
    }

    object OPComponentBirthAdvice {
        @net.bytebuddy.asm.Advice.OnMethodExit
        @JvmStatic
        fun exit(
            @net.bytebuddy.asm.Advice.This self: Any?,
            @net.bytebuddy.asm.Advice.Argument(0) actor: Any?,
        ) {
            ObserverParams.observerParamsComponent(self, actor)
        }
    }

    object OPActionBirthAdvice {
        @net.bytebuddy.asm.Advice.OnMethodExit
        @JvmStatic
        fun exit(@net.bytebuddy.asm.Advice.This self: Any?) {
            ObserverParams.observerParamsConstructed(self)
        }
    }

    object OPAssignedAdvice {
        @net.bytebuddy.asm.Advice.OnMethodExit(onThrowable = Throwable::class)
        @JvmStatic
        fun exit(
            @net.bytebuddy.asm.Advice.This self: Any?,
            @net.bytebuddy.asm.Advice.Argument(0) action: Any?,
            @net.bytebuddy.asm.Advice.Thrown failure: Throwable?,
        ) {
            ObserverParams.observerParamsAssigned(self, action, failure)
        }
    }

    @JvmStatic
    fun observerParamsInstall(instrumentation: java.lang.instrument.Instrumentation?) {
        synchronized(Main::class.java) {
            if (!OBSERVER_ASSOCIATION || opInstalled) return
            if (instrumentation == null) {
                opFail(IllegalStateException("Missing native loader Instrumentation"))
                return
            }
            val names =
                arrayOf(
                    "zombie.characters.component.StateMachineComponent",
                    "zombie.characters.IsoGameCharacter",
                    "zombie.ai.State",
                    "zombie.ai.State\$Param",
                    "zombie.ai.states.PlayerActionsState",
                    "zombie.network.fields.Variables",
                    "zombie.characters.CharacterTimedActions.BaseAction",
                    "zombie.characters.NetworkCharacterAI",
                    "zombie.network.packets.actions.StatePacket",
                )
            try {
                for (name in names) Class.forName(
                    name,
                    false,
                    ObserverParams::class.java.classLoader,
                )
                net.bytebuddy.agent.builder.AgentBuilder.Default(
                        net.bytebuddy
                            .ByteBuddy()
                            .ignore(net.bytebuddy.matcher.ElementMatchers.none()),
                    )
                    .disableClassFormatChanges()
                    .with(
                        net.bytebuddy.agent.builder.AgentBuilder.DescriptionStrategy.Default
                            .POOL_ONLY,
                    )
                    .with(
                        net.bytebuddy.agent.builder.AgentBuilder.RedefinitionStrategy
                            .RETRANSFORMATION,
                    )
                    .with(
                        object : net.bytebuddy.agent.builder.AgentBuilder.Listener.Adapter() {
                            override fun onError(
                                name: String,
                                loader: ClassLoader?,
                                module: net.bytebuddy.utility.JavaModule?,
                                loaded: Boolean,
                                error: Throwable,
                            ) {
                                if (name in names)
                                    opFail(IllegalStateException("Params transform $name", error))
                            }
                        },
                    )
                    .type(net.bytebuddy.matcher.ElementMatchers.namedOneOf(*names))
                    .transform { builder, type, _, _, _ ->
                        when (type.name) {
                            "zombie.characters.component.StateMachineComponent" ->
                                builder
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(
                                                OPComponentBirthAdvice::class.java,
                                            )
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.isConstructor<
                                                        net.bytebuddy.description.method.MethodDescription,
                                                    >()
                                                    .and(
                                                        net.bytebuddy.matcher.ElementMatchers
                                                            .takesArguments(1),
                                                    ),
                                            ),
                                    )
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPMapBirthAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.named(
                                                    "lambda\$getStateMachineParams\$0",
                                                ),
                                            ),
                                    )
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPGetterAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.named(
                                                    "getStateMachineParams",
                                                ),
                                            ),
                                    )
                            "zombie.characters.IsoGameCharacter" ->
                                builder
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPGetterAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.named(
                                                    "getStateMachineParams",
                                                ),
                                            ),
                                    )
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPBoundaryAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.named<
                                                        net.bytebuddy.description.method.MethodDescription,
                                                    >(
                                                        "clear",
                                                    )
                                                    .and(
                                                        net.bytebuddy.matcher.ElementMatchers
                                                            .takesArguments(Class::class.java),
                                                    ),
                                            ),
                                    )
                            "zombie.ai.State" ->
                                builder
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPGetterAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.named(
                                                    "getParams",
                                                ),
                                            ),
                                    )
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPBoundaryAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.namedOneOf(
                                                    "setParams",
                                                    "loadFrom",
                                                    "genericsHelper",
                                                ),
                                            ),
                                    )
                            "zombie.ai.State\$Param" ->
                                builder
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPGetterAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.named<
                                                        net.bytebuddy.description.method.MethodDescription,
                                                    >(
                                                        "get",
                                                    )
                                                    .and(
                                                        net.bytebuddy.matcher.ElementMatchers
                                                            .takesArguments(2),
                                                    ),
                                            ),
                                    )
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPBoundaryAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.namedOneOf(
                                                    "set",
                                                    "remove",
                                                ),
                                            ),
                                    )
                            "zombie.ai.states.PlayerActionsState" ->
                                builder.visit(
                                    net.bytebuddy.asm.Advice.to(OPBoundaryAdvice::class.java)
                                        .on(
                                            net.bytebuddy.matcher.ElementMatchers.named(
                                                "setParams",
                                            ),
                                        ),
                                )
                            "zombie.network.fields.Variables" ->
                                builder
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(
                                                OPVariablesBirthAdvice::class.java,
                                            )
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers
                                                    .isConstructor(),
                                            ),
                                    )
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPGetterAdvice::class.java)
                                            .on(net.bytebuddy.matcher.ElementMatchers.named("get")),
                                    )
                                    .visit(
                                        net.bytebuddy.asm.Advice.to(OPBoundaryAdvice::class.java)
                                            .on(
                                                net.bytebuddy.matcher.ElementMatchers.namedOneOf(
                                                    "parse",
                                                    "clear",
                                                ),
                                            ),
                                    )
                            "zombie.characters.CharacterTimedActions.BaseAction" ->
                                builder.visit(
                                    net.bytebuddy.asm.Advice.to(OPActionBirthAdvice::class.java)
                                        .on(
                                            net.bytebuddy.matcher.ElementMatchers.isConstructor<
                                                    net.bytebuddy.description.method.MethodDescription,
                                                >()
                                                .and(
                                                    net.bytebuddy.matcher.ElementMatchers
                                                        .takesArguments(1),
                                                ),
                                        ),
                                )
                            "zombie.characters.NetworkCharacterAI" ->
                                builder.visit(
                                    net.bytebuddy.asm.Advice.to(OPAssignedAdvice::class.java)
                                        .on(
                                            net.bytebuddy.matcher.ElementMatchers.named(
                                                "setAction",
                                            ),
                                        ),
                                )
                            else ->
                                builder.visit(
                                    net.bytebuddy.asm.Advice.to(OPBoundaryAdvice::class.java)
                                        .on(
                                            net.bytebuddy.matcher.ElementMatchers.namedOneOf(
                                                "setData",
                                                "update",
                                                "apply",
                                            ),
                                        ),
                                )
                        }
                    }
                    .installOn(instrumentation)
                opInstalled = true
            } catch (error: Throwable) {
                opFail(error)
            }
        }
    }
}
