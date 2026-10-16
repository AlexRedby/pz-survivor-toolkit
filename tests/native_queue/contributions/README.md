# Native fixture contributions

[Development](../../../docs/DEVELOPMENT.md#native-scenarios) · [Native runner](../README.md)

Preserve independent stands under topic directories. Integrate setup/events/receipts/log audit before adding them as ready suites in `../catalog.json`. Intake alone is not passing coverage.

Each contribution supplies source fixtures and a manifest/README with prerequisites, local path parameters, fresh-profile setup, commands, acceptance criteria and supported modes/platforms. Preserve VOIP-off, desktop-lock/process checks and ownership-safe teardown. Do not commit generated worlds, downloaded files, binaries, media or raw logs.

Preserved fixture intakes:

| Topic | Preserved source | Integration boundary |
|---|---|---|
| [video-recording](video-recording/README.md) | Fresh-profile preparation, Java/Lua capture fixture, verifier and tests | macOS GUI launch required; common-runner adapter pending |
| [animal-trailer](animal-trailer/README.md) | Equipment race, trailer ghost and animal timer probes; build/verify tools | Requires disposable dedicated-server/client setup; common-runner launch pending |
| [crafting-plans](crafting-plans/README.md) | Chains, shared inputs, Neat UI and ingredient alternatives | Parameterized MP scenarios; event/receipt adapter pending |
| [shared-wishlist](shared-wishlist/README.md) | Shared edits/access, persistence and UI fixtures | Server/client preparation preserved; common-runner adapter pending |
| [item-tags](item-tags/README.md) | Five screenshot/assertion scenes and preparation test | Needs Toolkit 0.1.53+ and listed UI mods; common-runner adapter pending |
| [wooden_cart_motion](wooden_cart_motion/README.md) | Input bridge, disposable area, Sprint/reverse/turn scenarios, mesh/palette/grip probes and analyzers | Needs candidate cart-motion APIs absent from queue main; trousers intersection criterion remains unresolved; common-runner adapter pending |
| [wooden_cart_multiplayer](wooden_cart_multiplayer/README.md) | Server-seeded cart, actual owner/observer, read-only pose probe and six-phase capture analyzer | Parameterized port needs live execution; no animation-equivalence PASS or common-runner adapter |
