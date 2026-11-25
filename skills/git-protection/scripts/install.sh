#!/usr/bin/env bash
# Install the git-protection hooks.
#   install.sh                 for this user (git config --global core.hooksPath)
#   install.sh --repo <path>   for one repository only (git config --local)
#   install.sh --uninstall [--repo <path>]
# Re-runnable. Refuses to replace a core.hooksPath that points somewhere else, because that
# directory (husky, lefthook, a team hooks dir) would stop running; merge by hand instead.
set -euo pipefail

src=$(dirname "$(readlink -f "$0")")
dst=${GIT_PROTECTION_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/git/hooks}
scope=--global; repo=""; action=install
while [ $# -gt 0 ]; do
  case $1 in
    --repo)      repo=${2:?--repo needs a path}; scope=--local; shift ;;
    --uninstall) action=uninstall ;;
    -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done
g() { if [ -n "$repo" ]; then git -C "$repo" config "$scope" "$@"; else git config "$scope" "$@"; fi; }

current=$(g --get core.hooksPath 2>/dev/null || true)
if [ "$action" = uninstall ]; then
  if [ "$current" = "$dst" ]; then g --unset core.hooksPath; echo "core.hooksPath unset (hooks left in $dst)"
  else echo "core.hooksPath is '${current:-unset}', not $dst; nothing to do"; fi
  exit 0
fi

if [ -n "$current" ] && [ "$current" != "$dst" ]; then
  echo "install.sh: core.hooksPath is already '$current'. Not replacing it." >&2
  echo "  Copy scripts/pre-push into that directory instead, or set GIT_PROTECTION_DIR to it." >&2
  exit 1
fi

mkdir -p "$dst"
install -m 755 "$src/pre-push" "$dst/pre-push"
install -m 755 "$src/_chain" "$dst/_chain"
# core.hooksPath replaces <repo>/.git/hooks, so every other client hook chains to the repo's own.
for h in applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg \
         commit-msg post-commit pre-rebase post-checkout post-merge post-rewrite pre-auto-gc \
         post-update push-to-checkout reference-transaction sendemail-validate; do
  ln -sfn _chain "$dst/$h"
done
g core.hooksPath "$dst"
echo "installed to $dst; core.hooksPath=$dst (${scope#--})"
