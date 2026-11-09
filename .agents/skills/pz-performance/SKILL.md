---
name: pz-performance
description: Investigate PZ Survivor Toolkit performance problems with reproducible gameplay scenarios, evidence-driven bottleneck selection, purposeful experiments and cross-chat reuse of negative results. Use for stutter, slow menus, loading delays, profiling and optimization requests; ordinary functional fixes and local cleanup without a performance claim use proportionate correctness checks instead.
---

# Evidence-driven performance investigation

Deliver a useful decision about a named player-visible problem: a verified improvement, a justified deferral, or a precise evidence gap. A stopped investigation is a valid result; do not manufacture optimizations to keep working.

Follow [project rules](../../../AGENTS.md), the relevant sections of [development guidance](../../../docs/DEVELOPMENT.md), and the [native runner guide](../../../tests/native_queue/README.md) when running the game. This skill does not activate the infrastructure-maintainer role. Audit/research requests stop at findings; implement changes only within the user's authorized task.

## 0. Choose a proportionate validation path

Separate the intended deliverables: clearer code or less unnecessary work, a player-visible performance improvement, or both. Decide what evidence would change implementation or acceptance before building a benchmark. A request to investigate performance does not make every source cleanup require an end-to-end speedup; an explicit request for measured improvement still needs an honest measurement result.

- For local cleanup, such as moving a proven pure read under its existing consumer condition, review semantic equivalence, readability and complexity, then run focused behavior/call-avoidance checks. It may be worth retaining for code quality with no established gameplay speedup. Noisy or inconclusive timing alone does not invalidate that independent rationale, and fewer calls alone do not prove faster gameplay.
- Judge risk by behavior, not diff size or the word "cleanup". New caches/state, lifetimes/invalidation, algorithms, batching, scheduling, effects or authority need their corresponding evidence. Native integration remains necessary when the changed behavior actually depends on it, including callback ordering or engine-owned effects.
- Start with existing evidence and the cheapest check that can answer the question. Escalate from source/call-frequency analysis to a focused diagnostic and then representative gameplay comparison when the likely impact, uncertainty or behavioral risk justifies that cost. Unknown contribution is a reason to locate it first, not automatically launch a full comparison series or prepare every SP/Host topology.
- Retaining performance-specific complexity needs a credible useful benefit. A sound simpler implementation can be retained on correctness/maintainability grounds without such a claim; record the two judgments separately. An invented millisecond/percentage hurdle must not replace that assessment.
- A synthetic extreme cohort may expose a mechanism or an upper bound. Verify the affected physical branch and state, and explain its relevance to ordinary gameplay; a large item count does not itself justify expensive repetition or prove useful player impact.

Use the remaining investigation workflow and experiment records for actual measurement work. If only cleanup and its correctness checks are needed, use the normal project workflow and briefly state the validation rationale; do not create a performance campaign or require a case template merely to retain that cleanup. If a task contains both, preserve an inconclusive performance result while recording any independently justified cleanup.

## 1. Recover the case before measuring

- Search project-scoped cumulative memory for the symptom, scenario, suspected component and failed experiments. Read useful full notes; treat candidates as leads and recheck version-sensitive claims.
- Inspect relevant existing reports, TODO and active worktrees/chats through available read-only tools. Search targeted `.codex/investigations/performance/` directories and known older evidence locations, rather than auditing every worktree. Existing evidence can come from another branch; record its exact source state.
- Reuse one stable scenario ID across chats. Find its owner, canonical case record, tested hypotheses and unresolved questions. One chat owns implementation and measurement for a case; other agents may analyze its saved evidence. If another chat owns active experiments, finish useful read-only analysis and report the ownership instead of starting a competing run. Do not take over or reset ownership merely because an owner is quiet.
- Continue an existing case rather than renaming it to repeat discarded work. A successor in a new worktree references the previous case, inherits its evidence and conclusions, and records the handoff. Never edit another chat's checkout. Resolve unclear ownership before competing measurements; recover enough prior evidence to identify a useful next question.

Use [the case and experiment template](references/experiment-record.md) before the first experiment. Store working records in `.codex/investigations/performance/<scenario-id>/` in the owning worktree; retain raw artifacts in an ignored or external output directory. Record their locations in the case and report. Neither TODO nor chat prose alone is the experiment history.

## 2. Define the question and why the next step is useful

Record before running:

- Player action and observable symptom; relevant supported platform and SP or Host mode.
- Reproduction command/procedure, route or item population, world/save snapshot, game/JVM/mod versions and order, baseline source identity including relevant uncommitted changes, settings and measurement window.
- Primary outcome, its practical relevance, protected behavior/quality and regression tolerance. Use numeric objectives when grounded in the user problem and baseline; label assumptions. Do not invent a timing cutoff to decide code quality or silently impose a universal percentage, FPS target or percentile.
- Cold/first-use versus warmed/repeated behavior, fixed exclusions, repetition plan, and evidence needed to distinguish the leading explanations.
- Owner, unresolved question, why this measurement is worth its preparation/run cost, the cheapest sufficient validation and conditions for continuing, stopping or revisiting a conclusion. Read-only recovery comes first and may avoid all runs.

Continue autonomously within the authorized task while the next step can resolve a named uncertainty, test a supported explanation or verify a useful retained change. Before another run or edit, explain what its possible results would change about the next decision. Choose enough comparable observations to answer that question; avoid repeats that merely seek a more favorable result.

Do not impose default quotas on hypotheses, implementation rounds, launches, elapsed investigation time or collector repairs, and do not request permission to renew them. Historical quota exhaustion is not a blocker: recover the prior findings and decide whether the current question merits further work. Respect explicit task limits supplied by the user; ordinary tool timeouts, resource admission and safety guards remain in force.

## 3. Validate the measurement path

Pilot the actual slow journey with the existing tools. Check that the intended sources/mods ran, the symptom occurred in the chosen window, and the collector measures the claimed event. A fixture PASS proves only its assertions, not representative performance.

- Stutter: use a frame-time timeline and counts/durations of long frames over a defined route/window; averages may hide the complaint. Report tails only with adequate observations, and keep rare stalls rather than trimming them as outliers.
- Menu/action delay: measure the user-visible interval, including deferred work, against a fixed selection/content size. A faster helper alone does not prove a faster menu.
- Startup/first use: include the relevant loading or initialization phase. Warm steady state cannot validate a cold-start fix. Separate cache warming from world generation or other unproven mechanisms.
- Repeated-use degradation: use a bounded repetition count with memory/latency observations and a defined settled-state signal.

Repeat a comparable baseline enough to expose variation under the planned workload. A few deterministic repeats are a pilot, not automatic statistical proof. Frames within one run are correlated; many frames do not substitute for independent repeated runs. Run additional samples only when they can resolve a named uncertainty that matters to the decision.

Keep source bytes, save identity, mods, route/speed, camera, resolution/framebuffer, frame cap/VSync, cache phase and instrumentation comparable except for the intended factor. Record unavoidable differences. Alternate baseline and candidate order when feasible; restore equivalent state for each run. Collision damage, changed content or differing route exposure can invalidate a comparison. Keep invalid runs with reasons; exclusions must not be chosen to favor a candidate.

Run performance comparisons serially on shared hardware, using the runner's exclusive admission. Resource admission alone does not establish comparability. Coordinate agent-owned builds, tests and captures; never stop unrelated user processes. Follow the existing macOS placement/focus policy without inventing a bypass. Use isolated settings/saves; installation into the user's game is a separate request. Test macOS as supported here; do not turn this skill into a Windows verification obligation or generalize results across platforms.

If the symptom is absent or collection is broken, correct an identified reproduction/collector defect when there is a concrete reason to expect a valid next observation. Reassess after the repair: repeated setup changes or retries without diagnostic progress are a reason to stop as not reproduced or inconclusive. A new synthetic load may help diagnosis but needs validation against the complaint before it can be an acceptance scenario.

## 4. Locate the limiting work before selecting a fix

Examine the slow event's timeline and relevant threads, then drill into the layer where its latency begins. Distinguish actual CPU work, runnable contention, locks/waits, disk/network I/O, GC/allocation and GPU/render work. Check resource utilization, saturation and errors when relevant; an unavailable metric stays unknown. Low aggregate CPU, a large flame-graph box or time inside a wait function alone does not identify the limiter.

Use profiling during diagnosis to verify what the workload actually exercises. Heavy traces can perturb timings: confirm acceptance with minimal, comparable instrumentation. Start with existing evidence; instrument only where the next observation distinguishes competing explanations. If history identifies a previously good version, consider bounded bisection before speculative tuning.

Rank candidates by contribution to the problematic event, confidence, expected end-to-end benefit, implementation cost and regression risk. Estimate the upper bound before editing: removing 0.2 ms from a sequential 40 ms stall saves at most 0.5%. Do not add overlapping CPU/GPU or nested inclusive times. Use the critical path of the slow event, not average cost across unrelated frames.

Runtime, native engine and third-party code are not automatically irreducible. Check whether callers can reduce repeated work or allocation safely. Conversely, a suspected GPU limit does not justify Lua micro-optimization without an explained connection. Resolution changes can also change visible world workload; they do not alone prove GPU causality or predict a hardware-upgrade gain.

Defer a candidate when its best plausible benefit is below the declared useful gain, its contribution is outside the delayed path, or its cost/risk exceeds the expected payoff. State the checked scope; do not claim that the whole game cannot be improved.

## 5. Run one falsifiable experiment at a time

Before each experiment, save: hypothesis, existing evidence, predicted distinguishing observation, one changed factor, baseline/control, planned observations and why they are sufficient, validity conditions and acceptance/rejection criteria. A diagnostic exclusion of a component is useful progress even without a code improvement. If no possible result would change the next decision, skip the experiment.

Implement the smallest reversible change that tests a supported cause, preserving requested behavior and quality. Reduced resolution, disabled content, shortened actions or delayed work are tradeoffs or diagnostic controls, not equivalent gameplay improvements. Verify that caching, batching or deferral does not lose freshness, effects or correctness. Keep owner implementation serial; independent review can use saved artifacts without competing for measured resources.

Compare end-to-end outcomes and affected correctness. Report absolute values, deltas, variation, sample counts and limitations; neither one lucky run nor statistical significance alone establishes a useful gain. An effect unresolved by the measurement is **inconclusive**, not proven zero. Where feasible, state the effect range still compatible with the data instead of inventing confidence.

Retain changes justified by performance gains only when those gains are repeatable and practically meaningful, with no disallowed regression. Revert unsuccessful performance-specific complexity; retain a separately justified cleanup only after its correctness/code-quality review, stating that its speedup is unestablished. Do not convert a failed speed claim into a successful one by relabeling the change. After a retained gain, recheck the changed limiter and verify the final combined state; independent wins do not automatically add up. If final verification is missing, report the candidate as unverified. Use independent evidence review for a material or ambiguous conclusion when available; review absence narrows confidence and does not create an endless rerun gate.

## 6. Stop, retain evidence, and define reopening

Stop when the target is met and the final state is verified, no supported next hypothesis has a plausible useful payoff, experiments keep returning the same unresolved result without improving the evidence, or progress needs unavailable evidence/capability or a user-owned tradeoff. A failed implementation or invalid launch alone is not a stopping rule; continue when the next step addresses its cause and can change the decision. Diagnostic narrowing is progress, but preparation and collector repair must remain tied to the player problem rather than becoming a separate open-ended infrastructure task.

Report the performance outcome: **target met**, **improved but target unmet**, **no retained useful improvement**, **not reproduced**, or **inconclusive**. Separately state any retained cleanup and its correctness/maintainability rationale; it does not turn an inconclusive performance outcome into a measured gain. Include before/after when meaningful, retained/discarded hypotheses, conditions actually tested, evidence paths, why further work is or is not worthwhile, and a concrete condition for revisiting the result. A decision to stop does not prove impossibility.

Before ending, save every attempted hypothesis and verdict using the record template. Keep TODO limited to practical unfinished actions; it must not accumulate completed attempts. Persist durable findings, failed approaches with their applicability limits, stop decisions and reopening conditions through cumulative-agent-memory with evidence anchors. Do not dump raw logs or routine run bookkeeping into memory. Keep experiment details in the canonical case; a stopped case's durable summary states the checked scope, evidence gap and reason for stopping. Reuse semantic experiment identity when citing the same evidence; a second chat is not an independent observation. Use available chat/worktree discovery to locate active records, with memory supplying durable conclusions after a worktree is gone.

Revisit a rejected or inconclusive hypothesis when new contradictory evidence, a relevant source/runtime/workload change, a materially better measurement method or an explicitly changed user goal gives the experiment a different decision value. State what changed and which prior conclusion it could affect; a new goal does not make old evidence false. A changed unrelated file, missing raw artifact, new chat, new agent or passage of time alone does not justify repeating the same work. If a case stopped only because of a former numeric quota, retain its findings and assess the useful next question without asking for a budget renewal. If the record is missing or ambiguous, recover its summary first and report the evidence gap rather than automatically repeating it. Preserve decisive evidence during cleanup; remove only owned scratch/processes whose loss does not undermine the result.

## Basis and calibration

See [sources and adaptation notes](references/sources.md) when explaining or revising this procedure. Continuation and stopping depend on expected decision value, observed progress and the user-visible goal. There are no default numeric investigation quotas.
