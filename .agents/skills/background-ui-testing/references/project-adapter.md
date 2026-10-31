# Adopting the contract

Keep the reusable skill independent of a particular product or harness. Store
project launch commands and exceptions in the project's own instructions or
testing document. No dependency on Codex, macOS, a particular MCP, or a new
permission is implied by the core contract.

## Project adapter

An adapter should identify the existing, supported:

- Isolated test build/profile, app identity, launch command, and graceful stop.
- Background presentation and optional display placement, including fallback.
- Bounded diagnostics and evidence output location, with their limitations.
- Verified controls versus activating/unsupported steps, per tested harness.
- Changed-state ownership, restoration, and normal launch fallback.

If one of these is unavailable, report the gap. Do not invent a background
mode, introduce tools, or alter the product just to fill the adapter.
An adapter need not be a new config format; a short existing document is enough.

## Instruction-file entry

Place this rule in `AGENTS.md` or the instruction entry point the harness
actually reads. Resolve the skill link against its installed location; adjust
it if the project uses another layout.

```markdown
## Background UI Testing

When testing a UI while the user continues working, read and follow
[background-ui-testing](.agents/skills/background-ui-testing/SKILL.md).
This applies to every agent, harness, and Computer Use provider.

Use this project's isolated test launcher and documented tool restrictions.
Verify capabilities before live attachment/input, then run a bounded
setting/navigation/screenshot gate without test-caused focus, pointer, or
workspace interference. Stop unsupported steps; never activate then restore.
Report functional and background results separately as PASS, FAIL, BLOCKED,
or NOT RUN, with evidence covering the actual action times. Restore only
this run's state and stop only its instances/observers.
```

If a harness cannot load skills, copy the rule into its actual instruction
file and supply the skill text as a referenced document. Do not claim that
`AGENTS.md`, a filename convention, or skill installation enforces behavior in
every runtime. Verify discovery in that runtime. Keep this entry short and
maintain the full procedure in one skill.

## Distribution

The repository copy is versioned source. For personal reuse, a copy can be
installed under `~/.agents/skills/background-ui-testing` for harnesses that
discover that directory. Other harnesses need their own supported skill path
or instruction reference. No global instruction files need to be overwritten.

Keep relative references within the skill so the directory can move intact.
`agents/openai.yaml` is optional Codex UI metadata; other harnesses can ignore
it. The core `SKILL.md` has no hardcoded CU API, machine path, dependency, or
permission requirement. This is a user-maintained local skill, not a
third-party entry to regenerate through a project's upstream lock file.
