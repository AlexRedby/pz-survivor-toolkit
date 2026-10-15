package zombie.characters;

import java.lang.reflect.Field;
import java.util.ArrayList;
import sun.misc.Unsafe;
import zombie.characters.animals.IsoAnimal;
import zombie.network.GameClient;
import zombie.network.packets.character.AnimalPacket;
import zombie.vehicles.BaseVehicle;
import net.alexredby.pztoolkitjavapatches.Main;

public final class AnimalChecks {
    static Unsafe unsafe;
    static final class Animal extends IsoAnimal {
        Animal() { super(null); }
        public float getAnimalTrailerSize() { return 3; }
    }
    static void set(Class<?> owner, Object target, String name, Object value) throws Exception {
        Field field = owner.getDeclaredField(name); field.setAccessible(true); field.set(target, value);
    }
    static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    static Animal animal() throws Exception { return (Animal)unsafe.allocateInstance(Animal.class); }
    static BaseVehicle trailer(Animal animal, Animal other) throws Exception {
        BaseVehicle vehicle = (BaseVehicle)unsafe.allocateInstance(BaseVehicle.class);
        set(BaseVehicle.class, vehicle, "animals", new ArrayList<>(java.util.List.of(animal, other)));
        vehicle.setCurrentTotalAnimalSize(6);
        animal.setVehicle(vehicle); other.setVehicle(vehicle);
        return vehicle;
    }
    static NetworkPlayerAI ai(IsoGameCharacter animal) throws Exception {
        NetworkPlayerAI ai = (NetworkPlayerAI)unsafe.allocateInstance(NetworkPlayerAI.class);
        set(NetworkCharacterAI.class, ai, "character", animal);
        return ai;
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init();
        zombie.core.random.RandLua.INSTANCE.init();
        Field field = Unsafe.class.getDeclaredField("theUnsafe"); field.setAccessible(true);
        unsafe = (Unsafe)field.get(null); GameClient.client = true;
        require(Main.ANIMAL_SUPPORTED, "unsupported animal decoder baseline");
        for (byte location : new byte[]{0, 1, 3}) {
            Animal animal = animal(), other = animal(); animal.onlineId = 42; animal.animalId = 123;
            BaseVehicle vehicle = trailer(animal, other); NetworkPlayerAI ai = ai(animal);
            vehicle.getAnimals().add(animal); vehicle.setCurrentTotalAnimalSize(9);
            AnimalPacket packet = new AnimalPacket(); packet.location = location;
            Main.AnimalTrailerLocation.enter(ai, packet);
            require(animal.getVehicle() == null && !vehicle.getAnimals().contains(animal), "stale trailer membership retained");
            require(vehicle.getAnimals().size() == 1 && vehicle.getAnimals().get(0) == other && other.getVehicle() == vehicle,
                "unrelated animal changed");
            require(vehicle.getCurrentTotalAnimalSize() == 3, "capacity not recomputed");
            require(animal.onlineId == 42 && animal.animalId == 123, "animal identity changed");
            Main.AnimalTrailerLocation.enter(ai, packet);
            require(vehicle.getAnimals().size() == 1 && vehicle.getCurrentTotalAnimalSize() == 3, "repeat snapshot changed capacity");
        }
        for (byte location : new byte[]{2, -1, 4}) {
            Animal animal = animal(), other = animal(); BaseVehicle vehicle = trailer(animal, other);
            AnimalPacket packet = new AnimalPacket(); packet.location = location;
            Main.AnimalTrailerLocation.enter(ai(animal), packet);
            require(animal.getVehicle() == vehicle && vehicle.getAnimals().size() == 2 && vehicle.getCurrentTotalAnimalSize() == 6,
                "trailer or unknown location mutated");
        }
        Animal animal = animal(), other = animal(); BaseVehicle vehicle = trailer(animal, other);
        AnimalPacket packet = new AnimalPacket(); packet.location = 3; GameClient.client = false;
        Main.AnimalTrailerLocation.enter(ai(animal), packet);
        require(animal.getVehicle() == vehicle && vehicle.getAnimals().size() == 2, "server behavior changed");
        GameClient.client = true;
        Main.AnimalTrailerLocation.enter(ai((IsoPlayer)unsafe.allocateInstance(IsoPlayer.class)), packet);
        Main.AnimalTrailerLocation.enter(ai(animal), null);
        require(!Main.AnimalTrailerLocation.disabled, "valid snapshots disabled reconciliation");
        System.out.println("ANIMAL_CHECKS_PASS (world/hutch/item, identity, duplicate membership, capacity, repeat, trailer/unknown, server/player guards)");
    }
}
