#!/usr/bin/env bash
# Hard reset (borrado de fábrica) en SMART Board (sistema iQ/Android) via USB.
# Uso: bash hard-reset.sh [--force]
# Requiere: adb (Android Platform Tools), USB debugging habilitado en la SMART Board.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $1"; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# ── Verificar dependencias ─────────────────────────────────────────────────────
check_deps() {
    command -v adb >/dev/null || err "adb no encontrado. Instala Android Platform Tools."
}

# ── Verificar SMART Board conectada ───────────────────────────────────────────
check_device() {
    local count
    count=$(adb devices | grep -v "^List" | grep -c "device$" 2>/dev/null || true)
    [[ "$count" -ge 1 ]] || err "No se detectó dispositivo. Conecta la SMART Board por USB y habilita la depuración ADB en Configuración → Sistema → Opciones de desarrollador."

    local model serial
    serial=$(adb get-serialno 2>/dev/null | tr -d '\r')
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    local brand
    brand=$(adb shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
    info "Dispositivo detectado: ${brand} ${model} (${serial})"
}

# ── Confirmación ───────────────────────────────────────────────────────────────
confirm_reset() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗"
    echo    "║        ⚠  ADVERTENCIA: HARD RESET  ⚠                ║"
    echo    "║                                                      ║"
    echo    "║  Esto borrará TODOS los datos de la SMART Board:     ║"
    echo    "║  apps instaladas, configuración, cuentas, archivos.  ║"
    echo    "║  El sistema iQ volverá a valores de fábrica.         ║"
    echo    "║  Esta acción NO SE PUEDE deshacer.                   ║"
    echo -e "╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$FORCE" == false ]]; then
        read -r -p "¿Estás seguro? Escribe exactamente 'RESET' para continuar: " confirm
        [[ "$confirm" == "RESET" ]] || err "Operación cancelada."
    else
        warn "Modo --force activado. Saltando confirmación."
    fi
}

# ── Hard reset vía ADB (Android / iQ de SMART Board) ─────────────────────────
do_reset() {
    log "Iniciando factory reset en la SMART Board..."

    # Intentar primero con el intent de borrado de fábrica (Android 5–12)
    if adb shell am broadcast -a android.intent.action.MASTER_CLEAR \
        --receiver-permission android.permission.MASTER_CLEAR >/dev/null 2>&1; then
        log "Señal de reset enviada via broadcast."
        return
    fi

    # Fallback: lanzar la actividad de restablecimiento de fábrica directamente
    warn "Broadcast no disponible. Intentando via Settings..."
    if adb shell am start \
        -n "com.android.settings/.Settings\$FactoryResetActivity" >/dev/null 2>&1; then
        log "Pantalla de factory reset abierta en la SMART Board."
        info "Confirma el reset en la pantalla del dispositivo."
        return
    fi

    # Fallback final: recovery mode
    warn "Intentando via recovery mode..."
    adb reboot recovery
    info "La SMART Board está en recovery. Selecciona 'Wipe data / factory reset'."
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    check_deps
    check_device
    confirm_reset

    echo ""
    do_reset

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗"
    echo    "║   Hard reset enviado a la SMART Board    ║"
    echo    "║   El sistema iQ se está reiniciando...   ║"
    echo -e "╚══════════════════════════════════════════╝${NC}"
    echo ""
    info "Tras el reinicio la SMART Board estará en valores de fábrica."
}

main "$@"
