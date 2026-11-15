package net.alexredby.pztoolkitjavapatches;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import sun.misc.Unsafe;
import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.characters.Stats;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.characters.BodyDamage.BodyPart;
import zombie.characters.BodyDamage.BodyPartType;
import zombie.characters.WornItems.BodyLocationGroup;
import zombie.characters.WornItems.WornItems;
import zombie.core.skinnedmodel.visual.ItemVisual;
import zombie.inventory.ItemContainer;
import zombie.inventory.types.Clothing;
import zombie.scripting.objects.ItemBodyLocation;

/** Native clinical update supplies removal synchronization; no Toolkit patch is applied. */
public final class MedicalVisualChecks {
    private static Unsafe unsafe;

    public static final class Patient extends IsoPlayer {
        BodyDamage damage;
        Stats statistics;
        WornItems worn;
        ItemContainer inventoryData;
        ArrayList<List<Integer>> snapshots;
        int changes;

        Patient() { super(null); }
        @Override public BodyDamage getBodyDamage() { return damage; }
        @Override public Stats getStats() { return statistics; }
        @Override public WornItems getWornItems() { return worn; }
        @Override public ItemContainer getInventory() { return inventoryData; }
        @Override public boolean isLocalPlayer() { return true; }
        @Override public void resetModelNextFrame() { }
        @Override public void onWornItemsChanged() { changes++; }
        // Observe the native synchronization boundary, without claiming network delivery.
        @Override public void syncClothing() {
            ArrayList<Integer> ids = new ArrayList<>();
            for (int i = 0; i < worn.size(); i++) ids.add(worn.getItemByIndex(i).getID());
            snapshots.add(ids);
        }
    }

    public static final class Visual extends Clothing {
        String fullType;
        ItemVisual visual;
        Visual() { super(null, null, null, (String)null, null, null); }
        @Override public String getFullType() { return fullType; }
        @Override public ItemBodyLocation getBodyLocation() { return ItemBodyLocation.BANDAGE; }
        @Override public ItemVisual getVisual() { return visual; }
    }

    private static void require(boolean condition, String detail) {
        if (!condition) throw new AssertionError(detail);
    }

    private static void removal(boolean dirty) throws Exception {
        Patient patient = (Patient)unsafe.allocateInstance(Patient.class);
        patient.statistics = new Stats();
        patient.inventoryData = new ItemContainer();
        patient.snapshots = new ArrayList<>();
        BodyLocationGroup locations = new BodyLocationGroup("native-medical-check");
        locations.getOrCreateLocation(ItemBodyLocation.BANDAGE);
        locations.setMultiItem(ItemBodyLocation.BANDAGE, true);
        patient.worn = new WornItems(locations);
        patient.damage = new BodyDamage(patient);
        BodyPart part = patient.damage.getBodyPart(BodyPartType.ForeArm_L);
        part.setBandaged(true, dirty ? 0f : 10f);
        patient.damage.setBodyPartsLastState();
        part.setBandaged(false, 0f);

        Class<?> type = Class.forName("zombie.characters.IsoGameCharacter$Bandages");
        Constructor<?> constructor = type.getDeclaredConstructor();
        constructor.setAccessible(true);
        Object models = constructor.newInstance();
        String name = part.getType().getBandageModel();
        if (dirty) {
            Method blood = type.getDeclaredMethod("getBloodBandageType", String.class);
            blood.setAccessible(true);
            name = (String)blood.invoke(models, name);
        }
        Visual item = (Visual)unsafe.allocateInstance(Visual.class);
        item.fullType = name;
        item.visual = new ItemVisual();
        item.visual.setItemType(name);
        item.setID(101);
        patient.worn.setItem(ItemBodyLocation.BANDAGE, item);
        patient.inventoryData.getItems().add(item);

        Method update = type.getDeclaredMethod("update", IsoGameCharacter.class);
        update.setAccessible(true);
        update.invoke(models, patient);
        require(!patient.worn.contains(item) && !patient.inventoryData.contains(item),
            "native clinical update retained the removed visual");
        require(patient.changes == 1, "native cleanup notification changed");
        require(patient.snapshots.equals(List.of(List.of())),
            "native clinical update omitted the post-removal clothing snapshot");
        update.invoke(models, patient);
        require(patient.snapshots.size() == 1, "unchanged native update repeated synchronization");
    }

    public static void main(String[] args) throws Exception {
        Field field = Unsafe.class.getDeclaredField("theUnsafe");
        field.setAccessible(true);
        unsafe = (Unsafe)field.get(null);
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        removal(false);
        removal(true);
        System.out.println("MEDICAL_VISUAL_CHECKS_PASS (native clinical removal and synchronization)");
    }
}
