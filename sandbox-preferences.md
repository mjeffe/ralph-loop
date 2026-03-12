# Sandbox Preferences

User-defined preferences for the sandbox environment. The agent reads this
file during `ralph sandbox setup` and incorporates these preferences into
the generated Dockerfile and related files.

## Packages

- Install `vim` (full version, not vim-tiny)

## User Environment

- Add the following preferences to the bottom of the user's `~/.bashrc` so they override existing defaults.
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

- Add a `~/.vimrc` with the following contents:
```
filetype plugin indent on           " required - turn on file type specific indening
set backspace=indent,eol,start      " make backspace work as you would expect - allow backspacing over line breaks,
                                    " automatically-inserted indentation, or the place where insert mode started

set ruler                           " show vim ruler
set showcmd                         " show incomplete cmds in bottom status bar
set showmode                        " show current mode in bottom status bar
set incsearch                       " jump to search results as typing?
set encoding=utf-8

"display tabs and trailing spaces, turn of with :set nolist
set list
set listchars=tab:▷⋅,trail:⋅,nbsp:⋅

" set shiftwidth and tabstop to the same value, and set expandtab to always insert spaces
set shiftwidth=4                    " set the number of spaces to use for a tab
set tabstop=4                       " sets a tab equivalent to 3 spaces
set expandtab                       " insert shiftwidth or tabstop spaces whenever a tab is used⋅
set pastetoggle=<F12>               " toggles the paste nopaste modes to turn on/off automatic indenting

"syntax enable                       " enable syntax highlighting, but allow customization (v.s. syn on)
syntax on                           " enable syntax highlighting, but allow customization (v.s. syn on)
```

