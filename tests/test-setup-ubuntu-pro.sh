#!/usr/bin/env bash
# Pruebas de la lógica de Ubuntu Pro con binarios simulados (sin tocar el sistema).
set -Eeuo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
bin="$work/bin"
mkdir -p "$bin"

# pro simulado: registra argv y, para attach, el contenido de --attach-config.
cat >"$bin/pro" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
case "$1" in
    status) printf '{"attached": %s}\n' "$FAKE_ATTACHED" ;;
    attach)
        while (($#)); do
            if [[ $1 == --attach-config ]]; then
                cp -- "$2" "$FAKE_LOG.cfg"
                stat -c '%a' "$2" >"$FAKE_LOG.mode"
            fi
            shift
        done ;;
    enable) [[ " ${FAKE_FAIL:-} " == *" $2 "* ]] && exit 1 ;;
esac
exit 0
EOF
cat >"$bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$FAKE_LOG"
EOF
chmod +x "$bin/pro" "$bin/apt-get"

# Carga las funciones del script sin ejecutar main.
lib="$work/lib.sh"
sed '$d' "$repo_dir/setup-ubuntu.sh" >"$lib"

run_case() {
    local attached=$1 fail=$2 token=$3 wsl=$4
    : >"$work/log"
    rm -f "$work/log.cfg" "$work/log.mode"
    PATH="$bin:$PATH" FAKE_LOG="$work/log" FAKE_ATTACHED=$attached FAKE_FAIL=$fail \
        UBUNTU_PRO_TOKEN=$token bash -c '
            lib=$1; set --; source "$lib"
            MODE=apply; SUDO=(); IS_WSL='"$wsl"'; IS_CONTAINER=0
            setup_ubuntu_pro' _ "$lib" </dev/null >/dev/null 2>&1
}

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. Sin attach + token de entorno: attach vía fichero 0600, token fuera de argv.
run_case false "" "tok-SECRET-123" 0 || fail "flujo con token abortó"
grep -q '^attach --no-auto-enable --attach-config ' "$work/log" || fail "no se hizo attach"
grep -q 'tok-SECRET-123' "$work/log" && fail "token presente en argv"
grep -q 'tok-SECRET-123' "$work/log.cfg" || fail "token ausente del attach-config"
[[ $(cat "$work/log.mode") == 600 ]] || fail "attach-config sin modo 0600"

# 2. Ya adjunto: no se vuelve a hacer attach.
run_case true "" "" 0 || fail "flujo adjunto abortó"
grep -q '^attach' "$work/log" && fail "attach repetido estando adjunto"

# 3. Livepatch falla: se continúa, se habilita usg y se instala el paquete usg.
run_case true "livepatch" "" 0 || fail "fallo de livepatch abortó el setup"
grep -q '^enable usg' "$work/log" || fail "usg no habilitado tras fallo de livepatch"
grep -q '^apt-get install .* usg$' "$work/log" || fail "paquete usg no instalado"
grep -q 'config set apt_news=false' "$work/log" || fail "no se llegó al final de Pro"

# 4. usg falla: no se instala el paquete y no aborta.
run_case true "usg" "" 0 || fail "fallo de usg abortó el setup"
grep -q '^apt-get install .* usg$' "$work/log" && fail "paquete usg instalado sin servicio"

# 5. WSL: livepatch no se intenta.
run_case true "" "" 1 || fail "flujo WSL abortó"
grep -q '^enable livepatch' "$work/log" && fail "livepatch intentado en WSL"

# 6. Sin attach, sin token y sin TTY: aborta.
run_case false "" "" 0 && fail "debió abortar sin token ni TTY"

echo "PASS: attach por estado JSON, token fuera de argv, servicios opcionales no fatales, usg instalado"
