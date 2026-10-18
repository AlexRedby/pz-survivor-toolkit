package zombie.characters;

import gnu.trove.map.hash.THashMap;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import net.alexredby.pztoolkitjavapatches.Main;
import net.alexredby.pztoolkitjavapatches.MedicalVisuals;
import sun.misc.Unsafe;
import zombie.characters.WornItems.BodyLocationGroup;
import zombie.characters.WornItems.WornItems;
import zombie.core.network.ByteBufferWriter;
import zombie.core.raknet.UdpConnection;
import zombie.core.skinnedmodel.visual.ItemVisual;
import zombie.inventory.InventoryItem;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.Clothing;
import zombie.network.GameClient;
import zombie.network.GameServer;
import zombie.network.IConnection;
import zombie.network.PacketTypes.PacketType;
import zombie.network.packets.INetworkPacket;
import zombie.network.packets.SyncClothingPacket;
import zombie.scripting.objects.ItemBodyLocation;

public final class MedicalVisualChecks {
    static Unsafe unsafe;
    static Method remove;
    static Connection connection;
    static final class Patient extends IsoPlayer {
        WornItems worn;
        ItemContainer inventory;
        boolean local;
        boolean failNotification;
        int notifications;
        Patient() { super(null); }
        public boolean isLocalPlayer() { return local; }
        public java.util.HashMap<Class<? extends zombie.characters.ecs.ECSComponent>, zombie.characters.ecs.ECSComponent> getECSComponentMap() { return new java.util.HashMap<>(); }
        public WornItems getWornItems() { return worn; }
        public ItemContainer getInventory() { return inventory; }
        public void resetModelNextFrame() { }
        public void onWornItemsChanged() {
            notifications++;
            if (failNotification) throw new IllegalStateException("native cleanup sentinel");
        }
    }
    static final class Visual extends Clothing {
        String type;
        ItemVisual visual;
        Visual() { super(null, null, null, (String)null, null, null); }
        public String getFullType() { return type; }
        public ItemBodyLocation getBodyLocation() { return ItemBodyLocation.BANDAGE; }
        public ItemVisual getVisual() { return visual; }
    }
    static final class Connection extends UdpConnection {
        boolean ready;
        List<List<Integer>> sent;
        SyncClothingPacket active;
        ByteBuffer outgoing;
        Connection() { super(null, 0, 0); }
        public boolean isReady() { return ready; }
        public INetworkPacket getPacket(PacketType type) {
            require(type == PacketType.SyncClothing, "unexpected packet");
            active = new SyncClothingPacket(); return active;
        }
        public ByteBufferWriter startPacket() { outgoing = ByteBuffer.allocate(4096); return new ByteBufferWriter(outgoing); }
        public boolean isLimitExceeded(PacketType type) { return false; }
        public boolean isHashEquals(PacketType type, Integer hash) { return false; }
        public void cancelPacket() { throw new AssertionError("native clothing serialization failed"); }
        public void endPacket(int priority, int reliability, byte ordering) {
            outgoing.flip();
            require(outgoing.get() == (byte)134 && outgoing.getShort() == PacketType.SyncClothing.getId(), "wrong native packet header");
            outgoing.getShort(); outgoing.get();
            var descriptions = (ArrayList<?>)get(SyncClothingPacket.class, active, "items");
            require(Byte.toUnsignedInt(outgoing.get()) == descriptions.size(), "native wire count differs");
            var ids = new ArrayList<Integer>();
            for (var item : descriptions) ids.add((Integer)get(item.getClass(), item, "itemId"));
            sent.add(ids);
        }
    }
    static void require(boolean value, String reason) { if (!value) throw new AssertionError(reason); }
    static Object get(Class<?> owner, Object object, String name) {
        try { Field f = owner.getDeclaredField(name); f.setAccessible(true); return f.get(object); }
        catch (Exception e) { throw new AssertionError(e); }
    }
    static Patient patient() throws Exception {
        var p = (Patient)unsafe.allocateInstance(Patient.class); p.local = true; p.onlineId = 42;
        var group = new BodyLocationGroup("medical-check"); group.getOrCreateLocation(ItemBodyLocation.BANDAGE); group.setMultiItem(ItemBodyLocation.BANDAGE, true);
        p.worn = new WornItems(group); p.inventory = new ItemContainer(); return p;
    }
    static Visual visual(Patient p, int id) throws Exception {
        var item = (Visual)unsafe.allocateInstance(Visual.class); item.type = "Base.Bandage_LeftLowerArm"; item.setID(id);
        item.visual = new ItemVisual(); item.visual.setItemType(item.type); item.visual.setTint(zombie.core.ImmutableColor.white);
        p.worn.setItem(ItemBodyLocation.BANDAGE, item); p.inventory.getItems().add(item); return item;
    }
    static Object models(InventoryItem item) throws Exception {
        var type = Class.forName("zombie.characters.IsoGameCharacter$Bandages");
        var ctor = type.getDeclaredConstructor(); ctor.setAccessible(true); var models = ctor.newInstance();
        @SuppressWarnings("unchecked") var map = (THashMap<String, InventoryItem>)get(type, models, "itemMap");
        map.put(item.getFullType(), item); return models;
    }
    static void removed(Patient p, Object models, InventoryItem item) throws Exception {
        int before = p.notifications; remove.invoke(models, p, item.getFullType());
        require(!p.worn.contains(item) && !p.inventory.getItems().contains(item), "native visual removal lost");
        require(p.notifications == before + 1, "native cleanup notification lost");
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); zombie.core.random.RandLua.INSTANCE.init();
        Field f = Unsafe.class.getDeclaredField("theUnsafe"); f.setAccessible(true); unsafe = (Unsafe)f.get(null);
        connection = (Connection)unsafe.allocateInstance(Connection.class); connection.ready = true; connection.sent = new ArrayList<>();
        GameClient.client = true; GameClient.connection = connection;
        var type = Class.forName("zombie.characters.IsoGameCharacter$Bandages");
        remove = type.getDeclaredMethod("removeBandageModel", IsoGameCharacter.class, String.class); remove.setAccessible(true);
        require(Main.MEDICAL_VISUALS_SUPPORTED, "unsupported native removal baseline");
        var original = patient(); var item = visual(original, 100); var nativeModels = models(item);
        removed(original, nativeModels, item); require(connection.sent.isEmpty(), "native removal unexpectedly synced");
        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", MedicalVisualChecks.class.getClassLoader());
        var p = patient(); var one = visual(p, 101); var two = visual(p, 102); var keep = visual(p, 103);
        var first = models(one); var second = models(two);
        require(MedicalVisuals.before(first, p, one.type, false) == null, "unsupported code accepted");
        require(MedicalVisuals.before(first, p, one.type, true) == one, "direct before failed");
        removed(p, first, one); require(connection.sent.equals(List.of(List.of(102, 103))), "first native clothing snapshot wrong: " + connection.sent);
        removed(p, second, two); require(connection.sent.equals(List.of(List.of(102, 103), List.of(103))), "duplicate model removal snapshot wrong");
        require(p.worn.contains(keep) && p.inventory.getItems().contains(keep), "unrelated model removed");
        remove.invoke(first, p, "Base.NotPresent"); remove.invoke(first, p, one.type);
        require(connection.sent.size() == 2, "missing/already removed model sent a snapshot");
        for (String mode : List.of("remote", "sp", "server", "offline", "unready", "unknownId")) {
            var control = patient(); var current = visual(control, 200); var state = models(current);
            control.local = !mode.equals("remote"); control.onlineId = (short)(mode.equals("unknownId") ? -1 : 42);
            GameClient.client = !mode.equals("sp"); GameServer.server = mode.equals("server");
            GameClient.connection = mode.equals("offline") ? null : connection; connection.ready = !mode.equals("unready");
            removed(control, state, current); require(connection.sent.size() == 2, mode + " emitted a snapshot");
        }
        var partial = patient(); partial.failNotification = true; var partialItem = visual(partial, 300);
        try { remove.invoke(models(partialItem), partial, partialItem.type); throw new AssertionError("native failure suppressed"); }
        catch (java.lang.reflect.InvocationTargetException expected) {
            require(expected.getCause() instanceof IllegalStateException && expected.getCause().getMessage().equals("native cleanup sentinel"), "unexpected native failure");
        }
        require(!partial.worn.contains(partialItem) && !partial.inventory.getItems().contains(partialItem)
            && connection.sent.size() == 2, "failed cleanup changed native effects or sent a partial snapshot");
        System.out.println("MEDICAL_VISUAL_CHECKS_PASS (native missing sync, woven exact ordered IDs, duplicates, cleanup/failure, no-op, remote/SP/server/disconnected/unsupported guards)");
    }
}
