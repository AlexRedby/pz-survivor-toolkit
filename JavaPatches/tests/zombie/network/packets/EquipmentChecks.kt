package zombie.network.packets

import java.nio.ByteBuffer
import net.alexredby.pztoolkitjavapatches.Main
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.network.GameClient

object EquipmentChecks {
    class LocalPlayer : IsoPlayer(null) {
        override fun isLocalPlayer(): Boolean = true
    }

    class CountingPacket : EquipPacket() {
        @JvmField var acknowledgements = 0

        override fun sendToServer(type: zombie.network.PacketTypes.PacketType?) {
            acknowledgements++
        }
    }

    @JvmStatic
    fun owner(packet: EquipPacket, owner: IsoPlayer?) {
        val field = zombie.network.fields.character.PlayerID::class.java.getDeclaredField("player")
        field.setAccessible(true)
        field.set(packet.player, owner)
    }

    @JvmStatic
    fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.setAccessible(true)
        val unsafe = field.get(null) as Unsafe
        val local = unsafe.allocateInstance(LocalPlayer::class.java) as IsoPlayer
        val remote = unsafe.allocateInstance(IsoPlayer::class.java) as IsoPlayer
        val packet = EquipPacket()
        owner(packet, local)
        val other = EquipPacket()
        owner(other, local)
        val unread = ByteBufferReader(ByteBuffer.wrap(byteArrayOf(2)))
        val complete = ByteBufferReader(ByteBuffer.allocate(0))
        GameClient.client = true
        require(Main.EQUIPMENT_SUPPORTED, "unsupported equipment baseline")
        Main.EquipmentParsed.exit(packet, unread, null)
        require(Main.EquipmentEcho.enter(packet, null), "incomplete local packet acknowledged")
        require(!Main.EquipmentEcho.enter(packet, null), "repeated packet suppressed")
        Main.EquipmentParsed.exit(packet, complete, null)
        require(!Main.EquipmentEcho.enter(packet, null), "valid equipment update suppressed")
        Main.EquipmentParsed.exit(packet, unread, null)
        require(!Main.EquipmentEcho.enter(other, null), "different packet suppressed")
        require(!Main.EquipmentEcho.enter(packet, null), "stale incomplete state retained")
        Main.EquipmentParsed.exit(packet, unread, null)
        Main.EquipmentParsed.exit(packet, complete, null)
        require(!Main.EquipmentEcho.enter(packet, null), "reused packet retained rejection")
        owner(packet, remote)
        Main.EquipmentParsed.exit(packet, unread, null)
        require(!Main.EquipmentEcho.enter(packet, null), "remote equipment update suppressed")
        GameClient.client = false
        owner(packet, local)
        Main.EquipmentParsed.exit(packet, unread, null)
        require(!Main.EquipmentEcho.enter(packet, null), "server or standalone update suppressed")
        GameClient.client = true
        val counted = CountingPacket()
        owner(counted, local)
        Main.EquipmentParsed.exit(counted, unread, null)
        counted.processClient(null)
        require(counted.acknowledgements == 1, "vanilla did not acknowledge incomplete equipment")
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            EquipmentChecks::class.java.classLoader,
        )
        Main.EquipmentParsed.exit(counted, unread, null)
        counted.processClient(null)
        require(counted.acknowledgements == 1, "woven prefix acknowledged incomplete equipment")
        Main.EquipmentParsed.exit(counted, complete, null)
        counted.processClient(null)
        require(
            counted.acknowledgements == 2,
            "woven prefix blocked valid equipment acknowledgement",
        )
        require(unread.bb.position() == 0, "inspection consumed packet data")
        println(
            "EQUIPMENT_CHECKS_PASS (vanilla versus woven acknowledgement, incomplete local ack, complete, repeat, reused/different packet, remote/server guards)",
        )
    }
}
