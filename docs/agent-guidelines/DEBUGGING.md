# Debug and release confidence workflow

This workflow complements [TESTING.md](TESTING.md). A successful build alone is
not a release gate, and skipped tests are not passing coverage.

## Execution order

1. Record the commit, working-tree changes, OS/Xcode versions, test commands,
   result bundles, and whether external integration flags are enabled.
2. Run the complete default XCTest suite with external paid/live integrations
   left opt-in. Classify every failure and skip; distinguish product defects,
   test isolation defects, missing dependencies, and manual diagnostics.
3. Reproduce each failure in isolation before changing code. Add a regression
   test at the shared owner of the behavior, then make the smallest complete fix.
4. Audit the risk matrix below, including error, cancellation, and stale-result
   paths. Do not infer runtime correctness from comments or source-string tests.
5. Run rendering diagnostics and headless performance tests serially. Use the
   same fixtures, configuration, hardware, and workload for comparisons. Record
   absolute timings and variance; a single timing is not proof of a speedup.
6. Re-run affected suites after each fix, then the default suite on the final
   source tree. Build Release too, to cover code excluded by `#if DEBUG`.
7. Publish a run report with fixes, evidence, unresolved failures, skips, and
   untested integrations. Do not describe unresolved gates as completed.

## Risk matrix

| Area | Scenarios and failure modes | Evidence |
| --- | --- | --- |
| Observation/rendering | Repeated equal updates; real changes; long mixed Markdown; streaming while scrolling; switch sessions; first paint; resize | Session-store tests, transcript render smoke, streaming stability, measured-height tests |
| RPC lifecycle | Launch failure; delayed startup; malformed events; partial output; stop/restart; stale client events; final flush; compaction; forks | Fake-Pi bridge/context/fork tests; explicit live RPC evaluation separately |
| Persistence | Save/reload; debounce boundaries; crash recovery; corrupt index/manifest; lazy loads; deletion while work is pending; image ownership | Session-store and persistence suites, temporary fixtures only |
| Refresh/scanning | Watch storms; unchanged fingerprints; missing/deleted paths; symlinks; imported skills; switch projects during scan | Discovery/scanner tests plus inspection of task ownership/generation checks |
| Subagents/loops | Cancellation; timeout; parent deletion; supervisor requests; sequential/parallel completion; report-only write boundaries | Harnessed runtime/loop tests; live subagent evaluation remains separate |
| MCP/resources | Invalid configs; disconnect/reconnect; timeouts; malformed payloads; builtin overrides; secret redaction | MCP and resource tests; live accounts/services separately |
| Git/worktrees | Failed commands; paths with spaces; dirty tree; cleanup; preservation of user changes | Temporary repository tests; no production push/merge for validation |
| Packaging | Debug/Release compilation; signing configuration; installer behavior | Release build and signing checks; notarized distribution validated separately |

## Performance acceptance

- Equal state updates must not invalidate observers or schedule persistence.
- Disabled diagnostics must not evaluate expensive message expressions.
- Foreground fixed-cadence streaming must not repeatedly count the full text.
- No new unbounded timer/task loop, synchronous process wait, file-tree walk,
  or whole-transcript work on the main actor without measured justification.
- Track CPU, memory growth, main-thread stalls, and scroll/stream/session-switch
  latency separately. Report stalls at or above the existing watchdog's 150 ms
  threshold; do not equate offscreen measurements with visible GPU smoothness.
- Performance changes need either deterministic work-elimination tests or
  repeatable before/after measurements, plus functional regression coverage.

## Isolation and operational limits

XCTest must use temporary session stores. Do not edit bundled resources or use
production repositories as destructive test fixtures. Never silently enable
paid model calls or publish messages/commits as part of a test run.

`scripts/run-autoperf.sh` uses real data roots and must not run beside a live
Agent Deck instance. Prefer the headless fixtures when that condition cannot be
met. Manual transcript rendering is opt-in through
`AGENT_DECK_ENABLE_TRANSCRIPT_RENDER_SMOKE=1`; run it without parallel testing.

## Delivery gate

No unresolved reproducible crash, data loss, broken core flow, or security defect
may be called release-ready. Default tests and affected regression tests must
pass on the final tree; skipped/manual/live checks must be itemized. Any remaining
performance concern needs a reproduction and evidence, not an unsupported claim
that the application is bug-free.
