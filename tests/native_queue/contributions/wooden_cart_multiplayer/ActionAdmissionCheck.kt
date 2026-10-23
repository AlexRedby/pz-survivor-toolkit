import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.lang.ref.WeakReference
import net.alexredby.cartlab.ActionAdmission
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionRecord
import net.alexredby.cartlab.ActionAdmission.ActionAdmissionScope
import net.alexredby.cartlab.LeaseControl
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.PacketTypes

/** Native action observations must serialize missing tokens and keep refusal absorbing. */
object ActionAdmissionCheck {
    private fun ensure(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @JvmStatic
    fun main(args: Array<String>) {
        ensure(
            ActionAdmission.ACTION_ADMISSION && LeaseControl.LEASE_CONTROL,
            "Admission regression requires the native observation flags",
        )
        val server = GameServer.server
        val client = GameClient.client
        val output = System.out
        val bytes = ByteArrayOutputStream()
        val capture = PrintStream(bytes, true, Charsets.UTF_8)
        try {
            GameServer.server = true
            GameClient.client = false
            val action =
                NetTimedAction().also {
                    it.type = "ToolkitWoodCartDrop"
                    it.action = se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable()
                }
            val state =
                Class.forName("zombie.core.Action").getDeclaredField("state").apply {
                    isAccessible = true
                }
            state.set(action, TransactionState.Request)
            val record =
                ActionAdmissionRecord().also {
                    it.action = WeakReference(action)
                    it.table = WeakReference(action.action)
                    it.actor = WeakReference(null)
                    it.connection = WeakReference(null)
                    it.item = WeakReference(null)
                    it.world = WeakReference(null)
                    it.transport =
                        LeaseControl.LeaseTransport(
                            WeakReference<UdpEngine>(null),
                            WeakReference<UdpConnection>(null),
                            1L,
                            1L,
                            PacketTypes.PacketType.NetTimedAction.getId().toInt(),
                        )
                    it.kind = action.type
                }
            val scope = ActionAdmissionScope(null, null, null, null)
            scope.starts.add(record)
            System.setOut(capture)
            ActionAdmission.actionAdmissionProcessExit(scope, null)
            ensure(
                !ActionAdmission.actionAdmissionFailed,
                "Pending null token disabled native observation: $bytes",
            )
            ensure(
                record.pendingLogged &&
                    record.stage == "terminal" &&
                    !record.accepted &&
                    !record.sourceValidated &&
                    !record.admittedBindingValid &&
                    record.reason == "admission-refused:token-unobserved" &&
                    record.token == null &&
                    record.bindingRefusal == null,
                "Missing native source/token acquired authority or changed refusal",
            )
            val rows =
                bytes
                    .toString(Charsets.UTF_8)
                    .lineSequence()
                    .filter {
                        it.startsWith("[CART_ADMISSION] ")
                    }
                    .toList()
            ensure(rows.size == 2, "Pending/refusal observations were not both emitted: $bytes")
            ensure(
                rows[0].startsWith("[CART_ADMISSION] {\"event\":\"pending\",") &&
                    rows[1].startsWith("[CART_ADMISSION] {\"event\":\"retired\",") &&
                    rows.all {
                        it.contains("\"token\":null,") &&
                            it.contains("\"tokenObserved\":false,") &&
                            it.contains("\"accepted\":false,") &&
                            it.contains("\"nativeState\":\"Request\",")
                    },
                "Native pending/refusal JSON lost nullable token or scalar types: $bytes",
            )
            // A later native state/token cannot revive an observation already refused.
            state.set(action, TransactionState.Accept)
            record.token = "later-token"
            ActionAdmission.actionAdmissionProcessExit(scope, null)
            ensure(
                !ActionAdmission.actionAdmissionFailed &&
                    record.stage == "terminal" &&
                    !record.accepted &&
                    !record.admittedBindingValid &&
                    bytes.toString(Charsets.UTF_8).lineSequence().count {
                        it.startsWith("[CART_ADMISSION] ")
                    } == 2,
                "Later native Accept/token revived a refused observation",
            )
        } finally {
            System.setOut(output)
            capture.close()
            GameServer.server = server
            GameClient.client = client
        }
        println(
            "ACTION_ADMISSION_CHECK_PASS nativeAction=true pendingNullToken=true refusalAbsorbing=true",
        )
    }
}
