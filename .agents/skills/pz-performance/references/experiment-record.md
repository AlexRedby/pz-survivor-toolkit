# Case and experiment record

Create one canonical `case.md` under `.codex/investigations/performance/<scenario-id>/` in the owner worktree. Reuse an existing case. Older evidence may live elsewhere: reference it without migrating or rerunning it merely to fit this layout. Fill only applicable fields; keep values precise enough for another chat to resume without replaying discovery. This is working evidence, not a new document under `docs/`.

## Case template

```markdown
# <stable-scenario-id>

## Ownership and continuity
- Owner chat and branch/worktree:
- Status: active | stopped | complete
- Canonical record location:
- Predecessor/handoff and other known evidence locations:
- Existing memory findings consulted, with applicability/version checks:

## Player problem and contract
- Action, symptom and why it matters:
- Goal and origin of thresholds (user/project/inferred):
- Primary outcome, unit and practical minimum gain:
- Protected behavior/quality and regression tolerances:
- Scope: game/JVM versions, platform, SP or Host:
- Baseline source revision and relevant uncommitted changes:
- Exact mod sources/order, save/world snapshot and input identity:
- Reproduction command or procedure:
- Route/speed or selection/content/population:
- Camera, logical/framebuffer size, quality, cap/VSync:
- Cold/first-use/warm phase and reset procedure:
- Collector, measured boundaries/window and overhead limits:
- Fixed exclusions, invalidation rules and repetition/sample plan:

## Budget (shared by continuations)
- Start and deadline:
- Experiment time consumed/remaining, including preparation, startup and waits:
- Limits: diagnostic hypotheses / implementation rounds / native executions:
- Consumed and remaining counters, including failed/invalid runs:
- Current planned finite series and its maximum cost:
- Stop conditions and reopening conditions:

## Baseline and bottleneck evidence
- Symptom reproduced? Artifact and exact interval:
- Baseline observations, variation and sample counts:
- Where time is spent; measured facts versus unknowns:
- Ranked hypotheses and distinguishing predictions:
- Best plausible end-to-end gain, with assumptions:

## Experiment index
| ID | Hypothesis | Kind | Evidence | Verdict | Reopen only if |
| --- | --- | --- | --- | --- | --- |

## Current decision / handoff
- Outcome and scope of claim:
- Retained changes and final-state verification:
- Unresolved evidence gaps and practical next action:
- Stop reason; what would justify reopening:
- Durable memory findings stored and evidence identities:
```

## Per-experiment template

Save one `experiment-<id>.md` before execution and fill its observed result immediately afterward, including invalid or aborted attempts. Reference immutable raw artifacts rather than replacing previous measurements. Interrupted work keeps a pending/aborted verdict and still consumes the attempts already made.

```markdown
# <scenario-id> / <experiment-id>

- Kind: reproduction/collector | diagnostic | implementation | confirmation
- Question and existing evidence:
- Falsifiable hypothesis and predicted observation:
- Changed factor and protected invariants:
- Baseline/control and candidate source/input identities:
- Procedure/commands, finite repeats, duration and counter cost:
- Validity and predeclared acceptance/rejection criteria:

| Run | Source/control | Phase | Raw evidence | Primary value/unit | Validity/reason |
| --- | --- | --- | --- | --- | --- |

- Observations: absolute/relative difference, variation, sample count:
- Could instrumentation, drift, state or sample size explain the result?
- Correctness/quality and adjacent-phase checks:
- Verdict: supported | refuted | no useful effect detected | inconclusive | invalid | aborted
- Interpretation and limits; useful information gained:
- Change disposition: retained | reverted | diagnostic only | unverified candidate
- Exact condition for retry/reopening:
- Updated case counters and next decision:
```

## Durable cross-chat handoff

Use the cumulative-memory skill's current API, with project scope and English explanatory text. Store a granular conclusion likely to prevent repeat work, its exact scenario/source applicability, evidence identity and reopening condition. Anchor code-derived claims to the relevant source files. A failed attempt can be durable evidence; it must not become a universal claim that the technique never works. Keep active ownership, run-by-run transcripts and transient counters in the canonical case and use available chat/worktree discovery for coordination.

Example of the needed distinction: a cold-route versus repeated-route comparison can support a warming effect under its tested conditions; it does not by itself identify which cache or generation mechanism caused it. A missing difference in a noisy experiment is inconclusive unless the data excludes the declared useful gain.
