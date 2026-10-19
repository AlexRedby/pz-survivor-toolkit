package zombie.iso.objects;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import net.alexredby.pztoolkitjavapatches.BytecodeSupport;
import net.alexredby.pztoolkitjavapatches.HutchCleanup;
import net.alexredby.pztoolkitjavapatches.Main;
import sun.misc.Unsafe;
import zombie.characters.animals.IsoAnimal;
import zombie.core.PerformanceSettings;
import zombie.iso.IsoCell;
import zombie.iso.IsoChunk;
import zombie.iso.IsoObject;
import zombie.popman.animal.HutchManager;

public final class HutchChecks {
    static Unsafe unsafe;
    static IsoCell cell;
    static CountingSet removals;

    static final class CountingSet extends HashSet<IsoObject> {
        int calls;
        public boolean add(IsoObject object) { calls++; return super.add(object); }
    }

    static final class Hutch extends IsoHutch {
        Hutch() { super(null); }
        public IsoCell getCell() { return cell; }
        public IsoChunk getChunk() { return null; }
        public void clearOnOverlay() { }
        protected void removeLightSourceFromWorld() { }
        public boolean couldBePoweredByGenerator() { return false; }
        public void flagForHotSave() { }
    }

    static final class Animal extends IsoAnimal {
        int removals;
        RuntimeException failure;
        Animal() { super(null); }
        public void removeFromUpdateLists() {
            removals++;
            if (failure != null) throw failure;
        }
    }

    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    static Hutch hutch() throws Exception {
        Hutch hutch = new Hutch();
        Field set = IsoCell.class.getDeclaredField("processIsoObjectSet"); set.setAccessible(true);
        ((java.util.Set<IsoObject>)set.get(cell)).add(hutch);
        cell.addToStaticUpdaterObjectList(hutch);
        HutchManager.getInstance().add(hutch);
        return hutch;
    }

    static Animal animal() throws Exception {
        return (Animal)unsafe.allocateInstance(Animal.class);
    }

    static void unload(boolean meta) throws Exception {
        Hutch hutch = hutch();
        Animal first = animal(), last = animal();
        hutch.animalInside.put(0, first);
        hutch.animalInside.put(1, null);
        hutch.animalInside.put(2, last);
        hutch.animalInsideSize = 3;
        var original = hutch.animalInside;
        var contents = new HashMap<>(original);
        int before = removals.calls;
        if (meta) hutch.removeFromWorldToMeta(); else hutch.removeFromWorld();
        require(first.removals == 1 && last.removals == 1, "valid animals not cleaned exactly once");
        require(removals.calls == before + 1 && removals.contains(hutch), "native superclass cleanup skipped or repeated");
        require(!cell.getStaticUpdaterObjectList().contains(hutch), "native static updater cleanup skipped");
        require(hutch.animalInside == original && original.equals(contents), "animal slots or identity changed");
        require(hutch.animalInsideSize == 3, "stored count changed");
        Field list = HutchManager.class.getDeclaredField("hutchList"); list.setAccessible(true);
        require(!((java.util.List<?>)list.get(HutchManager.getInstance())).contains(hutch), "manager cleanup skipped");
    }

    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Field field = Unsafe.class.getDeclaredField("theUnsafe"); field.setAccessible(true);
        unsafe = (Unsafe)field.get(null);
        cell = (IsoCell)unsafe.allocateInstance(IsoCell.class);
        removals = new CountingSet();
        for (String name : new String[]{"processIsoObjectSet", "staticUpdaterObjectSet", "processIsoObjectRemove", "staticUpdaterObjectList"}) {
            Field list = IsoCell.class.getDeclaredField(name); list.setAccessible(true);
            list.set(cell, name.equals("processIsoObjectRemove") ? removals
                : name.endsWith("List") ? new ArrayList<>() : new HashSet<>());
        }
        PerformanceSettings.fboRenderChunk = false;

        Hutch baseline = hutch();
        baseline.animalInside.put(0, null);
        try {
            baseline.removeFromWorldToMeta();
            throw new AssertionError("native null slot did not reproduce crash");
        } catch (NullPointerException expected) {
            require(expected.getStackTrace()[0].getClassName().equals(IsoHutch.class.getName()), "wrong native failure");
        }
        require(baseline.animalInside.containsKey(0), "baseline slot lost");

        me.zed_0xff.zombie_buddy.PatchEngine.applyPatches("net.alexredby.pztoolkitjavapatches", HutchChecks.class.getClassLoader());
        require(Main.HUTCH_SUPPORTED, "unsupported native engine");
        require(!BytecodeSupport.supports("zombie/iso/objects/IsoHutch.class", "unknown"), "unknown fingerprint accepted");
        for (int mode = 0; mode < 3; mode++) {
            zombie.network.GameClient.client = mode == 0;
            zombie.network.GameServer.server = mode == 2;
            unload(false);
            unload(true);
        }

        Hutch empty = hutch();
        var original = empty.animalInside;
        empty.removeFromWorld();
        require(empty.animalInside == original && original.isEmpty(), "empty map replaced");
        Animal valid = animal();
        empty.animalInside.put(7, valid);
        empty.removeFromWorld();
        require(valid.removals == 1 && empty.animalInside == original, "valid-only cleanup changed");
        empty.animalInside.put(7, null);
        empty.removeFromWorld();
        empty.removeFromWorld();
        require(empty.animalInside == original && original.size() == 1 && original.containsKey(7), "repeated null-only unload changed slots");

        Hutch failing = hutch();
        Animal broken = animal();
        broken.failure = new IllegalStateException("unrelated animal cleanup error");
        failing.animalInside.put(0, broken);
        failing.animalInside.put(1, null);
        original = failing.animalInside;
        try {
            failing.removeFromWorld();
            throw new AssertionError("unrelated exception swallowed");
        } catch (IllegalStateException expected) {
            require(expected == broken.failure, "unrelated exception replaced");
        }
        require(failing.animalInside == original && original.size() == 2 && broken.removals == 1, "exception did not restore slots");

        require(HutchCleanup.begin(failing, false) == null && failing.animalInside == original, "unsupported engine changed map");
        failing.animalInside = new LinkedHashMap<>(original);
        original = failing.animalInside;
        require(HutchCleanup.begin(failing, true) == null && failing.animalInside == original, "custom map changed");
        failing.animalInside = null;
        require(HutchCleanup.begin(failing, true) == null, "null map interpreted as empty");
        System.out.println("HUTCH_CHECKS_PASS (native crash, woven direct/meta unload, client/SP/server, exact cleanup, slot restoration, repeat unload, unrelated errors, unsupported/custom guards)");
    }
}
