# Quartermaster

The built-in storage designation, distribution, Manifest and crafting features
derive from **Quartermaster 0.24.0**, by **deckard**:
[Steam Workshop item 3761216758](https://steamcommunity.com/sharedfiles/filedetails/?id=3761216758).

The imported baseline is the Build 42 `media` directory: the `LootSorter_*.lua`
modules, English `ItemName.json` and `Recipes.json` translations,
`scripts/quartermaster_manifest.txt`, and `textures/Item_QuartermasterManifest.png`.
The installed source package contains no separate license file. This attribution
does not grant additional redistribution rights.

Toolkit maintains this code locally. Its changes connect container tag rules
directly to the sorting planner, integrate the tag picker and preset storage,
and expose explicit crafting and Manifest hooks to the Toolkit action queue.
The original `LootSorter` and `Quartermaster` data identifiers are retained for
existing saves, presets and settings. The separate Workshop mod must be disabled
when using this implementation.

# Inventory presentation

Toolkit's expanded item details, stack-sort policies and four nutrition icons
are adapted from **Item Details 0.0.12**, by **Bravo**:
[Steam Workshop item 3477237184](https://steamcommunity.com/sharedfiles/filedetails/?id=3477237184).
The icons are now under `42/media/ui/PZSurvivorToolkit/item-details/`.

Container capacity bars and magazine segments are adapted from
**Container Capacity Indicator 1.2.0**:
[Steam Workshop item 3789660055](https://steamcommunity.com/sharedfiles/filedetails/?id=3789660055).

Toolkit owns rendering and sorting through its inventory presentation boundary;
the separate Workshop mods must be disabled. Their original Mod Options keys
are retained to preserve existing preferences. Neither installed source package
contains a separate license file; attribution grants no additional rights.
