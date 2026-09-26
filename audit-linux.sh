#!/usr/bin/env bash
# Read-only security audit for Ubuntu/Debian/WSL2 hosts.
# It never installs, changes or deletes anything: it only reads state and
# writes one Markdown report. Identifying data is redacted by default.
# Messages print literal "~/" paths on purpose.
# shellcheck disable=SC2088

set -uo pipefail

REDACT=1
OUT=""
CRIT=0
WARN=0
REPORT=""

usage() {
    cat <<'EOF'
Usage: ./audit-linux.sh [--output FILE] [--no-redact]

Read-only audit: accounts, updates, SSH, listening ports, firewall, IPv6,
Docker, Ollama, credentials on disk, Claude Code/Codex config and persistence.

  --output FILE   report path (default: ./auditoria-linux-<host>-<date>.md)
  --no-redact     keep IPs, MACs, hostname, user and e-mails in the report
  -h, --help      show this help

Run it as your normal user first. Running it again with sudo adds the checks
that need root (sshd -T, ufw/nft rules, sudoers); it still changes nothing.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 2; }; OUT="$2"; shift 2 ;;
        --output=*) OUT="${1#*=}"; shift ;;
        --no-redact) REDACT=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

have() { command -v "$1" >/dev/null 2>&1; }
add()  { REPORT+="$*"$'\n'; }
section() { add ""; add "## $*"; add ""; }
ok()   { add "- [OK] $*"; }
info() { add "- [INFO] $*"; }
warn() { WARN=$((WARN + 1)); add "- [AVISO] $*"; }
crit() { CRIT=$((CRIT + 1)); add "- [CRÍTICO] $*"; }

# Path with $HOME shown as ~ (bash would expand a literal ~ in ${var/pat/rep}).
short() {
    local p=$1
    [[ "$p" == "$HOME"/* ]] && p="~${p#"$HOME"}"
    printf '%s' "$p"
}

# Octal permission bits of a path, or empty if it does not exist.
perm_of() { stat -c '%a' -- "$1" 2>/dev/null; }

# True when group or others have any permission on the path.
too_open() {
    local p
    p=$(perm_of "$1") || return 1
    [[ -n "$p" ]] || return 1
    (( (8#$p & 8#077) != 0 ))
}

IS_ROOT=0; [[ $(id -u) -eq 0 ]] && IS_ROOT=1
IS_WSL=0; grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1
IS_CONTAINER=0
if have systemd-detect-virt && systemd-detect-virt -cq 2>/dev/null; then IS_CONTAINER=1; fi
[[ -f /.dockerenv ]] && IS_CONTAINER=1
HOST=$(hostname 2>/dev/null || echo unknown)
NOW=$(date +%Y%m%d-%H%M)
[[ -n "$OUT" ]] || OUT="./auditoria-linux-${HOST}-${NOW}.md"

check_system() {
    section "Sistema"
    local pretty="desconocido"
    # shellcheck disable=SC1091
    [[ -r /etc/os-release ]] && pretty=$(. /etc/os-release && echo "${PRETTY_NAME:-desconocido}")
    info "SO: $pretty · kernel $(uname -r) · arquitectura $(uname -m)"
    info "WSL2: $([[ $IS_WSL -eq 1 ]] && echo sí || echo no) · contenedor: $([[ $IS_CONTAINER -eq 1 ]] && echo sí || echo no) · ejecutado como root: $([[ $IS_ROOT -eq 1 ]] && echo sí || echo no)"
    info "Arranque: $(uptime -s 2>/dev/null || echo desconocido)"
}

check_updates() {
    section "Actualizaciones"
    if ! have apt; then info "apt no disponible; revisa el gestor de paquetes manualmente"; return; fi
    local cache age_days upg sec
    cache=/var/cache/apt/pkgcache.bin
    if [[ -f $cache ]]; then
        age_days=$(( ( $(date +%s) - $(stat -c %Y "$cache") ) / 86400 ))
        if (( age_days > 7 )); then
            warn "Índice apt con $age_days días: el recuento de pendientes puede estar desfasado (ejecuta 'sudo apt update' y repite)"
        else
            info "Índice apt actualizado hace $age_days días"
        fi
    fi
    upg=$(apt list --upgradable 2>/dev/null | grep -c 'upgradable from' || true)
    sec=$(apt list --upgradable 2>/dev/null | grep -c -- '-security' || true)
    if (( sec > 0 )); then
        crit "$sec paquetes con actualización de seguridad pendiente ($upg pendientes en total)"
    elif (( upg > 0 )); then
        warn "$upg paquetes con actualización pendiente (ninguna marcada como security)"
    else
        ok "Sin paquetes pendientes según el índice local"
    fi
    [[ -f /var/run/reboot-required ]] && warn "Reinicio pendiente para aplicar actualizaciones (/var/run/reboot-required)"
    if dpkg -s unattended-upgrades >/dev/null 2>&1 &&
        apt-config dump 2>/dev/null | grep -q 'APT::Periodic::Unattended-Upgrade "1"'; then
        ok "unattended-upgrades instalado y activo"
    else
        warn "Actualizaciones de seguridad automáticas no activas (unattended-upgrades)"
    fi
}

check_accounts() {
    section "Cuentas y privilegios"
    local uid0 humans sudoers docker_members
    uid0=$(awk -F: '$3==0 && $1!="root"{print $1}' /etc/passwd | paste -sd, -)
    if [[ -n "$uid0" ]]; then crit "Cuentas con UID 0 distintas de root: $uid0"; else ok "Solo root tiene UID 0"; fi
    humans=$(awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false)$/ {print $1}' /etc/passwd | paste -sd, -)
    info "Cuentas humanas con shell: ${humans:-ninguna}"
    sudoers=$(getent group sudo admin wheel 2>/dev/null | awk -F: '$4!=""{print $4}' | paste -sd, -)
    info "Miembros de sudo/admin/wheel: ${sudoers:-ninguno}"
    docker_members=$(getent group docker 2>/dev/null | awk -F: '{print $4}')
    [[ -n "$docker_members" ]] && warn "Grupo docker (equivale a root sin contraseña): $docker_members"
    if [[ $IS_ROOT -eq 1 ]]; then
        local nopw
        nopw=$(grep -rhsE '^[^#].*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | wc -l)
        if (( nopw > 0 )); then warn "$nopw reglas sudo NOPASSWD en /etc/sudoers*"; else ok "Sin reglas sudo NOPASSWD"; fi
    elif sudo -n true 2>/dev/null; then
        warn "El usuario actual tiene sudo sin contraseña (NOPASSWD)"
    else
        info "sudoers no legible sin root; repite con sudo para revisar NOPASSWD"
    fi
}

check_ssh() {
    section "SSH"
    local listening=0 cfg=""
    if ss -Htln 2>/dev/null | awk '{print $4}' | grep -qE ':22$'; then listening=1; fi
    if pgrep -x sshd >/dev/null 2>&1 || [[ $listening -eq 1 ]]; then
        if cfg=$(sshd -T 2>/dev/null) && [[ -n "$cfg" ]]; then
            :
        else
            # Without root, approximate sshd's first-match rule: drop-ins are included first on Ubuntu.
            cfg=$(cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null |
                grep -iE '^\s*(passwordauthentication|permitrootlogin|kbdinteractiveauthentication|pubkeyauthentication)\s' |
                awk '{k=tolower($1); if (!(k in s)) {s[k]=1; print k, $2}}')
            info "Configuración sshd leída de ficheros (aproximación sin root)"
        fi
        local pa prl
        pa=$(awk 'tolower($1)=="passwordauthentication"{print tolower($2); exit}' <<<"$cfg")
        prl=$(awk 'tolower($1)=="permitrootlogin"{print tolower($2); exit}' <<<"$cfg")
        case "${prl:-prohibit-password}" in
            yes) crit "sshd: PermitRootLogin yes" ;;
            *) ok "sshd: PermitRootLogin ${prl:-prohibit-password (por defecto)}" ;;
        esac
        if [[ "${pa:-yes}" == yes ]]; then
            warn "sshd: PasswordAuthentication ${pa:-yes (por defecto)}; usa solo claves"
        else
            ok "sshd: PasswordAuthentication no"
        fi
        if systemctl is-active --quiet fail2ban 2>/dev/null; then ok "fail2ban activo"; else info "fail2ban no activo"; fi
    else
        ok "Servidor SSH no activo"
    fi

    local d="$HOME/.ssh" f
    [[ -d "$d" ]] || { info "Sin ~/.ssh"; return; }
    too_open "$d" && warn "~/.ssh con permisos $(perm_of "$d") (esperado 700)"
    for f in "$d"/id_* "$d"/*.pem; do
        [[ -f "$f" && "$f" != *.pub ]] || continue
        too_open "$f" && crit "Clave privada $(short "$f") con permisos $(perm_of "$f") (esperado 600)"
        if have ssh-keygen && ssh-keygen -y -P '' -f "$f" </dev/null >/dev/null 2>&1; then
            warn "Clave privada $(short "$f") sin passphrase"
        else
            ok "Clave privada $(short "$f") protegida con passphrase o no legible sin ella"
        fi
    done
    if [[ -f "$d/authorized_keys" ]] && have ssh-keygen; then
        local n
        n=$(grep -cvE '^\s*(#|$)' "$d/authorized_keys" || true)
        info "authorized_keys: $n claves autorizadas para entrar en esta cuenta (verifica cada huella):"
        while read -r bits fp _; do
            [[ -n "${fp:-}" ]] && add "    - $bits $fp"
        done < <(ssh-keygen -lf "$d/authorized_keys" 2>/dev/null)
    fi
}

port_label() {
    case "$1" in
        22) echo "SSH" ;; 139|445) echo "SMB" ;; 631) echo "CUPS" ;; 2375) echo "Docker API sin TLS" ;;
        2376) echo "Docker API TLS" ;; 3000) echo "web dev/Grafana" ;; 3306) echo "MySQL" ;;
        3389) echo "RDP" ;; 5000) echo "web dev/registry" ;; 5432) echo "PostgreSQL" ;;
        5900|5901) echo "VNC" ;; 6379) echo "Redis" ;; 7860) echo "Gradio" ;; 8080) echo "Open WebUI/web" ;;
        8188) echo "ComfyUI" ;; 8888) echo "Jupyter" ;; 9090) echo "Prometheus/Cockpit" ;;
        9200) echo "Elasticsearch" ;; 11434) echo "Ollama API" ;; 1234) echo "LM Studio" ;;
        27017) echo "MongoDB" ;; *) echo "" ;;
    esac
}

check_network() {
    section "Puertos a la escucha"
    if ! have ss; then info "ss no disponible"; return; fi
    local global6 line proto addr port proc label scope any_wild=0
    global6=$(ip -6 addr show scope global 2>/dev/null | grep -c 'inet6' || true)
    while read -r line; do
        proto=$(awk '{print $1}' <<<"$line")
        addr=$(awk '{print $5}' <<<"$line")
        proc=$(grep -oE 'users:\(\("[^"]+"' <<<"$line" | sed 's/users:(("//')
        port=${addr##*:}
        addr=${addr%:*}
        label=$(port_label "$port")
        case "$addr" in
            127.*|'[::1]'|'[::ffff:127.'*|localhost) scope=loopback ;;
            0.0.0.0|'*'|'[::]'|'[::ffff:0.0.0.0]') scope=todas; any_wild=1 ;;
            *%lo) scope=loopback ;;
            *) scope=interfaz ;;
        esac
        local desc="$proto $addr:$port ${proc:+($proc) }${label:+[$label]}"
        if [[ $scope == loopback ]]; then
            ok "$desc solo local"
        elif [[ "$port" == 2375 ]]; then
            crit "$desc: API de Docker sin TLS expuesta = root remoto"
        elif [[ -n "$label" && "$port" != 22 ]]; then
            if [[ "$addr" == '[::]' || "$addr" == '*' ]] && (( global6 > 0 )); then
                crit "$desc escucha en todas las interfaces y el host tiene IPv6 global: potencialmente alcanzable desde Internet si el router no filtra entrantes"
            else
                warn "$desc escucha en $scope; limita a 127.0.0.1 o filtra en el cortafuegos"
            fi
        else
            info "$desc escucha en $scope"
        fi
    done < <(ss -Htulpn 2>/dev/null | awk '$2=="LISTEN" || $1=="udp"' | grep -vE ':(53|5353|68|546)\s' )
    [[ $any_wild -eq 1 ]] && info "Hay servicios en 0.0.0.0/[::]: su exposición real depende del cortafuegos y del router"

    section "Cortafuegos e IPv6"
    local ufw_on=0
    if [[ -r /etc/ufw/ufw.conf ]] && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then ufw_on=1; fi
    if [[ $IS_ROOT -eq 1 ]] && have ufw; then
        ufw status 2>/dev/null | grep -q 'Status: active' && ufw_on=1
    fi
    if [[ $ufw_on -eq 1 ]]; then
        ok "UFW activado"
    elif [[ $IS_ROOT -eq 1 ]] && have nft && [[ $(nft list ruleset 2>/dev/null | grep -c 'hook input') -gt 0 ]]; then
        ok "nftables con cadena input"
    elif [[ $IS_WSL -eq 1 ]]; then
        info "WSL2: el filtrado lo hace el cortafuegos de Windows (revisa Audit-Windows.ps1)"
    else
        warn "No consta cortafuegos activo (UFW desactivado; repite con sudo para ver nftables)"
    fi
    if (( global6 > 0 )); then
        info "$global6 direcciones IPv6 globales"
        if ip -6 addr show scope global 2>/dev/null | grep 'inet6' | grep -v -e temporary -e mngtmpaddr |
            grep -qiE 'inet6 [0-9a-f:]+[0-9a-f]{0,2}ff:fe[0-9a-f]{2}:[0-9a-f]{1,4}/'; then
            warn "IPv6 global con identificador EUI-64 (derivado de la MAC): estable y rastreable; valora use_tempaddr=2 en clientes"
        fi
    else
        info "Sin IPv6 global"
    fi
}

check_docker() {
    section "Docker"
    if ! have docker; then info "Docker no instalado"; return; fi
    if [[ -r /etc/docker/daemon.json ]] && grep -q 'tcp://' /etc/docker/daemon.json; then
        crit "daemon.json declara un socket TCP para la API de Docker"
    fi
    if systemctl cat docker 2>/dev/null | grep -qE -- '-H[ =]*tcp://'; then
        crit "El servicio docker arranca con -H tcp://"
    fi
    local ps_out pub
    if ! ps_out=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null); then
        info "Sin acceso al daemon como este usuario; repite con sudo para listar contenedores"
        return
    fi
    info "Contenedores en ejecución: $(grep -c . <<<"$ps_out" || true)"
    pub=$(grep -E '0\.0\.0\.0:|\[::\]:|:::' <<<"$ps_out" || true)
    if [[ -n "$pub" ]]; then
        while read -r l; do warn "Contenedor publica puerto en todas las interfaces (Docker salta UFW): $l"; done <<<"$pub"
    else
        ok "Ningún contenedor publica puertos en todas las interfaces"
    fi
}

check_ollama() {
    section "Ollama / IA local"
    if ! have ollama && ! systemctl cat ollama >/dev/null 2>&1; then info "Ollama no detectado"; return; fi
    local env host origins
    env=$(systemctl show ollama --property=Environment 2>/dev/null)
    host=$(grep -oE 'OLLAMA_HOST=[^ ]+' <<<"$env${OLLAMA_HOST:+ OLLAMA_HOST=$OLLAMA_HOST}" | tail -1 | cut -d= -f2-)
    origins=$(grep -oE 'OLLAMA_ORIGINS=[^ ]+' <<<"$env" | tail -1 | cut -d= -f2-)
    case "${host:-127.0.0.1}" in
        127.*|localhost*|'[::1]'*) ok "OLLAMA_HOST=${host:-127.0.0.1:11434 (por defecto)}: solo local" ;;
        *) warn "OLLAMA_HOST=$host: la API de Ollama no tiene autenticación; exponla solo tras cortafuegos o proxy con auth" ;;
    esac
    [[ "$origins" == '*' ]] && warn "OLLAMA_ORIGINS='*': cualquier web visitada puede llamar a la API local"
    if have curl && curl -fsS --max-time 2 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
        info "API de Ollama responde en 127.0.0.1:11434"
    fi
}

check_credentials() {
    section "Credenciales en disco"
    local f
    [[ -f "$HOME/.git-credentials" ]] && crit "~/.git-credentials guarda tokens Git en texto plano"
    if [[ "$(git config --global credential.helper 2>/dev/null)" == store ]]; then
        crit "git credential.helper=store (texto plano); usa libsecret, gh auth o Git Credential Manager"
    fi
    for f in .netrc .aws/credentials .config/gh/hosts.yml .docker/config.json .npmrc .pypirc \
        .config/rclone/rclone.conf .cache/huggingface/token .huggingface/token .kube/config \
        .claude.json .claude/.credentials.json .codex/auth.json .config/gcloud/credentials.db; do
        [[ -f "$HOME/$f" ]] || continue
        if too_open "$HOME/$f"; then
            warn "~/$f legible por grupo/otros (permisos $(perm_of "$HOME/$f"); esperado 600)"
        else
            ok "~/$f con permisos $(perm_of "$HOME/$f")"
        fi
    done
    if [[ -f "$HOME/.config/gh/hosts.yml" ]] && grep -q 'oauth_token:' "$HOME/.config/gh/hosts.yml"; then
        warn "gh guarda el token en ~/.config/gh/hosts.yml en claro (sin keyring)"
    fi
    if [[ -f "$HOME/.docker/config.json" ]] && grep -q '"auth"' "$HOME/.docker/config.json"; then
        warn "~/.docker/config.json contiene credenciales de registro en base64 (sin credsStore)"
    fi
    local rc hits=0
    for rc in .bashrc .zshrc .profile .bash_profile .zprofile .config/fish/config.fish; do
        [[ -f "$HOME/$rc" ]] || continue
        if grep -qE '^\s*(export\s+)?[A-Z_]*(API_KEY|TOKEN|SECRET|PASSWORD)[A-Z_]*=\S' "$HOME/$rc"; then
            warn "~/$rc exporta variables con API_KEY/TOKEN/SECRET/PASSWORD en claro"
        fi
    done
    for rc in .bash_history .zsh_history .local/share/fish/fish_history; do
        [[ -f "$HOME/$rc" ]] || continue
        hits=$(grep -ciE '(api[_-]?key|token|secret|passw(or)?d)=|sk-ant-|ghp_|github_pat_|hf_[a-z0-9]{20}|AKIA[0-9A-Z]{16}' "$HOME/$rc" || true)
        (( hits > 0 )) && warn "~/$rc: $hits líneas con posible secreto (no se muestran; revísalas y bórralas)"
    done
    local envs
    envs=$(find "$HOME" -maxdepth 4 \( -name node_modules -o -name .git -o -name .cache -o -name .local \) -prune -o \
        -type f \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name '*.kdbx' \) \
        -print 2>/dev/null | head -50)
    if [[ -n "$envs" ]]; then
        info "Ficheros sensibles por nombre (máx. 50; revisa permisos y que no estén en repos públicos):"
        while read -r f; do add "    - $(short "$f") ($(perm_of "$f"))"; done <<<"$envs"
    fi
}

json_get() {
    # json_get FILE PYTHON_EXPR -> prints the expression evaluated over the parsed JSON as d.
    have python3 || return 1
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
r = eval(sys.argv[2], {"d": d})
if isinstance(r, (list, tuple)):
    print("\n".join(str(x) for x in r))
elif r is not None:
    print(r)
PY
}

check_agents() {
    section "Claude Code y otros agentes"
    if have claude; then info "Claude Code: $(claude --version 2>/dev/null | head -1)"; else info "Claude Code no está en PATH"; fi
    local s="$HOME/.claude/settings.json" mode allow hooks envk
    if [[ -f "$s" ]]; then
        mode=$(json_get "$s" 'd.get("permissions",{}).get("defaultMode")')
        [[ "$mode" == bypassPermissions ]] && crit "settings.json: defaultMode=bypassPermissions (sin confirmaciones)"
        [[ -n "$mode" && "$mode" != bypassPermissions ]] && info "settings.json: defaultMode=$mode"
        allow=$(json_get "$s" '[a for a in d.get("permissions",{}).get("allow",[]) if a in ("Bash","Bash(*)","Bash(*:*)") or a.startswith(("Bash(sudo","Bash(rm","Bash(curl"))]')
        [[ -n "$allow" ]] && warn "settings.json: permisos amplios pre-aprobados: $(paste -sd, - <<<"$allow")"
        hooks=$(json_get "$s" 'list(d.get("hooks",{}).keys())')
        [[ -n "$hooks" ]] && info "Hooks configurados (ejecutan comandos automáticamente): $(paste -sd, - <<<"$hooks")"
        envk=$(json_get "$s" '[k for k in d.get("env",{}) if any(t in k.upper() for t in ("KEY","TOKEN","SECRET"))]')
        [[ -n "$envk" ]] && warn "settings.json guarda secretos en env: $(paste -sd, - <<<"$envk")"
        json_get "$s" 'd.get("skipDangerousModePermissionPrompt")' | grep -qi true &&
            warn "settings.json: skipDangerousModePermissionPrompt=true"
    fi
    local cj="$HOME/.claude.json" mcp
    if [[ -f "$cj" ]]; then
        mcp=$(json_get "$cj" 'sorted(set(list(d.get("mcpServers",{}).keys()) + [k for p in d.get("projects",{}).values() for k in p.get("mcpServers",{})]))')
        if [[ -n "$mcp" ]]; then
            info "Servidores MCP locales (cada uno ejecuta código con tus permisos; verifica origen): $(paste -sd, - <<<"$mcp")"
        else
            ok "Sin servidores MCP locales en ~/.claude.json"
        fi
    fi
    local rc
    for rc in .bashrc .zshrc .bash_aliases; do
        [[ -f "$HOME/$rc" ]] && grep -q -- '--dangerously-skip-permissions' "$HOME/$rc" &&
            warn "~/$rc contiene alias/uso de --dangerously-skip-permissions"
    done
    local codex="$HOME/.codex/config.toml"
    if [[ -f "$codex" ]]; then
        grep -qE 'approval_policy\s*=\s*"never"' "$codex" && warn "Codex: approval_policy=\"never\""
        grep -qE 'sandbox_mode\s*=\s*"danger-full-access"' "$codex" && warn "Codex: sandbox_mode=\"danger-full-access\""
    fi
}

check_hardening() {
    section "Endurecimiento del sistema"
    if [[ $IS_WSL -eq 1 || $IS_CONTAINER -eq 1 ]]; then
        info "WSL2/contenedor: cifrado de disco y Secure Boot dependen del anfitrión"
    else
        if lsblk -rno TYPE,FSTYPE 2>/dev/null | grep -qE 'crypt|crypto_LUKS'; then
            ok "Hay volúmenes cifrados (LUKS)"
        else
            warn "No consta cifrado de disco (LUKS); un robo físico expone los datos"
        fi
        if have mokutil; then
            case "$(mokutil --sb-state 2>/dev/null)" in
                *enabled*) ok "Secure Boot activado" ;;
                *disabled*) warn "Secure Boot desactivado" ;;
                *) info "Estado de Secure Boot no disponible" ;;
            esac
        fi
    fi
    if [[ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" == Y ]]; then ok "AppArmor activo"; else info "AppArmor no activo"; fi
    if [[ $IS_WSL -eq 1 && -r /etc/wsl.conf ]]; then
        grep -qiE '^\s*enabled\s*=\s*false' /etc/wsl.conf || info "WSL: interop activo (Linux puede lanzar ejecutables de Windows)"
    fi
}

check_persistence() {
    section "Persistencia y tareas programadas"
    local n
    n=$(crontab -l 2>/dev/null | grep -cvE '^\s*(#|$)' || true)
    info "crontab de usuario: $n entradas"
    info "/etc/cron.d: $(find /etc/cron.d -maxdepth 1 -type f ! -name .placeholder -printf '%f\n' 2>/dev/null | paste -sd, -)"
    if [[ -d "$HOME/.config/autostart" ]]; then
        info "Autoarranque de escritorio: $(find "$HOME/.config/autostart" -name '*.desktop' -printf '%f\n' 2>/dev/null | paste -sd, -)"
    fi
    if have systemctl; then
        local user_units
        user_units=$(systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | paste -sd, -)
        [[ -n "$user_units" ]] && info "Servicios systemd de usuario habilitados: $user_units"
        local failed
        failed=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $2}' | paste -sd, -)
        [[ -n "$failed" ]] && warn "Unidades systemd fallidas: $failed"
    fi
}

redact() {
    if [[ $REDACT -eq 0 ]] || ! have perl; then cat; return; fi
    H="$HOST" U="${USER:-$(id -un)}" perl -pe '
        BEGIN { $h = $ENV{H}; $u = $ENV{U}; $u = "" if $u eq "root"; }
        s/\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b/<mac>/gi;
        s/\b(?!127\.0\.0\.1\b)(?!0\.0\.0\.0\b)(?:\d{1,3}\.){3}\d{1,3}\b/<ipv4>/g;
        s/(?<![0-9a-f:])(?:[0-9a-f]{1,4}:){4,7}[0-9a-f]{1,4}(?![0-9a-f:])/<ipv6>/gi;
        s/(?<![0-9a-f:])[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*::(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*)?(?![0-9a-f:])/<ipv6>/gi;
        s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g;
        s/\Q$h\E/<host>/g if length $h > 2;
        s/\b\Q$u\E\b/<user>/g if length $u > 2;
    '
}

main() {
    add "# Auditoría de seguridad Linux (solo lectura)"
    add ""
    add "Fecha: $(date -Iseconds) · redacción de datos identificativos: $([[ $REDACT -eq 1 ]] && echo activada || echo desactivada)"
    check_system
    check_updates
    check_accounts
    check_ssh
    check_network
    check_docker
    check_ollama
    check_credentials
    check_agents
    check_hardening
    check_persistence
    add ""
    add "## Resumen"
    add ""
    add "- CRÍTICO: $CRIT"
    add "- AVISO: $WARN"
    add ""
    add "No se ha modificado el sistema."
    ( umask 077; printf '%s' "$REPORT" | redact > "$OUT" ) || { echo "No se pudo escribir $OUT" >&2; exit 1; }
    printf '%s' "$REPORT" | redact
    printf '\n[+] Informe guardado en %s (permisos 600)\n' "$OUT" >&2
}

main
