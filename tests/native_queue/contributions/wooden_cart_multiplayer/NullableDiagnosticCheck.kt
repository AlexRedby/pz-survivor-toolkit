import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.lang.ref.WeakReference
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Modifier
import java.nio.charset.StandardCharsets.UTF_8
import net.alexredby.cartlab.ObserverAssociation
import net.alexredby.cartlab.ObserverParams
import org.joml.Matrix4f
import sun.misc.Unsafe
import zombie.characters.IsoPlayer
import zombie.core.skinnedmodel.model.SkinningData
import zombie.network.GameServer

/** Nullable Java diagnostic values stay JSON null and never poison the native observation. */
object NullableDiagnosticCheck {
    class NamelessOwner : IsoPlayer(null, null, 0, 0, 0) {
        override fun getUsername(): String? = null
    }

    @JvmStatic fun nullableBridge(player: IsoPlayer?): String? = null

    private fun invoke(owner: Any, name: String, vararg arguments: Any?): Any? {
        val method =
            owner.javaClass.declaredMethods
                .single { it.name == name }
                .apply {
                    isAccessible = true
                }
        try {
            return method.invoke(
                if (Modifier.isStatic(method.modifiers)) null else owner,
                *arguments,
            )
        } catch (error: InvocationTargetException) {
            throw error.targetException
        }
    }

    private fun field(owner: Any, name: String) =
        owner.javaClass.getDeclaredField(name).apply { isAccessible = true }

    private fun output(action: () -> Unit): String {
        val previous = System.out
        val bytes = ByteArrayOutputStream()
        try {
            PrintStream(bytes, true, UTF_8).use { capture ->
                System.setOut(capture)
                action()
            }
        } finally {
            System.setOut(previous)
        }
        return bytes.toString(UTF_8).trim()
    }

    @JvmStatic
    fun main(args: Array<String>) {
        check(System.getenv("PZ_CART_TIMELINE") == "true") {
            "Timeline must be enabled for bridge check"
        }
        val unsafe =
            Unsafe::class.java.getDeclaredField("theUnsafe").run {
                isAccessible = true
                get(null) as Unsafe
            }
        val associationFailed = field(ObserverAssociation, "observerAssociationFailed")
        val paramsFailed = field(ObserverParams, "opFailed")
        check(!associationFailed.getBoolean(null) && !paramsFailed.getBoolean(null))
        val row = output {
            invoke(
                ObserverAssociation,
                "observerWrite",
                "nullable",
                linkedMapOf("optional" to null, "text" to "null", "number" to 3, "flag" to true),
            )
        }
        check(
            row ==
                "[CART_OBSERVER] {\"event\":\"nullable\",\"optional\":null,\"text\":\"null\",\"number\":3,\"flag\":true}",
        ) {
            row
        }
        val params = output {
            invoke(ObserverParams, "opLog", "nullable", null, null, null, null, true, false)
        }
        check(
            params.startsWith("[CART_OBSERVER_PARAMS] {") && params.contains("\"reason\":null,"),
        ) {
            params
        }

        // The source serializer has its own loop. A native player's missing username is a real
        // nullable field supplied through observerRole(), independent of source token validity.
        val source = unsafe.allocateInstance(ObserverAssociation.ObserverSource::class.java)
        for ((name, value) in
            linkedMapOf(
                "life" to "1|01234567-89ab-cdef-0123-456789abcdef|1|2|3|4|5",
                "owner" to WeakReference<IsoPlayer>(null),
                "connection" to WeakReference<Any>(null),
            )) source.javaClass
            .getDeclaredField(name)
            .apply { isAccessible = true }
            .set(source, value)
        source.javaClass.getDeclaredField("begin").apply { isAccessible = true }.setLong(source, 5L)
        val previousOwner = IsoPlayer.getInstance()
        val previousServer = GameServer.server
        try {
            IsoPlayer.setInstance(
                unsafe.allocateInstance(NamelessOwner::class.java) as NamelessOwner,
            )
            GameServer.server = false
            val sourceRow = output {
                invoke(
                    ObserverAssociation,
                    "observerSourceLog",
                    "nullable-source",
                    source,
                    "test",
                    true,
                )
            }
            check(
                sourceRow.startsWith("[CART_OBSERVER] {") && sourceRow.contains("\"role\":null,"),
            ) {
                sourceRow
            }
        } finally {
            IsoPlayer.setInstance(previousOwner)
            GameServer.server = previousServer
        }
        var wrongTypeRejected = false
        val wrongTypeOutput = output {
            try {
                invoke(ObserverAssociation, "observerWrite", "wrong-type", mapOf("value" to Any()))
            } catch (expected: ClassCastException) {
                wrongTypeRejected = true
            }
        }
        check(wrongTypeRejected && wrongTypeOutput.isEmpty()) {
            "Wrong diagnostic type was coerced"
        }
        check(!associationFailed.getBoolean(null) && !paramsFailed.getBoolean(null)) {
            "Nullable logging poisoned the observers"
        }

        val nativeBridge = field(ClearanceProbe, "timelineInputBridge")
        val observerBridge = field(ClearanceProbe, "observerBridge")
        val previousNative = nativeBridge.get(null)
        val previousObserver = observerBridge.get(null)
        try {
            val bridge =
                NullableDiagnosticCheck::class
                    .java
                    .getMethod("nullableBridge", IsoPlayer::class.java)
            nativeBridge.set(null, bridge)
            observerBridge.set(null, bridge)
            val actual = invoke(ClearanceProbe, "nativeInputSnapshot", null)
            val expected =
                if (System.getenv("PZ_CART_OBSERVER_ASSOCIATION") == "true") "nullnull" else "null"
            check(actual == expected) {
                "Nullable reflection result changed Java concatenation: $actual"
            }
        } finally {
            nativeBridge.set(null, previousNative)
            observerBridge.set(null, previousObserver)
        }
        @Suppress("UNCHECKED_CAST")
        val solve = field(ClearanceProbe, "solve").get(null) as ThreadLocal<StringBuilder>
        val previousSolve = solve.get()
        try {
            solve.set(StringBuilder("["))
            val actor = unsafe.allocateInstance(SkinningData::class.java) as SkinningData
            actor.boneIndices = HashMap()
            // No bone exists, so the original native getter returns null without reading poses.
            val reach =
                ClearanceProbe.reachInput(arrayOf(null, actor, null, Matrix4f(), null, true, 1.0))
            check(reach?.startsWith("\"bone\":null,") == true && reach.endsWith("\"poses\":{}")) {
                reach.toString()
            }
        } finally {
            if (previousSolve == null) solve.remove() else solve.set(previousSolve)
        }
        println(
            "NULLABLE_DIAGNOSTIC_CHECK_PASS: three serializers, strict wrong-type refusal, nullable native bridges and reach input",
        )
    }
}
