#!/usr/bin/env bash
# Verifies setup-debian.sh / setup-linux-terminal.sh / sync-dotfiles.sh safety
# properties on any Debian-family host (CI: Ubuntu 24.04). Never mutates HOME.
set -Eeuo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_home=$(mktemp -d)
trap 'rm -rf -- "$tmp_home"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp_home/.config/nvim"
printf 'sentinel-zsh\n' > "$tmp_home/.zshrc"
printf 'sentinel-vim\n' > "$tmp_home/.config/nvim/init.vim"
snapshot() { find "$tmp_home" -type f -exec sha256sum {} + | sort; }
before=$(snapshot)

all_flags=(--replace-dotfiles --set-shell --configure-git --generate-ssh-key
           --with-nodesource --with-claude-code)

for target in proot avf; do
    out=$(HOME="$tmp_home" USER=tester bash "$repo_dir/setup-debian.sh" --target "$target" "${all_flags[@]}" 2>&1) \
        || fail "dry-run --target $target exited non-zero: $out"
    grep -q "Modo=dry-run destino=$target" <<<"$out" || fail "missing mode line ($target)"
    grep -q 'No se ha modificado el sistema' <<<"$out" || fail "missing dry-run summary ($target)"
    grep -q 'apt-get upgrade omitido' <<<"$out" || fail "upgrade not skipped by default ($target)"
    grep -q 'fichero temporal' <<<"$out" || fail "remote scripts must be downloaded, not piped ($target)"
done

code=$(grep -v '^[[:space:]]*#' "$repo_dir/setup-debian.sh")
grep -Eq 'curl[^|]*\|[[:space:]]*(sudo[^|]*)?(ba)?sh' <<<"$code" && fail "curl | sh found"
grep -q -- '-N ""' <<<"$code" && fail "passphrase-less ssh-keygen found"
grep -q -- '--break-system-packages' <<<"$code" && fail "global pip install found"

out=$(HOME="$tmp_home" bash "$repo_dir/setup-linux-terminal.sh" 2>&1) || fail "wrapper dry-run failed"
grep -q 'destino=avf' <<<"$out" || fail "wrapper must force --target avf"
grep -q 'Dotfiles omitidos' <<<"$out" || fail "dotfiles must be opt-in"

[[ $(snapshot) == "$before" ]] || fail "dry-run changed HOME"

HOME="$tmp_home" bash "$repo_dir/setup-debian.sh" --target avf --reuse-termux-ssh-key >/dev/null 2>&1 \
    && fail "--reuse-termux-ssh-key must be rejected for avf"
HOME="$tmp_home" bash "$repo_dir/setup-debian.sh" --target bogus >/dev/null 2>&1 \
    && fail "invalid --target must be rejected"
HOME="$tmp_home" bash "$repo_dir/setup-debian.sh" --target proot --apply >/dev/null 2>&1 \
    && fail "--apply must refuse when detected env differs from --target"

# sync-dotfiles: pull backs up differing local files before overwriting
sync_dir="$tmp_home/sync"
mkdir -p "$sync_dir"
printf 'remote-zsh\n' > "$sync_dir/.zshrc"
HOME="$tmp_home" SYNC_DIR="$sync_dir" bash "$repo_dir/sync-dotfiles.sh" pull >/dev/null 2>&1 || fail "sync pull failed"
grep -q remote-zsh "$tmp_home/.zshrc" || fail "sync pull did not update .zshrc"
grep -rq sentinel-zsh "$tmp_home/.local/state/dev-setup/backups" || fail "sync pull did not back up .zshrc"

echo "PASS: Debian/AVF dry-run is non-mutating; unsafe patterns absent; sync pull backs up"
