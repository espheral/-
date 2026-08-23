#!/usr/bin/env bash
# Debian Dev Environment Setup — se ejecuta DENTRO de: proot-distro login debian
# (instalado sobre Termux con install_debian_proot en setup.sh, o manualmente
#  con: pkg install proot-distro && proot-distro install debian)

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
echo "║   Debian Dev Setup (proot-distro)    ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

[ -f /etc/debian_version ] || err "Esto no es Debian. Ejecuta esto dentro de: proot-distro login debian"

# ── Actualizar paquetes ─────────────────────────────────────────────────────────
update_packages() {
    log "Actualizando apt..."
    apt update -y && apt upgrade -y
}

# ── Herramientas esenciales ─────────────────────────────────────────────────────
install_essentials() {
    log "Instalando herramientas esenciales..."
    apt install -y \
        git \
        curl \
        wget \
        openssh-client \
        gnupg \
        tar \
        zip \
        unzip \
        xz-utils \
        build-essential \
        ca-certificates
}

# ── Editores ─────────────────────────────────────────────────────────────────────
install_editors() {
    log "Instalando editores..."
    apt install -y neovim vim nano
}

# ── Lenguajes de programación ────────────────────────────────────────────────────
install_languages() {
    log "Instalando lenguajes de programación..."
    apt install -y python3 python3-pip python3-venv golang rustc cargo

    if ! command -v node &>/dev/null; then
        log "Instalando Node.js LTS (NodeSource)..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        apt install -y nodejs
    else
        warn "Node.js ya está instalado: $(node --version)"
    fi

    pip3 install --break-system-packages --upgrade pip black isort pytest httpx rich typer 2>/dev/null \
        || pip3 install --upgrade pip black isort pytest httpx rich typer
}

# ── Claude Code CLI ──────────────────────────────────────────────────────────────
install_claude_code() {
    log "Instalando Claude Code CLI..."
    if command -v claude &>/dev/null; then
        warn "Claude Code ya está instalado."
        return
    fi
    curl -fsSL https://claude.ai/install.sh | bash \
        || warn "No se pudo instalar Claude Code automáticamente. Instálalo manualmente con: curl -fsSL https://claude.ai/install.sh | bash"
}

# ── Shell mejorada (zsh + Oh-My-Zsh) ─────────────────────────────────────────────
install_shell() {
    log "Instalando zsh..."
    apt install -y zsh

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "Instalando Oh-My-Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        warn "Oh-My-Zsh ya está instalado."
    fi

    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions \
            "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    fi

    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting \
            "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    fi

    cp -f "$(dirname "$0")/dotfiles/.zshrc-debian" "$HOME/.zshrc" 2>/dev/null || true

    chsh -s zsh 2>/dev/null || warn "Cambia el shell manualmente con: chsh -s zsh"
}

# ── Neovim config básica ──────────────────────────────────────────────────────────
install_nvim_config() {
    log "Configurando Neovim..."
    mkdir -p "$HOME/.config/nvim"
    cp -f "$(dirname "$0")/dotfiles/init.vim" "$HOME/.config/nvim/init.vim" 2>/dev/null || true
}

# ── Git global config ───────────────────────────────────────────────────────────
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

# ── Clave SSH ─────────────────────────────────────────────────────────────────────
setup_ssh() {
    local key="$HOME/.ssh/id_ed25519"
    local termux_key="/data/data/com.termux/files/home/.ssh/id_ed25519"

    if [ -f "$key" ]; then
        warn "Clave SSH ya existe en $key"
    elif [ -f "$termux_key" ]; then
        info "Reutilizando la clave SSH de Termux (evita generar una nueva por dispositivo)."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        cp "$termux_key" "$key"
        cp "${termux_key}.pub" "${key}.pub"
        chmod 600 "$key"
    else
        log "Generando clave SSH Ed25519..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -C "debian-proot-android" -f "$key" -N ""
    fi

    info "Clave pública (agrégala a GitHub/GitLab):"
    echo ""
    cat "${key}.pub"
    echo ""
}

# ── Resumen final ──────────────────────────────────────────────────────────────────
summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗"
    echo "║         ¡Setup completado!           ║"
    echo "╚══════════════════════════════════════╝${NC}"
    echo ""
    info "Versiones instaladas:"
    command -v python3 &>/dev/null && echo "  Python:      $(python3 --version)"
    command -v node   &>/dev/null && echo "  Node:        $(node --version)"
    command -v nvim   &>/dev/null && echo "  Neovim:      $(nvim --version | head -1)"
    command -v git    &>/dev/null && echo "  Git:         $(git --version)"
    command -v go     &>/dev/null && echo "  Go:          $(go version)"
    command -v rustc  &>/dev/null && echo "  Rust:        $(rustc --version)"
    command -v claude &>/dev/null && echo "  Claude Code: instalado (ejecuta: claude)"
    echo ""
    warn "Reinicia la sesión (proot-distro login debian) para aplicar el shell."
}

# ── Main ───────────────────────────────────────────────────────────────────────────
main() {
    update_packages
    install_essentials
    install_editors
    install_languages
    install_claude_code
    install_shell
    install_nvim_config
    configure_git
    setup_ssh
    summary
}

main "$@"
