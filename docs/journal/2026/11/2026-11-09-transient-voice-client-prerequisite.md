# Transient voice input prerequisite for Studio App Phase 7.1

Date: 2026-11-09

The existing shared dictation and explicit local cleanup implementation is
selected as a dependency of the Studio existing-Material Candidate editor.
Core owns transient audio, readiness, cancellation and native model interaction.
Its result is an editable suggestion; it neither creates Material nor saves or
submits a domain object. Source text remains separate from model instructions.

This contribution includes the two voice API exports and their existing native
bridges. Video capture, playback, recovery and multimedia dependencies are kept
in the original pending worktree. No artifact version or dependency coordinate
is changed. The source-date and preceding development history remain intact.

The shared field's launch-time opt-out/factory protection belongs to TFAF.
Core specifications retain their behavior and have adjacent semantic action and
expectation descriptions. The selected contribution can be committed without
closing App Phase 7.2 or claiming model quality/device acceptance.

Detailed execution and independent-review material is retained locally at
`/Users/asami/src/Project2026/nict-editing-studio-app/target/phase71-commit-preparation-001/`.
That active material is excluded from Git. Original worktrees and saved data
remain available; no push or deployment is part of this contribution.
