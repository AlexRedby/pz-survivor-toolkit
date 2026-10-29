# Pinned cutaway cache experiment

This is a test-only repair of the pinned optimizer's `cutawayFast` replay. Keep the runtime profile's `cutawayFast=false`: this experiment has not established the complete cache lifetime or passed native single-player/menu-Host qualification.

The runner extracts the complete `FBORenderCell.calculateOccludingSquares` caller and `pzoptExactOccluderMask` helper from the pinned archive. `CacheGenerator.java` substitutes fixture infrastructure; `RepairedCache.java` adds lazy per-player masks, refreshes the native clipped change-detection mask during replay, and invokes the same overlapping-level invalidation when it changes. The dirty/missing-cache path still calls the real native `ChunkLevelData.calculateOccludingSquares`, followed by the complete extracted exact-mask helper.

## Reproduce

Provide the supported game Java directory, a JDK 25, and the pinned optimizer archive. Output must be new and outside the installed game. Class hashes reject changed native/pinned inputs. No game window opens and no installed mod or save is changed.

```sh
python3 tests/chunk_integration/cutaway_cache/run.py \
  --game "$GAME_JAVA" \
  --jdk "$JDK_HOME" \
  --official-overlay "$OFFICIAL_OVERLAY" \
  --output "$OUTPUT"
```

Add `--measure` for the bounded three-fork CPU diagnostic. It acquires the project's exclusive resource admission; do not run another CPU measurement concurrently. Each output contains compile/extraction/check logs and `result.json`; measurement adds admission, compilation, GC/safepoint and per-fork timing logs.

The fixture reuses `../cutaway_operation` rather than maintaining another complete native-operation extraction. Its isolated emitted IsoChunk has one added holder field; native method bodies remain unchanged. Other substitutions are public cell/player holders, fixed zoom=1/enabled=true, a configurable fast flag, cutaway-data lookup and an invalidation recorder. The callback recorder establishes which native invalidation would be requested; it does not render lower textures.

## Exact correctness scope

The final check compares **9,408 ordered snapshots** against native: output grid, all players' legacy masks and ordered invalidation callbacks. It covers levels -32..31; empty, bit 0/31/32/63, full and sparse masks; clipping and restoration; player 0/1 switching; flag, vision and below-square changes surrounded by actual native `invalidateLevel`/`clearDirty` calls; and validity reset/repopulation for both players. The native legacy mask retains its int-shift wrap and sign extension. Original pinned fast replay differs in 2,812 snapshots, establishing test sensitivity; repaired replay matches all 9,408.

The fixtures use well-formed square-array positions matching the owning chunk and level. Replay reconstructs coordinates from chunk and bit instead of reading live square x/y/z; the unclipped exact-mask rebuild also reads cells outside the native clipped scan. These 9,408 matches do not establish equivalence for arbitrary mutable or malformed square coordinates or array contents. Canonical square ownership/position and their lifetime are eligibility prerequisites; the separate operation fixture exercises malformed/mutable cases that this cache fixture does not.

Two original defects are distinguished:

- Native `shouldRenderBuildingSquare` produces different visibility for the same square from a basement camera and a camera on its floor. Sharing the exact mask across two local players replays the other player's occluder. This is a split-screen case; ordinary single-player and a menu-Host client with only local player 0 do not acquire remote players' flags this way.
- A single-player camera clip change can leave a still-visible chunk clean. The original replay writes the correct clipped grid but leaves its legacy mask unchanged and omits native overlapping-level invalidation. This proves a side-effect mismatch, not a visible-hole defect.

Validity reset models the cache assignment owned by `resetForStore` and the repair's all-player clear. It does not execute a full native unload/store cycle. Every changed input in the sequence has an explicit native invalidation; that does not prove every gameplay producer supplies one. The remaining producer-dependency gate includes lower-square changes across a two-level render-group boundary: the upper cache depends on the square below, and a dirty lower group alone does not establish that the upper cache is dirty. An API-level gap must be distinguished from a reachable gameplay action.

Lazy storage has 512 bytes of mask payload per populated local-player slot, 32 bytes of validity payload per chunk, a four-reference array and array headers/alignment. One local player keeps the original 512-byte mask payload; three additional populated slots add 1,536 payload bytes. Exact heap/RSS cost was not measured. Normal chunk reuse must clear all four validity entries; allocated mask arrays may remain for reuse.

## Bounded CPU result

The final diagnostic used 32 canonical one-level chunks per complete world-grid rebuild, including the common grid clear and checksum consumption. Sparse levels have 8 squares, dense 64, empty 0. Mixed worlds keep 8/32 levels dirty. Dirty state remains set throughout the measured window; no mode adds per-call dirty/clear allocations. Modes share the callback sink. Original fast is measured only with player 0 and stable clipping, where these demonstrated semantic defects are not activated.

Median across three fork medians, **CPU nanoseconds per complete 32-chunk call**:

| World | Native operation fallback in pinned caller | Original pinned fast | Repaired fast |
| --- | ---: | ---: | ---: |
| Empty, clean | 1,439 | 279 | 571 |
| Empty, 25% dirty | 1,428 | 724 | 1,005 |
| Empty, all dirty | 1,452 | 2,095 | 2,307 |
| Sparse, clean | 2,184 | 626 | 989 |
| Sparse, 25% dirty | 2,188 | 1,247 | 1,588 |
| Sparse, all dirty | 2,275 | 3,438 | 3,764 |
| Dense, clean | 6,975 | 2,708 | 3,337 |
| Dense, 25% dirty | 7,620 | 4,927 | 5,928 |
| Dense, all dirty | 7,574 | 10,141 | 10,448 |

Full caller methods reached non-OSR C2 before the first window in each fork; measured windows have no relevant JIT transition, GC or safepoint overlap. Checksums match. Repaired fork-median spread is about 2-8%, with consistent direction: clean calls use about 51-61% less CPU than native, mixed calls 21-34% less, and all-dirty calls **37-72% more**. The cache miss still performs the extra exact-mask scan. Even the dense clean result saves only about 3.6 microseconds per synthetic 32-chunk call here.

The real drive's cache-hit/dirty distribution is unknown. These headless costs do not establish FPS, frame-time improvement, runtime admission, or a reason for another user drive. An earlier capture with an unconditional fixture assertion-message allocation and measured GC was rejected before this result.

The receipt pins measured Java source and generated class bytes. The explicit C2 gate was added to the validation runner after the final capture and checked against those same fresh logs, without changing measured Java sources or classes or rerunning timing. Its post-validation hash is recorded separately from the original measured runner hash.

## Native dirty-dependency producer check

The independent focused check needs only native game classes and JDK 25:

```sh
python3 tests/chunk_integration/cutaway_cache/run_dirty_dependency.py \
  --game "$GAME_JAVA" --jdk "$JDK_HOME" --output "$OUTPUT"
```

It pins native class hashes and runs unmodified native APIs with normal
`IsoChunk.JobType.None`. Across the lower-level 1 / upper-level 2 render-group
boundary, native `setSquare` removal plus lower-level invalidation changes the
native upper occluder height from -32 to 2 while lower dirty is true and upper dirty
is false. A native `ReCalculateVisionBlocked` producer after a below-square
`blocksight` property change demonstrates the same missing upper dependency.
The test seeds valid flags and a native clean state; it does not inject vision
matrix answers, transform native classes, create GPU textures or run a game.

This proves the target-level dirty bit alone is insufficient as a general native
API freshness contract. It is **not** a visually observed bug or a complete
reachable gameplay-action reproduction. Reviewed object add/remove and floor
paths also request global lighting, cutaway and topology work; whether their
completion always dirties the upper render group before occluder calculation,
including JNI lighting ordering, remains unresolved. `occlusionRetain=true`
preserves dirt already raised and does not prove this dependency. Keep that
prerequisite open before any runtime adoption; this focused check changes none of
the measured cache Java sources or timing semantics.

## Deferred construction: repeated dirty calls

The separate `deferred.py` experiment retains the earlier measured sources and
receipts. It clears a player's slot before a dirty native call and skips the
extra exact-mask scan. A later clean miss executes native, preserves its
invalidation, and publishes a mask only after the optional build succeeds.
Native exceptions preserve native partial output; a failure in the extra
unclipped scan leaves the slot invalid without losing native invalidation.

```sh
python3 tests/chunk_integration/cutaway_cache/deferred.py \
  --game "$GAME_JAVA" --jdk "$JDK_HOME" \
  --official-overlay "$OFFICIAL_OVERLAY" --output "$OUTPUT" --measure
```

The focused checks pass 17,028 ordered comparisons, including dirty-to-clean,
repeated dirty, clipping/player/reset sequences, native miss exceptions and
optional-helper failure. A stale-validity negative control fails as intended.
A fully dirty cold one-level call allocates no cache. Changed-input scenarios
still explicitly dirty the required level; they do not establish producer closure.

Three exclusive forks retained 1,134 windows, with all three complete methods at
non-OSR C2 before timing, equal checksums and no relevant JIT/GC/safepoint overlap.
Same-capture medians below are CPU nanoseconds per complete 32-chunk operation:

| World | Native fallback | Earlier repaired | Deferred |
| --- | ---: | ---: | ---: |
| Dense, all dirty | 7,126 | 10,985 | 7,359 |
| Sparse, all dirty | 2,280 | 3,950 | 2,810 |
| Empty, all dirty | 1,438 | 2,402 | 1,643 |
| Dense, clean validity miss | 7,184 | 10,787 | 10,480 |
| Dense, four-call cycle | 7,446 | 7,308 | 7,498 |
| Dense, eight-call cycle | 7,370 | 6,610 | 6,758 |

Each cycle has one dirty call, one first-clean miss, then clean hits. The redundant
all-dirty scan is removed; residual overhead is about 3% dense, 23% sparse and 14%
empty in these medians. First-clean misses still pay both scans. Dense four-call
cycles are approximately native cost. Clean results vary between forks (dense
spread about 22%), so this is not a precise route-gain estimate.

Every timed mode has symmetric preallocated capacity. A clean validity miss is
not a first-allocation/GC measurement. The fixture's added native holder field
excludes production sidecar lookup, synchronization, retention and cleanup costs.
The measured candidate and benchmark sources remained unchanged when the final
check was strengthened to require an actual native callback on helper failure;
the receipt identifies that post-measurement correctness check separately.

The [dependency audit](../cutaway_dependency/README.md) rejects the current narrow
producer-generation approach: live public aliases and additional native writers
bypass its proposed hooks. Deferred construction fixes redundant work only; it
does not make that persistent cache safe. Neither variant is admitted to runtime.
