package zombie.core;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import net.alexredby.pztoolkitjavapatches.QueueManagers;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.ItemTransactionPacket;

public final class QueueManagerChecks {
    static final byte ID = -126;
    static Unsafe unsafe;
    static ConcurrentLinkedQueue<Transaction> transactions;
    static ConcurrentLinkedQueue<Action> actions;

    public static final class Connection extends UdpConnection {
        int replies;
        ByteBuffer bytes;
        Connection() { super(null, 0, 0); }
        public ByteBufferWriter startPacket() { bytes.clear(); return new ByteBufferWriter(bytes); }
        public void endPacket(int priority, int reliability, byte channel) { replies++; }
    }

    static final class Probe extends Action {
        public String getDescription() { return "queue-manager-check"; }
        public float getDuration() { return 1; }
        public void start() { }
        public void stop() { }
        public boolean isValid() { return true; }
        public void update() { }
        public boolean perform() { return true; }
        public boolean isUsingTimeout() { return false; }
    }

    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }

    static Field field(Class<?> type, String name) throws Exception {
        Field field = type.getDeclaredField(name); field.setAccessible(true); return field;
    }

    static IsoPlayer player(short id) throws Exception {
        IsoPlayer player = (IsoPlayer)unsafe.allocateInstance(IsoPlayer.class);
        player.onlineId = id;
        return player;
    }

    static Connection connection(IsoPlayer... players) throws Exception {
        Connection connection = (Connection)unsafe.allocateInstance(Connection.class);
        connection.players = players;
        connection.bytes = ByteBuffer.allocate(1024);
        return connection;
    }

    static void owner(PlayerID target, IsoPlayer player) {
        target.setID(player.onlineId);
        require(Accessor.trySet(target, "player", player), "fixture owner");
    }

    static ItemTransactionPacket transaction(IsoPlayer player, byte id) {
        ItemTransactionPacket packet = new ItemTransactionPacket();
        packet.id = id;
        packet.state = Transaction.TransactionState.Accept;
        if (player != null) owner(packet.playerId, player);
        TransactionManager.add(packet);
        return packet;
    }

    static Probe action(IsoPlayer player, byte id, Transaction.TransactionState state) {
        Probe action = new Probe();
        action.id = id; action.state = state; owner(action.playerId, player);
        ActionManager.add(action);
        return action;
    }

    static ItemTransactionPacket reject(byte id, Connection connection) {
        var bytes = ByteBuffer.allocate(2);
        var writer = new ByteBufferWriter(bytes);
        writer.putByte(id); writer.putEnum(Transaction.TransactionState.Reject); bytes.flip();
        var packet = new ItemTransactionPacket();
        packet.parse(new ByteBufferReader(bytes), connection);
        require(!bytes.hasRemaining() && packet.playerId.getPlayer() == null && packet.entries.isEmpty(),
            "Reject must contain only the native byte id and state");
        require(packet.isConsistent(connection), "native Reject consistency changed");
        return packet;
    }

    static void cleanScope() throws Exception {
        require(((ThreadLocal<?>)field(QueueManagers.class, "rejectScope").get(null)).get() == null,
            "incoming Reject ownership leaked outside packet processing");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        unsafe = (Unsafe)field(Unsafe.class, "theUnsafe").get(null);
        transactions = Accessor.tryGet(TransactionManager.class, "transactions", transactions);
        actions = Accessor.tryGet(ActionManager.class, "actions", actions);
        require(transactions != null && actions != null, "native queues inaccessible");
        GameServer.server = true; GameClient.client = false;
        IsoPlayer first = player((short)19), second = player((short)20), split = player((short)21);
        Connection firstConnection = connection(first, split), secondConnection = connection(second);
        Connection attacker = connection(player((short)22));

        transaction(first, ID); transaction(second, ID);
        reject(ID, firstConnection).processServer(null, firstConnection);
        require(transactions.isEmpty(), "original engine no longer reproduces cross-owner cancellation");
        Probe unrelated = action(second, ID, Transaction.TransactionState.Accept);
        PlayerID query = new PlayerID(); owner(query, first);
        require(ActionManager.isDone(query, ID), "original engine no longer reproduces missing-action completion");
        actions.clear();
        require(!ActionManager.isDone(query, ID), "original empty-queue completion semantics changed");

        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", QueueManagerChecks.class.getClassLoader());
        require(QueueManagers.ITEM_SUPPORTED && QueueManagers.ACTION_SUPPORTED, "unsupported native managers");
        ItemTransactionPacket own = transaction(first, ID), other = transaction(second, ID);
        ItemTransactionPacket splitOwn = transaction(split, ID), orphan = transaction(null, ID);
        ItemTransactionPacket differentId = transaction(first, (byte)127);
        ItemTransactionPacket incoming = reject(ID, attacker);
        // A populated/reused packet field cannot claim another connection's player.
        owner(incoming.playerId, first);
        incoming.processServer(null, attacker);
        require(transactions.size() == 5, "unowned Reject canceled a transaction");
        reject(ID, null).processServer(null, null);
        require(transactions.size() == 5, "missing connection canceled a transaction");
        reject((byte)111, firstConnection).processServer(null, firstConnection);
        require(transactions.size() == 5, "unknown id canceled a transaction");
        reject(ID, firstConnection).processServer(null, firstConnection);
        require(!transactions.contains(own) && !transactions.contains(splitOwn), "owned/split-screen cancellation failed");
        require(transactions.contains(other) && transactions.contains(orphan) && transactions.contains(differentId),
            "owned cancellation removed a foreign, ownerless, or different-id transaction");
        reject(ID, firstConnection).processServer(null, firstConnection);
        require(transactions.size() == 3, "duplicate Reject canceled an unrelated transaction");
        cleanScope();

        ItemTransactionPacket invalid = reject(ID, firstConnection);
        invalid.entries.add(new Transaction.TransactionEntry(null));
        try { invalid.processServer(null, firstConnection); throw new AssertionError("native validation failure disappeared"); }
        catch (NullPointerException expected) { }
        require(transactions.size() == 3, "invalid packet reached removal"); cleanScope();
        for (var state : new Transaction.TransactionState[] {Transaction.TransactionState.Accept, Transaction.TransactionState.Done}) {
            ItemTransactionPacket packet = new ItemTransactionPacket(); packet.id = ID; packet.state = state;
            packet.processServer(null, firstConnection);
            require(packet.state == state && transactions.size() == 3, "non-Reject packet behavior changed"); cleanScope();
        }
        ItemTransactionPacket request = new ItemTransactionPacket(); request.id = ID; request.state = Transaction.TransactionState.Request;
        request.processServer(null, firstConnection);
        require(request.state == Transaction.TransactionState.Reject && firstConnection.replies == 1 && transactions.size() == 3,
            "native invalid-Request rejection/reply changed"); cleanScope();
        TransactionManager.removeItemTransaction(ID, true);
        require(transactions.size() == 1 && transactions.contains(differentId), "direct server manager semantics changed or scope leaked");
        GameServer.server = false; GameClient.client = true;
        transaction(first, ID); transaction(second, ID);
        TransactionManager.removeItemTransaction(ID, false);
        require(transactions.size() == 1, "local client cleanup semantics changed");
        GameClient.client = false;

        require(!ActionManager.isDone(query, ID), "empty queue reported completion");
        actions.add(unrelated);
        require(!ActionManager.isDone(query, ID), "other player's action reported completion");
        Probe pending = action(first, ID, Transaction.TransactionState.Accept);
        require(!ActionManager.isDone(query, ID), "pending action reported completion");
        pending.state = Transaction.TransactionState.Done;
        require(ActionManager.isDone(query, ID), "completed action lost completion");
        Probe duplicate = action(first, ID, Transaction.TransactionState.Request);
        require(!ActionManager.isDone(query, ID), "mixed duplicate states lost native all-match semantics");
        duplicate.state = Transaction.TransactionState.Done;
        require(ActionManager.isDone(query, ID), "all completed matching actions failed");
        actions.remove(pending); actions.remove(duplicate);
        require(!ActionManager.isDone(query, ID), "removed matching action reported completion");
        action(first, (byte)127, Transaction.TransactionState.Done);
        require(!ActionManager.isDone(query, ID), "different byte id reported completion");
        require(ActionManager.isDone(query, (byte)127), "signed/positive id lookup changed");
        actions.clear(); transactions.clear();
        System.out.println("QUEUE_MANAGER_CHECKS_PASS (original failures, native Reject wire, connection ownership, split screen, validation, scope cleanup, non-Reject/client behavior, missing-action completion)");
    }
}
