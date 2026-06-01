#!/usr/bin/env bash
# Realiza un hard reset (borrado total de datos) en un dispositivo Android
# conectado por cable USB via ADB/fastboot.
# Uso: bash hard-reset.sh [--force]
# Requiere: adb, fastboot (Android Platform Tools)

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
    command -v adb      >/dev/null || err "adb no encontrado. Instala Android Platform Tools."
    command -v fastboot >/dev/null || err "fastboot no encontrado. Instala Android Platform Tools."
}

# ── Verificar dispositivo ADB conectado ───────────────────────────────────────
check_device() {
    local devices
    devices=$(adb devices | grep -v "^List" | grep -c "device$" 2>/dev/null || true)
    [[ "$devices" -ge 1 ]] || err "No se detectó ningún dispositivo ADB. Conecta tu Pixel y habilita depuración USB."

    local model serial
    serial=$(adb get-serialno 2>/dev/null | tr -d '\r')
    model=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    info "Dispositivo detectado: ${model} (${serial})"
}

# ── Confirmación antes del borrado ────────────────────────────────────────────
confirm_reset() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗"
    echo    "║           ⚠  ADVERTENCIA: HARD RESET  ⚠              ║"
    echo    "║                                                      ║"
    echo    "║  Esta operación BORRARÁ TODOS los datos del          ║"
    echo    "║  dispositivo (apps, fotos, cuentas, configuración).  ║"
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

# ── Método 1: Reset via bootloader + fastboot (más confiable en Pixel) ────────
reset_via_fastboot() {
    log "Reiniciando al bootloader..."
    adb reboot bootloader

    log "Esperando al bootloader (fastboot)..."
    local retries=15
    until fastboot devices | grep -q "fastboot" || [[ $retries -eq 0 ]]; do
        sleep 2
        (( retries-- )) || true
    done
    [[ $retries -gt 0 ]] || err "El dispositivo no entró en modo fastboot."

    log "Ejecutando wipe completo (userdata + cache)..."
    fastboot -w

    log "Reiniciando el dispositivo..."
    fastboot reboot
}

# ── Método 2: Reset via recovery (fallback) ───────────────────────────────────
reset_via_recovery() {
    warn "Fastboot no disponible. Intentando reset via recovery..."
    log "Reiniciando al recovery..."
    adb reboot recovery

    info "El dispositivo está en recovery."
    info "Navega manualmente: 'Wipe data / factory reset' → 'Factory data reset'"
    info "Luego selecciona 'Reboot system now'."
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    check_deps
    check_device
    confirm_reset

    echo ""
    log "Iniciando hard reset via USB..."

    if command -v fastboot >/dev/null 2>&1; then
        reset_via_fastboot
    else
        reset_via_recovery
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗"
    echo    "║   Hard reset completado con éxito    ║"
    echo    "║   El dispositivo está reiniciando... ║"
    echo -e "╚══════════════════════════════════════╝${NC}"
    echo ""
    info "Cuando el dispositivo arranque, puedes reinstalar Termux con:"
    echo ""
    echo "  bash install-termux.sh"
    echo ""
}

main "$@"
