#!/usr/bin/env bash
# Checks that audit-linux.sh leaves HOME untouched, flags planted risks,
# never prints secret values and redacts identifying data.
set -Eeuo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
home="$tmp/home"
mkdir -p "$home/.ssh" "$home/.claude"
chmod 700 "$home/.ssh"

printf 'https://user:never-print-this-token@github.com\n' > "$home/.git-credentials"
printf 'export OPENAI_API_KEY=never-print-this-key\n' > "$home/.bashrc"
printf 'curl -H "Authorization: token ghp_neverprintthishistorytoken"\n' > "$home/.bash_history"
printf '{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(*)"]}}\n' > "$home/.claude/settings.json"
printf '{"mcpServers":{"planted-mcp":{"command":"npx"}}}\n' > "$home/.claude.json"
chmod 644 "$home/.claude.json"
printf 'contacto: persona@example.com\n' > "$home/.env"
if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -q -t ed25519 -N '' -C '' -f "$home/.ssh/id_ed25519" >/dev/null
fi

before=$(find "$home" -exec stat -c '%n %a %s %Y' {} + | sort; find "$home" -type f -exec sha256sum {} + | sort)
out=$(HOME="$home" "$repo_dir/audit-linux.sh" --output "$tmp/report.md" 2>&1)
after=$(find "$home" -exec stat -c '%n %a %s %Y' {} + | sort; find "$home" -type f -exec sha256sum {} + | sort)

[[ "$before" == "$after" ]] || { echo "FAIL: audit changed HOME" >&2; exit 1; }
[[ $(stat -c '%a' "$tmp/report.md") == 600 ]] || { echo "FAIL: report is not 600" >&2; exit 1; }
grep -q 'git-credentials guarda tokens Git en texto plano' <<<"$out"
grep -q 'bashrc exporta variables con API_KEY' <<<"$out"
grep -q 'bash_history: 1 líneas con posible secreto' <<<"$out"
grep -q 'defaultMode=bypassPermissions' <<<"$out"
grep -q 'permisos amplios pre-aprobados: Bash(\*)' <<<"$out"
grep -q 'planted-mcp' <<<"$out"
grep -q 'claude.json legible por grupo/otros' <<<"$out"
if command -v ssh-keygen >/dev/null 2>&1; then
    grep -q 'id_ed25519 sin passphrase' <<<"$out"
fi
if grep -qE 'never-print-this|ghp_neverprint' <<<"$out" || grep -qE 'never-print-this|ghp_neverprint' "$tmp/report.md"; then
    echo "FAIL: secret value leaked to output" >&2
    exit 1
fi
grep -q 'No se ha modificado el sistema' "$tmp/report.md"

echo "PASS: Linux audit is read-only, flags planted risks and hides secret values"
