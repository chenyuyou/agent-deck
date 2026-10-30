# Agent Deck Documentation

This is the canonical reference set for how Agent Deck composes with the Pi CLI, how it manages resources, and how the app behaves at runtime.

In the session composer, Return sends the message once text input is complete. While an input method is composing text, Return and candidate navigation keys are handled by the input method first; confirming a candidate does not send the message.

Local file links in coding-agent messages resolve relative paths against the session's working directory, including its worktree when present. Absolute file paths open directly with the system's default application.

Transcript image references resolve relative to the session project or worktree, including percent-encoded Chinese filenames. The system-prompt preview token count is an approximate estimate that accounts for non-ASCII text; actual token counts depend on the model.

Conversation Markdown renders supported LaTeX math locally using MathJax, including `$…$`, `$$…$$`, `\(…\)` and `\[…\]`, common standalone `equation`, `align`, and matrix environments, as well as multiline bracketed formulas containing TeX commands. Conversion happens in the background; a native renderer provides an initial or fallback display. Standalone display formulas are centered; inline formulas stay with surrounding text. Outer `\boxed{…}` formulas have a visible border, and long plain `\text{…}` inside a box wraps. Code remains literal, and unsupported or incomplete formulas are not typeset. Selecting and copying a rendered formula copies its original markup.

## Concepts

- [Pi runtime vs Agent Deck](concepts/pi-runtime-vs-agent-deck.md) — where Pi ends and the app begins.
- [Resource scopes and resolution](concepts/resource-scopes-and-resolution.md) — Builtin / Global / Library / Project, and how the app picks one.
- [Safety and artifacts](concepts/safety-and-artifacts.md) — write targets, overrides, report-only subagents.
- [Loops](concepts/loops.md) — loop types, completion policy, validation, checkpoints, and parallel safety.

## Runtime reference

- [System prompt logic](agent-deck-system-prompt-logic.md) — how launch flags compose with Pi's prompt assembly.
- [Pi RPC launch flags](pi-rpc-launch-flags.md) — the full subprocess context surface.
- [Skills](skills-logic.md) — discovery, catalog, assignment, and explicit injection.
- [Model and thinking logic](model-and-thinking-logic.md) — launch-time configuration and per-session overrides.
- [Memory](memory.md) — project-scoped Markdown memory: launch-time index + recall, hybrid semantic/lexical ranking, upsert write tools with a near-duplicate guard.
- [Resource refresh and file watching](resource-refresh-and-file-watching.md) — FSEvents-driven catalog refresh.

## API reference

- [Agent frontmatter](reference/agent-frontmatter.md)
- [File locations](reference/file-locations.md)
- [Native subagent bridge](reference/native-subagent-bridge.md)

## Contributors

- [Architecture](contributors/architecture.md)
- [Source map](contributors/source-map.md)
- [Development and verification](contributors/development-and-verification.md)
- [LLM contributor guide](contributors/llm-contributor-guide.md)
- [Runtime validation matrix](contributors/runtime-validation-matrix.md)

Project-level invariants and UI conventions live in [`../docs/agent-guidelines/`](../docs/agent-guidelines/).
