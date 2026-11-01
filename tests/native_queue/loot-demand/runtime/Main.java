package toolkit.lootdemandruntime;

import java.lang.instrument.Instrumentation;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import me.zed_0xff.zombie_buddy.Accessor;
import me.zed_0xff.zombie_buddy.Loader;
import net.alexredby.lootdemand.LootDemand;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.characters.IsoPlayer;
import zombie.inventory.ItemContainer;
import zombie.inventory.ItemPickerJava;
import zombie.iso.IsoObject;
import zombie.iso.IsoWorld;
import zombie.iso.sprite.IsoSpriteManager;
import zombie.core.properties.IsoPropertyType;

/** Disposable fixture loader: the packaged authorization must match its owned cache. */
public final class Main {
    private static boolean active;
    public static void main(String[] args) throws Exception {
        try { installOwned(); }
        catch (Throwable failure) {
            System.err.println("[LOOT_DEMAND] FAILURE " + failure);
            failure.printStackTrace(System.err);
            if(failure instanceof Exception exception) throw exception;
            throw new IllegalStateException("Demand fixture activation failed",failure);
        }
    }
    private static void installOwned() throws Exception {
        Path cache=Path.of(ZomboidFileSystem.instance.getCacheDir()).toRealPath();
        Path marker=cache.resolve("Lua/smoke-user.txt"), token=cache.resolve("loot-demand.opt-in");
        String expected;
        try (var in=Main.class.getResourceAsStream("/loot-demand-token.txt")) {
            if(in==null) throw new IllegalStateException("Missing disposable authorization");
            expected=new String(in.readAllBytes(),java.nio.charset.StandardCharsets.US_ASCII).trim();
        }
        if(!expected.matches("[0-9a-f]{32}") || !Files.isRegularFile(marker,LinkOption.NOFOLLOW_LINKS)
            || !Files.isRegularFile(token,LinkOption.NOFOLLOW_LINKS)
            || !Files.readString(token).trim().equals(expected)
            || !Files.readString(marker).trim().matches("client1|server"))
            throw new IllegalStateException("Loot demand requires an authorized isolated profile");
        Instrumentation inst=Accessor.tryGet(Loader.class,"g_instrumentation",null);
        System.setProperty("pz.lootDemand.enabled","true");
        LootDemand.install(inst);
        if(!LootDemand.installed()) throw new IllegalStateException("Demand hooks inactive: "+LootDemand.diagnostic());
        active=true;
        System.out.println("[LOOT_DEMAND] INSTALLED isolated=true");
    }
    private static void gate() { if(!active || !LootDemand.installed()) throw new IllegalStateException("Demand fixture inactive"); }
    @LuaMethod(name="lootDemandInstalled",global=true)
    public static boolean installed() { return active && LootDemand.installed(); }
    @LuaMethod(name="lootDemandPending",global=true)
    public static boolean pending(ItemContainer container) { gate();return LootDemand.pending(container); }
    @LuaMethod(name="lootDemandEnsure",global=true)
    public static boolean ensure(ItemContainer container,IsoPlayer player) { gate();return LootDemand.ensure(container,player); }
    @LuaMethod(name="lootDemandSprite",global=true)
    public static String sprite(String type) {
        gate();return IsoSpriteManager.instance.namedMap.entrySet().stream()
            .filter(e->type.equals(e.getValue().getProperties().get(IsoPropertyType.CONTAINER)))
            .map(java.util.Map.Entry::getKey).sorted().findFirst().orElseThrow();
    }
    @LuaMethod(name="lootDemandTrashSprite",global=true)
    public static String trashSprite() {
        gate();return IsoSpriteManager.instance.namedMap.entrySet().stream()
            .filter(e->"bin".equals(e.getValue().getProperties().get(IsoPropertyType.CONTAINER))
                && e.getValue().getProperties().has("IsTrashCan"))
            .map(java.util.Map.Entry::getKey).sorted().findFirst().orElseThrow();
    }
    @LuaMethod(name="lootDemandTrash",global=true)
    public static void trash(IsoPlayer player,IsoObject object) {
        gate();if(zombie.network.GameClient.client) throw new IllegalStateException("Authority fixture required");
        var args=zombie.Lua.LuaManager.platform.newTable();var square=object.getSquare();
        args.rawset("x",(double)square.x);args.rawset("y",(double)square.y);args.rawset("z",(double)square.z);
        args.rawset("index",(double)object.getObjectIndex());
        zombie.Lua.LuaEventManager.triggerEvent("OnClientCommand","object","emptyTrash",player,args);
    }
    @LuaMethod(name="lootDemandAutomatic",global=true)
    public static void automatic(IsoObject object,boolean legacy) throws Exception {
        gate();if(legacy) {
            boolean saved=object.getSquare().isOverlayDone();
            try {object.getSquare().setOverlayDone(false);ItemPickerJava.doOverlaySprite(object.getSquare());}
            finally {object.getSquare().setOverlayDone(saved);}
        } else {
            Class<?> picker=Class.forName("zombie.LoadGridsquarePerformanceWorkaround$ItemPicker");
            var field=picker.getDeclaredField("instance");field.setAccessible(true);
            var method=picker.getDeclaredMethod("checkObject",IsoObject.class);method.setAccessible(true);
            method.invoke(field.get(null),object);
        }
    }
    private static void items(ItemContainer container,String prefix,java.util.List<String> rows,int depth,boolean includeTypes) {
        if(depth>32) throw new IllegalStateException("Fixture nesting limit");
        java.util.HashSet<Integer> ids=new java.util.HashSet<>();
        for(var item:container.getItems()) {
            if(!ids.add(item.getID())) throw new IllegalStateException("Duplicate native item ID");
            String key=prefix+item.getID()+(includeTypes?":"+item.getFullType():"");rows.add(key);
            if(item instanceof zombie.inventory.types.InventoryContainer bag) items(bag.getInventory(),key+"/",rows,depth+1,includeTypes);
        }
    }
    @LuaMethod(name="lootDemandRows",global=true)
    public static String rows(ItemContainer container) {
        gate();java.util.List<String> rows=new java.util.ArrayList<>();items(container,"",rows,0,true);java.util.Collections.sort(rows);
        return String.join("\n",rows);
    }
    @LuaMethod(name="lootDemandFingerprint",global=true)
    public static String fingerprint(ItemContainer container) throws Exception {
        return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256")
            .digest(rows(container).getBytes(java.nio.charset.StandardCharsets.UTF_8)));
    }
    private static String shape(ItemContainer container) {
        java.util.List<String> rows=new java.util.ArrayList<>();items(container,"",rows,0,false);java.util.Collections.sort(rows);
        return String.join("\n",rows);
    }
    private static ItemContainer roundtrip(ItemContainer container) throws Exception {
        gate();String before=rows(container),identities=shape(container);
        ByteBuffer out=ByteBuffer.allocate(8*1024*1024);container.save(out);out.flip();
        ItemContainer copy=new ItemContainer();copy.load(out,IsoWorld.getWorldVersion());
        if(out.hasRemaining() || !rows(container).equals(before) || !shape(copy).equals(identities)
            || copy.isExplored()!=container.isExplored() || !copy.getType().equals(container.getType()))
            throw new IllegalStateException("Native serialization changed source, identities, nesting or container state");
        return copy;
    }
    @LuaMethod(name="lootDemandRoundtripRows",global=true)
    public static String roundtripRows(ItemContainer container) throws Exception { return rows(roundtrip(container)); }
    @LuaMethod(name="lootDemandMoveableRoundtrip",global=true)
    public static boolean moveableRoundtrip() throws Exception {
        gate();ItemContainer container=new ItemContainer();
        var item=zombie.inventory.InventoryItemFactory.CreateItem("Base.Mov_PalletEmpty");
        if(!(item instanceof zombie.inventory.types.Moveable moveable)
            || !item.getFullType().equals("Base.Mov_PalletEmpty")
            || !moveable.getWorldSprite().equals("construction_01_5")) return false;
        container.AddItem(item);
        ItemContainer copy=roundtrip(container);
        var restored=copy.getItems().getFirst();
        return restored instanceof zombie.inventory.types.Moveable moved
            && restored.getID()==item.getID() && restored.getFullType().equals("Base.construction_01_5")
            && moved.getWorldSprite().equals(moveable.getWorldSprite());
    }
    @LuaMethod(name="lootDemandSerialized",global=true)
    public static boolean serialized(ItemContainer container) throws Exception {
        gate();ByteBuffer out=ByteBuffer.allocate(8*1024*1024);container.save(out);out.flip();
        ItemContainer copy=new ItemContainer();copy.load(out,IsoWorld.getWorldVersion());
        if(out.hasRemaining() || copy.isExplored()!=container.isExplored()
            || !copy.getType().equals(container.getType()) || copy.getItems().size()!=container.getItems().size()) return false;
        for(int i=0;i<copy.getItems().size();i++) {
            var a=copy.getItems().get(i);var b=container.getItems().get(i);
            if(a.getID()!=b.getID() || !a.getFullType().equals(b.getFullType())) return false;
        }
        return true; // ItemContainer native serialization only, not a world restart.
    }
}
