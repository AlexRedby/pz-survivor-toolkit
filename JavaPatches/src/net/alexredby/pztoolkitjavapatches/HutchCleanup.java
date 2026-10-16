package net.alexredby.pztoolkitjavapatches;

import java.util.HashMap;
import java.util.Objects;
import zombie.characters.animals.IsoAnimal;
import zombie.iso.objects.IsoHutch;

public final class HutchCleanup {
    private HutchCleanup() { }

    public static HashMap<Integer, IsoAnimal> begin(IsoHutch hutch, boolean supported) {
        var original = hutch.animalInside;
        // Do not reinterpret custom map behavior or guess after an engine update.
        if (!supported || original == null || original.getClass() != HashMap.class
            || !original.containsValue(null)) return null;

        // B42.21 iterates every value without checking for empty slots. Give only this
        // native unload call a non-null snapshot; keep the original slots and map identity.
        var present = new HashMap<>(original);
        present.values().removeIf(Objects::isNull);
        hutch.animalInside = present;
        return original;
    }
}
