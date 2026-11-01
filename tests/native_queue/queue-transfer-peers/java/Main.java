package net.alexredby.queuepeersprobe;

import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import me.zed_0xff.zombie_buddy.Patch;
import net.bytebuddy.ByteBuddy;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.dynamic.ClassFileLocator;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.pool.TypePool;
import static net.bytebuddy.matcher.ElementMatchers.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.characters.IsoPlayer;
import zombie.core.Transaction;
import zombie.core.Transaction.TransactionState;
import zombie.core.TransactionManager;
import zombie.core.raknet.UdpConnection;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.fields.character.PlayerID;
import zombie.network.fields.ContainerID;
import zombie.network.packets.ItemTransactionPacket;

/** Disposable client-side reply loss. Never changes a request, timer or item. */
public final class Main {
    private static final Map<String,String> SOURCES = Map.of(
        "zombie/core/TransactionManager", "4a0f649f5e55edd13eff7d6788934fbec49e0073901609e1c12731fc47d7481d",
        "zombie/core/Transaction", "107b0a554cc46d1015398ff283a2e48faf02efbc44adf12854f66394ee2487b6",
        "zombie/network/packets/ItemTransactionPacket", "41608a6690d16cb0ac202a4a3196b2b0851dadb935bca2b1d9a0a3e501791e83",
        "zombie/network/fields/ContainerID", "d7ef29f65c423135d70f829a1381b9e32ce06d68f87ae49de1980bfcf7c0244b",
        "zombie/network/fields/character/PlayerID", "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56",
        "zombie/core/raknet/UdpConnection", "9c9bb471ff0c3dccdd0e52a3bb3c770327d02f0ad262187f950e660b2730e763");
    private static final String MANAGER = "zombie/core/TransactionManager";
    private static final String TRANSACTION = "zombie/core/Transaction";
    private static final String PACKET = "zombie/network/packets/ItemTransactionPacket";
    private static final ThreadLocal<Scope> CURRENT = new ThreadLocal<>();
    private static final WeakHashMap<UdpConnection,History> HISTORIES = new WeakHashMap<>();
    private static final java.util.Set<String> WOVEN = new java.util.HashSet<>();
    private static boolean attempted, sourceExact, historyFromConnectionStart, used, armed, bound;
    private static String failure = "not-installed", closed = "";
    private static IsoPlayer actor;
    private static int itemId, droppedDone, passedAccept, passedReject, attempts, reused;
    private static byte id;
    private static UdpConnection connection;
    private static Transaction selected;
    private static ItemContainer source, destination;
    private static final class History { final int[] uses = new int[256]; }
    public static final class Scope {
        final Scope previous;
        final IsoPlayer actor;
        final List<InventoryItem> items;
        final ItemContainer source, destination;
        final UdpConnection connection;
        int allocations, additions;
        Transaction allocated, added;
        boolean nested;
        Scope(Scope previous, IsoPlayer actor, List<InventoryItem> items,
              ItemContainer source, ItemContainer destination) {
            this.previous=previous; this.actor=actor; this.items=items;
            this.source=source; this.destination=destination; this.connection=GameClient.connection;
        }
    }
    private static <T> T get(Object owner, String field, T fallback) {
        return Accessor.tryGet(owner, field, fallback);
    }
    private static TransactionState state(Transaction tx) { return get(tx,"state",(TransactionState)null); }
    private static Byte transactionId(Transaction tx) { return get(tx,"id",(Byte)null); }
    private static IsoPlayer owner(Transaction tx) {
        PlayerID player=get(tx,"playerId",(PlayerID)null);
        return player==null ? null : player.getPlayer();
    }
    private static List<?> entries(Transaction tx) { return get(tx,"entries",(List<?>)null); }
    private static ConcurrentLinkedQueue<?> transactions() {
        return get(TransactionManager.class,"transactions",(ConcurrentLinkedQueue<?>)null);
    }
    public static boolean sourceSupported() {
        try {
            for (var entry:SOURCES.entrySet()) {
                try (var stream=Main.class.getClassLoader().getResourceAsStream(entry.getKey()+".class")) {
                    if (stream==null || !entry.getValue().equals(HexFormat.of().formatHex(
                            MessageDigest.getInstance("SHA-256").digest(stream.readAllBytes())))) return false;
                }
            }
            return true;
        } catch (Exception error) { return false; }
    }
    /** Gate original resources before registering any transformation. */
    public static synchronized void main(String[] arguments) {
        if (attempted) return;
        attempted=true;
        if (!sourceSupported()) { failure="unsupported-native-source"; return; }
        historyFromConnectionStart=GameClient.connection==null;
        if (!historyFromConnectionStart) { failure="late-attachment"; return; }
        Instrumentation instrumentation=get(Loader.class,"g_instrumentation",(Instrumentation)null);
        if (instrumentation==null || !instrumentation.isRetransformClassesSupported()) {
            failure="no-retransform"; return;
        }
        try {
            // Warm advice metadata and validate every descriptor before changing
            // a live class. This also avoids recursively loading a target from
            // inside its own initial-load transformation.
            for (String name:List.of(MANAGER,TRANSACTION,PACKET)) {
                Class.forName(name.replace('/','.'),false,Main.class.getClassLoader());
                try (var stream=Main.class.getClassLoader().getResourceAsStream(name+".class")) {
                    if (stream==null) throw new IllegalStateException("missing class source");
                    weave(name,stream.readAllBytes(),Main.class.getClassLoader());
                }
            }
        } catch (Throwable error) { failure="descriptor-or-advice-preflight"; return; }
        ClassFileTransformer transformer=new ClassFileTransformer() {
            @Override public byte[] transform(ClassLoader loader,String name,Class<?> type,
                    java.security.ProtectionDomain domain,byte[] bytes) {
                if (!MANAGER.equals(name) && !TRANSACTION.equals(name) && !PACKET.equals(name)) return null;
                try {
                    byte[] result=weave(name,bytes,loader);
                    synchronized(Main.class) { WOVEN.add(name); }
                    return result;
                } catch (Throwable error) {
                    synchronized(Main.class) { sourceExact=false; failure="weave-"+name; }
                    return null;
                }
            }
        };
        instrumentation.addTransformer(transformer,true);
        try {
            for (String name:List.of(MANAGER,TRANSACTION,PACKET)) {
                Class<?> loaded=null;
                for (Class<?> candidate:instrumentation.getAllLoadedClasses())
                    if (candidate.getName().equals(name.replace('/','.'))) { loaded=candidate; break; }
                if (loaded==null) Class.forName(name.replace('/','.'),false,Main.class.getClassLoader());
                else instrumentation.retransformClasses(loaded);
            }
            sourceExact=WOVEN.size()==3;
            failure=sourceExact ? "" : "incomplete-weave";
        } catch (Throwable error) { sourceExact=false; failure="install-"+error.getClass().getSimpleName(); }
        if (!sourceExact) instrumentation.removeTransformer(transformer);
    }
    /** Public for focused bytecode verification; it does not install anything. */
    public static byte[] weave(String name,byte[] bytes,ClassLoader loader) {
        String binary=name.replace('/','.');
        var locator=new ClassFileLocator.Compound(ClassFileLocator.Simple.of(binary,bytes),
                ClassFileLocator.ForClassLoader.of(loader));
        var description=TypePool.Default.of(locator).describe(binary).resolve();
        DynamicType.Builder<?> builder=new ByteBuddy().redefine(description,locator);
        if (MANAGER.equals(name)) {
            var create=named("createItemTransaction").and(takesArguments(IsoPlayer.class,List.class,ItemContainer.class,ItemContainer.class)).and(returns(byte.class));
            var add=named("add").and(takesArguments(Transaction.class)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(create).size()!=1 || description.getDeclaredMethods().filter(add).size()!=1)
                throw new IllegalArgumentException("manager descriptors");
            builder=builder.visit(Advice.to(Request.class).on(create)).visit(Advice.to(Added.class).on(add));
        } else if (TRANSACTION.equals(name)) {
            var set=named("set").and(takesArguments(IsoPlayer.class,List.class,ItemContainer.class,ItemContainer.class,
                    String.class,zombie.iso.IsoDirections.class,float.class,float.class,float.class)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(set).size()!=1) throw new IllegalArgumentException("set descriptor");
            builder=builder.visit(Advice.to(Allocated.class).on(set));
        } else if (PACKET.equals(name)) {
            var receive=named("processClient").and(takesArguments(UdpConnection.class)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(receive).size()!=1) throw new IllegalArgumentException("receive descriptor");
            builder=builder.visit(Advice.to(Received.class).on(receive));
        } else throw new IllegalArgumentException("unsupported class");
        return builder.make().getBytes();
    }
    public static synchronized Scope begin(IsoPlayer requestActor,List<InventoryItem> items,
            ItemContainer requestSource,ItemContainer requestDestination) {
        if (used && requestActor==actor && items!=null) {
            for (InventoryItem item:items) if (item!=null && item.getID()==itemId) { attempts++; break; }
        }
        Scope parent=CURRENT.get();
        if (parent!=null) parent.nested=true;
        Scope scope=new Scope(parent,requestActor,items,requestSource,requestDestination);
        CURRENT.set(scope);
        return scope;
    }
    private static void recordAllocation(Transaction tx) {
        if (!GameClient.client || GameClient.connection==null || tx==null) return;
        Byte candidate=transactionId(tx);
        if (candidate==null) return;
        UdpConnection current=GameClient.connection;
        History history=HISTORIES.computeIfAbsent(current,key->new History());
        int index=candidate&255;
        history.uses[index]=Math.min(2,history.uses[index]+1);
        if (bound && connection==current && candidate==id) { reused++; close("byte-reused"); }
    }
    public static synchronized void allocated(Transaction tx) {
        recordAllocation(tx);
        Scope scope=CURRENT.get();
        if (scope!=null) { scope.allocations++; scope.allocated=tx; }
    }
    public static synchronized void added(Transaction tx) {
        Scope scope=CURRENT.get();
        // An add outside the one observed allocation/add pair can be a direct
        // reuse of the same object, so it must taint history as well.
        boolean exactAllocation=scope!=null && scope.allocations==1 && scope.allocated==tx && scope.additions==0;
        if (!exactAllocation) recordAllocation(tx);
        if (scope!=null) { scope.additions++; scope.added=tx; }
    }
    private static boolean exact(Transaction tx,Scope scope) {
        if (tx==null || tx.getClass()!=ItemTransactionPacket.class || owner(tx)!=scope.actor) return false;
        List<?> list=entries(tx);
        if (list==null || list.size()!=1 || !entryMatches(list.getFirst(),scope.source,scope.destination)) return false;
        return scope.items!=null && scope.items.size()==1
            && scope.items.getFirst()!=null && scope.items.getFirst().getID()==itemId;
    }
    private static boolean entryMatches(Object entry,ItemContainer from,ItemContainer to) {
        if (entry==null || !entry.getClass().getName().equals("zombie.core.Transaction$TransactionEntry")) return false;
        Integer item=get(entry,"itemId",(Integer)null);
        ContainerID sourceId=get(entry,"sourceId",(ContainerID)null);
        ContainerID destinationId=get(entry,"destinationId",(ContainerID)null);
        return item!=null && item==itemId && sourceId!=null && destinationId!=null
            && sourceId.getContainer()==from && destinationId.getContainer()==to;
    }
    public static synchronized void end(Scope scope,byte result,Throwable error) {
        if (scope==null) return;
        try {
            if (!armed || bound || scope.actor!=actor) return;
            if (CURRENT.get()!=scope || scope.previous!=null || scope.nested || error!=null || result==0
                    || scope.allocations!=1 || scope.additions!=1 || scope.allocated!=scope.added
                    || scope.connection!=connection || GameClient.connection!=connection
                    || scope.source==null || scope.destination==null || scope.source==scope.destination
                    || !exact(scope.added,scope) || transactionId(scope.added)==null
                    || transactionId(scope.added)!=result || state(scope.added)!=TransactionState.Request) {
                close("request-not-exact-singleton"); return;
            }
            History history=HISTORIES.get(connection);
            if (history==null || history.uses[result&255]!=1) { close("byte-history-ambiguous"); return; }
            selected=scope.added; source=scope.source; destination=scope.destination; id=result;
            if (!uniqueCurrent()) { close("transaction-not-unique"); return; }
            bound=true;
        } finally {
            if (scope.previous==null) CURRENT.remove(); else CURRENT.set(scope.previous);
        }
    }
    private static boolean uniqueCurrent() {
        ConcurrentLinkedQueue<?> queue=transactions();
        if (queue==null || selected==null) return false;
        int same=0,visited=0; boolean found=false;
        for (Object candidate:queue) {
            if (++visited>128) return false;
            if (candidate instanceof Transaction tx && transactionId(tx)!=null && transactionId(tx)==id) {
                same++; if (tx==selected) found=true;
            }
        }
        return found && same==1;
    }
    private static void close(String reason) { armed=false; closed=reason; }
    private static boolean currentBinding() {
        if (!sourceExact || !armed || !bound || GameClient.connection!=connection || !GameClient.client || GameServer.server)
            return false;
        History history=HISTORIES.get(connection);
        if (history==null || history.uses[id&255]!=1 || owner(selected)!=actor || !uniqueCurrent()) {
            close("native-transaction-retired-or-ambiguous"); return false;
        }
        List<?> list=entries(selected);
        if (list==null || list.size()!=1 || !entryMatches(list.getFirst(),source,destination)) {
            close("native-binding-changed"); return false;
        }
        TransactionState nativeState=state(selected);
        if (nativeState!=TransactionState.Request && nativeState!=TransactionState.Accept) {
            close("native-transaction-terminal"); return false;
        }
        return true;
    }
    /** Guard isolated for offline shape/identity checks; it does not fabricate a packet. */
    static boolean replyPayloadMatches(Object armedActor,Object incomingActor,List<?> incomingEntries,
            java.util.function.Predicate<Object> matchingEntry) {
        return armedActor!=null && incomingActor==armedActor && incomingEntries!=null
            && incomingEntries.size()==1 && matchingEntry.test(incomingEntries.getFirst());
    }
    private static boolean matchingPayload(ItemTransactionPacket packet) {
        return replyPayloadMatches(actor,owner(packet),entries(packet),
            entry->entryMatches(entry,source,destination));
    }
    /** Only Done is lost. Accept/Reject and every other packet run unchanged. */
    public static synchronized boolean drop(ItemTransactionPacket packet,UdpConnection incoming) {
        if (!currentBinding() || incoming!=connection || packet==selected || transactionId(packet)==null
                || transactionId(packet)!=id) return false;
        TransactionState reply=state(packet);
        if (reply==TransactionState.Accept) {
            if (matchingPayload(packet)) passedAccept++;
            return false;
        }
        if (reply==TransactionState.Reject) { passedReject++; return false; }
        if (reply!=TransactionState.Done || state(selected)!=TransactionState.Accept || passedAccept<1
                || !matchingPayload(packet)) return false;
        // Done carries actor and entries in this pinned wire format. Match them
        // against the armed singleton as well as the exact live outgoing object.
        // Reject alone omits that payload and is always passed through.
        droppedDone++;
        return true;
    }
    public static synchronized boolean arm(IsoPlayer player,int requestedItem) {
        if (used || !sourceExact || !historyFromConnectionStart || !GameClient.client || GameServer.server
                || GameClient.connection==null || player==null || !player.isLocalPlayer() || requestedItem<=0
                || CURRENT.get()!=null) return false;
        used=true; armed=true; actor=player; itemId=requestedItem; connection=GameClient.connection;
        return true;
    }
    public static synchronized KahluaTable snapshot() {
        if (armed && bound) currentBinding();
        KahluaTable table=new J2SEPlatform().newTable();
        table.rawset("sourceExact",sourceExact); table.rawset("historyFromConnectionStart",historyFromConnectionStart);
        table.rawset("armed",armed); table.rawset("bound",bound); table.rawset("used",used);
        table.rawset("droppedDone",(double)droppedDone); table.rawset("droppedAccept",0.0); table.rawset("droppedReject",0.0);
        table.rawset("passedAccept",(double)passedAccept); table.rawset("passedReject",(double)passedReject);
        table.rawset("attempts",(double)attempts); table.rawset("requestCount",(double)attempts);
        table.rawset("reused",(double)reused); table.rawset("nativePresent",bound && uniqueCurrent());
        table.rawset("transaction",(double)id); table.rawset("item",(double)itemId);
        table.rawset("actor",actor==null ? -1.0 : (double)actor.getOnlineID());
        table.rawset("failure",failure); table.rawset("closed",closed);
        table.rawset("pendingExact",armed && bound && currentBinding());
        table.rawset("nativeState",selected==null || state(selected)==null ? "" : state(selected).name());
        table.rawset("fault","drop-only-native-Done-no-replay");
        return table;
    }
    public static void bindings() {
        main(new String[0]);
        if (LuaManager.env==null) return;
        LuaManager.env.rawset("queuePeersArmReplyLoss",(JavaFunction)(frame,count)->frame.push(count==2
            && frame.get(0) instanceof IsoPlayer player && frame.get(1) instanceof Double number
            && number==Math.rint(number) && number<=Integer.MAX_VALUE && arm(player,number.intValue())));
        LuaManager.env.rawset("queuePeersReplyLossState",(JavaFunction)(frame,count)->frame.push(snapshot()));
    }
    @Patch(className="zombie.gameStates.GameLoadingState",methodName="exit",warmUp=true,strictMatch=true)
    public static class Exports { @Patch.OnExit public static void exit() { Main.bindings(); } }
    public static class Request {
        @Advice.OnMethodEnter(suppress=Throwable.class) public static Scope enter(@Advice.Argument(0) IsoPlayer player,
            @Advice.Argument(1) List<InventoryItem> items,@Advice.Argument(2) ItemContainer source,
            @Advice.Argument(3) ItemContainer destination) { return Main.begin(player,items,source,destination); }
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Advice.Enter Scope scope,
            @Advice.Return byte result,@Advice.Thrown Throwable error) { Main.end(scope,result,error); }
    }
    public static class Allocated {
        @Advice.OnMethodExit(suppress=Throwable.class) public static void exit(@Advice.This Transaction tx) { Main.allocated(tx); }
    }
    public static class Added {
        @Advice.OnMethodExit(suppress=Throwable.class) public static void exit(@Advice.Argument(0) Transaction tx) { Main.added(tx); }
    }
    public static class Received {
        @Advice.OnMethodEnter(skipOn=Advice.OnNonDefaultValue.class,suppress=Throwable.class) public static boolean enter(
            @Advice.This ItemTransactionPacket packet,@Advice.Argument(0) UdpConnection connection) {
            return Main.drop(packet,connection);
        }
    }
}
