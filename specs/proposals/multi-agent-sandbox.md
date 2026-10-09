# Proposal: Multi-Agent Sandbox

## Status
Proposed — not yet committed.

## Summary

Install all supported agent CLIs in the base image and forward all possible API keys in
docker-compose.yml so that switching `AGENT` in config only requires an agent script change at
runtime — no rebuild, no re-render.

## Problem

The sandbox bakes one agent CLI into the base image and one set of API-key env vars into
`docker-compose.yml` at setup time. Switching `AGENT` in config requires a rebuild
(`sandbox_build_base`) and a re-render (`--render-only --force`) to wire up the new agent.
You can not freely switch between amp, pi, claude, etc. on an existing sandbox.

## Design

Install all supported agent CLIs in the base image and forward all possible API keys in
docker-compose.yml. `AGENT` in config then only selects which `agents/*.sh` ralph sources at
runtime — no rebuild, no re-render needed.

### Changes

1. **`lib/sandbox.sh`**: New helper functions that source all `agents/*.sh` and aggregate
   `AGENT_INSTALL` (joined with `&&`) and `AGENT_ENV_KEYS` (union of all). `sandbox_build_base`
   and `sandbox_setup` call these instead of reading the single agent.

2. **`Dockerfile.base`**: No change — the single `ARG AGENT_INSTALL` already accepts a
   multi-command string.

3. **`prompts/sandbox-render.md`**: Update to present all aggregated env keys instead of one
   agent key.

4. **`specs/agent-scripts.md`**: Document the split: `AGENT_INSTALL`/`AGENT_ENV_KEYS` are
   consumed in aggregate at build time; function contracts (`agent_invoke`, etc.) are still
   per-invocation at runtime.

5. **Tests**: Verify that switching `AGENT` and running `sandbox up` works without
   `--render-only`.

### Trade-offs

- **Upside**: Switch agents by editing one line in `config`. No rebuild, no re-render.
- **Downside**: Base image is larger (~5 CLIs instead of 1). Mitigated by caching.
- **Downside**: Compose file references keys the user might not have. Mitigated by `${VAR:-}`
  syntax with empty defaults, so the agent just fails with a clear auth error (same as today
  for a missing key).

### Scope

Agent script contract (functions like `agent_invoke`) stays per-agent. Only installation and
env forwarding become aggregated.