package zombie.core

import java.lang.reflect.Field
import java.nio.BufferUnderflowException
import java.nio.ByteBuffer
import java.util.ArrayList
import java.util.HashMap
import java.util.LinkedHashMap
import java.util.Queue
import me.zed_0xff.zombie_buddy.PatchEngine
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.Main
import net.alexredby.pztoolkitjavapatches.MedicalTimedActions
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.vm.JavaFunction
import sun.misc.Unsafe
import zombie.GameTime
import zombie.Lua.LuaManager
import zombie.characters.BodyDamage.BodyDamage
import zombie.characters.BodyDamage.BodyPart
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.core.raknet.UdpConnection
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PZNetKahluaTableImpl
import zombie.network.PacketTypes
import zombie.network.fields.character.PlayerID
import zombie.network.packets.NetTimedActionPacket

object MedicalTimedActionChecks {
    private var constructors = 0
    private var acknowledgements = 0
    private lateinit var body: BodyPart
    private lateinit var patient: Patient
    private lateinit var parsing: ByteBufferReader
    private var nestedConstructor: Runnable? = null

    class Patient : IsoPlayer(null) {
        lateinit var damage: BodyDamage

        override fun getBodyDamage(): BodyDamage = damage
    }

    class Connection : UdpConnection(null, 0, 0) {
        lateinit var bytes: ByteBuffer

        override fun startPacket(): ByteBufferWriter {
            bytes.clear()
            return ByteBufferWriter(bytes)
        }

        override fun endPacket(priority: Int, reliability: Int, channel: Byte) {
            bytes.flip()
            val reader = ByteBufferReader(bytes)
            reader.getByte()
            require(
                reader.getShort() == PacketTypes.PacketType.NetTimedAction.getId(),
                "wrong rejection packet",
            )
            require(
                reader.getByte().toInt() == 17 &&
                    reader.getEnum(Transaction.TransactionState::class.java) ==
                        Transaction.TransactionState.Reject,
                "native rejection changed transaction or state",
            )
            val doctor = PlayerID()
            doctor.parse(reader, null)
            require(
                doctor.getID().toInt() == 19 && !reader.bb.hasRemaining(),
                "native rejection changed doctor/framing",
            )
            acknowledgements++
        }
    }

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun expect(type: Class<out Throwable>, callback: () -> Unit) {
        try {
            callback()
            throw AssertionError("missing native failure $type")
        } catch (failure: Throwable) {
            if (!type.isInstance(failure)) throw AssertionError("wrong failure", failure)
        }
    }

    private fun field(type: Class<*>, name: String): Field =
        type.getDeclaredField(name).apply { isAccessible = true }

    private fun clean() {
        require(
            (field(MedicalTimedActions::class.java, "current").get(null) as ThreadLocal<*>).get() ==
                null,
            "parse scope leaked",
        )
    }

    private fun table(): PZNetKahluaTableImpl = PZNetKahluaTableImpl(LinkedHashMap<Any, Any>())

    private fun player(writer: ByteBufferWriter, id: Short) {
        writer.putShort(id)
        writer.putByte((-1).toByte())
    }

    private fun bodyValue(id: Short): ByteBufferReader {
        val bytes = ByteBuffer.allocate(7)
        val writer = ByteBufferWriter(bytes)
        player(writer, id)
        writer.putInt(0)
        bytes.flip()
        return ByteBufferReader(bytes)
    }

    private fun wire(medical: Boolean, patientID: Short, finalType: Byte): ByteBufferReader {
        val bytes = ByteBuffer.allocate(512)
        val writer = ByteBufferWriter(bytes)
        writer.putByte(17.toByte())
        writer.putEnum(Transaction.TransactionState.Request)
        player(writer, 19)
        writer.putUTF(if (medical) "MedicalProbe" else "GenericProbe")
        writer.putUTF("owned-request")
        writer.putInt(if (medical) 3 else 2)
        writer.putByte(1.toByte())
        writer.putUTF("owner")
        writer.putByte(8.toByte())
        player(writer, 19)
        if (medical) {
            writer.putByte(1.toByte())
            writer.putUTF("bodyPart")
            writer.putByte(10.toByte())
            player(writer, patientID)
            writer.putInt(0)
        }
        writer.putByte(1.toByte())
        writer.putUTF("following")
        writer.putByte(finalType)
        if (finalType.toInt() == 1) writer.putUTF("after-body-payload")
        bytes.flip()
        return ByteBufferReader(bytes)
    }

    private fun ctor(medical: Boolean) {
        val type = LuaManager.platform.newTable()
        type.rawset(
            "new",
            JavaFunction { frame, _ ->
                constructors++
                require(
                    frame.get(1) === GameServer.IDToPlayerMap.get(19.toShort()),
                    "constructor doctor changed",
                )
                require(!medical || frame.get(2) === body, "constructor lost exact native BodyPart")
                require(
                    (frame.get(if (medical) 3 else 2) ?: throw NullPointerException()).equals(
                        "after-body-payload",
                    ),
                    "remaining payload changed",
                )
                require(
                    !parsing.bb.hasRemaining(),
                    "constructor ran before complete argument decoding",
                )
                val nested = nestedConstructor
                nestedConstructor = null
                if (nested != null) nested.run()
                frame.push(LuaManager.platform.newTable())
                1
            },
        )
        LuaManager.env.rawset(if (medical) "MedicalProbe" else "GenericProbe", type)
    }

    private fun parse(reader: ByteBufferReader): NetTimedActionPacket {
        val packet = NetTimedActionPacket()
        parsing = reader
        packet.parse(reader, null)
        return packet
    }

    private fun scopeChecks() {
        val packet = NetTimedActionPacket()
        packet.state = Transaction.TransactionState.Request
        packet.playerId.setID(19)
        packet.playerId.setPlayerIndex((-1).toByte())
        field(PlayerID::class.java, "player")
            .set(packet.playerId, GameServer.IDToPlayerMap.get(19.toShort()))
        val previous = table()
        (packet as NetTimedAction).actionArgs = previous
        previous.rawset("live", "unchanged")
        val reader = bodyValue(20)
        val outer = MedicalTimedActions.begin(packet, reader, true)
        require(
            MedicalTimedActions.beginArguments(previous, reader) == null,
            "cached Request args activated before current header",
        )
        (packet as NetTimedAction).actionArgs = table()
        val arguments =
            MedicalTimedActions.beginArguments((packet as NetTimedAction).actionArgs, reader)
        val duplicate = ByteBufferReader(reader.bb.duplicate())
        MedicalTimedActions.beforeValue(
            (packet as NetTimedAction).actionArgs,
            duplicate,
            null,
            10.toByte(),
        )
        MedicalTimedActions.beforeValue(
            (packet as NetTimedAction).actionArgs,
            ByteBufferReader(reader.bb),
            null,
            10.toByte(),
        )
        val inner = MedicalTimedActions.begin(NetTimedAction(), reader, true)
        MedicalTimedActions.beforeValue(
            (packet as NetTimedAction).actionArgs,
            reader,
            null,
            10.toByte(),
        )
        require(
            !MedicalTimedActions.end(inner, IllegalStateException("foreign")),
            "nested foreign failure suppressed",
        )
        var stale: Throwable? = null
        try {
            MedicalTimedActions.beforeValue(
                (packet as NetTimedAction).actionArgs,
                reader,
                null,
                10.toByte(),
            )
        } catch (failure: RuntimeException) {
            stale = failure
        }
        require(
            stale != null && reader.bb.position() == 0,
            "outer scope not restored or lookahead consumed payload",
        )
        MedicalTimedActions.endArguments(arguments)
        require(
            MedicalTimedActions.beginArguments((packet as NetTimedAction).actionArgs, reader) ==
                null,
            "Lua constructor could reactivate argument decoding",
        )
        require(MedicalTimedActions.end(outer, stale), "owned stale signal not handled")
        require("unchanged" == previous.rawget("live"), "live previous args mutated")
        clean()
        expect(NullPointerException::class.java) { table().load(bodyValue(20), null, 10.toByte()) }
    }

    @JvmStatic
    @Suppress("UNCHECKED_CAST")
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val unsafeField =
            Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }
        val unsafe = unsafeField.get(null) as Unsafe
        GameTime.setInstance(GameTime())
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newTable()
        LuaManager.thread = se.krka.kahlua.vm.KahluaThread(LuaManager.platform, LuaManager.env)
        LuaManager.thread.debugOwnerThread = Thread.currentThread()
        LuaManager.caller =
            se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        val doctor = unsafe.allocateInstance(Patient::class.java) as Patient
        doctor.onlineId = 19
        patient = unsafe.allocateInstance(Patient::class.java) as Patient
        patient.onlineId = 20
        field(zombie.iso.IsoObject::class.java, "ecsComponentMap").set(doctor, HashMap<Any, Any>())
        field(zombie.iso.IsoObject::class.java, "ecsComponentMap").set(patient, HashMap<Any, Any>())
        patient.damage = unsafe.allocateInstance(BodyDamage::class.java) as BodyDamage
        body = unsafe.allocateInstance(BodyPart::class.java) as BodyPart
        field(BodyDamage::class.java, "bodyParts").set(patient.damage, ArrayList(listOf(body)))
        GameServer.server = true
        GameClient.client = false
        GameServer.IDToPlayerMap.put(19.toShort(), doctor)
        ctor(true)
        ctor(false)
        require(Main.MEDICAL_TIMED_ACTION_SUPPORTED, "unsupported timed-action patch baseline")
        require(
            BytecodeSupport.supports(
                "zombie/network/PZNetKahluaTableImpl.class",
                "201f0e59502fc5a106f8c9021e0b0d13a30dcb8d0beb9e8934cec390231ddba6",
            ),
            "unsupported native table decoder",
        )
        require(
            !BytecodeSupport.supports("zombie/network/PZNetKahluaTableImpl.class", "unknown"),
            "unknown decoder accepted",
        )
        val unsupportedReader = bodyValue(20)
        val unsupported =
            MedicalTimedActions.begin(NetTimedActionPacket(), unsupportedReader, false)
        require(
            unsupported == null && !MedicalTimedActions.end(unsupported, null),
            "unsupported decoder guard activated",
        )
        MedicalTimedActions.beforeValue(table(), unsupportedReader, null, 10.toByte())
        expect(NullPointerException::class.java) {
            table().load(unsupportedReader, null, 10.toByte())
        }
        clean()
        expect(NullPointerException::class.java) { parse(wire(true, 20, 1)) }
        require(constructors == 0, "original stale request constructed action")
        PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            MedicalTimedActionChecks::class.java.classLoader,
        )
        val staleReader = wire(true, 20, 1)
        val stale = NetTimedActionPacket()
        val live = LuaManager.platform.newTable()
        live.rawset("live", "unchanged")
        stale.action = live
        val oldArgs = table()
        oldArgs.rawset("live", "unchanged")
        (stale as NetTimedAction).actionArgs = oldArgs
        stale.parse(staleReader, null)
        clean()
        require(
            constructors == 0 &&
                stale.action == null &&
                (stale as NetTimedAction).actionArgs.size() == 0 &&
                !staleReader.bb.hasRemaining(),
            "stale packet reached constructor or retained payload/action",
        )
        require(
            "unchanged" == live.rawget("live") && oldArgs.size() == 1,
            "cached live action/args mutated",
        )
        val existing = NetTimedAction()
        existing.id = 18
        existing.playerId.copy(stale.playerId)
        existing.state = Transaction.TransactionState.Accept
        existing.action = live
        existing.actionArgs = oldArgs
        val actions = field(ActionManager::class.java, "actions").get(null) as Queue<Any>
        actions.add(existing)
        val connection = unsafe.allocateInstance(Connection::class.java) as Connection
        connection.bytes = ByteBuffer.allocate(1024)
        stale.processServer(PacketTypes.PacketType.NetTimedAction, connection)
        require(acknowledgements == 1 && constructors == 0, "native Reject acknowledgement lost")
        require(
            actions.contains(existing) &&
                existing.state == Transaction.TransactionState.Accept &&
                existing.action === live &&
                existing.actionArgs === oldArgs,
            "stale request canceled/mutated prior ActionManager action",
        )
        actions.remove(existing)
        GameServer.IDToPlayerMap.put(20.toShort(), patient)
        require(
            parse(wire(true, 20, 1)).action != null && constructors == 1,
            "valid medical parse was changed/repeated",
        )
        clean()
        require(
            parse(wire(false, 20, 1)).action != null && constructors == 2,
            "generic non-body parse was changed/repeated",
        )
        clean()
        nestedConstructor = Runnable {
            require(parse(wire(false, 20, 1)).action != null, "nested generic parse changed")
        }
        require(
            parse(wire(true, 20, 1)).action != null && constructors == 4,
            "nested parse lost/repeated constructor",
        )
        clean()
        val unknown = wire(true, 20, 100)
        expect(RuntimeException::class.java) { parse(unknown) }
        require(constructors == 4, "unknown value reached constructor")
        clean()
        val truncated = wire(true, 20, 1)
        truncated.bb.limit(truncated.bb.limit() - 5)
        expect(BufferUnderflowException::class.java) { parse(truncated) }
        clean()
        GameServer.IDToPlayerMap.remove(20.toShort())
        expect(NullPointerException::class.java) { table().load(bodyValue(20), null, 10.toByte()) }
        scopeChecks()
        println(
            "MEDICAL_TIMED_ACTION_CHECKS_PASS (original NPE, woven stale Reject/no constructor, valid medical/generic single parse, exact framing, unsupported/unknown/truncated failures, nested and cached scope isolation)",
        )
    }
}
