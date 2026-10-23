package net.alexredby.cartlab

import java.lang.ref.WeakReference
import java.util.ArrayList
import java.util.LinkedHashMap
import java.util.concurrent.atomic.AtomicLong
import me.zed_0xff.zombie_buddy.Patch
import net.alexredby.cartlab.LeaseControl.LEASE_CONTROL
import net.alexredby.cartlab.LeaseControl.LeaseCommandIngress
import net.alexredby.cartlab.LeaseControl.LeaseTransport
import net.alexredby.cartlab.LeaseControl.leaseControlCurrent
import net.alexredby.cartlab.LeaseControl.leaseControlFailed
import net.alexredby.cartlab.LeaseControl.leaseControlServerReceipt
import net.alexredby.cartlab.LeaseControl.leaseControlValidatedServerScope
import net.alexredby.cartlab.Multiplayer.mpJsonString
import net.alexredby.cartlab.Multiplayer.timelineError
import net.alexredby.cartlab.NativeTime.NativeWeakMap
import net.alexredby.cartlab.NativeTime.nativeTimeIdentity
import net.alexredby.cartlab.NativeTime.nativeTimeProcess
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.NetTimedAction
import zombie.core.network.ByteBufferReader
import zombie.core.raknet.UdpConnection
import zombie.inventory.InventoryItem
import zombie.iso.IsoWorld
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.IConnection
import zombie.network.PacketTypes
import zombie.network.fields.character.PlayerID

object ActionAdmission {
    @JvmStatic fun initialize() = Unit

    // Opt-in observation of native server cart transactions. No effects, sends, or state writes.
    @JvmField val ACTION_ADMISSION = "true".equals(System.getenv("PZ_CART_ACTION_ADMISSION"))
    @JvmField @Volatile var actionAdmissionFailed: Boolean = false
    private val actionAdmissionLock = Any()
    private val actionAdmissionSequence = AtomicLong()
    private val actionAdmissions = ArrayList<ActionAdmissionRecord>()
    private val actionAdmissionParsed = NativeWeakMap<Any, ActionAdmissionParsed>()
    private val actionAdmissionScope = ThreadLocal<ActionAdmissionScope>()

    @JvmRecord
    data class ActionAdmissionParsed(val ingress: LeaseCommandIngress, val generation: Long)

    @JvmRecord
    data class ActionAdmissionParseScope(val packet: Any?, val ingress: LeaseCommandIngress?)

    class ActionAdmissionScope(
        val packet: Any?,
        val receipt: ActionAdmissionParsed?,
        val connection: UdpConnection?,
        val previous: ActionAdmissionScope?,
    ) {
        val starts: ArrayList<ActionAdmissionRecord> = ArrayList()
    }

    @JvmRecord
    data class ActionAdmissionBinding(
        val item: InventoryItem?,
        val world: IsoWorldInventoryObject?,
        val refusal: String?,
    )

    class ActionAdmissionRecord {
        lateinit var action: WeakReference<NetTimedAction?>
        lateinit var table: WeakReference<se.krka.kahlua.vm.KahluaTable?>
        lateinit var actor: WeakReference<IsoPlayer?>
        lateinit var connection: WeakReference<UdpConnection?>
        lateinit var item: WeakReference<InventoryItem?>
        lateinit var world: WeakReference<IsoWorldInventoryObject?>
        lateinit var transport: LeaseTransport
        var startGeneration: Long = 0
        var actorEpoch: Long = 0
        var connectionEpoch: Long = 0
        var actionEpoch: Long = 0
        var tableEpoch: Long = 0
        var itemEpoch: Long = 0
        var worldEpoch: Long = 0
        var ingressGeneration: Long = 0
        var parseGeneration: Long = 0
        var cart: Long = 0
        var owner: Int = 0
        var transaction: Int = 0
        var packetType: Int = 0
        var kind: String? = null
        var token: String? = null
        var stage: String? = "pending"
        var reason: String = "native-request-start"
        var nativeState: String? = "Request"
        var bindingRefusal: String? = null
        var sourceValidated: Boolean = false
        var nativeBindingValid: Boolean = false
        var admittedBindingValid: Boolean = false
        var accepted: Boolean = false
        var pendingLogged: Boolean = false
    }

    private fun actionAdmissionError(error: Throwable) {
        actionAdmissionFailed = true
        timelineError(
            IllegalStateException("Native cart admission observation failed: $error", error),
        )
    }

    private fun actionAdmissionEnabled(): Boolean {
        return ACTION_ADMISSION &&
            LEASE_CONTROL &&
            !leaseControlFailed &&
            !actionAdmissionFailed &&
            GameServer.server &&
            !GameClient.client
    }

    @Throws(ReflectiveOperationException::class)
    private fun actionAdmissionField(receiver: Any?, name: String): Any? {
        var cls: Class<*>? = receiver!!.javaClass
        while (cls != null) {
            try {
                val field = cls.getDeclaredField(name)
                field.setAccessible(true)
                return field.get(receiver)
            } catch (absent: NoSuchFieldException) {}

            cls = cls.getSuperclass()
        }
        throw NoSuchFieldException(receiver.javaClass.getName() + "." + name)
    }

    @Throws(ReflectiveOperationException::class)
    private fun actionAdmissionPlayer(action: Any): PlayerID? {
        return actionAdmissionField(action, "playerId") as PlayerID?
    }

    @Throws(ReflectiveOperationException::class)
    private fun actionAdmissionState(action: Any): String? {
        val state = actionAdmissionField(action, "state")
        return if (state == null) "unavailable" else state.toString()
    }

    internal fun actionAdmissionRegistered(
        player: IsoPlayer?,
        connection: UdpConnection?,
    ): Boolean {
        return (player != null &&
            connection != null &&
            player.getOnlineID() >= 0 &&
            !player.isDead() &&
            player.playerIndex >= 0 &&
            player.playerIndex < 4 &&
            connection.getPlayerAt(player.playerIndex) === player &&
            GameServer.IDToPlayerMap.get(player.getOnlineID()) === player &&
            GameServer.getConnectionFromPlayer(player) === connection &&
            GameServer.udpEngine != null &&
            GameServer.udpEngine.getActiveConnection(connection.getConnectedGUID()) === connection)
    }

    private fun actionAdmissionCart(item: InventoryItem?): Boolean {
        if (item == null) return false
        val type = item.getFullType()
        return ("SaucedCarts.ShoppingCart" == type) ||
            ("SaucedWheelbarrow.WheelbarrowWood" == type) ||
            ("SaucedWheelbarrow.WheelbarrowMetal" == type)
    }

    @JvmStatic
    fun actionAdmissionKind(kind: String?): Boolean {
        return ("ToolkitWoodCartPickup" == kind) ||
            ("ToolkitWoodCartSetdown" == kind) ||
            ("ToolkitWoodCartDrop" == kind)
    }

    // Pure admission guard: retirement is absorbing and a token is mandatory.
    @JvmStatic
    fun actionAdmissionCanAccept(
        stage: String?,
        nativeState: String?,
        source: Boolean,
        binding: Boolean,
        queued: Boolean,
        token: String?,
    ): Boolean {
        return ("pending" == stage) &&
            ("Accept" == nativeState) &&
            source &&
            binding &&
            queued &&
            token != null &&
            !token.isEmpty()
    }

    private fun actionAdmissionBinding(
        action: NetTimedAction,
        player: IsoPlayer,
    ): ActionAdmissionBinding {
        val table = action.action
        if (
            table == null ||
                table.rawget("character") !== player ||
                table.rawget("netAction") !== action
        )
            return ActionAdmissionBinding(null, null, "action-table-owner")
        if (!("ToolkitWoodCartPickup" == action.type)) {
            val value = table.rawget("item")
            if (!(value is InventoryItem) || !actionAdmissionCart(value))
                return ActionAdmissionBinding(null, null, "held-item-unresolved")
            if (
                player.getPrimaryHandItem() !== value ||
                    player.getSecondaryHandItem() !== value ||
                    value.getContainer() !== player.getInventory() ||
                    value.getWorldItem() != null
            )
                return ActionAdmissionBinding(value, null, "held-item-binding")
            return ActionAdmissionBinding(value, null, null)
        }
        if (player.getPrimaryHandItem() != null || player.getSecondaryHandItem() != null)
            return ActionAdmissionBinding(null, null, "pickup-hands-occupied")
        val x = table.rawget("squareX")
        val y = table.rawget("squareY")
        val z = table.rawget("squareZ")
        val id = table.rawget("itemId")
        if (
            (!(x is Number) ||
                !(y is Number) ||
                !(z is Number) ||
                !(id is Number) ||
                !actionAdmissionInteger(x.toDouble()) ||
                !actionAdmissionInteger(y.toDouble()) ||
                !actionAdmissionInteger(z.toDouble()) ||
                !actionAdmissionInteger(id.toDouble()))
        )
            return ActionAdmissionBinding(null, null, "pickup-constructor-fields")
        if (IsoWorld.instance == null || IsoWorld.instance.currentCell == null)
            return ActionAdmissionBinding(null, null, "pickup-cell-unavailable")
        val square = IsoWorld.instance.currentCell.getGridSquare(x.toInt(), y.toInt(), z.toInt())
        if (square == null) return ActionAdmissionBinding(null, null, "pickup-square-unavailable")
        val objects = square.getWorldObjects()
        if (objects.size > 256) return ActionAdmissionBinding(null, null, "pickup-square-capacity")
        var found: InventoryItem? = null
        var binding: IsoWorldInventoryObject? = null
        for (world in objects) {
            val item = world.getItem()
            if (item != null && item.getID().toDouble() == id.toDouble()) {
                if (found != null)
                    return ActionAdmissionBinding(null, null, "pickup-item-id-ambiguous")
                if (
                    !actionAdmissionCart(item) ||
                        item.getWorldItem() !== world ||
                        world.getSquare() !== square ||
                        item.getContainer() != null
                )
                    return ActionAdmissionBinding(item, world, "pickup-world-binding")
                found = item
                binding = world
            }
        }
        return if (found == null) ActionAdmissionBinding(null, null, "pickup-item-unresolved")
        else ActionAdmissionBinding(found, binding, null)
    }

    @JvmStatic
    fun actionAdmissionInteger(n: Double): Boolean {
        return n.isFinite() && n == Math.rint(n) && n >= Integer.MIN_VALUE && n <= Integer.MAX_VALUE
    }

    @Throws(ReflectiveOperationException::class)
    private fun actionAdmissionQueued(action: Any): Boolean {
        val field = ActionManager::class.java.getDeclaredField("actions")
        field.setAccessible(true)
        val value = field.get(null)
        if (!(value is Collection<*>))
            throw IllegalStateException("Native ActionManager.actions is not a collection")
        var count = 0
        for (candidate in value) {
            if (++count > 4096)
                throw IllegalStateException("Native action queue observation capacity exceeded")
            if (candidate === action) return true
        }
        return false
    }

    private fun actionAdmissionCurrentBinding(record: ActionAdmissionRecord): Boolean {
        val action = record.action.get()
        val player = record.actor.get()
        if (
            action == null ||
                player == null ||
                action.action !== record.table.get() ||
                !record.kind.equals(action.type)
        )
            return false
        val binding = actionAdmissionBinding(action, player)
        return binding.refusal == null &&
            binding.item != null &&
            binding.item === record.item.get() &&
            binding.world === record.world.get()
    }

    @JvmStatic
    fun actionAdmissionParseEnter(
        packet: Any?,
        reader: ByteBufferReader?,
        connection: IConnection?,
        type: Int,
    ): ActionAdmissionParseScope? {
        if (!actionAdmissionEnabled()) return null
        try {
            actionAdmissionParsed.remove(packet)
            return ActionAdmissionParseScope(
                packet,
                if (connection is UdpConnection) leaseControlServerReceipt(reader, connection, type)
                else null,
            )
        } catch (error: Throwable) {
            actionAdmissionError(error)
            return null
        }
    }

    @JvmStatic
    fun actionAdmissionParseExit(scope: ActionAdmissionParseScope?, failure: Throwable?) {
        if (scope == null) return
        try {
            actionAdmissionParsed.remove(scope.packet)
            if (
                failure == null &&
                    scope.ingress != null &&
                    leaseControlCurrent(scope.ingress.transport, true)
            )
                actionAdmissionParsed.put(
                    scope.packet,
                    ActionAdmissionParsed(scope.ingress, actionAdmissionSequence.incrementAndGet()),
                )
        } catch (error: Throwable) {
            actionAdmissionError(error)
        }
    }

    @JvmStatic
    fun actionAdmissionProcessEnter(
        packet: Any?,
        type: PacketTypes.PacketType?,
        connection: UdpConnection?,
    ): ActionAdmissionScope? {
        if (!actionAdmissionEnabled()) return null
        val previous = actionAdmissionScope.get()
        var valid: ActionAdmissionParsed? = null
        try {
            val receipt: ActionAdmissionParsed?
            synchronized(actionAdmissionParsed) {
                receipt = actionAdmissionParsed.get(packet)
                actionAdmissionParsed.remove(packet)
            }
            if (
                (receipt != null &&
                    type != null &&
                    receipt.ingress.transport.type == type.getId().toInt() &&
                    receipt.ingress.transport.connection.get() === connection &&
                    leaseControlCurrent(receipt.ingress.transport, true))
            )
                valid = receipt
        } catch (error: Throwable) {
            actionAdmissionError(error)
        }

        val scope = ActionAdmissionScope(packet, valid, connection, previous)
        actionAdmissionScope.set(scope)
        return scope
    }

    @JvmStatic
    fun actionAdmissionStartEnter(value: Any?): ActionAdmissionRecord? {
        if (
            !actionAdmissionEnabled() ||
                !(value is NetTimedAction) ||
                !actionAdmissionKind(value.type)
        )
            return null
        try {
            val scope = actionAdmissionScope.get()
            if (
                (scope == null ||
                    scope.receipt == null ||
                    !(scope.packet is zombie.network.packets.NetTimedActionPacket) ||
                    scope.packet.action !== value.action ||
                    !"Request".equals(actionAdmissionState(scope.packet)))
            )
                return null
            val owner = actionAdmissionPlayer(value)
            val packetOwner = actionAdmissionPlayer(scope.packet)
            val player = owner!!.getPlayer()
            val transaction = ((actionAdmissionField(value, "id") as Byte)).toInt()
            if (
                (player == null ||
                    packetOwner == null ||
                    transaction == 0 ||
                    transaction != ((actionAdmissionField(scope.packet, "id") as Byte)).toInt() ||
                    packetOwner.getPlayer() !== player ||
                    owner.getID() != player.getOnlineID() ||
                    packetOwner.getID() != player.getOnlineID() ||
                    packetOwner.getPlayerIndex().toInt() != player.playerIndex ||
                    !actionAdmissionRegistered(player, scope.connection))
            )
                return null
            // Native Action.copyFrom calls PlayerID.set(remotePlayer), resetting its local slot to
            // -1.
            // Only the original parsed wire owner slot identifies the source connection slot.
            val binding = actionAdmissionBinding(value, player)
            val record = ActionAdmissionRecord()
            record.action = WeakReference(value)
            record.table = WeakReference(value.action)
            record.actor = WeakReference(player)
            record.connection = WeakReference(scope.connection)
            record.item = WeakReference(binding.item)
            record.world = WeakReference(binding.world)
            record.transport = scope.receipt.ingress.transport
            record.startGeneration = actionAdmissionSequence.incrementAndGet()
            record.actorEpoch = nativeTimeIdentity(player, true)
            record.connectionEpoch = nativeTimeIdentity(scope.connection, false)
            record.actionEpoch = nativeTimeIdentity(value, false)
            record.tableEpoch = nativeTimeIdentity(value.action, false)
            record.itemEpoch =
                if (binding.item == null) 0 else nativeTimeIdentity(binding.item, false)
            record.worldEpoch =
                if (binding.world == null) 0 else nativeTimeIdentity(binding.world, false)
            record.owner = player.getOnlineID().toInt()
            record.transaction = transaction
            record.kind = value.type
            record.cart = if (binding.item == null) 0L else binding.item.getID().toLong()
            record.ingressGeneration = scope.receipt.ingress.generation
            record.parseGeneration = scope.receipt.generation
            record.packetType = record.transport.type
            record.sourceValidated = true
            record.nativeBindingValid = binding.refusal == null
            record.bindingRefusal = binding.refusal
            synchronized(actionAdmissionLock) {
                if (actionAdmissions.size >= 128)
                    throw IllegalStateException(
                        "Native cart admission registry capacity exceeded; no proof evicted",
                    )
                // A new real invocation is a new lifetime even if native reuses the Java object.
                for (old in actionAdmissions) if (
                    old.action.get() === value && !("terminal" == old.stage)
                )
                    actionAdmissionRetire(old, "native-restart")
                actionAdmissions.add(record)
                scope.starts.add(record)
            }
            return record
        } catch (error: Throwable) {
            actionAdmissionError(error)
            return null
        }
    }

    @JvmStatic
    fun actionAdmissionStartExit(record: ActionAdmissionRecord?, failure: Throwable?) {
        if (record == null) return
        try {
            synchronized(actionAdmissionLock) {
                if (failure != null) actionAdmissionRetire(record, "start-threw")
            }
        } catch (error: Throwable) {
            actionAdmissionError(error)
        }
    }

    // Called after the existing synchronized acknowledgement helper; no registry->Ack lock path.
    @JvmStatic
    fun actionAdmissionAcknowledged(action: Any?, failure: Throwable?) {
        if (!actionAdmissionEnabled() || failure != null) return
        try {
            val loader = ActionAdmission::class.java.classLoader
            val monitor =
                Class.forName(
                    "net.alexredby.pztoolkitjavapatches.ActionAcknowledgements",
                    false,
                    loader,
                )
            check(Thread.holdsLock(monitor)) {
                "Native acknowledgement observation escaped its synchronized facade"
            }
            val cls =
                Class.forName(
                    "net.alexredby.pztoolkitjavapatches.ActionAcknowledgementLogic",
                    false,
                    loader,
                )
            val field = cls.getDeclaredField("tokens")
            field.isAccessible = true
            // The facade's synchronized started() still owns this monitor on advice exit.
            // Read its logic's weak ledger before taking the admission registry lock.
            val raw = (field.get(null) as Map<*, *>).get(action)
            val token = if (raw is String) raw else null
            val scope = actionAdmissionScope.get()
            if (scope == null || scope.receipt == null) return
            synchronized(actionAdmissionLock) {
                for (record in scope.starts) if (
                    record.action.get() === action && ("pending" == record.stage)
                ) {
                    record.token = token
                    actionAdmissionPending(record)
                }
            }
        } catch (error: Throwable) {
            actionAdmissionError(error)
        }
    }

    private fun actionAdmissionPending(record: ActionAdmissionRecord) {
        if (!record.pendingLogged) {
            record.pendingLogged = true
            actionAdmissionLog("pending", record)
        }
    }

    @Throws(ReflectiveOperationException::class)
    private fun actionAdmissionRetire(record: ActionAdmissionRecord, reason: String) {
        if (("terminal" == record.stage)) return
        actionAdmissionPending(record)
        record.stage = "terminal"
        record.reason = reason
        val action = record.action.get()
        record.nativeState = if (action == null) "unavailable" else actionAdmissionState(action)
        record.nativeBindingValid = actionAdmissionCurrentBinding(record)
        actionAdmissionLog("retired", record)
    }

    @JvmStatic
    fun actionAdmissionProcessExit(scope: ActionAdmissionScope?, failure: Throwable?) {
        if (scope == null) return
        try {
            synchronized(actionAdmissionLock) {
                for (record in scope.starts) {
                    actionAdmissionPending(record)
                    if (("terminal" == record.stage)) continue
                    val action = record.action.get()
                    record.nativeState =
                        if (action == null) "unavailable" else actionAdmissionState(action)
                    record.nativeBindingValid = actionAdmissionCurrentBinding(record)
                    val source =
                        actionAdmissionRegistered(record.actor.get(), record.connection.get()) &&
                            leaseControlCurrent(record.transport, true)
                    var freshToken = true
                    for (old in actionAdmissions) if (
                        old != record && record.token != null && record.token.equals(old.token)
                    )
                        freshToken = false
                    if (
                        failure == null &&
                            freshToken &&
                            actionAdmissionCanAccept(
                                record.stage,
                                record.nativeState,
                                source && record.sourceValidated,
                                record.nativeBindingValid,
                                action != null && actionAdmissionQueued(action),
                                record.token,
                            )
                    ) {
                        record.accepted = true
                        record.admittedBindingValid = true
                        record.stage = "accepted"
                        record.reason = "native-accepted"
                        actionAdmissionLog("accepted", record)
                    } else
                        actionAdmissionRetire(
                            record,
                            if (failure != null) "handler-threw"
                            else
                                "admission-refused:" +
                                    (if (record.bindingRefusal != null) record.bindingRefusal
                                    else if (record.token == null) "token-unobserved"
                                    else if (!freshToken) "token-reused"
                                    else if (!source) "source-invalid" else "native-not-accepted"),
                        )
                }
            }
        } catch (error: Throwable) {
            actionAdmissionError(error)
        } finally {
            if (scope.previous == null) actionAdmissionScope.remove()
            else actionAdmissionScope.set(scope.previous)
        }
    }

    @Throws(ReflectiveOperationException::class)
    private fun actionAdmissionRefresh(record: ActionAdmissionRecord, removedReason: String) {
        if (!("accepted" == record.stage)) return
        val action = record.action.get()
        record.nativeState = if (action == null) "unavailable" else actionAdmissionState(action)
        record.nativeBindingValid = actionAdmissionCurrentBinding(record)
        if (("Done" == record.nativeState)) actionAdmissionRetire(record, "completed")
        else if (("Reject" == record.nativeState)) actionAdmissionRetire(record, "rejected")
        else if (!("Accept" == record.nativeState))
            actionAdmissionRetire(record, "native-state-changed")
        else if (
            !actionAdmissionRegistered(record.actor.get(), record.connection.get()) ||
                !leaseControlCurrent(record.transport, true)
        )
            actionAdmissionRetire(record, "actor-invalid")
        else if (action == null || !actionAdmissionQueued(action))
            actionAdmissionRetire(record, removedReason)
        else if (!record.nativeBindingValid) actionAdmissionRetire(record, "item-invalid")
    }

    // Bounded invocation-local pins survive native queue/token removal until its exit observation.
    @JvmStatic
    fun actionAdmissionPin(): ArrayList<Any>? {
        if (!actionAdmissionEnabled()) return null
        try {
            val pins = ArrayList<Any>()
            synchronized(actionAdmissionLock) {
                if (actionAdmissions.size > 128)
                    throw IllegalStateException("Native cart admission pin capacity exceeded")
                for (record in actionAdmissions) if (!("terminal" == record.stage)) {
                    val refs =
                        arrayOf<Any?>(
                            record.action.get(),
                            record.table.get(),
                            record.actor.get(),
                            record.connection.get(),
                            record.item.get(),
                            record.world.get(),
                        )
                    for (ref in refs) if (ref != null) pins.add(ref)
                }
            }
            return pins
        } catch (error: Throwable) {
            actionAdmissionError(error)
            return null
        }
    }

    @JvmStatic
    fun actionAdmissionSweepPinned(pins: ArrayList<Any>?, reason: String) {
        try {
            actionAdmissionSweep(reason)
        } finally {
            java.lang.ref.Reference.reachabilityFence(pins)
        }
    }

    @JvmStatic
    fun actionAdmissionSweep(reason: String) {
        if (!actionAdmissionEnabled()) return
        try {
            synchronized(actionAdmissionLock) {
                for (record in actionAdmissions) actionAdmissionRefresh(record, reason)
            }
        } catch (error: Throwable) {
            actionAdmissionError(error)
        }
    }

    @JvmStatic
    fun actionAdmissionDisconnected(connection: UdpConnection?) {
        if (!actionAdmissionEnabled()) return
        try {
            synchronized(actionAdmissionLock) {
                for (record in actionAdmissions) if (
                    record.connection.get() === connection && !("terminal" == record.stage)
                )
                    actionAdmissionRetire(record, "disconnect")
            }
        } catch (error: Throwable) {
            actionAdmissionError(error)
        }
    }

    private fun actionAdmissionSnapshot(
        record: ActionAdmissionRecord,
    ): LinkedHashMap<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        result.put("protocol", 1)
        result.put("process", nativeTimeProcess)
        result.put(
            "sourceSession",
            nativeTimeProcess +
                ":" +
                record.connectionEpoch +
                ":" +
                java.lang.Long.toUnsignedString(record.transport.guid),
        )
        result.put("owner", record.owner)
        result.put("actorEpoch", record.actorEpoch)
        result.put("connectionEpoch", record.connectionEpoch)
        result.put("startGeneration", record.startGeneration)
        result.put("actionEpoch", record.actionEpoch)
        result.put("tableEpoch", record.tableEpoch)
        result.put("token", record.token)
        result.put("transaction", record.transaction)
        result.put("kind", record.kind)
        result.put("cart", record.cart)
        result.put("itemEpoch", record.itemEpoch)
        result.put("worldEpoch", record.worldEpoch)
        result.put("stage", record.stage)
        result.put("reason", record.reason)
        result.put("nativeState", record.nativeState)
        result.put("nativeBindingValid", record.nativeBindingValid)
        result.put("admittedBindingValid", record.admittedBindingValid)
        result.put("accepted", record.accepted)
        result.put("sourceValidated", record.sourceValidated)
        result.put("tokenObserved", record.token != null)
        result.put("ingressGeneration", record.ingressGeneration)
        result.put("parseGeneration", record.parseGeneration)
        result.put("packetType", record.packetType)
        result.put("monoNs", System.nanoTime())
        result.put("wallMs", System.currentTimeMillis())
        return result
    }

    private fun actionAdmissionLog(event: String, record: ActionAdmissionRecord) {
        val fields = actionAdmissionSnapshot(record)
        val json = StringBuilder("{\"event\":").append(mpJsonString(event))
        for (entry in fields.entries) {
            json.append(',').append(mpJsonString(entry.key)).append(':')
            val value = entry.value
            json.append(
                if (value is Number || value is Boolean) value else mpJsonString(value as String?),
            )
        }
        System.out.println("[CART_ADMISSION] " + json.append('}'))
    }

    @LuaMethod(name = "cartActionAdmission", global = true)
    @JvmStatic
    fun cartActionAdmission(player: IsoPlayer?): se.krka.kahlua.vm.KahluaTable? {
        if (!actionAdmissionEnabled() || player == null) return null
        try {
            if (
                leaseControlValidatedServerScope() == null ||
                    player.getOnlineID() < 0 ||
                    GameServer.IDToPlayerMap.get(player.getOnlineID()) !== player
            )
                return null
            synchronized(actionAdmissionLock) {
                for (i in actionAdmissions.size - 1 downTo 0) {
                    val record = actionAdmissions.get(i)
                    if (record.actor.get() !== player) continue
                    actionAdmissionRefresh(record, "native-absent")
                    val result = zombie.Lua.LuaManager.platform.newTable()
                    for (entry in actionAdmissionSnapshot(record).entries) {
                        val value = entry.value
                        result.rawset(entry.key, if (value is Number) value.toDouble() else value)
                    }
                    return result
                }
            }
        } catch (error: Throwable) {
            actionAdmissionError(error)
        }

        return null
    }

    @Patch(
        className = "net.alexredby.pztoolkitjavapatches.ActionAcknowledgements",
        methodName = "started",
        warmUp = false,
    )
    object ActionAdmissionToken {
        @Patch.OnExit(onThrowable = Throwable::class, suppress = Throwable::class)
        @JvmStatic
        fun exit(@Patch.Argument(0) action: Any?, @Patch.Thrown failure: Throwable?) {
            ActionAdmission.actionAdmissionAcknowledged(action, failure)
        }
    }

    @Patch(className = "zombie.core.ActionManager", methodName = "disconnectPlayer", warmUp = false)
    object ActionAdmissionDisconnect {
        @Patch.OnEnter
        @JvmStatic
        fun enter(@Patch.Argument(0) connection: UdpConnection?) {
            ActionAdmission.actionAdmissionDisconnected(connection)
        }
    }
}
