#!/data/data/com.termux/files/usr/bin/bash
# Termux Android Dev Environment Setup

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

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║   Termux Dev Setup para Android      ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── Permisos de almacenamiento ─────────────────────────────────────────────────
setup_storage() {
    log "Configurando acceso al almacenamiento..."
    termux-setup-storage 2>/dev/null || warn "Otorga permiso de almacenamiento manualmente si se solicita."
}

# ── Actualizar repositorios ────────────────────────────────────────────────────
update_packages() {
    log "Actualizando paquetes..."
    pkg update -y && pkg upgrade -y
}

# ── Herramientas esenciales ────────────────────────────────────────────────────
install_essentials() {
    log "Instalando herramientas esenciales..."
    pkg install -y \
        git \
        curl \
        wget \
        openssh \
        gnupg \
        tar \
        zip \
        unzip \
        xz-utils \
        proot \
        termux-api
}

# ── Editores ───────────────────────────────────────────────────────────────────
install_editors() {
    log "Instalando editores..."
    pkg install -y neovim vim nano
}

# ── Lenguajes de programación ──────────────────────────────────────────────────
install_languages() {
    log "Instalando lenguajes de programación..."
    pkg install -y \
        python \
        python-pip \
        nodejs-lts \
        rust \
        golang \
        clang \
        make \
        cmake

    # Python tools
    pip install --upgrade pip
    pip install black isort pytest httpx rich typer
}

# ── Shell mejorada (zsh + Oh-My-Zsh) ──────────────────────────────────────────
install_shell() {
    log "Instalando zsh..."
    pkg install -y zsh

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "Instalando Oh-My-Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        warn "Oh-My-Zsh ya está instalado."
    fi

    # Plugins útiles
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions \
            "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    fi

    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting \
            "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    fi

    # Aplicar configuración .zshrc
    cp -f "$(dirname "$0")/dotfiles/.zshrc" "$HOME/.zshrc" 2>/dev/null || true

    chsh -s zsh 2>/dev/null || warn "Cambia el shell manualmente con: chsh -s zsh"
}

# ── Neovim config básica ───────────────────────────────────────────────────────
install_nvim_config() {
    log "Configurando Neovim..."
    mkdir -p "$HOME/.config/nvim"
    cp -f "$(dirname "$0")/dotfiles/init.vim" "$HOME/.config/nvim/init.vim" 2>/dev/null || true
}

# ── Git global config ──────────────────────────────────────────────────────────
configure_git() {
    log "Configurando Git..."
    read -rp "Nombre para Git (Enter para omitir): " git_name
    read -rp "Email para Git (Enter para omitir): " git_email

    [ -n "$git_name" ]  && git config --global user.name  "$git_name"
    [ -n "$git_email" ] && git config --global user.email "$git_email"

    git config --global init.defaultBranch main
    git config --global core.editor nvim
    git config --global pull.rebase false
    git config --global color.ui auto
}

# ── Debian vía proot-distro (opcional) ────────────────────────────────────────
install_debian_proot() {
    read -rp "¿Instalar un entorno Debian completo con proot-distro? Da glibc real, útil para herramientas que fallan en el entorno nativo de Termux (ej. Claude Code CLI) [y/N]: " reply
    case "$reply" in
        [yY]*)
            log "Instalando proot-distro..."
            pkg install -y proot-distro
            log "Instalando Debian (puede tardar unos minutos)..."
            proot-distro install debian || warn "Debian ya podría estar instalado. Revisa con: proot-distro list"
            info "Entra con: proot-distro login debian"
            info "Luego, dentro de Debian, ejecuta:"
            echo "  cd /data/data/com.termux/files/home/$(basename "$(pwd)")"
            echo "  bash setup-debian.sh"
            ;;
        *)
            info "Omitiendo instalación de Debian."
            ;;
    esac
}

# ── Clave SSH ──────────────────────────────────────────────────────────────────
setup_ssh() {
    local KEY="$HOME/.ssh/id_ed25519"
    if [ ! -f "$KEY" ]; then
        log "Generando clave SSH Ed25519..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -C "termux-android" -f "$KEY" -N ""
        info "Clave pública (agrégala a GitHub/GitLab):"
        echo ""
        cat "${KEY}.pub"
        echo ""
    else
        warn "Clave SSH ya existe en $KEY"
        info "Clave pública actual:"
        cat "${KEY}.pub"
    fi
}

# ── Resumen final ──────────────────────────────────────────────────────────────
summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗"
    echo "║         ¡Setup completado!           ║"
    echo "╚══════════════════════════════════════╝${NC}"
    echo ""
    info "Versiones instaladas:"
    command -v python3 &>/dev/null && echo "  Python:  $(python3 --version)"
    command -v node   &>/dev/null && echo "  Node:    $(node --version)"
    command -v nvim   &>/dev/null && echo "  Neovim:  $(nvim --version | head -1)"
    command -v git    &>/dev/null && echo "  Git:     $(git --version)"
    command -v go     &>/dev/null && echo "  Go:      $(go version)"
    command -v rustc  &>/dev/null && echo "  Rust:    $(rustc --version)"
    echo ""
    command -v proot-distro &>/dev/null && info "Entorno Debian disponible: escribe 'debian' para entrar."
    warn "Reinicia Termux para aplicar todos los cambios."
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    setup_storage
    update_packages
    install_essentials
    install_editors
    install_languages
    install_shell
    install_nvim_config
    configure_git
    setup_ssh
    install_debian_proot
    summary
}

main "$@"
