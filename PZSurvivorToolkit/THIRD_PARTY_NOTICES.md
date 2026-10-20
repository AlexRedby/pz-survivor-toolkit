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

# Smart Deposit

Toolkit's Smart Deposit routing and walking rules are adapted from the
Build 42.21 implementation of **Better Containers**, by **Eurymachus**:
[Steam Workshop item 3586216562](https://steamcommunity.com/sharedfiles/filedetails/?id=3586216562).

Toolkit owns one allocation used by drag feedback and transfer execution.
Better Containers remains required for proximity containers, permissions,
category data and its other features. No Better Containers assets or saved-data
formats are copied by this change.

# Vehicle dashboard lighting

The beam indicators and truck rocker artwork under
`42/media/ui/PZSurvivorToolkit/beams/` adapt pictograms, texture styling and
small background strips from **Realistic Dashboard & Gauges**:
[Steam Workshop item 3635591071](https://steamcommunity.com/sharedfiles/filedetails/?id=3635591071).
The matching generators in `tools/` retain source provenance, including the
embedded donor pixels. Realistic Dashboard remains required for its dashboard
layouts and controls. This attribution grants no additional redistribution rights.
