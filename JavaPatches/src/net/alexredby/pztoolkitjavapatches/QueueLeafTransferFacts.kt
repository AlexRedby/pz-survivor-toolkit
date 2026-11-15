package net.alexredby.pztoolkitjavapatches

import java.util.ArrayList
import java.util.LinkedHashMap
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.KahluaTableImpl
import zombie.Lua.LuaManager
import zombie.characters.BodyDamage.BodyDamage
import zombie.characters.AttachedItems.AttachedItems
import zombie.characters.IsoPlayer
import zombie.characters.WornItems.WornItems
import zombie.core.properties.IsoPropertyType
import zombie.core.properties.PropertyContainer
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.inventory.types.Clothing
import zombie.inventory.types.ComboItem
import zombie.inventory.types.DrainableComboItem
import zombie.inventory.types.HandWeapon
import zombie.inventory.types.InventoryContainer
import zombie.inventory.types.Key
import zombie.inventory.types.Literature
import zombie.inventory.types.MapItem
import zombie.inventory.types.WeaponPart
import zombie.iso.IsoDirections
import zombie.iso.IsoGridSquare
import zombie.iso.IsoObject
import zombie.network.GameServer
import zombie.network.GameClient
import zombie.iso.objects.IsoBarricade
import zombie.iso.objects.IsoThumpable
import zombie.iso.sprite.IsoSprite

/** A bounded final native read. These values grant neither admission nor execution rights. */
object QueueLeafTransferFacts {
    @JvmField
    internal val SUPPORTED =
        arrayOf(
            "zombie/inventory/InventoryItem.class" to "b45d4438636509d992aaa7b7505ef8323cd898947efc27bf1f7e762951d6643d",
            "zombie/inventory/ItemContainer.class" to "19ffefbabfc16ce3b40feb557189c4fbecdb752aa2c96e3daa8b8ec0542185d3",
            "zombie/inventory/types/ComboItem.class" to "161277cc8fab2aa4c4bbf634a237f28cdb5a583565df36612159ef3bd4e129d1",
            "zombie/inventory/types/DrainableComboItem.class" to "d5b4926058d77e6f889339ccffb4c8996fd1a93cdd49aec3786fd631b8ba51ea",
            "zombie/inventory/types/HandWeapon.class" to "db86fba1c10ba18c1100fdc54f982f1fb5e0d04dcc765680fa1489563b28ce85",
            "zombie/inventory/types/Clothing.class" to "a32e0ffb3f15b2dca12b17556ca5dbc9d515bd02efdc83ac24ba6e31dd598f1d",
            "zombie/inventory/types/Literature.class" to "b75aa46576e99cc1986fe6e3e1aebf76e1af4878ba3672dd41f8139eea2ce862",
            "zombie/inventory/types/Key.class" to "9ae78585d42e0e13b1fa5efbd89f3d5de7eea7a1d9002a6b9629c7de475b5a1c",
            "zombie/inventory/types/MapItem.class" to "e4533368d49f72005bae8486576b06e7b1bcd45d545946dbb726a124eff07e3b",
            "zombie/inventory/types/WeaponPart.class" to "c378358d6449cc7b1c2e968420b456a9108c8550246bb29b99a13e7ac69a857a",
            "zombie/inventory/types/InventoryContainer.class" to "891cb2f37a7d13de869edf05909de493a55ef90aa8665368b36bff7fa6b2555e",
            "zombie/characters/IsoGameCharacter.class" to "1ccabc492ba130f51486bf38a8400334545852253bbac9c46fff71242ab672f6",
            "zombie/characters/IsoPlayer.class" to "643585044a88ad1b29e8d5173774f66085c685c363ed10a89c0b79018de2874e",
            "zombie/characters/WornItems/WornItems.class" to "3a01a9b5b7e13d0902fcac9342ac0b42e5c2e87284d88ce9a6a01f45294409c1",
            "zombie/characters/WornItems/WornItem.class" to "84d0a8029e26abf00c07814e8dee65918ecc449c3a5aef42ed30f8dcee0863f6",
            "zombie/characters/BodyDamage/BodyDamage.class" to "b8e5d774f9bed459dbf34590ab304a12ad5ecc56c26e2a37d6600a9817bfb8e6",
            "zombie/iso/IsoMovingObject.class" to "70c0249c3bdb7b4c4fc335e644c74bc98c37aa0e4bfdc0665a75521460ea0900",
            "zombie/iso/IsoObject.class" to "7a99d06875c19ff132940d7192b414496537076e83474db0abc0cb38de6be70a",
            "zombie/iso/IsoGridSquare.class" to "b8cef32a10bb76433bad174397b51f1a046be1eef47997dc1e79dd8547d726c5",
            "zombie/iso/objects/IsoThumpable.class" to "61893a53f89547abf25dd8459aaf1fb43051bee39866f578f3aee7f074e6c47d",
            "zombie/iso/objects/IsoBarricade.class" to "ec42e234375fc3bfa2c8548ff284416c0235304a05bee967a37a5690110ac972",
            "zombie/iso/sprite/IsoSprite.class" to "498f94e38b171ed0eb528b3ab3b90cbf0d152cc81bfe9a3e1345825a627a04ce",
            "zombie/core/properties/PropertyContainer.class" to "400d434ad860a39feb745f1033a63dca446d6f93d8b1a2ec4c343b166b658959",
            "zombie/iso/SpriteDetails/IsoFlagType.class" to "0c11206e0b8366e286d4d7e2aaa802d40f106463163397a59bc5d761f40a8bf9",
            "se/krka/kahlua/j2se/KahluaTableImpl.class" to "1e79dbff83e85c8863df63f7847d3a506fddbaefa423cb676734751599db1aea",
            "se/krka/kahlua/vm/KahluaThread.class" to "25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6",
            "zombie/core/properties/IsoPropertyType.class" to "c713a1a7b47b8f0cd920742967e7a94f738fa935b57952a5ce9bcdc8f1e23217",
            "zombie/iso/IsoDirections.class" to "5108ccc19404dcb76320fc019ae8f48831bd72e88f9afc910ae0c79a58cd769f",
            "zombie/core/TilePropertyAliasMap.class" to "05124f3536bc2026fb29d5f7369dc0d809d1a725477d4733a1e0e827911a0a80",
            "zombie/core/TilePropertyAliasMap\$TileProperty.class" to "382534b6d3d05514032091c51232659c04ef7eca8a8f42468ba24469f5cbc515",
            "zombie/iso/IsoWorld.class" to "e17f9d3266154e7715237656612832123a9032e7bb9ff73ae7a29ecdf73374df",
            "zombie/iso/IsoCell.class" to "6c261778f1fac0c660ba8b6167b9bf5d318e8bd126378e3c1b3667c9469910ab",
            "zombie/iso/IsoChunkMap.class" to "7a64d736a95ba700afd2916ad7a93875ce39ce9390f7b1ea14197d1e90db49e4",
            "zombie/iso/IsoChunk.class" to "b069a07b79dc86d2a1133dff187fdcde904e1fe9a9d2f066b877b9ea0ea31af8",
            "zombie/iso/objects/interfaces/GridSquareEdgeElement.class" to "3cb116b623c2115e4fe80698e34e3aa366c403c36428527fbd38d0cb91fcf9d6",
            "zombie/iso/objects/GridSquareEdgeFacingDirection.class" to "e4b51f30b99d9e6edecf9a5e23ca376a0ea933c92d48fb12e490402ee0bfa5d5",
            "zombie/iso/IsoGridSquare\$1.class" to "ade21832b90dfb0d6623bb81f6506dc92b5577682569bc2aee83ea9805170992",
            "zombie/characters/AttachedItems/AttachedItems.class" to "7e977f7bae8d6641871013b97776da6b428a74eb5f33d045155cf9828ce03b39",
            "zombie/characters/AttachedItems/AttachedItem.class" to "9b2fb404576628ac98417c81077d6b00604deba5969d9f5c62644662ef96d3c1",
        ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }

    // Exact classes retain InventoryItem's no-op container add/remove hooks. Food calls
    // updateAge (including Lua events); world items, bags and unknown subclasses stay unknown.
    private val leafClasses = setOf(
        InventoryItem::class.java, ComboItem::class.java, DrainableComboItem::class.java,
        HandWeapon::class.java, Clothing::class.java, Literature::class.java, Key::class.java,
        MapItem::class.java, WeaponPart::class.java,
    )
    // Metadata-only callers (including luaMetatableMatches) must not initialize
    // the native request/client subsystem merely by loading this helper.
    internal val ALIAS_SUPPORTED by lazy { SUPPORTED && NativeTransferRequestsLogic.SUPPORTED &&
        BytecodeSupport.supports(
            "zombie/core/Transaction\$TransactionEntry.class",
            "e3ff05f0965b36dd7b72464ee0cdd3dbd79218df2bf580cb559ad3acd50c26b5",
        ) && BytecodeSupport.supports(
            "zombie/network/fields/ContainerID.class",
            "3123bde915f47f58fa81fb0f49fc1768efcb4db45749fe0d97c4c52dbc731bc0",
        ) }
    private val excludedContainerTypes = setOf("floor", "proximityInv", "twistInv_corpses", "TradeUI", "microwave")
    private val worldStorageTypes = setOf("crate", "shelf", "shelves", "metal_shelves")
    private val applianceGroups = setOf("Coffee", "Espresso")
    internal const val MAX_ENTRIES = 4096
    private const val MAX_WORN = 128
    private const val MAX_CONTAINERS = 64
    private val attachedEntries = try {
        AttachedItems::class.java.getDeclaredField("items").apply { isAccessible = true }
    } catch (_: Exception) { null }
    private val equipParent = try {
        InventoryItem::class.java.getDeclaredField("equipParent").apply { isAccessible = true }
    } catch (_: Exception) { null }
    private val wornEntries = try {
        WornItems::class.java.getDeclaredField("items").apply { isAccessible = true }
    } catch (_: Exception) { null }
    private val secondaryContainers = try {
        IsoObject::class.java.getDeclaredField("secondaryContainers").apply { isAccessible = true }
    } catch (_: Exception) { null }

    private val metatableSupported = BytecodeSupport.supports(
        "se/krka/kahlua/j2se/KahluaTableImpl.class",
        "1e79dbff83e85c8863df63f7847d3a506fddbaefa423cb676734751599db1aea",
    )

    // Lua getmetatable honors __metatable, so it cannot attest the actual
    // lookup parent. This value check exposes no table internals or authority.
    @JvmStatic
    @LuaMethod(name = "toolkitLuaMetatableMatches", global = true)
    fun luaMetatableMatches(owner: Any?, expected: Any?): Boolean {
        if (!metatableSupported) return false
        fun ordinary(value: Any?): KahluaTableImpl? {
            val table = value as? KahluaTableImpl ?: return null
            return table.takeIf {
                it.javaClass == KahluaTableImpl::class.java && it.rewriteTable == null &&
                    it.delegate.javaClass == LinkedHashMap::class.java
            }
        }
        val table = ordinary(owner) ?: return false
        if (expected != null && ordinary(expected) == null) return false
        return table.metatable === expected
    }

    @JvmStatic
    @LuaMethod(name = "toolkitLeafTransferFacts", global = true)
    fun facts(
        actor: IsoPlayer?, item: InventoryItem?, source: ItemContainer?,
        destination: ItemContainer?, id: Double, fullType: String?,
    ): KahluaTableImpl? = read(actor, item, source, destination, id, fullType, SUPPORTED,
        LuaManager.thread?.debugOwnerThread === Thread.currentThread())

    /**
     * Effect target only: ordinary MP requests encode the queued member's ID and native
     * Transaction.updateItem resolves that ID in source. Admission still reads the old
     * member's weight/allowance; this witness grants no admission or execution rights.
     */
    @JvmStatic
    @LuaMethod(name = "toolkitLeafTransferAliasFacts", global = true)
    fun aliasFacts(
        actor: IsoPlayer?, item: InventoryItem?, source: ItemContainer?,
        destination: ItemContainer?, id: Double, fullType: String?, queuedMember: InventoryItem?,
    ): KahluaTableImpl? {
        val env = LuaManager.env as? KahluaTableImpl
        val nativeApi = env != null && env.javaClass == KahluaTableImpl::class.java &&
            env.metatable == null && env.rewriteTable == null && env.delegate.javaClass == LinkedHashMap::class.java &&
            NativeTransferRequestsLogic.canonicalApi(env.delegate["createItemTransaction"])
        return readAlias(actor, item, source, destination, id, fullType, queuedMember,
            ALIAS_SUPPORTED, LuaManager.thread?.debugOwnerThread === Thread.currentThread(),
            GameClient.client && !GameServer.server, nativeApi)
    }

    /** Explicit negative-test gates; the exposed method always reads native state itself. */
    internal fun readAlias(
        actor: IsoPlayer?, item: InventoryItem?, source: ItemContainer?,
        destination: ItemContainer?, id: Double, fullType: String?, queuedMember: InventoryItem?,
        supported: Boolean, ownerThread: Boolean, client: Boolean, nativeApi: Boolean,
    ): KahluaTableImpl? {
        if (!supported || !ownerThread || !client || !nativeApi || actor?.javaClass != IsoPlayer::class.java ||
            item == null || queuedMember == null || queuedMember === item || item.javaClass !in leafClasses ||
            queuedMember.javaClass != item.javaClass) return null
        return try {
            // Both classes are exact pinned leaves before any virtual native getter. No
            // recursive scan, Lua dispatch, native request or list rebinding occurs here.
            if (queuedMember.id != item.id || queuedMember.getFullType() != item.getFullType() ||
                queuedMember.getContainer() != null || queuedMember.getWorldItem() != null ||
                queuedMember.getIsCraftingConsumed() || equipParent == null || equipParent.get(queuedMember) != null ||
                queuedMember.getAttachedSlot() >= 0) return null
            val facts = read(actor, item, source, destination, id, fullType, true, true, queuedMember) ?: return null
            facts.delegate["aliasMember"] = queuedMember
            facts.delegate["aliasResolution"] = "native-root-id"
            facts
        } catch (_: Exception) { null } catch (_: AssertionError) { null }
    }

    /** Explicit gates are a test seam; production always uses pinned classes and the Lua owner. */
    internal fun read(
        actor: IsoPlayer?, item: InventoryItem?, source: ItemContainer?,
        destination: ItemContainer?, id: Double, fullType: String?,
        supported: Boolean, ownerThread: Boolean, aliasMember: InventoryItem? = null,
    ): KahluaTableImpl? {
        if (!supported || !ownerThread || actor?.javaClass != IsoPlayer::class.java
            || item == null || item.javaClass !in leafClasses
            || source?.javaClass != ItemContainer::class.java
            || destination?.javaClass != ItemContainer::class.java || source === destination
            || !id.isFinite() || id % 1.0 != 0.0 || id < Int.MIN_VALUE || id > Int.MAX_VALUE
            || fullType.isNullOrEmpty()) return null
        return try {
            val number = actor.getIndex()
            val players = IsoPlayer.players
            if (players == null || number !in players.indices || players[number] !== actor
                || actor.getBodyDamage()?.javaClass != BodyDamage::class.java || actor.isDead()
                || actor.getInventory() !== source || source.getParent() !== actor
                || source.getContainingItem() != null || !ordinary(source)
                // Exact actor parent inherits IsoObject's constant-true removal predicate.
                // Restrict root type too: special native action branches are not location-only.
                || source.getType() != "inventory" && source.getType() != "none"
                || item.id != id.toInt() || item.getFullType() != fullType
                || item.getContainer() !== source || item.getWorldItem() != null
                || item.getIsCraftingConsumed() || equipParent == null || equipParent.get(item) != null
                || item.getAttachedSlot() >= 0 || item.getType() == "CandleLit"
                || item.getType() == "Lantern_HurricaneLit" || !unequipped(actor, item, aliasMember)
                || destination.id == item.id || !absent(destination, item.id)) return null
            val sourceTypes = parentTypes(actor) ?: return null
            val holder = destination.getContainingItem()
            val destinationTypes: List<String>
            if (holder != null) {
                // One direct carried bag only: no recursive lookup or owner-chain snapshot.
                if (holder.javaClass != InventoryContainer::class.java || holder === item
                    || source.id == item.id
                    || (holder as InventoryContainer).getInventory() !== destination
                    || holder.getContainer() !== source || holder.getWorldItem() != null
                    || holder.getIsCraftingConsumed()
                    || destination.getParent() != null || destination.getSourceGrid() != null
                    || !ordinary(destination)) return null
                destinationTypes = emptyList()
            } else {
                if (item.isFavorite()) return null
                destinationTypes = worldEndpoint(destination, actor) ?: return null
            }
            if (!directMembers(source, item, holder)) return null
            // Own tables/strings only. No Lua dispatch, item/action constructors, virtual weight,
            // capacity, validity, transaction or effect APIs run in this helper.
            val primary = actor.getPrimaryHandItem()
            val primaryKnown = primary == null || primary.javaClass in leafClasses
                || primary.javaClass == InventoryContainer::class.java
            val result = KahluaTableImpl(LinkedHashMap<Any, Any?>())
            result.delegate["schema"] = 2.0
            result.delegate["item"] = item
            result.delegate["source"] = source
            result.delegate["destination"] = destination
            result.delegate["id"] = id
            result.delegate["fullType"] = fullType
            result.delegate["location"] = source
            // Generic branch evidence for reviewed source owners. False means a
            // complete empty parent-type set, avoiding two empty Lua allocations.
            result.delegate["sourceParentTypes"] = typeTable(sourceTypes)
            result.delegate["destinationParentTypes"] = typeTable(destinationTypes)
            result.delegate["primaryItemContainerKnown"] = primaryKnown
            if (holder != null) {
                result.delegate["destinationOwner"] = holder
                result.delegate["destinationOwnerFullType"] = holder.getFullType()
            }
            if (primary != null) {
                result.delegate["primaryItem"] = primary
                if (primaryKnown) result.delegate["primaryFullType"] = primary.getFullType()
                if (primary.javaClass == InventoryContainer::class.java)
                    result.delegate["primaryItemContainer"] = (primary as InventoryContainer).getItemContainer()
            }
            result
        } catch (_: Exception) { null } catch (_: AssertionError) { null }
    }

    private fun ordinary(container: ItemContainer): Boolean =
        container.getVehiclePart() == null && container.getAcceptItemFunction() == null
            && container.getOnlyAcceptCategory() == null && container.getType() != null
            && container.getType() !in excludedContainerTypes

    private fun entries(container: ItemContainer): ArrayList<InventoryItem>? {
        val values = container.getItems() ?: return null
        return values.takeIf { it.javaClass == ArrayList::class.java && it.size <= MAX_ENTRIES }
    }

    private fun directMembers(container: ItemContainer, item: InventoryItem, owner: InventoryItem?): Boolean {
        val values = entries(container) ?: return false
        var references = 0
        var identities = 0
        var owners = 0
        var ownerIds = 0
        for (value in values) {
            if (value === item) references++
            // Public native fields, deliberately bypassing unknown other items' getters.
            if (value.id == item.id) identities++
            if (owner != null) {
                if (value === owner) owners++
                if (value.id == owner.id) ownerIds++
            }
        }
        return references == 1 && identities == 1 && (owner == null || owners == 1 && ownerIds == 1)
    }

    private fun absent(container: ItemContainer, id: Int): Boolean {
        val values = entries(container) ?: return false
        // A direct scan cannot disprove a duplicate hidden inside a destination bag.
        // Keep that topology unknown rather than recursively scanning its inventory.
        return values.none { it is InventoryContainer || it.id == id }
    }

    private fun unequipped(actor: IsoPlayer, item: InventoryItem, aliasMember: InventoryItem?): Boolean {
        fun selected(value: InventoryItem?): Boolean = value === item || aliasMember != null &&
            (value === aliasMember || value != null && value.id == item.id)
        // An alias request resolves by logical ID. A third equipment replica with
        // that ID is equally ambiguous. Inspect public IDs while traversing each
        // equipment collection once; ordinary facts retain reference-only checks.
        if (selected(actor.getPrimaryHandItem()) || selected(actor.getSecondaryHandItem())) return false
        val worn = actor.getWornItems() ?: return false
        if (worn.javaClass != WornItems::class.java) return false
        val values = wornEntries?.get(worn)
        if (values?.javaClass != ArrayList::class.java) return false
        val count = (values as ArrayList<*>).size
        if (count > MAX_WORN) return false
        for (index in 0 until count) if (selected(worn.getItemByIndex(index))) return false
        // Native transfer always calls removeAttachedItem, even if attachedSlot is stale.
        val attached = actor.getAttachedItems() ?: return false
        if (attached.javaClass != AttachedItems::class.java) return false
        val slots = attachedEntries?.get(attached)
        if (slots?.javaClass != ArrayList::class.java) return false
        val slotCount = (slots as ArrayList<*>).size
        if (slotCount > MAX_WORN) return false
        for (index in 0 until slotCount) if (selected(attached.getItemByIndex(index))) return false
        return true
    }

    private fun worldEndpoint(container: ItemContainer, actor: IsoPlayer): List<String>? {
        if (!ordinary(container) || container.getType() !in worldStorageTypes) return null
        val parent = container.getParent() ?: return null
        if (parent.javaClass != IsoObject::class.java && parent.javaClass != IsoThumpable::class.java) return null
        val square = parent.getSquare() ?: return null
        if (square.javaClass != IsoGridSquare::class.java || container.getSourceGrid() !== square) return null
        val origin = actor.getCurrentSquare() ?: return null
        if (origin.javaClass != IsoGridSquare::class.java) return null
        if (origin.getZ() != square.getZ() || kotlin.math.abs(origin.getX().toLong() - square.getX()) > 1
            || kotlin.math.abs(origin.getY().toLong() - square.getY()) > 1) return null
        val objects = square.getObjects() ?: return null
        // Native square construction backs the List API with an exact ArrayList.
        // Reject custom list callbacks before reading size or members.
        if (objects.javaClass != ArrayList::class.java || objects.size > MAX_ENTRIES) return null
        var anchors = 0
        for (index in 0 until objects.size) if (objects[index] === parent) anchors++
        if (anchors != 1) return null
        val types = parentTypes(parent, container) ?: return null
        val sprite = parent.getSprite()
        if (sprite != null && sprite.javaClass != IsoSprite::class.java) return null
        val properties = parent.getProperties()
        if (properties != null && properties.javaClass != PropertyContainer::class.java) return null
        if (properties?.get(IsoPropertyType.CUSTOM_NAME) == "Toaster"
            || properties?.get(IsoPropertyType.GROUP_NAME) in applianceGroups) return null
        if (parent is IsoThumpable) {
            if (parent.isDoor() || parent.isDoorFrame() || parent.isWindowN() || parent.isWindowW()
                || parent.isLocked() || parent.isLockedByKey() || parent.isLockedByPadlock()
                || parent.getLockedByCode() != 0) return null
            val north = parent.getNorth()
            if (!noBarricade(square, if (north) IsoDirections.N else IsoDirections.W)) return null
            // Native opposite-side lookup uses the live cell, not potentially absent/stale nav[].
            // IsoGridSquare, IsoWorld, IsoCell, IsoChunkMap and IsoChunk are final and
            // pinned (also asserted by native checks); their typed lookup path cannot
            // dispatch foreign overrides. This path performs only native reads.
            if (GameServer.server) return null
            val opposite = parent.getOppositeSquare()
            if (opposite != null && !noBarricade(opposite, if (north) IsoDirections.S else IsoDirections.E)) return null
        }
        return types
    }

    private fun parentTypes(parent: IsoObject, expected: ItemContainer? = null): List<String>? {
        if (parent.javaClass != IsoObject::class.java && parent.javaClass != IsoThumpable::class.java
            && parent.javaClass != IsoPlayer::class.java) return null
        val field = secondaryContainers ?: return null
        val secondary = field.get(parent)
        // Native count/index getters dispatch through this mutable backing list.
        // Check its exact implementation before invoking either getter.
        if (secondary != null && (secondary.javaClass != ArrayList::class.java ||
            (secondary as ArrayList<*>).size > MAX_CONTAINERS)) return null
        val count = parent.getContainerCount()
        if (count !in 0..MAX_CONTAINERS || expected != null && count == 0) return null
        if (count == 0) return emptyList()
        val types = ArrayList<String>(count)
        var owners = 0
        for (index in 0 until count) {
            val container = parent.getContainerByIndex(index) ?: continue
            if (container.javaClass != ItemContainer::class.java) return null
            if (container === expected) owners++
            container.getType()?.let { types.add(it) }
        }
        return if (expected == null || owners == 1) types else null
    }

    private fun typeTable(types: List<String>): Any {
        if (types.isEmpty()) return false
        val result = KahluaTableImpl(LinkedHashMap<Any, Any?>())
        for (index in types.indices) result.delegate[index.toDouble() + 1.0] = types[index]
        return result
    }

    private fun noBarricade(square: IsoGridSquare, direction: IsoDirections): Boolean {
        val values = square.getSpecialObjects() ?: return false
        if (values.javaClass != ArrayList::class.java || values.size > MAX_ENTRIES) return false
        for (value in values) if (value is IsoBarricade) {
            if (value.javaClass != IsoBarricade::class.java || value.getDir() == direction) return false
        }
        return true
    }
}
