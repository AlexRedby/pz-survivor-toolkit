package net.alexredby.pztoolkitjavapatches

import java.util.HashMap
import zombie.characters.animals.IsoAnimal
import zombie.iso.objects.IsoHutch

object HutchCleanup {
    @JvmStatic
    fun begin(hutch: IsoHutch, supported: Boolean): HashMap<Int, IsoAnimal?>? {
        val original = hutch.animalInside
        // Do not reinterpret custom map behavior or guess after an engine update.
        if (
            !supported ||
                original == null ||
                original.javaClass != HashMap::class.java ||
                !original.containsValue(null)
        )
            return null

        // B42.21 iterates every value without checking for empty slots. Give only this
        // native unload call a non-null snapshot; keep the original slots and map identity.
        val present = HashMap(original)
        present.values.removeIf { it == null }
        hutch.animalInside = present
        return original
    }
}
