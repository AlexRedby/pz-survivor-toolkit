import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Arrays
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract
import net.alexredby.cartlab.ActionAdmission
import net.alexredby.cartlab.LeaseControl
import net.alexredby.cartlab.Multiplayer
import net.alexredby.cartlab.NativeTime

// Standalone native serialization/helper check. No game, transport, settings or save is started.
object NativeTimeCheck {
    open class Owner : zombie.characters.IsoPlayer(null, null, 0, 0, 0) {
        var local = false

        override fun isLocalPlayer() = local

        lateinit var ai: zombie.characters.NetworkPlayerAI

        override fun getNetworkCharacterAI() = ai

        var motion: String? = null
        var action: String? = null

        override fun getUsername(): String? = "client1"

        override fun getOnlineID(): Short = 7

        override fun getVariableString(key: String?): String? {
            return if ("ToolkitCartPose".equals(key)) motion
            else if ("ToolkitCartActionPose".equals(key)) action else null
        }
    }

    @OptIn(ExperimentalContracts::class)
    private fun check(value: Boolean, message: String?) {
        contract { returns() implies value }
        if (!value) throw AssertionError(message)
    }

    @Suppress("UNCHECKED_CAST")
    private fun <K : Any, V> map(name: String?): NativeTime.NativeWeakMap<K, V> {
        val field = NativeTime::class.java.getDeclaredField(name)
        field.setAccessible(true)
        return field.get(null) as NativeTime.NativeWeakMap<K, V>
    }

    private fun rejectSpan(buffer: ByteBuffer?, begin: Int, end: Int) {
        try {
            NativeTime.nativeTimeBody(buffer, begin, end)
            throw AssertionError("Invalid body span accepted")
        } catch (expected: IllegalArgumentException) {}
    }

    private fun checkAdmissionNumbers(sources: java.nio.file.Path?) {
        val platform = se.krka.kahlua.j2se.J2SEPlatform.getInstance()
        val environment = platform.newEnvironment()
        val thread = se.krka.kahlua.vm.KahluaThread(platform, environment)
        thread.debugOwnerThread = Thread.currentThread()
        val probe = java.nio.file.Files.readString(sources!!.resolve("action-admission.lua"))
        val functions =
            probe!!.substring(
                probe.indexOf("local function integerText"),
                probe.indexOf("local function emit"),
            )
        val json = java.nio.file.Files.readString(sources.resolve("json.lua"))
        val script =
            ("local J=(function()\n" +
                json +
                "\nend)()\n" +
                functions +
                "\nlocal mono,maximum,wall=...;return encodeRow({monoNs=mono,maximum=maximum,negative=-maximum,wallMs=wall,zero=0,cart=-2147483648})")
        val closure =
            se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(
                script,
                "cart-admission-numbers",
                environment,
            )
        val result =
            thread.pcall(
                closure,
                arrayOf<Any?>(253716934852789.0, 9007199254740991.0, 1792720134545.0),
            )
        check(
            result!!.size == 2 && java.lang.Boolean.TRUE.equals(result[0]),
            "Actual Kahlua admission encoder failed: " + Arrays.toString(result),
        )
        val encoded = result[1] as String
        for (exact in
            arrayOf<String>(
                "\"monoNs\":253716934852789",
                "\"maximum\":9007199254740991",
                "\"negative\":-9007199254740991",
                "\"wallMs\":1792720134545",
                "\"zero\":0",
                "\"cart\":-2147483648",
            )) check(
            encoded.contains(exact),
            "Actual Kahlua admission counter lost precision: " + encoded,
        )
    }

    // Native copy normalizes a remote owner; the parsed packet alone retains the signed wire slot.
    private fun checkNativeActionOwnerCopy(unsafe: sun.misc.Unsafe?) {
        val server = zombie.network.GameServer.server
        val client = zombie.network.GameClient.client
        try {
            zombie.network.GameServer.server = true
            zombie.network.GameClient.client = false
            val remote = unsafe!!.allocateInstance(Owner::class.java) as Owner
            remote.local = false
            remote.onlineId = 7
            remote.playerIndex = 0
            // isLocal() is final and consults the native ECS component, not just isLocalPlayer().
            // Construct only the in-memory owner/component association, without an AI/world
            // lifecycle.
            val components = zombie.iso.IsoObject::class.java.getDeclaredField("ecsComponentMap")
            components.setAccessible(true)
            components.set(
                remote,
                java.util.HashMap<
                    Class<out zombie.characters.ecs.ECSComponent?>?,
                    zombie.characters.ecs.ECSComponent?,
                >(),
            )
            val network =
                unsafe.allocateInstance(
                    zombie.characters.component.NetworkPlayerComponent::class.java,
                ) as zombie.characters.component.NetworkPlayerComponent
            val componentClass =
                zombie.characters.ecs.ECSComponent::class.java.getDeclaredField("ecsClass")
            componentClass.setAccessible(true)
            componentClass.set(
                network,
                zombie.characters.ecs.ECSComponent.getECSClass(
                    zombie.characters.component.NetworkPlayerComponent::class.java,
                ),
            )
            network.setECSOwnerEntity(remote)
            check(network.isRemote() && !remote.isLocal(), "Native remote owner fixture is local")
            val actionClass = Class.forName("zombie.core.Action")
            val actionOwner = actionClass.getDeclaredField("playerId")
            actionOwner.setAccessible(true)
            val actionID = actionClass.getDeclaredField("id")
            actionID.setAccessible(true)
            val actionState = actionClass.getDeclaredField("state")
            actionState.setAccessible(true)
            val player =
                zombie.network.fields.character.PlayerID::class.java.getDeclaredField("player")
            player.setAccessible(true)
            val packet = zombie.network.packets.NetTimedActionPacket()
            val source = actionOwner.get(packet) as zombie.network.fields.character.PlayerID
            source.setID(7.toShort())
            source.setPlayerIndex(0.toByte())
            player.set(source, remote)
            actionID.setByte(packet, 1.toByte())
            actionState.set(packet, zombie.core.Transaction.TransactionState.Request)
            packet.type = "ToolkitWoodCartPickup"
            packet.action = se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable()
            val actual = zombie.core.NetTimedAction()
            actual.copyFrom(packet)
            val copied = actionOwner.get(actual) as zombie.network.fields.character.PlayerID
            check(
                source.getPlayerIndex().toInt() == 0,
                "Native action copy changed the packet's signed wire slot",
            )
            check(
                copied.getPlayerIndex().toInt() == -1,
                "Native action copy retained the source slot for a remote server actor",
            )
            check(
                copied.getPlayer() === remote && copied.getID().toInt() == 7,
                "Native action copy lost exact actor/online ID",
            )
            check(
                actionID.getByte(actual).toInt() == 1 &&
                    actionState.get(actual) === zombie.core.Transaction.TransactionState.Request,
                "Native action copy lost transaction/state",
            )
            check(
                actual.action === packet.action && actual.action.rawget("netAction") === actual,
                "Native action table did not rebind to the actual copied action",
            )
        } finally {
            zombie.network.GameServer.server = server
            zombie.network.GameClient.client = client
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        checkAdmissionNumbers(java.nio.file.Path.of(args[0]))
        check(
            ActionAdmission.actionAdmissionKind("ToolkitWoodCartPickup") &&
                !ActionAdmission.actionAdmissionKind("ISWalkToTimedAction"),
            "Unrelated action admitted",
        )
        check(
            ActionAdmission.actionAdmissionCanAccept(
                "pending",
                "Accept",
                true,
                true,
                true,
                "exact-token",
            ),
            "Actual accepted action refused",
        )
        check(
            !ActionAdmission.actionAdmissionCanAccept(
                "terminal",
                "Accept",
                true,
                true,
                true,
                "exact-token",
            ),
            "Retired action reopened",
        )
        check(
            !ActionAdmission.actionAdmissionCanAccept(
                "pending",
                "Request",
                true,
                true,
                true,
                "exact-token",
            ),
            "Pre-Accept start admitted",
        )
        check(
            (!ActionAdmission.actionAdmissionCanAccept(
                "pending",
                "Accept",
                false,
                true,
                true,
                "exact-token",
            ) &&
                !ActionAdmission.actionAdmissionCanAccept(
                    "pending",
                    "Accept",
                    true,
                    false,
                    true,
                    "exact-token",
                ) &&
                !ActionAdmission.actionAdmissionCanAccept(
                    "pending",
                    "Accept",
                    true,
                    true,
                    false,
                    "exact-token",
                ) &&
                !ActionAdmission.actionAdmissionCanAccept(
                    "pending",
                    "Accept",
                    true,
                    true,
                    true,
                    null,
                )),
            "Missing authority/binding/queue/token admitted",
        )
        check(
            (ActionAdmission.actionAdmissionInteger(Integer.MIN_VALUE.toDouble()) &&
                ActionAdmission.actionAdmissionInteger(Integer.MAX_VALUE.toDouble()) &&
                !ActionAdmission.actionAdmissionInteger(Double.NaN) &&
                !ActionAdmission.actionAdmissionInteger(.5) &&
                !ActionAdmission.actionAdmissionInteger(2147483648.0)),
            "Native constructor integer domain changed",
        )
        for (order in arrayOf<ByteOrder?>(ByteOrder.BIG_ENDIAN, ByteOrder.LITTLE_ENDIAN)) {
            val header = ByteBuffer.allocate(16).order(order)
            header.position(4)
            header.put(134.toByte()).putShort(321.toShort())
            header.limit(7).position(4)
            header.mark()
            val original = header.array().clone()
            check(LeaseControl.leaseControlHeader(header) == 321, "Lease command header/order lost")
            check(
                header.position() == 4 && header.limit() == 7 && header.order() === order,
                "Lease header changed cursor/limit/order",
            )
            header.reset()
            check(
                header.position() == 4 && Arrays.equals(original, header.array()),
                "Lease header changed mark/content",
            )
            header.limit(6)
            check(LeaseControl.leaseControlHeader(header) == -1, "Truncated lease header accepted")
            header.limit(7)
            header.put(4, 1.toByte())
            check(LeaseControl.leaseControlHeader(header) == -1, "Foreign header accepted")
        }
        val buffer = ByteBuffer.allocate(300).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(0x01020304).putFloat(-0.0f).putInt(0x7fc01234)
        buffer.position(2)
        buffer.mark()
        val before = buffer.array().clone()
        val body = NativeTime.nativeTimeBody(buffer, 4, 12)
        check(body.hex.equals("000000803412c07f"), "Raw float bits/order lost")
        check(
            body.bytes == 8 && body.order.equals("LITTLE_ENDIAN") && body.sha.length == 64,
            "Body metadata",
        )
        check(
            buffer.position() == 2 &&
                buffer.limit() == 300 &&
                buffer.order() === ByteOrder.LITTLE_ENDIAN,
            "Original cursor/order changed",
        )
        buffer.reset()
        check(
            buffer.position() == 2 && Arrays.equals(before, buffer.array()),
            "Original mark/content changed",
        )
        val direct = ByteBuffer.allocateDirect(16)
        direct.putLong(0x0102030405060708L)
        direct.position(0)
        check(
            NativeTime.nativeTimeBody(direct, 0, 8).hex.equals("0102030405060708"),
            "Direct body unsupported",
        )
        check(
            NativeTime.nativeTimeBody(buffer, 4, 12).equals(body),
            "Repeated payload fingerprint changed",
        )
        rejectSpan(buffer, -1, 2)
        rejectSpan(buffer, 2, 1)
        rejectSpan(buffer, 0, 257)
        rejectSpan(buffer, 0, 301)
        val identities = NativeTime.NativeWeakMap<Any, Long>()
        val first =
            object : Any() {
                override fun equals(other: Any?): Boolean {
                    return true
                }

                override fun hashCode(): Int {
                    return 1
                }
            }
        val second =
            object : Any() {
                override fun equals(other: Any?): Boolean {
                    return true
                }

                override fun hashCode(): Int {
                    return 1
                }
            }
        identities.put(first, 1L)
        identities.put(second, 2L)
        check(
            identities.get(first) == 1L && identities.get(second) == 2L,
            "Identity map used equality",
        )
        identities.remove(first)
        check(identities.get(first) == null && identities.get(second) == 2L, "Identity removal")
        val a = NativeTime.nativeTimeIdentity(first, true)
        val b = NativeTime.nativeTimeIdentity(second, true)
        val c = NativeTime.nativeTimeIdentity(first, false)
        check(
            a > 0 && b > a && c > b && NativeTime.nativeTimeIdentity(first, true) == a,
            "Epoch ordinals reused",
        )
        // Initialize native static facilities only. Unsafe avoids creating a world/player
        // lifecycle.
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        Class.forName("zombie.characters.IsoGameCharacter")
        Class.forName("zombie.network.GameClient")
        val unsafeField = sun.misc.Unsafe::class.java.getDeclaredField("theUnsafe")
        unsafeField.setAccessible(true)
        val unsafe = unsafeField.get(null) as sun.misc.Unsafe
        checkNativeActionOwnerCopy(unsafe)
        val owner = unsafe.allocateInstance(Owner::class.java) as Owner
        owner.local = true
        owner.motion = "motion-before"
        owner.action = "action-before"
        owner.ai =
            unsafe.allocateInstance(zombie.characters.NetworkPlayerAI::class.java)
                as zombie.characters.NetworkPlayerAI
        owner.ai.prediction = zombie.network.fields.character.Prediction()
        zombie.network.GameServer.server = false
        zombie.network.GameClient.client = true
        // Helpers are checked without opening timeline output or relying on any cache settings.
        val closing = Multiplayer::class.java.getDeclaredField("timelineClosing")
        closing.setAccessible(true)
        closing.setBoolean(null, true)
        val packet = zombie.network.packets.character.PlayerPacket()
        val playerField =
            zombie.network.fields.character.PlayerID::class.java.getDeclaredField("player")
        playerField.setAccessible(true)
        playerField.set(packet.id, owner)
        packet.id.setID(7.toShort())
        packet.id.setPlayerIndex(0.toByte())
        packet.prediction.type = 1
        packet.prediction.x = 12.5f
        packet.prediction.y = 15.5f
        packet.prediction.z = 1
        packet.prediction.direction = -0.0f
        packet.prediction.moveDirection = .5f
        packet.prediction.speed = .75f
        packet.prediction.distance = 3
        val source = NativeTime.nativeTimeSourceEnter(packet, owner)
        check(source != null, "Explicit timeline opt-in required")
        owner.motion = "motion-after"
        owner.action = "action-after"
        NativeTime.nativeTimeSourceExit(packet, owner, source, null)
        val frozen =
            NativeTimeCheck.map<
                    zombie.network.packets.character.PlayerPacket,
                    NativeTime.NativeSource,
                >(
                    "nativeTimeSources",
                )
                .get(packet)!!
        check(
            frozen.generation == source.generation && frozen.end >= frozen.begin,
            "Source sample interval",
        )
        check(
            frozen.motionBegin.equals("motion-before") &&
                frozen.motionEnd.equals("motion-after") &&
                frozen.actionBegin.equals("action-before") &&
                frozen.actionEnd.equals("action-after"),
            "Semantic set sample not frozen",
        )
        val wire = ByteBuffer.allocate(256)
        wire.position(2)
        val wireWriter = zombie.core.network.ByteBufferWriter(wire)
        zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.doPacket(wireWriter)
        val begin = wire.position()
        packet.write(wireWriter)
        val end = wire.position()
        val nativeBody = NativeTime.nativeTimeBody(wire, begin, end)
        check(nativeBody.bytes == 32, "Native wire layout boundary")
        val repeated = NativeTime.nativeTimeSourceEnter(packet, owner)
        NativeTime.nativeTimeSourceExit(packet, owner, repeated, null)
        check(
            repeated!!.generation != source.generation,
            "Repeated payload conflated source generations",
        )
        val wire2 = ByteBuffer.allocate(256)
        packet.write(zombie.core.network.ByteBufferWriter(wire2))
        check(
            nativeBody.equals(NativeTime.nativeTimeBody(wire2, 0, wire2.position())),
            "Source tracing changed native wire",
        )
        // Exact destination writer mapping; no transport call is made.
        val connection =
            unsafe.allocateInstance(zombie.core.raknet.UdpConnection::class.java)
                as zombie.core.raknet.UdpConnection
        zombie.network.GameClient.connection = connection
        val writer = zombie.core.network.ByteBufferWriter(wire)
        NativeTime.nativeTimeStartActive(connection, writer, null)
        NativeTime.nativeTimeWrite(packet, writer, begin, null)
        val active = NativeTime.nativeTimeFinishEnter(connection)
        check(active != null, "Missing active native send")
        NativeTime.nativeTimeStartActive(
            connection,
            writer,
            null,
        ) // Simulates next lock owner before old exit advice.
        NativeTime.nativeTimeFinish(connection, active, true, null)
        check(
            NativeTime.nativeTimeFinishEnter(connection) != null,
            "Old completion removed new send",
        )
        // Acceptance requires exact persistent destination/source inside exact AI/packet scope.
        owner.local = false
        zombie.network.GameClient.IDToPlayerMap.put(7.toShort(), owner)
        val data = zombie.network.ZomboidNetData()
        val inputBuffer = wire.duplicate()
        inputBuffer.position(begin)
        inputBuffer.limit(end)
        val input = zombie.core.network.ByteBufferReader(inputBuffer)
        var ingressMono = System.nanoTime()
        data.read(
            zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),
            input,
            connection,
        )
        NativeTime.nativeTimeIngressRead(
            data,
            zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),
            input,
            connection,
            begin,
            end,
            ingressMono,
            null,
        )
        // VehicleID.parse resolves the wire ID through this ordinary in-memory manager.
        // Its constructor initializes maps/timers only; no world, socket or update loop starts.
        zombie.vehicles.VehicleManager.instance = zombie.vehicles.VehicleManager()
        val parsed = zombie.network.packets.character.PlayerPacket()
        val parseBegin = data.buffer.position()
        parsed.parse(data.buffer, connection)
        val parseEnd = data.buffer.position()
        NativeTime.nativeTimeParse(parsed, data.buffer, connection, parseBegin, null)
        check(
            data.buffer.position() == parseEnd &&
                NativeTime.nativeTimeBody(data.buffer.bb, parseBegin, parseEnd).equals(nativeBody),
            "Parsed span changed native cursor/body",
        )
        val receipt =
            NativeTimeCheck.map<
                    zombie.network.packets.character.PlayerPacket,
                    NativeTime.NativeReceipt,
                >(
                    "nativeTimeReceipts",
                )
                .get(parsed)
        check(
            receipt != null &&
                receipt.ingress > 0 &&
                receipt.type ==
                    zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId().toInt(),
            "Ingress receipt not associated by exact reader",
        )
        NativeTime.nativeTimeIngressReset(data)
        data.reset()
        check(
            NativeTimeCheck.map<zombie.core.network.ByteBufferReader, NativeTime.NativeIngress>(
                    "nativeTimeIngress",
                )
                .get(data.buffer) == null,
            "Pooled reader retained ingress generation",
        )
        inputBuffer.position(begin)
        ingressMono = System.nanoTime()
        data.read(
            zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),
            input,
            connection,
        )
        NativeTime.nativeTimeIngressRead(
            data,
            zombie.network.PacketTypes.PacketType.PlayerUpdateReliable.getId(),
            input,
            connection,
            begin,
            end,
            ingressMono,
            null,
        )
        check(
            NativeTimeCheck.map<zombie.core.network.ByteBufferReader, NativeTime.NativeIngress>(
                    "nativeTimeIngress",
                )
                .get(data.buffer)!!
                .generation != receipt.ingress,
            "Pooled reuse retained ingress generation",
        )
        val scope = NativeTime.nativeTimeCopyEnter(owner.ai, parsed)
        check(scope != null, "Exact AI copy scope unavailable")
        NativeTime.nativeTimeCopied(
            zombie.network.fields.character.Prediction(),
            parsed.prediction,
            null,
        )
        NativeTime.nativeTimeCopied(
            owner.ai.prediction,
            parsed.prediction,
            IllegalStateException("synthetic copy failure"),
        )
        check(
            NativeTime.timelineNativeSnapshot(owner).contains("\"nativeReceiveGeneration\":0"),
            "Foreign/failed copy accepted",
        )
        owner.ai.prediction.copy(parsed.prediction)
        NativeTime.nativeTimeCopied(owner.ai.prediction, parsed.prediction, null)
        NativeTime.nativeTimeCopyExit(scope)
        val generation = "\"nativeReceiveGeneration\":" + receipt.generation
        check(
            NativeTime.timelineNativeSnapshot(owner).contains(generation),
            "Exact copy not accepted",
        )
        NativeTime.nativeTimeCopied(owner.ai.prediction, parsed.prediction, null)
        val frozenSnapshot = NativeTime.timelineNativeSnapshot(owner)
        owner.ai.prediction = zombie.network.fields.character.Prediction()
        check(
            NativeTime.timelineNativeSnapshot(owner).contains("\"nativeReceiveGeneration\":0"),
            "Replaced persistent prediction retained old receipt",
        )
        check(frozenSnapshot.contains(generation), "Prepared snapshot mutated")
        val failed = Multiplayer::class.java.getDeclaredField("timelineFailed")
        failed.setAccessible(true)
        check(!failed.getBoolean(null), "Native tracing diagnostic failed")
        System.out.println("NATIVE_TIME_CHECK_PASS")
    }
}
