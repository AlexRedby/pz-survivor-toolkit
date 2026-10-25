package net.alexredby.pztoolkitjavapatches

import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.util.WeakHashMap
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.network.fields.ContainerID.ContainerType
import zombie.core.raknet.RakNetPeerInterface
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.InventoryContainer
import zombie.iso.IsoWorld
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.IConnection
import zombie.network.PacketTypes.PacketType
import zombie.vehicles.BaseVehicle
import zombie.vehicles.VehicleManager

/** Server sends only: the first native full snapshot subsumes earlier inventory changes. */
object VehicleInventoryOrdering {
    @JvmField val SUPPORTED = arrayOf(
        "network/packets/INetworkPacket" to "616a8d2e86a03952e16c45e756dae12910f637716568a74571defdc1884ce7e9",
        "network/packets/vehicle/VehicleFullUpdatePacket" to "ba52aaae8413854173b305956145dcb15bd0e7c7b7a1a4971da6dfb8e65c9f14",
        "network/packets/AddInventoryItemToContainerPacket" to "ebbd2e60b7430b6478498257cae19f21eb9d3e656bb1f03ac1dfa4422d2947f1",
        "network/packets/RemoveInventoryItemFromContainerPacket" to "9eaceabf11a0fc4b2e0dc843fecfeada2417f76155de03aa059e7dae766fa983",
        "core/raknet/UdpConnection" to "9c9bb471ff0c3dccdd0e52a3bb3c770327d02f0ad262187f950e660b2730e763",
        "core/raknet/RakNetPeerInterface" to "4911885c02c5216e5f7831d3834e3074ef56816dafa1310dca55b15e2a745ed4",
        "core/raknet/UdpEngine" to "385c8fa80a6b24c8a7fe1770cae1e5c9ddb0d23e614297c6c0c05283e51adf36",
        "vehicles/VehicleManager" to "2eabab623bee04ea33cec3d20b0871b6c8202fbfa1d7b1173737dd13666cb9a6",
        "vehicles/BaseVehicle" to "e7ade19e1e6f66450bef2bd37e52b2afccc7377c4e4571d0fa39435ecdb55661",
        "network/fields/ContainerID" to "d7ef29f65c423135d70f829a1381b9e32ce06d68f87ae49de1980bfcf7c0244b",
        "network/fields/vehicle/VehicleAuthorization" to "000ce5a3112736ec1479a1b65a15ec8598acd997ae6974da1b1aecc57ac4bdd7",
        "network/fields/vehicle/VehiclePassengers" to "d94511f6446f018aa3166d51eb721309b88cc54e2b21a640bc319bc042674abb",
        "network/PacketTypes\$PacketType" to "aa6718ed4e2e33b199734c8cfa4b85a64c193ccc307b2cc4deafe18e0a43d5f5",
        "inventory/ItemContainer" to "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96",
        "inventory/types/InventoryContainer" to "891cb2f37a7d13de869edf05909de493a55ef90aa8665368b36bff7fa6b2555e",
    ).all { (name, hash) -> BytecodeSupport.supports("zombie/$name.class", hash) }

    private class Delivery(val id: Short, var full: Boolean = false, var retry: Boolean = false, var revision: Long = 0)
    private class Recipient(val guid: Long, val timestamp: Long) {
        val vehicles = WeakHashMap<BaseVehicle, Delivery>()
    }
    class Scope internal constructor(
        internal val previous: Scope?,
        internal val connection: UdpConnection?,
        internal val type: PacketType?,
        internal val vehicle: BaseVehicle?,
        internal val recipient: Any?,
        @JvmField val coalesce: Boolean,
        internal val revision: Long = 0,
    ) {
        internal var writing = false
        internal var serialized = false
        internal var authorizationStart = -1
        internal var authorizationValid = false
        internal var sent = false
    }
    private val active = ThreadLocal<Scope>()
    private val recipients = WeakHashMap<UdpConnection, Recipient>()
    private var engine = WeakReference<UdpEngine>(null)
    private var cell = WeakReference<Any>(null)
    private var world = WeakReference<Any>(null)
    private var manager = WeakReference<VehicleManager>(null)

    private fun delta(type: PacketType?) = type == PacketType.AddInventoryItemToContainer ||
        type == PacketType.RemoveInventoryItemFromContainer

    private fun vehicle(type: PacketType?, values: Array<Any?>?): BaseVehicle? =
        if (type == PacketType.VehicleFullUpdate && values?.size == 1) values[0] as? BaseVehicle else null

    @Synchronized private fun recipient(connection: UdpConnection): Recipient? {
        val currentEngine = GameServer.udpEngine ?: return null
        val currentWorld = IsoWorld.instance ?: return null
        val currentCell = currentWorld.currentCell ?: return null
        val currentManager = VehicleManager.instance ?: return null
        if (engine.get() !== currentEngine || world.get() !== currentWorld || cell.get() !== currentCell || manager.get() !== currentManager) {
            recipients.clear()
            engine = WeakReference(currentEngine); world = WeakReference(currentWorld)
            cell = WeakReference(currentCell); manager = WeakReference(currentManager)
        }
        if (currentEngine.connections.none { it === connection }) return null
        val guid = connection.getConnectedGUID()
        val timestamp = connection.getLastConnection()
        var result = recipients[connection]
        if (result == null || result.guid != guid || result.timestamp != timestamp) {
            result = Recipient(guid, timestamp)
            recipients[connection] = result
        }
        return result
    }

    private fun scope(udp: UdpConnection?, type: PacketType?, car: BaseVehicle?, supported: Boolean): Scope {
        var recipient: Recipient? = null
        if (supported && GameServer.server && !GameClient.client && udp != null && car != null &&
            car.getId().toInt() >= 0 && VehicleManager.instance?.getVehicleByID(car.getId()) === car)
            recipient = recipient(udp)
        val result = synchronized(this) {
            val delivery = if (recipient != null && car != null) {
                val old = recipient.vehicles[car]
                if (old == null || old.id != car.getId()) Delivery(car.getId()).also { recipient.vehicles[car] = it } else old
            } else null
            var outer = active.get()
            var snapshotInProgress = false
            while (outer != null) {
                if (outer.connection === udp && outer.vehicle === car && outer.type == PacketType.VehicleFullUpdate)
                    snapshotInProgress = true
                outer = outer.previous
            }
            val coalesce = delivery != null && delta(type) && (!delivery.full || snapshotInProgress)
            if (coalesce) {
                // This is an explicit send request, never a query for client visibility.
                val state = VehicleManager.instance.getVehicleState(udp, car)
                state.flags = (state.flags.toInt() or 1).toShort()
                delivery.revision++
                delivery.retry = true
            }
            Scope(active.get(), udp, type, car, recipient, coalesce, delivery?.revision ?: 0)
        }
        active.set(result)
        return result
    }

    /** A nested delta must not overwrite the native buffer owned by its enclosing full send. */
    private fun nestedVehicle(connection: IConnection?, type: PacketType?, values: Array<Any?>?): BaseVehicle? {
        if (!delta(type) || values?.size != 2) return null
        val items = values[1]
        if (items !is InventoryItem && (items !is ArrayList<*> || items.any { it !is InventoryItem })) return null
        val container = values[0] as? ItemContainer ?: return null
        val bag = container.containingItem
        val root = if (bag == null) container else bag.getOutermostContainer() ?: return null
        val car = root.parent as? BaseVehicle ?: return null
        val part = root.vehiclePart ?: return null
        if (root.containingItem != null || part.getVehicle() !== car || part.getItemContainer() !== root ||
            car.getPartByIndex(part.getIndex()) !== part) return null
        if (bag != null && (bag !is InventoryContainer || bag.getWorldItem() != null ||
            root.getItemWithID(bag.getID()) !== bag || bag.getInventory() !== container)) return null
        var outer = active.get()
        while (outer != null) {
            if (outer.connection === connection && outer.vehicle === car && outer.recipient != null &&
                outer.type == PacketType.VehicleFullUpdate) return car
            outer = outer.previous
        }
        return null
    }

    @JvmStatic fun begin(connection: IConnection?, type: PacketType?, values: Array<Any?>?, supported: Boolean): Scope {
        // Every invocation shadows the previous scope, including unrelated/nested native sends.
        val car = try {
            if (!supported) null else if (type == PacketType.VehicleFullUpdate) vehicle(type, values)
            else nestedVehicle(connection, type, values)
        } catch (_: Exception) { null }
        return scope(connection as? UdpConnection, type, car, supported)
    }

    private val outputBuffer by lazy {
        UdpConnection::class.java.getDeclaredField("bb").apply { isAccessible = true }
    }

    /** Native server relays also write packets directly, bypassing INetworkPacket.send. */
    @JvmStatic fun written(connection: IConnection?, type: PacketType?, supported: Boolean): Scope? {
        if (!supported || !GameServer.server || GameClient.client || !delta(type)) return null
        val udp = connection as? UdpConnection ?: return null
        val car = try {
            val original = outputBuffer.get(udp) as ByteBuffer
            val buffer = original.duplicate().order(original.order()).flip()
            if (buffer.remaining() < 17 || buffer.get().toInt() and 255 != 134 || buffer.short != type!!.getId()) return null
            val reader = ByteBufferReader(buffer)
            val kind = reader.getEnum(ContainerType::class.java)
            if (kind != ContainerType.Vehicle && kind != ContainerType.ObjectInVehicle) return null
            reader.getInt(); reader.getInt(); reader.getByte()
            val vehicle = VehicleManager.instance?.getVehicleByID(reader.getShort()) ?: return null
            val part = vehicle.getPartByIndex(reader.getShort().toInt()) ?: return null
            val container = part.getItemContainer() ?: return null
            if (container.parent !== vehicle || container.vehiclePart !== part || container.containingItem != null) return null
            if (kind == ContainerType.ObjectInVehicle) {
                val bag = container.getItemWithID(reader.getInt()) as? InventoryContainer ?: return null
                if (bag.getOutermostContainer() !== container || bag.getInventory().containingItem !== bag) return null
            }
            vehicle
        } catch (_: Exception) { return null }
        val result = scope(udp, type, car, supported)
        if (result.coalesce) {
            try { udp.cancelPacket() } catch (error: Throwable) { end(result, error); throw error }
        }
        return result
    }

    @JvmStatic fun end(scope: Scope?, failure: Throwable?) {
        if (scope == null) return
        try {
            if (scope.type == PacketType.VehicleFullUpdate && scope.recipient is Recipient && scope.vehicle != null) {
                synchronized(this) {
                    if (recipient(scope.connection!!) === scope.recipient &&
                        VehicleManager.instance?.getVehicleByID(scope.vehicle.getId()) === scope.vehicle) {
                        val delivery = scope.recipient.vehicles[scope.vehicle]
                        if (delivery != null && delivery.id == scope.vehicle.getId()) {
                            if (failure == null && scope.serialized && scope.sent) {
                                delivery.full = true; delivery.retry = delivery.revision != scope.revision
                            } else delivery.retry = true
                        }
                    }
                }
            }
        } finally {
            if (scope.previous == null) active.remove() else active.set(scope.previous)
        }
    }

    @JvmStatic fun ordering(connection: UdpConnection, reliability: Int, ordering: Byte): Byte {
        val scope = active.get() ?: return ordering
        if (scope.recipient != null && scope.connection === connection && delta(scope.type) &&
            !scope.coalesce && reliability == 3 && ordering.toInt() == 1) {
            return 0
        }
        return ordering
    }

    @JvmStatic fun writing(value: Boolean, failure: Throwable?) {
        val scope = active.get() ?: return
        if (scope.recipient == null || scope.type != PacketType.VehicleFullUpdate) return
        scope.writing = value
        if (value || failure != null) scope.serialized = false
        if (value) scope.authorizationValid = false
    }

    /** Native authorization catches its own failures, so require its complete fixed-size write. */
    @JvmStatic fun authorization(writer: ByteBufferWriter, finished: Boolean, failure: Throwable?) {
        val scope = active.get() ?: return
        if (!scope.writing) return
        if (!finished) scope.authorizationStart = writer.position()
        else scope.authorizationValid = failure == null && writer.position() - scope.authorizationStart == 6
    }

    /** This is the last write in the fingerprinted full snapshot; an earlier caught failure skips it. */
    @JvmStatic fun passengersWritten(failure: Throwable?) {
        val scope = active.get() ?: return
        if (scope.writing) scope.serialized = scope.authorizationValid && failure == null
    }

    @JvmStatic fun sent(peer: RakNetPeerInterface, bytes: ByteBuffer?, guid: Long, broadcast: Boolean, result: Int, failure: Throwable?) {
        val scope = active.get() ?: return
        val connection = scope.connection ?: return
        if (scope.recipient != null && scope.type == PacketType.VehicleFullUpdate && failure == null &&
            result > 0 && !broadcast && guid == connection.getConnectedGUID() &&
            GameServer.udpEngine?.getPeer() === peer && bytes != null && bytes.limit() >= 3 &&
            bytes.get(0).toInt() and 255 == 134 && bytes.getShort(1) == scope.type.getId()) scope.sent = true
    }

    @JvmStatic @Synchronized fun retry(connection: UdpConnection) {
        val recipient = recipients[connection] ?: return
        if (recipient(connection) !== recipient) return
        for ((car, delivery) in recipient.vehicles) {
            if (delivery.retry && delivery.id == car.getId() &&
                VehicleManager.instance?.getVehicleByID(car.getId()) === car) {
                // Read only an existing native state. sendVehicles clears its flags after send(),
                // so restore FULL at its exit to make a failed first send eligible next tick.
                val state = connection.vehicleStates.get(car.getId()) ?: continue
                state.flags = (state.flags.toInt() or 1).toShort()
            }
        }
    }

    @JvmStatic @Synchronized fun disconnected(guid: Long) {
        recipients.entries.removeIf { it.value.guid == guid }
    }
    @JvmStatic @Synchronized fun deleted(car: BaseVehicle?) {
        if (car != null) for (recipient in recipients.values) recipient.vehicles.remove(car)
    }
}
