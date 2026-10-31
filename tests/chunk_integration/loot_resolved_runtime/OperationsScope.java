package toolkit.lootresolved.bootstrap;

import java.util.concurrent.atomic.AtomicReference;
import zombie.inventory.InventoryItem;

/** Test-only fixed storage. No Lua callback, allocation, map or formatting on normal append. */
public final class OperationsScope {
    public static final String KIND="owner-window-paired-roll-v1";
    private static final AtomicReference<Session> ACTIVE=new AtomicReference<>();
    public static final class Session {
        public final Thread owner=Thread.currentThread();
        public final boolean candidate;
        public final InventoryItem[] items, increments;
        public final int[] deltas;
        public int itemCount, incrementCount, nullReturns, selections;
        private boolean window, windowUsed;
        private String poison;
        private Session(boolean candidate,int limit) {
            this.candidate=candidate; items=new InventoryItem[limit]; increments=new InventoryItem[limit]; deltas=new int[limit];
        }
        public boolean poisoned() { return poison!=null; }
        public String failure() { return poison; }
    }
    private static void reject(Session session,String reason) {
        if (session.poison==null) session.poison=reason;
        throw new IllegalStateException(reason);
    }
    private static Session owned() {
        Session session=ACTIVE.get();
        if (session==null || session.owner!=Thread.currentThread()) throw new IllegalStateException("operations-owner-required");
        return session;
    }
    public static Session begin(boolean candidate,int limit) {
        if (limit<1 || limit>16384) throw new IllegalArgumentException("operations-storage-bound");
        if (ACTIVE.get()!=null) throw new IllegalStateException("operations-already-owned");
        Session session=new Session(candidate,limit);
        if (!ACTIVE.compareAndSet(null,session)) throw new IllegalStateException("operations-already-owned");
        return session;
    }
    public static void beginWindow() {
        Session session=owned();
        if (session.windowUsed || session.poison!=null) reject(session,"operations-window-reentry-or-poison");
        session.windowUsed=true; session.window=true;
    }
    public static void endWindow() {
        Session session=owned();
        if (!session.window) reject(session,"operations-window-not-open");
        session.window=false;
    }
    /** Both native-chance and resolved-chance variants pay this identical owner/phase selection. */
    public static boolean resolved() {
        Session session=ACTIVE.get();
        if (session==null || session.owner!=Thread.currentThread() || !session.window) return false;
        session.selections++;
        return session.candidate;
    }
    public static void factoryReturned(InventoryItem item) {
        Session session=ACTIVE.get();
        if (session==null || session.owner!=Thread.currentThread()) return;
        if (item==null) { session.nullReturns++; return; }
        if (session.itemCount==session.items.length) reject(session,"operations-factory-array-overflow");
        session.items[session.itemCount++]=item;
    }
    /** Invoked after the actual native InstanceTracker update, never instead of it. */
    public static void incremented(InventoryItem item,int delta) {
        Session session=ACTIVE.get();
        if (session==null || session.owner!=Thread.currentThread() || item==null) return;
        if (session.incrementCount==session.increments.length) reject(session,"operations-increment-array-overflow");
        session.increments[session.incrementCount]=item; session.deltas[session.incrementCount++]=delta;
    }
    /** Poison must survive native protected callbacks swallowing the original exception. */
    public static void failed(Throwable ignored) {
        Session session=ACTIVE.get();
        if (session!=null && session.owner==Thread.currentThread() && session.poison==null)
            session.poison="operations-native-factory-or-increment-threw";
    }
    public static void close() {
        Session session=owned();
        session.window=false;
        if (!ACTIVE.compareAndSet(session,null)) throw new IllegalStateException("operations-owner-changed");
        if (session.poison!=null) throw new IllegalStateException(session.poison);
    }
}
