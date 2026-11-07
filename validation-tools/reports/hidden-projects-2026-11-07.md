# Removed-project sidebar visibility — 1.0.1 build 20

## Behavior

Explicitly removed projects and their sessions are excluded from the expanded
sidebar, compact recent strip and session list. Hidden preferences invalidate all
three caches. Project paths are normalized before matching; similarly named
projects and unrelated missing projects remain visible.

Removal retains project files, worktrees and session history, and does not stop
running work. Re-adding a project exposes its retained sessions again.

## Validation

- Project discovery and session grouping: **50 passed, 0 failed, 0 skipped**.
- Summary: `/tmp/agent-deck-hidden-project-summary.json`.
- Final test log: `/tmp/agent-deck-hidden-project-tests-final.log`.
- New regression covers removed running sessions, normalized paths, unrelated
  missing projects, independent chats, historical regrouping and re-add visibility.
- The initial run exposed an invalid independent-chat test fixture (nonempty project
  path); it was corrected to use a project-kind session with an empty project path.
- `scripts/test-package-signing.sh` and `git diff --check` passed.
- Release log: `/tmp/agent-deck-hidden-project-build20-release.log`.

## Limits

No live mouse-driven check or full-suite rerun was performed for this focused
change. The local app is not Developer ID signed or notarized; the machine lacks
signing identities. No production project/session records were deleted or edited
as part of testing.

## Artifacts

Release build succeeded. Generated Info.plist confirms 1.0.1 / build 20 and the
chenyuyou/agent-deck update feed. ZIP integrity check passed.

- `build/hidden-projects-1.0.1-build20/Agent Deck.app`
- `build/hidden-projects-1.0.1-build20/Agent-Deck-1.0.1-build20-macOS-arm64.zip`
