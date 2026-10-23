package zombie.characters

import gnu.trove.map.hash.THashMap
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import java.nio.ByteBuffer
import java.util.ArrayList
import java.util.HashMap
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.Main
import net.alexredby.pztoolkitjavapatches.MedicalVisuals
import sun.misc.Unsafe
import zombie.characters.WornItems.BodyLocationGroup
import zombie.characters.WornItems.WornItems
import zombie.characters.ecs.ECSComponent
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.core.skinnedmodel.visual.ItemVisual
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.Clothing
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes.PacketType
import zombie.network.packets.INetworkPacket
import zombie.network.packets.SyncClothingPacket
import zombie.scripting.objects.ItemBodyLocation

object MedicalVisualChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var remove: Method
    private lateinit var connection: Connection

    class Patient : IsoPlayer(null) {
        lateinit var worn: WornItems
        lateinit var inventoryData: ItemContainer
        var local = false
        var failNotification = false
        var notifications = 0
        override fun isLocalPlayer(): Boolean = local
        override fun getECSComponentMap(): HashMap<Class<out ECSComponent>, ECSComponent> = HashMap()
        override fun getWornItems(): WornItems = worn
        override fun getInventory(): ItemContainer = inventoryData
        override fun resetModelNextFrame() {}
        override fun onWornItemsChanged() {
            notifications++
            if (failNotification) throw IllegalStateException("native cleanup sentinel")
        }
    }

    class Visual : Clothing(null, null, null, null as String?, null, null) {
        lateinit var fullTypeData: String
        lateinit var itemVisual: ItemVisual
        override fun getFullType(): String = fullTypeData
        override fun getBodyLocation(): ItemBodyLocation = ItemBodyLocation.BANDAGE
        override fun getVisual(): ItemVisual = itemVisual
    }

    class Connection : UdpConnection(null, 0, 0) {
        var readyForPackets = false
        lateinit var sent: MutableList<List<Int>>
        lateinit var active: SyncClothingPacket
        lateinit var outgoing: ByteBuffer
        override fun isReady(): Boolean = readyForPackets
        override fun getPacket(type: PacketType): INetworkPacket {
            require(type == PacketType.SyncClothing, "unexpected packet")
            active = SyncClothingPacket()
            return active
        }
        override fun startPacket(): ByteBufferWriter {
            outgoing = ByteBuffer.allocate(4096)
            return ByteBufferWriter(outgoing)
        }
        override fun isLimitExceeded(type: PacketType): Boolean = false
        override fun isHashEquals(type: PacketType, hash: Int?): Boolean = false
        override fun cancelPacket() { throw AssertionError("native clothing serialization failed") }
        override fun endPacket(priority: Int, reliability: Int, ordering: Byte) {
            outgoing.flip()
            require(outgoing.get() == 134.toByte() && outgoing.short == PacketType.SyncClothing.id, "wrong native packet header")
            outgoing.short
            outgoing.get()
            val descriptions = get(SyncClothingPacket::class.java, active, "items") as ArrayList<*>
            require(java.lang.Byte.toUnsignedInt(outgoing.get()) == descriptions.size, "native wire count differs")
            val ids = ArrayList<Int>()
            for (item in descriptions) ids.add(get(item!!.javaClass, item, "itemId") as Int)
            sent.add(ids)
        }
    }

    private fun require(value: Boolean, reason: String) {
        if (!value) throw AssertionError(reason)
    }

    private fun get(owner: Class<*>, instance: Any, name: String): Any? {
        try {
            val field = owner.getDeclaredField(name).apply { isAccessible = true }
            return field.get(instance)
        } catch (error: Exception) {
            throw AssertionError(error)
        }
    }

    private fun patient(): Patient {
        val p = unsafe.allocateInstance(Patient::class.java) as Patient
        p.local = true
        p.onlineId = 42
        val group = BodyLocationGroup("medical-check")
        group.getOrCreateLocation(ItemBodyLocation.BANDAGE)
        group.setMultiItem(ItemBodyLocation.BANDAGE, true)
        p.worn = WornItems(group)
        p.inventoryData = ItemContainer()
        return p
    }

    private fun visual(p: Patient, id: Int): Visual {
        val item = unsafe.allocateInstance(Visual::class.java) as Visual
        item.fullTypeData = "Base.Bandage_LeftLowerArm"
        item.setID(id)
        item.itemVisual = ItemVisual()
        item.itemVisual.setItemType(item.fullTypeData)
        item.itemVisual.setTint(zombie.core.ImmutableColor.white)
        p.worn.setItem(ItemBodyLocation.BANDAGE, item)
        p.inventoryData.items.add(item)
        return item
    }

    @Suppress("UNCHECKED_CAST")
    private fun models(item: InventoryItem): Any {
        val type = Class.forName("zombie.characters.IsoGameCharacter\$Bandages")
        val ctor = type.getDeclaredConstructor().apply { isAccessible = true }
        val models = ctor.newInstance()
        val map = get(type, models, "itemMap") as THashMap<String, InventoryItem>
        map.put(item.fullType, item)
        return models
    }

    private fun removed(p: Patient, models: Any, item: InventoryItem) {
        val before = p.notifications
        remove.invoke(models, p, item.fullType)
        require(!p.worn.contains(item) && !p.inventoryData.items.contains(item), "native visual removal lost")
        require(p.notifications == before + 1, "native cleanup notification lost")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        unsafe = field.get(null) as Unsafe
        connection = unsafe.allocateInstance(Connection::class.java) as Connection
        connection.readyForPackets = true
        connection.sent = ArrayList()
        GameClient.client = true
        GameClient.connection = connection
        val type = Class.forName("zombie.characters.IsoGameCharacter\$Bandages")
        remove = type.getDeclaredMethod("removeBandageModel", IsoGameCharacter::class.java, String::class.java).apply { isAccessible = true }
        require(Main.MEDICAL_VISUALS_SUPPORTED, "unsupported native removal baseline")
        val original = patient()
        val item = visual(original, 100)
        val nativeModels = models(item)
        removed(original, nativeModels, item)
        require(connection.sent.isEmpty(), "native removal unexpectedly synced")
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MedicalVisualChecks::class.java.classLoader)
        val p = patient()
        val one = visual(p, 101)
        val two = visual(p, 102)
        val keep = visual(p, 103)
        val first = models(one)
        val second = models(two)
        require(MedicalVisuals.before(first, p, one.fullTypeData, false) == null, "unsupported code accepted")
        require(MedicalVisuals.before(first, p, one.fullTypeData, true) === one, "direct before failed")
        removed(p, first, one)
        require(connection.sent == listOf(listOf(102, 103)), "first native clothing snapshot wrong: ${connection.sent}")
        removed(p, second, two)
        require(connection.sent == listOf(listOf(102, 103), listOf(103)), "duplicate model removal snapshot wrong")
        require(p.worn.contains(keep) && p.inventoryData.items.contains(keep), "unrelated model removed")
        remove.invoke(first, p, "Base.NotPresent")
        remove.invoke(first, p, one.fullTypeData)
        require(connection.sent.size == 2, "missing/already removed model sent a snapshot")
        for (mode in listOf("remote", "sp", "server", "offline", "unready", "unknownId")) {
            val control = patient()
            val current = visual(control, 200)
            val state = models(current)
            control.local = mode != "remote"
            control.onlineId = (if (mode == "unknownId") -1 else 42).toShort()
            GameClient.client = mode != "sp"
            GameServer.server = mode == "server"
            GameClient.connection = if (mode == "offline") null else connection
            connection.readyForPackets = mode != "unready"
            removed(control, state, current)
            require(connection.sent.size == 2, "$mode emitted a snapshot")
        }
        val partial = patient()
        partial.failNotification = true
        val partialItem = visual(partial, 300)
        try {
            remove.invoke(models(partialItem), partial, partialItem.fullTypeData)
            throw AssertionError("native failure suppressed")
        } catch (expected: InvocationTargetException) {
            require(expected.cause is IllegalStateException && expected.cause!!.message == "native cleanup sentinel", "unexpected native failure")
        }
        require(!partial.worn.contains(partialItem) && !partial.inventoryData.items.contains(partialItem)
            && connection.sent.size == 2, "failed cleanup changed native effects or sent a partial snapshot")
        println("MEDICAL_VISUAL_CHECKS_PASS (native missing sync, woven exact ordered IDs, duplicates, cleanup/failure, no-op, remote/SP/server/disconnected/unsupported guards)")
    }
}
