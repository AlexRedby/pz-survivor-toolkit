# TODO

## Network Fix follow-up

- [ ] Prioritize vehicle desync reproduction in ordinary Host mode: driver moves while host sees the car frozen for about a minute, host/passenger enters and exits at a stale position, and driver sometimes jumps between distant positions. Reported on the then-latest game without Jaysync/these sync or vehicle mods; exact episode build still unconfirmed.
- [ ] Before adding another fix, distinguish driver physics not sent, server queue drops, consistency/anticheat rejection, authority mismatch, relevance filtering and remote interpolation. Inspect Host server logs for the native physics-drop warning; then add opt-in bounded vehicle tracing only for gaps existing logs cannot explain.
- [ ] Validate the trace/fix with driver, host passenger and observer, including repeated enter/exit, controlled latency, jitter and packet loss. Current recovery regression exercises native interpolation state only.
- [ ] Check long-running sessions, the user's full mod set and mixed patched/unpatched clients before treating this as a stable release. All participating clients should use the patch during evaluation.
- [ ] Reproduce the reported two-player combat/grapple jerks and compare the original engine with the patch; current MP verification covers real zombie snapshots and repeated authority handoff. Lower priority than vehicle desync.
