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
import se.krka.kahlua.j2se.KahluaTableImpl;
import se.krka.kahlua.vm.LuaClosure;
import se.krka.kahlua.vm.JavaFunction;
import se.krka.kahlua.vm.KahluaTable;
import zombie.Lua.LuaManager;
import zombie.GameTime;
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

/** Disposable exact-request reply loss and opt-in competing physical move fixtures. */
public final class Main {
    private static final Map<String,String> SOURCES = Map.of(
        "zombie/network/GameClient", "99d1778ab2c2627ddcbc04fdbb435461289c3c3075c96cf70eae5c216193352b",
        "zombie/inventory/ItemContainer", "a2ac7dd6235f91255dc57b91419a2c8609bdb105214cddf7fb445b70507b6f96",
        "zombie/network/GameServer", "308ee5247dc8bba4df2283d40d753c6839497767b9342a4adeea60e7c08cfacc",
        "zombie/GameTime", "ec030ac26790d8c06712c3e1d5935bb29cc816ac3b6f1ea55b06ebeccb7e7125",
        "zombie/core/TransactionManager", "4a0f649f5e55edd13eff7d6788934fbec49e0073901609e1c12731fc47d7481d",
        "zombie/core/Transaction", "107b0a554cc46d1015398ff283a2e48faf02efbc44adf12854f66394ee2487b6",
        "zombie/network/packets/ItemTransactionPacket", "41608a6690d16cb0ac202a4a3196b2b0851dadb935bca2b1d9a0a3e501791e83",
        "zombie/network/fields/ContainerID", "d7ef29f65c423135d70f829a1381b9e32ce06d68f87ae49de1980bfcf7c0244b",
        "zombie/network/fields/character/PlayerID", "d40d1b745a70ad3bf562c15765b9f46a117ecb48aeeabf05597ce646a73e0b56",
        "zombie/core/raknet/UdpConnection", "9c9bb471ff0c3dccdd0e52a3bb3c770327d02f0ad262187f950e660b2730e763");
    private static final String MANAGER = "zombie/core/TransactionManager";
    private static final String TRANSACTION = "zombie/core/Transaction";
    private static final WeakHashMap<UdpConnection,History> SERVER_HISTORIES = new WeakHashMap<>();
    private static Partial partial = new Partial();
    private static final String PACKET = "zombie/network/packets/ItemTransactionPacket";
    private static final ThreadLocal<Scope> CURRENT = new ThreadLocal<>();
    private static final WeakHashMap<UdpConnection,History> HISTORIES = new WeakHashMap<>();
    private static final WeakHashMap<Transaction,Long> CLOCK_BIRTHS = new WeakHashMap<>();
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
        DynamicType.Builder<?> builder=new ByteBuddy().ignore(none()).redefine(description,locator);
        if (MANAGER.equals(name)) {
            var create=named("createItemTransaction").and(takesArguments(IsoPlayer.class,List.class,ItemContainer.class,ItemContainer.class)).and(returns(byte.class));
            var add=named("add").and(takesArguments(Transaction.class)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(create).size()!=1 || description.getDeclaredMethods().filter(add).size()!=1)
                throw new IllegalArgumentException("manager descriptors");
            var expiry=named("lambda$update$1").and(takesArguments(long.class,Transaction.class)).and(returns(boolean.class));
            if (description.getDeclaredMethods().filter(expiry).size()!=1)
                throw new IllegalArgumentException("expiry descriptor");
            var update=named("update").and(takesArguments(0)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(update).size()!=1) throw new IllegalArgumentException("manager update descriptor");
            builder=builder.visit(Advice.to(Request.class).on(create)).visit(Advice.to(Added.class).on(add))
                    .visit(Advice.to(Expired.class).on(expiry)).visit(Advice.to(ManagerUpdated.class).on(update));
        } else if (TRANSACTION.equals(name)) {
            var set=named("set").and(takesArguments(IsoPlayer.class,List.class,ItemContainer.class,ItemContainer.class,
                    String.class,zombie.iso.IsoDirections.class,float.class,float.class,float.class)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(set).size()!=1) throw new IllegalArgumentException("set descriptor");
            var update=named("update").and(takesArguments(0)).and(returns(boolean.class));
            if (description.getDeclaredMethods().filter(update).size()!=1) throw new IllegalArgumentException("transaction update descriptor");
            builder=builder.visit(Advice.to(Allocated.class).on(set)).visit(Advice.to(PartialUpdate.class).on(update));
        } else if (PACKET.equals(name)) {
            var receive=named("processClient").and(takesArguments(UdpConnection.class)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(receive).size()!=1) throw new IllegalArgumentException("receive descriptor");
            var server=named("processServer").and(takesArguments(zombie.network.PacketTypes.PacketType.class,UdpConnection.class)).and(returns(void.class));
            var write=named("write").and(takesArguments(zombie.core.network.ByteBufferWriter.class)).and(returns(void.class));
            if (description.getDeclaredMethods().filter(server).size()!=1 || description.getDeclaredMethods().filter(write).size()!=1)
                throw new IllegalArgumentException("server admission/write descriptors");
            builder=builder.visit(Advice.to(Received.class).on(receive)).visit(Advice.to(ServerReceived.class).on(server))
                .visit(Advice.to(PacketWritten.class).on(write));
        } else throw new IllegalArgumentException("unsupported class");
        return builder.make().getBytes();
    }
    public static synchronized Scope begin(IsoPlayer requestActor,List<InventoryItem> items,
            ItemContainer requestSource,ItemContainer requestDestination) {
        if (used && requestActor==actor && items!=null) {
            for (InventoryItem item:items) if (item!=null && item.getID()==itemId) { attempts++; break; }
        }
        Partial p=partial;
        if (p.used && p.client && requestActor==p.actor && items!=null && items.stream().anyMatch(
                value->value!=null && (value.getID()==p.firstId || value.getID()==p.secondId))) {
            p.requestCount++;
            if (p.requestCount!=1) partialClose("repeated-request");
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
        if (partial.bound && partial.client && partial.connection==current && candidate==partial.id) {
            partial.reused++; partialClose("byte-reused");
        }
        if (bound && connection==current && candidate==id) { reused++; close("byte-reused"); }
    }
    public static synchronized void allocated(Transaction tx) {
        recordAllocation(tx);
        if (GameClient.client && !GameServer.server && tx!=null && tx.getClass()==ItemTransactionPacket.class) {
            CLOCK_BIRTHS.put(tx,System.nanoTime());
            clockEvent("allocated",tx,null);
        }
        Scope scope=CURRENT.get();
        if (scope!=null) { scope.allocations++; scope.allocated=tx; }
    }
    private static void clockEvent(String event,Transaction tx,Long timeoutNow) {
        Long birth=CLOCK_BIRTHS.get(tx);
        System.out.println("[QueuePeersClock] " + event + " object="+System.identityHashCode(tx)
            +" id="+transactionId(tx)+" state="+state(tx)
            +" start="+get(tx,"startTime",(Long)null)+" end="+get(tx,"endTime",(Long)null)
            +" ready="+GameTime.getServerTimeShiftIsSet()+" server="+GameTime.getServerTimeMills()
            +" ageMs="+(birth==null ? "unknown" : (System.nanoTime()-birth)/1_000_000L)
            +" timeoutNow="+timeoutNow);
    }
    public static synchronized void expired(Transaction tx,long timeoutNow,boolean result) {
        if (result && partial.used && partial.client && tx==partial.selected) {
            if (partialEpoch() && partial.passedAccept==1 && state(tx)==TransactionState.Accept) partial.expired=true;
            else partialClose("expiry-binding-changed");
        }
        if (result && GameClient.client && !GameServer.server && tx!=null && CLOCK_BIRTHS.containsKey(tx))
            clockEvent("expired",tx,timeoutNow);
    }
    public static class Expired {
        @Advice.OnMethodExit(suppress=Throwable.class)
        public static void exit(@Advice.Argument(0) long nativeNow,
                @Advice.Argument(1) Transaction tx,@Advice.Return boolean result) {
            expired(tx,nativeNow,result);
        }
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
            partialRequestEnd(scope,result,error);
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
        partialReply(packet,incoming);
        if (GameClient.client && !GameServer.server && packet!=null)
            clockEvent("received",packet,null);
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
        partialBindings();
        LuaManager.env.rawset("queuePeersArmReplyLoss",(JavaFunction)(frame,count)->frame.push(count==2
            && frame.get(0) instanceof IsoPlayer player && frame.get(1) instanceof Double number
            && number==Math.rint(number) && number<=Integer.MAX_VALUE && arm(player,number.intValue())));
        LuaManager.env.rawset("queuePeersReplyLossState",(JavaFunction)(frame,count)->frame.push(snapshot()));
    }
    @Patch(className="zombie.gameStates.GameLoadingState",methodName="exit",warmUp=true,strictMatch=true)
    public static class Exports { @Patch.OnExit public static void exit() { Main.bindings(); } }
    /** Independent one-shot state; never grants production replay or recovery authority. */
    private static final class Partial {
        boolean used, armed, bound, client, movedSecond, nativeReturnedFalse, updateThrew;
        boolean managerReject, managerRemoved, expired;
        String token="", closed="";
        IsoPlayer actor;
        int actorId, firstId, secondId, requestCount, accepted, updateCalls, terminalWrites;
        int acceptWrites, passedAccept, passedDone, passedReject, reused;
        byte id;
        long guid;
        UdpConnection connection;
        Transaction selected;
        InventoryItem first, second;
        ItemContainer source, destination, quarantine;
        List<?> originalEntries;
        Object entry1, entry2;
    }
    private static void partialClose(String reason) { partial.armed=false; if (partial.closed.isEmpty()) partial.closed=reason; }
    private static boolean validToken(String token) { return token!=null && token.matches("[A-Za-z0-9_:-]{1,128}"); }
    private static int occurrences(ItemContainer container,InventoryItem item) {
        if (container==null || item==null) return -1;
        int count=0;
        for (InventoryItem value:container.getItems()) if (value==item || value.getID()==item.getID()) {
            if (value!=item) return -1;
            count++;
        }
        return count;
    }
    private static boolean at(InventoryItem item,ItemContainer container) {
        return item!=null && item.getContainer()==container && occurrences(container,item)==1;
    }
    private static boolean absent(InventoryItem item,ItemContainer container) { return occurrences(container,item)==0; }
    private static boolean pairEntry(Object entry,int id,ItemContainer from,ItemContainer to) {
        if (entry==null || !entry.getClass().getName().equals("zombie.core.Transaction$TransactionEntry")) return false;
        Integer value=get(entry,"itemId",(Integer)null);
        ContainerID source=get(entry,"sourceId",(ContainerID)null), destination=get(entry,"destinationId",(ContainerID)null);
        return value!=null && value==id && source!=null && destination!=null
            && source.getContainer()==from && destination.getContainer()==to;
    }
    /** Canonical order is significant: the first member must execute before the missing second. */
    static boolean pairPayloadMatches(Object actor,Object incoming,List<?> list,
            java.util.function.Predicate<Object> first,java.util.function.Predicate<Object> second) {
        return actor!=null && actor==incoming && list!=null && list.size()==2
            && list.get(0)!=list.get(1) && first.test(list.get(0)) && second.test(list.get(1));
    }
    private static boolean partialPayload(Transaction tx) {
        Partial p=partial;
        return tx!=null && tx.getClass()==ItemTransactionPacket.class && pairPayloadMatches(p.actor,owner(tx),entries(tx),
            e->pairEntry(e,p.firstId,p.source,p.destination), e->pairEntry(e,p.secondId,p.source,p.destination));
    }
    private static boolean partialEntriesUnchanged() {
        Partial p=partial; List<?> list=entries(p.selected);
        return list==p.originalEntries && list!=null && list.size()==2 && list.get(0)==p.entry1 && list.get(1)==p.entry2
            && partialPayload(p.selected);
    }
    private static boolean partialPresent() {
        ConcurrentLinkedQueue<?> queue=transactions();
        return queue!=null && partial.selected!=null && queue.contains(partial.selected);
    }
    private static boolean partialUnique() {
        Partial p=partial; ConcurrentLinkedQueue<?> queue=transactions();
        if (queue==null || p.selected==null) return false;
        int count=0,visited=0; boolean found=false;
        for (Object value:queue) {
            if (++visited>128) return false;
            if (value instanceof Transaction tx && transactionId(tx)!=null && transactionId(tx)==p.id
                    && (p.client || owner(tx)==p.actor)) { count++; if (tx==p.selected) found=true; }
        }
        return found && count==1;
    }
    private static boolean partialEpoch() {
        Partial p=partial;
        if (!sourceExact || p.connection==null || p.actor==null || p.actor.getOnlineID()!=p.actorId
                || p.connection.getConnectedGUID()!=p.guid) return false;
        return p.client ? GameClient.client && !GameServer.server && GameClient.instance.connected
                && GameClient.connection==p.connection && p.actor.isLocalPlayer()
            : GameServer.server && !GameClient.client && p.connection.isFullyConnected() && GameServer.getConnectionFromPlayer(p.actor)==p.connection
                && GameServer.IDToPlayerMap.get((short)p.actorId)==p.actor;
    }
    private static void partialBind(Transaction tx) {
        Partial p=partial; p.selected=tx; p.id=transactionId(tx);
        p.originalEntries=entries(tx); p.entry1=p.originalEntries.get(0); p.entry2=p.originalEntries.get(1); p.bound=true;
    }
    private static final Map<String,Object> ARM_DIAGNOSTIC=new java.util.LinkedHashMap<>();
    private static void armContext(IsoPlayer player,int first,int second,String token) {
        ARM_DIAGNOSTIC.put("sourceExact",sourceExact); ARM_DIAGNOSTIC.put("historyFromConnectionStart",historyFromConnectionStart);
        ARM_DIAGNOSTIC.put("client",GameClient.client); ARM_DIAGNOSTIC.put("server",GameServer.server);
        ARM_DIAGNOSTIC.put("connectionPresent",GameClient.connection!=null); ARM_DIAGNOSTIC.put("instanceConnected",GameClient.instance.connected);
        ARM_DIAGNOSTIC.put("serverFullyConnectedFlag",GameClient.connection!=null && GameClient.connection.isFullyConnected());
        ARM_DIAGNOSTIC.put("actorPresent",player!=null); ARM_DIAGNOSTIC.put("localActor",player!=null && player.isLocalPlayer());
        ARM_DIAGNOSTIC.put("scopePresent",CURRENT.get()!=null); ARM_DIAGNOSTIC.put("alreadyUsed",partial.used);
        ARM_DIAGNOSTIC.put("firstValid",first>0); ARM_DIAGNOSTIC.put("secondValid",second>0);
        ARM_DIAGNOSTIC.put("distinct",first!=second); ARM_DIAGNOSTIC.put("tokenValid",validToken(token));
    }
    private static boolean armRejected(String reason) {
        ARM_DIAGNOSTIC.put("reason",reason); ARM_DIAGNOSTIC.put("accepted",false);
        System.out.println("[QueuePeersPartialArm] "+ARM_DIAGNOSTIC);
        return false;
    }
    public static synchronized KahluaTable partialArmSnapshot() {
        KahluaTable table=new J2SEPlatform().newTable();
        for (var entry:ARM_DIAGNOSTIC.entrySet()) table.rawset(entry.getKey(),entry.getValue());
        return table;
    }
    public static synchronized boolean armPartialClient(IsoPlayer player,int first,int second,String token) {
        armContext(player,first,second,token);
        if (partial.used) return armRejected("already-used");
        if (!sourceExact) return armRejected("native-source-unsupported");
        if (!historyFromConnectionStart) return armRejected("late-attachment");
        if (!GameClient.client || GameServer.server) return armRejected("not-client-role");
        if (GameClient.connection==null) return armRejected("no-current-connection");
        if (!GameClient.instance.connected) return armRejected("client-instance-not-connected");
        if (player==null || !player.isLocalPlayer()) return armRejected("actor-not-local");
        if (first<=0 || second<=0 || first==second) return armRejected("item-ids-invalid");
        if (!validToken(token)) return armRejected("token-invalid");
        if (CURRENT.get()!=null) return armRejected("request-scope-present");
        Partial p=partial; p.used=true; p.armed=true; p.client=true; p.actor=player; p.actorId=player.getOnlineID();
        p.firstId=first; p.secondId=second; p.token=token; p.connection=GameClient.connection; p.guid=p.connection.getConnectedGUID();
        if (!partialEpoch()) { partialClose("invalid-epoch"); return armRejected("client-epoch-invalid"); }
        ARM_DIAGNOSTIC.put("reason",""); ARM_DIAGNOSTIC.put("accepted",true);
        return true;
    }
    public static synchronized boolean armPartial(IsoPlayer player,InventoryItem first,InventoryItem second,
            ItemContainer source,ItemContainer destination,ItemContainer quarantine,String token) {
        if (partial.used || !sourceExact || !GameServer.server || GameClient.client || player==null || first==null || second==null
                || first==second || first.getID()<=0 || second.getID()<=0 || first.getID()==second.getID()
                || source==null || destination==null || quarantine==null || source==destination || source==quarantine
                || destination==quarantine || !validToken(token) || !at(first,source) || !at(second,source)
                || !absent(first,destination) || !absent(second,destination) || !absent(first,quarantine) || !absent(second,quarantine)) return false;
        UdpConnection connection=GameServer.getConnectionFromPlayer(player);
        if (connection==null || !connection.isFullyConnected()) return false;
        Partial p=partial; p.used=true; p.armed=true; p.actor=player; p.actorId=player.getOnlineID();
        p.first=first; p.second=second; p.firstId=first.getID(); p.secondId=second.getID();
        p.source=source; p.destination=destination; p.quarantine=quarantine; p.token=token;
        p.connection=connection; p.guid=connection.getConnectedGUID();
        if (!partialEpoch()) { partialClose("invalid-epoch"); return false; }
        return true;
    }
    private static void partialRequestEnd(Scope scope,byte result,Throwable error) {
        Partial p=partial;
        if (!p.armed || !p.client || p.bound || scope.actor!=p.actor) return;
        if (p.requestCount!=1 || scope.items==null || scope.items.size()!=2 || scope.items.get(0)==null || scope.items.get(1)==null
                || scope.items.get(0).getID()!=p.firstId || scope.items.get(1).getID()!=p.secondId
                || CURRENT.get()!=scope || scope.previous!=null || scope.nested || error!=null || result==0
                || scope.allocations!=1 || scope.additions!=1 || scope.allocated!=scope.added
                || scope.connection!=p.connection || !partialEpoch() || scope.source==null || scope.destination==null
                || scope.source==scope.destination || transactionId(scope.added)==null || transactionId(scope.added)!=result
                || state(scope.added)!=TransactionState.Request) { partialClose("request-not-exact-pair"); return; }
        p.source=scope.source; p.destination=scope.destination;
        History history=HISTORIES.get(p.connection);
        if (!partialPayload(scope.added) || history==null || history.uses[result&255]!=1) {
            partialClose("pair-or-byte-history-ambiguous"); return;
        }
        partialBind(scope.added);
        if (!partialUnique()) partialClose("transaction-not-unique");
    }
    public static synchronized boolean partialServerEnter(ItemTransactionPacket packet,UdpConnection incoming) {
        if (!GameServer.server || GameClient.client || packet==null || state(packet)!=TransactionState.Request) return false;
        Byte candidate=transactionId(packet);
        if (candidate==null || incoming==null) return false;
        History history=SERVER_HISTORIES.computeIfAbsent(incoming,key->new History());
        history.uses[candidate&255]=Math.min(2,history.uses[candidate&255]+1);
        Partial p=partial;
        if (p.bound && incoming==p.connection && candidate==p.id) { p.reused++; partialClose("byte-reused"); }
        if (!p.used || p.client || owner(packet)!=p.actor || incoming!=p.connection) return false;
        List<?> list=entries(packet);
        boolean relevant=list!=null && list.stream().anyMatch(e->{ Integer item=get(e,"itemId",(Integer)null);
            return item!=null && (item==p.firstId || item==p.secondId); });
        if (!relevant) return false;
        p.requestCount++;
        if (!p.armed || p.bound || p.requestCount!=1 || !partialEpoch() || !partialPayload(packet)
                || history.uses[candidate&255]!=1 || !at(p.first,p.source) || !at(p.second,p.source)) {
            partialClose("admission-not-exact-pair"); return false;
        }
        // This is the actual received object, before native admission and its Accept write.
        partialBind(packet);
        return true;
    }
    public static synchronized void partialServerExit(ItemTransactionPacket packet,UdpConnection incoming,boolean observed,Throwable error) {
        Partial p=partial;
        if (!observed || packet!=p.selected) return;
        if (error!=null || incoming!=p.connection || !partialEpoch() || !partialEntriesUnchanged()
                || state(packet)!=TransactionState.Accept || !partialUnique() || p.acceptWrites!=1) {
            partialClose("native-admission-not-accepted"); return;
        }
        p.accepted++;
    }
    public static synchronized void partialWrite(ItemTransactionPacket packet) {
        Partial p=partial;
        if (!p.used || p.client || packet!=p.selected) return;
        if (state(packet)==TransactionState.Accept) p.acceptWrites++;
        else if (state(packet)==TransactionState.Done || state(packet)==TransactionState.Reject) p.terminalWrites++;
    }
    public static synchronized boolean partialUpdateEnter(Transaction tx) {
        Partial p=partial;
        if (!p.used || p.client || tx!=p.selected) return false;
        p.updateCalls++;
        if (!p.armed || p.updateCalls!=1 || p.accepted!=1 || !partialEpoch() || !partialUnique()
                || !partialEntriesUnchanged() || state(tx)!=TransactionState.Accept
                || !at(p.first,p.source) || !at(p.second,p.source)
                || !absent(p.first,p.destination) || !absent(p.second,p.destination)
                || !absent(p.first,p.quarantine) || !absent(p.second,p.quarantine)) {
            partialClose("update-binding-changed"); return true;
        }
        Long start=get(tx,"startTime",(Long)null), end=get(tx,"endTime",(Long)null);
        if (start==null || end==null || end>GameTime.getServerTimeMills()) { partialClose("update-not-native-due"); return true; }
        try {
            // Disposable fixture intervention: a competing move of the exact second
            // physical item. Original update, entries, state and clocks stay native.
            p.source.Remove(p.second);
            InventoryItem moved=p.quarantine.addItem(p.second);
            if (moved!=p.second || !at(p.second,p.quarantine) || !absent(p.second,p.source)) {
                partialClose("competing-move-failed"); return true;
            }
            GameServer.sendRemoveItemFromContainer(p.source,p.second);
            GameServer.sendAddItemToContainer(p.quarantine,p.second);
            p.movedSecond=true;
            if (!partialEntriesUnchanged() || state(tx)!=TransactionState.Accept
                    || !start.equals(get(tx,"startTime",(Long)null)) || !end.equals(get(tx,"endTime",(Long)null)))
                partialClose("native-metadata-changed");
        } catch (Throwable error) { partialClose("competing-move-"+error.getClass().getSimpleName()); }
        return true;
    }
    public static synchronized void partialUpdateExit(Transaction tx,boolean observed,boolean result,Throwable error) {
        Partial p=partial;
        if (!observed || tx!=p.selected) return;
        p.updateThrew=error!=null;
        p.nativeReturnedFalse=error==null && !result;
        if (error!=null || result || !p.movedSecond || !partialEpoch() || !partialEntriesUnchanged()
                || !at(p.first,p.destination) || !absent(p.first,p.source) || !absent(p.first,p.quarantine)
                || !at(p.second,p.quarantine) || !absent(p.second,p.source) || !absent(p.second,p.destination))
            partialClose("native-partial-result-not-proven");
    }
    private static void partialReply(ItemTransactionPacket packet,UdpConnection incoming) {
        Partial p=partial;
        if (!p.used || !p.client || !p.bound || packet==null || incoming!=p.connection
                || transactionId(packet)==null || transactionId(packet)!=p.id) return;
        if (!partialEpoch() || !partialUnique() || !partialEntriesUnchanged()) { partialClose("reply-binding-changed"); return; }
        TransactionState reply=state(packet);
        if (reply==TransactionState.Accept) {
            if (partialPayload(packet)) { p.passedAccept++; p.accepted++; }
            else partialClose("foreign-accept-payload");
        } else if (reply==TransactionState.Done) p.passedDone++;
        else if (reply==TransactionState.Reject) p.passedReject++;
        // Pure observation: every native reply always executes unchanged.
    }
    public static synchronized void managerUpdated() {
        if (GameServer.server) partialBindings();
        Partial p=partial;
        if (!p.used || !p.bound) return;
        if (!partialEpoch()) { partialClose("connection-epoch-changed"); return; }
        if (p.client) {
            if (p.expired && !partialPresent()) { p.managerRemoved=true; p.armed=false; }
        } else if (p.updateCalls>0) {
            p.managerReject=state(p.selected)==TransactionState.Reject;
            p.managerRemoved=!partialPresent();
            if (!p.managerReject || !p.managerRemoved || p.terminalWrites!=0) partialClose("native-manager-result-not-proven");
            else p.armed=false;
        }
    }
    public static synchronized KahluaTable partialSnapshot() {
        Partial p=partial; KahluaTable table=new J2SEPlatform().newTable();
        table.rawset("sourceExact",sourceExact); table.rawset("used",p.used); table.rawset("armed",p.armed);
        table.rawset("bound",p.bound); table.rawset("token",p.token); table.rawset("actor",p.used ? (double)p.actorId : -1.0);
        table.rawset("first",(double)p.firstId); table.rawset("second",(double)p.secondId); table.rawset("transaction",(double)p.id);
        table.rawset("requestCount",(double)p.requestCount); table.rawset("accepted",(double)p.accepted);
        table.rawset("acceptWrites",(double)p.acceptWrites); table.rawset("updateCalls",(double)p.updateCalls);
        table.rawset("terminalWrites",(double)p.terminalWrites); table.rawset("passedAccept",(double)p.passedAccept);
        table.rawset("passedDone",(double)p.passedDone); table.rawset("passedReject",(double)p.passedReject);
        table.rawset("reused",(double)p.reused); table.rawset("movedSecond",p.movedSecond);
        table.rawset("nativeReturnedFalse",p.nativeReturnedFalse); table.rawset("updateThrew",p.updateThrew);
        table.rawset("managerReject",p.managerReject); table.rawset("managerRemoved",p.managerRemoved); table.rawset("expired",p.expired);
        table.rawset("nativePresent",partialPresent()); table.rawset("nativeState",p.selected==null || state(p.selected)==null ? "" : state(p.selected).name());
        table.rawset("failure",failure); table.rawset("closed",p.closed); table.rawset("fault","competing-native-second-move-no-replay");
        return table;
    }
    private static boolean exactInt(Object value) {
        return value instanceof Double number && number==Math.rint(number) && number>0 && number<=Integer.MAX_VALUE;
    }
    private static final Object[] GRAB_CONSTANTS={"ISInventoryPane","getActualItems","getSpecificPlayer","getPlayerInventory",
        "inventory","ipairs","instanceof","InventoryItem","items",2.0,1.0,"getContainer","luautils","walkToContainer",
        "isHumanCorpse","ISTimedActionQueue","add","ISGrabCorpseItem","new","ISInventoryTransferUtil","newInventoryTransferAction"};
    private static final Object[] GRAB_WRAPPER_CONSTANTS={6.0,"kind","player",1.0,"chr","getSpecificPlayer",2.0,"records",
        "pcall","ipairs","enqueued","equip","action","accepted",true,"pending","finished",null,"error",0.0,"unpack","n"};
    private static boolean closureFile(LuaClosure closure,String filename) {
        if (closure==null || closure.prototype==null || closure.prototype.filename==null) return false;
        String path=closure.prototype.filename.replace('\\','/');
        String name=path.substring(path.lastIndexOf('/')+1);
        return name.equals(filename) || name.equals("@"+filename);
    }
    private static final Object[] CLEAN_GRAB_CONSTANTS={"ISInventoryPane","getActualItems","getSpecificPlayer","getPlayerInventory",
        "inventory","ipairs","instanceof","InventoryItem","items",2.0,1.0,"luautils","walkToContainer",
        "isHumanCorpse","ISTimedActionQueue","add","ISGrabCorpseItem","new","ISInventoryTransferUtil","newInventoryTransferAction"};
    private static final WeakHashMap<LuaClosure,LuaClosure> CLEAN_GRAB_HELPERS=new WeakHashMap<>();
    private static boolean grabCode(se.krka.kahlua.vm.Prototype p,String hash) {
        if (p.code==null || p.code.length>512) return false;
        try {
            var bytes=java.nio.ByteBuffer.allocate(p.code.length*4);
            for (int instruction:p.code) bytes.putInt(instruction);
            return hash.equals(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes.array())));
        } catch (Exception error) { return false; }
    }
    private static boolean cleanContainerPrototype(se.krka.kahlua.vm.Prototype p,String method) {
        return p!=null && "pcall".equals(p.name) && p.numParams==0 && !p.isVararg && p.numUpvalues==1
            && p.prototypes!=null && p.prototypes.length==0 && java.util.Arrays.equals(p.constants,new Object[]{method})
            && grabCode(p,"4f44fce860a83c8f323ded18f1509467ca3bdb3d3b50dadc272acc93aad31e8c");
    }
    private static boolean cleanGrabHelper(LuaClosure leaf) {
        if (leaf.upvalues.length!=1 || leaf.upvalues[0]==null || !(leaf.upvalues[0].getValue() instanceof LuaClosure helper)
                || helper.env!=leaf.env || !closureFile(helper,"ISInventoryPaneContextMenu.lua")) return false;
        var p=helper.prototype;
        if (!"CleanUI_getValidTransferContainer".equals(p.name) || p.numParams!=1 || p.isVararg || p.numUpvalues!=0
                || helper.upvalues.length!=0 || !java.util.Arrays.equals(p.constants,new Object[]{"instanceof","InventoryItem","pcall"})
                || !grabCode(p,"600bb164a3509745919b0e74fba7aa93dd066c67c8d9db86ec4e2331d04aa61b")
                || p.prototypes==null || p.prototypes.length!=2 || !cleanContainerPrototype(p.prototypes[0],"getContainer")
                || !cleanContainerPrototype(p.prototypes[1],"getType")) return false;
        LuaClosure saved=CLEAN_GRAB_HELPERS.get(leaf);
        if (saved!=null) return saved==helper;
        CLEAN_GRAB_HELPERS.put(leaf,helper); return true;
    }
    private static boolean directGrab(Object value) {
        if (!(value instanceof LuaClosure closure) || !closureFile(closure,"ISInventoryPaneContextMenu.lua")) return false;
        var p=closure.prototype;
        if (!"onGrabItems".equals(p.name) || p.numParams!=2 || p.isVararg || closure.upvalues==null
                || p.prototypes==null || p.prototypes.length!=0) return false;
        if (p.numUpvalues==0 && closure.upvalues.length==0 && java.util.Arrays.equals(p.constants,GRAB_CONSTANTS)) return true;
        return p.numUpvalues==1 && closure.upvalues.length==1 && java.util.Arrays.equals(p.constants,CLEAN_GRAB_CONSTANTS)
            && grabCode(p,"6d8ea53b90472e1ea143145ef7d543a3bf061f873cf94c188183763c17633a5e") && cleanGrabHelper(closure);
    }
    private static final Object[] GRAB_RETENTION_CONSTANTS={"onMoveItemsTo","select",2.0,1.0,"type","table","selectionAllowsStuck","filterTransfer"};
    private record GrabHelpers(Object protection,Object selection,Object filter) { }
    private static final WeakHashMap<Object,GrabHelpers> GRAB_HELPERS=new WeakHashMap<>();
    private static boolean grabHelper(Object value,String file,String name,int upvalues,Object[] constants,KahluaTable env) {
        if (!(value instanceof LuaClosure closure) || !closureFile(closure,file) || closure.env!=env) return false;
        var p=closure.prototype;
        return name.equals(p.name) && p.numParams==2 && !p.isVararg && p.numUpvalues==upvalues
            && closure.upvalues!=null && closure.upvalues.length==upvalues && p.prototypes!=null && p.prototypes.length==0
            && java.util.Arrays.equals(p.constants,constants);
    }
    private static boolean grabRetentionHelpers(Object retained,Object protection,KahluaTable env) {
        Object selection=own(protection,"selectionAllowsStuck"), filter=own(retained,"filterTransfer");
        if (!grabHelper(selection,"InventoryTransferProtection.lua","selectionAllowsStuck",3,new Object[]{"player","items",null},env)
                || !grabHelper(filter,"ItemRetentionUI.lua","filterTransfer",2,new Object[]{"ipairs","allowsAutomatic",1.0},env)) return false;
        GrabHelpers saved=GRAB_HELPERS.get(retained);
        if (saved!=null) return saved.protection==protection && saved.selection==selection && saved.filter==filter;
        GRAB_HELPERS.put(retained,new GrabHelpers(protection,selection,filter));
        return true;
    }
    private static String grabOriginReason="not-observed",grabOriginChain="",grabOriginLogged="",grabOriginLeaf="",grabOriginCounts="";
    private static boolean grabOriginSupported;
    private static Object own(Object owner,String key) {
        return owner instanceof KahluaTableImpl table && owner.getClass()==KahluaTableImpl.class ? table.delegate.get(key) : null;
    }
    private static boolean grabShape(LuaClosure closure,String file,String name,int params,int upvalues,Object[] constants) {
        if (!closureFile(closure,file)) return false;
        var p=closure.prototype;
        return name.equals(p.name) && p.numParams==params && p.isVararg && p.numUpvalues==upvalues
            && closure.upvalues!=null && closure.upvalues.length==upvalues && p.prototypes!=null && p.prototypes.length==0
            && java.util.Arrays.equals(p.constants,constants);
    }
    private static int grabKind(Object value) {
        if (!(value instanceof LuaClosure closure)) return 0;
        if (directGrab(closure)) return 1;
        if (grabShape(closure,"ActionQueueTidyIntent.lua","replacement",0,13,GRAB_WRAPPER_CONSTANTS)) return 2;
        if (grabShape(closure,"ItemRetentionUI.lua","wrapper",1,4,GRAB_RETENTION_CONSTANTS)) return 3;
        return 0;
    }
    private static String grabMetadata(LuaClosure closure) {
        if (closure==null || closure.prototype==null) return "non-Lua";
        String file="foreign";
        for (String known:List.of("ISInventoryPaneContextMenu.lua","ActionQueueTidyIntent.lua","ItemRetentionUI.lua"))
            if (closureFile(closure,known)) file=known;
        var p=closure.prototype;
        String name=p.name!=null && p.name.matches("[A-Za-z0-9_]{1,32}") ? p.name : "unnamed";
        return file+":"+name+":params="+p.numParams+":upvalues="+(closure.upvalues==null ? -1 : closure.upvalues.length);
    }
    private static LuaClosure grabReject(String reason) { grabOriginReason=reason; grabOriginSupported=false; return null; }
    /** Follow at most one exact TidyIntent and one Retention direct callback.
     * No general graph traversal, table recursion, callback or helper invocation. */
    public static synchronized LuaClosure grabOriginal(Object callback,Object owner) {
        grabOriginChain=""; grabOriginLeaf=""; grabOriginCounts=""; grabOriginSupported=false;
        if (!(callback instanceof LuaClosure closure)) return grabReject("callback-not-Lua");
        if (own(owner,"onGrabItems")!=callback || own(closure.env,"ISInventoryPaneContextMenu")!=owner)
            return grabReject("owner-current-field-mismatch");
        KahluaTable environment=closure.env;
        boolean tidy=false,retention=false;
        var visited=java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<LuaClosure,Boolean>());
        for (int depth=0;depth<3;depth++) {
            if (!grabOriginChain.isEmpty()) grabOriginChain+=" -> ";
            grabOriginChain+=grabMetadata(closure);
            if (!visited.add(closure)) return grabReject("callback-cycle");
            if (closure.env!=environment) return grabReject("callback-environment-mismatch");
            int kind=grabKind(closure);
            if (kind==1) { grabOriginSupported=true; grabOriginReason=""; grabOriginLeaf=closure.upvalues.length==0 ? "stock" : "cleanui-reviewed"; return closure; }
            if (kind==0) return grabReject("unsupported-source-or-prototype");
            if (kind==2 && tidy || kind==3 && retention) return grabReject("duplicate-wrapper-kind");
            if (kind==2) tidy=true; else retention=true;
            Object toolkit=own(environment,"PZSurvivorToolkit");
            Object retained=own(toolkit,"ItemRetention"), protection=own(toolkit,"InventoryTransferProtection");
            if (kind==3 && (!(retained instanceof KahluaTableImpl) || !(protection instanceof KahluaTableImpl)
                    || retained==protection)) return grabReject("retention-current-tables-missing");
            if (kind==3 && !grabRetentionHelpers(retained,protection,environment)) return grabReject("retention-helper-source-or-identity-changed");
            int owners=0,names=0,selves=0,retainedCells=0,protectionCells=0,callbacks=0;
            LuaClosure next=null;
            for (var upvalue:closure.upvalues) {
                Object value=upvalue==null ? null : upvalue.getValue();
                if (value==owner) owners++;
                if ("onGrabItems".equals(value)) names++;
                if (value==closure) selves++;
                if (value==retained) retainedCells++;
                if (value==protection) protectionCells++;
                if (value!=closure && grabKind(value)!=0) { callbacks++; next=(LuaClosure)value; }
            }
            grabOriginCounts="owners="+owners+",names="+names+",selves="+selves+",children="+callbacks;
            StringBuilder direct=new StringBuilder();
            for (int i=0;i<closure.upvalues.length;i++) {
                var cell=closure.upvalues[i]; Object value=cell==null ? null : cell.getValue();
                if (value instanceof LuaClosure child && value!=closure) direct.append(";cell").append(i).append("=").append(grabMetadata(child));
            }
            grabOriginCounts+=direct;
            if (callbacks!=1 || names!=1) return grabReject("wrapper-name-or-direct-callback-ambiguous");
            if (kind==2 && (owners!=1 || selves!=1)) return grabReject("tidy-owner-or-self-mismatch");
            if (kind==3 && (retainedCells!=1 || protectionCells!=1 || owners!=0 || selves!=0))
                return grabReject("retention-table-identity-mismatch");
            closure=next;
        }
        return grabReject("callback-depth-exceeded");
    }
    public static synchronized KahluaTable grabOriginSnapshot() {
        KahluaTable table=new J2SEPlatform().newTable();
        table.rawset("supported",grabOriginSupported); table.rawset("reason",grabOriginReason); table.rawset("chain",grabOriginChain);
        table.rawset("leaf",grabOriginLeaf); table.rawset("counts",grabOriginCounts);
        return table;
    }
    private static final JavaFunction grabOriginState=(frame,count)->frame.push(grabOriginSnapshot());
    private static final JavaFunction grabOriginalFunction=(frame,count)->{
        LuaClosure original=count==2 ? grabOriginal(frame.get(0),frame.get(1)) : grabReject("argument-count");
        if (original==null) {
            String diagnostic=grabOriginReason+" chain="+grabOriginChain+" counts="+grabOriginCounts;
            if (!diagnostic.equals(grabOriginLogged)) { grabOriginLogged=diagnostic; System.out.println("[QueuePeersGrabOrigin] "+diagnostic); }
        }
        return frame.push(original);
    };
    private static final JavaFunction partialState=(frame,count)->frame.push(partialSnapshot());
    private static final JavaFunction partialArmState=(frame,count)->frame.push(partialArmSnapshot());
    private static final JavaFunction partialArmClient=(frame,count)->{
        Object player=count>0 ? frame.get(0) : null, first=count>1 ? frame.get(1) : null;
        Object second=count>2 ? frame.get(2) : null, token=count>3 ? frame.get(3) : null;
        ARM_DIAGNOSTIC.clear(); ARM_DIAGNOSTIC.put("argumentCount",(double)count);
        ARM_DIAGNOSTIC.put("actorClass",player==null ? "nil" : player.getClass().getName());
        ARM_DIAGNOSTIC.put("firstClass",first==null ? "nil" : first.getClass().getName());
        ARM_DIAGNOSTIC.put("secondClass",second==null ? "nil" : second.getClass().getName());
        ARM_DIAGNOSTIC.put("tokenClass",token==null ? "nil" : token.getClass().getName());
        armContext(player instanceof IsoPlayer actor ? actor : null,exactInt(first) ? ((Double)first).intValue() : 0,
            exactInt(second) ? ((Double)second).intValue() : 0,token instanceof String value ? value : null);
        if (count!=4) return frame.push(armRejected("argument-count"));
        if (!(player instanceof IsoPlayer actor)) return frame.push(armRejected("actor-class"));
        if (!exactInt(first) || !exactInt(second)) return frame.push(armRejected("numeric-id-class-or-range"));
        if (!(token instanceof String text)) return frame.push(armRejected("token-class"));
        return frame.push(armPartialClient(actor,((Double)first).intValue(),((Double)second).intValue(),text));
    };
    private static final JavaFunction partialArm=(frame,count)->frame.push(count==7
        && frame.get(0) instanceof IsoPlayer player && frame.get(1) instanceof InventoryItem first && frame.get(2) instanceof InventoryItem second
        && frame.get(3) instanceof ItemContainer source && frame.get(4) instanceof ItemContainer destination
        && frame.get(5) instanceof ItemContainer quarantine && frame.get(6) instanceof String token
        && armPartial(player,first,second,source,destination,quarantine,token));
    public static void partialBindings() {
        if (LuaManager.env==null) return;
        LuaManager.env.rawset("queuePeersGrabOriginal",grabOriginalFunction);
        LuaManager.env.rawset("queuePeersGrabOriginState",grabOriginState);
        LuaManager.env.rawset("queuePeersArmPartial",partialArm);
        LuaManager.env.rawset("queuePeersArmPartialClient",partialArmClient);
        LuaManager.env.rawset("queuePeersPartialArmState",partialArmState);
        LuaManager.env.rawset("queuePeersPartialState",partialState);
    }
    public static class ManagerUpdated {
        @Advice.OnMethodExit(suppress=Throwable.class) public static void exit() { Main.managerUpdated(); }
    }
    public static class ServerReceived {
        @Advice.OnMethodEnter(suppress=Throwable.class) public static boolean enter(@Advice.This ItemTransactionPacket packet,
            @Advice.Argument(1) UdpConnection connection) { return Main.partialServerEnter(packet,connection); }
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Advice.This ItemTransactionPacket packet,
            @Advice.Argument(1) UdpConnection connection,@Advice.Enter boolean observed,@Advice.Thrown Throwable error) {
            Main.partialServerExit(packet,connection,observed,error);
        }
    }
    public static class PacketWritten {
        @Advice.OnMethodEnter(suppress=Throwable.class) public static void enter(@Advice.This ItemTransactionPacket packet) { Main.partialWrite(packet); }
    }
    public static class PartialUpdate {
        @Advice.OnMethodEnter(suppress=Throwable.class) public static boolean enter(@Advice.This Transaction tx) { return Main.partialUpdateEnter(tx); }
        @Advice.OnMethodExit(onThrowable=Throwable.class,suppress=Throwable.class) public static void exit(@Advice.This Transaction tx,
            @Advice.Enter boolean observed,@Advice.Return boolean result,@Advice.Thrown Throwable error) {
            Main.partialUpdateExit(tx,observed,result,error);
        }
    }
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
