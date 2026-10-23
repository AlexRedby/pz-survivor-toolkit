import java.nio.ByteBuffer
import java.util.LinkedHashMap
import net.alexredby.cartlab.NativeTime.NativeWeakMap
import net.alexredby.cartlab.ObserverAssociation
import net.alexredby.cartlab.ObserverAssociation.ObserverPacket
import net.alexredby.cartlab.ObserverAssociation.ObserverProxy
import net.alexredby.cartlab.ObserverAssociation.ObserverTag
import zombie.ai.State
import zombie.ai.states.PlayerActionsState
import zombie.characters.CharacterTimedActions.BaseAction
import zombie.characters.IsoGameCharacter
import zombie.characters.IsoPlayer
import zombie.characters.NetworkPlayerAI
import zombie.network.PZNetKahluaTableImpl
import zombie.network.packets.actions.StatePacket

/** Pinned native State.loadFrom/params check without a world, socket or game lifecycle. */
object ObserverAssociationCheck {
    class Owner : IsoPlayer(null, null, 0, 0, 0) {
        lateinit var values: MutableMap<State.Param<*>, Any?>
        var ai: Network? = null

        override fun getStateMachineParams(type: Class<*>): MutableMap<State.Param<*>, Any?> =
            values

        override fun getNetworkCharacterAI(): NetworkPlayerAI? = ai

        override fun isLocalPlayer() = false

        override fun getOnlineID(): Short = 7

        override fun getUsername() = "client2"
    }

    class Network(owner: Owner) : NetworkPlayerAI(owner) {
        lateinit var owner: Owner
        var current: BaseAction? = null

        override fun getCharacter(): IsoGameCharacter = owner

        override fun getAction(): BaseAction? = current
    }

    private fun ensure(value: Boolean, message: String) {
        if (!value) throw AssertionError(message)
    }

    @Suppress("UNCHECKED_CAST")
    private fun clearedProxyCheck(
        unsafe: sun.misc.Unsafe,
        owner: Owner,
        packet: StatePacket,
        tag: ObserverTag,
    ) {
        val ai = (unsafe.allocateInstance(Network::class.java) as Network).also { it.owner = owner }
        owner.ai = ai
        val action = unsafe.allocateInstance(BaseAction::class.java) as BaseAction
        val input =
            ObserverPacket(packet, owner, tag).also {
                it.applied = true
                it.processed = true
            }
        val proxy = ObserverProxy(action, owner, input, 1L)
        proxy.proxy.clear()
        ensure(
            proxy.proxy.get() == null && ai.action == null,
            "Cleared-action fixture still has a live pointer",
        )
        val field =
            ObserverAssociation::class.java.getDeclaredField("observerActors").apply {
                isAccessible = true
            }
        val actors = field.get(null) as NativeWeakMap<IsoPlayer, ObserverProxy>
        val previous = actors.get(owner)
        actors.put(owner, proxy)
        try {
            var snapshot = ObserverAssociation.observerAssociationSnapshot(owner)
            ensure(
                snapshot.contains("\"observerProxyEpoch\":${proxy.epoch},"),
                "Cleared-action fixture did not reach diagnostic snapshot",
            )
            ensure(
                snapshot.contains("\"observerProxyState\":\"active\"") &&
                    snapshot.contains("\"observerProxyCurrent\":false") &&
                    snapshot.contains("\"observerAssociationValid\":false"),
                "Two null pointers revived a historical proxy",
            )
            ObserverAssociation.observerAction(ai, null, null)
            ensure(proxy.state == "replaced", "Null assignment did not retire a cleared weak proxy")
            ai.current = action
            ObserverAssociation.observerAction(ai, action, null)
            snapshot = ObserverAssociation.observerAssociationSnapshot(owner)
            ensure(
                proxy.state == "replaced" &&
                    snapshot.contains("\"observerProxyState\":\"replaced\"") &&
                    snapshot.contains("\"observerProxyCurrent\":false") &&
                    snapshot.contains("\"observerAssociationValid\":false"),
                "Later pointer reuse resurrected the retired association",
            )
        } finally {
            if (previous == null) actors.remove(owner) else actors.put(owner, previous)
        }
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        for (name in
            arrayOf(
                "zombie.characters.IsoGameCharacter",
                "zombie.network.GameClient",
                "zombie.network.GameServer",
                "zombie.network.packets.actions.StatePacket",
                "zombie.ai.states.PlayerActionsState",
                "zombie.characters.NetworkState",
                "zombie.characters.NetworkCharacterAI",
                "zombie.characters.CharacterTimedActions.LuaTimedActionNew",
            )) Class.forName(name, false, ObserverAssociationCheck::class.java.classLoader)
        val life = "1|01234567-89ab-cdef-0123-456789abcdef|1|2|3|4|5"
        val text = "$life|6"
        val tag = checkNotNull(ObserverAssociation.observerAssociationTag(text))
        ensure(
            tag.life == life &&
                tag.text == text &&
                tag.actor == 1L &&
                tag.connection == 2L &&
                tag.action == 3L &&
                tag.table == 4L &&
                tag.begin == 5L &&
                tag.state == 6L,
            "Exact marker identity changed",
        )
        ensure(
            ObserverAssociation.observerAssociationTag("$life|7")!!.state != tag.state,
            "Repeated state generation collapsed",
        )
        for (invalid in
            arrayOf(
                "$text|8",
                text.replace("|6", "|0"),
                text.replace("|6", "|-1"),
                text.replace("|6", "|1.0"),
                text.replace("|6", "|01"),
                text.replace("|6", "|9007199254740992"),
                "invalid",
            )) ensure(
            ObserverAssociation.observerAssociationTag(invalid) == null,
            "Malformed diagnostic marker accepted: $invalid",
        )
        val unsafe =
            sun.misc.Unsafe::class
                .java
                .getDeclaredField("theUnsafe")
                .apply { isAccessible = true }
                .get(null) as sun.misc.Unsafe
        val owner =
            (unsafe.allocateInstance(Owner::class.java) as Owner).also {
                it.values = LinkedHashMap()
            }
        val state = PlayerActionsState.instance()
        owner.values[PlayerActionsState.STAGE] = State.Stage.Exit
        val incoming = linkedMapOf<Any, Any>(ObserverAssociation.OBSERVER_MARKER to text)
        state.loadFrom(incoming, owner)
        ensure(
            owner.values.size == 1 && owner.values[PlayerActionsState.STAGE] === State.Stage.Exit,
            "Unknown top-level params changed native state",
        )
        incoming[PlayerActionsState.STAGE.name] = State.Stage.Enter
        state.loadFrom(incoming, owner)
        ensure(
            owner.values.size == 1 && owner.values[PlayerActionsState.STAGE] === State.Stage.Enter,
            "Known native params stopped loading beside diagnostic tag",
        )
        val packet = StatePacket()
        val params =
            StatePacket::class
                .java
                .getDeclaredField("params")
                .apply { isAccessible = true }
                .get(packet) as PZNetKahluaTableImpl
        params.rawset(ObserverAssociation.OBSERVER_MARKER, text)
        ensure(
            params.rawget(ObserverAssociation.OBSERVER_MARKER) == text && owner.values.size == 1,
            "Packet params alias native character params",
        )
        val bytes = ByteBuffer.allocate(512)
        params.save(bytes)
        val end = bytes.position()
        bytes.flip()
        val parsed = PZNetKahluaTableImpl(LinkedHashMap<Any, Any>())
        parsed.load(zombie.core.network.ByteBufferReader(bytes), null)
        ensure(
            text == parsed.rawget(ObserverAssociation.OBSERVER_MARKER) && bytes.position() == end,
            "Native params serialization lost diagnostic marker",
        )
        ensure(
            packet.shouldInstantiate(),
            "StatePacket stopped allocating distinct receipt instances",
        )
        clearedProxyCheck(unsafe, owner, packet, tag)
        println("OBSERVER_ASSOCIATION_CHECK_PASS")
    }
}
