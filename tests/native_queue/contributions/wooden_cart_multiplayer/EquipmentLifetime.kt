package net.alexredby.cartlab

import java.lang.ref.WeakReference
import java.util.ArrayList
import java.util.HashSet
import me.zed_0xff.zombie_buddy.Patch
import net.alexredby.cartlab.LeaseControl.LEASE_CONTROL
import net.alexredby.cartlab.LeaseControl.LeaseCommandIngress
import net.alexredby.cartlab.LeaseControl.LeaseDispatchScope
import net.alexredby.cartlab.LeaseControl.leaseControlCurrent
import net.alexredby.cartlab.LeaseControl.leaseControlDispatch
import net.alexredby.cartlab.LeaseControl.leaseControlFailed
import net.alexredby.cartlab.LeaseControl.leaseControlIngresses
import net.alexredby.cartlab.Multiplayer.mpJsonString
import net.alexredby.cartlab.NativeTime.NativeWeakMap
import net.alexredby.cartlab.NativeTime.nativeTimeIdentity
import net.alexredby.cartlab.NativeTime.nativeTimeNext
import net.alexredby.cartlab.NativeTime.nativeTimeProcess
import se.krka.kahlua.integration.annotations.LuaMethod
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.core.network.ByteBufferReader
import zombie.core.raknet.UdpConnection
import zombie.core.raknet.UdpEngine
import zombie.inventory.InventoryItem
import zombie.network.GameClient
import zombie.network.GameServer
import zombie.network.IConnection
import zombie.network.PacketTypes.PacketType
import zombie.util.AddCoopPlayer

/** Diagnostic ledger for the pinned native setter, load, death, and removal boundaries. */
object EquipmentLifetime {
    @JvmField val LEASE_LIFETIME = System.getenv("PZ_CART_LEASE_LIFETIME") == "true"
    private val equipmentLifetimeLock = Any()
    private val equipmentLives = NativeWeakMap<IsoPlayer, EquipmentLife>()
    private val equipmentRetiredConnections = NativeWeakMap<UdpConnection, Boolean>()
    private val equipmentLifetimeRecords = ArrayList<EquipmentLife>()
    @Volatile private var equipmentLifetimeFailed = false
    private var equipmentLifetimeTraceCount = 0L
    private var equipmentLifetimeMutationSerial = 0L
    private var equipmentLifetimeParseSerial = 0L
    private var equipmentLifetimeIssuedCount = 0L
    private val equipmentLifetimeParsing = ThreadLocal<EquipmentParse>()

    class EquipmentParse(
        val reader: ByteBufferReader?,
        val connection: UdpConnection?,
        val ingress: LeaseCommandIngress?,
        val dispatch: LeaseDispatchScope?,
        val previous: EquipmentParse?,
        val serial: Long,
        val trusted: Boolean,
    ) {
        var actor: IsoPlayer? = null
        var life: EquipmentLife? = null
        var original: InventoryItem? = null
        var next: InventoryItem? = null
        var beforeRevision = 0L
        var beforeHardRevision = 0L
        var stage = 0
        var directCalls = 0
        var genericCalls = 0
        var invalid = false
    }

    class EquipmentLife(actor: IsoPlayer, val actorEpoch: Long = nativeTimeIdentity(actor, true)) {
        val actor = WeakReference(actor)
        var born = false
        var birthPending = false
        var retiredRegistered = false
        var birthRemovedStamp = 0L
        var retirementReason: String? = null
        var birthEngine = WeakReference<UdpEngine>(null)
        var birthConnection = WeakReference<UdpConnection>(null)
        val issued = HashSet<Long>()
        var connection = WeakReference<UdpConnection>(null)
        var primary = WeakReference<InventoryItem>(null)
        var secondary = WeakReference<InventoryItem>(null)
        var revision = 1L
        var hardRevision = 1L
        var thread = 0L
        var depth = 0
        var cart = 0
        var parseDepth = 0
        var baseline = false
        var poisoned = false
        var retired = false
    }

    @JvmRecord
    data class EquipmentMutation(
        val life: EquipmentLife,
        val depth: Int,
        val thread: Long,
        val serial: Long,
        val reason: String,
        val oldPrimary: InventoryItem?,
        val oldSecondary: InventoryItem?,
        val parse: EquipmentParse?,
        val pending: EquipmentPendingBirth?,
    )

    private fun equipmentLifetimeEnabled() =
        LEASE_LIFETIME && LEASE_CONTROL && !leaseControlFailed && !equipmentLifetimeFailed

    private fun equipmentLifetimeError(error: Throwable) {
        equipmentLifetimeFailed = true
        System.err.println(
            "[CART_EQUIPMENT] {\"event\":\"error\",\"reason\":" +
                mpJsonString(error.toString()) +
                "}",
        )
        Multiplayer.timelineError(
            IllegalStateException("Native equipment lifetime observation failed", error),
        )
    }

    private fun equipmentLifetimeTrace(
        event: String,
        life: EquipmentLife,
        scope: EquipmentMutation?,
        reason: String,
        success: Boolean,
    ) {
        check(++equipmentLifetimeTraceCount <= 8192) { "Equipment lifetime trace limit" }
        val actor = life.actor.get()
        val primary = actor?.getPrimaryHandItem()
        val secondary = actor?.getSecondaryHandItem()
        val parse = if (scope == null) equipmentLifetimeParsing.get() else scope.parse
        val resnapshot = event == "resnapshot"
        val oldPrimary =
            if (resnapshot && parse != null) parse.original
            else if (scope == null) primary else scope.oldPrimary
        val oldSecondary =
            if (resnapshot && parse != null) parse.original
            else if (scope == null) secondary else scope.oldSecondary
        println(
            "[CART_EQUIPMENT] {\"event\":" +
                mpJsonString(event) +
                ",\"process\":" +
                mpJsonString(nativeTimeProcess) +
                ",\"ownerID\":" +
                (actor?.getOnlineID() ?: -1) +
                ",\"actorEpoch\":" +
                life.actorEpoch +
                ",\"connectionEpoch\":" +
                nativeTimeIdentity(life.connection.get(), false) +
                ",\"revision\":" +
                life.revision +
                ",\"depth\":" +
                life.depth +
                ",\"reason\":" +
                mpJsonString(reason) +
                ",\"mutationSerial\":" +
                (scope?.serial ?: 0) +
                ",\"hardRevision\":" +
                life.hardRevision +
                ",\"parseSerial\":" +
                (parse?.serial ?: 0) +
                ",\"ingressGeneration\":" +
                (parse?.ingress?.generation ?: 0) +
                ",\"beforeRevision\":" +
                (parse?.beforeRevision ?: 0) +
                ",\"afterRevision\":" +
                life.revision +
                ",\"certified\":" +
                (resnapshot && success) +
                ",\"directCalls\":" +
                (parse?.directCalls ?: 0) +
                ",\"genericCalls\":" +
                (parse?.genericCalls ?: 0) +
                ",\"oldPrimaryEpoch\":" +
                nativeTimeIdentity(oldPrimary, false) +
                ",\"oldSecondaryEpoch\":" +
                nativeTimeIdentity(oldSecondary, false) +
                ",\"primaryEpoch\":" +
                nativeTimeIdentity(primary, false) +
                ",\"secondaryEpoch\":" +
                nativeTimeIdentity(secondary, false) +
                ",\"primaryID\":" +
                (primary?.getID()?.toString() ?: "null") +
                ",\"secondaryID\":" +
                (secondary?.getID()?.toString() ?: "null") +
                ",\"success\":" +
                success +
                ",\"poisoned\":" +
                life.poisoned +
                ",\"retired\":" +
                life.retired +
                ",\"monoNs\":" +
                System.nanoTime() +
                "}",
        )
    }

    private fun equipmentLife(actor: IsoPlayer, create: Boolean): EquipmentLife? {
        equipmentLives.get(actor)?.let {
            return it
        }
        if (!create) return null
        check(equipmentLifetimeRecords.size < 512) { "Equipment lifetime ledger limit" }
        return EquipmentLife(actor).also {
            equipmentLives.put(actor, it)
            equipmentLifetimeRecords.add(it)
        }
    }

    private fun equipmentLifetimeCart(item: InventoryItem?): Boolean =
        when (item?.getFullType()) {
            "SaucedCarts.ShoppingCart",
            "SaucedWheelbarrow.WheelbarrowWood",
            "SaucedWheelbarrow.WheelbarrowMetal" -> true
            else -> false
        }

    private fun equipmentLifetimeRemember(life: EquipmentLife, actor: IsoPlayer) {
        val primary = actor.getPrimaryHandItem()
        val secondary = actor.getSecondaryHandItem()
        life.primary = WeakReference(primary)
        life.secondary = WeakReference(secondary)
        life.cart = primary?.getID() ?: 0
    }

    private fun equipmentLifetimeBegin(
        life: EquipmentLife,
        reason: String,
        candidate: Boolean,
    ): EquipmentMutation? {
        val thread = Thread.currentThread().threadId()
        val actor = life.actor.get()
        val pending = actor?.let(equipmentPendingBirths::get)
        if (pending != null && pending.previous === life && !pending.invalid) {
            if (pending.depth == Int.MAX_VALUE || pending.depth > 0 && pending.thread != thread) {
                pending.invalid = true
                return null
            }
            pending.depth++
            pending.thread = thread
            return EquipmentMutation(
                life,
                pending.depth,
                thread,
                0,
                reason,
                actor.getPrimaryHandItem(),
                actor.getSecondaryHandItem(),
                null,
                pending,
            )
        }
        if (life.retired || life.poisoned) return null
        if (life.depth > 0 && life.thread != thread) {
            life.poisoned = true
            return null
        }
        if (
            life.revision >= 9007199254740991L ||
                equipmentLifetimeMutationSerial >= 9007199254740991L ||
                life.depth == Int.MAX_VALUE
        ) {
            life.poisoned = true
            return null
        }
        life.revision++
        life.depth++
        life.thread = thread
        val parse = equipmentLifetimeParsing.get()
        if (!candidate) {
            life.hardRevision = life.revision
            if (parse != null) parse.invalid = true
        }
        val scope =
            EquipmentMutation(
                life,
                life.depth,
                thread,
                ++equipmentLifetimeMutationSerial,
                reason,
                actor?.getPrimaryHandItem(),
                actor?.getSecondaryHandItem(),
                parse,
                null,
            )
        equipmentLifetimeTrace("mutation-enter", life, scope, reason, true)
        return scope
    }

    /** Invalidate before native OnEquip callbacks; getters remain denied until native exit. */
    @JvmStatic
    fun equipmentLifetimeHands(
        actor: IsoGameCharacter?,
        incoming: InventoryItem?,
        primary: Boolean,
    ): EquipmentMutation? {
        if (!equipmentLifetimeEnabled() || actor !is IsoPlayer) return null
        return try {
            synchronized(equipmentLifetimeLock) {
                val life = equipmentLife(actor, false) ?: return null
                val old = if (primary) actor.getPrimaryHandItem() else actor.getSecondaryHandItem()
                if (old === incoming) return null
                val parse = equipmentLifetimeParsing.get()
                var candidate = false
                if (parse != null) {
                    val direct = equipmentLifetimeDirect(primary)
                    if (direct) parse.directCalls++ else parse.genericCalls++
                    if (parse.life == null) {
                        parse.life = life
                        parse.actor = actor
                        parse.original = actor.getPrimaryHandItem()
                        parse.beforeRevision = life.revision
                        parse.beforeHardRevision = life.hardRevision
                    }
                    if (
                        parse.trusted &&
                            !parse.invalid &&
                            parse.actor === actor &&
                            life.baseline &&
                            !life.retired &&
                            !life.poisoned &&
                            life.depth == 0 &&
                            equipmentLifetimeConnection(actor) === parse.connection &&
                            life.connection.get() === parse.connection &&
                            !actor.isLocalPlayer() &&
                            direct
                    ) {
                        if (
                            primary &&
                                parse.stage == 0 &&
                                life.parseDepth == 0 &&
                                old != null &&
                                old === actor.getSecondaryHandItem() &&
                                life.primary.get() === old &&
                                life.secondary.get() === old &&
                                life.cart == old.getID() &&
                                incoming != null &&
                                incoming !== old &&
                                equipmentLifetimeCart(old) &&
                                old.getWorldItem() == null &&
                                incoming.getID() == old.getID() &&
                                incoming.getFullType() == old.getFullType() &&
                                incoming.getWorldItem() == null
                        ) {
                            parse.next = incoming
                            parse.stage = 1
                            life.parseDepth++
                            candidate = true
                        } else if (
                            !primary &&
                                parse.stage == 1 &&
                                life.parseDepth == 1 &&
                                incoming === parse.next &&
                                actor.getPrimaryHandItem() === parse.next &&
                                old === parse.original
                        ) {
                            parse.stage = 2
                            candidate = true
                        }
                    }
                    if (!candidate) parse.invalid = true
                }
                equipmentLifetimeBegin(life, if (primary) "primary" else "secondary", candidate)
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
            null
        }
    }

    @JvmStatic
    fun equipmentLifetimeLoad(actor: IsoGameCharacter?, reason: String): EquipmentMutation? {
        if (!equipmentLifetimeEnabled() || actor !is IsoPlayer) return null
        return try {
            synchronized(equipmentLifetimeLock) {
                equipmentLife(actor, false)?.let { equipmentLifetimeBegin(it, reason, false) }
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
            null
        }
    }

    @JvmStatic
    fun equipmentLifetimeOnlineID(actor: IsoPlayer, incoming: Short): EquipmentMutation? =
        if (actor.getOnlineID() == incoming) null else equipmentLifetimeLoad(actor, "online-id")

    @JvmStatic
    fun equipmentLifetimeItem(
        item: InventoryItem,
        changed: Boolean,
        reason: String,
    ): ArrayList<EquipmentMutation>? {
        if (!equipmentLifetimeEnabled() || !changed) return null
        return try {
            synchronized(equipmentLifetimeLock) {
                val scopes = ArrayList<EquipmentMutation>()
                for (life in equipmentLifetimeRecords) if (
                    life.actor.get() != null &&
                        (life.primary.get() === item || life.secondary.get() === item)
                )
                    equipmentLifetimeBegin(life, reason, false)?.let(scopes::add)
                scopes
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
            null
        }
    }

    @JvmStatic
    fun equipmentLifetimeExit(scope: EquipmentMutation?, failure: Throwable?) {
        scope ?: return
        try {
            synchronized(equipmentLifetimeLock) {
                val life = scope.life
                val pending = scope.pending
                if (pending != null) {
                    if (
                        failure != null ||
                            pending.depth != scope.depth ||
                            pending.thread != scope.thread ||
                            Thread.currentThread().threadId() != scope.thread
                    )
                        pending.invalid = true
                    if (pending.depth > 0) pending.depth--
                    if (pending.depth == 0) pending.thread = 0
                    return
                }
                if (
                    failure != null ||
                        life.depth != scope.depth ||
                        life.thread != scope.thread ||
                        Thread.currentThread().threadId() != scope.thread
                ) {
                    life.poisoned = true
                    life.hardRevision = life.revision
                    scope.parse?.invalid = true
                }
                if (life.depth > 0) life.depth--
                if (life.depth == 0) {
                    life.thread = 0
                    val actor = life.actor.get()
                    if (actor != null && !life.poisoned && !life.retired)
                        equipmentLifetimeRemember(life, actor)
                }
                equipmentLifetimeTrace(
                    "mutation-exit",
                    life,
                    scope,
                    scope.reason,
                    failure == null && !life.poisoned,
                )
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
        }
    }

    @JvmStatic
    fun equipmentLifetimeItemExit(scopes: ArrayList<EquipmentMutation>?, failure: Throwable?) {
        if (scopes != null)
            for (i in scopes.size - 1 downTo 0) equipmentLifetimeExit(scopes[i], failure)
    }

    @JvmStatic
    fun equipmentLifetimeRetire(actor: IsoGameCharacter?, reason: String) {
        if (!equipmentLifetimeEnabled() || actor !is IsoPlayer) return
        try {
            synchronized(equipmentLifetimeLock) {
                val life = equipmentLife(actor, true)!!
                equipmentPendingBirths.get(actor)?.invalid = true
                val slot = actor.playerIndex
                life.retiredRegistered =
                    life.retiredRegistered ||
                        GameServer.server &&
                            !GameClient.client &&
                            GameServer.IDToPlayerMap[actor.getOnlineID()] === actor ||
                        GameClient.client &&
                            !GameServer.server &&
                            (GameClient.IDToPlayerMap[actor.getOnlineID()] === actor ||
                                slot >= 0 &&
                                    slot < IsoPlayer.players.size &&
                                    IsoPlayer.players[slot] === actor)
                life.retired = true
                if (life.retirementReason == null || reason != "actor-remove")
                    life.retirementReason = reason
                life.hardRevision = life.revision
                equipmentLifetimeParsing.get()?.invalid = true
                equipmentLifetimeTrace("retire", life, null, reason, true)
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
        }
    }

    @JvmStatic
    fun equipmentLifetimeDisconnect(engine: UdpEngine, guid: Long) {
        if (!equipmentLifetimeEnabled()) return
        try {
            synchronized(equipmentLifetimeLock) {
                val connection = engine.getActiveConnection(guid) ?: return
                equipmentRetiredConnections.put(connection, true)
                for (life in equipmentLifetimeRecords) if (life.connection.get() === connection) {
                    life.retired = true
                    life.retirementReason = "connection-remove"
                    life.hardRevision = life.revision
                    equipmentLifetimeTrace("retire", life, null, "connection-remove", true)
                }
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
        }
    }

    private fun equipmentLifetimeConnection(player: IsoPlayer?): UdpConnection? {
        if (
            player == null ||
                player.getOnlineID() < 0 ||
                player.removedFromWorldMs != 0L && !equipmentLifetimeBornAfterRemoval(player) ||
                !player.isAlive()
        )
            return null
        val engine: UdpEngine?
        val connection: UdpConnection?
        when {
            GameServer.server && !GameClient.client -> {
                if (GameServer.IDToPlayerMap[player.getOnlineID()] !== player) return null
                connection = GameServer.getConnectionFromPlayer(player)
                engine = GameServer.udpEngine
                val slot = player.playerIndex
                if (connection == null || slot !in 0..3 || connection.getPlayerAt(slot) !== player)
                    return null
            }
            GameClient.client && !GameServer.server -> {
                if (
                    GameClient.instance == null ||
                        !GameClient.instance.connected ||
                        GameClient.IDToPlayerMap[player.getOnlineID()] !== player
                )
                    return null
                connection = GameClient.connection
                engine = GameClient.instance.udpEngine
            }
            else -> return null
        }
        return connection?.takeIf {
            equipmentRetiredConnections.get(it) == null &&
                engine != null &&
                engine.getActiveConnection(it.getConnectedGUID()) === it
        }
    }

    private fun equipmentLifetimeRead(player: IsoPlayer, connection: UdpConnection): String? =
        synchronized(equipmentLifetimeLock) {
            equipmentLifetimeActivateBirth(player, connection)
            val life = equipmentLife(player, true)!!
            if (
                life.retired ||
                    life.poisoned ||
                    life.depth != 0 ||
                    life.parseDepth != 0 ||
                    equipmentLifetimeParsing.get() != null
            )
                return null
            val item = player.getPrimaryHandItem()
            val secondary = player.getSecondaryHandItem()
            if (
                life.baseline &&
                    (life.connection.get() !== connection ||
                        life.primary.get() !== item ||
                        life.secondary.get() !== secondary ||
                        item != null && life.cart != item.getID())
            ) {
                life.poisoned = true
                return null
            }
            if (
                item == null ||
                    item !== secondary ||
                    !equipmentLifetimeCart(item) ||
                    item.getWorldItem() != null
            )
                return null
            if (!life.baseline) {
                life.baseline = true
                life.connection = WeakReference(connection)
                equipmentLifetimeRemember(life, player)
                equipmentLifetimeTrace("baseline", life, null, "admitted-current", true)
            }
            if (life.revision !in life.issued) {
                check(equipmentLifetimeIssuedCount < 8192) { "Equipment issued-lifetime limit" }
                life.issued.add(life.revision)
                equipmentLifetimeIssuedCount++
            }
            "1|$nativeTimeProcess|${life.actorEpoch}|${nativeTimeIdentity(connection, false)}|${life.revision}"
        }

    private fun equipmentLifetimeDirect(primary: Boolean): Boolean {
        val method = if (primary) "setPrimaryHandItem" else "setSecondaryHandItem"
        return StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE).walk { frames ->
            frames
                .dropWhile {
                    it.declaringClass != IsoGameCharacter::class.java || it.methodName != method
                }
                .skip(1)
                .findFirst()
                .map {
                    it.declaringClass == zombie.network.packets.EquipPacket::class.java &&
                        it.methodName == "parse"
                }
                .orElse(false)
        }
    }

    @JvmStatic
    fun equipmentLifetimeParseEnter(
        reader: ByteBufferReader?,
        supplied: IConnection?,
    ): EquipmentParse? {
        if (!equipmentLifetimeEnabled()) return null
        var scope: EquipmentParse? = null
        return try {
            synchronized(equipmentLifetimeLock) {
                val previous = equipmentLifetimeParsing.get()
                previous?.invalid = true
                check(equipmentLifetimeParseSerial < 9007199254740991L) {
                    "Equipment parse serial exhausted"
                }
                val connection = supplied as? UdpConnection
                val dispatch = leaseControlDispatch.get()
                val ingress = reader?.let(leaseControlIngresses::get)
                val trusted =
                    previous == null &&
                        connection != null &&
                        dispatch != null &&
                        dispatch.reader === reader &&
                        dispatch.ingress === ingress &&
                        ingress != null &&
                        ingress.transport.type == PacketType.Equip.getId().toInt() &&
                        ingress.transport.connection.get() === connection &&
                        leaseControlCurrent(ingress.transport, false)
                EquipmentParse(
                        reader,
                        connection,
                        ingress,
                        dispatch,
                        previous,
                        ++equipmentLifetimeParseSerial,
                        trusted,
                    )
                    .also {
                        scope = it
                        equipmentLifetimeParsing.set(it)
                    }
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
            scope
        }
    }

    @JvmStatic
    fun equipmentLifetimeParseExit(scope: EquipmentParse?, failure: Throwable?) {
        scope ?: return
        try {
            synchronized(equipmentLifetimeLock) {
                if (equipmentLifetimeParsing.get() !== scope) scope.invalid = true
                val life = scope.life
                val actor = scope.actor
                if (life != null) {
                    val original = scope.original
                    val next = scope.next
                    val ingress = scope.ingress
                    val certified =
                        failure == null &&
                            scope.trusted &&
                            !scope.invalid &&
                            scope.stage == 2 &&
                            scope.directCalls == 2 &&
                            scope.genericCalls == 0 &&
                            life.depth == 0 &&
                            life.parseDepth == 1 &&
                            !life.poisoned &&
                            !life.retired &&
                            life.hardRevision == scope.beforeHardRevision &&
                            actor != null &&
                            equipmentLifetimeConnection(actor) === scope.connection &&
                            actor.getPrimaryHandItem() === next &&
                            actor.getSecondaryHandItem() === next &&
                            original != null &&
                            next != null &&
                            original !== next &&
                            original.getID() == next.getID() &&
                            original.getFullType() == next.getFullType() &&
                            original.getWorldItem() == null &&
                            next.getWorldItem() == null &&
                            equipmentLifetimeCart(next) &&
                            ingress != null &&
                            leaseControlDispatch.get() === scope.dispatch &&
                            leaseControlIngresses.get(scope.reader) === ingress &&
                            leaseControlCurrent(ingress.transport, false)
                    if (!certified) life.hardRevision = life.revision
                    if (life.parseDepth > 0) life.parseDepth--
                    if (failure != null) {
                        life.poisoned = true
                        scope.invalid = true
                    }
                    equipmentLifetimeTrace(
                        "resnapshot",
                        life,
                        null,
                        "remote-equip-resnapshot",
                        certified,
                    )
                }
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
        } finally {
            if (scope.previous == null) equipmentLifetimeParsing.remove()
            else equipmentLifetimeParsing.set(scope.previous)
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseResnapshot", global = true)
    fun cartLeaseResnapshot(player: IsoPlayer?, previousLifetime: String?): Boolean {
        if (
            !equipmentLifetimeEnabled() || previousLifetime == null || previousLifetime.length > 160
        )
            return false
        return try {
            synchronized(equipmentLifetimeLock) {
                val connection = equipmentLifetimeConnection(player)
                val life = player?.let { equipmentLife(it, false) }
                if (
                    connection == null ||
                        life == null ||
                        !life.baseline ||
                        equipmentLifetimeRead(player, connection) == null
                )
                    return false
                val prefix =
                    "1|$nativeTimeProcess|${life.actorEpoch}|${nativeTimeIdentity(connection, false)}|"
                if (!previousLifetime.startsWith(prefix)) return false
                val field = previousLifetime.substring(prefix.length)
                if (!field.matches(Regex("[1-9][0-9]{0,15}"))) return false
                val revision = field.toLong()
                revision <= 9007199254740991L &&
                    revision in life.issued &&
                    revision >= life.hardRevision &&
                    revision < life.revision
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
            false
        }
    }

    class EquipmentBirth(
        val task: AddCoopPlayer,
        val actor: IsoPlayer,
        val engine: UdpEngine,
        val connection: UdpConnection,
        val previous: EquipmentBirth?,
    ) {
        var born: EquipmentPendingBirth? = null
    }

    class EquipmentPendingBirth(
        val previous: EquipmentLife,
        val epoch: Long,
        val removedStamp: Long,
        engine: UdpEngine,
        connection: UdpConnection,
    ) {
        val engine = WeakReference(engine)
        val connection = WeakReference(connection)
        var invalid = false
        var depth = 0
        var thread = 0L
    }

    private val equipmentPendingBirths = NativeWeakMap<IsoPlayer, EquipmentPendingBirth>()
    private val equipmentBirthScope = ThreadLocal<EquipmentBirth>()

    private fun equipmentBirthNativeCaller(type: Class<*>, method: String): Boolean =
        StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE).walk { frames ->
            frames
                .dropWhile { it.declaringClass == EquipmentLifetime::class.java }
                .findFirst()
                .map { it.declaringClass == type && it.methodName == method }
                .orElse(false)
        }

    private fun equipmentBirthTransport(engine: UdpEngine?, connection: UdpConnection?): Boolean =
        GameClient.client &&
            !GameServer.server &&
            Thread.currentThread() === zombie.GameWindow.gameThread &&
            GameClient.instance != null &&
            GameClient.instance.connected &&
            engine != null &&
            connection != null &&
            GameClient.instance.udpEngine === engine &&
            GameClient.connection === connection &&
            equipmentRetiredConnections.get(connection) == null &&
            engine.getActiveConnection(connection.getConnectedGUID()) === connection

    @JvmStatic
    fun equipmentLifetimeCoopEnter(task: AddCoopPlayer?): EquipmentBirth? {
        if (
            !equipmentLifetimeEnabled() ||
                task == null ||
                !equipmentBirthNativeCaller(AddCoopPlayer::class.java, "update")
        )
            return null
        return try {
            synchronized(equipmentLifetimeLock) {
                val actor = task.getPlayer()
                val engine = GameClient.instance?.udpEngine
                val connection = GameClient.connection
                if (
                    actor == null ||
                        task.isFinished() ||
                        zombie.iso.IsoWorld.instance == null ||
                        !zombie.iso.IsoWorld.instance.addCoopPlayers.contains(task) ||
                        !equipmentBirthTransport(engine, connection)
                )
                    return null
                EquipmentBirth(task, actor, engine!!, connection!!, equipmentBirthScope.get())
                    .also(equipmentBirthScope::set)
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
            null
        }
    }

    @JvmStatic
    fun equipmentLifetimeCoopExit(scope: EquipmentBirth?, failure: Throwable?) {
        scope ?: return
        try {
            synchronized(equipmentLifetimeLock) {
                check(equipmentBirthScope.get() === scope) { "Native birth scope mismatch" }
                if (failure != null) scope.born?.invalid = true
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
        } finally {
            if (scope.previous == null) equipmentBirthScope.remove()
            else equipmentBirthScope.set(scope.previous)
        }
    }

    /** Only the original AddCoopPlayer native event can witness a distinct birth. */
    @JvmStatic
    fun equipmentLifetimeCoopEvent(event: String?, index: Any?, supplied: Any?) {
        if (
            !equipmentLifetimeEnabled() ||
                event != "OnCreatePlayer" ||
                index !is Int ||
                supplied !is IsoPlayer
        )
            return
        try {
            synchronized(equipmentLifetimeLock) {
                val actor = supplied
                val slot = index
                val scope = equipmentBirthScope.get()
                val origin =
                    StackWalker.getInstance(StackWalker.Option.RETAIN_CLASS_REFERENCE).walk { frames
                        ->
                        val callers =
                            frames
                                .dropWhile {
                                    it.declaringClass != zombie.Lua.LuaEventManager::class.java ||
                                        it.methodName != "triggerEvent"
                                }
                                .limit(2)
                                .toList()
                        callers.size == 2 &&
                            callers[0].methodType.parameterCount() == 3 &&
                            callers[1].declaringClass == AddCoopPlayer::class.java &&
                            callers[1].methodName == "update"
                    }
                if (
                    !origin ||
                        scope == null ||
                        scope.born != null ||
                        scope.actor !== actor ||
                        scope.task.getPlayer() !== actor ||
                        scope.task.getPlayerIndex() != slot ||
                        slot != 0 ||
                        actor.playerIndex != slot ||
                        IsoPlayer.players[slot] !== actor ||
                        IsoPlayer.getInstance() !== actor ||
                        !actor.isLocalPlayer() ||
                        !actor.isAlive() ||
                        actor.isDead() ||
                        zombie.iso.IsoWorld.instance == null ||
                        !zombie.iso.IsoWorld.instance.addCoopPlayers.contains(scope.task) ||
                        !equipmentBirthTransport(scope.engine, scope.connection)
                )
                    return
                val previous = equipmentLife(actor, false) ?: return
                // An issued or registered removal remains permanent; only an unissued preview can
                // be born.
                if (
                    !previous.retired ||
                        previous.born ||
                        previous.birthPending ||
                        previous.retiredRegistered ||
                        previous.baseline ||
                        previous.issued.isNotEmpty() ||
                        previous.poisoned ||
                        previous.depth != 0 ||
                        previous.parseDepth != 0 ||
                        previous.retirementReason != "actor-remove"
                )
                    return
                val pending =
                    EquipmentPendingBirth(
                        previous,
                        nativeTimeNext(),
                        actor.removedFromWorldMs,
                        scope.engine,
                        scope.connection,
                    )
                previous.birthPending = true
                equipmentPendingBirths.put(actor, pending)
                scope.born = pending
                println(
                    "[CART_EQUIPMENT_BIRTH] {\"schema\":1,\"diagnosticOnly\":true,\"authorityProof\":false,\"process\":" +
                        mpJsonString(nativeTimeProcess) +
                        ",\"oldActorEpoch\":" +
                        previous.actorEpoch +
                        ",\"newActorEpoch\":" +
                        pending.epoch +
                        ",\"objectEpoch\":" +
                        nativeTimeIdentity(actor, true) +
                        ",\"taskEpoch\":" +
                        nativeTimeIdentity(scope.task, false) +
                        ",\"playerIndex\":" +
                        slot +
                        ",\"connectionEpoch\":" +
                        nativeTimeIdentity(scope.connection, false) +
                        ",\"removedFromWorldMsWitness\":" +
                        pending.removedStamp +
                        ",\"prebirthRetired\":" +
                        previous.retired +
                        ",\"prebirthUnissued\":" +
                        previous.issued.isEmpty() +
                        ",\"prebirthUnbaselined\":" +
                        !previous.baseline +
                        ",\"prebirthRegistered\":" +
                        previous.retiredRegistered +
                        ",\"prebirthReason\":" +
                        mpJsonString(previous.retirementReason) +
                        ",\"nativeOrigin\":\"AddCoopPlayer.update/OnCreatePlayer\",\"monoNs\":" +
                        System.nanoTime() +
                        "}",
                )
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
        }
    }

    private fun equipmentPendingBirthValid(
        actor: IsoPlayer,
        pending: EquipmentPendingBirth?,
    ): Boolean =
        pending != null &&
            !pending.invalid &&
            pending.depth == 0 &&
            pending.thread == 0L &&
            equipmentLife(actor, false) === pending.previous &&
            pending.previous.retired &&
            !pending.previous.retiredRegistered &&
            !pending.previous.baseline &&
            pending.previous.issued.isEmpty() &&
            pending.previous.retirementReason == "actor-remove" &&
            !pending.previous.poisoned &&
            actor.removedFromWorldMs == pending.removedStamp &&
            actor.playerIndex == 0 &&
            IsoPlayer.players[0] === actor &&
            IsoPlayer.getInstance() === actor &&
            actor.isLocalPlayer() &&
            actor.isAlive() &&
            !actor.isDead() &&
            equipmentBirthTransport(pending.engine.get(), pending.connection.get())

    private fun equipmentLifetimeBornAfterRemoval(actor: IsoPlayer): Boolean {
        if (equipmentPendingBirthValid(actor, equipmentPendingBirths.get(actor))) return true
        val life = equipmentLife(actor, false) ?: return false
        return life.born &&
            !life.retired &&
            !life.poisoned &&
            actor.removedFromWorldMs == life.birthRemovedStamp &&
            life.birthEngine.get() != null &&
            life.birthConnection.get() != null &&
            equipmentBirthTransport(life.birthEngine.get(), life.birthConnection.get())
    }

    private fun equipmentLifetimeActivateBirth(actor: IsoPlayer, connection: UdpConnection) {
        val pending = equipmentPendingBirths.get(actor) ?: return
        val primary = actor.getPrimaryHandItem()
        if (
            !equipmentPendingBirthValid(actor, pending) ||
                connection !== pending.connection.get() ||
                GameClient.IDToPlayerMap[actor.getOnlineID()] !== actor ||
                actor.getOnlineID() < 0 ||
                primary == null ||
                primary !== actor.getSecondaryHandItem() ||
                !equipmentLifetimeCart(primary) ||
                primary.getWorldItem() != null ||
                equipmentLifetimeParsing.get() != null
        )
            return
        check(equipmentLifetimeRecords.size < 512) { "Equipment birth ledger limit" }
        val fresh =
            EquipmentLife(actor, pending.epoch).apply {
                born = true
                birthRemovedStamp = pending.removedStamp
                birthEngine = pending.engine
                birthConnection = pending.connection
            }
        equipmentLives.put(actor, fresh)
        equipmentLifetimeRecords.add(fresh)
        equipmentPendingBirths.remove(actor)
    }

    /** Read-only snapshot; it creates no lifetime and supplies no authority. */
    @JvmStatic
    @LuaMethod(name = "cartLeaseEligibility", global = true)
    fun cartLeaseEligibility(player: IsoPlayer?): String? {
        if (!LEASE_LIFETIME || !LEASE_CONTROL) return null
        return try {
            synchronized(equipmentLifetimeLock) {
                val life = player?.let { equipmentLife(it, false) }
                val server = GameServer.server && !GameClient.client
                val client = GameClient.client && !GameServer.server
                val engine =
                    if (server) GameServer.udpEngine
                    else if (client) GameClient.instance?.udpEngine else null
                val connection =
                    if (server && player != null) GameServer.getConnectionFromPlayer(player)
                    else if (client) GameClient.connection else null
                val mapped = player?.let { GameClient.IDToPlayerMap[it.getOnlineID()] }
                val mappedLife = mapped?.let { equipmentLife(it, false) }
                val pending = player?.let(equipmentPendingBirths::get)
                val primary = player?.getPrimaryHandItem()
                val secondary = player?.getSecondaryHandItem()
                val slot = player?.playerIndex ?: -1
                val active =
                    if (engine == null || connection == null) "null"
                    else
                        (engine.getActiveConnection(connection.getConnectedGUID()) === connection)
                            .toString()
                "{\"schema\":1,\"diagnosticOnly\":true,\"authorityProof\":false,\"process\":" +
                    mpJsonString(nativeTimeProcess) +
                    ",\"equipmentHealthy\":" +
                    !equipmentLifetimeFailed +
                    ",\"controlHealthy\":" +
                    !leaseControlFailed +
                    ",\"playerPresent\":" +
                    (player != null) +
                    ",\"actorEpoch\":" +
                    (life?.actorEpoch ?: nativeTimeIdentity(player, true)) +
                    ",\"objectEpoch\":" +
                    nativeTimeIdentity(player, true) +
                    ",\"onlineID\":" +
                    (player?.getOnlineID() ?: -1) +
                    ",\"playerIndex\":" +
                    slot +
                    ",\"localPlayer\":" +
                    (player != null && player.isLocalPlayer()) +
                    ",\"localSlotExact\":" +
                    (player != null &&
                        slot >= 0 &&
                        slot < IsoPlayer.players.size &&
                        IsoPlayer.players[slot] === player) +
                    ",\"currentActorExact\":" +
                    (player != null && IsoPlayer.getInstance() === player) +
                    ",\"clientMapActorEpoch\":" +
                    (mappedLife?.actorEpoch ?: nativeTimeIdentity(mapped, true)) +
                    ",\"clientMapObjectEpoch\":" +
                    nativeTimeIdentity(mapped, true) +
                    ",\"clientMapExact\":" +
                    (player != null && mapped === player) +
                    ",\"alive\":" +
                    (player != null && player.isAlive()) +
                    ",\"dead\":" +
                    (player != null && player.isDead()) +
                    ",\"removedFromWorldMs\":" +
                    (player?.removedFromWorldMs ?: 0) +
                    ",\"sourceRole\":" +
                    mpJsonString(if (server) "server" else if (client) "client" else "unknown") +
                    ",\"clientConnected\":" +
                    (GameClient.instance != null && GameClient.instance.connected) +
                    ",\"engineKnown\":" +
                    (engine != null) +
                    ",\"connectionEpoch\":" +
                    nativeTimeIdentity(connection, false) +
                    ",\"connectionRetired\":" +
                    (connection != null && equipmentRetiredConnections.get(connection) != null) +
                    ",\"exactActiveMapping\":" +
                    active +
                    ",\"lifePresent\":" +
                    (life != null) +
                    ",\"baseline\":" +
                    (life != null && life.baseline) +
                    ",\"retired\":" +
                    (life != null && life.retired) +
                    ",\"poisoned\":" +
                    (life != null && life.poisoned) +
                    ",\"revision\":" +
                    (life?.revision ?: 0) +
                    ",\"hardRevision\":" +
                    (life?.hardRevision ?: 0) +
                    ",\"depth\":" +
                    (life?.depth ?: 0) +
                    ",\"parseDepth\":" +
                    (life?.parseDepth ?: 0) +
                    ",\"pendingBirth\":" +
                    (pending != null && !pending.invalid) +
                    ",\"pendingBirthEpoch\":" +
                    (pending?.epoch ?: 0) +
                    ",\"pendingBirthDepth\":" +
                    (pending?.depth ?: 0) +
                    ",\"born\":" +
                    (life != null && life.born) +
                    ",\"issuedCount\":" +
                    (life?.issued?.size ?: 0) +
                    ",\"primaryEpoch\":" +
                    nativeTimeIdentity(primary, false) +
                    ",\"secondaryEpoch\":" +
                    nativeTimeIdentity(secondary, false) +
                    ",\"primaryID\":" +
                    (primary?.getID()?.toString() ?: "null") +
                    ",\"secondaryID\":" +
                    (secondary?.getID()?.toString() ?: "null") +
                    ",\"primaryType\":" +
                    mpJsonString(primary?.getFullType()) +
                    ",\"secondaryType\":" +
                    mpJsonString(secondary?.getFullType()) +
                    ",\"primaryWorldAttached\":" +
                    (primary != null && primary.getWorldItem() != null) +
                    ",\"secondaryWorldAttached\":" +
                    (secondary != null && secondary.getWorldItem() != null) +
                    ",\"sameHands\":" +
                    (primary != null && primary === secondary) +
                    "}"
            }
        } catch (_: Throwable) {
            null
        }
    }

    @JvmStatic
    @LuaMethod(name = "cartLeaseLifetime", global = true)
    fun cartLeaseLifetime(player: IsoPlayer?): String? {
        if (!equipmentLifetimeEnabled()) return null
        return try {
            synchronized(equipmentLifetimeLock) {
                val connection = equipmentLifetimeConnection(player) ?: return null
                equipmentLifetimeRead(player!!, connection)
            }
        } catch (error: Throwable) {
            equipmentLifetimeError(error)
            null
        }
    }

    @Patch(
        className = "zombie.Lua.LuaEventManager",
        methodName = "triggerEvent",
        strictMatch = true,
        warmUp = true,
    )
    object EquipmentLifetimeCoopCreateEvent {
        @JvmStatic
        @Patch.OnEnter
        fun enter(
            @Patch.Argument(0) event: String?,
            @Patch.Argument(1) index: Any?,
            @Patch.Argument(2) actor: Any?,
        ) {
            equipmentLifetimeCoopEvent(event, index, actor)
        }
    }

    @Patch(className = "zombie.characters.IsoPlayer", methodName = "OnDeath", warmUp = false)
    object EquipmentLifetimeDeath {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This actor: IsoPlayer) {
            equipmentLifetimeRetire(actor, "actor-death")
        }
    }

    @Patch(
        className = "zombie.characters.IsoPlayer",
        methodName = "removeFromWorld",
        warmUp = false,
    )
    object EquipmentLifetimeRemove {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This actor: IsoPlayer) {
            equipmentLifetimeRetire(actor, "actor-remove")
        }
    }

    @Patch(
        className = "zombie.core.raknet.UdpEngine",
        methodName = "removeConnection",
        warmUp = false,
    )
    object EquipmentLifetimeDisconnect {
        @JvmStatic
        @Patch.OnEnter
        fun enter(@Patch.This engine: UdpEngine, @Patch.Argument(0) guid: Long) {
            equipmentLifetimeDisconnect(engine, guid)
        }
    }

    @JvmStatic fun initialize() = Unit
}
