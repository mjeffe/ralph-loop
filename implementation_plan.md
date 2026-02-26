# Implementation Plan

## Learnings & Gotchas

- The ralph-loop repo is self-hosting: RALPH_DIR resolves to the project root, so `last_agent_output`, `implementation_plan.md`, etc. all live at root level.
- Specs are sometimes internally inconsistent (e.g., `text` agent type listed in overview.md and project-structure.md but absent from loop-behavior.md's agent type table).
- The canonical prompt templates live in the specs (plan-mode.md, build-mode.md). The actual prompt files (prompts/plan.md, prompts/build.md) must match them. Both have drifted slightly.
- The updater feature (specs/updater.md) is entirely unimplemented — no update.sh, no `update` mode in ralph, no .version/.manifest support.

---

### Task 1: Fix prompt mode max_iterations parsing
**Status:** planned
**Spec:** specs/loop-behavior.md
**Priority:** high (bug fix)

The spec says `prompt <file> [max_iterations]` but the argument parser only captures the file — a second positional arg for prompt mode is ignored. Fix the argument parser in `ralph` to accept both `PROMPT_FILE` and `MAX_ITERATIONS` when mode is `prompt`.

**Current code (around line 79):**
```bash
if [[ "$MODE" == "prompt" ]]; then
    PROMPT_FILE="$1"
else
    MAX_ITERATIONS="$1"
fi
```

**Fix:** After capturing `PROMPT_FILE`, if another positional arg follows, capture it as `MAX_ITERATIONS`. One approach: track whether PROMPT_FILE has been set; if it has, treat the next positional as MAX_ITERATIONS.

---

### Task 2: Sync prompt templates with canonical specs
**Status:** planned
**Spec:** specs/plan-mode.md, specs/build-mode.md

Both prompt files have drifted from their canonical definitions in the specs. Reconcile them.

**Plan prompt (prompts/plan.md vs specs/plan-mode.md):**
- Actual prompt has step 9 "Commit all changes with a descriptive commit message" which the spec omits. This is useful behavior — update the spec to include it (making the spec have 10 responsibilities instead of 9).

**Build prompt (prompts/build.md vs specs/build-mode.md):**
- Spec Mission section says "using parallel subagents" and "using subagents" — actual prompt omits these. Decide whether subagent references belong in the canonical template (they're agent-specific, not all agents support subagents). If keeping them, update prompts/build.md. If removing, update the spec.
- Minor punctuation differences (trailing periods on list items).

**Rule from AGENTS.md:** "When modifying prompt templates in prompts/, also update the canonical template definitions."

---

### Task 3: Resolve `text` agent type spec inconsistency
**Status:** planned
**Spec:** specs/overview.md, specs/project-structure.md, specs/loop-behavior.md

`overview.md` lists `text` as a supported AGENT_TYPE. `project-structure.md` shows a `text` config example. But `loop-behavior.md` (the detailed agent type spec with the definitive table) does not include `text`.

**Options:**
1. Fully define `text` in loop-behavior.md and implement it in `ralph` → adds complexity for a type that has no JSON output parsing
2. Remove `text` references from overview.md and project-structure.md → simpler, acknowledges that all supported agents produce NDJSON

**Recommendation:** Option 2 — remove `text` references since the loop's architecture (completion detection, display filters) assumes NDJSON output.

---

### Task 4: Clean up .gitignore and add generated file exclusions
**Status:** planned
**Spec:** specs/project-structure.md, specs/loop-behavior.md

**Root .gitignore (ralph-loop repo):**
- Remove unrelated Laravel/Node entries (lines 4-30) — this is a bash project, not Laravel
- Add `last_agent_output` — generated each iteration, should not be committed

**Installer .gitignore template (.ralph/.gitignore in install.sh):**
- Add `last_agent_output` exclusion — the loop writes this file inside RALPH_DIR

---

### Task 5: Update installer to generate .version and .manifest
**Status:** planned
**Spec:** specs/updater.md (section "Changes to Existing Files → install.sh")
**Depends on:** none (but prerequisite for Tasks 6-7)

The updater spec requires the installer to:
1. Write `.ralph/.version` with the current upstream commit hash at install time
2. Write `.ralph/.manifest` with SHA256 checksums of all installed files

**Implementation notes:**
- When running via curl from GitHub, the installer can query the GitHub API or use `git ls-remote` to get the current HEAD commit hash.
- When running locally from the ralph-loop repo, use `git rev-parse --short HEAD`.
- Manifest entries: one line per file, format `<sha256>  <relative-path>` (relative to .ralph/).
- Files to track: ralph, config, prompts/plan.md, prompts/build.md, README.md.
- Do NOT track: implementation_plan.md, logs/, .gitignore (these are project state).

---

### Task 6: Add `update` mode to ralph script
**Status:** planned
**Spec:** specs/updater.md (section "Changes to Existing Files → ralph")
**Depends on:** Task 5

Add `update` as a recognized mode in the ralph script. When invoked:
```bash
.ralph/ralph update
```

Behavior:
1. Fetch and execute the remote `update.sh` from GitHub: `curl -sSL https://raw.githubusercontent.com/mjeffe/ralph-loop/main/update.sh | bash`
2. No iteration loop — single execution
3. Does not require agent CLI to be installed (skip that prerequisite check for update mode)

**Changes to ralph:**
- Add `update` to the case statement in argument parsing (line 64-66)
- Add `update` case in the entry point (line 443+)
- Skip agent CLI validation for update mode in `validate_prerequisites`
- Update `usage()` to list the update mode

---

### Task 7: Create update.sh
**Status:** planned
**Spec:** specs/updater.md
**Depends on:** Tasks 5, 6

Create `update.sh` at the project root implementing the full update logic:

1. **Pre-update checks:** verify .ralph/ exists, .git/ exists, network access
2. **Version comparison:** read .ralph/.version, compare to latest upstream commit
3. **Manifest-based file update:**
   - For each managed file: compute current checksum, compare to manifest
   - Checksums match → overwrite with new version
   - Checksums differ → preserve user version, write `<file>.upstream`
   - File deleted by user → skip
   - New upstream files → add normally
4. **Post-update:** update .manifest, update .version, display summary
5. **Edge case: pre-manifest install** — treat all files as modified, write .upstream for everything

Also update `.ralph/.gitignore` template in install.sh to include `*.upstream`.

---

### Task 8: Sync README.md with current project state
**Status:** planned
**Spec:** specs/overview.md, specs/project-structure.md
**Depends on:** Tasks 1-7 (do this last)

Minor README updates to keep it aligned:
- Verify the updater spec is referenced (it's already in the specs table in README)
- Update "Future Enhancements" to remove "Upgrade mechanism" since the updater spec now exists
- Any other alignment issues discovered during earlier tasks
