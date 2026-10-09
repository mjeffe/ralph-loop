# Known Issues

This spec documents bugs that affect users and lack obvious workarounds.
Not every bug belongs here — only ones with user-facing impact where
advance warning saves debugging time.

When an issue is fixed, remove it from this file and note the fix in the
commit message. Do not let this become a graveyard of stale entries.

---

## `ralph update` Breaks When the Ralph Script Itself Changed

**Symptom:** Running `ralph update` in a parent project when the `ralph`
script itself has been modified produces a shell syntax error:

```
./ralph: line 1663: unexpected EOF while looking for matching `''
```

**Cause (hypothesis):** The running shell process is reading the `ralph`
script as it executes. When `ralph update` overwrites the script file
mid-execution, the shell's read position is invalidated, causing it to
see a truncated or corrupted version of the file.

**Affected:** All versions. The bug is inherent to the self-replacing
script pattern.

**Workaround:** If this happens, re-run `ralph update` from the fresh
copy. The new version is already in place; the error occurs after the
file has been written.

**Related:** `specs/updater.md`