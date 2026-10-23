import java.lang.reflect.Field
import java.util.HashMap
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract
import net.alexredby.cartlab.EquipmentLifetime
import net.alexredby.cartlab.LeaseControl
import net.alexredby.cartlab.NativeTime

// Actual native setter/removal advice checks; no game world, save, socket or installation.
object EquipmentLifetimeCheck {
    private lateinit var unsafe: sun.misc.Unsafe
    private var eventCallbacks: Int = 0
    private var eventFailure: String? = null
    private var deathExpected: Owner? = null
    private var deathItem: zombie.inventory.InventoryItem? = null
    private var deathCallbacks: Int = 0
    private var deathFailure: String? = null
    private var deathToken: String? = null
    private lateinit var checkedParsing: ThreadLocal<EquipmentLifetime.EquipmentParse?>
    private var expectedParseTrust: Boolean? = null
    private var expectedDirectParse: Boolean = false
    private var parseCallbacks: Int = 0

    open class Owner : zombie.characters.IsoPlayer(null, null, 0, 0, 0) {
        var nested: Boolean = false
        var throwAfter: Boolean = false
        var nativeAliveCheck: Boolean = false
        var blockedCallbacks: Int = 0
        var nestedItem: zombie.inventory.InventoryItem? = null

        override fun getUsername(): String = "client1"

        override fun isAlive(): Boolean = !nativeAliveCheck || super.isAlive()

        override fun isInvulnerable(): Boolean = false

        override fun isLocalPlayer(): Boolean = false

        override fun getBallisticsController(): zombie.core.physics.BallisticsController? = null

        override fun checkAnimalAttachedToRope(item: zombie.inventory.InventoryItem?) {}

        protected override fun setEquipParent(
            old: zombie.inventory.InventoryItem?,
            next: zombie.inventory.InventoryItem?,
        ) {}

        protected override fun setEquipParent(
            old: zombie.inventory.InventoryItem?,
            next: zombie.inventory.InventoryItem?,
            ignored: Boolean,
        ) {}

        override fun setUseHandWeapon(item: zombie.inventory.types.HandWeapon?) {}

        override fun setVariable(
            key: String?,
            value: String?,
        ): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? {
            return null
        }

        override fun setVariable(
            key: String?,
            value: Boolean,
        ): zombie.core.skinnedmodel.advancedanimation.IAnimationVariableSlot? {
            return null
        }

        override fun resetEquippedHandsModels() {
            check(
                EquipmentLifetime.cartLeaseLifetime(this) == null,
                "Intermediate native callback exposed a lifetime",
            )
            blockedCallbacks++
            if (expectedParseTrust != null) {
                val parse = checkedParsing.get()
                check(
                    parse != null && parse.trusted == expectedParseTrust,
                    "Exact receipt/reader trust branch was not reached",
                )
                check(
                    (parse.directCalls > 0) == expectedDirectParse,
                    "Actual native parser caller classification changed",
                )
                parseCallbacks++
            }
            if (nested) {
                nested = false
                setSecondaryHandItem(nestedItem)
                check(
                    EquipmentLifetime.cartLeaseLifetime(this) == null,
                    "Nested setter exit exposed outer mutation",
                )
            }
            if (throwAfter) throw IllegalStateException("fixture setter failure")
        }
    }

    class Item :
        zombie.inventory.InventoryItem(
            "SaucedWheelbarrow",
            "WheelbarrowWood",
            "WheelbarrowWood",
            "Item_WheelbarrowWood",
        ) {
        override fun getFullType(): String = "SaucedWheelbarrow.WheelbarrowWood"
    }

    class Connection : zombie.core.raknet.UdpConnection(null, 1L, 0) {
        override fun getConnectedGUID(): Long = 1

        override fun getIndex(): Int = 0
    }

    class Engine() : zombie.core.raknet.UdpEngine(0, 0, 1, null, false)

    @OptIn(ExperimentalContracts::class)
    private fun check(value: Boolean, message: String?) {
        contract { returns() implies value }
        if (!value) throw AssertionError(message)
    }

    private fun field(type: Class<*>, name: String?): Field {
        val value = type.getDeclaredField(name)
        value.setAccessible(true)
        return value
    }

    private fun item(id: Int): Item {
        val item = unsafe.allocateInstance(Item::class.java) as Item
        item.setID(id)
        return item
    }

    private fun owner(item: Item?, id: Short): Owner {
        val owner = unsafe.allocateInstance(Owner::class.java) as Owner
        owner.onlineId = id
        owner.playerIndex = 0
        field(zombie.characters.IsoGameCharacter::class.java, "leftHandItem").set(owner, item)
        field(zombie.characters.IsoGameCharacter::class.java, "rightHandItem").set(owner, item)
        return owner
    }

    @Suppress("UNCHECKED_CAST")
    private fun connections(engine: Engine?): HashMap<Long?, zombie.core.raknet.UdpConnection?>? {
        return field(zombie.core.raknet.UdpEngine::class.java, "connectionMap").get(engine)
            as HashMap<Long?, zombie.core.raknet.UdpConnection?>
    }

    private fun registered(owner: Owner?, connection: Connection?, engine: Engine?) {
        zombie.network.GameServer.IDToPlayerMap.clear()
        zombie.network.GameServer.PlayerToAddressMap.clear()
        zombie.network.GameServer.IDToPlayerMap.put(owner!!.getOnlineID(), owner)
        zombie.network.GameServer.PlayerToAddressMap.put(owner, 1L)
        connection!!.players = arrayOf<zombie.characters.IsoPlayer?>(owner, null, null, null)
        connections(engine)!!.put(1L, connection)
        field(zombie.core.raknet.UdpEngine::class.java, "connectionArray")
            .set(engine, arrayOf<zombie.core.raknet.UdpConnection?>(connection))
    }

    private fun life(owner: Owner?): String {
        val life = EquipmentLifetime.cartLeaseLifetime(owner)
        check(life != null, "Expected admitted current lifetime")
        return life
    }

    @Suppress("UNCHECKED_CAST")
    private fun deathChecks(engine: Engine?, connection: Connection?) {
        val item = item(42)
        val dying = owner(item, 7.toShort())
        registered(dying, connection, engine)
        dying.nativeAliveCheck = true
        dying.setHealth(100f)
        val token = life(dying)
        check(dying.isAlive, "Native health baseline is not alive")
        val lives =
            field(EquipmentLifetime::class.java, "equipmentLives").get(null)
                as
                NativeTime.NativeWeakMap<
                    zombie.characters.IsoPlayer,
                    EquipmentLifetime.EquipmentLife,
                >
        dying.setHealth(0f)
        check(!dying.isAlive, "Native death health not applied")
        check(
            EquipmentLifetime.cartLeaseLifetime(dying) == null && !lives.get(dying)!!.retired,
            "Dead guard did not precede permanent native entry retirement",
        )
        deathExpected = dying
        deathItem = item
        deathToken = token
        val beforeCallbacks = deathCallbacks
        // Actual instrumented native OnDeath; server role stops after its original superclass
        // event,
        // before world-dependent client UI/drop code. No helper or fake event invokes the advice.
        dying.OnDeath()
        check(
            deathCallbacks == beforeCallbacks + 1 && deathFailure == null,
            "Native superclass death callback absent or observed a live binding: " + deathFailure,
        )
        check(
            lives.get(dying)!!.retired,
            "Native OnDeath did not leave a permanent actor tombstone",
        )
        dying.setHealth(100f)
        dying.setPrimaryHandItem(null)
        dying.setSecondaryHandItem(null)
        dying.setPrimaryHandItem(item)
        dying.setSecondaryHandItem(item)
        check(
            dying.isAlive &&
                dying.getHealth() == 100f &&
                dying.getPrimaryHandItem() === item &&
                dying.getSecondaryHandItem() === item,
            "Native health/hands restoration fixture did not restore exact actor/item",
        )
        check(
            EquipmentLifetime.cartLeaseLifetime(dying) == null &&
                !EquipmentLifetime.cartLeaseResnapshot(dying, token),
            "Restored health/hands resurrected native death token",
        )
        check(dying.removedFromWorldMs == 0L, "Death entry check unexpectedly used actor removal")
        val fresh = owner(item, 7.toShort())
        registered(fresh, connection, engine)
        check(
            !life(fresh).equals(token),
            "Death tombstone collapsed fresh same-ID actor incarnation",
        )
        deathExpected = null
        deathItem = null
        deathToken = null
        System.out.println(
            "EQUIPMENT_NATIVE_DEATH_ENTRY_CHECK_PASS callbacks=" +
                (deathCallbacks - beforeCallbacks) +
                " restoredHealthHands=true oldTokenRevived=false actorRemoval=false",
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseChecks(engine: Engine?, connection: Connection?) {
        // Only negative classifier tests seed receipt objects. Positive native receipt proof is the
        // Host gate.
        val ingress =
            field(LeaseControl::class.java, "leaseControlIngresses").get(null)
                as
                NativeTime.NativeWeakMap<
                    zombie.core.network.ByteBufferReader,
                    LeaseControl.LeaseCommandIngress?,
                >
        val dispatch =
            field(LeaseControl::class.java, "leaseControlDispatch").get(null)
                as ThreadLocal<LeaseControl.LeaseDispatchScope?>
        val parsing =
            field(EquipmentLifetime::class.java, "equipmentLifetimeParsing").get(null)
                as ThreadLocal<EquipmentLifetime.EquipmentParse?>
        checkedParsing = parsing
        zombie.network.GameServer.server = false
        zombie.network.GameClient.client = true
        zombie.network.GameClient.instance.udpEngine = engine
        zombie.network.GameClient.instance.connected = true
        zombie.network.GameClient.connection = connection
        for (scenario in
            arrayOf<String>(
                "untrusted-release",
                "trusted-release",
                "trusted-failed-parse",
                "foreign-reader",
                "trusted-indirect-setters",
            )) {
            val original = item(42)
            val player = owner(original, 7.toShort())
            registered(player, connection, engine)
            zombie.network.GameClient.IDToPlayerMap.clear()
            zombie.network.GameClient.IDToPlayerMap.put(7.toShort(), player)
            val before = life(player)
            val bytes =
                java.nio.ByteBuffer.allocate(16)
                    .putShort(7.toShort())
                    .put((-1).toByte())
                    .put(0.toByte())
            if (!scenario.equals("trusted-failed-parse")) bytes.put(0.toByte())
            bytes.flip()
            val reader = zombie.core.network.ByteBufferReader(bytes)
            val receipt =
                LeaseControl.LeaseCommandIngress(
                    100L + scenario.length,
                    LeaseControl.LeaseTransport(
                        java.lang.ref.WeakReference(engine),
                        java.lang.ref.WeakReference(connection),
                        NativeTime.nativeTimeIdentity(connection, false),
                        1,
                        zombie.network.PacketTypes.PacketType.Equip.getId().toInt(),
                    ),
                )
            if (!scenario.equals("untrusted-release")) {
                ingress.put(reader, receipt)
                val selected =
                    if (scenario.equals("foreign-reader"))
                        zombie.core.network.ByteBufferReader(bytes.duplicate())
                    else reader
                dispatch.set(LeaseControl.LeaseDispatchScope(selected, receipt, null))
            }
            var threw = false
            val beforeCallbacks = parseCallbacks
            expectedParseTrust = scenario.startsWith("trusted")
            expectedDirectParse = !scenario.equals("trusted-indirect-setters")
            try {
                if (scenario.equals("trusted-indirect-setters")) {
                    val scope = EquipmentLifetime.equipmentLifetimeParseEnter(reader, connection)
                    check(scope != null && scope.trusted, "Trusted negative-scope fixture refused")
                    val next = item(42)
                    player.setPrimaryHandItem(next)
                    player.setSecondaryHandItem(next)
                    check(
                        EquipmentLifetime.cartLeaseLifetime(player) == null &&
                            !EquipmentLifetime.cartLeaseResnapshot(player, before),
                        "Indirect setters exposed in-progress outer parse",
                    )
                    EquipmentLifetime.equipmentLifetimeParseExit(scope, null)
                } else zombie.network.packets.EquipPacket().parse(reader, connection)
            } catch (expected: java.nio.BufferUnderflowException) {
                threw = true
            } finally {
                expectedParseTrust = null
                dispatch.remove()
                ingress.remove(reader)
            }
            check(
                parseCallbacks > beforeCallbacks,
                "Native parse did not reach the receipt trust assertion",
            )
            check(
                threw == scenario.equals("trusted-failed-parse"),
                "Actual native parse failure fixture changed",
            )
            check(parsing.get() == null, "Native parse scope leaked after " + scenario)
            if (!scenario.equals("trusted-indirect-setters"))
                check(
                    player.getPrimaryHandItem() == null,
                    "Actual native parse did not release primary",
                )
            check(
                !EquipmentLifetime.cartLeaseResnapshot(player, before),
                "Release, indirect call or failed parse certified as resnapshot",
            )
            if (!scenario.equals("trusted-indirect-setters"))
                check(
                    EquipmentLifetime.cartLeaseLifetime(player) == null,
                    "Release or failed parse exposed held lifetime",
                )
            player.setPrimaryHandItem(original)
            player.setSecondaryHandItem(original)
            if (threw)
                check(
                    EquipmentLifetime.cartLeaseLifetime(player) == null,
                    "Failed parse actor revived",
                )
            else {
                val after = life(player)
                check(!before.equals(after), "Parsed release roundtrip lost lifetime transition")
                check(
                    !EquipmentLifetime.cartLeaseResnapshot(player, before) &&
                        !EquipmentLifetime.cartLeaseResnapshot(player, after),
                    "Generic restoration or unchanged token certified",
                )
            }
        }
        zombie.network.GameClient.client = false
        zombie.network.GameServer.server = true
    }

    private fun jsonField(json: String?, key: String?, value: Any?) {
        val encoded = if (value is String) "\"" + value + "\"" else java.lang.String.valueOf(value)
        check(
            json != null &&
                json.contains(
                    "\"" +
                        key +
                        "\":" +
                        encoded +
                        (if (json.endsWith("\"" + key + "\":" + encoded + "}")) "}" else ","),
                ),
            "Diagnostic field differs: " + key + " expected=" + encoded + " json=" + json,
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun eligibilityChecks(known: Owner?, connection: Connection?, engine: Engine?) {
        val lives =
            field(EquipmentLifetime::class.java, "equipmentLives").get(null)
                as
                NativeTime.NativeWeakMap<
                    zombie.characters.IsoPlayer,
                    EquipmentLifetime.EquipmentLife,
                >
        val records =
            field(EquipmentLifetime::class.java, "equipmentLifetimeRecords").get(null)
                as java.util.ArrayList<*>
        val issued = field(EquipmentLifetime::class.java, "equipmentLifetimeIssuedCount")
        val state = lives.get(known)!!
        val count = records.size
        val issuedSize = state.issued.size
        val issuedCount = issued.getLong(null)
        val revision = state.revision
        val hard = state.hardRevision
        val json = EquipmentLifetime.cartLeaseEligibility(known)
        check(
            json != null && json.equals(EquipmentLifetime.cartLeaseEligibility(known)),
            "Repeated diagnostic snapshot changed state",
        )
        jsonField(json, "schema", 1)
        jsonField(json, "authorityProof", false)
        jsonField(json, "diagnosticOnly", true)
        jsonField(json, "actorEpoch", NativeTime.nativeTimeIdentity(known, true))
        jsonField(json, "clientMapExact", false)
        jsonField(json, "sourceRole", "server")
        jsonField(json, "engineKnown", true)
        jsonField(json, "exactActiveMapping", true)
        jsonField(json, "baseline", true)
        jsonField(json, "retired", false)
        jsonField(json, "revision", revision)
        jsonField(
            json,
            "primaryEpoch",
            NativeTime.nativeTimeIdentity(known!!.getPrimaryHandItem(), false),
        )
        jsonField(json, "sameHands", true)
        val unknown = owner(item(84), 12.toShort())
        val absent = EquipmentLifetime.cartLeaseEligibility(unknown)
        jsonField(absent, "lifePresent", false)
        jsonField(absent, "issuedCount", 0)
        jsonField(absent, "connectionEpoch", 0)
        jsonField(absent, "exactActiveMapping", null)
        check(lives.get(unknown) == null, "Diagnostic snapshot created an unknown actor lifetime")
        val missing = EquipmentLifetime.cartLeaseEligibility(null)
        jsonField(missing, "playerPresent", false)
        jsonField(missing, "lifePresent", false)
        check(
            records.size == count &&
                issued.getLong(null) == issuedCount &&
                state.issued.size == issuedSize &&
                state.revision == revision &&
                state.hardRevision == hard,
            "Read-only diagnostics changed ledger count, issued tokens or native revision",
        )
        zombie.network.GameServer.server = false
        zombie.network.GameClient.client = true
        zombie.network.GameClient.instance.connected = true
        zombie.network.GameClient.instance.udpEngine = engine
        zombie.network.GameClient.connection = connection
        val previous = IsoPlayerState.capture()
        try {
            zombie.characters.IsoPlayer.players[0] = unknown
            zombie.characters.IsoPlayer.setInstance(unknown)
            zombie.network.GameClient.IDToPlayerMap.clear()
            zombie.network.GameClient.IDToPlayerMap.put(12.toShort(), unknown)
            val local = EquipmentLifetime.cartLeaseEligibility(unknown)
            jsonField(local, "localSlotExact", true)
            jsonField(local, "currentActorExact", true)
            jsonField(local, "clientMapExact", true)
            jsonField(local, "clientMapActorEpoch", NativeTime.nativeTimeIdentity(unknown, true))
            jsonField(local, "clientConnected", true)
            jsonField(local, "sourceRole", "client")
            jsonField(local, "lifePresent", false)
            jsonField(local, "exactActiveMapping", true)
            check(
                lives.get(unknown) == null &&
                    records.size == count &&
                    issued.getLong(null) == issuedCount,
                "Local eligibility diagnostics issued a binding",
            )
            zombie.network.GameClient.IDToPlayerMap.put(12.toShort(), known)
            val wrong = EquipmentLifetime.cartLeaseEligibility(unknown)
            jsonField(wrong, "clientMapExact", false)
            jsonField(wrong, "clientMapActorEpoch", NativeTime.nativeTimeIdentity(known, true))
            unknown.removedFromWorldMs = 123
            jsonField(EquipmentLifetime.cartLeaseEligibility(unknown), "removedFromWorldMs", 123)
            unknown.removedFromWorldMs = 0
            connections(engine)!!.remove(1L)
            jsonField(EquipmentLifetime.cartLeaseEligibility(unknown), "exactActiveMapping", false)
            connections(engine)!!.put(1L, connection)
            zombie.network.GameClient.instance.udpEngine = null
            jsonField(EquipmentLifetime.cartLeaseEligibility(unknown), "engineKnown", false)
            jsonField(EquipmentLifetime.cartLeaseEligibility(unknown), "exactActiveMapping", null)
            zombie.network.GameClient.instance.udpEngine = engine
        } finally {
            previous.restore()
            zombie.network.GameClient.IDToPlayerMap.clear()
            zombie.network.GameClient.client = false
            zombie.network.GameServer.server = true
        }
        EquipmentLifetime.equipmentLifetimeRetire(unknown, "actor-remove")
        val retired = lives.get(unknown)!!
        val retiredRevision = retired.revision
        jsonField(EquipmentLifetime.cartLeaseEligibility(unknown), "retired", true)
        check(
            retired.revision == retiredRevision &&
                retired.issued.isEmpty() &&
                issued.getLong(null) == issuedCount,
            "Diagnostic snapshot revived or issued retired actor",
        )
        System.out.println(
            "EQUIPMENT_ELIGIBILITY_CHECK_PASS noNewLife=true noTokenIssuance=true revisionsUnchanged=true unknownActor=true localMapAndSlot=true retiredPreserved=true",
        )
    }

    private data class IsoPlayerState(
        val current: zombie.characters.IsoPlayer?,
        val slot: zombie.characters.IsoPlayer?,
    ) {
        fun restore() {
            zombie.characters.IsoPlayer.players[0] = slot
            zombie.characters.IsoPlayer.setInstance(current)
        }

        companion object {
            fun capture(): IsoPlayerState {
                return IsoPlayerState(
                    zombie.characters.IsoPlayer.getInstance(),
                    zombie.characters.IsoPlayer.players[0],
                )
            }
        }
    }

    class BirthOwner : Owner() {
        var fixtureInventory: zombie.inventory.ItemContainer? = null

        override fun getInventory() = fixtureInventory

        override fun isLocalPlayer(): Boolean = true

        override fun getEmitter(): zombie.characters.BaseCharacterSoundEmitter? =
            zombie.characters.DummyCharacterSoundEmitter(this)

        override fun isAsleep(): Boolean = false

        override fun updateLightInfo() {}

        override fun setCurrentSquareFromPosition() {}

        override fun updateUsername() {}

        override fun setSceneCulled(value: Boolean) {}
    }

    @Suppress("UNCHECKED_CAST")
    private fun birthChecks(engine: Engine?, connection: Connection?) {
        val lives =
            field(EquipmentLifetime::class.java, "equipmentLives").get(null)
                as
                NativeTime.NativeWeakMap<
                    zombie.characters.IsoPlayer,
                    EquipmentLifetime.EquipmentLife,
                >
        val world = unsafe.allocateInstance(zombie.iso.IsoWorld::class.java) as zombie.iso.IsoWorld
        val cell = unsafe.allocateInstance(zombie.iso.IsoCell::class.java) as zombie.iso.IsoCell
        field(zombie.iso.IsoCell::class.java, "objectList")
            .set(cell, java.util.HashSet<zombie.iso.IsoMovingObject?>())
        field(zombie.iso.IsoCell::class.java, "addList")
            .set(cell, java.util.HashSet<zombie.iso.IsoMovingObject?>())
        field(zombie.iso.IsoCell::class.java, "processItems")
            .set(cell, java.util.ArrayList<zombie.inventory.InventoryItem?>())
        world.currentCell = cell
        world.addCoopPlayers = java.util.ArrayList()
        val previousWorld = zombie.iso.IsoWorld.instance
        val previousSound = zombie.SoundManager.instance
        val previousInstance = zombie.characters.IsoPlayer.getInstance()
        val previousSlot = zombie.characters.IsoPlayer.players[0]
        zombie.iso.IsoWorld.instance = world
        zombie.SoundManager.instance = zombie.DummySoundManager()
        zombie.network.GameServer.server = false
        zombie.network.GameClient.client = true
        zombie.network.GameClient.instance.udpEngine = engine
        zombie.network.GameClient.instance.connected = true
        zombie.network.GameClient.connection = connection
        connections(engine)!!.put(1L, connection)
        zombie.network.GameClient.IDToPlayerMap.clear()
        try {
            for (scenario in
                arrayOf<String>(
                    "preview-removed",
                    "forged-event",
                    "registered-removed",
                    "death",
                    "dead",
                    "after-birth-remove",
                    "wrong-engine",
                    "wrong-slot",
                )) {
                val player = unsafe.allocateInstance(BirthOwner::class.java) as BirthOwner
                player.onlineId = 7
                player.playerIndex = 0
                player.setHealth(100f)
                player.fixtureInventory =
                    unsafe.allocateInstance(zombie.inventory.ItemContainer::class.java)
                        as zombie.inventory.ItemContainer
                player.fixtureInventory!!.items = java.util.ArrayList()
                val cart = item(42)
                field(zombie.characters.IsoGameCharacter::class.java, "leftHandItem")
                    .set(player, cart)
                field(zombie.characters.IsoGameCharacter::class.java, "rightHandItem")
                    .set(player, cart)
                zombie.characters.IsoPlayer.players[0] = null
                zombie.characters.IsoPlayer.setInstance(player)
                zombie.network.GameClient.IDToPlayerMap.clear()
                if (scenario.equals("registered-removed"))
                    zombie.network.GameClient.IDToPlayerMap.put(7.toShort(), player)
                if (scenario.equals("preview-removed")) {
                    try {
                        player.removeFromWorld()
                    } catch (expected: Throwable) {}

                    check(
                        player.removedFromWorldMs > 0,
                        "Actual native preview removal did not write its historical timestamp",
                    )
                    field(zombie.characters.IsoGameCharacter::class.java, "leftHandItem")
                        .set(player, cart)
                    field(zombie.characters.IsoGameCharacter::class.java, "rightHandItem")
                        .set(player, cart)
                } else {
                    EquipmentLifetime.equipmentLifetimeRetire(
                        player,
                        if (scenario.equals("death")) "actor-death" else "actor-remove",
                    )
                    player.removedFromWorldMs = 123
                }
                val original = lives.get(player)!!
                val oldEpoch = original.actorEpoch
                check(
                    EquipmentLifetime.cartLeaseLifetime(player) == null,
                    "Prebirth removed actor admitted",
                )
                val task = zombie.util.AddCoopPlayer(player, false)
                world.addCoopPlayers.add(task)
                field(zombie.util.AddCoopPlayer::class.java, "stage")
                    .set(task, zombie.util.AddCoopPlayer.Stage.AddToWorld)
                if (scenario.equals("forged-event")) {
                    check(
                        EquipmentLifetime.equipmentLifetimeCoopEnter(task) == null,
                        "Direct call forged native birth scope",
                    )
                    zombie.characters.IsoPlayer.players[0] = player
                    zombie.Lua.LuaEventManager.triggerEvent(
                        "OnCreatePlayer",
                        Integer.valueOf(0),
                        player,
                    )
                    EquipmentLifetime.equipmentLifetimeCoopEvent(
                        "OnCreatePlayer",
                        Integer.valueOf(0),
                        player,
                    )
                } else {
                    if (scenario.equals("wrong-engine"))
                        zombie.network.GameClient.instance.udpEngine = null
                    if (scenario.equals("wrong-slot")) player.playerIndex = 1
                    if (scenario.equals("dead")) player.setHealth(0f)
                    task.update()
                    if (scenario.equals("after-birth-remove"))
                        EquipmentLifetime.equipmentLifetimeRetire(player, "actor-remove")
                    zombie.network.GameClient.instance.udpEngine = engine
                    player.playerIndex = 0
                }
                if (scenario.equals("preview-removed")) {
                    check(
                        lives.get(player) === original && original.retired,
                        "Native event prematurely replaced pre-registration tombstone",
                    )
                    player.setOnlineID(8.toShort())
                    player.setOnlineID(7.toShort())
                    zombie.network.GameClient.IDToPlayerMap.put(7.toShort(), player)
                    // Actual native hand setters before promotion must remain invisible, including
                    // OnEquip reentrant reads.
                    player.setPrimaryHandItem(null)
                    player.setSecondaryHandItem(null)
                    player.setPrimaryHandItem(cart)
                    player.setSecondaryHandItem(cart)
                    zombie.network.GameClient.IDToPlayerMap.clear()
                    check(
                        lives.get(player) === original &&
                            original.revision == 1L &&
                            original.issued.isEmpty(),
                        "Final native online-ID update changed prebaseline logical lifetime",
                    )
                    check(
                        EquipmentLifetime.cartLeaseLifetime(player) == null,
                        "Birth witness bypassed missing authoritative client map",
                    )
                    zombie.network.GameClient.IDToPlayerMap.put(7.toShort(), player)
                    val token = life(player)
                    val fresh = lives.get(player)!!
                    check(
                        fresh !== original &&
                            fresh.actorEpoch != oldEpoch &&
                            fresh.born &&
                            !fresh.retired &&
                            original.retired &&
                            original.issued.isEmpty(),
                        "Native birth did not preserve old tombstone and create distinct unissued life",
                    )
                    check(
                        NativeTime.nativeTimeIdentity(player, true) == oldEpoch,
                        "Equipment birth rotated shared object identity",
                    )
                    check(
                        fresh.revision == 1L && token.endsWith("|1"),
                        "Fresh baseline did not start at revision one after final online-ID update",
                    )
                    check(
                        token.contains("|" + fresh.actorEpoch + "|") &&
                            !token.contains("|" + oldEpoch + "|"),
                        "Birth reused retired logical epoch",
                    )
                    check(
                        !EquipmentLifetime.cartLeaseResnapshot(
                            player,
                            "1|" +
                                LeaseControl.cartLeaseSeed() +
                                "|" +
                                oldEpoch +
                                "|" +
                                NativeTime.nativeTimeIdentity(connection, false) +
                                "|1",
                        ),
                        "Prebirth namespace entered fresh lifetime",
                    )
                    task.update()
                    check(
                        lives.get(player) === fresh && token.equals(life(player)),
                        "Repeated completed task rotated fresh incarnation",
                    )
                    zombie.network.GameClient.IDToPlayerMap.remove(7.toShort())
                    check(
                        EquipmentLifetime.cartLeaseLifetime(player) == null,
                        "Native birth bypassed remote/client map fence",
                    )
                    zombie.network.GameClient.IDToPlayerMap.put(7.toShort(), player)
                    EquipmentLifetime.equipmentLifetimeRetire(player, "actor-remove")
                    check(
                        EquipmentLifetime.cartLeaseLifetime(player) == null,
                        "Postbirth removal revived",
                    )
                    field(zombie.util.AddCoopPlayer::class.java, "stage")
                        .set(task, zombie.util.AddCoopPlayer.Stage.AddToWorld)
                    task.update()
                    check(
                        lives.get(player) === fresh &&
                            fresh.retired &&
                            EquipmentLifetime.cartLeaseLifetime(player) == null,
                        "Repeated native birth healed issued/retired incarnation",
                    )
                } else
                    check(
                        lives.get(player) === original &&
                            original.retired &&
                            EquipmentLifetime.cartLeaseLifetime(player) == null,
                        "Invalid birth admitted " + scenario,
                    )
                world.addCoopPlayers.remove(task)
                zombie.network.GameClient.IDToPlayerMap.clear()
            }
        } finally {
            zombie.iso.IsoWorld.instance = previousWorld
            zombie.SoundManager.instance = previousSound
            zombie.characters.IsoPlayer.players[0] = previousSlot
            zombie.characters.IsoPlayer.setInstance(previousInstance)
            zombie.network.GameClient.client = false
            zombie.network.GameServer.server = true
        }
        System.out.println(
            "EQUIPMENT_NATIVE_COOP_BIRTH_CHECK_PASS originalEvent=true nativePreviewRemoval=true prebirthOnly=true immutableEpoch=true oldTombstonePreserved=true forgedRepeatedRegisteredDeathWrongSlotEngineDenied=true mapGuardUnchanged=true",
        )
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        zombie.Lua.LuaManager.env = se.krka.kahlua.j2se.J2SEPlatform.getInstance().newEnvironment()
        zombie.Lua.LuaManager.env.rawset(
            "Events",
            se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable(),
        )
        zombie.GameWindow.gameThread = Thread.currentThread()
        val platform = se.krka.kahlua.j2se.J2SEPlatform.getInstance()
        zombie.Lua.LuaManager.thread =
            se.krka.kahlua.vm.KahluaThread(platform, zombie.Lua.LuaManager.env)
        zombie.Lua.LuaManager.thread.debugOwnerThread = Thread.currentThread()
        zombie.Lua.LuaManager.caller =
            se.krka.kahlua.integration.LuaCaller(se.krka.kahlua.converter.KahluaConverterManager())
        zombie.Lua.LuaManager.env.rawset(
            "assertBlocked",
            se.krka.kahlua.vm.JavaFunction { frame, count ->
                val actor = frame!!.get(0)
                eventCallbacks++
                if (!(actor is Owner) || EquipmentLifetime.cartLeaseLifetime(actor) != null)
                    eventFailure = "Native OnEquip callback exposed intermediate lifetime"
                0
            },
        )
        val callback =
            se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(
                "assertBlocked(...)",
                "native-equipment-event",
                zombie.Lua.LuaManager.env,
            )
        zombie.Lua.LuaEventManager.AddEvent("OnEquipPrimary").callbacks.add(callback)
        zombie.Lua.LuaEventManager.AddEvent("OnEquipSecondary").callbacks.add(callback)
        zombie.Lua.LuaManager.env.rawset(
            "assertDeathRetired",
            se.krka.kahlua.vm.JavaFunction { frame, count ->
                val actor = frame!!.get(0)
                deathCallbacks++
                try {
                    if (actor !== deathExpected || !(actor is Owner))
                        deathFailure = "Wrong native death actor"
                    else {
                        val lives =
                            field(EquipmentLifetime::class.java, "equipmentLives").get(null)
                                as
                                NativeTime.NativeWeakMap<
                                    zombie.characters.IsoPlayer,
                                    EquipmentLifetime.EquipmentLife,
                                >
                        val state = lives.get(actor)
                        if (
                            state == null ||
                                !state.retired ||
                                EquipmentLifetime.cartLeaseLifetime(actor) != null ||
                                EquipmentLifetime.cartLeaseResnapshot(actor, deathToken)
                        )
                            deathFailure =
                                "Superclass OnCharacterDeath callback preceded retirement"
                        else if (
                            actor.getPrimaryHandItem() !== deathItem ||
                                actor.getSecondaryHandItem() !== deathItem ||
                                actor.removedFromWorldMs != 0L
                        )
                            deathFailure =
                                "Native death callback did not precede hand release/removal"
                    }
                } catch (error: Throwable) {
                    deathFailure = error.toString()
                }

                0
            },
        )
        val deathCallback =
            se.krka.kahlua.luaj.compiler.LuaCompiler.loadstring(
                "assertDeathRetired(...)",
                "native-equipment-death-event",
                zombie.Lua.LuaManager.env,
            )
        zombie.Lua.LuaEventManager.AddEvent("OnCharacterDeath").callbacks.add(deathCallback)
        val access = field(sun.misc.Unsafe::class.java, "theUnsafe")
        unsafe = access.get(null) as sun.misc.Unsafe
        val engine = unsafe.allocateInstance(Engine::class.java) as Engine
        field(zombie.core.raknet.UdpEngine::class.java, "connectionMap")
            .set(engine, HashMap<Long?, zombie.core.raknet.UdpConnection?>())
        val connection = unsafe.allocateInstance(Connection::class.java) as Connection
        zombie.network.GameServer.server = true
        zombie.network.GameClient.client = false
        zombie.network.GameServer.udpEngine = engine
        val original = item(42)
        val owner = owner(original, 7.toShort())
        registered(owner, connection, engine)
        val first = life(owner)
        check(first.equals(life(owner)), "Read-only sampling changed native lifetime")
        birthChecks(engine, connection)
        eligibilityChecks(owner, connection, engine)
        check(
            !EquipmentLifetime.cartLeaseResnapshot(owner, first) &&
                !EquipmentLifetime.cartLeaseResnapshot(owner, "invalid"),
            "Unchanged or malformed native token certified",
        )
        owner.setPrimaryHandItem(original)
        owner.setSecondaryHandItem(original)
        check(first.equals(life(owner)), "Native same-reference setter no-op invalidated lifetime")
        owner.setPrimaryHandItem(null)
        check(
            EquipmentLifetime.cartLeaseLifetime(owner) == null,
            "Released primary retained held lifetime",
        )
        owner.setSecondaryHandItem(null)
        owner.setPrimaryHandItem(original)
        owner.setSecondaryHandItem(original)
        val reacquired = life(owner)
        check(!reacquired.equals(first), "Complete release/reacquire between polls reused lifetime")
        val replacement = item(42)
        check(
            replacement !== original && replacement.getID() == original.getID(),
            "Same-ID fixture invalid",
        )
        owner.nested = true
        owner.nestedItem = replacement
        owner.setPrimaryHandItem(replacement)
        val replaced = life(owner)
        check(!replaced.equals(reacquired), "Same numeric ID replacement reused old lifetime")
        check(
            owner.getPrimaryHandItem() === replacement &&
                owner.getSecondaryHandItem() === replacement &&
                owner.blockedCallbacks >= 6,
            "Actual native hand setter effects/callback nesting not exercised",
        )
        replacement.setID(43)
        replacement.setID(42)
        val idCycle = life(owner)
        check(!idCycle.equals(replaced), "Same-object numeric ID roundtrip invisible")
        val world =
            unsafe.allocateInstance(zombie.iso.objects.IsoWorldInventoryObject::class.java)
                as zombie.iso.objects.IsoWorldInventoryObject
        replacement.setWorldItem(world)
        check(
            EquipmentLifetime.cartLeaseLifetime(owner) == null,
            "World-bound item admitted as held",
        )
        replacement.setWorldItem(null)
        check(!life(owner).equals(idCycle), "World-item roundtrip reused lifetime")
        val oldID = owner.getOnlineID()
        owner.setOnlineID(8.toShort())
        owner.setOnlineID(oldID)
        val onlineCycle = life(owner)
        check(!onlineCycle.equals(idCycle), "Actor online ID roundtrip invisible")
        owner.throwAfter = true
        try {
            owner.setSecondaryHandItem(original)
            throw AssertionError("Expected native callback throw")
        } catch (expected: IllegalStateException) {}

        owner.throwAfter = false
        owner.setSecondaryHandItem(replacement)
        check(
            EquipmentLifetime.cartLeaseLifetime(owner) == null,
            "Throwing setter revived poisoned actor",
        )
        // A fresh exact actor with the same online ID can establish a new lifetime; old record
        // remains poisoned.
        val next = owner(original, 7.toShort())
        registered(next, connection, engine)
        check(!life(next).equals(first), "Same-ID actor replacement collapsed identity")
        try {
            next.load(java.nio.ByteBuffer.allocate(0), 249, false)
        } catch (expected: Throwable) {}

        check(
            EquipmentLifetime.cartLeaseLifetime(next) == null,
            "Failed actual native load did not poison lifetime",
        )
        val itemLoaded = item(42)
        val itemOwner = owner(itemLoaded, 7.toShort())
        registered(itemOwner, connection, engine)
        life(itemOwner)
        try {
            val bytes = java.nio.ByteBuffer.allocate(4).putInt(43)
            bytes.flip()
            itemLoaded.load(bytes, 249)
        } catch (expected: Throwable) {}

        check(
            itemLoaded.getID() == 43 && EquipmentLifetime.cartLeaseLifetime(itemOwner) == null,
            "Actual item.load ID write/failure escaped lifetime fence",
        )
        deathChecks(engine, connection)
        val removed = owner(original, 7.toShort())
        registered(removed, connection, engine)
        life(removed)
        try {
            removed.removeFromWorld()
        } catch (expected: Throwable) {}

        check(
            EquipmentLifetime.cartLeaseLifetime(removed) == null,
            "Actual removal entry did not permanently retire actor",
        )
        val disconnected = owner(original, 7.toShort())
        registered(disconnected, connection, engine)
        life(disconnected)
        // Neutral role avoids native cleanup infrastructure after the engine removes its actual map
        // entry.
        zombie.network.GameServer.server = false
        engine.removeConnection(1L)
        zombie.network.GameServer.server = true
        check(!connections(engine)!!.containsKey(1L), "Actual engine map removal not exercised")
        connections(engine)!!.put(1L, connection)
        check(
            EquipmentLifetime.cartLeaseLifetime(disconnected) == null,
            "Reinserting identical connection revived retired record",
        )
        val lateActor = owner(original, 7.toShort())
        registered(lateActor, connection, engine)
        check(
            EquipmentLifetime.cartLeaseLifetime(lateActor) == null,
            "An unadmitted actor revived an already removed exact transport",
        )
        val reconnected = owner(original, 7.toShort())
        val connection2 = unsafe.allocateInstance(Connection::class.java) as Connection
        registered(reconnected, connection2, engine)
        check(!life(reconnected).equals(first), "New connection/actor incarnation reused lifetime")
        zombie.network.GameServer.IDToPlayerMap.remove(7.toShort())
        check(
            EquipmentLifetime.cartLeaseLifetime(reconnected) == null,
            "Unregistered actor admitted",
        )
        zombie.network.GameServer.IDToPlayerMap.put(7.toShort(), reconnected)
        life(reconnected)
        val lives =
            field(EquipmentLifetime::class.java, "equipmentLives").get(null)
                as
                NativeTime.NativeWeakMap<
                    zombie.characters.IsoPlayer,
                    EquipmentLifetime.EquipmentLife,
                >
        lives.get(reconnected)!!.revision = 9007199254740991L
        reconnected.setSecondaryHandItem(null)
        check(
            EquipmentLifetime.cartLeaseLifetime(reconnected) == null,
            "Exact Lua integer exhaustion did not poison record",
        )
        check(
            EquipmentLifetime.cartLeaseLifetime(owner) == null,
            "Historical owner unexpectedly revived",
        )
        val parseConnection = unsafe.allocateInstance(Connection::class.java) as Connection
        connections(engine)!!.put(1L, parseConnection)
        parseChecks(engine, parseConnection)
        check(
            eventCallbacks >= 8 && eventFailure == null,
            "Actual Lua OnEquip callbacks missing or exposed intermediate binding: " + eventFailure,
        )
        System.out.println("EQUIPMENT_LIFETIME_CHECK_PASS")
    }
}
