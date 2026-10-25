package net.alexredby.vehicleinventoryfixture

import java.nio.ByteBuffer
import me.zed_0xff.zombie_buddy.Loader
import net.bytebuddy.agent.builder.AgentBuilder
import net.bytebuddy.asm.MemberSubstitution
import net.bytebuddy.description.type.TypeDescription
import net.bytebuddy.matcher.ElementMatchers
import zombie.vehicles.VehicleInventoryOrderingChecks

/**
 * Substitute only the JNI invocation in Java Send; preserve native method flags and class shape.
 */
object NativeTransport {
    @JvmStatic
    fun install() {
        val instrumentation =
            Loader::class
                .java
                .getDeclaredField("g_instrumentation")
                .apply { isAccessible = true }
                .get(null) as java.lang.instrument.Instrumentation
        AgentBuilder.Default()
            .disableClassFormatChanges()
            .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
            .type(ElementMatchers.named<TypeDescription>("zombie.core.raknet.RakNetPeerInterface"))
            .transform(
                AgentBuilder.Transformer { builder, _, _, _, _ ->
                    builder.visit(
                        MemberSubstitution.strict()
                            .method(ElementMatchers.named("sendNative"))
                            .replaceWith(
                                NativeTransport::class
                                    .java
                                    .getMethod(
                                        "send",
                                        Any::class.java,
                                        ByteBuffer::class.java,
                                        Integer.TYPE,
                                        Integer.TYPE,
                                        Integer.TYPE,
                                        java.lang.Byte.TYPE,
                                        java.lang.Long.TYPE,
                                        java.lang.Boolean.TYPE,
                                    ),
                            )
                            .on(ElementMatchers.named("Send")),
                    )
                },
            )
            .installOn(instrumentation)
    }

    @JvmStatic
    fun send(
        peer: Any,
        bytes: ByteBuffer,
        length: Int,
        priority: Int,
        reliability: Int,
        channel: Byte,
        guid: Long,
        broadcast: Boolean,
    ): Int =
        VehicleInventoryOrderingChecks.transport(
            bytes,
            priority,
            reliability,
            channel,
            guid,
            broadcast,
        )
}
