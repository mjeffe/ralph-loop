# Sandbox Preferences

User-defined preferences for the sandbox environment. The agent reads this
file during `ralph sandbox setup` and incorporates these preferences into
the generated Dockerfile and related files.

## Packages

- Install `vim` (full version, not vim-tiny)

## User Environment

- Add the following preferences to the user's environment setup (probably `~/.bashrc`):
```
    set -o vi
    alias ll="ls -lF --group-directories-first"
    alias vi=`which vim`
    alias view="`which vim` -R"

    # list the most recently changed files
    lt() {
        ls -lArtF "$@" | tail -20
    }
```


