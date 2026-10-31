# Shared queue resources and container capacity

Status: implementation plan, not a delivered runtime feature. The performance gate below must pass before the proposed mechanism grants additional move/cancel permissions. Open implementation work is tracked in [TODO](../../TODO.md#shared-queue-resources-and-container-capacity).

## Goal and boundaries

Allow independent actions to be cancelled and reordered regardless of where an item came from, while preserving real prerequisites, native inventory rules, authoritative item effects and required cleanup. Use one contract for the queue's resource decisions instead of adding action-pair exceptions.

The executor stays `ISTimedActionQueue`. Existing native action durations, resource costs, selection intent and game balance remain authoritative. This is not a generic undo system: completed consumption, creation, XP and pages are retained, never replayed or restored from an old world snapshot. Do not impose a new universal carry limit, silently change native overload rules or modify a user's saves.

The current bug provides the first acceptance case: borrowed-book reading with an automatic return can block whole-operation cancellation and promotion of an ordinary equip action because of a blanket equipment/transfer capacity conflict. Root-only reading can pass the same edit. The source-backed regression identifies this false denial; live coverage of the new bank is still pending. A root-held pen is not automatically neutral under every mod's equipment callbacks.

## What exists and what changes

| Existing boundary | Reuse | Required change |
|---|---|---|
| `ActionQueueDefinitions` and family inspectors | Routing, labels, source/callback proofs | Compile reviewed behavior into one versioned effect contract; presentation grants no permissions |
| `ActionQueueEditModel` and edit adapters | Declarative facts, requirements and effects | Add capacity/ancestry and execution capabilities without a parallel action-type allowlist |
| `ActionQueuePolicy` | Fresh decision contexts, disjoint-footprint fast paths, live queue snapshots | Replace the duplicate capacity ledger and blanket conflicts for qualified contracts; index affected dependencies |
| `ActionQueueWeights` | Native rounding, safe weight bounds, factory-free reads | Capture each relevant item/container once per decision; share nested aggregates without impure factory/getter calls |
| `ActionQueueLifecycle`, `Operations`, `Reading`, `TidyIntent` | Native stop/resume, operation identity and explicit equipment intent | Consume the common contract while preserving their timing and ownership responsibilities |
| `ActionQueueSettlement`, `Acknowledgements` | Exact item/endpoint receipts, queue generations and earned cleanup | Generalize item outcome observation; ordinary item transactions need their own evidence, not just timed-action ACKs |
| Java `ItemBatchAdmissionLogic` | Native-request batch admission and scoped accounting | Fill only demonstrated admission gaps at the actual native transaction boundaries; do not reserve the whole future queue |
| Queue panel and common scenario runner | Hover cache, press/release revalidation, selected-pack controls and log audits | Show forecast uncertainty separately from proven dependencies; add bounded profiling and migration coverage |

Storage tools such as Smart Deposit and Quartermaster retain their routing rules. They can reuse a qualified shared weight/admission primitive where appropriate, but this plan does not authorize rewriting unrelated storage features. Their native transfers remain regression consumers of changes to a shared transfer boundary.

## Contract and decision flow

### One contract, three distinct answers

A reviewed action descriptor identifies its version and binding, exact item identity/type or a bounded late-selector scope, endpoints/ancestors, resource reads and writes, native prerequisites, bounded weight/quantity effects, interruption capability and required cleanup ownership. It also declares whether execution has a verified live admission and outcome boundary.

Extend the current declarative representation rather than making a second interpreter. Compile stable descriptor structure once for the verified binding; capture mutable facts afresh for each authoritative decision. Adapters describe effects; they never execute `isValid`, item factories, recipe callbacks or world mutations to discover those effects. Unreviewed callbacks and ambiguous ancestry remain explicit unknowns.

1. **Forecast:** project the affected resources in the proposed order. Return a proven dependency conflict, a safe forecast, or conditional/unknown capacity with its cause. A forecast does not reserve space or prove execution.
2. **Admission:** resolve live resources and validate native restrictions immediately before each mutation/request, including subsequent entries or batches created by the same action. A check only at `perform` is too late if `start` already submitted the transaction.
3. **Outcome:** associate the native result and observed effects with the exact operation, step, queue generation and attempt. Report confirmed success, rejection without effects, partial effects, or unresolved outcome. Queue disappearance and completion callbacks are not receipts.

Capacity uncertainty alone may stop being an edit barrier only for a reviewed contract with a safe execution boundary and defined failure/cleanup behavior. This does not relax unknown resource dependencies, custom callbacks, active paid effects or unsupported interruption. If the bounded proof is unavailable, retain the existing native/protected path with an accurate reason.

### Projection and container rules

- Distinguish an item's physical weight, its effective contribution while held/worn/attached, each nested container's load and the actor's native inventory rules. Read hard capacity and trait effects from the native endpoints; actor encumbrance is a separate soft limit.
- Start from current observed facts. Index item, container/owner, hand, device and other relevant domains, then visit the changed interval and its transitive dependency closure. Include preceding effects needed to establish its state and all later consumers/cleanup whose prerequisites could change; the crossed interval alone is insufficient.
- Track intermediate peak occupancy, not just final net weight. A pickup followed by consumption or return must fit at the pickup boundary. A replaced item, fluid change or nested bag can change more than one capacity domain.
- Represent uncertain effects as bounds/unknowns. Never spend hypothetical freed MP space as already available. A forecast may describe a conditional release; only actual confirmed effects update the execution snapshot.
- Reuse existing safe weight bounds and outward rounding. Do not call getters that can create extra-food items merely to obtain an exact weight. Cycles, malformed graphs, NaN/overflow and unsupported acceptance functions cannot produce a permission grant.
- Keep active steps outside speculative replay. Saved pages/checkpoints enter the observed state; native stop/drain and reconstruction of a supported remainder remain lifecycle responsibilities.

### Multiplayer and failure handling

Stock B42.21 item request admission checks and the existing batch patch are not an atomic commit: native transactions can apply entries sequentially, and acceptance does not guarantee the world is unchanged when effects occur. The native ID-based actor-root path also differs from ordinary box capacity checks. Preserve these semantics unless a separate demonstrated bug justifies a targeted correction.

Reuse native short-lived transfer accounting where possible. Any additional reservation is scoped to an admitted native attempt and released on every terminal/timeout/disconnect path; it must not lock a container for a minute-long planned queue. The client forecast is never server authority. Do not introduce per-frame capacity polling packets, full inventory broadcasts or one new round trip per recipe ingredient unless a measured correctness gap requires it.

`isItemTransactionDone` alone is insufficient: absent transactions can appear both done and rejected. Extend Settlement's existing exact-ID/type, source absence and destination observation with native transaction evidence. If evidence conflicts or expires, reconcile the affected IDs/endpoints; do not retry a possibly committed step automatically. A native batch may have a committed prefix, which must be retained and excluded from retry.

A failed step invalidates its dependent remainder, not unrelated queue work. Keep an earned return obligation visible when storage has filled or disappeared; preserve the actual item and current container, with a bounded retry only when safe or explicitly requested. Do not teleport, duplicate, delete or drop it into an arbitrary fallback container. Explicitly cancelling an optional book return keeps the book with the actor and lets reading continue, as already requested. Cleanup with paid effects or another live owner cannot be waived this way.

Bind deduplication to the native episode and queue generation, not a reusable byte ID or action type. Bound retained attempts, deduplication records and reconciliation timers. Window teardown releases UI caches/listeners only: it must not discard an admitted transaction, its evidence or earned cleanup. Queue reset, death and disconnect detach old ownership from new work while preserving admitted effects and cleanup through a terminal outcome or bounded reconciliation; an unresolved result remains unknown and cannot be replayed. An old receipt must never grant permission for a new queue.

## Performance gate before runtime integration

Performance has priority over this architecture. Source inspection has identified risks, not measured a passing candidate:

- `transferCapacityConflict` builds one proposed prefix per decision, but repeated root and nested-container weight snapshots can traverse overlapping item trees. `Weights.unequipped` also creates a separate context for each item.
- `editComponent` grows connectivity through repeated scans. Complex/reverse dependency chains need a worklist/index prototype and scaling measurements; the existing disjoint fast path must stay cheap.
- The panel already evaluates only the relevant hovered row and caches advisory text for 250 ms. Preserve this; do not simulate the full queue for every rendered row.
- A blocked urgent action can be reconsidered on successive ticks. No new full inventory capture or projection belongs in every such retry. A retry scheduler may reuse an advisory denial until a relevant change or bounded recheck, but may never reuse it as execution permission or indefinitely starve progress.

The CPU prototypes have not passed the general gate. The implementation direction is therefore the smaller common-contract/admission/outcome design, preserving cheap native/stateless checks. Do not require a whole-inventory/whole-queue projection for every family or edit. Keep the adaptive worklist and batch weight snapshot in development tests; they grant no runtime permissions. The worklist preserves the ordinary first sweep and indexes unresolved transitive growth. The snapshot scans overlapping topology once and reuses production arithmetic, but its allocation/capture cost regresses plain flat/native-exact cases. A nested-case speedup is insufficient for universal adoption. Any later integration needs a cheap, verified eligibility rule and independent performance/correctness qualification for both the selected and fallback paths. See the [opt-in CPU bank](../DEVELOPMENT.md#queue-resource-performance-prototype) for reproducible measurement and its limits. Live selected-pack evidence remains necessary before any permission expansion.

The initial admission/outcome slice is deliberately bounded: at most 32 queued native steps and 128 private borrowing-record visits, with eligibility checked before suffix work. Only source-verified reading, walking, owned deferred approaches, hand equipment and supported radio/TV setter suffixes enter this proof. Larger queues, complex recipe inputs, future transfers and changed target helpers keep the previous protected/native path. Negative-path CPU scaling and a tiny live UI bank do not qualify positive 32-step Policy/Panel cost or multiplayer contention; measure those separately before extending this scope.

### Baseline and candidate measurements

Before implementation grants permissions, add opt-in profiling at the existing boundaries and a nonauthoritative prototype. It must use the production model and weight routines where applicable, not a toy calculator. Run identical deterministic workloads in the game's native Kahlua and collect exclusive, selected-pack native UI/Host measurements. Lupa checks support correctness and counters; they do not establish runtime timing.

| Workload | Required evidence |
|---|---|
| Closed/idle panel, visible unhovered rows | Zero added forecast calls, world/item scans and packets |
| Hover, stationary and moving drag | Rebuild counts, cache hits, p50/p95/p99/max latency and allocation/GC cost |
| Move/cancel press and release, priority attempt | Fresh authoritative reads, exact outcomes, repeated-attempt cost |
| Independent and reverse-dependent queues | Scaling at 10/50/200/1000 steps; unrelated tail must not create pair products |
| Root, nested and worn bags, full containers | 100/1000/10000 relevant items, shared ancestors, varied nesting, changing quantities |
| Unknown/mod callbacks and malformed inputs | Cheap protected result; no callback invocation or log flood |
| Host contention, delayed/duplicate/partial outcomes | Admission overhead versus native control, packet/byte counts and bounded reconciliation |
| Repeated queue/UI lifecycle | Retained records, timers, listeners and memory return to a bounded steady state |

Archive provenance and raw samples in fresh runner artifacts; report warmed and first-use costs separately. Keep counters cheap and profiling off in ordinary gameplay. Compare the current implementation, the candidate in observation mode and queue-off native controls with identical sources/state. Use one prepared code-built world and batched scenarios, not one launch per vector. Native timing captures require exclusive runner admission.

### Acceptance budgets and decisions

Freeze concrete budgets from the baseline before candidate tuning. Initial engineering targets for the normal bank (up to 200 steps and 1000 relevant items) are p95 <= 1 ms / p99 <= 2 ms per advisory rebuild and p95 <= 2 ms / p99 <= 4 ms for a complete authoritative edit, with no new frame/tick stutter. These are proposed gates, not measured results or performance claims about weaker clients. Record any baseline-driven adjustment and rationale before comparing the candidate; do not raise the budget afterward to obtain a pass.

For stress workloads, use bounded advisory work slices targeting <= 1 ms, a hard work/memory ceiling and explicit pending/unknown status rather than blocking the game thread. A final authoritative check must be fresh and bounded; if it cannot finish safely, leave the queue unchanged and report that limitation. Do not turn a time or size limit into an allow decision. Single unbounded native calls cannot be hidden by slicing surrounding Lua work; measure them and exclude, bound or replace those paths first.

The structural targets are one capture per relevant item/container within a decision and work proportional to the visited facts/effect edges, not all action pairs or repeated full subtrees. Snapshot validation remains fresh even if the display cache is stale. Event dirtiness, item counts and a TTL are not complete stock revision proofs; do not persist authoritative decision contexts across edits. Do not amortize the same expensive scan over every tick while claiming it is incremental.

Server work must remain local to the actual affected request; assess both absolute latency and overhead against the native admission baseline, plus packet rate and throughput under contention. A relative regression above 10% in a nontrivial admission path requires investigation, not automatic rejection of all extra validation; a near-zero baseline needs absolute timing. Freeze its acceptable absolute budget before integration. Queue-off consumers must not acquire background forecasts, additional packets or altered success/failure behavior.

If a target fails, first try decision-local snapshot memoization, shared ancestry aggregation, indexed dependency worklists, smaller affected scopes and bounded advisory scheduling. Recheck correctness as well as timing. If safe bounded projection still cannot meet the budget, stop the general forecast expansion and use the smaller design: common effect declarations, fresh per-step native admission, verified outcomes and conservative edit proofs for supported cases. Do not disable capacity/resource protections to make the benchmark pass. Failure of this gate is an acceptable reason to reject the full system.

## Implementation sequence and migration

Each phase depends on the preceding gate. Do not ship an unbound prototype as a new permission path.

1. **Baseline and go/no-go:** use the CPU bank to compare scaling, latency and allocation of shared snapshots and indexed closure. The current decision rejects unconditional projection in favor of the smaller admission design. Complete its applicable native UI/Host/network/retention gates and frozen budgets before permissions change; do not reopen a universal forecast merely because one stress case becomes faster.
2. **Common contract and first vertical slice:** extend the existing model and adapters for reviewed direct transfer, reading, simple equipment and device setters. Route book pickup/read/return, root pen equip and TV volume through the common path. Preserve full-pack callback/event proofs. Keep this phase in observation mode: replacing the blanket denial and granting new permissions also requires the applicable admission, failure/outcome and earned-return checks in phase 3. An old denial may be a false positive, so compare semantic/effect evidence rather than demanding identical booleans.
3. **Transfer execution and item outcomes:** reuse and generalize existing native admission/Settlement boundaries, including the next transfer batch. Qualify changing capacity, failed/partial transfer, remote competing actor and required return. Enable the first slice only after these execution checks and its functional/performance controls pass. Add Java/server changes only for demonstrated uncovered boundaries, source-gated to the supported build. No broad `ItemContainer.AddItem` interception or snapshot rollback.
4. **Migrate in effect-based batches:** use the ledger below and the common scenario contracts. Keep the native producers/executors. Remove replaced family capacity/dependency bypasses in the same qualified change; any temporary legacy branch gets an owner, reason and concrete removal gate in TODO.
5. **Consolidate and release:** verify no applicable capacity/edit consumer still chooses between two authorities, remove the old capacity algorithm and temporary observation code, repeat bounded performance/lifecycle and selected-pack SP/Host controls, audit logs, bump only changed shipped components above latest main and record delivered behavior. Deployment to the user's game needs its own request.

### Coverage ledger to implement

Generate a ledger from registered action types/adapters, joined with scenario evidence. Every existing queue family needs an entry, including unsupported or not-applicable effects. Track contract version/binding, capacity and dependency domains, late selectors, interrupt/cancel/recovery capabilities, admission owner, outcome/cleanup owner, legacy fallback/removal gate, focused/native/queue-off evidence and performance profile. An absent adapter must not disappear from coverage; source catalog presence is not a test pass.

| Migration batch | Existing consumers | Additional gate |
|---|---|---|
| Read, approach, media and ordinary item transfer | Policy, Reading, Approach, Media, ItemEditAdapters, TidyIntent | Root/bag/world book controls, saved pages, nested peak load, exact returns, final explicit equipment intent |
| Equipment and restoration | Native equip/unequip, Compat, Settlement, TidyIntent | Hand/worn/attached weight changes, heavy-drop/back conversion, equipment events, shared cleanup ownership |
| Food, fluids and container selection | ItemEditAdapters, consumption/bulk adapters, water and fuel producers | Native portions, replacement/depletion, exact nutrition/fluid deductions, resolved cans/bottles, no speculative capacity credit |
| Crafting and Project Cook | Craft, plans/fetching, ingredient and spice cleanup | Outputs/intermediate peaks, callbacks/late selection, paid inputs, partially applied ingredients and joining-client receipts |
| World and tool actions | World, Fire, Generators, Firearms, wreck/fuel adapters | Target/tool changes, quantity/charge costs, late approach and independent tail |
| Health, hygiene and fitness | Health, Fitness and hygiene adapters | Patient/prop identity, movement/placement, active effects and mandatory restoration |
| Animals, cosmetics and cart-related queue actions | Animals/AnimalStops, Grooming/GroomingCosts, Makeup/MakeupMove, Carts | Yield and replacement effects, special containers, event/visual dependencies; retain family proofs until separately qualified |
| Unknown mod producers and recovery | Definitions routing, NativeContinuation, Recovery/RecoveryAdapters | Explicit footprint/capability gaps, asynchronous continuation, untouched reconstruction only where proven; no automatic replay of partial/unknown effects |

This is a migration of queue resource decisions, not a mandate to rewrite the cart protocol or every family's executor. All families use the same decision vocabulary; support remains capability-based rather than pretending every action can be interrupted or undone.

## Functional qualification and completion

Use the existing scenario matrix, extend it with reusable resource variants, and batch by world/mod pack rather than launching per action. The first bank already covers root, worn military bag and world shelf reading through real panel cancel/drag handlers; complete that bank instead of inventing a second book fixture.

Required common variants include empty queue, repeated requests, favorite/nonfavorite items where relevant, nested and near-full storage, capacity changing after a permitted edit, lost/replaced IDs or endpoints, late selectors, required versus optional cleanup, active versus untouched work, native batch continuation with a committed prefix and rejected remainder, no replay of committed entries, native failure, partial effects, reset/disconnect and late/duplicate outcomes. Two actors must compete for the same finite container on actual menu Host, including the joining-client view. Synthetic receipt tests supplement that check.

For each migrated family compare the same native producers with the queue disabled and enabled in SP/menu Host using isolated settings/saves and the current locked selected pack. Assert exact item/quantity/nutrition/output effects and independent tail behavior, not just queue emptiness or a full progress bar. Separate input-handler simulation from physical GUI coverage. Keep whole-operation and child controls distinct.

Completion requires the measured performance gate, no duplication/loss or unpaid results in the affected matrix, no new unclassified runtime errors, explicit unsupported cases and removal of superseded checks. A partial bank does not establish all action combinations, all mods or performance on other machines.
