#!/usr/bin/env bash
# Descarga e instala Termux (arm64-v8a) en un Pixel conectado por ADB.
# Uso: bash install-termux.sh
# Requiere: adb, curl (en el PC/Mac desde donde ejecutas este script)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $1"; }

# ── Detectar arquitectura del dispositivo conectado ────────────────────────────
detect_arch() {
    local abi
    abi=$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r') \
        || err "No se detectó dispositivo ADB. Conecta tu Pixel y habilita depuración USB."
    echo "$abi"
}

# ── Obtener última versión desde la API de GitHub ─────────────────────────────
latest_version() {
    curl -fsSL "https://api.github.com/repos/termux/termux-app/releases/latest" \
        | grep '"tag_name"' \
        | head -1 \
        | sed 's/.*"tag_name": *"\(.*\)".*/\1/'
}

# ── Construir URLs de descarga ─────────────────────────────────────────────────
apk_url() {
    local version="$1" arch="$2"
    local encoded_version
    encoded_version=$(echo "$version" | sed 's/+/%2B/g')
    echo "https://github.com/termux/termux-app/releases/download/${version}/termux-app_${encoded_version}%2Bgithub-debug_${arch}.apk"
}

sha_url() {
    local version="$1" arch="$2"
    local encoded_version
    encoded_version=$(echo "$version" | sed 's/+/%2B/g')
    echo "https://github.com/termux/termux-app/releases/download/${version}/termux-app_${encoded_version}%2Bgithub-debug_${arch}.apk.sha256sum"
}

# ── Verificar integridad del APK ───────────────────────────────────────────────
verify_apk() {
    local apk_file="$1" sha_url="$2"
    local sha_file
    sha_file=$(mktemp /tmp/termux-sha.XXXXXX)

    log "Descargando checksum SHA256..."
    curl -fsSL -o "$sha_file" "$sha_url" \
        || { rm -f "$sha_file"; err "No se pudo descargar el checksum. Abortando por seguridad."; }

    local expected actual
    expected=$(awk '{print $1}' "$sha_file")
    actual=$(sha256sum "$apk_file" | awk '{print $1}')
    rm -f "$sha_file"

    if [[ "$expected" != "$actual" ]]; then
        rm -f "$apk_file"
        err "¡FALLO DE INTEGRIDAD SHA256! El APK puede haber sido manipulado. No se instalará."
    fi
    log "SHA256 verificado: $actual"
}

# ── Verificar dependencias locales ─────────────────────────────────────────────
check_deps() {
    command -v adb  >/dev/null || err "adb no encontrado. Instala Android Platform Tools."
    command -v curl >/dev/null || err "curl no encontrado."
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    check_deps

    log "Detectando dispositivo..."
    local arch
    arch=$(detect_arch)
    info "Arquitectura detectada: $arch"

    # Validar que sea una arquitectura con APK disponible
    case "$arch" in
        arm64-v8a|armeabi-v7a|x86|x86_64) ;;
        *) warn "Arquitectura '$arch' inusual. Usando arm64-v8a como fallback."; arch="arm64-v8a" ;;
    esac

    log "Consultando última versión de Termux..."
    local version
    version=$(latest_version)
    [ -z "$version" ] && err "No se pudo obtener la versión de GitHub. Revisa tu conexión."
    info "Versión: $version"

    local url sha_download_url
    url=$(apk_url "$version" "$arch")
    sha_download_url=$(sha_url "$version" "$arch")

    # Nombre de archivo aleatorio — evita race condition TOCTOU con nombre predecible
    local apk_file
    apk_file=$(mktemp /tmp/termux-XXXXXX.apk)

    # Limpiar el APK temporal en cualquier salida (éxito, error o Ctrl+C)
    trap 'rm -f "$apk_file"' EXIT

    log "Descargando APK..."
    curl -fL --progress-bar -o "$apk_file" "$url" \
        || err "Descarga fallida. URL: $url"

    info "APK guardado en: $apk_file"

    verify_apk "$apk_file" "$sha_download_url"

    log "Instalando en el dispositivo via ADB..."
    adb install -r "$apk_file" \
        || err "Instalación fallida. Asegúrate de habilitar 'Instalar apps desconocidas' en el Pixel."

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗"
    echo "║   Termux ${version} instalado          ║"
    echo "╚══════════════════════════════════════╝${NC}"
    echo ""
    info "Siguiente paso: abre Termux en tu Pixel y ejecuta:"
    echo ""
    echo "  pkg install -y git"
    echo "  git clone https://github.com/espheral/- ~/termux-setup"
    echo "  cd ~/termux-setup && chmod +x setup.sh && ./setup.sh"
    echo ""
}

main "$@"
