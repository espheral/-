#!/usr/bin/env bash
# Sincroniza dotfiles entre Termux, Debian proot y la app Terminal (AVF) del
# mismo móvil a través de la carpeta Descargas de Android:
#   Termux / proot : /sdcard/Download/.dotfiles-sync
#   AVF            : /mnt/shared/.dotfiles-sync   (misma carpeta vista desde la VM)
#
# Uso: ./sync-dotfiles.sh [status|push|pull]
#   push  copia los dotfiles locales a la carpeta compartida
#   pull  trae los dotfiles; antes guarda copia de los locales
#
# Aviso: el almacenamiento compartido es legible por otras apps con permiso de
# almacenamiento. No se sincronizan claves SSH ni credenciales.

set -Eeuo pipefail

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

DOTFILES=(.zshrc .gitconfig .config/nvim/init.vim)

detect_env() {
    if [[ -d /mnt/shared ]]; then
        echo avf
    elif [[ -f /etc/debian_version && -d /data/data/com.termux/files/home ]]; then
        echo proot
    elif [[ -n ${TERMUX_VERSION:-} || -d /data/data/com.termux ]]; then
        echo termux
    else
        echo unknown
    fi
}

ENV_NAME=$(detect_env)
case "$ENV_NAME" in
    avf)          SYNC_DIR=${SYNC_DIR:-/mnt/shared/.dotfiles-sync} ;;
    termux|proot) SYNC_DIR=${SYNC_DIR:-/sdcard/Download/.dotfiles-sync} ;;
    *)            SYNC_DIR=${SYNC_DIR:-} ;;
esac

require_sync_dir() {
    [[ -n $SYNC_DIR ]] || die "Entorno no reconocido; define SYNC_DIR explícitamente."
}

push_dotfiles() {
    require_sync_dir
    mkdir -p "$SYNC_DIR" || die "No se pudo crear $SYNC_DIR (¿termux-setup-storage?)."
    log "Enviando a $SYNC_DIR"
    local f
    for f in "${DOTFILES[@]}"; do
        if [[ -f $HOME/$f ]]; then
            mkdir -p "$SYNC_DIR/$(dirname "$f")"
            cp -- "$HOME/$f" "$SYNC_DIR/$f"
            log "✓ $f"
        else
            warn "⊘ $f no existe localmente"
        fi
    done
    log "En el otro entorno: bash sync-dotfiles.sh pull"
}

pull_dotfiles() {
    require_sync_dir
    [[ -d $SYNC_DIR ]] || die "$SYNC_DIR no existe; ejecuta antes 'push' en el otro entorno."
    local backup f
    backup="$HOME/.local/state/dev-setup/backups/sync-$(date -u +%Y%m%dT%H%M%SZ)"
    log "Trayendo desde $SYNC_DIR (copia previa en $backup)"
    for f in "${DOTFILES[@]}"; do
        if [[ ! -f $SYNC_DIR/$f ]]; then
            warn "⊘ $f no está en la carpeta compartida"
            continue
        fi
        if [[ -e $HOME/$f ]]; then
            if cmp -s -- "$SYNC_DIR/$f" "$HOME/$f"; then
                log "= $f sin cambios"
                continue
            fi
            mkdir -p "$backup/$(dirname "$f")"
            cp -a -- "$HOME/$f" "$backup/$f"
        fi
        mkdir -p "$HOME/$(dirname "$f")"
        cp -- "$SYNC_DIR/$f" "$HOME/$f"
        log "✓ $f"
    done
    warn "Abre una nueva sesión de shell para aplicar los cambios."
}

status_dotfiles() {
    log "Entorno: $ENV_NAME  carpeta: ${SYNC_DIR:-<sin definir>}"
    local f state
    for f in "${DOTFILES[@]}"; do
        if [[ ! -f $HOME/$f ]]; then
            state="solo remoto/ausente"
        elif [[ -z $SYNC_DIR || ! -f $SYNC_DIR/$f ]]; then
            state="solo local"
        elif cmp -s -- "$HOME/$f" "$SYNC_DIR/$f"; then
            state="idéntico"
        else
            state="DIFIERE"
        fi
        printf '  %-24s %s\n' "$f" "$state"
    done
}

case "${1:-status}" in
    push) push_dotfiles ;;
    pull) pull_dotfiles ;;
    status) status_dotfiles ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "Uso: bash $0 {status|push|pull}" ;;
esac
