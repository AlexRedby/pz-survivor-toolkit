package net.alexredby.pztoolkitjavapatches

import java.lang.reflect.Field
import java.util.LinkedHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import se.krka.kahlua.integration.annotations.LuaMethod
import se.krka.kahlua.j2se.KahluaTableImpl
import zombie.Lua.LuaManager
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.ActionManager
import zombie.core.NetTimedAction
import zombie.core.Transaction.TransactionState
import zombie.inventory.InventoryItem
import zombie.inventory.ItemContainer
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.fields.character.PlayerID

/** Server point observation only. It is neither a packet receipt nor an edit capability. */
object QueueNativeHandState {
    @JvmField internal val SUPPORTED = LuaFactApi.SUPPORTED && arrayOf(
        "zombie/core/ActionManager.class" to "3e85655f0d287837b17164d2ee4cecb7067ab419ffbe8ce1adb36bd7d54b202f",
        "zombie/core/Action.class" to "4a2fe6aaf0cf73235279946e930b40489ec44859aff64cc19d97976bcc75610d",
        "zombie/core/NetTimedAction.class" to "d4a3046eeaec409977a756c6ea80b0676229274684012ad51210559ebfcb1090",
        "zombie/characters/IsoPlayer.class" to "3f1c4634d3a8e7e36baf4b33f76cf7ef79d88c3351bd0eb2a6a6bb34c2d9858f",
        "zombie/characters/IsoGameCharacter.class" to "29040e19c3e420499f73bc0ea0d5b86d7f7d38655acdc13d0107df736eb54c0b",
        "zombie/inventory/InventoryItem.class" to "48f01be16d1ef1b76e37638fac6e25ca4eb285ad38ab2f462caa5597318c7f9d",
        "zombie/inventory/ItemContainer.class" to "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96",
        "zombie/network/fields/character/PlayerID.class" to "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56",
        "zombie/network/fields/IDShort.class" to "852188ce7dceb2a40c32ae233d6fcdbdec3cc74dd45d9d5151334308f514cdcd",
    ).all { (path, hash) -> BytecodeSupport.supports(path, hash) }
    private fun field(type: Class<*>, name: String): Field? = if (!SUPPORTED) null else try {
        type.getDeclaredField(name).apply { isAccessible = true }
    } catch (_: Exception) { null }
    private val actionClass = NetTimedAction::class.java.superclass
    private val actions = field(ActionManager::class.java,"actions")
    private val ownerField = field(actionClass,"playerId")
    private val stateField = field(actionClass,"state")
    private val idField = field(actionClass,"id")
    private val ownerPlayer = field(PlayerID::class.java,"player")
    private val inventory = field(IsoGameCharacter::class.java,"inventory")
    private val primary = field(IsoGameCharacter::class.java,"leftHandItem")
    private val secondary = field(IsoGameCharacter::class.java,"rightHandItem")
    private val itemId = field(InventoryItem::class.java,"id")
    private val itemType = field(InventoryItem::class.java,"fullType")
    private val itemContainer = field(InventoryItem::class.java,"container")
    private val READY = listOf(actions,ownerField,stateField,idField,ownerPlayer,inventory,primary,secondary,
        itemId,itemType,itemContainer).all { it != null }
    private val readMethod = QueueNativeHandState::class.java.getMethod("read",Any::class.java,Any::class.java,Any::class.java)
    private val checkMethod = QueueNativeHandState::class.java.getMethod("apiMatches",Any::class.java)

    private fun active(actor: IsoPlayer): NetTimedAction? {
        val values = actions?.get(null)
        if (values?.javaClass != ConcurrentLinkedQueue::class.java) return null
        var found: NetTimedAction? = null
        for (candidate in values as ConcurrentLinkedQueue<*>) {
            if (candidate == null || !actionClass.isInstance(candidate)) return null
            val owner = ownerField?.get(candidate)
            if (owner?.javaClass != PlayerID::class.java) return null
            owner as PlayerID
            val player = ownerPlayer?.get(owner)
            if (player !== actor) {
                // An unresolved/replaced object with this same network ID is not
                // another player's independent action.
                if (owner.getID() == actor.onlineId) return null
                continue
            }
            if (owner.getID() != actor.onlineId) return null
            when (stateField?.get(candidate)) {
                TransactionState.Done, TransactionState.Reject -> continue
                TransactionState.Accept -> {
                    if (found != null || candidate.javaClass != NetTimedAction::class.java) return null
                    found = candidate as NetTimedAction
                }
                else -> return null
            }
        }
        return found
    }
    private data class Item(val reference: InventoryItem?, val id: Int?, val type: String?, val inRoot: Boolean)
    private fun item(value: Any?, root: ItemContainer): Item? {
        if (value == null) return Item(null,null,null,false)
        if (value !is InventoryItem) return null
        // Raw metadata only: virtual item getters may create state or belong to
        // another mod. Container equality does not prove root-list membership.
        val id = itemId?.getInt(value) ?: return null
        val type = itemType?.get(value) as? String ?: return null
        return Item(value,id,type,itemContainer?.get(value) === root)
    }
    private fun unchanged(value: Item, root: ItemContainer): Boolean = value.reference?.let {
        itemId?.getInt(it) == value.id && itemType?.get(it) == value.type
            && (itemContainer?.get(it) === root) == value.inRoot
    } ?: true

    @JvmStatic @LuaMethod(name="toolkitNativeHandStateApiMatches",global=true)
    fun apiMatches(function: Any?): Boolean = try {
        READY && LuaFactApi.entry("toolkitNativeHandStateApiMatches",checkMethod,arrayOf(function))
            && LuaFactApi.canonical(function,readMethod)
            && LuaFactApi.plain(LuaManager.env)?.delegate?.get("toolkitNativeHandState") === function
    } catch (_: Exception) { false } catch (_: AssertionError) { false }

    @JvmStatic @LuaMethod(name="toolkitNativeHandState",global=true)
    fun read(actor: Any?, transaction: Any?, token: Any?): KahluaTableImpl? = try {
        if (!READY || !ActionAcknowledgements.SUPPORTED || !GameServer.server || GameClient.client
            || !LuaFactApi.entry("toolkitNativeHandState",readMethod,arrayOf(actor,transaction,token))
            || actor?.javaClass != IsoPlayer::class.java || transaction?.javaClass != Double::class.javaObjectType
            || token !is String || token.length != 36) null
        else {
            actor as IsoPlayer
            val number = transaction as Double
            if (!number.isFinite() || number != number.toInt().toDouble() || number !in -128.0..127.0
                || number == 0.0 || actor.onlineId < 0) null
            else {
                val action = active(actor)
                val root = inventory?.get(actor)
                if (action == null || root?.javaClass != ItemContainer::class.java
                    || idField?.getByte(action)?.toDouble() != number || ActionAcknowledgements.token(action) != token
                    || (root as ItemContainer).parent !== actor || root.containingItem != null
                    || action.type == null || action.type.isEmpty() || action.action == null) null
                else {
                    val kind = action.type
                    val table = action.action
                    val p = item(primary?.get(actor),root)
                    val s = item(secondary?.get(actor),root)
                    if (p == null || s == null || active(actor) !== action || inventory.get(actor) !== root
                        || root.parent !== actor || root.containingItem != null
                        || primary?.get(actor) !== p.reference || secondary?.get(actor) !== s.reference
                        || !unchanged(p,root) || !unchanged(s,root) || action.type != kind || action.action !== table
                        || idField.getByte(action).toDouble() != number || ActionAcknowledgements.token(action) != token) null
                    else KahluaTableImpl(LinkedHashMap<Any,Any?>()).apply {
                        delegate["schema"]=1.0;delegate["scope"]="server-native-active-action-point"
                        delegate["player"]=actor.onlineId.toDouble();delegate["transaction"]=number
                        delegate["token"]=token;delegate["kind"]=kind;delegate["state"]="accepted"
                        delegate["primaryPresent"]=p.reference!=null;delegate["secondaryPresent"]=s.reference!=null
                        delegate["primaryId"]=p.id?.toDouble() ?: false;delegate["secondaryId"]=s.id?.toDouble() ?: false
                        delegate["primaryType"]=p.type ?: false;delegate["secondaryType"]=s.type ?: false
                        delegate["primaryContainerIsRoot"]=p.inRoot;delegate["secondaryContainerIsRoot"]=s.inRoot
                        delegate["sameItem"]=p.reference!=null && p.reference===s.reference
                        delegate["rootMembershipVerified"]=false;delegate["packetCorrelated"]=false
                        delegate["effectsVerified"]=false;delegate["editAuthority"]=false
                    }
                }
            }
        }
    } catch (_: Exception) { null } catch (_: AssertionError) { null }
}
