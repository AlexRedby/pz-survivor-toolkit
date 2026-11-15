package net.alexredby.queueengineprobechecks;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgementLogic;
import net.alexredby.pztoolkitjavapatches.ActionAcknowledgements;
import net.alexredby.queueengineprobe.Main;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.ActionManager;
import zombie.core.NetTimedAction;
import zombie.core.Transaction.TransactionState;
import zombie.Lua.LuaManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaThread;
import se.krka.kahlua.integration.LuaCaller;
import se.krka.kahlua.converter.KahluaConverterManager;
import zombie.network.fields.character.ConnectionPlayer;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.server.EventManager;

/** Native manager/receipt identities are real; player construction and repair bodies are isolated. */
public final class EnginePeerProbeChecks {
    private static final byte ID = -126;
    private static final Unsafe UNSAFE;
    static {
        try { UNSAFE = (Unsafe)field(Unsafe.class, "theUnsafe").get(null); }
        catch (ReflectiveOperationException error) { throw new ExceptionInInitializerError(error); }
    }

    public static final class Player extends IsoPlayer {
        public Player() { super(null); }
        @Override public String getUsername() { return onlineId == 19 ? "client1" : "client2"; }
    }

    public static final class Repair extends NetTimedAction {
        int stopped;
    }

    private static final Class<?> ACTION;
    static {
        try { ACTION = Class.forName("zombie.core.Action"); }
        catch (ClassNotFoundException error) { throw new ExceptionInInitializerError(error); }
    }

    private static ConnectionPlayer owner(Repair action) {
        return Accessor.tryGet(action, "player", (ConnectionPlayer)null);
    }

    private static TransactionState state(Repair action) {
        return Accessor.tryGet(action, "state", (TransactionState)null);
    }

    private static void state(Repair action, TransactionState state) throws ReflectiveOperationException {
        field(ACTION, "state").set(action, state);
    }

    private static Field field(Class<?> owner, String name) throws ReflectiveOperationException {
        Field field = owner.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    private static void require(boolean condition, String detail) {
        if (!condition) throw new AssertionError(detail);
    }

    private static Repair repair(short id) throws ReflectiveOperationException {
        Player player = (Player)UNSAFE.allocateInstance(Player.class);
        player.onlineId = id;
        Repair action = new Repair();
        field(ACTION, "id").setByte(action, ID);
        state(action, TransactionState.Accept);
        action.type = "ISFixGenerator";
        owner(action).set(player);
        // Observation follows the actor's online ID; wire/local-index metadata cannot select a peer.
        owner(action).setId((short)0);
        action.action = LuaManager.platform.newTable();
        action.action.rawset("serverStop", (JavaFunction)(frame, arguments) -> {
            require(arguments == 1 && frame.get(0) == action.action, "native stop callback lost its exact Lua owner");
            action.stopped++;
            return 0;
        });
        return action;
    }

    private static String output(Runnable task) {
        PrintStream previous = System.out;
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (PrintStream capture = new PrintStream(bytes, true, StandardCharsets.UTF_8)) {
            System.setOut(capture);
            task.run();
        } finally { System.setOut(previous); }
        return bytes.toString(StandardCharsets.UTF_8);
    }

    private static void replace(Field field, Object value) {
        UNSAFE.putObjectVolatile(UNSAFE.staticFieldBase(field), UNSAFE.staticFieldOffset(field), value);
    }

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        GameClient.client = false;
        GameServer.server = true;
        LuaManager.platform = new J2SEPlatform();
        LuaManager.env = LuaManager.platform.newEnvironment();
        LuaManager.thread = new KahluaThread(LuaManager.platform, LuaManager.env);
        LuaManager.thread.debugOwnerThread = Thread.currentThread();
        LuaManager.caller = new LuaCaller(new KahluaConverterManager());
        ConcurrentLinkedQueue<Object> actions = Accessor.tryGet(ActionManager.class, "actions", (ConcurrentLinkedQueue<Object>)null);
        Map<Object, String> tokens = (Map<Object, String>)field(ActionAcknowledgementLogic.class, "tokens").get(null);
        require(actions != null && tokens != null && actions.isEmpty() && tokens.isEmpty(), "native probe stores not initially empty");
        require(output(() -> Main.main(new String[0])).contains("[ENGINE_TEST] PROBE active=true"), "supported probe did not validate startup stores");
        String rejection = "The packet ExtraInfo is not consistent: Player id=4";
        String nativeReport = output(() -> EventManager.instance().report(rejection));
        String receipt = "[ENGINE_TEST] NATIVE_PACKET_REJECTION " + rejection;
        require(nativeReport.strip().equals(receipt), "native EventManager rejection lost exact packet evidence");
        require(output(() -> {
            EventManager.instance().report("unrelated native event");
            EventManager.instance().report(null);
        }).isEmpty(), "packet observer changed unrelated event output");
        output(() -> Main.main(new String[0]));
        require(output(() -> EventManager.instance().report(rejection)).strip().equals(receipt),
            "repeated initialization duplicated native rejection receipts");
        require(actions.isEmpty() && tokens.isEmpty(), "packet observation mutated native queue stores");
        Repair first = repair((short)19);
        Repair second = repair((short)20);
        actions.add(first);
        actions.add(second);
        ActionAcknowledgements.started(first);
        ActionAcknowledgements.started(second);
        String firstToken = tokens.get(first), secondToken = tokens.get(second);
        require(firstToken != null && secondToken != null && !firstToken.equals(secondToken), "real acknowledgement tokens were not distinct");
        Main.Overlap overlap = Main.before(owner(first).getPlayer(), ID);
        require(overlap != null && overlap.other() == second && overlap.id() == ID
            && overlap.first() == 19 && overlap.second() == 20
            && firstToken.equals(overlap.firstToken()) && secondToken.equals(overlap.secondToken()),
            "probe did not correlate two exact accepted same-byte native owners/tokens");
        require(actions.size() == 2 && state(first) == TransactionState.Accept && state(second) == TransactionState.Accept,
            "read-only before probe changed native pending actions");
        ActionManager.remove(owner(first).getPlayer(), ID);
        require(!actions.contains(first) && actions.contains(second) && first.stopped == 1 && second.stopped == 0,
            "native manager cancellation did not isolate the exact owner");
        String expected = "[ENGINE_TEST] CANCEL_OVERLAP transaction=" + ID + " firstPlayer=19 secondPlayer=20 firstToken="
            + firstToken + " secondToken=" + secondToken + " otherPending=true";
        require(output(() -> Main.after(overlap)).contains(expected), "after probe did not prove identical foreign native action survives");
        require(actions.contains(second) && state(second) == TransactionState.Accept, "read-only after probe changed foreign action");
        actions.add(first);
        tokens.remove(second);
        require(output(() -> require(Main.before(owner(first).getPlayer(), ID) == null, "missing foreign token produced overlap"))
            .contains("[QUEUE_TEST] FAIL engine cancel lacked simultaneous pending same-ID peer"), "missing token failed silently");
        tokens.put(second, secondToken);
        state(second, TransactionState.Done);
        require(output(() -> require(Main.before(owner(first).getPlayer(), ID) == null, "completed foreign action produced overlap"))
            .contains("[QUEUE_TEST] FAIL engine cancel lacked simultaneous pending same-ID peer"), "completed peer failed silently");
        state(second, TransactionState.Accept);
        for (Field store : new Field[]{field(ActionAcknowledgementLogic.class, "tokens"), field(ActionManager.class, "actions")}) {
            Object original = store.get(null);
            try {
                replace(store, null);
                String startup = output(() -> {
                    try { Main.main(new String[0]); throw new AssertionError("missing store passed startup"); }
                    catch (IllegalStateException expectedFailure) { }
                });
                require(startup.contains("[QUEUE_TEST] FAIL engine peer probe") && !startup.contains("PROBE active=true"), "unavailable startup store failed silently");
                String boundary = output(() -> require(Main.before(owner(first).getPlayer(), ID) == null, "missing store produced overlap"));
                require(boundary.contains("[QUEUE_TEST] FAIL engine peer probe"), "unavailable cancellation store failed silently");
            } finally { replace(store, original); }
        }
        actions.clear();
        tokens.clear();
        System.out.println("ENGINE_PEER_PROBE_CHECKS_PASS");
    }
}
