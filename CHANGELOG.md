# Changelog

Functional changes to the repository components. For current behavior and limits, see [features](docs/FEATURES.md) and the [Java guide](JavaPatches/README.md).

- [PZ Survivor Toolkit](#pz-survivor-toolkit)
- [Survivor Wishlist](#survivor-wishlist)
- [Toolkit Java Patches](#toolkit-java-patches)

Version labels come from committed component metadata, including changes made without a version bump. Parallel branches sometimes reused a label; consolidation entries identify the combined behavior. There are no release tags in this history, so these entries do not assert publication dates. Third-party mod selection is documented in the [catalog](USEFUL_MODS.md).

## Selected mod set

- **Added:** Archery Nexus with Wilderness Progression: Archery Nexus to the B42.21 selection (49 Mod IDs / 46 Workshop items), with the base loaded before its companion. Includes crafting/progression, arrow recovery and draw endurance/strain; full-pack and Host behavior remain unverified. Existing sandbox settings are unchanged.
- **Added:** Vanilla Vehicles Animated and its ZombieBuddy-based Animated Vehicle Parts Fix to the B42.21 selection (47 Mod IDs / 44 Workshop items). Optional VVA submods and the outdated multiplayer synchronization addon remain disabled. SP visuals, lighting coexistence and Host animation synchronization are not yet verified.

## PZ Survivor Toolkit

### 0.1.168

- **Changed:** Item Details reads the native Mod Options values directly instead of maintaining a second configuration synchronized on Apply and main-menu entry. Existing preferences, display settings and bounded stack sorting are preserved.
- **Fixed:** Toggling loose-item highlighting no longer refreshes unrelated inventory panes, TV controls or context menus. Applying the full Toolkit options still updates the affected features.

### 0.1.167

- **Fixed:** In Host, ordinary VHS insertion keeps its pending playback when the TV state or tape removal arrives before native completion. The exact started insertion waits for correlated server completion and both effects, including with the Toolkit queue disabled; explicit cancellation and native failure still clear ordinary pending work.

### 0.1.166

- **Changed:** Container configuration saves now use Quartermaster's existing command transport instead of a separate request/reply and timeout loop. Player identity, access checks, revision conflicts and accepted-field updates are preserved; request tokens no longer modify caller-owned arguments.

### 0.1.165

- **Changed:** The sport dashboard headlight button cycles off, low, high and off on successive releases. It keeps the original bulb symbol, six-dot grip and momentary press effect, with the dashboard indicator showing the beam mode. Power steps retain native commands and acknowledgement handling; selecting high does not toggle headlight power.

### 0.1.164

- **Changed:** Quartermaster's Storage controls and Mod Options share one owner for the crafting preference and availability updates. Each native/Neat crafting window refreshes independently after a change or cancelled haul; pending updates wait for active hauling/crafting to finish and survive a failed refresh. Control placement, saved settings and physical ingredient fetching are preserved.

### 0.1.163

- **Changed:** Live context menus and editor previews now share explicit per-pass state instead of switching shared temporary variables. Existing grouping, scoped rules, saved preferences and native option ownership are preserved.

### 0.1.162

- **Fixed:** Wooden wheelbarrow pickup now requires the player to reach the actual handle position before starting the lift. A path shortened by a nearby obstacle leaves the cart on the ground instead of starting from a misaligned stance.

### 0.1.161

- **Fixed:** CleanUI inventory transfers retain one operation per drag through deferred enqueueing. Native transfer batching works again, avoiding expensive per-item queue checks while a batch runs. Separate drags remain separate; native transfer timing, capacity checks and multiplayer item authority are preserved.

### 0.1.160

- **Changed:** The standard dashboard headlight knob uses evenly spaced off/low/high positions: low sits halfway between off and the original on position, with high at the original on position. Matching soft grey faceplate symbols replace the previous layout at every dashboard scale. Clicking retains the native power acknowledgement path and High Beams selection.

### 0.1.159

- **Changed:** Pending portions of ordinary food that leaves an empty container can be reordered or cancelled when every retained portion preserves the original food. Native portion sizes and decreasing item weight remain intact; edits that would create a replacement, near-empty remnants, custom weights and callbacks keep their protection.

### 0.1.158

- **Changed:** Wishlist row highlights now use Toolkit's shared inventory presentation boundary, removing their separate pane and CleanUI mode-switch hooks. Mixed-stack matching, full-row clipping, drag exclusions and saved settings are preserved.

### 0.1.157

- **Fixed:** Inventory search, exact categories and tag filters now match each physical item before building visible stacks. Same-name items with different individual categories no longer disappear together or satisfy different parts of one search. Category choices, selection and outgoing bulk transfers follow the resulting view in native and CleanUI inventories.

### 0.1.156

- **Changed:** The heavy Realistic Dashboard replaces its pull knob and printed label with a Polaris-style three-position headlight rocker. Its upper/lower halves step between off, low and high; distinct raised edges and recess shadows show the selection at every dashboard scale. Native headlight power commands, pending acknowledgements and external hotkey/radial changes remain authoritative.

- **Fixed:** Vehicle beam origins follow the ground projections of the current model's lamp-mask surfaces, with native normalized coordinates and per-model scale/offset. Unknown or unsupported model geometry retains upstream origins. Removed the duplicate blue headlight-switch artwork in Realistic Dashboard.

- **Fixed:** High Beams now drives the existing Realistic Dashboard lamp using its original soft artwork, dimensions and layout: green sloping rays for low and blue horizontal rays for high. Keeps warning-light fading and native power handling; the standard rotary switch cycles off/low/high with a third position and matching marking. Includes a stock-dashboard fallback.

- **Added:** Optional approximate beam geometry separates broader low beams from focused high beams and places front/reverse beam origins at the vehicle ends. Preserves upstream High Beams power/range controls, lamp colour, activation and condition scaling; can restore the original geometry.

- **Added:** Adjustable short-range light spill around working vehicle lamps, using native occlusion and cleanup when lamps turn off, lose power or leave the loaded area.
- **Changed:** With Reverse Drive Lights enabled, reverse beams default to range 12 and intensity 0.3, below native low beams (36 / 0.75). Mod Options provides weaker and original-mod presets independently of surrounding spill.

### 0.1.155

- **Changed:** Pending portions of cold food with a native cooking replacement, such as bread slices that can become toast, can be reordered or cancelled while the carried food cannot keep cooking. Original item identity, portions and cooking metadata stay intact; hot food and consumption replacements remain protected.

### 0.1.154

- **Fixed:** Better Clothing Info's main tooltip and comparison now use one measured frame for context-menu, controller and anchored placement. Its clothing details, comparison and settings remain upstream. The native per-item “No Recipes” marker is visible again and disappears when cleared.

### 0.1.153

- **Fixed:** VHS skill and recipe details now participate in native tooltip measurement and placement through the same extension boundary as planting information. Long lines and additional rows fit the tooltip background and follow its visibility. Show VHS Skills in Tooltip still supplies its catalog and translations, while its unrelated clothing suppression and background-alpha changes are avoided.

### 0.1.152

- **Changed:** Pending portions of ordinary cookable food can be reordered or cancelled once the food and its carried outer inventory are cool enough to prevent further cooking. Native cooked hunger/fullness bonuses remain intact; hot food, dangerous raw food, fertilized eggs and callback/replacement effects keep their protection.

### 0.1.151

- **Fixed:** Single-player wooden-cart emergency release starts from the last displayed held pose and finishes a short cart-only settling transition. Native instant-drop, exact cart/cargo ownership and the existing Host request remain authoritative.

### 0.1.150

- **Fixed:** Smart Deposit drag feedback and execution now use the same allocation. Items that do not fit nearby storage remain visibly rejected when other selected items can be moved. Type/category/fallback routing, protected items and native transfer actions are preserved in both inventory modes.

### 0.1.149

- **Fixed:** Distribution checks which carry containers can hold each item before reserving destination space. Items rejected by all roomy carriers no longer block later items from being sorted or push them into lower-priority overflow boxes.

### 0.1.148

- **Fixed:** Better Containers pin markers now share the actual-icon presentation used by research and planting badges. Markers follow scaled native/CleanUI icons without a separate row renderer, stay on stack headers and avoid covering other Toolkit badges; pin settings, ordering and saved data are unchanged.

### 0.1.147

- **Changed:** Pending ordinary-food actions with a captured fork or spoon use the shared queue edit contract. Safe reorder and cancellation preserve the exact selected utensil, native portion, duration and benefits; selected-tool and carried-container dependencies remain protected.

### 0.1.146

- **Changed:** Research and planting indicators now use Toolkit's shared inventory presentation in both CleanUI modes. Research availability follows native character knowledge and skills; planting information is implemented from native farming data, retaining known-season badges, growth details, crop images and saved preferences without modifying item categories.
- **Changed:** Removed the separate HasResearch and SeedSeasonIndicator mods from the selected set. Disable them in existing profiles when updating; planting settings now appear under Toolkit.

### 0.1.145

- **Changed:** Pending ordinary-food actions with any valid native portion, including EatSmart-calculated amounts, can be reordered or cancelled when their remaining-food, location and fullness dependencies permit it. Captured portions keep their original-food meaning; depleted items and required returns stay protected.

### 0.1.144

- **Fixed:** Seed Season Indicator no longer replaces inventory categories or category sorting with seasonal labels. Toolkit tags retain their normal categories; planting-season icons and detailed tooltips keep the mod's existing knowledge checks and settings.

### 0.1.143

- **Fixed:** Crafting from storage counts each physical item once when ordinary reachable containers and designated boxes overlap. The quantity limit and fetch plan share one source snapshot, so aliases cannot inflate availability or reserve the same item twice. Crafting refreshes no longer append an already accessible designated container again.
- **Fixed:** When a handcraft depends on nearby world ingredients as well as fetched storage items, the haul returns to the starting location before crafting, restoring access to those original ingredients.

### 0.1.142

- **Changed:** EatSmart menu goals use short English/Russian outcome labels, with the estimated percentage of remaining food in parentheses. Numeric targets remain in tooltips beside existing unavailable reasons; native portions, settings and callbacks are preserved.

### 0.1.141

- **Changed:** Ordinary pending food portions use the shared queue edit model, allowing legal same-item reorder and cancellation while retaining native original-food fractions. Exact pickup, remaining-food and fullness requirements protect later actions; consuming a whole item cannot precede a dependent portion or return.
- **Fixed:** Food and nutritious drinks share the character's fullness dependency. Unknown food callbacks, cooking/replacement effects and required equipment remain protected; projected consumption never grants extra container capacity or replays native effects.

### 0.1.140

- **Changed:** A wooden wheelbarrow held against an obstacle uses a planted pushing stance with staggered feet, a slight forward body lean and smooth contact/release blends. The same pose is available to other players through the existing cart synchronization.

### 0.1.139

- **Fixed:** Quartermaster distribution respects organizedCategories' enabled Stick protection. Quantity transfers preserve the original selection's intent before filtering or limiting items, so a mixed selection reduced to one item cannot bypass Stick. Deliberate single-row/stack transfers and live Stick opt-out retain their existing behavior.

### 0.1.138

- **Added:** Close an open door from the occupied seat through the vehicle radial menu (`V`) or a dashboard button. The radial uses the selected blue-door icon with a red closing arrow and artwork inset within its 64x64 canvas. The dashboard uses the native door pictogram. The filled, rounded dashboard button matches the size and hover opacity of Realistic Dashboard seat/sleep shortcuts on driver and passenger panels; it is ochre when available and grey when closed or pending. Uses the native door action and synchronization without leaving or switching seats.

### 0.1.137

- **Fixed:** Quartermaster skips matching containers that cannot accept an item while planning the haul, so a restricted or unavailable destination no longer hides the next suitable box. Explicit-item precedence, priority and planned capacity are retained; transfers still recheck the destination when executed.

### 0.1.136

- **Changed:** Toolkit now owns Container Capacity Indicator and Item Details: capacity bars, magazine segments, expanded item values and bounded stack sorting share one presentation boundary for CleanUI and native inventories. Removed both separate Workshop mods from the selected set; existing display/sort preferences are retained.
- **Fixed:** Capacity indicators follow actual scaled or texture-sized icons, and a dirty inventory redraw retains the physical Shift-selection anchor while reordering an expanded stack. Expanded food details no longer overlap Better Containers freshness percentages.

### 0.1.135

- **Changed:** Pending clean-water drinking and single-item transfers between carried containers use the shared queue edit model. Legal return/pickup orders may change the final container; removing a pickup required by a later drink remains blocked.
- **Fixed:** Modeled queue edits retain a separate capacity check using full current item weights. Native SP drink endpoints and Host consumption uncertainty are preserved; edits do not reserve future resources, alter portions or replay native effects.

### 0.1.134

- **Changed:** Wooden-wheelbarrow standing pivots use broader authored leading/following steps with modest weight transfer. The lateral stride and root-motion budget increase together, reducing foot cadence while retaining turn speed, hand grip and wheel support. Other cart types and fast gait clips retain their existing selection.

### 0.1.133

- **Fixed:** Host presets save and synchronize categories, items and tag rules as one complete snapshot, preserving existing preset identities during automatic migration. Late replies cannot restore older state, and open preset editors keep a coherent draft until save/reopen.
- **Fixed:** Storage discovery no longer rewrites container data while removing obsolete preset links. The Host container editor excludes unresolved links from its selection and cleans them through ordinary Save; SP retains world links absent from the local preset library.

### 0.1.132

- **Fixed:** Pasting container sorting settings saves categories, items, preset links, priority and tag rules together through the editor's authority checks. Stale or denied pastes leave the destination unchanged; its name, icon and colour are preserved. Removed the separate client publication of container data.

### 0.1.131

- **Changed:** Bulk clothing, electronics and battery menus share one native recipe lookup per selected item and one reachable-container snapshot per menu build. Each command retains its own first viable recipe, exact selected items and toggle; clicking still revalidates inputs and tools before queuing native actions.


### 0.1.130

- **Changed:** Pending volume, channel and microphone settings for a fixed world radio/TV can be reordered or cancelled even when they share a device. Native commands still apply each effect; the chosen order may deliberately change the final setting. Power, playback and unverified dependencies remain protected.
- **Added:** A shared versioned resource-effect contract checks the proposed queue and its downstream prerequisites. Unsupported contracts retain conservative protection, with separate required-state, resource, capacity and unknown-effect explanations.
- **Fixed:** Queue commands revalidate current ownership, operation members, generation, conditions and callbacks immediately before changing the queue, rejecting stale UI decisions without removing work.

### 0.1.129

- **Fixed:** Toolkit refreshes dependent features once after Mod Options applies all new values. Removed early per-option notifications that repeated refreshes with stale or partially applied settings; the highlight hotkey still takes effect immediately.

### 0.1.128

- **Changed:** Canceling a wholly unstarted operation with the verified native no-effect cancellation handler no longer treats shared resources with preceding work as a conflict. Dependencies of following operations, required cleanup, started work and custom cancellation handlers remain protected.

### 0.1.127

- **Added:** The first sorting tag selected in the container editor fills empty name, icon and colour fields from that tag. An exact item supplies its own icon and its primary tag's colour, leaving the name empty. Existing values and subsequent manual edits are preserved; later selections do not change the suggestion.

### 0.1.126

- **Added:** Active reading can be dragged below waiting operations, preserving their order and continuing from saved pages before returning the book to its original container.
- **Changed:** Reviewed world-TV VHS insertion supports queue edits with exact tape/device dependencies. TV power, insertion and playback retain their required order; shelf-reading moves check capacity without relying on future freed space.
- **Fixed:** In Host, VHS insertion promoted above reading tolerates its expected media/tape replication arriving before native completion, then waits for the confirmed result before advancing. After native completion, unavailable media or a bounded replication timeout skips linked playback while retaining independent reading; an unconfirmed active action retains native cancellation.

### 0.1.125

- **Changed:** World containers have one **Configure container...** editor for sorting, name, icon and colour. It reuses Better Containers' existing appearance data and icon catalogue; supported container menus no longer offer separate rename/customize paths. Bags keep their existing controls.
- **Changed:** The editor saves sorting selections, tag rules and appearance together after the same authority checks. Cancel leaves all fields unchanged; existing per-player/global Better Containers appearance is retained.

### 0.1.124

- **Changed:** Quartermaster prepares its item/tag catalog once per editor window and shares it with rule previews. Search and selection filter prepared rows instead of rescanning every loaded item; reopening refreshes the catalog. Exact picks, partial-category rules and saved categories from missing mods retain their meaning.

### 0.1.123

- **Changed:** Wishlist and crafting-plan buttons share one owner for native crafting rows and Neat Crafting footers. Creation, visibility and reserved space no longer depend on nested layout hooks; action behavior, button order and embedded-plan controls are preserved.

### 0.1.122

- **Fixed:** Better Containers pin markers now follow the inventory's rendered rows, including hidden CleanUI equipment and expanded stacks. Toolkit draws the markers directly while BC retains pin settings, menus and assets; removed the global pane swap used to install BC's separate row renderer.

### 0.1.121

- **Fixed:** Restored the reviewed Project Cook 1.4.10 action-queue integration, including batch completion and automatic dish returns. The new return producer keeps its operation ownership; changed configuration helpers remain protected.

### 0.1.120

- **Changed:** Quartermaster's owned editor now creates and handles its tag controls directly. Removed per-window method replacements for layout, filtering and controller navigation while preserving exact categories, tag rules and Save behavior.

### 0.1.119

- **Fixed:** Inventory selection follows visible rows after refresh, filtering and sorting, including hidden equipment and expanded stacks beyond the render limit. Whole-stack selections remain groups across repeated refreshes instead of becoming a single item; selection and Shift anchors share one row projection.

### 0.1.118

- **Added:** Fitness requests show exercise-specific labels and elapsed workout time in the action queue. Waiting workouts can be reordered or canceled before preparation.
- **Fixed:** Workout timers start when exercise begins. Natural endings and queue cancellation retain independent actions and restore exact carried equipment even after closing the fitness window; Host waits for the authoritative stop before advancing.

### 0.1.117

- **Fixed:** Item Details sorting keeps the Shift-selection anchor on the same visible item or group when equipped rows are hidden. Item Details and Better Containers now share row mapping for collapsed equipment, virtual stack headers and clipped stacks.

### 0.1.116

- **Changed:** Quartermaster exposes distant storage only during crafting-panel container refreshes for the requesting player. Removed the render-time global availability window; ordinary inventory queries and fallback crafting keep their normal containers, while ingredients still travel through the existing physical haul.

### 0.1.115

- **Changed:** With item tags enabled, Quartermaster category and tag selections exclude broken tools, including carpentry tools. Explicit item assignments can still collect them.
- **Fixed:** The `drug` tag uses the native pill icon instead of a suture needle.

### 0.1.114

- **Fixed:** Tag choices and previews use organizedCategories inventory categories while preserving native loot categories. Quartermaster prepares item categories directly before sorting, inspecting container contents and recording the storage manifest, removing dependence on prior inventory-pane refreshes or external wrappers.

### 0.1.113

- **Fixed:** `Distribute Loot` remains available when right-clicking an item in the inventory or a worn bag, even when its toolbar button is visible. Explicit menu-profile hiding remains respected.

### 0.1.112

- **Fixed:** Walking no longer loses the queued action after an item finishes transferring from a carried bag. Belt attachment, drinking and other follow-up actions retain their native movement and cancellation rules.

### 0.1.111

- **Fixed:** Grab and Grab One work when organizedCategories and Tidy Up Meister are loaded. The compatibility guard now uses the shared closure check instead of calling a removed helper before the pickup starts.

### 0.1.110

- **Changed:** Quartermaster's owned editor and clipboard save complete container designations directly, without callback interception or temporarily replacing the clipboard. Native fields are published together after any tag-rule acceptance; existing save data and authorization are preserved.
- **Fixed:** Copy/paste preserves preset generations, preventing a copied link from silently attaching to a deleted-and-recreated preset with the same name.

### 0.1.109

- **Fixed:** Inspecting clothing from storage uses the item delivered to the player's inventory in Host/multiplayer, keeping the inspection window open after transfer. Delayed cart deliveries get a bounded wait; carried-item and single-player inspection retain the native window.

### 0.1.108

- **Fixed:** The action queue window remembers each local player's moved position when the native queue is replaced or disappears during the current game session.

### 0.1.107

- **Changed:** E picks up the nearest reachable cart or puts down the held cart. Accepted cart actions take priority over doors and windows for that key press; ordinary Interact remains available when no cart action starts. The old V default migrates once, preserving other custom bindings.

### 0.1.106

- **Changed:** Quartermaster preset commands use owned storage directly, saving presets and tag rules together without replacing global functions or publishing temporary drafts. Existing saved formats, legacy import and multiplayer commands are preserved; the unused duplicate parser is removed.
- **Fixed:** The multiplayer startup retry waits for both preset data and enabled tag rules, matching the sorting readiness check.

### 0.1.105

- **Fixed:** Waiting native drinks from independent inventory bottles can be cancelled or reordered, including verified SaucedCarts wrappers. Clean-water backpack operations retain conservative capacity checks. Active drinking, shared bottles and unknown callbacks remain protected; vanilla portion calculations are unchanged.

### 0.1.104

- **Changed:** Quartermaster is included in Toolkit with its storage designations, distribution, Manifest and crafting integration. Disable the separate Workshop mod when updating; existing assignments, options and presets keep their identifiers and formats.
- **Changed:** Container tag rules pass directly to sorting instead of temporarily replacing item categories. Craft-window layout and action-queue handoffs are integrated with the owned implementation.

### 0.1.103

- Register bounded cart locomotion and interaction snapshots for native multiplayer variable synchronization; every client renders cart poses locally.
- Align the final wooden wheelbarrow pickup approach with the center between its handles.

### 0.1.102

- **Fixed:** An updated Project Cook interface no longer prevents TidyUpMeister from preserving explicit equipment choices. Independently verified recipe modifiers load before compatibility snapshots; changed cooking interfaces and unknown modifiers remain protected.

### 0.1.101

- **Fixed:** Queue transfer controls recognize Better Containers 42.21 and its new stale-vehicle helper. Modified helpers remain protected, and transfers into stale vehicle containers retain the upstream rejection.

### 0.1.100

- **Changed:** Wishlist uses Toolkit's shared button styling and inventory-class integration, removing duplicate standalone paths while preserving existing controls and highlights when CleanUI switches views.
- **Fixed:** Better Containers pins remain first within their search and equipment sections across native, CleanUI and organizedCategories inventory views, preserving selection and the chosen column order. Added under this existing version label in `2dd301c`.

### 0.1.99

- **Fixed:** Wishlist, tag-rule, context-menu and craft-chain labels share Unicode-safe truncation. Long labels preserve whole characters in the game's native string format, and very narrow columns no longer show an overflowing ellipsis.

### 0.1.98

- **Fixed:** Closing the context-menu editor or tag-rule picker releases text-entry focus and its open dropdown, including when the feature is disabled or settings cannot be saved.
- **Fixed:** Window cleanup, including Wishlist, leaves another control's shared dropdown open.

### 0.1.97

- **Changed:** Audited TidyUpMeister cleanup of temporarily held items uses shared native completion, preserving empty hands, exact inventory returns and explicit equipment intent. Clothing, hotbar, heavy items and unverified callbacks retain their existing completion path.

### 0.1.96

- **Changed:** Wishlist sharing now searches and selects online players instead of accepting typed usernames. Existing offline members keep their access.

### 0.1.95

- **Fixed:** Server medicine throttles discard expired player entries, and Wishlist refreshes release disconnected players' snapshots and request buckets without relying on weak tables unsupported by Kahlua.

### 0.1.94

- **Fixed:** TidyUpMeister can return borrowed floor items in Host after the network replaces their inventory reference, preserving exact item identity, original placement and explicit pickup intent with the queue enabled or disabled.
- **Changed:** Audited TidyUpMeister hand and activation restores use shared native completion, preserving protected mixed-session cleanup. Equipment slot and floor placement fields are checked before granting queue permissions.

### 0.1.93

- **Changed:** Audited TidyUpMeister inventory returns retain their queue contracts after approved late transfer hooks and use shared native completion ownership, preserving exact destinations, explicit pickup/equipment intent and the unsupported-engine fallback.

### 0.1.92

- **Changed:** Audited medical expansion uses shared native completion ownership, retaining exact child treatment/resource proofs, bare-hands ordering and the unsupported-engine fallback.

### 0.1.91

- **Fixed:** Prepared mods and developer ZIPs retain the common/version animation and action-group directories required by native Host loading, avoiding missing-directory errors that the test snapshots previously masked.

### 0.1.90

- **Changed:** Generator repair chains use shared native completion ownership while preserving exact repair effects, continuation guards and the unsupported-engine fallback.

### 0.1.89

- **Changed:** Campfire kindling retries use the shared native completion boundary while retaining exact child validation and retry-before-tool-return ordering. Unsupported engines keep the existing completion fallback.

### 0.1.88

- **Fixed:** Context-menu preferences use alternating checked snapshots with readback verification, retain the legacy INI for import and refuse stale writes. Failed loads cannot overwrite saved settings; failed preference edits roll back without reporting success. Reopening the editor retries in the same profile object, and storage failure leaves ordinary menus usable.

### 0.1.87

- **Fixed:** Fullness no longer silently cancels water drinking after a backpack transfer. Empty containers remain invalid; nutritious drinks keep their native fullness restriction. Applies in single-player and Host, with or without the Toolkit queue.

### 0.1.86

- **Fixed:** Wishlist and named inventory tag filters refuse writes when the game cannot open/read/close their existing stores. Fresh empty slots initialize safely and failed loads retry without caching an empty replacement; Wishlist directory creation never truncates an existing slot.

### 0.1.85

- **Fixed:** Single-player Quartermaster presets and Toolkit tag rules save as one verified snapshot, alternating between two files. Interrupted or short writes retain the previous coherent pair; failed verification forces a fresh read before another save. Existing global files import automatically and remain untouched.
- **Fixed:** Preset snapshots preserve native generation, revision, creator and item full types across restarts. Strict parsing rejects malformed or trailing data; string quoting preserves backslashes, Unicode and control characters in the game's Lua runtime.

### 0.1.84

- **Fixed:** Server-side cart unequip and broken-cart drop finish without accessing the client action queue and return a Boolean based on the authoritative item result.

- **Fixed:** Server cart pickup reconstructs the selected action without querying client render models.
- **Fixed:** Cart pickup retains the constructor field names required by native multiplayer serialization, so Host/server actions receive the cart coordinates and ID for every cart type.
- **Fixed:** Repeated wooden-wheelbarrow pickup uses fractional stance distance rather than the integer-only distance overload, avoiding an unnecessary zero-length path and cancelled pickup.

- **Fixed:** Shopping carts and metal wheelbarrows approach an accessible adjacent tile before ground pickup when out of reach. Native pickup/equip, cargo and the wooden-wheelbarrow stance are preserved.

### 0.1.83

- **Fixed:** Quartermaster waits for both its presets and Toolkit tag rules before multiplayer sorting, and requests both again through its existing gather retry when either is missing. Disabling tags retains native readiness.
- **Fixed:** Failed single-player tag-rule reads no longer publish an empty cache or allow linked native preset changes before loading succeeds. Readers/writers close on exceptions; serialization finishes before opening the existing file for overwrite.

### 0.1.82

- **Added:** Wishlist requests for compatible vehicle parts from the mechanics window. All compatible variants of the requested vehicle class are highlighted in inventories and mechanics, with combined carried counts.
- **Changed:** Item context menus and the catalog switch between adding and removing requests. Compatible vehicle groups have their own removal actions, preserving separate exact-item requests and the selected list.

### 0.1.81

- **Fixed:** Better Generator Info queue integration accepts its reviewed source in the game as well as the test runtime. Source checks now share UTF16 normalization, bounded reads and reader cleanup across compatibility, fire, generator and medical adapters; changed or unverified sources remain protected.

### 0.1.80

- **Fixed:** Verified native crafting UI batches skip an exhausted pool of selected one-use items before the next craft starts, preserving tool cleanup and independent queued actions. A sufficient remaining pool continues normally.

### 0.1.79

- **Fixed:** Shared transfer guards preserve existing completion callbacks and their arguments. Reapplying the guard retains native stop provenance without granting unknown callbacks queue permissions.
- **Maintenance:** Removed adapters and checks for the excluded Proximity Inventory and Manage Containers mods. Current Better Containers and Quartermaster checks no longer require the old Proximity Inventory Workshop installation.

### 0.1.78

- **Fixed:** Bulk clothing cutting includes belts, eligible holsters and empty bandoliers through the native recipe, including mixed selections with clothing. Native tools, outputs and protected-item checks are preserved.

### 0.1.77

- **Fixed:** Clicking inventory items during transfers follows the pressed item across row changes and stack sorting instead of selecting the replacement row on mouse release. Rapid clicks on different items no longer trigger a double-click action after a transfer.

### 0.1.76

- **Maintenance:** TV videos retain the original mod's catalog and initialization. Removed the duplicate Lua video list and macOS path-depth search; path correction now runs before native video caching.

### 0.1.75

- **Changed:** Lemongrass displays the native cooldown instead of estimating its maximum duration. Removed the separate Lua countdown and food-action hooks; unsupported readings hide only this indicator.

### 0.1.74

- **Maintenance:** Inventory adapters share class discovery and CleanUI toggle subscriptions while preserving each adapter's installation order, native fallback and existing hooks.

### 0.1.73

- **Added:** Authored wooden-wheelbarrow pickup and setdown clips, including the SaucedCarts setdown hotkey, cancellation recovery and exact world/held-item handoffs.
- **Fixed:** Brief transitions from Run/Sprint to walking retain cart momentum for smooth, cargo-dependent braking.
- **Changed:** Consolidated the cart integration with the current queue and shared Wishlist changes; remote cart-pose reconstruction and the remaining visual cases stay open.

### 0.1.72

- **Fixed:** Automatic batch crafting keeps automatic material selection without the B42.21 Java queued-item accounting exceptions. Manual selection and native multiplayer constructor fields are preserved.

### 0.1.71

- **Fixed:** Native crafting UI actions remain supported when Quartermaster or P4 wraps layout and craft-button entry points. Neat accepts only the two source-verified Quartermaster UI wrappers; completion, cancellation and their helpers retain identity guards.
- **Fixed:** Project Cook batch crafting releases its per-action busy counter after every completed craft, so its window becomes available again when the batch ends.

### 0.1.70

- **Fixed:** Before a queued manual craft starts, a missing selected input cancels only its operation and preserves safe tool returns and independent follow-up work. Started crafts and unknown callbacks keep their existing safeguards.

### 0.1.69

- **Fixed:** Queue reset and clear revoke pending callbacks through the shared native cancellation boundary, including after Quartermaster reloads its saved reset wrapper. Clearing only a command's generated actions preserves its parent and valid continuations.

### 0.1.68

- **Fixed:** A completed multiplayer fire ignition waits for its correlated server outcome before cancellation cleanup, preserving the original fuel container and queued follow-up actions.

### 0.1.67

- **Fixed:** Queue behavior lookup evaluates only handlers registered for an action's type; an unrelated handler failure no longer disables other families. Matching errors and ambiguous contracts still deny control.
- **Changed:** Move, cancellation and priority checks share lazy analysis within one decision and refresh resources and helper validation on the next decision.

### 0.1.65

- **Changed:** Wishlist is included in Toolkit, with one ground-item scanner and sidebar entry. Existing lists and settings retain their identifiers and format. Remove the old Wishlist mod folder and Mod ID when updating; keep its saved data.


### 0.1.61

- **Changed:** Added cargo-dependent cart acceleration/steering, distinct shopping-cart and wheelbarrow turns, and rolling wheel contact.
- **Changed:** Refined the wooden wheelbarrow's anchored grip, natural Walk/Run/Sprint legs, 7-degree turn lean, backward steps and forward/reverse transitions.
- **Fixed:** Smoothed heavy-item braking and the final return to the standing grip, preserving immediate input interruption and hand contact.
- **Note:** Remote cart-pose reconstruction, stationary turns and natural pickup/put-down remain unfinished; these local animation changes do not establish multiplayer equivalence.

### 0.1.58

- **Fixed:** Preserve the verified SP transfer chain when Quartermaster Manifest and SaucedCarts are both enabled.
- **Added:** Guarded native inventory bandaging, including carried-bag pickups, with exact selected items and self-treatment targets.
- **Added:** MiniHealthPlus bandage replacement is one queue operation across removal, pickup and application. Cancellation preserves completed effects and borrowed supplies; lost future materials stop replacement before removing the current bandage.

### 0.1.57

- **Fixed:** First drops of ready-made and handmade splints enqueue treatment with the exact dropped supplies, preserving native clinical restrictions and earlier handlers.
- **Added:** Guarded MiniHealthPlus treatment queue operations with a stable doctor/patient, cancellation and reordering. Bandage replacement and direct inventory-menu treatment remain protected.
- **Fixed:** Preserved reviewed container-getter chains after Quartermaster installs its crafting wrapper; active remote-storage availability scans remain protected.

### 0.1.56

- **Fixed:** Planting inputs such as sunflower seeds, potatoes and herbs gain Farming/Seed tags while preserving their food/medical roles; empty seed packets keep Farming without Seed. Roles come from native crop definitions and seed-packet recipes.
- **Fixed:** Inventory filters, previews and Quartermaster tag rules match individual items, including mixed-category stacks; unrelated items sharing a category or display name are not included. Partial-category tag selections use stable rules across UI languages; manual Quartermaster category/item selections remain additive.

### [0.1.55](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7755743)

- **Added:** Native icons for all 209 defined tags, with shared caliber pictograms and a generic icon for custom categories.
- **Fixed:** Completed known installed category mappings, including the exact `FurnitureDoor` alias; preserved existing exact-category filters after semantic tags are added.
- **Added:** An explicit-source category coverage checker.

### [0.1.54](https://github.com/AlexRedby/pz-survivor-toolkit/commit/e689236)

- **Added:** Combined all/any tag filters with exclusions, grouped search, match previews and named local saved filters.
- **Added:** Persistent Quartermaster container/preset tag rules with server validation, stale-write rejection and peer synchronization; manual selections remain additive.

### [0.1.53](https://github.com/AlexRedby/pz-survivor-toolkit/commit/72b97cdba2399950e24bc76ab9d048519c560eef)

- **Added:** Native pictograms and consistent item-family colours for item tags, including Quartermaster tag choices and inventory chips.
- **Changed:** Combined tag visuals with the medical queue operations from the parallel 0.1.52 snapshot.

### [0.1.52](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7e406a542f4ceff7ea17cba3c7e3eeab8b9836c0)

- **Added:** Localized item tags derived from organizedCategories, inventory tag chips/filters and tag-based Quartermaster selection while preserving exact legacy category IDs.
- **Added:** Guarded native medical queue operations with doctor/patient and wound identity, independent treatment reordering, supported active cancellation and borrowed-tool returns. [Medical source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/1ea939076d6c96be6c1204c0f213486f435a585b).
- **Note:** The tag and medical changes used the same version label on parallel branches; their combined snapshot is 0.1.53.

### [0.1.51](https://github.com/AlexRedby/pz-survivor-toolkit/commit/cc2fb6744d857b23406c7bb43c70798c6447d5ae)

- **Added:** Capacity-aware reordering and cancellation of independent carried-cart transfers, including cart-to-cart routes; shared cargo and in-flight multiplayer transfers remain protected.
- **Changed:** Expanded generator fuel/pickup and fire-operation compatibility with reviewed equipment helpers; holding a cart retains conservative controls.

### [0.1.50](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f2072566509dd919ab5a16adeebcd27d1baa157b)

- **Added:** Queue-aware Better Generator Info connection and power controls, preserving dependencies between shared power areas and buildings.

### [0.1.49](https://github.com/AlexRedby/pz-survivor-toolkit/commit/88590522d1d0dcad9af8bd99bdcfbe13c9eb8634)

- **Fixed:** Kept queued washing/drying attached to the correct live clothing and towel IDs when multiplayer replaces item objects.
- **Fixed:** Skipped returns of already-consumed fire inputs without losing borrowed tools or unrelated queued work.

### [0.1.48](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a083a49a530d4f9eee6c499804d36e08fe161986)

- **Added:** Queued opening and eating for native OpenCannedFood/OpenCannedFood2 recipes, linking full/half/quarter portions to the exact created food item.
- **Fixed:** Prevented late or duplicate results from restarting cancelled eating or consuming unrelated food.
- **Fixed:** Released completed operation records and closed crafting UI owners/listeners instead of retaining them indefinitely.

### [0.1.47](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f26fa4fc610f2842682fdf2ff91d8cd71fd0bee2)

- **Added:** Half and quarter portions for selected-food batches.
- **Changed:** Allowed independent washing and towel-drying operations to move or cancel safely; active native effects and resource use finish before cancellation of later steps.

### [0.1.46](https://github.com/AlexRedby/pz-survivor-toolkit/commit/70513065c473f762a2f61b0f0c26eb521aedac65)

- **Changed:** Matched cart body/hand animation speeds and transitions, and added load-dependent walking turns. Running/sprinting keep native steering; releasing the cart restores ordinary handling.

### [0.1.45](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3bcc56fcab6c8b916fe18759cf38e511c7f686ce)

- **Changed:** Restricted shopping-cart spawns to appropriate retail/warehouse surroundings while retaining wheelbarrows around farm/shed storage. Existing carts and saved spawn decisions are preserved.

### [0.1.44](https://github.com/AlexRedby/pz-survivor-toolkit/commit/2b5d89843512e34e5e50048918189302fcad2d42)

- **Changed:** Combined the guarded cart queue controls and the unsupported-resource inspection fix from the parallel 0.1.43 snapshots.

### [0.1.43](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8a6a28c437ba2dbe7f7856f9bc9fe48316a2e47b)

- **Added:** Guarded queue controls for carried-cart transfers and native single-player cart returns.
- **Fixed:** Restored recursive single-player generator repair across native completion/cleanup boundaries.
- **Fixed:** Stopped unsupported craft/repair inspection from emitting caught-assertion errors; unknown resources remain protected. [Inspection fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ae3cb58d62855f5703d6ed353e2a5670f37e8a17).

### [0.1.42](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6bc32bcf69ebe6275f24a831161ab94054547c82)

- **Changed:** Combined queued bulk eating with the Item Details and cart-equipment fixes from the parallel 0.1.41 histories.

### [0.1.41](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8f6c44dcac8535d85278a4977879667ddf5e00de)

- **Added:** Eat selected batches for eligible ready-to-eat food, with exact item ownership, favourite-item exclusion and independent cancellation.
- **Changed:** A parallel snapshot combined the Item Details and cart-equipment fixes from 0.1.40. Both histories were combined in 0.1.42. [Integration source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ce52f5537cb897a88a8faebeeb68356dc1b02370).

### [0.1.40](https://github.com/AlexRedby/pz-survivor-toolkit/commit/433ef33fab238496318178b547c7d97a09b2c3fa)

- **Fixed:** Restored Item Details condition display/sorting for organizedCategories vehicle parts and preserved every item beyond the configured sorted prefix of large stacks.
- **Fixed:** Cleared stale cart hand slots after Tidy Up Meister cancellation and recognized server-completed multiplayer cart pickup/equip. [Cart fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8aa02a9cebf16ae6d762ecb02622599b3c65167b).

### [0.1.39](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a28ad9ccf454c9406c6977f2b3b6f083cc0a612a)

- **Fixed:** World-electronics dismantling no longer discards following work when multiplayer removes the target before the action completes.
- **Fixed:** Deduplicated the same physical vehicle part exposed through both proximity and real containers. [Vehicle fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/74b924028af5b4380a29d23a7feb7b5817024801).

### [0.1.38](https://github.com/AlexRedby/pz-survivor-toolkit/commit/02593124e27b4e184b334da1b8f914d963ee86be)

- **Added:** Guarded generator and camping/BBQ/fireplace fuel/lighting queue operations, including recursive generator repair, cancellation and borrowed-tool returns.

### [0.1.37](https://github.com/AlexRedby/pz-survivor-toolkit/commit/4a7c270d676ea243394d6172589fdcca7c21f57a)

- **Fixed:** Initialized SaucedCarts drop, unequip and forced-drop safety hooks on dedicated servers, preserving worn-cart cargo and preventing stale hand references from duplicating a ground cart.

### [0.1.36](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ade2c97fc9d04823e694f6a0f1a4ee4e3c9b4581)

- **Added:** Independent transfers through nested carried bags with capacity checks across destination ancestors.
- **Changed:** Single-player capacity checks can account for space freed by a required earlier pickup; multiplayer and unknown capacity effects remain conservative.

### [0.1.35](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ca7efdeb1165527f4254279f9e32304ef737f627)

- **Added:** Reordering/cancellation of independent carried-bag transfers when the proposed order fits available capacity.
- **Fixed:** Kept mixed Tidy Up Meister returns attached to the correct operation while preserving shared equipment cleanup.

### [0.1.34](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c5e33f53e6216239a0458ceb3c4bfac5ba5b623a)

- **Changed:** Expanded safe queue controls to known future craft inputs and supported WashFix, Neat Equipment, Tidy Up Meister and Project Cook continuations; unknown callbacks retain protected controls.
- **Changed:** Stove power requests take priority at safe boundaries, preserve reading and revalidate the desired state instead of toggling twice.
- **Added:** Localized presentation for native action families, separate from their movement/cancellation permissions.

### [0.1.33](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3a3675767f2b0ebe153a537f93030f1b4b0c0442)

- **Added:** Queued burnt/smashed vehicle dismantling without interrupting prior work, with tools/targets rechecked when execution begins.

### [0.1.32](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ae35a65595b0f55a3793125cbc0645e06d62379a)

- **Fixed:** Vehicle refuelling and siphoning select containers and calculate amounts when their turn begins, allowing repeated requests to use the next eligible container without dropping later work.

### [0.1.31](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6f4a3eb5be4f990c39f739cd1bbfe89c10d9d778)

- **Changed:** Grouped native/Neat multicraft and legacy Craft All batches with meaningful progress and cancellation of future continuations.
- **Fixed:** Appliance controls no longer discard unrelated queued work; approach and target validation are deferred until execution.

### [0.1.30](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f7de4db558b526e0fe55e4e2457230016af33a2f)

- **Added:** Safe multiplayer construction interruption/resumption with server acknowledgements from Java Patches 0.1.3; completed builds are never replayed.
- **Changed:** Allowed waiting item repair to cross independent work while protecting matching future donors and shared dependencies.

### [0.1.29](https://github.com/AlexRedby/pz-survivor-toolkit/commit/b3eef8a4b957300e30e7c5f285e02a0bd6694e93)

- **Added:** Supported active operation cancellation and independent native/Neat handcraft reordering, preserving completed results and eligible borrowed-item returns.
- **Fixed:** Sidebar icons no longer intercept native Cooking flyout clicks. [Sidebar fix](https://github.com/AlexRedby/pz-survivor-toolkit/commit/2bfa133af39afda263fe67c1754cef87da460121).

### [0.1.28](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c7cc5f17a49fa95d2bfe483e1c52006b13d6a47c)

- **Added:** Prerequisite crafting plans for native and Neat Crafting: reachable-stock accounting, reusable tools, intermediate chains, material choices and queueing as one operation.
- **Changed:** Combined crafting plans with whole-operation queue controls and the compact sidebar. This is the first retained source snapshot of the planner; the older README also calls it 0.1.27.

### 0.1.27 (documented label)

The older README associates prerequisite crafting with this label, but no separate 0.1.27 metadata snapshot is retained. See [0.1.28](#0128) for the committed planner changes.

### [0.1.26](https://github.com/AlexRedby/pz-survivor-toolkit/commit/07bbc747bc18a5fa0acf1a35762ea61048f2d773)

- **Changed:** Improved EN/RU task labels and target headings, preserving operation titles during preparation and returns.
- **Changed:** Extended whole-operation cancellation and deferred world-action preparation. [Operation source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/2d2175936d7a1f32874552630148a9d4cc923a9d).
- **Changed:** Replaced sidebar squares with compact flashlight/tools icons, settings shortcuts and matching window controls. [Sidebar source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9c0dcb22e6444ccf7b289ac712c7b3bc9c413dac).

### [0.1.25](https://github.com/AlexRedby/pz-survivor-toolkit/commit/17aac2f10643ca5c8999df8048df3b36615951f6)

- **Added:** Collapsible operation groups with expandable native steps and whole-operation dragging/cancellation.
- **Fixed:** Prevented unsafe movement across shared world targets and dependent preparation/return steps.

### [0.1.24](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a88007511440e3ec01857c98ab12eaa525191231)

- **Changed:** Ordered common context-menu actions by purpose and context, while preserving stable ties, unknown commands, manual placements and native selectors.

### [0.1.23](https://github.com/AlexRedby/pz-survivor-toolkit/commit/ec25437cf747e0bde37c877329687f12acc83b8d)

- **Fixed:** Removed exact repeated context-menu commands and duplicate bulk entries while preserving different targets, arguments and mod metadata.

### [0.1.22](https://github.com/AlexRedby/pz-survivor-toolkit/commit/d539d45b8eabc3a5d17654c181c8b0e6caf41de0)

- **Added:** Cut selected clothing for mixed cotton, denim and leather, using native recipes/tools and skipping favourites and worn/held garments.

### [0.1.21](https://github.com/AlexRedby/pz-survivor-toolkit/commit/eee693878b6bfe4ad1a420780ea7bac503c1ac7b)

- **Added:** Automatic context-menu groups and editable per-player rules for placement, hiding and restoring actions.
- **Changed:** Enabled the action queue on fresh profiles and allowed whole waiting operations to move ahead of reading and resume it afterwards. [Queue source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/665ee8b973e2b3809a59e6cb4cf0824f4c57fca1).
- **Added:** Deferred door dismantling and selective cancellation without clearing unrelated work. [World-action source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3a0a88bc1304ebf6fd54fe77e24709bf6afb63f7).
- **Changed:** Added Wishlist-aware ground-highlight priority and preparation/distribution of the complete three-component set. [Wishlist integration](https://github.com/AlexRedby/pz-survivor-toolkit/commit/668b867e30ca174e7144ab944938923ee4aaa99c) and [distribution source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/5808f1329403409f359abd2d6310f4e32d242933).

### [0.1.20](https://github.com/AlexRedby/pz-survivor-toolkit/commit/0ba9f52ad0ff19d658be3711ffdadc9616dc5f97)

- **Added:** Grab amount / Put amount with a whole-number budget across a selected batch.
- **Changed:** Provided medicine/herb indicators directly through MoodleFramework, removing the Medicine Moodles dependency and preventing duplicate indicators.
- **Fixed:** EN/RU TV device recognition, Better Containers category-filter integration and malformed MP Fast Forward speed commands.
- **Added:** Optional native action-queue window with icons, per-row cancellation and guarded drag reordering. [Initial queue](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9756eccd63e8b4e9912c533522a80f126d7ab981) and [row controls](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6ed594650371ee1b54af058bfe1077fbdd0c46a4).

### [0.1.19](https://github.com/AlexRedby/pz-survivor-toolkit/commit/74cb8b717dde00fa26522de03d75b5a062bd71a0)

- **Added:** Bulk battery removal, magazine/firearm unloading and weapon-attachment removal with native tools, outputs and item identities.
- **Changed:** Corrected server-derived medicine effects and added independent herbal indicators, including dried herbs. The older README refers to this medicine work as 0.1.16; this is its first retained source snapshot.
- **Changed:** Fitted Navigator to vanilla/Realistic Dashboard styles with a compact textured housing and live rollback.

### 0.1.16 (documented label)

The older README associates medicine indicators with this label, but no separate 0.1.16 metadata snapshot is retained. See [0.1.19](#0119) for the committed medicine changes. No distinct functional record for 0.1.17 or 0.1.18 is retained.

### [0.1.15](https://github.com/AlexRedby/pz-survivor-toolkit/commit/d9ebdf52419187ce4520cfac67074d7dd4882dc5)

- **Changed:** Combined vehicle-part removal to the ground with bulk electronics dismantling and contested-pickup protection.

### [0.1.14](https://github.com/AlexRedby/pz-survivor-toolkit/commit/449337180d795f94f747d20a0176d0c7c7050fac)

- **Fixed:** Preserved native dismantling recipe icons/submenus and stopped rejected bulk pickups from cancelling another client's same-numbered transaction.

### [0.1.13](https://github.com/AlexRedby/pz-survivor-toolkit/commit/8fbb425f1bd49bdbadd4cde81e5f3fe057fe3881)

- **Added:** Optional bulk dismantling of selected electronics with native recipes, tools, outputs and XP.
- **Added:** A parallel 0.1.13 snapshot added Uninstall to ground for removable vehicle parts, preserving native tools, duration and success/damage chances. Combined with bulk dismantling in 0.1.15. [Vehicle source](https://github.com/AlexRedby/pz-survivor-toolkit/commit/88ee47cc4a939eb99bd31a6b8ab2c0344d122d1f).

### [0.1.12](https://github.com/AlexRedby/pz-survivor-toolkit/commit/b5bdd893b273a2658e6e369aec5299794059f141)

- **Fixed:** Kept CCI item/container-button bars working across CleanUI enhanced/vanilla modes and icon views, including native icon alpha.

### [0.1.11](https://github.com/AlexRedby/pz-survivor-toolkit/commit/195b5bc82a4786243a1f4ebd34bc52fef1caf0bb)

- **Fixed:** Preserved manually selected Proximity Inventory loot containers across automatic source/destination selections without bypassing native container locks.

### [0.1.10](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9b9f5410a9a7bf5e00443f6b374db7a201c1150d)

- **Fixed:** Preserved inventory marquee selection across refreshes.

### [0.1.9](https://github.com/AlexRedby/pz-survivor-toolkit/commit/a1efc520c0feeffa221faffd670cedcf2e89ec03)

- **Added:** Inventory category filters.
- **Fixed:** CleanUI inventory layout integration and Manage Containers controls in both enhanced and vanilla inventory modes.

### [0.1.8](https://github.com/AlexRedby/pz-survivor-toolkit/commit/896ff3526ce0ed8a12368aedc6f4f9dbab8a0b00)

- **Fixed:** Marked only fully watched VHS tapes as completed for the current character.

### [0.1.7](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7a0fbcd204663f4bbdd3c00070fec86cd5de288d)

- **Added:** VHS selection from reachable containers/bags, drag insertion and direct click-to-eject using native inventory/device actions.

### [0.1.6](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7b62819b8e758a4e9d15d19cba231a7559eebea6)

- **Added:** Independent switches for the sidebar highlight button and neutral clothing comparisons.

### [0.1.5](https://github.com/AlexRedby/pz-survivor-toolkit/commit/7b8b438399f578208144b11413a38b7eba229cd9)

- **Fixed:** Hid optional-mod settings and skipped their integrations when the corresponding mod was inactive.

### [0.1.4](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c4f86df469bc8a9fb3083a632b4310dfafa81037)

- **Added:** Configurable TV/radio window persistence and native macOS video lookup in the active TV mod directory, without a Workshop-path symlink.

### [0.1.3](https://github.com/AlexRedby/pz-survivor-toolkit/commit/1cad3f4b24e3d8bbecb44f9f5b23d16b9c6749a8)

- **Fixed:** Aligned Container Capacity Indicator bars with CleanUI inventory rows, equipment headers and scaled icons.

### [0.1.2](https://github.com/AlexRedby/pz-survivor-toolkit/commit/e91b9225d7fbc3e2a12c952f268f74f819752377)

- **Fixed:** Used each multiplayer player's auto-drink preference instead of the host's saved global option, including option reloads.

### [0.1.1](https://github.com/AlexRedby/pz-survivor-toolkit/commit/6d23b177b9661102e02fdd2ca5c8c2dc5f562b2e)

- **Changed:** Displayed zero clothing-protection differences in neutral grey while retaining native improvement/degradation colours.

### [0.1.0](https://github.com/AlexRedby/pz-survivor-toolkit/commit/3926508d2d421ddc021aef1032f914e335eec95d)

- **Added:** Visible loose-item highlighting, native Mod Options for colour/radius/shortcut, an F8 shortcut and sidebar toggle.
- **Added:** Mod icon and localized selection metadata.

## Survivor Wishlist

### [0.1.0](https://github.com/AlexRedby/pz-survivor-toolkit/commit/668b867e30ca174e7144ab944938923ee4aaa99c)

- **Added:** Independent personal and shared wishlists, with a searchable item catalog, desired quantities, carried-item counts and manual completion.
- **Added:** Shared editing for named players or a faction, owner-controlled access, revision-conflict protection and persistent lists separated by world.
- **Added:** Inventory-menu and native/Neat Crafting/Neat Building/Project Cook integration for adding wanted items, recipe results and missing ingredient choices.
- **Added:** Highlight wanted inventory rows and visible loose ground items, with CleanUI and Better Containers support and independent highlight/crafting settings.
- **Added:** English and Russian UI, a configurable K shortcut and sidebar access.
- **Changed:** Replaced the standalone sidebar text button with a compact tools icon, integrated Wishlist access into Toolkit's sidebar menu and matched button styling.
- **Fixed:** Prevented the standalone Wishlist sidebar icon from blocking the native Cooking flyout's clicks, and kept the icon aligned with sidebar visibility and scaling.

## Toolkit Java Patches

### 0.1.39

- **Fixed:** Cancelling wooden-wheelbarrow setdown while running now returns the handles to the current movement pose, avoiding the jump from an idle endpoint. Moving pickup recovery preserves the knee's forward bend when a lifted toe changes direction.

### 0.1.38

- **Fixed:** The male character's right trouser leg no longer clips the wooden wheelbarrow handle during the checked single-player emergency wall-fall transition. A short, smoothly blended knee adjustment preserves the foot, pelvis, actor root, stationary cart and native backward recoil. Female poses and Host behavior are unchanged.

### 0.1.37

- **Fixed:** After a confirmed single-player wooden-cart emergency release, the character no longer steps forward through the stationary cart. The bounded impact episode preserves the stock backward recoil, lateral motion and obstacle collision, and clears on state or ownership changes.

### 0.1.36

- **Fixed:** Wooden-cart emergency release preserves the rendered axle position and eases the handles down over 240 ms. The exact-item transition survives the native floor-inventory projection, restores pooled renderer state and clears on pickup, expiry or world exit. This presentation fix applies to single-player; stock fall motion and its remaining body overlap are unchanged.

### 0.1.35

- **Fixed:** Remote wooden-wheelbarrow rendering validates a shared character/cart pose against nearby obstacles, with matching camera and model depth and a gradual correction release. Native movement, manual reverse and cart synchronization traffic are unchanged.

### 0.1.34

- **Fixed:** Tiny accepted coordinate changes no longer repeatedly release wooden-cart pushing effort at a blocked obstacle. Forward contact is checked independently from the exhausted root-motion budget; releasing input, reversing or clearing the obstacle releases the stance. Native movement/collision and manual reverse are preserved.
- **Changed:** Cart pose synchronization carries an effort flag in its existing packet fields and rate budget; remote catch-up retains its required locomotion before entering the planted pose.

### 0.1.33

- **Changed:** Calibrated cadence and outgoing-gait clearance for the wooden wheelbarrow's authored pivot clips. Exact cart-type selection is derived locally for owners and observers without adding network fields.

### 0.1.32

- **Fixed:** Wooden carts keep a consistent collision-constrained path while aligning with a wall. Established contact preserves tangential travel and accepts only the inward movement made safe by the planned turn, preventing alternating sidesteps without changing manual reverse or wall clearance. Contact steering follows the native animation movement budget, avoiding residual sidestep flicker when deferred motion and the current frame have different durations.

### 0.1.31

- **Fixed:** Wooden wheelbarrow steering no longer accumulates yaw from rounded world coordinates after releasing the keys. Manual wall exits keep the requested turn direction while collision checks limit travel and rotation. Forward wall sliding finishes aligning with the wall and releases guidance when steering away or releasing forward movement.

### 0.1.30

- Smooth the grip during wooden wheelbarrow pickup and setdown, preserving the thumb pose through the native transition into holding the handles.

### 0.1.29

- Center the wooden wheelbarrow pickup approach while preserving native collision and final handle alignment.

### 0.1.28

- Prevent the inventory-icon silhouette from flashing when highlighting a wooden wheelbarrow in 3D. Preserve the orange model highlight and native sprite outlines when 3D ground items are disabled.

### 0.1.27

- Keep the wooden wheelbarrow grip continuous during setdown when native multiplayer position lag requires a little more shoulder reach; preserve hand targets, bone lengths and world placement.

### 0.1.26

- Use heading-relative keyboard controls for shopping carts and both wheelbarrows: forward/reverse motion and continuous left/right steering, preserving native movement and collision handling.
- Reconstruct cart grounding, grip, banking, wheel rotation and wooden pickup/setdown presentation for remote players from small throttled state snapshots, with identity, native-action and lifecycle guards.

### 0.1.25

- **Changed:** Startup patches own their bytecode contracts and installation checks instead of keeping those details in the central dispatcher; patch guards and gameplay behavior are preserved. Refactored under this existing version label in `4fc28c8`.
- **Version:** The forge candidate was locally labeled 0.1.23 during live verification; 0.1.25 integrates it without replacing the concurrent medicine and TV releases below. The historical live run does not cover every subsequently merged upstream change.
- **Fixed:** Refresh a registered workstation's stale spatial entity ID before decoding its CraftBench reference on the server. Removing an earlier object from the same square could otherwise cause `loadComponent` to throw while accepting a crafting request, leaving the client at 100% progress. Recovery requires the exact already-resolved workstation and matching incoming ID; no recipe effects are forced or replayed.
- **Checks:** Reproduced the 100% Forge Simple Blade stall in a disposable Windows Host world with all 48 selected mods and Java Patches 0.1.22. The same fixture with 0.1.23 passed ordinary hand crafting, unchanged-forge crafting and crafting after a real earlier-object removal: one blade, one charcoal/iron debit, conserved tool IDs and idle native action/UI. Only the Java mod changed. Native decoder/medical regressions also passed. Both live runs retain seven client font-loading errors; the fixed run has no server action errors but remains runtime `needs-review`, not a clean whole-pack acceptance. No macOS, WAN or second-client coverage is claimed.

### 0.1.24

- **Fixed:** Resolve recognized TV & Radio ReInvented video paths from the active mod directory on macOS, preserving native cache keys, dimensions and synchronous/asynchronous loading.

### 0.1.23

- **Added:** A guarded, read-only Lua accessor for the native food-sickness treatment cooldown in single-player and on the multiplayer server.

### 0.1.22

- **Added:** Wooden-wheelbarrow footprints respect walls, doors and vehicle hulls while allowing wall sliding. Tight contact requires a manual reverse manoeuvre before turning out.
- **Fixed:** Preserved full native lateral strides and anchored grip during stationary turns, smoothed bank reversals and improved handle clearance during side steps.
- **Fixed:** Preserved wheel rotation and floor contact across pickup, setdown and cancellation; native wall-impact recovery releases the cart through SaucedCarts.
- **Note:** These cart changes are client-local; multiplayer visual reconstruction and the remaining body/clothing contacts are not declared complete.

### 0.1.19

- **Added:** Side input from rest turns the wooden wheelbarrow with native lateral steps around its front wheel, then resumes pushing. Run/Sprint wait until the pivot finishes; opposite input retains backward movement.
- **Changed:** Stationary turns use full native lateral strides; cargo changes their cadence, preserving turning speed without rapid idle-blended shuffling.
- **Fixed:** Releasing a stationary turn consumes no residual sideways movement as an unwanted forward step. Native collisions still determine accepted rotation.

Previously named **PZ Network Fix** through 0.1.1.

### 0.1.18

- **Added:** Guarded client cart movement, pose/grip, grounded wheel rendering and cargo-dependent pace for the selected carts and wheelbarrows.
- **Fixed:** Preserved native gait cadence during transitions, capped braking by release speed and retained cart contact while heavy-item stops settle.
- **Changed:** Consolidated the cart candidate with the existing animal, equipment and hutch fixes. Native collisions and server-authoritative item ownership remain unchanged.
### 0.1.15

- **Fixed:** Rejected a late server medical action whose BodyPart owner disconnected before argument decoding. Native Reject acknowledgement replaces the null-player exception; valid requests and existing queued actions remain native.
- **Fixed:** Ignored an in-flight body-damage UPDATE after its patient disappeared from the client, preventing the native null-player exception. Valid health updates and subscription control packets retain native behavior; exact B42.21 bytecode is required.

### 0.1.10

- **Fixed:** Reconciled occupied-vehicle physics authority with the validated server driver after the reproduced collision/entry/release race, preserving towing ownership and native packet authorization.
- **Added:** Bounded, opt-in vehicle diagnostics with `-Dpz.vehicle.trace=true`; the ownership repair itself needs no flag. Updated server/client setup and platform-specific collection instructions.
- **Changed:** Combined vehicle recovery with the native string-property, fluid-container, fence-validation and early font-page guards from main under a distinct version. The vehicle-recovery candidate in a controlled macOS Host with two connected clients passed post-repair travel, towing/detachment and driver/passenger handoffs; spontaneous user-save and real WAN-loss incidence remain unverified.

### 0.1.9

- **Fixed:** Deferred native fence validation until script loading completed and corrected early font-page resolution. The font guard uses a separate local bootstrap JAR with explicit early loader activation.

### 0.1.8

- **Fixed:** Normalized the two shipped fluid-container name tokens `Large Bucket` and `Fuel Pump` before native parsing, preserving validation for other names.

### 0.1.7

- **Fixed:** Preserved five shipped native string properties without startup enum lookup exceptions, keeping alias IDs, values and string storage.

### [0.1.6](https://github.com/AlexRedby/pz-survivor-toolkit/commit/761aea81f0c699c34b3a41709d49cecc662dda94)

- **Fixed:** Prevented the B42.21 hutch-unloading crash caused by empty animal slots, while preserving existing animals and the original hutch data in clients, single-player and servers.

### [0.1.5](https://github.com/AlexRedby/pz-survivor-toolkit/commit/c3ad1e0aabec486e34e41caa76449c8b125a48f6)

- **Fixed:** Prevented incomplete equipment acknowledgements from clearing a just-grabbed animal from the local player's hands when equipment packets arrive before the animal transfer.

### [0.1.4](https://github.com/AlexRedby/pz-survivor-toolkit/commit/bd6d1088d8fb9a81219b6e4c7b15cd1446757fae)

- **Fixed:** Removed stale or duplicate client trailer membership when an animal's server-reported location changes to the world, a hutch or an inventory, correcting ghost animals and occupied trailer capacity.

### [0.1.3](https://github.com/AlexRedby/pz-survivor-toolkit/commit/f7de4db558b526e0fe55e4e2457230016af33a2f)

- **Added:** Server build acknowledgements that let Toolkit safely interrupt and resume multiplayer construction after confirmed cancellation, without replaying completed builds.
- **Added:** Optional programmatic game-window recording through Lua or Java for isolated test profiles, producing silent H.264 MP4 through FFmpeg without automatic recording or a new game menu.

### [0.1.2](https://github.com/AlexRedby/pz-survivor-toolkit/commit/9edadea9de0f5464b36197bb207ca9827b15aec0)

- **Changed:** Renamed PZ Network Fix to Toolkit Java Patches, including the local Mod ID, JAR and Java package; existing installations must enable `PZToolkitJavaPatches` instead of `PZNetworkFix`.
- **Added:** A macOS Host launcher that loads ZombieBuddy in the client and separate Host server process, using the bundled Apple Silicon or Intel Java runtime and refusing duplicate loader arguments.

### [0.1.1](https://github.com/AlexRedby/pz-survivor-toolkit/commit/aa101d6090c6612e867775b001caca90e8577c9b) (PZ Network Fix)

- **Fixed:** Prevented server-authoritative cassette/VHS playback from stopping again after a quick Stop/Play sequence.
- **Changed:** Packaged the Java patch for both clients and servers instead of the client-only Java directory.
- **Added:** A Windows Host launcher that passes ZombieBuddy to the child server process and avoids adding a duplicate client loader.

### [0.1.0](https://github.com/AlexRedby/pz-survivor-toolkit/commit/b8423c527640019fd246e172e1a9914a003b8691) (PZ Network Fix)

- **Added:** Experimental B42.21 client patches for remote zombie speed decoding and vehicle interpolation recovery, with ZombieBuddy and per-class bytecode guards that disable unsupported patches.
- **Fixed:** Corrected standard Steam game-path defaults for Windows and Linux and added clear missing-JAR checks.
- **Fixed:** Required JDK 25 or newer to read B42.21 game dependencies while retaining Java 17 output compatibility.
