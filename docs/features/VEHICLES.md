# Vehicles and carts

[Features](../FEATURES.md) · [Installation](../../MOD_INSTALL.md)

Toolkit integration with Navigator, SaucedCarts and the vehicle mechanics window. For third-party requirements and settings, use the [selected mod catalog](../MODPACK.md).

- [Navigator](#navigator)
- [SaucedCarts](#saucedcarts)
- [Vehicle mechanics](#vehicle-mechanics)

## Navigator

**Fit Navigator to vehicle dashboard**, shown only with Navigator installed, preserves Navigator's original textured, bevelled monitor housing in a compact shape and tints/positions it for the vanilla dashboard and each Realistic Dashboard driver style. One continuous textured mount sits behind the curved panel edge without covering its controls. Map size follows the dashboard setting within readable bounds; labels and power button retain their native sizes. Routing, animation and dragging stay with Navigator. Disabling the option restores its original UI immediately. Keep `RealisticDash` before `Navigator`. Other dashboard mods and split-screen layouts have not been validated.

## SaucedCarts

With **SaucedCarts**, dedicated servers initialize the upstream drop, unequip and forced-drop hooks. Worn carts spill their cargo on ordinary drops, and stale hand references cannot create a second ground cart. MP clients recognize their own cart after server-completed pickup/equip, avoiding a false cancellation. With Tidy Up Meister, cancellation clears hand references to carts already dropped for a tool, preserving the cart and cargo on the ground. Use Push Cart again to resume pushing.

**Cart world spawns:** shopping carts use retail and warehouse buildings; standalone sheds and farm storage retain wooden/metal SaucedWheelbarrow spawns. Outdoor carts require a nearby building eligible for that type (a three-chunk margin, roughly 24 tiles, includes adjacent parking). Ordinary distant driveways no longer receive these carts. Existing carts and saved spawn decisions remain intact; restart the game/server and explore undecided areas for the new distribution. Spawn rate, building limits and world-spawning switches retain their native effects.

**Cart motion:** selected shopping carts and wheelbarrows use load-dependent acceleration and steering. Shopping carts pivot near the front wheels; wheelbarrows lean into a turn. Native character collision still limits movement. Releasing the cart, aiming, sneaking, injury or a timed action restores ordinary handling.

The wooden wheelbarrow has the refined animation: hands remain attached to its handles, the grounded wheel rolls with actual movement and turns lean up to 7 degrees. Walk, Run and Sprint retain moving legs; cargo affects acceleration and Sprint entry/exit. Releasing Run/Sprint uses a heavy-item braking step and a smooth return to the standing grip. New input interrupts braking. From a settled stop, side input uses full native lateral strides around the front wheel before pushing in the new direction. Cargo slows the stride cadence rather than shortening the steps. Run/Sprint wait for that turn to finish. Releasing the direction returns to standing; an opposite-direction command still requests a slower backward step. Use successive side directions for a U-turn.

This tuning was checked locally with empty/full wooden wheelbarrows on both body models. Cart motion and action poses are replicated to remote players. A matching owner/observer pose at the same source time and smooth presentation across every transition remain unverified; local capture does not establish multiplayer equivalence. Stationary hip/clothing clearance, the remaining maneuver matrix and natural pickup/put-down transitions remain [open work](../../TODO.md#natural-wooden-wheelbarrow-animation). There is no separate cart rigid-body simulation.

## Vehicle mechanics

Right-click a removable part in the vehicle mechanics window and select **Uninstall to ground**. The part is left at your character's feet when removal succeeds, including light bulbs and heavy parts; there is no weight threshold. Tools, skills, work duration and the chance of damaging a part remain native. The original **Uninstall** action keeps its usual inventory destination and its fallback to the ground when the inventory has no room. Disable **Uninstall vehicle parts to ground** in Mod Options to hide the extra command; already queued actions keep their chosen destination.

The mechanics context menu also offers **Add to wishlist** for replacement parts with a native installation operation. It requests the compatible part variants for that vehicle class, even if tools or skills are currently missing. Fixed parts such as the vanilla glovebox have no replacement wish; modded installable gloveboxes can qualify. Wanted parts are highlighted in mechanics and inventory.

In multiplayer, install Toolkit on the server and every client. No additional mod or Java patch is required for this action. Modded vehicles have not been validated.
