#!/usr/bin/env bash
# Sincroniza dotfiles entre Termux y Linux Terminal (AVF).
# Útil cuando usas ambos entornos en el mismo Pixel y quieres mantener
# .zshrc, .gitconfig, etc. en sincronía.
#
# Uso: ./sync-dotfiles.sh [push|pull|status]
#   push   → copia los dotfiles locales a /mnt/shared (solo Linux Terminal)
#   pull   → obtiene dotfiles de /mnt/shared (solo Linux Terminal)
#   status → muestra qué hay en cada lado
#
# Archivos sincronizados: .zshrc, .gitconfig, .ssh/config, init.vim

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $1"; }

# Detectar entorno
detect_env() {
    if [ -d /mnt/shared ]; then
        echo "linux-terminal"
    elif [ -d /sdcard ]; then
        echo "termux"
    else
        echo "unknown"
    fi
}

# Ruta de sincronización (solo funciona en Linux Terminal)
SYNC_DIR="/mnt/shared/.dotfiles-sync"
ENV=$(detect_env)

if [ "$ENV" = "termux" ]; then
    # Desde Termux, copiar a /sdcard/shared
    SYNC_DIR="/sdcard/shared/.dotfiles-sync"
fi

# Archivos a sincronizar
declare -a DOTFILES=(
    ".zshrc"
    ".gitconfig"
    ".config/nvim/init.vim"
)

push_dotfiles() {
    if [ ! -d "$SYNC_DIR" ]; then
        mkdir -p "$SYNC_DIR" || err "No se pudo crear $SYNC_DIR — verifica permisos."
    fi

    log "Enviando dotfiles a $SYNC_DIR..."
    for file in "${DOTFILES[@]}"; do
        if [ -f "$HOME/$file" ]; then
            mkdir -p "$SYNC_DIR/$(dirname "$file")"
            cp "$HOME/$file" "$SYNC_DIR/$file"
            info "✓ $file"
        else
            warn "⊘ $file no encontrado localmente"
        fi
    done

    echo ""
    info "Archivos listos en $SYNC_DIR"
    info "Para sincronizar desde otro entorno: ./sync-dotfiles.sh pull"
}

pull_dotfiles() {
    if [ ! -d "$SYNC_DIR" ]; then
        err "$SYNC_DIR no existe — ejecuta primero 'sync-dotfiles.sh push' desde el otro entorno."
    fi

    log "Trayendo dotfiles desde $SYNC_DIR..."
    for file in "${DOTFILES[@]}"; do
        if [ -f "$SYNC_DIR/$file" ]; then
            mkdir -p "$HOME/$(dirname "$file")"
            cp "$SYNC_DIR/$file" "$HOME/$file"
            info "✓ $file"
        else
            warn "⊘ $file no encontrado en sincronización"
        fi
    done

    echo ""
    warn "Reinicia el shell (cierra y abre la terminal) para aplicar cambios."
}

status_dotfiles() {
    info "Entorno detectado: $ENV"
    echo ""

    if [ -d "$SYNC_DIR" ]; then
        info "Estado en $SYNC_DIR:"
        ls -lh "$SYNC_DIR"/ 2>/dev/null | tail -n +2 || echo "  (vacío)"
    else
        warn "No hay sincronización activa en $SYNC_DIR"
    fi

    echo ""
    info "Dotfiles locales:"
    for file in "${DOTFILES[@]}"; do
        if [ -f "$HOME/$file" ]; then
            echo "  ✓ $file ($(date -r "$HOME/$file" '+%Y-%m-%d %H:%M'))"
        else
            echo "  ⊘ $file"
        fi
    done
}

main() {
    local action="${1:-status}"

    case "$action" in
        push)
            push_dotfiles
            ;;
        pull)
            pull_dotfiles
            ;;
        status)
            status_dotfiles
            ;;
        *)
            err "Uso: $0 {push|pull|status}"
            ;;
    esac
}

main "$@"
