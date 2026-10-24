# Native fixture sources

[Development](../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../README.md)

This directory holds source fixtures used by native scenario adapters. Read a topic guide for its fixture contract and limitations; use the [shared runner guide](../README.md) for preparation, launch, reports and current coverage. A fixture's presence or registration does not establish a passing native run.

Each contribution supplies source fixtures and a manifest/README with prerequisites, local path parameters, fresh-profile setup, commands, acceptance criteria and supported modes/platforms. Preserve VOIP-off, desktop-lock/process checks and ownership-safe teardown. Do not commit generated worlds, downloaded files, binaries, media or raw logs.

| Fixture | Purpose |
|---|---|---|
| [video-recording](video-recording/README.md) | In-game recording, clip verification and frame extraction |
| [animal-trailer](animal-trailer/README.md) | Multiplayer animal equipment, trailer membership and timer fixtures |
| [crafting-plans](crafting-plans/README.md) | Craft chains, shared inputs, UI state and ingredient alternatives |
| [shared-wishlist](shared-wishlist/README.md) | Shared wishlist UI, access and persistence fixtures |
| [inventory-presentation](inventory-presentation/README.md) | Inventory details, capacity and stack presentation |
| [inventory-tooltips](inventory-tooltips/README.md) | Native item tooltip layout and clothing comparisons |
| [item-tags](item-tags/README.md) | Inventory tag rendering, filtering and saved selection |
| [basement-hall](basement-hall/README.md) | Basement room identity and traversal across save/reload |
| [smart-deposit](smart-deposit/README.md) | Partial acceptance and exact inventory conservation |
| [wooden_cart_motion](wooden_cart_motion/README.md) | Calibrated single-player cart motion captures and geometry analysis |
| [wooden_cart_multiplayer](wooden_cart_multiplayer/README.md) | Owner/observer cart motion, action and replication captures |
