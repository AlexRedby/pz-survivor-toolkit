package zombie.network.packets

import java.lang.reflect.Field
import java.nio.ByteBuffer
import net.alexredby.pztoolkitjavapatches.BytecodeSupport
import net.alexredby.pztoolkitjavapatches.ItemStatsDefaults
import sun.misc.Unsafe
import zombie.core.network.ByteBufferReader
import zombie.core.network.ByteBufferWriter
import zombie.inventory.InventoryItem
import zombie.inventory.types.Food

/** Exercise omitted native wire values against a reused packet and the real apply path. */
object ItemStatsChecks {
    private data class FloatStat(val field: String, val getter: String, val value: Float)
    private data class IntStat(val field: String, val getter: String, val value: Int, val omitted: Int)
    private val floats = arrayOf(
        FloatStat("cookingTime", "getCookingTime", 30f),
        FloatStat("minutesToCook", "getMinutesToCook", 31f),
        FloatStat("minutesToBurn", "getMinutesToBurn", 60f),
        FloatStat("hungChange", "getHungChange", -.25f),
        FloatStat("calories", "getCalories", 123.5f),
        FloatStat("proteins", "getProteins", 7.25f),
        FloatStat("lipids", "getLipids", 3.75f),
        FloatStat("carbohydrates", "getCarbohydrates", 22.5f),
        FloatStat("thirstChange", "getThirstChangeUnmodified", -.125f),
        FloatStat("painReduction", "getPainReduction", 1.5f),
        FloatStat("endChange", "getEndChange", -.0625f),
        FloatStat("stressChange", "getStressChangeUnmodified", -.375f),
        FloatStat("fatigueChange", "getFatigueChange", -.1875f),
        FloatStat("unhappyChange", "getUnhappyChangeUnmodified", 4.25f),
        FloatStat("boredomChange", "getBoredomChangeUnmodified", 5.5f),
        FloatStat("baseHunger", "getBaseHunger", -.5f)
    )
    private val integers = arrayOf(
        IntStat("fluReduction", "getFluReduction", 3, 0),
        IntStat("foodSicknessChange", "getFoodSicknessChange", 4, 0),
        IntStat("fertilizedTime", "getFertilizedTime", 1234, 0),
        IntStat("poisonDetectionLevel", "getPoisonDetectionLevel", 6, -1)
    )

    private fun require(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    private fun field(name: String): Field = ItemStatsPacket::class.java.getDeclaredField(name).apply { isAccessible = true }

    private fun floats(packet: ItemStatsPacket, nondefault: Boolean) {
        for (stat in floats) field(stat.field).setFloat(packet, if (nondefault) stat.value else 0f)
        for (stat in integers) field(stat.field).setInt(packet, if (nondefault) stat.value else stat.omitted)
    }

    private fun packet(nondefault: Boolean): ItemStatsPacket = ItemStatsPacket().apply {
        // Undefined ContainerID is a native world-free endpoint, not a replacement packet encoder.
        id = if (nondefault) 101 else 102
        condition = 1
        uses = 1
        heat = 1f
        isFood = true
        isCooked = nondefault
        isFrozen = nondefault
        isTainted = nondefault
        isBurnt = nondefault
        isAlcoholic = nondefault
        isFertilized = nondefault
        isWet = nondefault
        wetCooldown = if (nondefault) 77f else 0f
        poisonPower = if (nondefault) 9 else 0
        name = "ItemStats native regression"
        actualWeight = .25f
        floats(this, nondefault)
    }

    private fun wire(packet: ItemStatsPacket): ByteArray {
        val data = ByteBuffer.allocate(2048)
        packet.write(ByteBufferWriter(data))
        return data.array().copyOf(data.position())
    }

    private fun parse(receiver: ItemStatsPacket, data: ByteArray) {
        val input = ByteBuffer.wrap(data)
        receiver.parse(ByteBufferReader(input), null)
        require(!input.hasRemaining(), "native parse did not consume the complete payload: ${input.remaining()}")
    }

    private fun packetStats(packet: ItemStatsPacket, nondefault: Boolean, context: String) {
        for (stat in floats) {
            val expected = if (nondefault) stat.value else 0f
            val actual = field(stat.field).getFloat(packet)
            require(actual == expected, "$context ${stat.field}: $actual != $expected")
        }
        for (stat in integers) {
            val expected = if (nondefault) stat.value else stat.omitted
            val actual = field(stat.field).getInt(packet)
            require(actual == expected, "$context ${stat.field}: $actual != $expected")
        }
    }

    private fun food(unsafe: Unsafe): Food = (unsafe.allocateInstance(Food::class.java) as Food).apply {
        // Avoid starting a world or item factory. Application setters and getters remain native.
        conditionMax = 10
    }

    private fun apply(packet: ItemStatsPacket, item: InventoryItem) {
        ItemStatsPacket::class.java.getDeclaredMethod("applyItemStats", InventoryItem::class.java)
            .apply { isAccessible = true }.invoke(packet, item)
    }

    private fun foodStats(food: Food, nondefault: Boolean, context: String) {
        for (stat in floats) {
            val expected = if (nondefault) stat.value else 0f
            val actual = (Food::class.java.getMethod(stat.getter).invoke(food) as Number).toFloat()
            require(actual == expected, "$context applied ${stat.field}: $actual != $expected")
        }
        for (stat in integers) {
            val expected = if (nondefault) stat.value else stat.omitted
            val actual = if (stat.field == "foodSicknessChange") {
                // The public getter adjusts for age/cooked/burnt state; check the raw setter value.
                Food::class.java.getDeclaredField("foodSicknessChange").apply { isAccessible = true }.getInt(food)
            } else {
                (Food::class.java.getMethod(stat.getter).invoke(food) as Number).toInt()
            }
            require(actual == expected, "$context applied ${stat.field}: $actual != $expected")
        }
    }

    private fun ordinaryState(packet: ItemStatsPacket, nondefault: Boolean) {
        require(packet.id == (if (nondefault) 101 else 102) && packet.isFood && packet.heat == 1f &&
            packet.condition.toInt() == 1 && packet.uses == 1 && packet.actualWeight == .25f,
            "native unconditional packet values changed")
        require(packet.isCooked == nondefault && packet.isFrozen == nondefault && packet.isTainted == nondefault &&
            packet.isBurnt == nondefault && packet.isAlcoholic == nondefault && packet.isFertilized == nondefault &&
            packet.isWet == nondefault && packet.poisonPower.toInt() == (if (nondefault) 9 else 0),
            "native present bits changed")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        require(ItemStatsDefaults.SUPPORTED, "unsupported ItemStats defaults baseline")
        require(BytecodeSupport.supports("zombie/network/packets/ItemStatsPacket.class",
            "1b2cd2f150e418d8266cdee8ab671210f8676bf9fd02f596eb5265f1389eaa8a"), "unsupported native ItemStats packet")
        require(!BytecodeSupport.supports("zombie/network/packets/ItemStatsPacket.class", "unknown"),
            "unknown ItemStats bytecode accepted")
        val unsafe = Unsafe::class.java.getDeclaredField("theUnsafe").apply { isAccessible = true }.get(null) as Unsafe
        val nondefault = wire(packet(true))
        val defaults = wire(packet(false))
        require(nondefault.size - defaults.size == 16 * java.lang.Float.BYTES + 3 * Integer.BYTES + 1 + java.lang.Float.BYTES,
            "native writer did not omit the twenty defaults and guarded dry cooldown")

        // Reproduce before weaving: cached parse retains every preceding omitted scalar.
        val stale = ItemStatsPacket()
        parse(stale, nondefault)
        packetStats(stale, true, "original nondefault")
        parse(stale, defaults)
        packetStats(stale, true, "original reused omitted")
        require(stale.cookingTime == 30f && !stale.isCooked, "original stale cookingTime=30 not reproduced")
        val staleFood = food(unsafe)
        apply(stale, staleFood)
        foodStats(staleFood, true, "original reused omitted")
        val fresh = ItemStatsPacket()
        require(fresh.poisonDetectionLevel == 0, "original Java constructor poison default changed")
        parse(fresh, defaults)
        require(fresh.poisonDetectionLevel == 0, "original omitted poison sentinel mismatch not reproduced")
        val freshFood = food(unsafe)
        apply(fresh, freshFood)
        require(freshFood.poisonDetectionLevel == 0, "original fresh poison mismatch not applied")
        println("ITEM_STATS_ORIGINAL_STALE cookingTime=30 poisonDetectionLevel=6; fresh omitted poison=0, wire default=-1")

        val unsupported = packet(true)
        ItemStatsDefaults.reset(unsupported, false)
        packetStats(unsupported, true, "unsupported reset")
        ItemStatsDefaults.reset(null, false)
        ItemStatsDefaults.reset(null, true)

        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ItemStatsChecks::class.java.classLoader)
        require(nondefault.contentEquals(wire(packet(true))) && defaults.contentEquals(wire(packet(false))),
            "woven patch changed native writer bytes")
        val reused = ItemStatsPacket()
        val target = food(unsafe)
        repeat(3) {
            parse(reused, nondefault)
            packetStats(reused, true, "woven nondefault")
            ordinaryState(reused, true)
            apply(reused, target)
            foodStats(target, true, "woven nondefault")
            require(target.isWet && target.wetCooldown == 77f, "native wet cooldown application changed")
            parse(reused, defaults)
            packetStats(reused, false, "woven reused omitted")
            ordinaryState(reused, false)
            apply(reused, target)
            foodStats(target, false, "woven reused omitted")
            require(!target.isWet && target.wetCooldown == 77f,
                "dry packet applied omitted cooldown despite the native wet guard")
        }
        val clean = ItemStatsPacket()
        parse(clean, defaults)
        packetStats(clean, false, "woven fresh omitted")
        apply(clean, target)
        foodStats(target, false, "woven fresh omitted")

        // Native nonfood packets retain their short wire and never enter Food application.
        val nonfood = packet(false)
        nonfood.isFood = false
        nonfood.isWet = true
        nonfood.wetCooldown = 12.5f
        parse(reused, wire(nonfood))
        require(!reused.isFood && reused.isWet && reused.wetCooldown == 12.5f, "nonfood parse changed")
        val plain = unsafe.allocateInstance(InventoryItem::class.java) as InventoryItem
        plain.conditionMax = 10
        apply(reused, plain)
        require(plain.condition == 1 && plain.itemHeat == 1f && plain.isWet && plain.wetCooldown == 12.5f,
            "native nonfood application changed")
        nonfood.isWet = false
        parse(reused, wire(nonfood))
        apply(reused, plain)
        require(!plain.isWet && plain.wetCooldown == 12.5f, "native nonfood dry cooldown guard changed")
        println("ITEM_STATS_CHECKS_PASS (original stale30 and poison sentinel reproduced; native writer/parse reuse, all20 reset/applied, nondefaults, wet/dry, nonfood and unsupported guards)")
    }
}
