package zombie.network.packets

import java.nio.ByteBuffer
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.ItemStatsCharge
import sun.misc.Unsafe
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.inventory.InventoryItem
import zombie.inventory.types.DrainableComboItem
import zombie.inventory.types.Food
import zombie.scripting.objects.Item

/** Keep the native integer charge through the real multiplayer packet codec and apply path. */
object DrainableChargeChecks {
    private val unsafe =
        Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null)
            as Unsafe
    private val usedDeltaField =
        ItemStatsPacket::class.java.getDeclaredField("usedDelta").apply { isAccessible = true }
    private val applyStats =
        ItemStatsPacket::class
            .java
            .getDeclaredMethod("applyItemStats", InventoryItem::class.java)
            .apply { isAccessible = true }

    private data class ChargeCase(val name: String, val delta: Float, val partial: Int)

    private val cases =
        arrayOf(
            ChargeCase("plastic gun", .0009f, 414),
            ChargeCase("battery", .007f, 53),
            ChargeCase("binary fraction", .03125f, 13),
            ChargeCase("coarse fraction", .3f, 2),
        )

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun drainable(
        delta: Float,
        uses: Int = 0,
        weighted: Boolean = false,
    ): DrainableComboItem =
        (unsafe.allocateInstance(DrainableComboItem::class.java) as DrainableComboItem).apply {
            // Keep construction world-free while exercising the native setters and weight logic.
            // Native weight getters distinguish display names from unresolved full types.
            module = "Base"
            type = "DrainableChargeRegression"
            name = "Drainable charge regression"
            conditionMax = 10
            useDelta = delta
            if (weighted) {
                scriptItem =
                    (unsafe.allocateInstance(Item::class.java) as Item).apply {
                        actualWeight = 2f
                    }
                weightEmpty = .25f
            }
            currentUses = uses
        }

    private fun packet(source: DrainableComboItem): ItemStatsPacket =
        ItemStatsPacket().apply {
            // Undefined ContainerID is the native world-free writer endpoint.
            id = 123
            condition = 7
            uses = source.currentUses
            usedDeltaField.setFloat(this, source.currentUsesFloat)
            heat = 1.25f
            isWet = true
            wetCooldown = 37f
        }

    private fun wire(packet: ItemStatsPacket): ByteArray {
        val data = ByteBuffer.allocate(2048)
        packet.write(ByteBufferWriter(data))
        return data.array().copyOf(data.position())
    }

    private fun parse(receiver: ItemStatsPacket, bytes: ByteArray): ItemStatsPacket {
        val input = ByteBuffer.wrap(bytes)
        receiver.parse(ByteBufferReader(input), null)
        require(!input.hasRemaining(), "native parse left ${input.remaining()} charge bytes")
        return receiver
    }

    private fun apply(packet: ItemStatsPacket, item: InventoryItem) {
        applyStats.invoke(packet, item)
    }

    private fun ordinaryState(packet: ItemStatsPacket, item: InventoryItem, context: String) {
        require(
            packet.id == 123 &&
                packet.condition == 7 &&
                packet.heat == 1.25f &&
                packet.isWet &&
                packet.wetCooldown == 37f,
            "$context changed unrelated packet values",
        )
        require(
            item.condition == 7 && item.itemHeat == 1.25f && item.isWet && item.wetCooldown == 37f,
            "$context changed unrelated applied values",
        )
    }

    private fun original() {
        for (case in cases.take(2)) {
            for (count in intArrayOf(case.partial, drainable(case.delta).maxUses)) {
                val source = drainable(case.delta, count)
                val received = parse(ItemStatsPacket(), wire(packet(source)))
                val target = drainable(case.delta)
                apply(received, target)
                require(received.uses == count, "${case.name} lost the native wire integer")
                require(
                    target.currentUses == count - 1,
                    "${case.name} native charge loss not reproduced: $count/${target.currentUses}",
                )
                println(
                    "DRAINABLE_CHARGE_ORIGINAL ${case.name} wire=$count applied=${target.currentUses}",
                )
            }
        }
    }

    private fun unchanged(
        packet: ItemStatsPacket?,
        target: DrainableComboItem,
        supported: Boolean,
        context: String,
    ) {
        val before = target.currentUses
        val weight = target.actualWeight
        ItemStatsCharge.restore(packet, target, supported)
        require(
            target.currentUses == before && target.actualWeight == weight,
            "$context did not retain the native result",
        )
    }

    private fun guards() {
        val source = drainable(.007f, 53)
        val packet = packet(source)
        unchanged(packet, drainable(.007f, 52), false, "unsupported bytecode")
        unchanged(null, drainable(.007f, 52), true, "null packet")
        ItemStatsCharge.restore(packet, null, true)
        ItemStatsCharge.restore(null, null, false)
        for (count in intArrayOf(-1, Int.MIN_VALUE, source.maxUses + 100, Int.MAX_VALUE)) {
            packet.uses = count
            unchanged(packet, drainable(.007f, 52), true, "invalid uses $count")
        }
        packet.uses = 53
        for (delta in
            floatArrayOf(0f, -.007f, 1.1f, Float.MIN_VALUE, Float.NaN, Float.POSITIVE_INFINITY)) {
            unchanged(packet, drainable(delta, 52), true, "invalid item useDelta $delta")
        }
        for (delta in floatArrayOf(-1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            usedDeltaField.setFloat(packet, delta)
            unchanged(packet, drainable(.007f, 52), true, "invalid packet usedDelta $delta")
        }
        usedDeltaField.setFloat(packet, .1f)
        unchanged(packet, drainable(.007f, 52), true, "inconsistent packet integer and delta")
    }

    private fun nativeFallback() {
        val malformed =
            arrayOf(
                -1 to (53 * .007f),
                Int.MAX_VALUE to (53 * .007f),
                53 to .1f,
                53 to Float.NaN,
                53 to Float.POSITIVE_INFINITY,
                53 to -.25f,
            )
        for ((count, delta) in malformed) {
            val sent =
                packet(drainable(.007f, 53)).apply {
                    uses = count
                    usedDeltaField.setFloat(this, delta)
                }
            val received = parse(ItemStatsPacket(), wire(sent))
            val target = drainable(.007f)
            apply(received, target)
            val nativeUses = (target.maxUses.toFloat() * delta).toInt()
            require(
                target.currentUses == nativeUses,
                "malformed uses=$count delta=$delta changed the native fallback",
            )
            ordinaryState(received, target, "malformed charge fallback")
        }
    }

    private fun woven() {
        val reused = ItemStatsPacket()
        for (case in cases) {
            val full = drainable(case.delta).apply { currentUsesFloat = 1f }.currentUses
            val counts =
                intArrayOf(0, 1, case.partial, drainable(case.delta).maxUses, full).distinct()
            for (count in counts) {
                val source = drainable(case.delta, count)
                val sent = packet(source)
                val bytes = wire(sent)
                val target = drainable(case.delta, weighted = true)
                repeat(5) { round ->
                    val received = parse(reused, bytes)
                    require(received.uses == count, "${case.name} changed wire integer $count")
                    apply(received, target)
                    require(
                        target.currentUses == count,
                        "${case.name} round $round charge: ${target.currentUses} != $count",
                    )
                    val expectedWeight = (2f - .25f) * source.currentUsesFloat + .25f
                    require(
                        target.actualWeight == expectedWeight && target.isCustomWeight,
                        "${case.name} charge correction did not update native drainable weight",
                    )
                    ordinaryState(received, target, "${case.name} round $round")
                    // Relay the current receiver through the real writer, as the next sync does.
                    val relay = parse(ItemStatsPacket(), wire(packet(target)))
                    apply(relay, target)
                    require(
                        target.currentUses == count,
                        "${case.name} repeated sync drained charge",
                    )
                }
                require(bytes.contentEquals(wire(sent)), "woven patch changed native writer bytes")
            }
        }

        val food =
            (unsafe.allocateInstance(Food::class.java) as Food).apply {
                module = "Base"
                type = "OrdinaryChargeRegression"
                name = "Ordinary charge regression"
                conditionMax = 10
                currentUses = 11
            }
        val ordinary = parse(ItemStatsPacket(), wire(packet(drainable(.007f, 53))))
        apply(ordinary, food)
        require(food.currentUses == 11, "charge patch changed a non-drainable item")
        ordinaryState(ordinary, food, "non-drainable")
        ItemStatsCharge.restore(ordinary, food, true)
        require(food.currentUses == 11, "charge helper changed a non-drainable item")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        require(ItemStatsCharge.SUPPORTED, "unsupported drainable charge baseline")
        require(
            !BytecodeSupport.supports("zombie/network/packets/ItemStatsPacket.class", "unknown"),
            "unknown ItemStats bytecode accepted",
        )
        original()
        guards()
        val before = cases.map { wire(packet(drainable(it.delta, it.partial))) }
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches(
            "net.alexredby.pztoolkitjavapatches",
            DrainableChargeChecks::class.java.classLoader,
        )
        cases.forEachIndexed { index, case ->
            require(
                before[index].contentEquals(wire(packet(drainable(case.delta, case.partial)))),
                "${case.name} weaving changed native writer bytes",
            )
        }
        woven()
        nativeFallback()
        guards()
        println("DRAINABLE_CHARGE_CHECKS_PASS")
    }
}
