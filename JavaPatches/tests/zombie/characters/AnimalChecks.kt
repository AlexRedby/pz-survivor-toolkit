package zombie.characters

import java.util.ArrayList
import net.alexredby.pztoolkitjavapatches.Main
import sun.misc.Unsafe
import zombie.characters.animals.IsoAnimal
import zombie.network.GameClient
import zombie.network.packets.character.AnimalPacket
import zombie.vehicles.BaseVehicle

object AnimalChecks {
    @JvmField var unsafe: Unsafe? = null

    class Animal : IsoAnimal(null) {
        override fun getAnimalTrailerSize(): Float = 3f
    }

    @JvmStatic
    fun set(owner: Class<*>, target: Any?, name: String?, value: Any?) {
        val field = owner.getDeclaredField(name)
        field.setAccessible(true)
        field.set(target, value)
    }

    @JvmStatic
    fun require(condition: Boolean, message: String) {
        if (!condition) throw AssertionError(message)
    }

    @JvmStatic
    fun animal(): Animal =
        (unsafe ?: throw NullPointerException()).allocateInstance(Animal::class.java) as Animal

    @JvmStatic
    fun trailer(animal: Animal, other: Animal): BaseVehicle {
        val vehicle =
            (unsafe ?: throw NullPointerException()).allocateInstance(BaseVehicle::class.java)
                as BaseVehicle
        set(
            BaseVehicle::class.java,
            vehicle,
            "animals",
            ArrayList(java.util.List.of(animal, other)),
        )
        vehicle.setCurrentTotalAnimalSize(6f)
        animal.setVehicle(vehicle)
        other.setVehicle(vehicle)
        return vehicle
    }

    @JvmStatic
    fun ai(animal: IsoGameCharacter?): NetworkPlayerAI {
        val ai =
            (unsafe ?: throw NullPointerException()).allocateInstance(NetworkPlayerAI::class.java)
                as NetworkPlayerAI
        set(NetworkCharacterAI::class.java, ai, "character", animal)
        return ai
    }

    @JvmStatic
    fun main(args: Array<String>) {
        zombie.core.random.RandStandard.INSTANCE.init()
        zombie.core.random.RandLua.INSTANCE.init()
        val field = Unsafe::class.java.getDeclaredField("theUnsafe")
        field.setAccessible(true)
        unsafe = field.get(null) as Unsafe
        GameClient.client = true
        require(Main.ANIMAL_SUPPORTED, "unsupported animal decoder baseline")
        for (location in byteArrayOf(0, 1, 3)) {
            val animal = animal()
            val other = animal()
            animal.onlineId = 42
            animal.animalId = 123
            val vehicle = trailer(animal, other)
            val ai = ai(animal)
            vehicle.getAnimals().add(animal)
            vehicle.setCurrentTotalAnimalSize(9f)
            val packet = AnimalPacket()
            packet.location = location
            Main.AnimalTrailerLocation.enter(ai, packet)
            require(
                animal.getVehicle() == null && !vehicle.getAnimals().contains(animal),
                "stale trailer membership retained",
            )
            require(
                vehicle.getAnimals().size == 1 &&
                    vehicle.getAnimals()[0] === other &&
                    other.getVehicle() === vehicle,
                "unrelated animal changed",
            )
            require(vehicle.getCurrentTotalAnimalSize() == 3f, "capacity not recomputed")
            require(
                animal.onlineId.toInt() == 42 && animal.animalId == 123,
                "animal identity changed",
            )
            Main.AnimalTrailerLocation.enter(ai, packet)
            require(
                vehicle.getAnimals().size == 1 && vehicle.getCurrentTotalAnimalSize() == 3f,
                "repeat snapshot changed capacity",
            )
        }
        for (location in byteArrayOf(2, -1, 4)) {
            val animal = animal()
            val other = animal()
            val vehicle = trailer(animal, other)
            val packet = AnimalPacket()
            packet.location = location
            Main.AnimalTrailerLocation.enter(ai(animal), packet)
            require(
                animal.getVehicle() === vehicle &&
                    vehicle.getAnimals().size == 2 &&
                    vehicle.getCurrentTotalAnimalSize() == 6f,
                "trailer or unknown location mutated",
            )
        }
        val animal = animal()
        val other = animal()
        val vehicle = trailer(animal, other)
        val packet = AnimalPacket()
        packet.location = 3
        GameClient.client = false
        Main.AnimalTrailerLocation.enter(ai(animal), packet)
        require(
            animal.getVehicle() === vehicle && vehicle.getAnimals().size == 2,
            "server behavior changed",
        )
        GameClient.client = true
        Main.AnimalTrailerLocation.enter(
            ai(
                (unsafe ?: throw NullPointerException()).allocateInstance(IsoPlayer::class.java)
                    as IsoPlayer,
            ),
            packet,
        )
        Main.AnimalTrailerLocation.enter(ai(animal), null)
        require(!Main.AnimalTrailerLocation.disabled, "valid snapshots disabled reconciliation")
        println(
            "ANIMAL_CHECKS_PASS (world/hutch/item, identity, duplicate membership, capacity, repeat, trailer/unknown, server/player guards)",
        )
    }
}
