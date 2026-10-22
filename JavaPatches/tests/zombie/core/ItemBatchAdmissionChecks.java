package zombie.core;

import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import me.zed_0xff.zombie_buddy.Accessor;
import net.alexredby.pztoolkitjavapatches.ItemBatchAdmission;
import net.bytebuddy.jar.asm.ClassReader;
import net.bytebuddy.jar.asm.ClassVisitor;
import net.bytebuddy.jar.asm.ClassWriter;
import net.bytebuddy.jar.asm.MethodVisitor;
import net.bytebuddy.jar.asm.Opcodes;
import sun.misc.Unsafe;
import zombie.characters.IsoPlayer;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.InventoryContainer;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.PacketTypes;
import zombie.network.ServerOptions;
import zombie.network.fields.ContainerID;
import zombie.network.fields.character.PlayerID;
import zombie.network.packets.ItemTransactionPacket;
import zombie.scripting.objects.CharacterTrait;

/** Exercises native packet validation and native capacity checks, with no copied capacity algorithm. */
public final class ItemBatchAdmissionChecks {
    static Unsafe unsafe;
    static ConcurrentLinkedQueue<Transaction> transactions;
    static Player player;
    static Connection connection;
    static int nextItem = 1000;
    static byte nextPacket = 10;

    public static final class Player extends IsoPlayer {
        Player() { super(null); }
        public boolean hasTrait(CharacterTrait trait) { return false; }
        public boolean isWearingAwkwardGloves() { return false; }
    }
    public static final class Item extends InventoryItem {
        float weight;
        Runnable onWeight;
        Item() { super("Base", "BatchProbe", "BatchProbe", ""); }
        public float getUnequippedWeight() {
            Runnable callback = onWeight;onWeight = null;if (callback != null) callback.run();
            return weight;
        }
        public float getWeight() { return weight; }
        public float getActualWeight() { return weight; }
        public String getType() { return "BatchProbe"; }
        public String getCategory() { return "BatchProbe"; }
    }
    public static final class Connection extends UdpConnection {
        ByteBuffer bytes;
        int replies;
        Transaction.TransactionState replied;
        ItemTransactionPacket expected;
        Connection() { super(null, 0, 0); }
        public ByteBufferWriter startPacket() { bytes.clear();return new ByteBufferWriter(bytes); }
        public void endPacket(int priority, int reliability, byte channel) {
            bytes.flip();var reader = new ByteBufferReader(bytes);
            require(reader.getByte() == (byte)134 && reader.getShort() == PacketTypes.PacketType.ItemTransaction.getId(), "wrong reply framing");
            byte id = reader.getByte();replied = reader.getEnum(Transaction.TransactionState.class);
            require(id == expected.id, "reply transaction id changed");
            if (replied == Transaction.TransactionState.Reject) require(!bytes.hasRemaining(), "Reject gained partial-entry payload");
            var written = ByteBuffer.allocate(1024);expected.write(new ByteBufferWriter(written));written.flip();
            bytes.position(3);require(bytes.equals(written), "reply changed native packet serialization");
            replies++;
        }
    }
    interface Checked { void run() throws Exception; }
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static Field field(Class<?> type, String name) throws Exception {
        Field result = type.getDeclaredField(name);result.setAccessible(true);return result;
    }
    static Item item(ItemContainer source, float weight) throws Exception {
        Item item = (Item)unsafe.allocateInstance(Item.class);item.weight = weight;item.setID(nextItem++);
        item.setContainer(source);source.items.add(item);return item;
    }
    static ItemContainer container(int capacity) {
        ItemContainer container = new ItemContainer();container.type = "crate";container.capacity = capacity;
        return container;
    }
    static Transaction.TransactionEntry entry(Item item, ItemContainer destination) throws Exception {
        var entry = new Transaction.TransactionEntry(item.getID());
        entry.sourceId.containerType = ContainerID.ContainerType.ObjectContainer;entry.destinationId.containerType = ContainerID.ContainerType.ObjectContainer;
        field(ContainerID.class, "container").set(entry.sourceId, item.getContainer());
        field(ContainerID.class, "container").set(entry.destinationId, destination);
        return entry;
    }
    static ItemTransactionPacket packet(Transaction.TransactionEntry... entries) throws Exception {
        var packet = new ItemTransactionPacket();packet.id = nextPacket++;
        packet.state = Transaction.TransactionState.Request;packet.setDuration(1000);
        packet.entries.addAll(List.of(entries));packet.playerId.setID(player.onlineId);
        field(PlayerID.class, "player").set(packet.playerId, player);
        return packet;
    }
    static void process(ItemTransactionPacket packet, Transaction.TransactionState expected, int queued) {
        int replies = connection.replies;var previous = connection.expected;connection.expected = packet;
        var entries = new ArrayList<>(packet.entries);
        try {packet.processServer(PacketTypes.PacketType.ItemTransaction, connection);} finally {connection.expected = previous;}
        require(packet.entries.equals(entries), "admission changed request membership");
        require(packet.state == expected && connection.replied == expected && connection.replies == replies + 1,
            "request did not receive exactly one native " + expected + " reply");
        require(transactions.size() == queued && transactions.contains(packet) == (expected == Transaction.TransactionState.Accept),
            "request admission changed native queue unexpectedly");
    }
    static void unchanged(ItemContainer source, ItemContainer destination, Item... items) {
        require(source.items.equals(List.of(items)) && destination.items.isEmpty(), "admission mutated world inventories");
        for (Item item : items) require(item.getContainer() == source, "admission moved an item");
    }
    static void overflow(boolean patched) throws Exception {
        transactions.clear();var source = container(100);var destination = container(5);
        var a = item(source, 3);var b = item(source, 3);
        require(TransactionManager.isConsistent(a.getID(), null, source, destination, null, null, player) == 0
            && TransactionManager.isConsistent(b.getID(), null, source, destination, null, null, player) == 0,
            "overflow fixture does not fit one item at a time");
        if (patched) {
            a.onWeight = () -> require(Accessor.tryGet(ItemBatchAdmission.class, "requests", (ThreadLocal<?>)null).get() != null, "Request scope absent");
            b.onWeight = () -> require(ItemBatchAdmission.reservations(transactions).hasNext(), "second item prefix absent");
        }
        var request = packet(entry(a, destination), entry(b, destination));
        if (patched) {
            var scope = ItemBatchAdmission.beginRequest(request);require(scope != null, "eligible request refused scope");ItemBatchAdmission.endRequest(scope);
        }
        process(request, patched ? Transaction.TransactionState.Reject : Transaction.TransactionState.Accept, patched ? 0 : 1);
        unchanged(source, destination, a, b);
    }
    static void reservedOverflow() throws Exception {
        transactions.clear();var source = container(100);var destination = container(8);
        var reservedItem = item(source, 3);var a = item(source, 3);var b = item(source, 3);
        var reserved = packet(entry(reservedItem, destination));reserved.state = Transaction.TransactionState.Accept;reserved.playerId.setID((short)20);
        var competitor = (Player)unsafe.allocateInstance(Player.class);competitor.onlineId = 20;
        field(PlayerID.class, "player").set(reserved.playerId, competitor);transactions.add(reserved);
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Reject, 1);
        require(transactions.peek() == reserved && reserved.state == Transaction.TransactionState.Accept, "existing reservation was mutated");
        unchanged(source, destination, reservedItem, a, b);
    }
    static void fitting() throws Exception {
        transactions.clear();var source = container(100);var destination = container(6);
        var a = item(source, 3);var b = item(source, 3);
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Accept, 1);
        unchanged(source, destination, a, b);
        transactions.clear();var other = container(3);
        process(packet(entry(a, destination), entry(b, other)), Transaction.TransactionState.Accept, 1);
        require(other.items.isEmpty(), "independent destination changed");unchanged(source, destination, a, b);
    }
    static void bag() throws Exception {
        transactions.clear();var source = container(100);var destination = container(8);
        var bag = (InventoryContainer)unsafe.allocateInstance(InventoryContainer.class);
        var script = (zombie.scripting.objects.Item)unsafe.allocateInstance(zombie.scripting.objects.Item.class);script.maxItemSize = 5;
        field(InventoryItem.class, "scriptItem").set(bag, script);destination.inventoryContainer = bag;
        var a = item(source, 4);var b = item(source, 4);
        require(destination.hasRoomFor(player, a) && destination.hasRoomFor(player, b)
            && !destination.hasRoomFor(player, 8), "bag fixture does not distinguish item size from batch weight");
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Accept, 1);
        unchanged(source, destination, a, b);
    }
    static void nativeRules() throws Exception {
        transactions.clear();var source = container(100);var destination = container(100);
        var a = item(source, 1);var b = item(source, 1);
        destination.setOnlyAcceptCategory("Food");
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Reject, 0);
        destination.setOnlyAcceptCategory(null);var missing = new Transaction.TransactionEntry(12345);
        missing.sourceId.containerType = ContainerID.ContainerType.ObjectContainer;missing.destinationId.containerType = ContainerID.ContainerType.ObjectContainer;
        field(ContainerID.class, "container").set(missing.sourceId, source);field(ContainerID.class, "container").set(missing.destinationId, destination);
        process(packet(entry(a, destination), missing), Transaction.TransactionState.Reject, 0);
        var single = container(1);process(packet(entry(a, single)), Transaction.TransactionState.Accept, 1);
        unchanged(source, destination, a, b);require(single.items.isEmpty(), "single request moved item");
    }
    static void clean() throws Exception {
        for (String name : new String[] {"requests", "checks"})
            require(((ThreadLocal<?>)field(ItemBatchAdmission.class, name).get(null)).get() == null, name + " scope leaked");
    }
    static void unchecked(Checked action) {
        try { action.run(); } catch (Exception failure) { throw new RuntimeException(failure); }
    }
    static byte[] changed(byte[] bytes, String method) {
        var reader = new ClassReader(bytes);var writer = new ClassWriter(reader, 0);
        reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                var visitor = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals(method)) return visitor;
                return new MethodVisitor(Opcodes.ASM9, visitor) {
                    public void visitCode() { super.visitCode();super.visitInsn(Opcodes.NOP); }
                };
            }
        }, 0);return writer.toByteArray();
    }
    static void weaving() throws Exception {
        byte[] nativeBytes;
        try (var input = ItemBatchAdmissionChecks.class.getClassLoader().getResourceAsStream("zombie/core/TransactionManager.class")) {
            nativeBytes = input.readAllBytes();
        }
        byte[] woven = ItemBatchAdmission.weave(nativeBytes);
        require(woven != null && ItemBatchAdmission.weave(woven) == null, "native weave missing or applied twice");
        require(ItemBatchAdmission.weave(changed(nativeBytes, "isConsistent")) == null, "changed admission method accepted");
        require(ItemBatchAdmission.weave(changed(nativeBytes, "removeItemTransaction")) != null, "independent ownership method conflicts with admission");
        int[] hooks = {0};new ClassReader(woven).accept(new ClassVisitor(Opcodes.ASM9) {
            public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
                return new MethodVisitor(Opcodes.ASM9) {
                    public void visitMethodInsn(int opcode, String owner, String method, String desc, boolean itf) {
                        if (owner.equals("net/alexredby/pztoolkitjavapatches/ItemBatchAdmission") && method.equals("reservations")) {
                            require(name.equals("isConsistent"), "reservation hook escaped consistency method");hooks[0]++;
                        }
                    }
                };
            }
        }, 0);require(hooks[0] == 1, "native reservation iterator was not replaced exactly once");
    }
    static void vehicle() throws Exception {
        transactions.clear();var source = container(100);var destination = container(5);
        destination.parent = (zombie.vehicles.BaseVehicle)unsafe.allocateInstance(zombie.vehicles.BaseVehicle.class);
        destination.sourceGrid = (zombie.iso.IsoGridSquare)unsafe.allocateInstance(zombie.iso.IsoGridSquare.class);
        var a = item(source, 3);var b = item(source, 3);
        process(packet(entry(a, destination), entry(b, destination)), Transaction.TransactionState.Reject, 0);
        unchanged(source, destination, a, b);
    }
    static void scopeChecks() throws Exception {
        transactions.clear();var source = container(100);var destination = container(5);
        var a = item(source, 3);var b = item(source, 3);var outer = packet(entry(a, destination), entry(b, destination));
        // Nested packet processing uses its own connection, so each caller still receives one reply.
        var nestedSource = container(100);var nestedDestination = container(2);
        var c = item(nestedSource, 1);var d = item(nestedSource, 1);var inner = packet(entry(c, nestedDestination), entry(d, nestedDestination));
        var nestedConnection = (Connection)unsafe.allocateInstance(Connection.class);
        nestedConnection.players = connection.players;nestedConnection.bytes = ByteBuffer.allocate(1024);
        b.onWeight = () -> unchecked(() -> {
            require(TransactionManager.isConsistent(a.getID(), null, source, destination, null, outer, player) == 0,
                "reentrant same-packet check inherited outer prefix");
            var previous = connection;connection = nestedConnection;
            try { process(inner, Transaction.TransactionState.Accept, 1); } finally {connection = previous;}
        });
        process(outer, Transaction.TransactionState.Reject, 1);clean();
        require(transactions.peek() == inner, "nested request lost its real queue membership");
        unchanged(source, destination, a, b);unchanged(nestedSource, nestedDestination, c, d);
        transactions.clear();var failing = packet(entry(a, destination), entry(b, destination));
        a.onWeight = () -> { throw new IllegalStateException("native weight failure"); };
        int replies = connection.replies;
        try {failing.processServer(PacketTypes.PacketType.ItemTransaction, connection);throw new AssertionError("native exception swallowed");}
        catch (IllegalStateException expected) {require(expected.getMessage().equals("native weight failure"), "wrong native exception");}
        require(transactions.isEmpty() && replies == connection.replies, "failed validation admitted or replied");clean();
        var excluded = packet(entry(a, destination), entry(b, destination));
        for (var type : new ContainerID.ContainerType[] {ContainerID.ContainerType.Undefined, ContainerID.ContainerType.IsoObject, ContainerID.ContainerType.Floor}) {
            excluded.entries.get(0).sourceId.containerType = type;
            require(ItemBatchAdmission.beginRequest(excluded) == null, "special container entered batch scope");
        }
        excluded.entries.get(0).sourceId.containerType = ContainerID.ContainerType.ObjectContainer;
        source.type = "floor";require(ItemBatchAdmission.beginRequest(excluded) == null, "floor entered batch scope");source.type = "crate";
        excluded.extra = "native-special";require(ItemBatchAdmission.beginRequest(excluded) == null, "special extra entered batch scope");
        clean();
    }
    static void ownership() throws Exception {
        transactions.clear();var source = container(100);var destination = container(100);var item = item(source, 1);
        var own = packet(entry(item, destination));own.state = Transaction.TransactionState.Accept;
        var foreign = packet(entry(item, destination));foreign.id = own.id;foreign.state = Transaction.TransactionState.Accept;
        var other = (Player)unsafe.allocateInstance(Player.class);other.onlineId = 20;
        foreign.playerId.setID(other.onlineId);field(PlayerID.class, "player").set(foreign.playerId, other);
        transactions.add(own);transactions.add(foreign);
        var reject = new ItemTransactionPacket();reject.id = own.id;reject.state = Transaction.TransactionState.Reject;
        reject.processServer(PacketTypes.PacketType.ItemTransaction, connection);
        require(transactions.size() == 1 && transactions.peek() == foreign, "batch advice broke owned Reject cancellation");
        clean();transactions.clear();
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();zombie.core.random.RandLua.INSTANCE.init();
        unsafe = (Unsafe)field(Unsafe.class, "theUnsafe").get(null);
        transactions = Accessor.tryGet(TransactionManager.class, "transactions", transactions);
        require(transactions != null, "native reservation queue unavailable");
        player = (Player)unsafe.allocateInstance(Player.class);player.onlineId = 19;
        field(zombie.iso.IsoObject.class, "ecsComponentMap").set(player, new java.util.HashMap<>());
        connection = (Connection)unsafe.allocateInstance(Connection.class);connection.players = new IsoPlayer[] {player};connection.bytes = ByteBuffer.allocate(1024);
        ServerOptions.getInstance().safehouseAllowLoot.setValue(true);GameServer.server = true;GameClient.client = false;
        overflow(false);transactions.clear();
        weaving();
        if (args.length > 0 && args[0].equals("patch-first")) {
            me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ItemBatchAdmissionChecks.class.getClassLoader());
            require(!ItemBatchAdmission.install(ItemBatchAdmission.SUPPORTED), "changed transformer chain reported enabled");
            overflow(false);clean();transactions.clear();
            System.out.println("ITEM_BATCH_ADMISSION_PATCH_FIRST_PASS (changed transformation order disabled safely)");return;
        }
        require(ItemBatchAdmission.SUPPORTED && ItemBatchAdmission.install(ItemBatchAdmission.SUPPORTED), "native batch reservation patch unsupported");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", ItemBatchAdmissionChecks.class.getClassLoader());
        overflow(true);clean();reservedOverflow();clean();fitting();clean();bag();clean();nativeRules();clean();vehicle();clean();scopeChecks();ownership();
        var instrumentation = Accessor.tryGet(me.zed_0xff.zombie_buddy.Loader.class, "g_instrumentation", (java.lang.instrument.Instrumentation)null);
        require(instrumentation != null, "agent instrumentation unavailable");
        instrumentation.retransformClasses(TransactionManager.class, ItemTransactionPacket.class);
        overflow(true);clean();transactions.clear();
        System.out.println("ITEM_BATCH_ADMISSION_CHECKS_PASS (original overflow, native whole-request Reject/Accept wire, existing reservations, exact fit, per-item bag limit, source/admission rules, vehicle, unchanged inventories, nested/reentrant/exception scopes, ownership compatibility, repeat transformation)");
    }
}
