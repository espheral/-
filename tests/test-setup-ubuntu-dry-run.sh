#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_home=$(mktemp -d)
trap 'rm -rf -- "$tmp_home"' EXIT

mkdir -p "$tmp_home/.config/nvim"
printf 'sentinel-zsh\n' > "$tmp_home/.zshrc"
printf 'sentinel-vim\n' > "$tmp_home/.config/nvim/init.vim"
before=$(find "$tmp_home" -type f -exec sha256sum {} + | sort)

output=$(UBUNTU_PRO_TOKEN='never-print-this-secret' HOME="$tmp_home" USER=tester "$repo_dir/setup-ubuntu.sh" \
    --dry-run --replace-dotfiles --configure-git --generate-ssh-key \
    --with-docker 2>&1)

after=$(find "$tmp_home" -type f -exec sha256sum {} + | sort)
[[ "$before" == "$after" ]] || { echo "FAIL: dry-run changed HOME" >&2; exit 1; }
grep -q 'Modo=dry-run' <<<"$output"
grep -q 'No se ha modificado el sistema' <<<"$output"
grep -q 'token-oculto-o-magic-attach' <<<"$output"
if grep -q 'never-print-this-secret' <<<"$output"; then
    echo "FAIL: environment token leaked to output" >&2
    exit 1
fi
grep -q 'apt-get upgrade omitido' <<<"$output"
grep -q 'Docker Engine desde el repositorio oficial' <<<"$output"

if HOME="$tmp_home" "$repo_dir/setup-ubuntu.sh" --token secret >/dev/null 2>&1; then
    echo "FAIL: --token should be rejected" >&2
    exit 1
fi

echo "PASS: dry-run is non-mutating and argv tokens are rejected"
