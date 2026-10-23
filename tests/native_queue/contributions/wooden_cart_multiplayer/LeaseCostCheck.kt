import java.lang.reflect.Field
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import java.util.ArrayList
import java.util.HashMap
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract
import net.alexredby.cartlab.EquipmentLifetime
import net.alexredby.cartlab.LeaseControl
import net.alexredby.cartlab.NativeTime

// Pinned native command serialization/parser and read-only receipt checks; no world, socket or game
// launch.
object LeaseCostCheck {
    private val TYPE = zombie.network.PacketTypes.PacketType.ClientCommand.getId()
    private lateinit var unsafe: sun.misc.Unsafe
    private var generation: Long = 0
    private var callbackFailure: Throwable? = null
    private var callbacks: Int = 0
    private var nestedEvents: Int = 0
    private val active = ArrayDeque<Sample>()
    private val measured = ArrayList<Sample>()
    private val traceBytes = java.io.ByteArrayOutputStream()
    private val initialOut = System.out
    private val CLIENT =
        method(
            zombie.network.GameClient::class.java,
            "receiveClientCommand",
            zombie.core.network.ByteBufferReader::class.java,
            Short::class.javaPrimitiveType!!,
        )
    private val SERVER =
        method(
            zombie.network.GameServer::class.java,
            "receiveClientCommand",
            zombie.core.network.ByteBufferReader::class.java,
            zombie.core.raknet.UdpConnection::class.java,
            Short::class.javaPrimitiveType!!,
        )
    private var foreignConnection: Connection? = null
    private var membershipChecks: Int = 0
    private lateinit var engine: Engine
    private lateinit var connection: Connection
    private lateinit var player: Owner
    private lateinit var ingresses:
        NativeTime.NativeWeakMap<
            zombie.core.network.ByteBufferReader,
            LeaseControl.LeaseCommandIngress?,
        >
    private lateinit var callbackScopes: ThreadLocal<*>
    private lateinit var receiptFrames: ThreadLocal<*>

    open class Owner : zombie.characters.IsoPlayer(null, null, 0, 0, 0) {
        override fun getUsername(): String = "client1"

        override fun getOnlineID(): Short = 7
    }

    class Connection : zombie.core.raknet.UdpConnection(null, 1L, 0) {
        var guid = 1L

        override fun getConnectedGUID() = guid

        override fun getIndex(): Int = 0

        override fun getIDStr(): String = "lease-cost-native"
    }

    class Engine() : zombie.core.raknet.UdpEngine(0, 0, 1, null, false) {
        lateinit var activeConnections: HashMap<Long, zombie.core.raknet.UdpConnection>

        override fun getActiveConnection(guid: Long): zombie.core.raknet.UdpConnection? {
            return activeConnections[guid]
        }
    }

    class Peer : Owner() {
        override fun getOnlineID(): Short = 8
    }

    private class Sample(
        val module: String,
        val command: String,
        val mode: String,
        val server: Boolean,
        val table: Boolean,
        val order: ByteOrder,
        direct: Boolean,
    ) {
        val data: zombie.network.ZomboidNetData
        val buffer: ByteBuffer
        val begin: Int
        val end: Int
        val payload: Int
        val original: ByteArray
        var ingress: LeaseControl.LeaseCommandIngress? = null
        var receipt: String? = null
        var inner: Sample? = null

        init {
            buffer =
                (if (direct) ByteBuffer.allocateDirect(4096) else ByteBuffer.allocate(4096)).order(
                    order,
                )
            begin = 11
            buffer.position(begin - 3)
            val writer = zombie.core.network.ByteBufferWriter(buffer)
            zombie.network.PacketTypes.PacketType.ClientCommand.doPacket(writer)
            check(
                buffer.position() == begin &&
                    (buffer.get(begin - 3).toInt() and 255) == 134 &&
                    buffer.getShort(begin - 2) == TYPE,
                "Pinned native engine header changed",
            )
            if (server) writer.putByte(0)
            writer.putUTF(module)
            writer.putUTF(command)
            writer.putBoolean(table)
            if (table) zombie.network.TableNetworkUtils.save(table(), writer)
            if (mode.equals("trailing")) writer.putByte(99)
            end = buffer.position()
            payload = end - begin
            buffer.limit(end)
            buffer.position(begin)
            buffer.mark()
            original = bytes(buffer)
            data = zombie.network.ZomboidNetData()
            data.type = zombie.network.PacketTypes.PacketType.ClientCommand
            data.connection = 1
            field(zombie.network.ZomboidNetData::class.java, "buffer")
                .set(data, zombie.core.network.ByteBufferReader(buffer))
        }
    }

    private fun method(
        owner: Class<*>,
        name: String?,
        vararg args: Class<*>,
    ): java.lang.reflect.Method {
        try {
            val method = owner.getDeclaredMethod(name, *args)
            method.setAccessible(true)
            return method
        } catch (error: Exception) {
            throw ExceptionInInitializerError(error)
        }
    }

    private fun field(owner: Class<*>, name: String?): Field {
        val result = owner.getDeclaredField(name)
        result.setAccessible(true)
        return result
    }

    @OptIn(ExperimentalContracts::class)
    private fun check(condition: Boolean, text: String?) {
        contract { returns() implies condition }
        if (!condition) throw AssertionError(text)
    }

    private fun bytes(buffer: ByteBuffer?): ByteArray {
        val copy = buffer!!.duplicate()
        copy.clear()
        val result = ByteArray(copy.remaining())
        copy.get(result)
        return result
    }

    private fun mark(buffer: ByteBuffer?): Int {
        try {
            return buffer!!.duplicate().reset().position()
        } catch (missing: java.nio.InvalidMarkException) {
            return -1
        }
    }

    private fun table(): se.krka.kahlua.vm.KahluaTable? {
        val table = se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable()
        val nested = se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable()
        nested.rawset("inner", "кириллица/é")
        nested.rawset("number", 42.0)
        nested.rawset("yes", true)
        table.rawset("payload", nested)
        table.rawset("op", "UPDATE")
        table.rawset("seq", 3.0)
        return table
    }

    private fun receipt(sample: Sample?, module: String?, command: String?): String? {
        val buffer = sample!!.data.buffer.bb
        val at = buffer!!.position()
        val limit = buffer.limit()
        val mark = mark(buffer)
        val order = buffer.order()
        val before = bytes(buffer)
        val result = LeaseControl.cartLeaseReceipt(module, command)
        check(
            (sample.data.buffer.bb === buffer &&
                buffer.position() == at &&
                buffer.limit() == limit &&
                buffer.order() === order &&
                mark(buffer) == mark &&
                java.util.Arrays.equals(before, bytes(buffer))),
            "Receipt observation changed native buffer identity/content/state",
        )
        return result
    }

    private fun positive(sample: Sample?) {
        check(
            receipt(sample, sample!!.module + "foreign", sample.command) == null,
            "Foreign module matched native header",
        )
        check(
            receipt(sample, sample.module, sample.command + "foreign") == null,
            "Foreign command matched native header",
        )
        val wrong =
            if (sample.module.equals("CartLeaseProbe")) "CartLeaseLifetimes" else "CartLeaseProbe"
        check(
            receipt(sample, wrong, sample.command) == null,
            "Another allowed module matched native header",
        )
        val value = receipt(sample, sample.module, sample.command)
        if (value == null) {
            val scope = callbackScopes.get() as LeaseControl.LeaseCallbackScope?
            initialOut!!.println(
                "MISS server=" +
                    sample.server +
                    " scope=" +
                    scope +
                    " frames=" +
                    receiptFrames.get() +
                    " source=" +
                    LeaseControl.cartLeaseSource(player) +
                    " ingress=" +
                    LeaseControl.cartLeaseIngress() +
                    " position=" +
                    sample.buffer.position() +
                    " limit=" +
                    sample.buffer.limit(),
            )
            initialOut.println(traceBytes.toString(java.nio.charset.StandardCharsets.UTF_8))
        }
        check(value != null && value.length <= 160, "Exact native command receipt missing")
        check(
            value.equals(receipt(sample, sample.module, sample.command)),
            "Repeated API call allocated another receipt",
        )
        sample.receipt = value
        measured.add(sample)
        if (sample.mode.equals("nested")) {
            zombie.Lua.LuaEventManager.triggerEvent(
                "LeaseCostNested",
                sample.module,
                sample.command,
                table(),
            )
            check(
                value.equals(receipt(sample, sample.module, sample.command)),
                "Unrelated nested event damaged the native receipt",
            )
        }
        if (sample.inner != null) {
            invoke(sample.inner, true)
            check(
                value.equals(receipt(sample, sample.module, sample.command)),
                "Reentrant native callback replaced the outer receipt",
            )
            check(
                !value.equals(sample.inner!!.receipt),
                "Nested native callback reused the outer receipt",
            )
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun membership(server: Boolean) {
        val actual =
            if (server) LeaseControl.cartLeaseSource(player) else LeaseControl.cartLeaseIngress()
        check(
            actual === connection &&
                java.lang.Boolean.TRUE.equals(LeaseControl.cartLeaseConnectionActive(actual)),
            "Exact live native transport was not active",
        )
        check(
            LeaseControl.cartLeaseConnectionActive(null) == null,
            "Null connection acquired a transport status",
        )
        val unrelated = unsafe.allocateInstance(Connection::class.java) as Connection
        unrelated.guid = 3
        engine.activeConnections.put(3L, unrelated)
        try {
            check(
                LeaseControl.cartLeaseConnectionActive(unrelated) == null,
                "Uncaptured connection borrowed current engine membership",
            )
        } finally {
            engine.activeConnections.remove(3L)
        }
        check(
            LeaseControl.cartLeaseConnectionActive(foreignConnection) == null,
            "Captured foreign engine reported a retired connection",
        )
        val clientRole = zombie.network.GameClient.client
        val serverRole = zombie.network.GameServer.server
        zombie.network.GameClient.client = true
        zombie.network.GameServer.server = true
        try {
            check(
                LeaseControl.cartLeaseConnectionActive(actual) == null,
                "Mixed client/server role acquired transport status",
            )
        } finally {
            zombie.network.GameClient.client = clientRole
            zombie.network.GameServer.server = serverRole
        }
        val ownEngine =
            if (server) zombie.network.GameServer.udpEngine
            else zombie.network.GameClient.instance.udpEngine
        if (server) zombie.network.GameServer.udpEngine = null
        else zombie.network.GameClient.instance.udpEngine = null
        try {
            check(
                LeaseControl.cartLeaseConnectionActive(actual) == null,
                "Missing owning engine reported a disconnect",
            )
        } finally {
            if (server) zombie.network.GameServer.udpEngine = ownEngine
            else zombie.network.GameClient.instance.udpEngine = ownEngine
        }
        val failed = field(LeaseControl::class.java, "leaseControlFailed")
        failed.setBoolean(null, true)
        try {
            check(
                LeaseControl.cartLeaseConnectionActive(actual) == null,
                "Failed native observer returned transport status",
            )
        } finally {
            failed.setBoolean(null, false)
        }
        if (server) {
            val target = unsafe.allocateInstance(Peer::class.java) as Peer
            target.onlineId = 8
            target.playerIndex = 0
            val original = unsafe.allocateInstance(Connection::class.java) as Connection
            original.guid = 2
            original.players = arrayOf<zombie.characters.IsoPlayer?>(target, null, null, null)
            engine.activeConnections.put(2L, original)
            zombie.network.GameServer.IDToPlayerMap.put(8.toShort(), target)
            zombie.network.GameServer.PlayerToAddressMap.put(target, 2L)
            try {
                check(
                    LeaseControl.cartLeaseOwnerConnection(target) === original,
                    "Target native membership was not captured",
                )
                check(
                    java.lang.Boolean.TRUE.equals(LeaseControl.cartLeaseConnectionActive(original)),
                    "Captured target connection not active",
                )
                val retired =
                    field(EquipmentLifetime::class.java, "equipmentRetiredConnections").get(null)
                        as NativeTime.NativeWeakMap<zombie.core.raknet.UdpConnection, Boolean>
                retired.put(original, true)
                zombie.network.GameServer.IDToPlayerMap.remove(8.toShort())
                zombie.network.GameServer.PlayerToAddressMap.remove(target)
                try {
                    check(
                        java.lang.Boolean.TRUE.equals(
                            LeaseControl.cartLeaseConnectionActive(original),
                        ),
                        "Actor/equipment retirement was mistaken for transport disconnect",
                    )
                } finally {
                    retired.remove(original)
                }
                val replacement = unsafe.allocateInstance(Connection::class.java) as Connection
                replacement.guid = 2
                engine.activeConnections.put(2L, replacement)
                check(
                    java.lang.Boolean.FALSE.equals(
                        LeaseControl.cartLeaseConnectionActive(original),
                    ),
                    "Same-GUID replacement left old connection active",
                )
                check(
                    LeaseControl.cartLeaseConnectionActive(replacement) == null,
                    "Same-GUID replacement inherited original membership",
                )
                engine.activeConnections.remove(2L)
                check(
                    java.lang.Boolean.FALSE.equals(
                        LeaseControl.cartLeaseConnectionActive(original),
                    ),
                    "Removed exact GUID did not retire captured transport",
                )
            } finally {
                engine.activeConnections.remove(2L)
                zombie.network.GameServer.IDToPlayerMap.remove(8.toShort())
                zombie.network.GameServer.PlayerToAddressMap.remove(target)
            }
        }
        membershipChecks++
    }

    private fun event(frame: se.krka.kahlua.vm.LuaCallFrame?, count: Int) {
        val sample = active.peek()
        check(sample != null, "Native callback has no active fixture")
        callbacks++
        check(
            sample.module.equals(frame!!.get(0)) && sample.command.equals(frame.get(1)),
            "Native decoded header differs",
        )
        val args = frame.get(if (sample.server) 3 else 2)
        if (sample.table) {
            check(args is se.krka.kahlua.vm.KahluaTable, "Native nested table missing")
            val nested = args.rawget("payload") as se.krka.kahlua.vm.KahluaTable?
            check(
                nested != null &&
                    "кириллица/é".equals(nested.rawget("inner")) &&
                    java.lang.Double.valueOf(42.0).equals(nested.rawget("number")),
                "Original native table parser lost nested values",
            )
        } else check(args == null, "Empty native command unexpectedly acquired a table")
        if (sample.mode.equals("membership-capture")) {
            foreignConnection =
                if (sample.server) LeaseControl.cartLeaseSource(player) as Connection?
                else LeaseControl.cartLeaseIngress() as Connection?
            check(
                foreignConnection === connection &&
                    java.lang.Boolean.TRUE.equals(
                        LeaseControl.cartLeaseConnectionActive(foreignConnection),
                    ),
                "Foreign engine setup did not capture original transport",
            )
        } else if (sample.mode.equals("membership")) {
            membership(sample.server)
        } else if (sample.mode.equals("foreign-buffer")) {
            field(zombie.core.network.ByteBufferReader::class.java, "bb")
                .set(sample.data.buffer, sample.buffer.duplicate().order(sample.order))
            try {
                check(
                    receipt(sample, sample.module, sample.command) == null,
                    "Foreign buffer accepted",
                )
            } finally {
                field(zombie.core.network.ByteBufferReader::class.java, "bb")
                    .set(sample.data.buffer, sample.buffer)
            }
        } else if (sample.mode.equals("foreign-ingress")) {
            val foreign = LeaseControl.LeaseCommandIngress(++generation, sample.ingress!!.transport)
            ingresses.put(sample.data.buffer, foreign)
            check(
                receipt(sample, sample.module, sample.command) == null,
                "Foreign ingress generation accepted",
            )
        } else if (sample.mode.equals("reset")) {
            sample.data.reset()
            check(
                receipt(sample, sample.module, sample.command) == null,
                "Pooled reader reset retained receipt authority",
            )
        } else if (sample.mode.equals("changed-limit")) {
            sample.buffer.limit(sample.end + 1)
            try {
                check(
                    receipt(sample, sample.module, sample.command) == null,
                    "Changed original limit accepted",
                )
            } finally {
                sample.buffer.limit(sample.end)
            }
        } else if (sample.mode.equals("changed-order")) {
            sample.buffer.order(
                if (sample.order === ByteOrder.BIG_ENDIAN) ByteOrder.LITTLE_ENDIAN
                else ByteOrder.BIG_ENDIAN,
            )
            try {
                check(
                    receipt(sample, sample.module, sample.command) == null,
                    "Changed original byte order accepted",
                )
            } finally {
                sample.buffer.order(sample.order)
            }
        } else if (
            sample.mode.equals("trailing") ||
                sample.mode.equals("unguarded") ||
                sample.mode.equals("synthetic") ||
                sample.mode.equals("foreign-module")
        ) {
            check(
                receipt(sample, sample.module, sample.command) == null,
                "Partial, unguarded or synthetic callback obtained receipt",
            )
        } else positive(sample)
    }

    private fun roles(server: Boolean) {
        zombie.network.GameServer.server = server
        zombie.network.GameClient.client = !server
        zombie.network.GameServer.udpEngine = engine
        zombie.network.GameClient.instance.udpEngine = engine
        zombie.network.GameClient.instance.connected = true
        zombie.network.GameClient.connection = connection
        zombie.network.GameServer.IDToPlayerMap.put(7.toShort(), player)
        zombie.network.GameServer.PlayerToAddressMap.put(player, 1L)
        zombie.network.GameClient.IDToPlayerMap.put(7.toShort(), player)
    }

    private fun seed(sample: Sample?) {
        sample!!.ingress =
            LeaseControl.LeaseCommandIngress(
                ++generation,
                LeaseControl.LeaseTransport(
                    java.lang.ref.WeakReference(engine),
                    java.lang.ref.WeakReference(connection),
                    NativeTime.nativeTimeIdentity(connection, false),
                    1,
                    TYPE.toInt(),
                ),
            )
        ingresses.put(sample.data.buffer, sample.ingress)
    }

    private fun invoke(sample: Sample?, guarded: Boolean) {
        roles(sample!!.server)
        active.push(sample)
        if (guarded) seed(sample)
        var dispatch: LeaseControl.LeaseDispatchScope? = null
        if (!sample.server) dispatch = LeaseControl.leaseControlDispatchEnter(sample.data)
        try {
            if (sample.server) SERVER.invoke(null, sample.data.buffer, connection, TYPE)
            else CLIENT.invoke(null, sample.data.buffer, TYPE)
            if (callbackFailure != null)
                throw AssertionError("Native callback assertion failed", callbackFailure)
        } catch (failed: java.lang.reflect.InvocationTargetException) {
            val cause = failed.cause
            if (cause is Exception) throw cause
            throw AssertionError(cause)
        } finally {
            if (dispatch != null) LeaseControl.leaseControlDispatchExit(dispatch)
            ingresses.remove(sample.data.buffer)
            active.pop()
            if (active.isEmpty())
                check(
                    callbackScopes.get() == null && receiptFrames.get() == null,
                    "Native callback/frame cleanup leaked",
                )
        }
        check(
            LeaseControl.cartLeaseReceipt(sample.module, sample.command) == null,
            "Receipt escaped its native callback",
        )
        if (!sample.mode.equals("reset"))
            check(
                (sample.buffer.position() ==
                    (if (sample.mode.equals("trailing")) sample.end - 1 else sample.end) &&
                    sample.buffer.limit() == sample.end &&
                    sample.buffer.order() === sample.order &&
                    mark(sample.buffer) == sample.begin &&
                    java.util.Arrays.equals(sample.original, bytes(sample.buffer))),
                "Original parser/API changed native content/mark/limit/order",
            )
    }

    @Suppress("UNCHECKED_CAST")
    @JvmStatic
    fun main(argv: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val scratch =
            java.nio.file.Path.of(System.getenv("PZ_CART_RUNTIME_FILE"))
                .toAbsolutePath()
                .getParent()
                .getParent()
        zombie.ZomboidFileSystem.instance.setCacheDir(scratch.resolve("native-cache").toString())
        val access = field(sun.misc.Unsafe::class.java, "theUnsafe")
        unsafe = access.get(null) as sun.misc.Unsafe
        engine = unsafe.allocateInstance(Engine::class.java) as Engine
        engine.activeConnections = HashMap()
        connection = unsafe.allocateInstance(Connection::class.java) as Connection
        connection.guid = 1
        engine.activeConnections.put(1L, connection)
        player = unsafe.allocateInstance(Owner::class.java) as Owner
        player.onlineId = 7
        player.playerIndex = 0
        player.username = "client1"
        connection.players = arrayOf<zombie.characters.IsoPlayer?>(player, null, null, null)
        ingresses =
            field(LeaseControl::class.java, "leaseControlIngresses").get(null)
                as
                NativeTime.NativeWeakMap<
                    zombie.core.network.ByteBufferReader,
                    LeaseControl.LeaseCommandIngress?,
                >
        callbackScopes =
            field(LeaseControl::class.java, "leaseControlCallback").get(null) as ThreadLocal<*>
        receiptFrames =
            field(LeaseControl::class.java, "leaseReceiptFrames").get(null) as ThreadLocal<*>
        val platform = se.krka.kahlua.j2se.J2SEPlatform.getInstance()
        zombie.Lua.LuaManager.env = platform.newEnvironment()
        zombie.Lua.LuaManager.env.rawset("Events", platform.newTable())
        zombie.GameWindow.gameThread = Thread.currentThread()
        zombie.Lua.LuaManager.thread =
            se.krka.kahlua.vm.KahluaThread(platform, zombie.Lua.LuaManager.env)
        zombie.Lua.LuaManager.thread.debugOwnerThread = Thread.currentThread()
        zombie.Lua.LuaManager.caller =
            se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        zombie.Lua.LuaManager.env.rawset(
            "nativeLeaseCost",
            se.krka.kahlua.vm.JavaFunction { frame, count ->
                try {
                    event(frame, count)
                } catch (failure: Throwable) {
                    callbackFailure = failure
                }

                0
            },
        )
        zombie.Lua.LuaManager.env.rawset(
            "nestedLeaseCost",
            se.krka.kahlua.vm.JavaFunction { frame, count ->
                try {
                    val sample = checkNotNull(active.peek())
                    nestedEvents++
                    check(
                        receipt(sample, sample.module, sample.command) == null,
                        "Unrelated nested Lua event borrowed outer native receipt",
                    )
                    check(
                        LeaseControl.cartLeaseConnectionActive(connection) == null,
                        "Unrelated nested event borrowed connection membership scope",
                    )
                } catch (failure: Throwable) {
                    callbackFailure = failure
                }

                0
            },
        )
        val event =
            se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(
                "nativeLeaseCost(...)",
                "native-lease-cost",
                zombie.Lua.LuaManager.env,
            )
        zombie.Lua.LuaEventManager.AddEvent("OnClientCommand").callbacks.add(event)
        zombie.Lua.LuaEventManager.AddEvent("OnServerCommand").callbacks.add(event)
        zombie.Lua.LuaEventManager.AddEvent("LeaseCostNested")
            .callbacks
            .add(
                se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(
                    "nestedLeaseCost(...)",
                    "nested-lease-cost",
                    zombie.Lua.LuaManager.env,
                ),
            )
        val process = LeaseControl.cartLeaseSeed()
        val fresh = LeaseControl.cartLeaseChallengeSeed()
        val other = LeaseControl.cartLeaseChallengeSeed()
        check(
            (process != null &&
                process.equals(LeaseControl.cartLeaseSeed()) &&
                fresh != null &&
                other != null &&
                fresh.length <= 80 &&
                other.length <= 80 &&
                !fresh.equals(other) &&
                !fresh.equals(process) &&
                !other.equals(process)),
            "Fresh challenge seeds reused process/receiver namespace",
        )
        check(
            LeaseControl.cartLeaseReceipt("CartLeaseProbe", "Bind") == null,
            "No-scope receipt accepted",
        )
        check(
            LeaseControl.cartLeaseConnectionActive(connection) == null,
            "No-scope connection status accepted",
        )
        System.setOut(
            java.io.PrintStream(traceBytes, true, java.nio.charset.StandardCharsets.UTF_8),
        )
        try {
            val originalEngine = engine
            val originalConnection = connection
            engine = unsafe.allocateInstance(Engine::class.java) as Engine
            engine.activeConnections = HashMap()
            connection = unsafe.allocateInstance(Connection::class.java) as Connection
            connection.guid = 1
            connection.players = originalConnection!!.players
            engine.activeConnections.put(1L, connection)
            try {
                invoke(
                    Sample(
                        "CartLeaseLifetimes",
                        "Capture",
                        "membership-capture",
                        true,
                        false,
                        ByteOrder.BIG_ENDIAN,
                        false,
                    ),
                    true,
                )
            } finally {
                engine = originalEngine
                connection = originalConnection
            }
            for (server in booleanArrayOf(false, true)) invoke(
                Sample(
                    "CartLeaseLifetimes",
                    "Membership",
                    "membership",
                    server,
                    false,
                    ByteOrder.BIG_ENDIAN,
                    false,
                ),
                true,
            )
            check(
                membershipChecks == 2 && LeaseControl.cartLeaseConnectionActive(connection) == null,
                "Transport membership check escaped native callback",
            )
            for (server in booleanArrayOf(false, true)) for (module in
                arrayOf<String>(
                    "CartLeaseProbe",
                    "CartLeaseLifetimes",
                    "CartActionAdmissionProbe",
                )) invoke(
                Sample(module, "Query", "normal", server, true, ByteOrder.BIG_ENDIAN, false),
                true,
            )
            invoke(
                Sample(
                    "CartLeaseProbe",
                    "Empty",
                    "normal",
                    false,
                    false,
                    ByteOrder.LITTLE_ENDIAN,
                    true,
                ),
                true,
            )
            invoke(
                Sample(
                    "CartLeaseLifetimes",
                    "Nested",
                    "nested",
                    false,
                    true,
                    ByteOrder.BIG_ENDIAN,
                    false,
                ),
                true,
            )
            for (server in booleanArrayOf(false, true)) {
                val outer =
                    Sample(
                        "CartLeaseProbe",
                        "Outer",
                        "normal",
                        server,
                        true,
                        ByteOrder.BIG_ENDIAN,
                        false,
                    )
                outer.inner =
                    Sample(
                        "CartActionAdmissionProbe",
                        "Inner",
                        "normal",
                        server,
                        true,
                        ByteOrder.BIG_ENDIAN,
                        false,
                    )
                invoke(outer, true)
            }
            for (mode in
                arrayOf<String>(
                    "trailing",
                    "unguarded",
                    "foreign-buffer",
                    "foreign-ingress",
                    "changed-limit",
                    "changed-order",
                    "reset",
                )) invoke(
                Sample("CartLeaseLifetimes", mode, mode, false, true, ByteOrder.BIG_ENDIAN, false),
                !mode.equals("unguarded"),
            )
            invoke(
                Sample(
                    "UnownedModule",
                    "Foreign",
                    "foreign-module",
                    true,
                    true,
                    ByteOrder.BIG_ENDIAN,
                    false,
                ),
                true,
            )
            // A manually entered scope and synthetic event cannot stand in for the original native
            // parser.
            val synthetic =
                Sample(
                    "CartLeaseProbe",
                    "Synthetic",
                    "synthetic",
                    false,
                    true,
                    ByteOrder.BIG_ENDIAN,
                    false,
                )
            roles(false)
            seed(synthetic)
            val dispatch = LeaseControl.leaseControlDispatchEnter(synthetic.data)
            val scope = LeaseControl.leaseControlClientEnter(synthetic.data.buffer, TYPE)
            synthetic.buffer.position(synthetic.end)
            active.push(synthetic)
            try {
                check(
                    LeaseControl.cartLeaseReceipt(synthetic.module, synthetic.command) == null,
                    "Synthetic complete cursor bypassed native parser",
                )
                zombie.Lua.LuaEventManager.triggerEvent(
                    "OnServerCommand",
                    synthetic.module,
                    synthetic.command,
                    table(),
                )
            } finally {
                active.pop()
                LeaseControl.leaseControlCallbackExit(scope)
                LeaseControl.leaseControlDispatchExit(dispatch)
                ingresses.remove(synthetic.data.buffer)
            }
            check(
                callbackFailure == null &&
                    receiptFrames.get() == null &&
                    callbackScopes.get() == null,
                "Synthetic scope cleanup failed",
            )
            // Native header truncation throws before the event; neither duplicate decode nor
            // cleanup changes its state.
            val truncated =
                Sample(
                    "CartLeaseProbe",
                    "Truncated",
                    "normal",
                    false,
                    false,
                    ByteOrder.BIG_ENDIAN,
                    false,
                )
            truncated.buffer.limit(truncated.begin + 3)
            val before = callbacks
            try {
                invoke(truncated, true)
                throw AssertionError("Truncated native UTF header accepted")
            } catch (expected: java.nio.BufferUnderflowException) {}

            check(
                callbacks == before && receiptFrames.get() == null && callbackScopes.get() == null,
                "Truncated native parser emitted or leaked a callback",
            )
        } finally {
            System.setOut(initialOut)
        }
        val trace = traceBytes.toString(java.nio.charset.StandardCharsets.UTF_8)
        val lines =
            trace!!.lines().filter({ line -> line.startsWith("[CART_LEASE_BYTES] ") }).toList()
        check(
            lines.size == measured.size && measured.size == 12 && nestedEvents == 1,
            "Native byte rows are missing, duplicated or attributed to rejected calls",
        )
        val tokens = java.util.HashSet<String?>()
        for (sample in measured) {
            check(tokens.add(sample.receipt), "Receipt token reused across native callbacks")
            val matches =
                lines
                    .stream()
                    .filter({ line -> line!!.contains("\"receipt\":\"" + sample.receipt + "\"") })
                    .toList()
            check(matches.size == 1, "Exact native callback trace missing")
            val row = matches.get(0)
            check(
                (row!!.contains("\"payloadBytes\":" + sample.payload + ",") &&
                    row.contains("\"engineBytes\":" + (sample.payload + 3) + ",") &&
                    row.contains(
                        "\"direction\":\"" +
                            (if (sample.server) "client-to-server" else "server-to-client") +
                            "\"",
                    ) &&
                    row.contains("\"ingressGeneration\":" + sample.ingress!!.generation + ",")),
                "Native byte count/direction/source differs from serialized sample",
            )
        }
        check(
            !trace.contains("[CART_TIMELINE] ERROR"),
            "Native receipt observer failed closed unexpectedly",
        )
        for (line in lines) initialOut!!.println(line)
        initialOut!!.println(
            "LEASE_CONNECTION_ACTIVITY_CHECK_PASS roles=" +
                membershipChecks +
                " exact-map replacement removed-guid actor-retirement unknown foreign-engine missing-engine wrong-role scope fail-closed",
        )
        initialOut.println("LEASE_COST_CHECK_PASS rows=" + lines.size + " callbacks=" + callbacks)
    }
}
