package zombie.vehicles

import java.nio.ByteBuffer
import java.util.concurrent.locks.ReentrantLock
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.VehicleInventoryOrdering
import net.alexredby.vehicleinventoryfixture.NativeTransport
import org.joml.Quaternionf
import sun.misc.Unsafe
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.RakNetPeerInterface
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.iso.IsoCell
import zombie.iso.IsoWorld
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes.PacketType
import zombie.network.packets.INetworkPacket
import zombie.network.packets.vehicle.VehicleFullUpdatePacket

/** Real cached native packet, snapshot serializer and UdpConnection send path; fake wire only. */
object VehicleInventoryOrderingChecks {
    data class Frame(val bytes: ByteArray, val reliability: Int, val channel: Byte, val guid: Long) {
        val type get() = PacketType.entries[ByteBuffer.wrap(bytes).getShort(1).toInt()]
    }
    private val frames = ArrayList<Frame>()
    private var wireResult = 1
    private var wireFailure: Throwable? = null
    private var duringFull: (() -> Unit)? = null
    private lateinit var unsafe: Unsafe
    private lateinit var engine: UdpEngine
    private lateinit var connection: UdpConnection
    private lateinit var car: BaseVehicle
    private lateinit var container: ItemContainer
    private lateinit var added: InventoryItem
    private lateinit var removed: InventoryItem

    @JvmStatic fun transport(bytes: ByteBuffer, priority: Int, reliability: Int, channel: Byte, guid: Long, broadcast: Boolean): Int {
        wireFailure?.let { throw it }
        verify(!broadcast, "unexpected broadcast")
        val data = ByteArray(bytes.remaining())
        bytes.duplicate().get(data)
        if (wireResult > 0) {
            val frame = Frame(data, reliability, channel, guid)
            frames.add(frame)
            if (frame.type == PacketType.VehicleFullUpdate) duringFull?.let { duringFull = null; it() }
        }
        return wireResult
    }
    private fun verify(value: Boolean, reason: String) { if (!value) throw AssertionError(reason) }
    private fun set(target: Any, type: Class<*>, name: String, value: Any?) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }
    private fun connection(guid: Long): UdpConnection = UdpConnection(engine, guid, 0).also {
        set(it, UdpConnection::class.java, "fullyConnected", true)
        it.setRelevantPos(0, zombie.iso.Vector3(0f, 0f, 0f))
        it.setRelevantRange(10)
        engine.connections.add(it)
    }
    private fun ids(): VehicleIDMap = VehicleManager::class.java.getDeclaredField("idToVehicle").apply { isAccessible = true }.get(VehicleManager.instance) as VehicleIDMap
    private fun vehicle(): BaseVehicle {
        val value = BaseVehicle(null)
        value.vehicleId = ids().allocateID()
        NativeChecks.set(value, "passengers", emptyArray<BaseVehicle.Passenger>())
        NativeChecks.set(value, "wheelInfo", emptyArray<BaseVehicle.WheelInfo>())
        NativeChecks.set(value, "savedRot", Quaternionf())
        NativeChecks.set(value, "physics", unsafe.allocateInstance(zombie.core.physics.CarController::class.java))
        val parts = VehicleParts()
        parts.setOwner(value)
        val part = VehiclePart(value)
        set(part, VehiclePart::class.java, "partId", "GloveBox")
        parts.add(part)
        NativeChecks.set(value, "parts", parts)
        val root = ItemContainer("glovebox", null, value)
        part.setItemContainer(root)
        root.vehiclePart = part
        VehicleManager.instance.registerVehicle(value)
        return value
    }
    private fun add(c: UdpConnection = connection) = INetworkPacket.send(c, PacketType.AddInventoryItemToContainer, container, added)
    private fun remove(c: UdpConnection = connection) = INetworkPacket.send(c, PacketType.RemoveInventoryItemFromContainer, container, removed)
    private fun full(c: UdpConnection = connection, v: BaseVehicle = car) = INetworkPacket.send(c, PacketType.VehicleFullUpdate, v)
    private fun deltaBypass(server: Boolean, client: Boolean, reason: String) {
        GameServer.server = server; GameClient.client = client
        val before = frames.size
        remove()
        verify(frames.size == before + 1 && frames.last().channel.toInt() == 1, reason)
        GameClient.client = false; GameServer.server = true
    }
    private fun coalesced(c: UdpConnection = connection, reason: String) {
        val before = frames.size
        remove(c); add(c)
        verify(frames.size == before, reason + " server=" + GameServer.server + " client=" + GameClient.client + " parent=" + container.parent + " part=" + container.vehiclePart + " id=" + car.getId() + " registered=" + (VehicleManager.instance.getVehicleByID(car.getId()) === car) + " frames=" + frames.drop(before).map { it.type })
    }
    private fun sendVehicles(c: UdpConnection) {
        set(IsoWorld.instance.currentCell, IsoCell::class.java, "vehicles", linkedSetOf(car))
        VehicleManager::class.java.getDeclaredMethod("sendVehicles", UdpConnection::class.java).apply { isAccessible = true }.invoke(VehicleManager.instance, c)
    }
    private fun raw(type: PacketType, c: UdpConnection, root: ItemContainer = container, item: InventoryItem = removed) {
        val packet = c.getPacket(type)
        packet.setData(root, item)
        val writer = c.startPacket()
        type.doPacket(writer)
        packet.write(writer)
        type.send(c)
    }
    private fun snapshot(): ByteArray {
        val bb = ByteBuffer.allocate(100_000)
        val writer = ByteBufferWriter(bb)
        PacketType.VehicleFullUpdate.doPacket(writer)
        VehicleFullUpdatePacket().apply { setData(car); write(writer) }
        return bb.array().copyOf(bb.position())
    }
    @JvmStatic fun main(args: Array<String>) {
        zombie.ZomboidFileSystem.instance.setCacheDir(System.getProperty("pz.test.cache"))
        zombie.ZomboidFileSystem.instance.init()
        zombie.Lua.LuaManager.platform = se.krka.kahlua.j2se.J2SEPlatform()
        zombie.Lua.LuaManager.env = zombie.Lua.LuaManager.platform.newTable()
        zombie.Lua.LuaManager.thread = se.krka.kahlua.vm.KahluaThread(zombie.Lua.LuaManager.platform, zombie.Lua.LuaManager.env)
        zombie.Lua.LuaManager.thread.debugOwnerThread = Thread.currentThread()
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
        verify(VehicleInventoryOrdering.SUPPORTED, "unsupported native fingerprint")
        // Replace only private JNI sendNative before its class loads; real Java Send remains woven.
        verify(NativeTransport::class.java.name.isNotEmpty(), "missing transport fixture")
        NativeTransport.install()
        engine = unsafe.allocateInstance(UdpEngine::class.java) as UdpEngine
        set(engine, UdpEngine::class.java, "connections", ArrayList<UdpConnection>())
        set(engine, UdpEngine::class.java, "connectionMap", HashMap<Long, UdpConnection>())
        val peer = unsafe.allocateInstance(RakNetPeerInterface::class.java) as RakNetPeerInterface
        set(peer, RakNetPeerInterface::class.java, "sendLock", ReentrantLock())
        set(peer, RakNetPeerInterface::class.java, "sendBuf", ByteBuffer.allocateDirect(100_000))
        set(engine, UdpEngine::class.java, "peer", peer)
        GameServer.udpEngine = engine
        GameServer.server = true; GameClient.client = false
        IsoWorld.instance.currentCell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        VehicleManager.instance = VehicleManager()
        connection = connection(421)
        car = vehicle()
        container = car.getPartByIndex(0).getItemContainer()
        added = InventoryItem("Base", "Test", "Test", "Test").apply { id = 1087356724 }
        removed = InventoryItem("Base", "Test", "Test", "Test").apply { id = 541156268 }
        container.items.add(added)
        car.save(ByteBuffer.allocate(100_000), false)
        // Original native writer demonstrates the ordering-channel race.
        for ((type, values) in listOf(
            PacketType.RemoveInventoryItemFromContainer to arrayOf<Any>(container, removed),
            PacketType.AddInventoryItemToContainer to arrayOf<Any>(container, added),
            PacketType.VehicleFullUpdate to arrayOf<Any>(car),
        )) connection.getPacket(type).apply { setData(*values); sendToClient(type, connection) }
        verify(frames.map { it.channel.toInt() } == listOf(1, 1, 0), "native race did not reproduce")
        verify(frames.last().bytes.contentEquals(snapshot()), "native snapshot fixture unstable")
        frames.clear()
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", javaClass.classLoader)
        coalesced(reason = "pre-full inventory changes escaped")
        verify(connection.vehicleStates.get(car.getId()).flags.toInt() and 1 == 1, "coalescing failed to request native full snapshot")
        // The forthcoming snapshot uses the authoritative state at serialization time, not a held delta.
        val later = InventoryItem("Base", "Test", "Test", "Test").apply { id = 1765432109 }
        container.items.add(later)
        val expected = snapshot()
        full()
        verify(frames.size == 1 && frames.single().type == PacketType.VehicleFullUpdate &&
            frames.single().bytes.contentEquals(expected), "first native snapshot did not carry latest state")
        remove(); add(); remove()
        verify(frames.map { it.type } == listOf(PacketType.VehicleFullUpdate,
            PacketType.RemoveInventoryItemFromContainer, PacketType.AddInventoryItemToContainer,
            PacketType.RemoveInventoryItemFromContainer), "deltas lost, duplicated, reordered or replayed: " + frames.map { it.type })
        verify(frames.all { it.channel.toInt() == 0 && it.reliability == 3 }, "vehicle sends not FIFO ordered")
        verify(container.items == listOf(added, later), "send path mutated authoritative inventory")
        deltaBypass(false, false, "SP route changed")
        deltaBypass(false, true, "client route changed")
        deltaBypass(true, true, "mixed client/server route changed")
        val other = connection(422)
        coalesced(other, "another recipient borrowed first snapshot")
        full(other); remove(other)
        verify(frames.last().guid == 422L && frames.last().channel.toInt() == 0, "second recipient barrier failed")
        // Real processServer uses a direct raw relay, excluding origin and irrelevant recipients.
        val origin = connection(430)
        val unknownRelay = connection(431)
        val irrelevant = connection(432).apply { setRelevantPos(0, zombie.iso.Vector3(100000f, 100000f, 0f)) }
        val unknownState = VehicleManager.instance.getVehicleState(unknownRelay, car).apply { flags = 0 }
        val beforeRelay = frames.size
        val relay = zombie.network.packets.RemoveInventoryItemFromContainerPacket()
        relay.setData(container, added)
        relay.processServer(PacketType.RemoveInventoryItemFromContainer, origin)
        val relayed = frames.drop(beforeRelay)
        verify(relayed.map { it.guid }.toSet() == setOf(421L, 422L) && relayed.all { it.channel.toInt() == 0 }, "native relay changed relevance/origin/channel semantics")
        verify(!container.items.contains(added) && unknownState.flags.toInt() and 1 == 1, "relay did not preserve authoritative removal or request missing full")
        verify(!irrelevant.vehicleStates.containsKey(car.getId()) && !origin.vehicleStates.containsKey(car.getId()), "ineligible recipient acquired ordering state")
        val rootPlayer = unsafe.allocateInstance(zombie.characters.IsoPlayer::class.java) as zombie.characters.IsoPlayer
        set(rootPlayer, zombie.iso.IsoObject::class.java, "ecsComponentMap", HashMap<Any, Any>())
        val ordinary = ItemContainer("inventory", null, rootPlayer)
        val worldObject = unsafe.allocateInstance(zombie.iso.objects.IsoWorldInventoryObject::class.java) as zombie.iso.objects.IsoWorldInventoryObject
        worldObject.item = removed
        val worldContainer = ItemContainer("bag", null, worldObject)
        for (root in listOf(ordinary, worldContainer)) {
            val before = frames.size
            raw(PacketType.RemoveInventoryItemFromContainer, connection, root)
            verify(frames.size == before + 1 && frames.last().channel.toInt() == 1, "ordinary/player/world inventory route changed")
        }
        container.items.add(added)
        raw(PacketType.AddInventoryItemToContainer, connection, item = added)
        verify(frames.last().type == PacketType.AddInventoryItemToContainer && frames.last().channel.toInt() == 0, "raw Add route bypassed ordering")
        val sameGuid = connection(connection.getConnectedGUID())
        coalesced(sameGuid, "new actual connection borrowed same-GUID visibility")
        full(sameGuid); remove(sameGuid)
        verify(frames.last().channel.toInt() == 0, "same-GUID new connection could not establish own snapshot")
        // Nested bags in a vehicle have the same full-snapshot dependency; player/world bags do not.
        val square = unsafe.allocateInstance(zombie.iso.IsoGridSquare::class.java) as zombie.iso.IsoGridSquare
        car.square = square
        rootPlayer.square = square
        fun bag(id: Int) = zombie.inventory.types.InventoryContainer("Base", "Bag", "Bag", "Bag").apply { this.id = id }
        val carBag = bag(1890022111)
        container.items.add(carBag); carBag.setContainer(container)
        carBag.getInventory().items.add(InventoryItem("Base", "Test", "Test", "Test").apply { id = 1890022112 })
        raw(PacketType.RemoveInventoryItemFromContainer, connection, carBag.getInventory())
        verify(frames.last().channel.toInt() == 0, "nested vehicle bag bypassed channel ordering")
        val nestedRecipient = connection(433)
        val beforeNested = frames.size
        raw(PacketType.RemoveInventoryItemFromContainer, nestedRecipient, carBag.getInventory())
        verify(frames.size == beforeNested && nestedRecipient.vehicleStates.get(car.getId()).flags.toInt() and 1 == 1, "early nested vehicle bag was not coalesced into native full")
        full(nestedRecipient)
        raw(PacketType.RemoveInventoryItemFromContainer, nestedRecipient, carBag.getInventory())
        verify(frames.last().channel.toInt() == 0, "nested vehicle recipient barrier failed")
        val deepCarBag = bag(1890022116)
        carBag.getInventory().items.add(deepCarBag); deepCarBag.setContainer(carBag.getInventory())
        val beforeDeep = frames.size
        raw(PacketType.RemoveInventoryItemFromContainer, connection, deepCarBag.getInventory())
        verify(frames.size == beforeDeep + 1 && frames.last().channel.toInt() == 1, "unsupported deeper vehicle bag route changed")
        carBag.getInventory().items.remove(deepCarBag)
        val playerBag = bag(1890022113)
        ordinary.items.add(playerBag); playerBag.setContainer(ordinary)
        val worldBag = bag(1890022114)
        worldObject.item = worldBag; worldBag.setWorldItem(worldObject)
        for (root in listOf(playerBag.getInventory(), worldBag.getInventory())) {
            val before = frames.size
            raw(PacketType.RemoveInventoryItemFromContainer, connection, root)
            verify(frames.size == before + 1 && frames.last().channel.toInt() == 1, "player/world nested bag route changed")
        }
        car.square = null
        // Failed wire submission does not release inventory deltas.
        val failed = connection(423)
        wireResult = 0; full(failed); wireResult = 1
        coalesced(failed, "failed native Send established barrier")
        val nativeState = VehicleManager.instance.getVehicleState(failed, car)
        nativeState.flags = 0
        sendVehicles(failed)
        verify(nativeState.flags.toInt() and 1 == 1, "failed first snapshot was not scheduled for native retry")
        sendVehicles(failed); remove(failed)
        verify(frames.last().channel.toInt() == 0, "retry did not establish barrier")
        // A change during the first full send must survive sendVehicles' unconditional flag reset.
        val changing = connection(434)
        val change = InventoryItem("Base", "Test", "Test", "Test").apply { id = 1890022115 }
        val changingState = VehicleManager.instance.getVehicleState(changing, car).apply { flags = 1 }
        val beforeChanging = frames.size
        val nestedDiagnostics = java.io.ByteArrayOutputStream()
        val nestedLogger = zombie.debug.DebugLog.getInstance()
        zombie.debug.DebugType.Multiplayer.setLogSeverity(zombie.debug.LogSeverity.Error)
        nestedLogger.setStdOut(nestedDiagnostics); nestedLogger.setStdErr(nestedDiagnostics)
        duringFull = {
            INetworkPacket.send(changing, PacketType.RemoveInventoryItemFromContainer, container, "unsupported")
            container.items.add(change); remove(changing)
        }
        try { sendVehicles(changing) } finally { nestedLogger.setStdOut(System.out); nestedLogger.setStdErr(System.err) }
        verify(nestedDiagnostics.toString().contains("ClassCastException"), "malformed nested native values lost diagnostics: " + nestedDiagnostics.toString())
        verify(frames.size == beforeChanging + 1 && changingState.flags.toInt() and 1 == 1, "nested change escaped or lost its native full retry")
        val latest = snapshot()
        sendVehicles(changing)
        verify(frames.last().bytes.contentEquals(latest) && changingState.flags.toInt() == 0, "nested change did not reach the next native snapshot")
        remove(changing)
        verify(frames.last().channel.toInt() == 0, "nested-change retry did not release ordered deltas")
        container.items.remove(change)
        // Native inner authorization and outer full writer errors retain diagnostics and cannot release deltas.
        val invalid = connection(435)
        val nativeErrors = java.io.ByteArrayOutputStream()
        val logger = zombie.debug.DebugLog.getInstance()
        logger.setStdOut(nativeErrors); logger.setStdErr(nativeErrors)
        try {
            val authorization = car.netPlayerAuthorization
            car.netPlayerAuthorization = null
            full(invalid)
            car.netPlayerAuthorization = authorization
            coalesced(invalid, "internally caught authorization failure established barrier")
            NativeChecks.set(car, "passengers", null)
            full(invalid)
            NativeChecks.set(car, "passengers", emptyArray<BaseVehicle.Passenger>())
            coalesced(invalid, "caught full-snapshot serialization failure established barrier")
        } finally { logger.setStdOut(System.out); logger.setStdErr(System.err) }
        verify(nativeErrors.toString().contains("failed"), "native full-send diagnostics were suppressed")
        full(invalid); remove(invalid)
        verify(frames.last().channel.toInt() == 0, "valid full after serialization failure did not recover")
        // GUID, timestamp, object, world, manager and deletion boundaries cannot reuse old visibility.
        set(connection, UdpConnection::class.java, "lastConnection", connection.getLastConnection() + 1)
        coalesced(reason = "connection timestamp reuse retained barrier")
        full()
        VehicleInventoryOrdering.disconnected(connection.getConnectedGUID())
        coalesced(reason = "disconnect retained barrier")
        full()
        VehicleManager.instance.unregisterVehicle(car)
        verify(ids().allocateID() == car.getId(), "native same-instance ID reservation failed")
        VehicleManager.instance.registerVehicle(car)
        coalesced(reason = "deletion retained barrier")
        full()
        val reusedId = car.getId()
        VehicleManager.instance.unregisterVehicle(car)
        val replacement = vehicle()
        verify(replacement.getId() == reusedId, "native fixture did not reuse vehicle ID")
        car = replacement; container = car.getPartByIndex(0).getItemContainer()
        container.items.add(added)
        coalesced(reason = "vehicle ID reuse retained barrier")
        full()
        IsoWorld.instance.currentCell = unsafe.allocateInstance(IsoCell::class.java) as IsoCell
        coalesced(reason = "world-cell replacement retained barrier")
        full()
        // Native managers share VehicleIDMap.instance; replacing the manager preserves its map.
        VehicleManager.instance = VehicleManager()
        coalesced(reason = "vehicle manager replacement retained barrier")
        full()
        // Unknown argument shapes and unsupported fingerprints stay on their native path.
        val unsupported = VehicleInventoryOrdering.begin(connection, PacketType.RemoveInventoryItemFromContainer,
            arrayOf(container, removed), false)
        verify(!unsupported.coalesce, "unsupported engine coalesced native packet")
        VehicleInventoryOrdering.end(unsupported, null)
        val unknown = VehicleInventoryOrdering.begin(connection, PacketType.RemoveInventoryItemFromContainer,
            arrayOf(container, "unknown"), true)
        verify(!unknown.coalesce, "unknown native values were coalesced")
        VehicleInventoryOrdering.end(unknown, null)
        // Throwable cleanup, including Error outside native Exception handlers.
        val nativeLock = UdpConnection::class.java.getDeclaredField("bufferLock").apply { isAccessible = true }.get(connection) as ReentrantLock
        verify(nativeLock.holdCount == 0, "coalescing left the native writer lock held")
        wireFailure = AssertionError("fixture transport failure")
        try { full(); throw AssertionError("expected transport failure") } catch (e: AssertionError) {
            verify(e.message == "fixture transport failure", "wrong throwable")
        } finally {
            wireFailure = null
            // Vanilla flipSendUnlock does not unlock on Error; release only this fixture-owned hold.
            if (nativeLock.isHeldByCurrentThread) nativeLock.unlock()
        }
        val writer = connection.startPacket()
        PacketType.RemoveInventoryItemFromContainer.doPacket(writer)
        connection.endPacket(1, 3, 1)
        verify(frames.last().channel.toInt() == 1, "send scope leaked after Throwable")
        println("VEHICLE_INVENTORY_ORDERING_CHECKS_PASS (native cached packets/full serialization/UdpConnection sends, initial snapshot/latest state, FIFO, raw native relay/relevance/origin, nested car bags and player/world bypass, failed Send/serialization/retry/nested changes, same-GUID reconnect/session/world/ID lifecycle, guards, balanced cancel and Throwable cleanup)")
        kotlin.system.exitProcess(0)
    }
}
