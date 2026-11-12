package zombie.network.packets

import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.raknet.UdpConnection
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketSetting
import zombie.network.PacketTypes
import zombie.network.fields.character.PlayerID

/**
 * Native packet application with explicit actor/send doubles and real root lookup. An old
 * echo overwriting later authoritative hands is a saved known-bad observation,
 * never a fix, action/Equip correlation, real UDP reorder or permission pass.
 * Native hand setters/Lua callbacks, packet parsing and live peers are not run.
 */
object HostEquipTransportChecks {
    private lateinit var unsafe: Unsafe
    private lateinit var ownerConnection: UdpConnection
    private data class Hands(val primary: Int, val secondary: Int)

    class Item : InventoryItem("Base", "TransportProbe", "TransportProbe", "TransportProbe") {
        override fun getFullType(): String = "Base.Screwdriver"
    }

    class Player : IsoPlayer(null) {
        lateinit var root: ItemContainer
        lateinit var writes: MutableList<String>
        var localActor = false
        var primary: InventoryItem? = null
        var secondary: InventoryItem? = null
        override fun isLocalPlayer(): Boolean = localActor
        override fun getInventory(): ItemContainer = root
        override fun getPrimaryHandItem(): InventoryItem? = primary
        override fun getSecondaryHandItem(): InventoryItem? = secondary
        override fun setPrimaryHandItem(item: InventoryItem?) { writes.add("primary"); primary = item }
        override fun setSecondaryHandItem(item: InventoryItem?) { writes.add("secondary"); secondary = item }
    }

    class Packet : EquipPacket() {
        private val echoes = ArrayList<Hands>()
        private val broadcasts = ArrayList<Hands>()
        var lastExcluded: UdpConnection? = null
        override fun sendToServer(type: PacketTypes.PacketType?) {
            check(type == PacketTypes.PacketType.Equip)
            echoes.add(Hands(primaryHand, secondaryHand))
        }
        override fun sendToClients(type: PacketTypes.PacketType?, connection: UdpConnection?) {
            check(type == PacketTypes.PacketType.Equip)
            lastExcluded = connection
            broadcasts.add(hands(player.getPlayer()))
        }
        internal fun sentCount(): Int = echoes.size
        internal fun broadcastCount(): Int = broadcasts.size
        private fun captured(index: Int): Hands = echoes[index]
        private fun published(): Hands = broadcasts.single()
        internal fun samePayload(first: Int, second: Int): Boolean = captured(first) == captured(second)
        internal fun copyEcho(index: Int, target: Packet) {
            val value = captured(index)
            target.primaryHand = value.primary
            target.secondaryHand = value.secondary
        }
        internal fun publishedIds(primary: Int, secondary: Int): Boolean = published() == Hands(primary, secondary)
    }

    private fun hands(player: IsoPlayer): Hands =
        Hands(player.getPrimaryHandItem()?.id ?: -1, player.getSecondaryHandItem()?.id ?: -1)

    private fun item(id: Int): InventoryItem = (unsafe.allocateInstance(Item::class.java) as Item).apply { this.id = id }
    private fun actor(local: Boolean, vararg items: InventoryItem): Player =
        (unsafe.allocateInstance(Player::class.java) as Player).apply {
            localActor = local
            writes = ArrayList()
            root = ItemContainer().apply {
                for (item in items) { getItems().add(item); item.container = this }
            }
        }
    private fun owner(packet: EquipPacket, actor: IsoPlayer) {
        PlayerID::class.java.getDeclaredField("player").apply { isAccessible = true }.set(packet.player, actor)
    }
    private fun clientEcho(actor: Player): Packet {
        GameClient.client = true; GameServer.server = false
        return Packet().also { owner(it, actor); it.processClient(null) }
    }
    private fun applyEcho(packet: Packet, actor: Player) {
        GameClient.client = false; GameServer.server = true
        owner(packet, actor)
        packet.processServer(PacketTypes.PacketType.Equip, ownerConnection)
        check(packet.lastExcluded === ownerConnection) { "Native echo rebroadcast lost its sender exclusion" }
    }

    private fun metadata() {
        check(BytecodeSupport.supports("zombie/network/packets/EquipPacket.class",
            "35e25895c725c3154d0f1e4b3217c7e19795ed1296441dbcea9283026ec5da89"))
        check(BytecodeSupport.supports("zombie/network/packets/NetTimedActionPacket.class",
            "ce367190ce6158eb88809f3215ebc471e6161896d9d526eb9ef0e73d58de847b"))
        check(BytecodeSupport.supports("zombie/inventory/ItemContainer.class",
            "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96"))
        val equip = EquipPacket::class.java.getAnnotation(PacketSetting::class.java)
        val action = NetTimedActionPacket::class.java.getAnnotation(PacketSetting::class.java)
        check(equip.reliability == 3 && action.reliability == 3 && equip.ordering.toInt() == 0 && action.ordering.toInt() == 1) {
            "Native action/equipment ordered-channel distinction changed"
        }
        check(EquipPacket::class.java.declaredFields.map { it.name }.toSet() == setOf("player", "primaryHand", "secondaryHand")) {
            "Equip gained an identity/revision field; transport observation requires review"
        }
    }

    private fun delayedEcho(shared: Boolean) {
        val clientA = item(101); val serverA = item(101); val serverB = item(102)
        check(clientA !== serverA && serverA.fullType == serverB.fullType && serverA.id != serverB.id)
        val client = actor(true, clientA).apply { primary = clientA; secondary = if (shared) clientA else null }
        val echoed = clientEcho(client)
        check(echoed.sentCount() == 1)
        val server = actor(false, serverA, serverB)
        // Explicit authoritative-state double: no server Lua action completion is claimed.
        server.setPrimaryHandItem(serverB); server.setSecondaryHandItem(if (shared) serverB else null)
        val before = hands(server)
        val delayed = Packet(); echoed.copyEcho(0, delayed); applyEcho(delayed, server)
        check(server.primary === serverA && server.primary !== clientA && before.primary == serverB.id) {
            "Known-bad native delayed echo no longer overwrites later server hands; review the observation"
        }
        check(server.secondary === if (shared) serverA else null)
        check(server.root.getItemWithID(serverA.id) === serverA && server.root.items.size == 2)
        check(delayed.broadcastCount() == 1 && delayed.publishedIds(serverA.id, if (shared) serverA.id else -1))
        check(server.writes.takeLast(2) == listOf("primary", "secondary"))
    }

    private fun missingAndEmpty() {
        val a = item(201); val b = item(202)
        val server = actor(false, a, b).apply { primary = a; secondary = a }
        val missingPrimary = Packet().apply { primaryHand = 999; secondaryHand = b.id }
        applyEcho(missingPrimary, server)
        check(server.primary == null && server.secondary === b) {
            "Native missing primary ID did not clear only that hand"
        }
        check(missingPrimary.publishedIds(-1, b.id))
        val missingSecondary = Packet().apply { primaryHand = a.id; secondaryHand = 999 }
        applyEcho(missingSecondary, server)
        check(server.primary === a && server.secondary == null)
        val sharedMissing = Packet().apply { primaryHand = 999; secondaryHand = 999 }
        applyEcho(sharedMissing, server)
        check(server.primary == null && server.secondary == null)
        server.primary = a; server.secondary = b
        val empty = Packet().apply { primaryHand = -1; secondaryHand = -1 }
        applyEcho(empty, server)
        check(server.primary == null && server.secondary == null)
        check(server.root.getItemWithID(a.id) === a && server.root.getItemWithID(b.id) === b && server.root.items.size == 2)
    }

    private fun indistinguishableAbaAndRemote() {
        val a = item(301); val b = item(302)
        check(a !== b && a.fullType == b.fullType && a.id != b.id)
        val local = actor(true, a, b).apply { primary = a }
        GameClient.client = true; GameServer.server = false
        val packet = Packet(); owner(packet, local)
        packet.processClient(null)
        local.primary = b; packet.processClient(null)
        local.primary = a; packet.processClient(null)
        check(packet.sentCount() == 3 && !packet.samePayload(0, 1) && packet.samePayload(0, 2)) {
            "Native echo payload unexpectedly distinguishes equal A states across ABA"
        }
        val remote = actor(false, a).apply { primary = a }
        val remotePacket = clientEcho(remote)
        check(remotePacket.sentCount() == 0) { "Remote actor unexpectedly echoed equipment" }
    }

    @JvmStatic fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init()
        unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
        // Opaque sender marker only: send endpoints never touch a socket/connection method.
        ownerConnection = unsafe.allocateInstance(UdpConnection::class.java) as UdpConnection
        val wasClient = GameClient.client; val wasServer = GameServer.server
        try {
            metadata(); delayedEcho(false); delayedEcho(true); missingAndEmpty(); indistinguishableAbaAndRemote()
            println("HOST_EQUIP_TRANSPORT_OBSERVATION_PASS nativeProcessClient=true nativeProcessServer=true " +
                "knownBadDelayedEchoOverwrite=observed sharedAlias=observed missingIdClear=observed abaPayload=indistinguishable " +
                "actorSendDoubles=true nativeRootLookup=true udpReorderingExercised=false actionCorrelation=false permissionsQualified=false gameStarted=false")
        } finally { GameClient.client = wasClient; GameServer.server = wasServer }
    }
}
