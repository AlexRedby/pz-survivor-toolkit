# Persistent cutaway dependency cache: not admissible

The current narrow generation proposal is not admissible for the supported mutable
native/official API, including its public aliases. No cheap complete contract has
been established for this persistent-mask cache.
Hooking `setSquare`, `ReCalculateVisionBlocked`, flag preparation and reset is
insufficient. No runtime implementation, profile change, timing or game launch is
provided by this experiment. Keep the native operation as the complete fallback.

```sh
python3 tests/chunk_integration/cutaway_dependency/run.py \
  --game "$GAME_JAVA" --jdk "$JDK_HOME" \
  --official-overlay "$OFFICIAL_OVERLAY" --output "$OUTPUT"
```

This focused check pins the complete native JAR and original official class ZIP,
uses the shared project JVM target 25, and writes only to a new external output.
It scans all 23,829 native classes and 1,099 official classes. The receipt merges
the official replacement classes over native classes, lists actual `PUTFIELD`
sites and potential array consumers with exact method descriptors/class hashes,
and explicitly records that alias closure and selected-modpack writer closure
are not proved. Array-operation counts are method-local candidates, not dataflow
proof that every counted store/fill targets a square row. The scan also follows
native `getSquaresForLevel` calls, whose returned row is a mutable alias.

The command separately compiles the existing `DirtyDependencyChecks` fixture and
new `NativeMutationChecks` against **unmodified native classes**. Ten positive
counterexamples pass. Actual native `setX`, `setY` and `setZ` change the native
occluder answer while the target level stays clean. Public flag-row store, fill,
arraycopy and row replacement do the same. Mutating a row returned by native
`getSquaresForLevel` changes the native upper or below-square predicate without
calling `setSquare`. A public `visionMatrix` field write also bypasses the named
vision producer. These are API-level counterexamples, not claims that the sealed
modpack performs those mutations or that visual corruption was observed.

## Actual bytecode writer boundary

The native direct `visionMatrix` writers are `IsoGridSquare`'s constructor, both
`getNew` overloads, and `ReCalculateVisionBlocked`. The official replacement adds
`pzoptHrRestore`; its recalculation has two write sites, including the memoized
early path. Hooking only the ordinary recalculation return misses that restore.

Actual native `setX`, `setY` and `setZ` are coordinate writers outside those hooks.
Constructors and pooled `getNew` also write x/y/z. Chunk membership changes in
`IsoChunk.setSquare`, disk-load assignment, removal, and `IsoGridSquare.discard`.
`IsoChunk` wx/wy, min/max levels and square-array replacements also belong to the
state contract; using wx/wy as a persistent identity cannot distinguish reuse.

The native flag-row writes are the two `BASTORE` sites in
`FBORenderCell.prepareChunkForUpdating` and `Arrays.fill` in
`ChunkLevelData.removeFromWorld` (plus initial allocation). Official zoom-granted
preparation contains an `arraycopy` restoration to flag rows in its dev path.
Other reported flag consumers such as BloodWet copies and PuddleCache lookup
must not be mislabeled as writes without checking the copy direction.

Native membership is not routed exclusively through `setSquare`:
`IsoChunkLevel.clear` fills its shared square row; `IsoChunk.unlinkSquares`,
`doReuseGridsquares`, and `WorldReuserThread.reuseGridSquares` clear entries;
`setMinMaxLevel` changes rows and extents. Reuse paths ordinarily reach reset, but
the complete contract must invalidate before pooled state is reused, retain the
old owner until that invalidation, and handle partial/exceptional completion.
The inventory includes dedicated-server paths as evidence of writers; it does
not add dedicated-server support to the project.

## Minimum complete remedy and cost boundary

A producer-generation design would need all of the following, independently of
native render dirt and of JNI lighting completion:

- Identity-keyed chunk lifecycle state, separate player visibility generations,
  and shape/vision generations. With after-load retransformation, native fields
  cannot simply be added: this requires bounded sidecar storage, weak identity
  ownership or explicit eviction, thread-safe publication, and reset cleanup.
- Every actual writer, including setters, direct field writes, row replacement,
  row stores, fills and copies through escaped aliases, must update that state.
  Membership changes invalidate both z and z+1 when the latter exists; downward
  vision changes invalidate the square's own z. Flags invalidate the affected
  player and level. Coordinate/chunk reassignment must invalidate the old and new
  owners before the old association is lost. Extent/row replacement invalidates
  all affected levels. At the chunk minimum, the below lookup is out of range until extents change;
  respect the supported -32 lower bound and never wrap z=31 into -32.
- Dirty-bit clearing must not clear generations. New chunks at reused wx/wy and
  pooled chunks need distinct lifecycle tokens; counter rollover must invalidate
  rather than make old generations equal. A canonical square/coordinate check at
  cache construction alone is insufficient: a later native setter can invalidate
  that correspondence while leaving all four named hooks silent.

Per-chunk generations are feasible **only after proving and maintaining that full
writer/alias barrier**. The four named native/official hooks do not provide it.
The native APIs expose primitive arrays and mutable public fields. After-load
instrumentation cannot turn those arrays into immutable/wrapped containers or
remove setters without changing the native API. Observing arbitrary existing
aliases needs broad writer/call-site instrumentation, array-identity ownership,
copy/fill handling, and class-loading closure; instrumenting a few producer
methods cannot intercept stores through a previously returned row. This is a
substantially broader mechanism, not an admissible implementation of the current
small optimization. Its hook/sidecar/retention costs have not been measured.

A single global epoch is cheap to update, but does not rescue useful reuse: dirty
flag preparation before an occlusion rebuild would invalidate every cached chunk
on those frames. The existing all-dirty cache path already performs an extra
scan and regresses in its separate CPU experiment. A global epoch therefore
cannot be accepted as a useful fallback to the missing per-chunk barrier.

The bounded complete alternative is fresh validation of every live dependency
before reuse, preserving native clipping, access order, virtual calls and
exceptions. Public aliases defeat an identity-only or generation-only guard:
the row can retain the same identity while its elements change. Complete live
validation must revisit the same square/flag/vision/below-cell inputs that form
the native predicate; running the exact native operation already provides this
contract with no persistent-cache bookkeeping. No cheaper live guard has been
established, and no validation-cost timing is claimed.

No cheaply detectable restricted subset has been shown to cover the captured
operation. Empty rows still require checking for aliased insertion; bottom-level
rows still have mutable flags, coordinates and membership; stable row identities
and clean dirty bits are contradicted by the focused checks. The selected-source
text audit can narrow known callers but cannot establish immutable public aliases
or exclude alternate versions/reflection/native writers. Thus this persistent
cache approach is **not admissible under the current contract**, rather than a
candidate waiting only for gameplay testing. Reconsider it only with a closed,
qualified writer barrier and its full cost, or a measured live-validation method
that demonstrably beats the existing native operation.
