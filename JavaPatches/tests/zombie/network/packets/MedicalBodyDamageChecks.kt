package zombie.network.packets

import java.lang.reflect.Field
import java.nio.ByteBuffer
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.Main
import net.alexredby.pztoolkitjavapatches.MedicalBodyDamage
import sun.misc.Unsafe
import zombie.characters.BodyDamage.BodyDamage
import zombie.characters.IsoPlayer
import zombie.characters.Stats
import zombie.network.fields.character.PlayerID

object MedicalBodyDamageChecks {
    class Patient : IsoPlayer(null) {
        lateinit var damage: BodyDamage
        lateinit var statData: Stats
        override fun getBodyDamageRemote(): BodyDamage = damage
        override fun getStats(): Stats = statData
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun data(packet: BodyDamageUpdatePacket): ByteBuffer =
        field(BodyDamageUpdatePacket::class.java, "data").get(packet) as ByteBuffer

    private fun packet(type: String, patient: IsoPlayer?): BodyDamageUpdatePacket {
        val packet = BodyDamageUpdatePacket()
        val typeField = field(BodyDamageUpdatePacket::class.java, "packetType")
        for (value in typeField.type.enumConstants)
            if ((value as Enum<*>).name == type) typeField.set(packet, value)
        val id = field(BodyDamageUpdatePacket::class.java, "remotePlayer").get(packet) as PlayerID
        field(PlayerID::class.java, "player").set(id, patient)
        // Native UPDATE overall-health payload, then BD_END. Keep its position nonzero to detect skipped parsing.
        val data = ByteBuffer.allocate(12).put(50.toByte()).putFloat(73.5f).put(4.toByte())
            .put(1.toByte()).putFloat(12.5f).put(65.toByte())
        field(BodyDamageUpdatePacket::class.java, "data").set(packet, data)
        return packet
    }

    private fun staleThrows(packet: BodyDamageUpdatePacket) {
        try {
            packet.processClient(null)
            throw AssertionError("native stale UPDATE did not reproduce NPE")
        } catch (expected: NullPointerException) {
            require(expected.message!!.contains("getBodyDamageRemote"), "unrelated native NPE: $expected")
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        require(Main.MEDICAL_BODY_DAMAGE_SUPPORTED, "unsupported medical patch baseline")
        require(BytecodeSupport.supports("zombie/network/packets/BodyDamageUpdatePacket.class", "2e37ca1add6b8696464285bd498e7c97cd9712c9094c51d1d57daac688145c8c"), "unsupported native packet")
        require(BytecodeSupport.supports("zombie/network/fields/character/PlayerID.class", "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56"), "unsupported native player resolution")
        require(!BytecodeSupport.supports("zombie/network/packets/BodyDamageUpdatePacket.class", "unknown"), "unknown bytecode accepted")
        val unsafe = field(Unsafe::class.java, "theUnsafe").get(null) as Unsafe
        val patient = unsafe.allocateInstance(Patient::class.java) as Patient
        patient.damage = unsafe.allocateInstance(BodyDamage::class.java) as BodyDamage
        patient.statData = Stats()
        var stale = packet("UPDATE", null)
        require(!MedicalBodyDamage.skip(stale, false), "unsupported guard skipped packet")
        staleThrows(stale)
        PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MedicalBodyDamageChecks::class.java.classLoader)
        stale = packet("UPDATE", null)
        stale.processClient(null)
        require(data(stale).position() == 12, "stale UPDATE consumed payload")
        for (type in listOf("START_UPDATING", "STOP_UPDATING")) {
            val control = packet(type, null)
            require(!MedicalBodyDamage.skip(control, true), "control packet skipped")
            control.processClient(null)
            require(data(control).position() == 12, "control packet parsed UPDATE data")
        }
        val valid = packet("UPDATE", patient)
        require(!MedicalBodyDamage.skip(valid, true), "valid UPDATE skipped")
        valid.processClient(null)
        require(patient.damage.overallBodyHealth == 73.5f && patient.damage.remotePainLevel.toInt() == 4
            && patient.damage.isFakeInfected && patient.statData.get(zombie.characters.CharacterStat.ZOMBIE_INFECTION) == 12.5f,
            "valid native UPDATE effect lost")
        require(data(valid).position() == 12, "valid native payload not fully consumed")
        println("MEDICAL_BODY_DAMAGE_CHECKS_PASS (original stale NPE, woven stale no-op, native valid effects, controls and unsupported guards)")
    }
}
