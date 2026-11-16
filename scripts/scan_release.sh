#!/bin/bash
# Looks through everything inside a release ZIP (programs included) for things that must never ship:
# this computer's folder paths, user and computer names, API keys, and any private words listed, one
# per line, in ~/.config/qingzhou/release-canaries.txt (or the file named by QINGZHOU_CANARIES).
#   scan_release.sh <zip>
set -euo pipefail
export LC_ALL=C
ZIP="$1"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
ditto -x -k "$ZIP" "$WORK"
BAD=0
check() { # <what it is> <fixed string>
  [ -n "$2" ] || return 0
  local hits; hits="$(grep -rlaF -- "$2" "$WORK" | sed "s#$WORK/##" || true)"
  if [ -n "$hits" ]; then echo "Found $1 in: $hits" >&2; BAD=1; fi
}
check "this computer's home folder" "$HOME"
check "a /Users/ folder path" "/Users/"
check "this computer's user name" "$(id -un)"
check "this computer's name" "$(scutil --get LocalHostName 2>/dev/null || true)"
check "the git author email of this machine" "$(git config --global user.email 2>/dev/null || true)"
KEYS='sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
if grep -rlaE "$KEYS" "$WORK" >/dev/null; then echo "Found something shaped like an API key or private key." >&2; BAD=1; fi
CANARIES="${QINGZHOU_CANARIES:-$HOME/.config/qingzhou/release-canaries.txt}"
N=0
if [ -f "$CANARIES" ]; then
  while IFS= read -r word; do
    [ -n "$word" ] || continue
    N=$((N + 1))
    if grep -rqaF -- "$word" "$WORK"; then echo "Found private word number $N from the canary list." >&2; BAD=1; fi
  done < "$CANARIES"
fi
if [ "$BAD" != "0" ]; then echo "Stopped: $ZIP must not be published." >&2; exit 1; fi
echo "Release scan passed: no machine paths, names, keys, or listed private words ($N checked)."
