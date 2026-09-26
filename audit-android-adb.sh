#!/usr/bin/env bash
# Read-only security audit of an Android phone over ADB, run from a PC/Mac.
# It only issues read commands (getprop, settings get, dumpsys, pm list,
# appops query, netstat, ip). It never installs, grants or changes anything.

set -uo pipefail

REDACT=1
OUT=""
SERIAL=""
CRIT=0
WARN=0
REPORT=""

usage() {
    cat <<'EOF'
Usage: ./audit-android-adb.sh [--serial SERIAL] [--output FILE] [--no-redact]

Requires adb (Android Platform Tools) and USB debugging enabled on the phone.
Disable USB/wireless debugging again when the audit finishes.

  --serial SERIAL  device to audit when several are connected
  --output FILE    report path (default: ./auditoria-android-<model>-<date>.md)
  --no-redact      keep serial, IPs, MACs and e-mails in the report
  -h, --help       show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --serial) [[ $# -ge 2 ]] || { echo "--serial requires a value" >&2; exit 2; }; SERIAL="$2"; shift 2 ;;
        --output) [[ $# -ge 2 ]] || { echo "--output requires a path" >&2; exit 2; }; OUT="$2"; shift 2 ;;
        --no-redact) REDACT=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

add()  { REPORT+="$*"$'\n'; }
section() { add ""; add "## $*"; add ""; }
ok()   { add "- [OK] $*"; }
info() { add "- [INFO] $*"; }
warn() { WARN=$((WARN + 1)); add "- [AVISO] $*"; }
crit() { CRIT=$((CRIT + 1)); add "- [CRÍTICO] $*"; }

command -v adb >/dev/null 2>&1 || { echo "adb no encontrado: instala Android Platform Tools" >&2; exit 1; }

if [[ -z "$SERIAL" ]]; then
    mapfile -t devices < <(adb devices | awk 'NR>1 && $2=="device"{print $1}')
    case ${#devices[@]} in
        0) echo "No hay dispositivos autorizados (revisa el cable y acepta la huella RSA en el móvil)" >&2; exit 1 ;;
        1) SERIAL="${devices[0]}" ;;
        *) echo "Hay varios dispositivos; elige uno con --serial: ${devices[*]}" >&2; exit 1 ;;
    esac
fi

# Runs one read-only shell command on the device; output without CRs.
dev() { adb -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r'; }
prop() { dev getprop "$1"; }
setting() { local v; v=$(dev settings get "$1" "$2"); [[ "$v" == null ]] && v=""; printf '%s' "$v"; }

MODEL=$(prop ro.product.model)
NOW=$(date +%Y%m%d-%H%M)
[[ -n "$OUT" ]] || OUT="./auditoria-android-${MODEL// /_}-${NOW}.md"

days_since() {
    local then_s
    then_s=$(date -d "$1" +%s 2>/dev/null) ||
        then_s=$(python3 -c 'import sys,datetime;print(int(datetime.datetime.strptime(sys.argv[1],"%Y-%m-%d").timestamp()))' "$1" 2>/dev/null) ||
        return 1
    echo $(( ( $(date +%s) - then_s ) / 86400 ))
}

check_system() {
    section "Dispositivo y parches"
    info "Modelo: $(prop ro.product.manufacturer) $MODEL · Android $(prop ro.build.version.release) (SDK $(prop ro.build.version.sdk))"
    local patch age
    patch=$(prop ro.build.version.security_patch)
    if [[ -n "$patch" ]] && age=$(days_since "$patch"); then
        if (( age > 180 )); then crit "Parche de seguridad $patch ($age días): sin soporte o sin actualizar"
        elif (( age > 90 )); then warn "Parche de seguridad $patch ($age días); busca actualizaciones del sistema"
        else ok "Parche de seguridad $patch ($age días)"; fi
    else
        info "Parche de seguridad: ${patch:-desconocido}"
    fi
    local mainline
    mainline=$(dev pm list packages --show-versioncode com.google.android.modulemetadata | grep -oE 'versionCode:[0-9]+' | cut -d: -f2)
    [[ -n "$mainline" ]] && info "Google Play system update (mainline): versionCode $mainline"
}

check_integrity() {
    section "Integridad de arranque y cifrado"
    local vbs locked tags debuggable crypto
    vbs=$(prop ro.boot.verifiedbootstate)
    locked=$(prop ro.boot.flash.locked)
    tags=$(prop ro.build.tags)
    debuggable=$(prop ro.debuggable)
    case "$vbs" in
        green) ok "Verified Boot: green (sistema original verificado)" ;;
        yellow) warn "Verified Boot: yellow (clave de firma propia)" ;;
        orange) warn "Verified Boot: orange (bootloader desbloqueado; el sistema no se verifica)" ;;
        *) info "Verified Boot: ${vbs:-desconocido}" ;;
    esac
    [[ "$locked" == 0 ]] && warn "Bootloader desbloqueado (ro.boot.flash.locked=0)"
    [[ -n "$tags" && "$tags" != release-keys ]] && warn "Build firmada con $tags"
    [[ "$debuggable" == 1 ]] && crit "Build depurable (ro.debuggable=1): no es una build de usuario"
    if dev 'command -v su' | grep -q .; then warn "Binario su presente (root)"; fi
    crypto=$(prop ro.crypto.state)
    if [[ "$crypto" == encrypted ]]; then ok "Almacenamiento cifrado ($(prop ro.crypto.type))"; else warn "Cifrado: ${crypto:-desconocido}"; fi
    local cred
    cred=$(dev dumpsys lock_settings | grep -m1 -oiE 'CredentialType: *[A-Z_]+' | awk '{print $NF}')
    case "$cred" in
        NONE) crit "Sin bloqueo de pantalla con credencial" ;;
        PIN|PASSWORD|PATTERN|PASSWORD_OR_PIN) ok "Bloqueo de pantalla: $cred" ;;
        *) info "Tipo de bloqueo de pantalla no legible; compruébalo en Ajustes" ;;
    esac
}

check_debug() {
    section "Depuración y fuentes de instalación"
    [[ "$(setting global development_settings_enabled)" == 1 ]] && info "Opciones de desarrollador activas"
    [[ "$(setting global adb_enabled)" == 1 ]] && warn "Depuración USB activa: desactívala al terminar esta auditoría"
    [[ "$(setting global adb_wifi_enabled)" == 1 ]] && warn "Depuración inalámbrica activa"
    case "$(setting global package_verifier_enable)" in
        0) warn "Google Play Protect: verificación de apps desactivada" ;;
        1) ok "Google Play Protect: verificación de apps activa" ;;
        *) info "Estado de Play Protect no expuesto por settings; compruébalo en Play Store" ;;
    esac
    local installers
    installers=$(dev cmd appops query-op --user 0 REQUEST_INSTALL_PACKAGES allow)
    if [[ -n "$installers" ]]; then
        warn "Apps autorizadas a instalar otras apps (fuentes desconocidas):"
        while read -r p; do [[ -n "$p" ]] && add "    - $p"; done <<<"$installers"
    else
        ok "Ninguna app autorizada a instalar apps de fuentes desconocidas"
    fi
}

split_components() { tr ':' '\n' | sed 's#/.*##' | sort -u | grep -v '^$'; }

check_surveillance() {
    section "Permisos de vigilancia (indicadores de stalkerware)"
    local acc nl p
    acc=$(setting secure enabled_accessibility_services)
    if [[ -n "$acc" ]]; then
        warn "Servicios de accesibilidad activos (leen y controlan la pantalla); verifica cada uno:"
        while read -r p; do add "    - $p"; done < <(split_components <<<"$acc")
    else
        ok "Sin servicios de accesibilidad activos"
    fi
    nl=$(setting secure enabled_notification_listeners)
    if [[ -n "$nl" ]]; then
        info "Apps que leen todas las notificaciones (incluidos códigos 2FA por SMS):"
        while read -r p; do add "    - $p"; done < <(split_components <<<"$nl")
    fi
    local dp admins owner
    dp=$(dev dumpsys device_policy)
    admins=$(grep -oE 'admin=ComponentInfo\{[^/]+' <<<"$dp" | sed 's/.*{//' | sort -u)
    if [[ -n "$admins" ]]; then
        while read -r p; do
            if [[ "$p" == com.google.android.gms ]]; then ok "Administrador de dispositivo: $p (Encontrar mi dispositivo)"
            else warn "Administrador de dispositivo: $p (puede bloquear/borrar el móvil; verifica que lo reconoces)"; fi
        done <<<"$admins"
    else
        ok "Sin administradores de dispositivo"
    fi
    owner=$(grep -iE 'Device Owner|Profile Owner' -A2 <<<"$dp" | grep -oE 'package=[^ ,]+' | sort -u | paste -sd, -)
    [[ -n "$owner" ]] && warn "Propietario de dispositivo/perfil gestionado (MDM): $owner"
    info "Usuarios/perfiles: $(dev pm list users | grep -c 'UserInfo{' || true) (incluye perfil de trabajo o espacio privado si existen)"
}

check_apps() {
    section "Apps de terceros"
    local list total side
    list=$(dev pm list packages -3 -i)
    total=$(grep -c '^package:' <<<"$list" || true)
    info "Apps de terceros instaladas: $total"
    side=$(awk '{
            pkg=$1; sub(/^package:/,"",pkg); inst=$2; sub(/^installer=/,"",inst)
            if (inst !~ /^(com\.android\.vending|com\.sec\.android\.app\.samsungapps|com\.xiaomi\.market|com\.huawei\.appmarket|org\.fdroid\.fdroid|com\.amazon\.venezia|com\.google\.android\.apps\.work\.clouddpc)$/)
                print pkg " (instalador: " (inst == "" || inst == "null" ? "desconocido" : inst) ")"
        }' <<<"$list")
    if [[ -n "$side" ]]; then
        info "Apps instaladas fuera de tiendas (sideload/ADB); confirma el origen de cada una:"
        while read -r p; do add "    - $p"; done <<<"$side"
    else
        ok "Todas las apps de terceros proceden de tiendas"
    fi
}

check_network() {
    section "Red y servicios expuestos"
    local dns spec vpn
    dns=$(setting global private_dns_mode)
    spec=$(setting global private_dns_specifier)
    case "$dns" in
        hostname) ok "DNS privado: $spec" ;;
        off) info "DNS privado desactivado" ;;
        *) info "DNS privado: ${dns:-automático}" ;;
    esac
    vpn=$(setting secure always_on_vpn_app)
    [[ -n "$vpn" ]] && info "VPN siempre activa: $vpn (bloqueo sin VPN: $(setting secure always_on_vpn_lockdown))"
    local listen global6
    global6=$(dev ip -6 addr show scope global | grep -c inet6 || true)
    listen=$(dev netstat -tln | awk '$NF=="LISTEN"{print $4}' | sort -u)
    if [[ -z "$listen" ]]; then
        info "No se pudieron leer los puertos a la escucha (Android restringe /proc/net)"
    fi
    local addr port
    while read -r addr; do
        [[ -n "$addr" ]] || continue
        port=${addr##*:}
        case "$addr" in
            127.*|::1:*|::ffff:127.*) ok "Puerto $addr solo local" ;;
            0.0.0.0:*|:::*|'*:'*)
                if [[ "$port" == 11434 || "$port" == 8022 || "$port" == 8080 || "$port" == 5555 ]]; then
                    if (( global6 > 0 )); then crit "Puerto $port escucha en todas las interfaces con IPv6 global: potencialmente alcanzable desde Internet"
                    else warn "Puerto $port escucha en todas las interfaces (visible en la Wi-Fi local)"; fi
                else
                    info "Puerto $port escucha en todas las interfaces"
                fi ;;
            *) info "Puerto $addr escucha en una interfaz concreta" ;;
        esac
    done <<<"$listen"
    (( global6 > 0 )) && info "$global6 direcciones IPv6 globales en el móvil"
}

redact() {
    if [[ $REDACT -eq 0 ]] || ! command -v perl >/dev/null 2>&1; then cat; return; fi
    SER="$SERIAL" perl -pe '
        s/\Q$ENV{SER}\E/<serial>/g if length $ENV{SER} > 3;
        s/\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b/<mac>/gi;
        s/\b(?!127\.0\.0\.1\b)(?!0\.0\.0\.0\b)(?:\d{1,3}\.){3}\d{1,3}\b/<ipv4>/g;
        s/(?<![0-9a-f:])(?:[0-9a-f]{1,4}:){4,7}[0-9a-f]{1,4}(?![0-9a-f:])/<ipv6>/gi;
        s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g;
    '
}

main() {
    add "# Auditoría de seguridad Android vía ADB (solo lectura)"
    add ""
    add "Fecha: $(date -Iseconds) · dispositivo: $SERIAL · redacción: $([[ $REDACT -eq 1 ]] && echo activada || echo desactivada)"
    check_system
    check_integrity
    check_debug
    check_surveillance
    check_apps
    check_network
    add ""
    add "## Resumen"
    add ""
    add "- CRÍTICO: $CRIT"
    add "- AVISO: $WARN"
    add ""
    add "No se ha modificado el dispositivo. Desactiva la depuración USB al terminar."
    ( umask 077; printf '%s' "$REPORT" | redact > "$OUT" ) || { echo "No se pudo escribir $OUT" >&2; exit 1; }
    printf '%s' "$REPORT" | redact
    printf '\n[+] Informe guardado en %s (permisos 600)\n' "$OUT" >&2
}

main
