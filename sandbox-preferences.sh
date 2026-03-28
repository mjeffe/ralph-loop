#!/bin/bash
# Sandbox Preferences
#
# User-defined preferences for the sandbox environment. This script runs as
# root during `docker build` to install packages, configure dotfiles, set up
# editors, and apply any other customizations you want in your container.
#
# How it works:
# - Runs during image build, not on every container start. Changes are baked
#   into the Docker image layer.
# - Every `ralph sandbox up` copies this file into the build context and
#   rebuilds with --build. Docker's layer cache skips re-execution if the
#   file hasn't changed. Edit this file and run `sandbox up` to apply changes.
# - Runs as root, so apt-get install, writing to /home/ralph, etc. all work.
#   Ownership of /home/ralph is fixed after this script runs.
#
# IMPORTANT: This script runs non-interactively — there is no TTY during
# `docker build`. Commands that read from /dev/tty will fail. This includes
# commands in scripts fetched via curl. Common patterns and workarounds:
#
#   Problem:  vim +PlugInstall +qall </dev/tty
#   Fix:      vim -es -u ~/.vimrc +PlugInstall +qall
#
#   Problem:  curl -fsSL https://example.com/setup.sh | bash  # script uses /dev/tty internally
#   Fix:      curl -fsSL https://example.com/setup.sh | sed 's|</dev/tty||g' | bash
#
#   Problem:  read -p "Continue? " answer </dev/tty
#   Fix:      Remove interactive prompts, or default to "yes" in Docker builds

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
