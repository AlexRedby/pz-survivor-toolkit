package net.alexredby.pztoolkitjavapatches

import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.util.WeakHashMap
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
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
import zombie.network.fields.ContainerID.ContainerType
import zombie.vehicles.BaseVehicle
import zombie.vehicles.VehicleManager

/** Server sends only: the first native full snapshot subsumes earlier inventory changes. */
object VehicleInventoryOrdering {
    @JvmField
    val SUPPORTED =
        arrayOf(
                "network/packets/INetworkPacket" to
                    "379d43baf329ab04ee27c390b72f19906007a0f296c6932028966e9f8cd00a71",
                "network/packets/vehicle/VehicleFullUpdatePacket" to
                    "273cd0debd5c5b8373643631a653a723246ae0a2e9a0415c2c63013923ba0d0a",
                "network/packets/AddInventoryItemToContainerPacket" to
                    "be172c878be965b2541b0617ffdd5ed0b16a428404912dd739c7a436de68d9f6",
                "network/packets/RemoveInventoryItemFromContainerPacket" to
                    "8be205de3b421010aca57e460d4908be57ae2872b4b6714d1094e01b64fe6b08",
                "core/raknet/UdpConnection" to
                    "9efbe65d4d728cb3b1e7827e4f639bab3aae049f910343c9b9a1c7b4fe228622",
                "core/raknet/RakNetPeerInterface" to
                    "4911885c02c5216e5f7831d3834e3074ef56816dafa1310dca55b15e2a745ed4",
                "core/raknet/UdpEngine" to
                    "0d77da28ee1dda94f9961b09c7d33acb4ad3b19187e37288d5eee0bb2700d0a7",
                "vehicles/VehicleManager" to
                    "7416822e234e27d6bfea815bc84d5abdb386c6671ee26b42c00f1642c481f7e3",
                "vehicles/BaseVehicle" to
                    "354b166db919f8de692a5327b7afd01fefdbfb8021f0c99e2b2b44a3fe606de3",
                "network/fields/ContainerID" to
                    "3123bde915f47f58fa81fb0f49fc1768efcb4db45749fe0d97c4c52dbc731bc0",
                "network/fields/vehicle/VehicleAuthorization" to
                    "000ce5a3112736ec1479a1b65a15ec8598acd997ae6974da1b1aecc57ac4bdd7",
                "network/fields/vehicle/VehiclePassengers" to
                    "d94511f6446f018aa3166d51eb721309b88cc54e2b21a640bc319bc042674abb",
                "network/PacketTypes\$PacketType" to
                    "fe3411ff586ab5cb1c051be844e99fd58b8411712115d44411b46625d70a4116",
                "inventory/ItemContainer" to
                    "19ffefbabfc16ce3b40feb557189c4fbecdb752aa2c96e3daa8b8ec0542185d3",
                "inventory/types/InventoryContainer" to
                    "891cb2f37a7d13de869edf05909de493a55ef90aa8665368b36bff7fa6b2555e",
                "inventory/InventoryItem" to
                    "b45d4438636509d992aaa7b7505ef8323cd898947efc27bf1f7e762951d6643d",
                "vehicles/VehiclePart" to
                    "27febf9f1cbc8c057bf34e400c743f1e19e70638f6553b45f0140d086e329311",
                "vehicles/VehicleIDMap" to
                    "1c803a637228321fb84251664cdd170fa42cd9a9ed53be65392144b5f6824170",
                "vehicles/BaseVehicle\$ServerVehicleState" to
                    "da643712adc463060d93aeb92ed10dc249a597e02ae3cd7629e48be6bd43d91c",
                "core/network/ByteBufferReader" to
                    "1c2731f2a49b57d2ad895069d499705f8492e3cb6ac275a8f1163b4940e370ff",
                "core/network/ByteBufferWriter" to
                    "b8f4a1aeace9d91b7b252965a52afe6dfaa32bd2569fbd875eaf5aeb89470b6a",
                "network/fields/ContainerID\$ContainerType" to
                    "beb8f224ef49c5912ec86f8ea710991148df43a60d81bf4191ccf5ab4bb325e4",
            )
            .all { (name, hash) -> BytecodeSupport.supports("zombie/$name.class", hash) }

    private class Delivery(
        val id: Short,
        var full: Boolean = false,
        var retry: Boolean = false,
        var revision: Long = 0,
    )

    private class Recipient(val guid: Long, val timestamp: Long) {
        val vehicles = WeakHashMap<BaseVehicle, Delivery>()
    }

    class Scope
    internal constructor(
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

    private fun delta(type: PacketType?) =
        type == PacketType.AddInventoryItemToContainer ||
            type == PacketType.RemoveInventoryItemFromContainer

    private fun vehicle(type: PacketType?, values: Array<Any?>?): BaseVehicle? =
        if (type == PacketType.VehicleFullUpdate && values?.size == 1) values[0] as? BaseVehicle
        else null

    @Synchronized
    private fun recipient(connection: UdpConnection): Recipient? {
        val currentEngine = GameServer.udpEngine ?: return null
        val currentWorld = IsoWorld.instance ?: return null
        val currentCell = currentWorld.currentCell ?: return null
        val currentManager = VehicleManager.instance ?: return null
        if (
            engine.get() !== currentEngine ||
                world.get() !== currentWorld ||
                cell.get() !== currentCell ||
                manager.get() !== currentManager
        ) {
            recipients.clear()
            engine = WeakReference(currentEngine)
            world = WeakReference(currentWorld)
            cell = WeakReference(currentCell)
            manager = WeakReference(currentManager)
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

    private fun scope(
        udp: UdpConnection?,
        type: PacketType?,
        car: BaseVehicle?,
        supported: Boolean,
    ): Scope {
        var recipient: Recipient? = null
        if (
            supported &&
                GameServer.server &&
                !GameClient.client &&
                udp != null &&
                car != null &&
                car.getId().toInt() >= 0 &&
                VehicleManager.instance?.getVehicleByID(car.getId()) === car
        )
            recipient = recipient(udp)
        val result =
            synchronized(this) {
                val delivery =
                    if (recipient != null && car != null) {
                        val old = recipient.vehicles[car]
                        if (old == null || old.id != car.getId())
                            Delivery(car.getId()).also { recipient.vehicles[car] = it }
                        else old
                    } else null
                var outer = active.get()
                var snapshotInProgress = false
                while (outer != null) {
                    if (
                        outer.connection === udp &&
                            outer.vehicle === car &&
                            outer.type == PacketType.VehicleFullUpdate
                    )
                        snapshotInProgress = true
                    outer = outer.previous
                }
                val coalesce =
                    delivery != null && delta(type) && (!delivery.full || snapshotInProgress)
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
    private fun nestedVehicle(
        connection: IConnection?,
        type: PacketType?,
        values: Array<Any?>?,
    ): BaseVehicle? {
        if (!delta(type) || values?.size != 2) return null
        val items = values[1]
        if (
            items !is InventoryItem &&
                (items !is ArrayList<*> || items.any { it !is InventoryItem })
        )
            return null
        val container = values[0] as? ItemContainer ?: return null
        val bag = container.containingItem
        val root = if (bag == null) container else bag.getOutermostContainer() ?: return null
        val car = root.parent as? BaseVehicle ?: return null
        val part = root.vehiclePart ?: return null
        if (
            root.containingItem != null ||
                part.getVehicle() !== car ||
                part.getItemContainer() !== root ||
                car.getPartByIndex(part.getIndex()) !== part
        )
            return null
        if (
            bag != null &&
                (bag !is InventoryContainer ||
                    bag.getWorldItem() != null ||
                    root.getItemWithID(bag.getID()) !== bag ||
                    bag.getInventory() !== container)
        )
            return null
        var outer = active.get()
        while (outer != null) {
            if (
                outer.connection === connection &&
                    outer.vehicle === car &&
                    outer.recipient != null &&
                    outer.type == PacketType.VehicleFullUpdate
            )
                return car
            outer = outer.previous
        }
        return null
    }

    @JvmStatic
    fun begin(
        connection: IConnection?,
        type: PacketType?,
        values: Array<Any?>?,
        supported: Boolean,
    ): Scope {
        // Every invocation shadows the previous scope, including unrelated/nested native sends.
        val car =
            try {
                if (!supported) null
                else if (type == PacketType.VehicleFullUpdate) vehicle(type, values)
                else nestedVehicle(connection, type, values)
            } catch (_: Exception) {
                null
            }
        return scope(connection as? UdpConnection, type, car, supported)
    }

    private val outputBuffer by lazy {
        UdpConnection::class.java.getDeclaredField("bb").apply { isAccessible = true }
    }

    /** Inspect completed native writes without forcing packet-enum initialization at startup. */
    @JvmStatic
    fun written(connection: IConnection?, supported: Boolean): Scope? {
        if (!supported || !GameServer.server || GameClient.client) return null
        val udp = connection as? UdpConnection ?: return null
        val type: PacketType
        val car =
            try {
                val original = outputBuffer.get(udp) as ByteBuffer
                val buffer = original.duplicate().order(original.order()).flip()
                if (buffer.remaining() < 17 || buffer.get().toInt() and 255 != 134) return null
                type =
                    when (buffer.short) {
                        PacketType.AddInventoryItemToContainer.getId() ->
                            PacketType.AddInventoryItemToContainer
                        PacketType.RemoveInventoryItemFromContainer.getId() ->
                            PacketType.RemoveInventoryItemFromContainer
                        else -> return null
                    }
                val reader = ByteBufferReader(buffer)
                val kind = reader.getEnum(ContainerType::class.java)
                if (kind != ContainerType.Vehicle && kind != ContainerType.ObjectInVehicle)
                    return null
                reader.getInt()
                reader.getInt()
                reader.getByte()
                val vehicle =
                    VehicleManager.instance?.getVehicleByID(reader.getShort()) ?: return null
                val part = vehicle.getPartByIndex(reader.getShort().toInt()) ?: return null
                val container = part.getItemContainer() ?: return null
                if (
                    container.parent !== vehicle ||
                        container.vehiclePart !== part ||
                        container.containingItem != null
                )
                    return null
                if (kind == ContainerType.ObjectInVehicle) {
                    val bag =
                        container.getItemWithID(reader.getInt()) as? InventoryContainer
                            ?: return null
                    if (
                        bag.getOutermostContainer() !== container ||
                            bag.getInventory().containingItem !== bag
                    )
                        return null
                }
                vehicle
            } catch (_: Exception) {
                return null
            }
        val result = scope(udp, type, car, supported)
        if (result.coalesce) {
            try {
                udp.cancelPacket()
            } catch (error: Throwable) {
                end(result, error)
                throw error
            }
        }
        return result
    }

    @JvmStatic
    fun end(scope: Scope?, failure: Throwable?) {
        if (scope == null) return
        try {
            if (
                scope.type == PacketType.VehicleFullUpdate &&
                    scope.recipient is Recipient &&
                    scope.vehicle != null
            ) {
                synchronized(this) {
                    if (
                        recipient(scope.connection!!) === scope.recipient &&
                            VehicleManager.instance?.getVehicleByID(scope.vehicle.getId()) ===
                                scope.vehicle
                    ) {
                        val delivery = scope.recipient.vehicles[scope.vehicle]
                        if (delivery != null && delivery.id == scope.vehicle.getId()) {
                            if (failure == null && scope.serialized && scope.sent) {
                                delivery.full = true
                                delivery.retry = delivery.revision != scope.revision
                            } else delivery.retry = true
                        }
                    }
                }
            }
        } finally {
            if (scope.previous == null) active.remove() else active.set(scope.previous)
        }
    }

    @JvmStatic
    fun ordering(connection: UdpConnection, reliability: Int, ordering: Byte): Byte {
        val scope = active.get() ?: return ordering
        if (
            scope.recipient != null &&
                scope.connection === connection &&
                delta(scope.type) &&
                !scope.coalesce &&
                reliability == 3 &&
                ordering.toInt() == 1
        ) {
            return 0
        }
        return ordering
    }

    @JvmStatic
    fun writing(value: Boolean, failure: Throwable?) {
        val scope = active.get() ?: return
        if (scope.recipient == null || scope.type != PacketType.VehicleFullUpdate) return
        scope.writing = value
        if (value || failure != null) scope.serialized = false
        if (value) scope.authorizationValid = false
    }

    /** Native authorization catches its own failures, so require its complete fixed-size write. */
    @JvmStatic
    fun authorization(writer: ByteBufferWriter, finished: Boolean, failure: Throwable?) {
        val scope = active.get() ?: return
        if (!scope.writing) return
        if (!finished) scope.authorizationStart = writer.position()
        else
            scope.authorizationValid =
                failure == null && writer.position() - scope.authorizationStart == 6
    }

    /**
     * This is the last write in the fingerprinted full snapshot; an earlier caught failure skips
     * it.
     */
    @JvmStatic
    fun passengersWritten(failure: Throwable?) {
        val scope = active.get() ?: return
        if (scope.writing) scope.serialized = scope.authorizationValid && failure == null
    }

    @JvmStatic
    fun sent(
        peer: RakNetPeerInterface,
        bytes: ByteBuffer?,
        guid: Long,
        broadcast: Boolean,
        result: Int,
        failure: Throwable?,
    ) {
        val scope = active.get() ?: return
        val connection = scope.connection ?: return
        if (
            scope.recipient != null &&
                scope.type == PacketType.VehicleFullUpdate &&
                failure == null &&
                result > 0 &&
                !broadcast &&
                guid == connection.getConnectedGUID() &&
                GameServer.udpEngine?.getPeer() === peer &&
                bytes != null &&
                bytes.limit() >= 3 &&
                bytes.get(0).toInt() and 255 == 134 &&
                bytes.getShort(1) == scope.type.getId()
        )
            scope.sent = true
    }

    @JvmStatic
    @Synchronized
    fun retry(connection: UdpConnection) {
        val recipient = recipients[connection] ?: return
        if (recipient(connection) !== recipient) return
        for ((car, delivery) in recipient.vehicles) {
            if (
                delivery.retry &&
                    delivery.id == car.getId() &&
                    VehicleManager.instance?.getVehicleByID(car.getId()) === car
            ) {
                // Read only an existing native state. sendVehicles clears its flags after send(),
                // so restore FULL at its exit to make a failed first send eligible next tick.
                val state = connection.vehicleStates.get(car.getId()) ?: continue
                state.flags = (state.flags.toInt() or 1).toShort()
            }
        }
    }

    @JvmStatic
    @Synchronized
    fun disconnected(guid: Long) {
        recipients.entries.removeIf { it.value.guid == guid }
    }

    @JvmStatic
    @Synchronized
    fun deleted(car: BaseVehicle?) {
        if (car != null) for (recipient in recipients.values) recipient.vehicles.remove(car)
    }
}
