# Alignment Ledger

Process Specs: specs/process/
Created: 2026-10-11

Migration: `specs/process/output-pipeline-python.md` (Phases 1-3, all complete per
`implementation_plan.md`). The phases were purely additive: `lib/format_output.py`,
`tests/test_format_output.py`, and a `format_output` group in `tests/test_ralph.sh`.
Nothing in `ralph` or `agents/*.sh` calls the processor yet. The process spec defers the
cutover, including updates to `loop-behavior.md`, `agent-scripts.md`,
`project-structure.md`, `tech-debt.md`, and `README.md`, to one supervised integration
commit ("What This Spec Does NOT Cover"; prompt: `integrate-output-pipeline-prompt.md`,
section 5).

Grep terms used for the completeness check (all specs except `process/` and `archive/`):
`format_output`, `agent_format_display`, `agent_extract_response`, `agent_post_iteration`,
`test_ralph.sh`, `Available groups`, `unittest`, `python`, `lib/`.

## Affected Specs

### 1. specs/output-pipeline.md
Status: complete
Changes: New target-state spec for the processor, which had no spec outside the process
spec (and would lose its contract once the process spec is archived). Covers integration
status, CLI and exit codes, summary JSON, the signal detection constraint, screen vs. log
display, robustness, implementation shape, the `text` / `stream-json` / `pi-json` rules,
adding a format, and testing. Records build-time decisions from the plan notes (untruncated
error detail lines, stderr line numbers count blank lines, non-boolean `result.is_error`
ignored, `"unknown error"` fallback, top-level-only context, pi missing usage fields count
as 0). Follow-up for integration: the module docstring in `lib/format_output.py` still
points to the process spec for the contract; repoint it here when the process spec is
archived (code change, out of scope for this mode).
Commit: see git log ("docs: add output-pipeline spec and alignment ledger")

### 2. specs/README.md
Status: complete
Changes: Added `output-pipeline.md` to the index. The process spec entry stays (the user
archives it).
Commit: see git log ("docs: add output-pipeline spec and alignment ledger")

### 3. specs/loop-behavior.md
Status: complete
Changes: Confirmed unchanged. Grep matches (`agent_format_display`,
`agent_extract_response`, `agent_post_iteration`, session log via `tee -a`) still describe
current `ralph` behavior, because the processor is not wired in. The process spec assigns
its rewrite to the integration commit.

### 4. specs/agent-scripts.md
Status: complete
Changes: Confirmed unchanged. The bash function contract is still what `agents/*.sh`
implement. `AGENT_OUTPUT_FORMAT` and the reduced contract arrive with the integration
commit, which owns this spec's update.

### 5. specs/project-structure.md
Status: blocked
Reason: Deferred by the process spec. The lib table and trees do not list
`lib/format_output.py`, but the process spec ("What This Spec Does NOT Cover") assigns this
update to the supervised integration commit and says not to modify the file during this
migration. The lib table also describes modules "sourced or invoked by ralph", which the
processor is not yet. Resolve during integration.

### 6. specs/tech-debt.md
Status: blocked
Reason: Deferred by the process spec. Item 3's remediation sketch is stale relative to the
built design (`lib/format-output.py --agent "$AGENT"`, `| tee -a "$SESSION_LOG"`, and
"Signal detection checks all message types", which contradicts the assistant-text-only
constraint now in `output-pipeline.md`). Item 7 already describes the post-integration
state ("ralph refuses to run them"), which is not yet true. The integration plan removes
items 3 and 6 and keeps items 5 and 7; the process spec forbids editing this file before
then.

### 7. specs/sandbox-setup-prompt.md
Status: complete
Changes: Confirmed unchanged. Its `agent_invoke ... | agent_format_display` examples match
current `lib/sandbox.sh` usage. The integration commit removes `agent_format_display`, so
these examples will need updating then (not listed in the process spec's integration
scope; flagged here for the integration session).

### 8. specs/installer.md, specs/updater.md
Status: complete
Changes: Confirmed unchanged. `lib/format_output.py` is not yet in `MANAGED_FILES`; adding
it is integration work.
