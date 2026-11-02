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
import zombie.iso.objects.IsoBarricade
import zombie.iso.objects.IsoThumpable
import zombie.iso.sprite.IsoSprite
import zombie.util.list.PZArrayList

/** A bounded final native read. These values grant neither admission nor execution rights. */
object QueueLeafTransferFacts {
    @JvmField
    internal val SUPPORTED =
        arrayOf(
            "zombie/inventory/InventoryItem.class" to "48f01be16d1ef1b76e37638fac6e25ca4eb285ad38ab2f462caa5597318c7f9d",
            "zombie/inventory/ItemContainer.class" to "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96",
            "zombie/inventory/types/ComboItem.class" to "161277cc8fab2aa4c4bbf634a237f28cdb5a583565df36612159ef3bd4e129d1",
            "zombie/inventory/types/DrainableComboItem.class" to "f2b9c855c4deb394c31701c1466cafc633b6155dae7c9544921d05e3b7d5414d",
            "zombie/inventory/types/HandWeapon.class" to "2d1d3266cd03730fc8af8bfc631eea37a8e07708ceb6fe7b376d2b0e5f4174e4",
            "zombie/inventory/types/Clothing.class" to "a32e0ffb3f15b2dca12b17556ca5dbc9d515bd02efdc83ac24ba6e31dd598f1d",
            "zombie/inventory/types/Literature.class" to "b75aa46576e99cc1986fe6e3e1aebf76e1af4878ba3672dd41f8139eea2ce862",
            "zombie/inventory/types/Key.class" to "9ae78585d42e0e13b1fa5efbd89f3d5de7eea7a1d9002a6b9629c7de475b5a1c",
            "zombie/inventory/types/MapItem.class" to "4121112d1e4ef513ae3efd7f4702adf597157eba220bcb573b9511d6392cb1f2",
            "zombie/inventory/types/WeaponPart.class" to "c378358d6449cc7b1c2e968420b456a9108c8550246bb29b99a13e7ac69a857a",
            "zombie/inventory/types/InventoryContainer.class" to "891cb2f37a7d13de869edf05909de493a55ef90aa8665368b36bff7fa6b2555e",
            "zombie/characters/IsoGameCharacter.class" to "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
            "zombie/characters/IsoPlayer.class" to "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f",
            "zombie/characters/WornItems/WornItems.class" to "3a01a9b5b7e13d0902fcac9342ac0b42e5c2e87284d88ce9a6a01f45294409c1",
            "zombie/characters/WornItems/WornItem.class" to "84d0a8029e26abf00c07814e8dee65918ecc449c3a5aef42ed30f8dcee0863f6",
            "zombie/characters/BodyDamage/BodyDamage.class" to "e3509531e997649a240db7a8427a4d9df67582fe2460baf436ade26aae8c638e",
            "zombie/iso/IsoMovingObject.class" to "7e6e84fe9d3cb264e8d8e682d91e0abe919d481b7349d17b997e8a78f2293a5f",
            "zombie/iso/IsoObject.class" to "22387ecf47c1cf9aac192466de6298067f27584160c76a72baee38c6ad36dff2",
            "zombie/iso/IsoGridSquare.class" to "e8192f87d88da607abe0293228c84efbd822ed4ac0a331102c030bc3eeaba467",
            "zombie/iso/objects/IsoThumpable.class" to "cc19adbef73edbda83a56fdb727b70210278e6e4bd3c2c1def881dab804f8323",
            "zombie/iso/objects/IsoBarricade.class" to "49b181237bee661405aa94284751269091d18b37a150aab20de4fb03525595e0",
            "zombie/iso/sprite/IsoSprite.class" to "68c01e6b1c914f662621743e09c8dd8a62c0258392ce1a75654a713e1034067f",
            "zombie/core/properties/PropertyContainer.class" to "bc236f8e9e4e0da8a86b0d1fd19ad8d44a040fe4f67d1baac77401b3b148bd77",
            "zombie/iso/SpriteDetails/IsoFlagType.class" to "0c11206e0b8366e286d4d7e2aaa802d40f106463163397a59bc5d761f40a8bf9",
            "zombie/util/list/PZArrayList.class" to "7ce79434a59558ed7c966d46d592d765ea6160949e0e87705002ccac7d4f5394",
            "se/krka/kahlua/j2se/KahluaTableImpl.class" to "101df1481366f976f76c037094e29f5ad21c71f5026dc3d0693f25d68b1c79f7",
            "se/krka/kahlua/vm/KahluaThread.class" to "25f4c0dea91800dcb3fadd3d482ed5f7d5cf17908bf167afd308b85c99856bb6",
            "zombie/core/properties/IsoPropertyType.class" to "7e7deb55cc8a949a4cab6cf93e0cabef01090229154203730f758526c948ebd3",
            "zombie/iso/IsoDirections.class" to "44a5f26c7f1c39bcd209996eda6533943d49b5433b63064973c96e9d64b55bc1",
            "zombie/core/TilePropertyAliasMap.class" to "05124f3536bc2026fb29d5f7369dc0d809d1a725477d4733a1e0e827911a0a80",
            "zombie/core/TilePropertyAliasMap\$TileProperty.class" to "382534b6d3d05514032091c51232659c04ef7eca8a8f42468ba24469f5cbc515",
            "zombie/iso/IsoWorld.class" to "5b7406a70f33578a47ff417b0b6aa7a2b7a5bebfa00487a60935303f5747fb71",
            "zombie/iso/IsoCell.class" to "5e9a88e1cd9a3f370e31ae0152c9de381d649caea7cab750ebc82a91b4e1f767",
            "zombie/iso/IsoChunkMap.class" to "7a64d736a95ba700afd2916ad7a93875ce39ce9390f7b1ea14197d1e90db49e4",
            "zombie/iso/IsoChunk.class" to "5048becc3f46f746686513d4dcadb137e6e11bfd44617075f41923b3db11650a",
            "zombie/iso/objects/interfaces/GridSquareEdgeElement.class" to "d1bc39151da5d10670a7e556123343825ded9f0e471afac4e4c7a396c875a043",
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

    private val metatableSupported = BytecodeSupport.supports(
        "se/krka/kahlua/j2se/KahluaTableImpl.class",
        "101df1481366f976f76c037094e29f5ad21c71f5026dc3d0693f25d68b1c79f7",
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

    /** Explicit gates are a test seam; production always uses pinned classes and the Lua owner. */
    internal fun read(
        actor: IsoPlayer?, item: InventoryItem?, source: ItemContainer?,
        destination: ItemContainer?, id: Double, fullType: String?,
        supported: Boolean, ownerThread: Boolean,
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
                || item.getType() == "Lantern_HurricaneLit" || !unequipped(actor, item)
                || !absent(destination, item.id)) return null
            val sourceTypes = parentTypes(actor) ?: return null
            val holder = destination.getContainingItem()
            val destinationTypes: List<String>
            if (holder != null) {
                // One direct carried bag only: no recursive lookup or owner-chain snapshot.
                if (holder.javaClass != InventoryContainer::class.java || holder === item
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

    private fun unequipped(actor: IsoPlayer, item: InventoryItem): Boolean {
        if (actor.getPrimaryHandItem() === item || actor.getSecondaryHandItem() === item) return false
        val worn = actor.getWornItems() ?: return false
        if (worn.javaClass != WornItems::class.java) return false
        val values = wornEntries?.get(worn)
        if (values?.javaClass != ArrayList::class.java) return false
        val count = (values as ArrayList<*>).size
        if (count > MAX_WORN) return false
        for (index in 0 until count) if (worn.getItemByIndex(index) === item) return false
        // Native transfer always calls removeAttachedItem, even if attachedSlot is stale.
        val attached = actor.getAttachedItems() ?: return false
        if (attached.javaClass != AttachedItems::class.java) return false
        val slots = attachedEntries?.get(attached)
        if (slots?.javaClass != ArrayList::class.java) return false
        val slotCount = (slots as ArrayList<*>).size
        if (slotCount > MAX_WORN) return false
        for (index in 0 until slotCount) if (attached.getItemByIndex(index) === item) return false
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
        if (objects.javaClass != PZArrayList::class.java || objects.size > MAX_ENTRIES) return null
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
