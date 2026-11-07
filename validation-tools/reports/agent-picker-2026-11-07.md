# Agent picker follow-up (1.0.1 build 19)

## Changes

- Add agents opens the picker even when no additional catalog entries exist;
  its empty state explains catalog creation/import instead of silently disabling it.
- Deselected default agents are offered by Add agents again. The selection filter
  retains existing extra-agent choices and deduplicates names.
- Session settings explains how to open model and thinking controls.

## Verification

- Added a regression test covering deselected defaults, selected defaults,
  extra-agent preservation and duplicate names.
- Before these source changes, live Computer Use on the installed app opened the
  model menu and changed explorer thinking Medium → High → Agent default (Medium).
  The original thinking configuration was restored. This verifies UI persistence,
  not a live provider/model invocation.
- Package signing static checks and git diff --check passed.
- Full retry: **782 total, 776 passed, 1 timed out, 5 existing skips**.
- Timed out: `CodexComputerUseBrokerDiscoveryTests.testVariantDerivationScriptPinsReviewedApprovalChanges`.
  The sampled main thread was blocked opening the repository script (Foundation
  String(contentsOf:) → open), not in Agent picker code. Underlying filesystem
  blocking cause is unconfirmed. The first unbounded run was stopped after sampling.
- A shell/Python check independently passed the same seven broker-script static
  assertions (both digests plus five reviewed source markers). This does not turn
  the timed-out XCTest into a pass.
- The new picker regression test passed. Previous focused 13-test run also passed.
- Result bundle: /tmp/agent-deck-picker-build19-retry.xcresult.
- Summary: /tmp/agent-deck-picker-build19-summary.json.
- Stack sample: /tmp/agent-deck-build19-testhost.sample.txt.
- Test log: /tmp/agent-deck-picker-build19-tests.log.
- Release build log: /tmp/agent-deck-picker-build19-release.log.

## Distribution limits

Local Release app only: no Developer ID signing identities are installed, so the
notarized DMG workflow cannot be completed. Live provider calls and a production
performance workload were not run. The existing optional live diagnostic skips
are not counted as passes.

## Build artifacts

Release build succeeded. Version 1.0.1 / build 19 and the chenyuyou GitHub update
feed were verified from the generated Info.plist. ZIP integrity verification passed.
Artifacts: `build/agent-picker-1.0.1-build19/Agent Deck.app` and
`build/agent-picker-1.0.1-build19/Agent-Deck-1.0.1-build19-macOS-arm64.zip`.
