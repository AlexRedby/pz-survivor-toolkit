package zombie.core;

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
import zombie.core.Transaction.TransactionState;
import zombie.network.GameClient;
import zombie.network.GameServer;

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
        @Override void stop() { stopped++; }
    }

    private static Field field(Class<?> owner, String name) throws ReflectiveOperationException {
        Field field = owner.getDeclaredField(name);
        field.setAccessible(true);
        return field;
    }

    private static void require(boolean condition, String detail) {
        if (!condition) throw new AssertionError(detail);
    }

    private static Repair repair(short id) throws InstantiationException {
        Player player = (Player)UNSAFE.allocateInstance(Player.class);
        player.onlineId = id;
        Repair action = new Repair();
        action.id = ID;
        action.state = TransactionState.Accept;
        action.type = "ISFixGenerator";
        action.playerId.setID(id);
        require(Accessor.trySet(action.playerId, "player", player), "native PlayerID fixture binding failed");
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
        ConcurrentLinkedQueue<Object> actions = Accessor.tryGet(ActionManager.class, "actions", (ConcurrentLinkedQueue<Object>)null);
        Map<Object, String> tokens = (Map<Object, String>)field(ActionAcknowledgementLogic.class, "tokens").get(null);
        require(actions != null && tokens != null && actions.isEmpty() && tokens.isEmpty(), "native probe stores not initially empty");
        require(output(() -> Main.main(new String[0])).contains("[ENGINE_TEST] PROBE active=true"), "supported probe did not validate startup stores");
        Repair first = repair((short)19);
        Repair second = repair((short)20);
        actions.add(first);
        actions.add(second);
        ActionAcknowledgements.started(first);
        ActionAcknowledgements.started(second);
        String firstToken = tokens.get(first), secondToken = tokens.get(second);
        require(firstToken != null && secondToken != null && !firstToken.equals(secondToken), "real acknowledgement tokens were not distinct");
        Main.Overlap overlap = Main.before(first.playerId, ID);
        require(overlap != null && overlap.other() == second && overlap.id() == ID
            && overlap.first() == 19 && overlap.second() == 20
            && firstToken.equals(overlap.firstToken()) && secondToken.equals(overlap.secondToken()),
            "probe did not correlate two exact accepted same-byte native owners/tokens");
        require(actions.size() == 2 && first.state == TransactionState.Accept && second.state == TransactionState.Accept,
            "read-only before probe changed native pending actions");
        ActionManager.remove(first.playerId, ID, true);
        require(!actions.contains(first) && actions.contains(second) && first.stopped == 1 && second.stopped == 0,
            "native manager cancellation did not isolate the exact owner");
        String expected = "[ENGINE_TEST] CANCEL_OVERLAP transaction=" + ID + " firstPlayer=19 secondPlayer=20 firstToken="
            + firstToken + " secondToken=" + secondToken + " otherPending=true";
        require(output(() -> Main.after(overlap)).contains(expected), "after probe did not prove identical foreign native action survives");
        require(actions.contains(second) && second.state == TransactionState.Accept, "read-only after probe changed foreign action");
        actions.add(first);
        tokens.remove(second);
        require(output(() -> require(Main.before(first.playerId, ID) == null, "missing foreign token produced overlap"))
            .contains("[QUEUE_TEST] FAIL engine cancel lacked simultaneous pending same-ID peer"), "missing token failed silently");
        tokens.put(second, secondToken);
        second.state = TransactionState.Done;
        require(output(() -> require(Main.before(first.playerId, ID) == null, "completed foreign action produced overlap"))
            .contains("[QUEUE_TEST] FAIL engine cancel lacked simultaneous pending same-ID peer"), "completed peer failed silently");
        second.state = TransactionState.Accept;
        for (Field store : new Field[]{field(ActionAcknowledgementLogic.class, "tokens"), field(ActionManager.class, "actions")}) {
            Object original = store.get(null);
            try {
                replace(store, null);
                String startup = output(() -> {
                    try { Main.main(new String[0]); throw new AssertionError("missing store passed startup"); }
                    catch (IllegalStateException expectedFailure) { }
                });
                require(startup.contains("[QUEUE_TEST] FAIL engine peer probe") && !startup.contains("PROBE active=true"), "unavailable startup store failed silently");
                String boundary = output(() -> require(Main.before(first.playerId, ID) == null, "missing store produced overlap"));
                require(boundary.contains("[QUEUE_TEST] FAIL engine peer probe"), "unavailable cancellation store failed silently");
            } finally { replace(store, original); }
        }
        actions.clear();
        tokens.clear();
        System.out.println("ENGINE_PEER_PROBE_CHECKS_PASS");
    }
}
