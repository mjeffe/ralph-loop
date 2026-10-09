# Proposal: Sandbox Integration Tests

## Status
Proposed — not yet committed.

## Summary

Add two levels of automated sandbox testing to catch regressions without requiring a full agent invocation.

## Design

### 1. Entrypoint Snippet Tests

Add `tests/test_sandbox_snippets.sh` that runs the "use exact" entrypoint snippets from prompt appendices inside `docker run --user ralph ralph-sandbox-base` to catch runtime failures (e.g., `su - ralph` hanging). No agent invocation, just Docker + bash.

### 2. Smoke Test with Fixture

Ship a fixture `tests/fixtures/hello-project/` with a minimal pre-baked profile and generated files. Test does `docker compose up`, waits for healthy, asserts basics (user is ralph, git works, supervisord is PID 1), then tears down.

Gate behind `--integration` flag since it is slow.

## Trade-offs

- Adds Docker as a test dependency. The snippet tests are fast (single `docker run`). The smoke test is slow (full compose cycle) but gated behind a flag.
- Catches regressions in the sandbox setup that are otherwise only discovered during real agent runs.
- Does not test agent behavior inside the sandbox — only that the sandbox itself starts correctly.

## Decision Criteria

Implement when sandbox-related changes become frequent enough that manual verification is a bottleneck.