# Repeated square-property aggregation: rejected

This headless research regression preserves a rejected invocation-scoped reuse
candidate. It is not part of the shipped mod, does not install anything, and
must not be used as evidence that the candidate is safe in SP or menu Host.

The target is repeated `RecalcProperties` inside one `RecalcAllWithNeighbours`.
Loaded squares remain dirty after rebuilding, so neighbor calculations can
repeat object scans and property merging. The candidate retains an identity,
eight aggregation booleans and two pre-correction flag words in bounded scratch;
it reuses aggregation while executing the original prefix and suffix. Native
world objects gain no fields. Test-only methods are added to a temporary overlay;
this is not an after-load runtime transformer.

## Run

Supply external B42.21 game/JDK inputs, the prepared selected-official overlay,
its profile manifest, and a new disposable output directory outside the game:

```sh
python3 tests/chunk_integration/recalc_aggregation/run.py \
  --game "$PZ_GAME" --jdk "$JAVA_HOME" \
  --official-overlay "$PZ_OFFICIAL_OVERLAY" \
  --manifest tests/optimizer_trial/candidate-manifest.json \
  --output "$PZ_RECALC_RESULTS"
```

The command requires reviewed native/official class hashes and disabled upstream
handoff fast/memo/parallel flags. It snapshots sources, compiles against native
classes, runs native and official variants from isolated working/home paths,
and records receipts and logs. No timing or game window is started. The final
`AGGREGATION_REJECTION_REGRESSION_PASS` means the rejection was reproduced.

## What the checks establish

The counted fixture compares complete native property operations and native
neighbor traversal through actual `cellGetSquare`, cell/chunk maps and metadata.
It covers borders/levels, sparse/dense objects, stairs/slopes, dirty flags,
lighting/physics/collision/puddle/water effects, native caches and pointer
identities. Unknown getters, exceptions, nesting, overflow and edits between
scopes retain baseline behavior. Prefix/suffix call counts match. Separate
instruction comparison confirms that removing diagnostic counters does not
otherwise change the two affected methods. These synchronous checks passed
1,728 native / 1,729 official direct cases and 144 full neighbor cases each.
They do not prove worker coherence or real-world performance.

A plain finalized-map candidate initially skipped native conditional `unset`
calls. Restoring pre-suffix flag words repaired that synchronous difference.
The repaired version still fails when its shared source changes:
`SharedSourceMutationCheck` uses the real native `AddProperties` operation
between two reads. Baseline sees `collideN=true, Surface=20`; reuse retains
`false, 10`. The harness supplies that interleaving; it does not launch a worker
or execute the full window loader.

`WindowAliasCheck` separately extracts eight hash-guarded native window
constructor instructions. A controlled thread executes the original two flag
unsets on the same native sprite/property alias; a fresh aggregate observes
`cutN=false` while the cached aggregate retains `true`. The fixture later
restores the directional flag through native APIs. This is a native-prefix/API
counterexample, not a live race or complete-constructor test.

The audited native writer path is WorldStreamer -> chunk LoadBrandNew ->
CellLoader.LoadCellBinaryChunk -> IsoCell.PlaceLot -> global sprite lookup ->
DoTileObjectCreation -> IsoWindow constructor. The constructor temporarily clears
both cut flags before restoring the directional flag. Existing loaded objects
can reference that global sprite; chunk publication and the handoff lock do not
serialize these sprite writes. Saved-window loading also mutates global sprite
variant properties. Neither a game-thread identity check nor a callback-free
local method makes these inputs immutable. Menu Host's separate server heap
does not remove its client's loader.

Do not enable this reuse or the broader handoff optimization on the strength of
the synchronous fixture. Shared-input validation, versioning or synchronization
would be a different design requiring complete writer coverage and measured
cost. No performance comparison was started after the counterexample. The
unused timing draft and earlier rejected controls remain private research
artifacts, not delivered functionality.
