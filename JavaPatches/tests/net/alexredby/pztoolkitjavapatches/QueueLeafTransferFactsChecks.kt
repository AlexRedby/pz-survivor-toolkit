package net.alexredby.pztoolkitjavapatches

import java.util.ArrayList
import se.krka.kahlua.converter.KahluaConverterManager
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.J2SEPlatform
import se.krka.kahlua.j2se.KahluaTableImpl
import se.krka.kahlua.luaj.compiler.LuaCompiler
import se.krka.kahlua.vm.KahluaThread
import sun.misc.Unsafe
import zombie.Lua.KahluaNumberConverter
import zombie.Lua.LuaManager
import zombie.characters.BodyDamage.BodyDamage
import zombie.characters.AttachedItems.AttachedItems
import zombie.characters.AttachedItems.AttachedItem
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.characters.WornItems.WornItem
import zombie.characters.WornItems.WornItems
import zombie.core.TilePropertyAliasMap
import zombie.core.properties.IsoPropertyType
import zombie.core.properties.PropertyContainer
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.ComboItem
import zombie.inventory.types.Food
import zombie.inventory.types.InventoryContainer
import zombie.inventory.types.Radio
import zombie.iso.IsoCell
import zombie.iso.IsoChunk
import zombie.iso.IsoChunkMap
import zombie.iso.IsoDirections
import zombie.iso.IsoGridSquare
import zombie.iso.IsoMovingObject
import zombie.iso.IsoObject
import zombie.iso.IsoWorld
import zombie.iso.objects.IsoBarricade
import zombie.iso.objects.IsoThumpable
import zombie.iso.objects.IsoWorldInventoryObject
import zombie.iso.sprite.IsoSprite
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.util.list.PZArrayList

/** Real native fixtures; no game client, action, item factory or native transfer is started. */
object QueueLeafTransferFactsChecks {
    private val unsafe = Unsafe::class.java.getDeclaredField("theUnsafe")
        .apply { isAccessible = true }.get(null) as Unsafe
    private fun verify(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }
    private fun field(type: Class<*>, target: Any, name: String, value: Any?) {
        type.getDeclaredField(name).apply { isAccessible = true }.set(target, value)
    }
    private fun <T> bare(type: Class<T>): T = type.cast(unsafe.allocateInstance(type))

    private class ForeignItem : InventoryItem("Base", "foreign", "foreign", "foreign") {
        override fun getID(): Int = throw AssertionError("foreign item getter invoked")
    }
    private class ForeignList : ArrayList<InventoryItem>() {
        override fun get(index: Int): InventoryItem = throw AssertionError("foreign list getter invoked")
    }

    private class Fixture(world: Boolean = false, thumpable: Boolean = false) {
        val actor = bare(IsoPlayer::class.java)
        val root = container("inventory", actor)
        val item = item(ComboItem::class.java, 17)
        val bag = item(InventoryContainer::class.java, 23)
        val destination = container(if (world) "crate" else "bag", null)
        val origin = square(2, 2)
        val target = square(3, 2)
        val parent: IsoObject? = if (world) bare(if (thumpable) IsoThumpable::class.java else IsoObject::class.java) else null
        private val body = bare(BodyDamage::class.java)
        init {
            field(IsoGameCharacter::class.java, actor, "health", 100f)
            field(BodyDamage::class.java, body, "overallBodyHealth", 100f)
            field(IsoGameCharacter::class.java, actor, "bodyDamage", body)
            field(IsoGameCharacter::class.java, actor, "inventory", root)
            field(IsoPlayer::class.java, actor, "playerIndex", 0)
            field(IsoMovingObject::class.java, actor, "current", origin)
            val worn = bare(WornItems::class.java)
            field(WornItems::class.java, worn, "items", ArrayList<WornItem>())
            field(IsoGameCharacter::class.java, actor, "wornItems", worn)
            val attached = bare(AttachedItems::class.java)
            field(AttachedItems::class.java, attached, "items", ArrayList<AttachedItem>())
            field(IsoGameCharacter::class.java, actor, "attachedItems", attached)
            IsoPlayer.players[0] = actor
            IsoPlayer.numPlayers = 1
            field(InventoryItem::class.java, item, "container", root)
            field(InventoryItem::class.java, bag, "container", root)
            root.items.add(item)
            if (world) {
                field(IsoObject::class.java, parent!!, "square", target)
                field(IsoObject::class.java, parent, "container", destination)
                field(ItemContainer::class.java, destination, "parent", parent)
                field(ItemContainer::class.java, destination, "sourceGrid", target)
                target.getObjects().add(parent)
                cell(origin, target)
            } else {
                field(InventoryContainer::class.java, bag, "container", destination)
                field(ItemContainer::class.java, destination, "containingItem", bag)
                root.items.add(bag)
            }
        }
        fun read(id: Double = 17.0, kind: String? = "Base.Leaf") =
            QueueLeafTransferFacts.read(actor, item, root, destination, id, kind, true, true)
        fun sprite(properties: PropertyContainer) {
            val sprite = bare(IsoSprite::class.java)
            field(IsoSprite::class.java, sprite, "properties", properties)
            field(IsoObject::class.java, parent!!, "sprite", sprite)
        }
        fun worn() {
            val entry = bare(WornItem::class.java)
            field(WornItem::class.java, entry, "item", item)
            field(WornItems::class.java, actor.getWornItems(), "items", arrayListOf(entry))
        }
    }

    private fun container(type: String, parent: IsoObject?): ItemContainer = bare(ItemContainer::class.java).also {
        field(ItemContainer::class.java, it, "type", type)
        field(ItemContainer::class.java, it, "parent", parent)
        field(ItemContainer::class.java, it, "items", ArrayList<InventoryItem>())
    }
    private fun <T : InventoryItem> item(type: Class<T>, id: Int): T = bare(type).also {
        it.id = id
        field(InventoryItem::class.java, it, "fullType", "Base.Leaf")
        field(InventoryItem::class.java, it, "module", "Base")
        field(InventoryItem::class.java, it, "type", "Leaf")
        field(InventoryItem::class.java, it, "attachedSlot", -1)
    }
    private fun square(x: Int, y: Int): IsoGridSquare = bare(IsoGridSquare::class.java).also {
        field(IsoGridSquare::class.java, it, "x", x)
        field(IsoGridSquare::class.java, it, "y", y)
        field(IsoGridSquare::class.java, it, "objects", PZArrayList(IsoObject::class.java, 8))
        field(IsoGridSquare::class.java, it, "specialObjects", ArrayList<IsoObject>())
        field(IsoGridSquare::class.java, it, "nav", arrayOfNulls<IsoGridSquare>(8))
    }
    private fun cell(vararg loaded: IsoGridSquare) {
        val cell = bare(IsoCell::class.java)
        val chunk = bare(IsoChunk::class.java)
        val squares = arrayOf(arrayOfNulls<IsoGridSquare>(64))
        for (square in loaded) squares[0][square.getX() + square.getY() * 8] = square
        field(IsoChunk::class.java, chunk, "squares", squares)
        field(IsoChunk::class.java, chunk, "minLevel", 0)
        field(IsoChunk::class.java, chunk, "maxLevel", 0)
        field(IsoChunk::class.java, chunk, "loaded", true)
        val map = bare(IsoChunkMap::class.java)
        field(IsoChunkMap::class.java, map, "chunksSwapA", arrayOf(chunk))
        field(IsoChunkMap::class.java, map, "chunksSwapB", arrayOf(chunk))
        field(IsoCell::class.java, cell, "chunkMap", arrayOf(map))
        IsoChunkMap.chunkGridWidth = 1
        IsoChunkMap.chunkWidthInTiles = 8
        IsoWorld.instance.currentCell = cell
    }

    private fun mutations() {
        fun rejected(message: String, world: Boolean = false, change: (Fixture) -> Unit) {
            val fixture = Fixture(world)
            verify(fixture.read() != null, "invalid baseline: $message")
            change(fixture)
            verify(fixture.read() == null, message)
        }
        rejected("changed ID") { it.item.id = 18 }
        rejected("changed type") { field(InventoryItem::class.java, it.item, "fullType", "Base.Other") }
        rejected("changed location") { field(InventoryItem::class.java, it.item, "container", it.destination) }
        rejected("missing root reference") { it.root.items.clear() }
        rejected("duplicate root reference") { it.root.items.add(it.item) }
        rejected("duplicate root ID") { it.root.items.add(item(ComboItem::class.java, 17)) }
        rejected("opposite ID") { it.destination.items.add(item(ComboItem::class.java, 17)) }
        rejected("nested opposite bag hides duplicate") {
            val nested = item(InventoryContainer::class.java, 99)
            val contents = container("bag", null)
            contents.items.add(item(ComboItem::class.java, 17))
            field(InventoryContainer::class.java, nested, "container", contents)
            it.destination.items.add(nested)
        }
        rejected("foreign native list") { field(ItemContainer::class.java, it.destination, "items", ForeignList()) }
        rejected("consumed item") { field(InventoryItem::class.java, it.item, "isCraftingConsumed", true) }
        rejected("attached item") { field(InventoryItem::class.java, it.item, "attachedSlot", 0) }
        rejected("hand item") { field(IsoGameCharacter::class.java, it.actor, "leftHandItem", it.item) }
        rejected("worn item") { it.worn() }
        rejected("attached native list with stale negative slot") {
            val entry = bare(AttachedItem::class.java)
            field(AttachedItem::class.java, entry, "item", it.item)
            field(AttachedItems::class.java, it.actor.getAttachedItems(), "items", arrayListOf(entry))
        }
        rejected("foreign worn list") {
            field(WornItems::class.java, it.actor.getWornItems(), "items", ForeignList())
        }
        rejected("foreign attached list") {
            field(AttachedItems::class.java, it.actor.getAttachedItems(), "items", ForeignList())
        }
        rejected("raw equipped parent") { field(InventoryItem::class.java, it.item, "equipParent", it.actor) }
        rejected("world item") { field(InventoryItem::class.java, it.item, "worldItem", bare(IsoWorldInventoryObject::class.java)) }
        rejected("lit transformation") { field(InventoryItem::class.java, it.item, "type", "CandleLit") }
        rejected("root parent") { field(ItemContainer::class.java, it.root, "parent", null) }
        rejected("root special type") { field(ItemContainer::class.java, it.root, "type", "microwave") }
        rejected("root acceptance") { field(ItemContainer::class.java, it.root, "acceptItemFunction", "MustNeverRun") }
        rejected("destination acceptance") { field(ItemContainer::class.java, it.destination, "acceptItemFunction", "MustNeverRun") }
        rejected("destination category") { field(ItemContainer::class.java, it.destination, "onlyAcceptCategory", "Food") }
        rejected("owner left root") { field(InventoryItem::class.java, it.bag, "container", it.destination) }
        rejected("owner inventory changed") { field(InventoryContainer::class.java, it.bag, "container", it.root) }
        rejected("owner ID alias") { it.root.items.add(item(ComboItem::class.java, 23)) }
        rejected("foreign local player") { IsoPlayer.players[0] = null }
        rejected("dead actor") { field(IsoGameCharacter::class.java, it.actor, "health", 0f) }
        rejected("detached world anchor", true) { it.target.getObjects().clear() }
        rejected("world parent does not own endpoint", true) { field(IsoObject::class.java, it.parent!!, "container", null) }
        rejected("wrong source square", true) { field(ItemContainer::class.java, it.destination, "sourceGrid", it.origin) }
        rejected("out of reach", true) { field(IsoGridSquare::class.java, it.target, "x", 5) }
        rejected("different level", true) { field(IsoGridSquare::class.java, it.target, "z", 1) }
        rejected("favorite world return", true) { field(InventoryItem::class.java, it.item, "favorite", true) }
        rejected("unsupported storage", true) { field(ItemContainer::class.java, it.destination, "type", "fridge") }
        val aliases = hashMapOf("CustomName" to arrayListOf("Toaster"), "GroupName" to arrayListOf("Coffee", "Espresso"))
        TilePropertyAliasMap.instance.Generate(aliases)
        for ((property, value) in listOf(IsoPropertyType.CUSTOM_NAME to "Toaster", IsoPropertyType.GROUP_NAME to "Coffee", IsoPropertyType.GROUP_NAME to "Espresso")) {
            rejected("restricted sprite acceptance $value", true) {
                val properties = PropertyContainer()
                properties.set(property, value)
                verify(properties.get(property) == value, "property fixture $value")
                it.sprite(properties)
            }
        }
        val thump = Fixture(true, true)
        verify(thump.read() != null, "ordinary thumpable")
        field(IsoThumpable::class.java, thump.parent!!, "locked", true)
        verify(thump.read() == null, "locked thumpable")
        val barricaded = Fixture(true, true)
        val barricade = bare(IsoBarricade::class.java)
        field(IsoObject::class.java, barricade, "dir", IsoDirections.W)
        barricaded.target.getSpecialObjects().add(barricade)
        verify(barricaded.read() == null, "same-side barricade")
        val opposite = Fixture(true, true)
        val west = opposite.origin // Canonical cell contains this square; target nav[] remains empty.
        val back = bare(IsoBarricade::class.java)
        field(IsoObject::class.java, back, "dir", IsoDirections.E)
        west.getSpecialObjects().add(back)
        verify(opposite.read() == null, "opposite barricade hidden by absent nav")
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        GameClient.client = false
        GameServer.server = false
        verify(QueueLeafTransferFacts.SUPPORTED, "installed bytecode is unsupported")
        // The canonical opposite-side cell lookup and final equipment element getters
        // cannot dispatch a foreign subclass. A future non-final shape needs a new audit.
        for (type in listOf(WornItems::class.java, WornItem::class.java,
            AttachedItems::class.java, AttachedItem::class.java, IsoGridSquare::class.java,
            IsoWorld::class.java, IsoCell::class.java, IsoChunkMap::class.java, IsoChunk::class.java)) {
            verify(java.lang.reflect.Modifier.isFinal(type.modifiers), "native dispatch class is no longer final: ${type.name}")
        }
        val small = Fixture()
        val result = small.read() ?: throw AssertionError("ordinary carried return")
        verify(result.getMetatable() == null && result.getRewriteTable() == null && result.delegate.size == 7, "plain exact DTO")
        verify(result.delegate["schema"] == 1.0 && result.delegate["item"] === small.item
            && result.delegate["source"] === small.root && result.delegate["destination"] === small.destination
            && result.delegate["location"] === small.root && result.delegate["id"] == 17.0
            && result.delegate["fullType"] == "Base.Leaf", "DTO fields")
        field(InventoryItem::class.java, small.item, "favorite", true)
        verify(small.read() != null, "favorite carried return")
        for (id in listOf(Double.NaN, Double.POSITIVE_INFINITY, 17.5, Int.MAX_VALUE.toDouble() + 1)) verify(small.read(id) == null, "invalid ID $id")
        verify(small.read(kind = "") == null, "empty type")
        for (type in listOf(Food::class.java, Radio::class.java, InventoryContainer::class.java, ForeignItem::class.java)) {
            val unsupported = item(type, 17)
            verify(QueueLeafTransferFacts.read(small.actor, unsupported, small.root, small.destination, 17.0, "Base.Leaf", true, true) == null, "unsupported leaf ${type.simpleName}")
        }
        verify(QueueLeafTransferFacts.read(small.actor, small.item, small.root, small.destination, 17.0, "Base.Leaf", false, true) == null, "unsupported gate")
        verify(QueueLeafTransferFacts.read(small.actor, small.item, small.root, small.destination, 17.0, "Base.Leaf", true, false) == null, "owner gate")
        mutations()
        val near = Fixture()
        while (near.root.items.size < QueueLeafTransferFacts.MAX_ENTRIES) near.root.items.add(item(ComboItem::class.java, 10000 + near.root.items.size))
        while (near.destination.items.size < QueueLeafTransferFacts.MAX_ENTRIES) near.destination.items.add(item(ComboItem::class.java, 20000 + near.destination.items.size))
        verify(near.read() != null, "bounded large direct lists")
        near.destination.items.add(item(ComboItem::class.java, 30000))
        verify(near.read() == null, "destination bound")
        near.destination.items.removeAt(near.destination.items.lastIndex)
        near.root.items.add(item(ComboItem::class.java, 30000))
        verify(near.read() == null, "source bound")
        near.root.items.removeAt(near.root.items.lastIndex)

        val fixture = Fixture()
        LuaManager.platform = J2SEPlatform()
        LuaManager.env = LuaManager.platform.newEnvironment()
        val converters = KahluaConverterManager()
        KahluaNumberConverter.install(converters)
        LuaManager.exposer = LuaManager.Exposer(converters, LuaManager.platform, LuaManager.env)
        val method = QueueLeafTransferFacts::class.java.getMethod("facts", IsoPlayer::class.java, InventoryItem::class.java, ItemContainer::class.java, ItemContainer::class.java, Double::class.javaPrimitiveType, String::class.java)
        verify(method.getAnnotation(LuaMethod::class.java)?.name == "toolkitLeafTransferFacts", "annotated global")
        LuaManager.exposer.exposeGlobalClassFunction(LuaManager.env, QueueLeafTransferFacts::class.java, method, "toolkitLeafTransferFacts")
        val thread = KahluaThread(LuaManager.platform, LuaManager.env)
        thread.debugOwnerThread = Thread.currentThread()
        LuaManager.thread = thread
        thread.call(LuaCompiler.loadstring("callbacks=0; function MustNeverRun() callbacks=callbacks+1; error('callback invoked') end", "leaf-callback-sentinel", LuaManager.env), null)
        val function = LuaManager.env.rawget("toolkitLeafTransferFacts")
        val arguments = arrayOf<Any?>(fixture.actor, fixture.item, fixture.root, fixture.destination, 17.0, "Base.Leaf")
        verify(thread.call(function, arguments) is KahluaTableImpl, "real Kahlua native facts crossing")
        field(ItemContainer::class.java, fixture.destination, "acceptItemFunction", "MustNeverRun")
        verify(thread.call(function, arguments) == null && LuaManager.env.rawget("callbacks") == 0.0, "Lua acceptance callback ran")
        field(ItemContainer::class.java, fixture.destination, "acceptItemFunction", null)
        thread.debugOwnerThread = null
        verify(QueueLeafTransferFacts.facts(fixture.actor, fixture.item, fixture.root, fixture.destination, 17.0, "Base.Leaf") == null, "missing native owner thread")
        thread.debugOwnerThread = Thread.currentThread()
        var foreignThreadResult: KahluaTableImpl? = result
        Thread { foreignThreadResult = QueueLeafTransferFacts.facts(fixture.actor, fixture.item, fixture.root, fixture.destination, 17.0, "Base.Leaf") }.apply { start(); join() }
        verify(foreignThreadResult == null, "foreign thread read")
        verify(fixture.item.getContainer() === fixture.root && fixture.root.items.size == 2 && fixture.destination.items.isEmpty(), "observation changed native membership")
        if ("--measure" in args) {
            fun measure(label: String, value: Fixture, runs: Int) {
                IsoPlayer.players[0] = value.actor
                repeat(200) { verify(value.read() != null, "measurement warmup") }
                val start = System.nanoTime()
                repeat(runs) { verify(value.read() != null, "measurement read") }
                println("LEAF_FACTS_COST helper-only warm-JVM diagnostic (no planner/render baseline): $label root=${value.root.items.size} destination=${value.destination.items.size} ns/read=${(System.nanoTime()-start)/runs} reads=$runs; one direct source scan, one direct destination scan, one 7-field DTO")
            }
            measure("small", Fixture().also { while (it.root.items.size < 16) it.root.items.add(item(ComboItem::class.java, 100 + it.root.items.size)) }, 2000)
            measure("at-bound", near, 200)
        }
        println("QUEUE_LEAF_TRANSFER_FACTS_CHECKS_PASS (native direct identities, endpoint/acceptance/equipment mutations, nested duplicate, callback-free Kahlua, bounds and owner thread)")
        kotlin.system.exitProcess(0)
    }
}
