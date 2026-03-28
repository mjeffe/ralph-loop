#!/bin/bash
# Sandbox Preferences
#
# User-defined preferences for the sandbox environment. This script is COPY'd
# into the Docker build context and executed during image build to apply
# packages, shell configuration, editor setup, and git config.
#
# TTY note: The Dockerfile strips `< /dev/tty` references automatically before
# executing this script, so commands that read from /dev/tty will work as-is.

set -euo pipefail

# --- Packages ---
apt-get update -qq
apt-get install -y --no-install-recommends vim bash-completion
rm -rf /var/lib/apt/lists/*

# --- User Environment ---

# Bashrc customizations (appended so they override existing defaults)
cat >> /home/ralph/.bashrc <<'BASHRC'

# -------------------------------
# bash customizations
# -------------------------------
git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
lt() {
    ls -lArtF "$@" | tail -20
}

PS1="\[\e[1;33m\]\u\[\e[m\]" # username yellow
PS1+=":"
PS1+="\[\e[0;36m\]\w\[\e[m\]" # pwd cyan
PS1+="\$(git_branch)" # git branch
PS1+="$ "
export PS1;

set -o vi
alias ll="ls -lF --group-directories-first"
alias vi=`which vim`
alias view="`which vim` -R"
alias vide='VIM_IDE=1 vim'
alias ralph='./.ralph/ralph'

export EDITOR=vim
export VISUAL=vim
BASHRC

# Vim configuration
curl -fsSL https://raw.githubusercontent.com/mjeffe/nix-profile/master/vim-config/install.sh \
    | bash -s min

# Git configuration
cat > /home/ralph/.gitconfig <<'GITCONFIG'
[push]
	default = simple
[pull]
	rebase = true
	stat = true
[remote "origin"]
	prune = true
[fetch]
	prune = true
[merge]
	stat = true
[alias]
	# simple log
	slog = log --decorate --oneline
	# full log
	flog = log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ad)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --full-history --sparse --date=local
	# who log
	wlog = log --pretty=format:"%h%x09%an%x09%ad%x09%s" --date=local
	# history log
	hlog = log --stat -p
	# history follow log (follows renames, deletes, etc)
	fhlog = log --oneline --find-renames --stat --follow
GITCONFIG

chown ralph:ralph /home/ralph/.bashrc /home/ralph/.gitconfig
