#!/usr/bin/env bash
# Ubuntu Dev Environment Setup (escritorio, servidor o WSL2) + Ubuntu Pro gratuito
#
# Uso:
#   ./setup-ubuntu.sh [--token TOKEN] [--skip-pro] [--with-docker] [--no-apt-news]
#
# Variables de entorno equivalentes:
#   UBUNTU_PRO_TOKEN   token de https://ubuntu.com/pro/dashboard (si se omite: magic attach interactivo)
#   SKIP_PRO=1         no tocar Ubuntu Pro
#   WITH_DOCKER=1      instalar Docker Engine desde el repo oficial
#
# Requiere: Ubuntu LTS (20.04 / 22.04 / 24.04) y sudo.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $1"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRO_TOKEN="${UBUNTU_PRO_TOKEN:-}"
SKIP_PRO="${SKIP_PRO:-0}"
WITH_DOCKER="${WITH_DOCKER:-0}"
APT_NEWS="${APT_NEWS:-0}"     # 0 = desactivar los avisos comerciales de apt (pro config apt_news)
IS_WSL=0
IS_CONTAINER=0

# ── Argumentos ─────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --token)        PRO_TOKEN="${2:-}"; shift 2 ;;
        --token=*)      PRO_TOKEN="${1#*=}"; shift ;;
        --skip-pro)     SKIP_PRO=1; shift ;;
        --with-docker)  WITH_DOCKER=1; shift ;;
        --keep-apt-news) APT_NEWS=1; shift ;;
        -h|--help)      sed -n '2,13p' "$0"; exit 0 ;;
        *)              err "Argumento desconocido: $1 (usa --help)" ;;
    esac
done

echo -e "${BLUE}"
echo "╔══════════════════════════════════════╗"
echo "║   Ubuntu Dev Setup + Ubuntu Pro      ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── Comprobaciones previas ─────────────────────────────────────────────────────
preflight() {
    [ -r /etc/os-release ] || err "No se encontró /etc/os-release. ¿Es esto Ubuntu?"
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "${ID:-}" = "ubuntu" ] || err "Este script es solo para Ubuntu (detectado: ${ID:-desconocido})."
    UBUNTU_VERSION="${VERSION_ID}"
    UBUNTU_CODENAME="${VERSION_CODENAME}"

    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    else
        command -v sudo >/dev/null || err "Se necesita sudo."
        SUDO="sudo"
        $SUDO -v || err "No se pudo obtener sudo."
    fi

    grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        systemd-detect-virt -cq && IS_CONTAINER=1
    fi

    info "Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})  WSL=${IS_WSL}  contenedor=${IS_CONTAINER}"
    export DEBIAN_FRONTEND=noninteractive
}

apt_install() { $SUDO apt-get install -y --no-install-recommends "$@"; }

# ── Actualizar sistema ─────────────────────────────────────────────────────────
update_packages() {
    log "Actualizando paquetes..."
    $SUDO apt-get update -y
    $SUDO apt-get upgrade -y
}

# ── Herramientas esenciales ────────────────────────────────────────────────────
install_essentials() {
    log "Instalando herramientas esenciales..."
    apt_install \
        build-essential git curl wget ca-certificates gnupg lsb-release \
        openssh-client tar zip unzip xz-utils jq \
        htop tmux tree ripgrep fd-find fzf bat \
        software-properties-common apt-transport-https
}

# ── Editores ───────────────────────────────────────────────────────────────────
install_editors() {
    log "Instalando editores..."
    apt_install neovim vim nano
}

# ── Lenguajes ──────────────────────────────────────────────────────────────────
install_languages() {
    log "Instalando Python..."
    apt_install python3 python3-pip python3-venv pipx
    pipx ensurepath >/dev/null 2>&1 || true
    for tool in black isort pytest httpx rich typer; do
        pipx install "$tool" >/dev/null 2>&1 || warn "pipx: no se pudo instalar $tool"
    done

    log "Instalando Node.js LTS (NodeSource 22.x)..."
    if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]; then
        $SUDO install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
            | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
            | $SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null
        $SUDO apt-get update -y
        apt_install nodejs
    else
        warn "Node $(node -v) ya presente, se omite NodeSource."
    fi

    log "Instalando Go (apt) y toolchain C/C++..."
    apt_install golang-go clang make cmake pkg-config

    if ! command -v rustc >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/rustc" ]; then
        log "Instalando Rust (rustup)..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    else
        warn "Rust ya está instalado."
    fi
}

# ── Shell: zsh + Oh-My-Zsh ─────────────────────────────────────────────────────
install_shell() {
    log "Instalando zsh..."
    apt_install zsh

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "Instalando Oh-My-Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        warn "Oh-My-Zsh ya está instalado."
    fi

    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    [ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] \
        || git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    [ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] \
        || git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

    [ -f "$HOME/.zshrc" ] && cp -f "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%Y%m%d%H%M%S)"
    cp -f "$REPO_DIR/dotfiles/.zshrc" "$HOME/.zshrc"

    if [ "$SHELL" != "$(command -v zsh)" ]; then
        $SUDO chsh -s "$(command -v zsh)" "$USER" || warn "Cambia el shell manualmente: chsh -s $(command -v zsh)"
    fi
}

# ── Neovim ─────────────────────────────────────────────────────────────────────
install_nvim_config() {
    log "Configurando Neovim..."
    mkdir -p "$HOME/.config/nvim/undo"
    cp -f "$REPO_DIR/dotfiles/init.vim" "$HOME/.config/nvim/init.vim"
}

# ── Git ────────────────────────────────────────────────────────────────────────
configure_git() {
    log "Configurando Git..."
    if [ -t 0 ]; then
        read -rp "Nombre para Git (Enter para omitir): " git_name
        read -rp "Email para Git (Enter para omitir): " git_email
        [ -n "$git_name" ]  && git config --global user.name  "$git_name"
        [ -n "$git_email" ] && git config --global user.email "$git_email"
    else
        warn "Sin TTY: se omite nombre/email de Git."
    fi
    git config --global init.defaultBranch main
    git config --global core.editor nvim
    git config --global pull.rebase false
    git config --global color.ui auto
}

# ── SSH ────────────────────────────────────────────────────────────────────────
setup_ssh() {
    local KEY="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    if [ ! -f "$KEY" ]; then
        log "Generando clave SSH Ed25519..."
        ssh-keygen -t ed25519 -C "$USER@$(hostname)" -f "$KEY" -N ""
    else
        warn "Clave SSH ya existe en $KEY"
    fi
    info "Clave pública (agrégala a GitHub/GitLab):"
    echo; cat "${KEY}.pub"; echo
}

# ── Ubuntu Pro (plan personal gratuito: hasta 5 máquinas) ──────────────────────
pro_attached() {
    $SUDO pro status --format json 2>/dev/null | jq -e '.attached == true' >/dev/null 2>&1
}

pro_enable() {
    local svc="$1"
    if $SUDO pro status --format json 2>/dev/null \
        | jq -e --arg s "$svc" '.services[] | select(.name==$s and .status=="enabled")' >/dev/null 2>&1; then
        warn "Pro: $svc ya estaba habilitado."
        return 0
    fi
    log "Pro: habilitando $svc..."
    $SUDO pro enable "$svc" --assume-yes || warn "Pro: no se pudo habilitar $svc (revisa 'pro status')."
}

setup_ubuntu_pro() {
    if [ "$SKIP_PRO" = "1" ]; then
        warn "Ubuntu Pro omitido (--skip-pro)."
        return 0
    fi

    case "$UBUNTU_VERSION" in
        *.04) ;;
        *) warn "Ubuntu Pro solo aplica a versiones LTS. Detectado ${UBUNTU_VERSION}; se omite."; return 0 ;;
    esac

    log "Instalando cliente de Ubuntu Pro..."
    apt_install ubuntu-pro-client 2>/dev/null || apt_install ubuntu-advantage-tools

    if pro_attached; then
        warn "Esta máquina ya está adjunta a Ubuntu Pro."
    else
        if [ -n "$PRO_TOKEN" ]; then
            log "Adjuntando con token..."
            $SUDO pro attach --no-auto-enable "$PRO_TOKEN"
        elif [ -t 0 ]; then
            info "Sin token: se usará 'magic attach'. Sigue las instrucciones en pantalla"
            info "(abre https://ubuntu.com/pro/attach e introduce el código que aparecerá)."
            $SUDO pro attach --no-auto-enable
        else
            warn "Sin token y sin TTY: no se puede adjuntar. Exporta UBUNTU_PRO_TOKEN o ejecuta 'sudo pro attach' luego."
            return 0
        fi
    fi

    # Servicios incluidos en el plan gratuito y seguros de activar en cualquier máquina
    pro_enable esm-infra
    pro_enable esm-apps

    # Livepatch necesita kernel de Canonical + snapd: no aplica en WSL ni contenedores
    if [ "$IS_WSL" = "1" ] || [ "$IS_CONTAINER" = "1" ]; then
        warn "Livepatch omitido (WSL/contenedor no usan kernel de Canonical)."
    else
        pro_enable livepatch
    fi

    # USG (Ubuntu Security Guide): solo añade el repo y la herramienta 'usg'. No endurece nada por sí solo.
    pro_enable usg

    if [ "$APT_NEWS" = "0" ]; then
        $SUDO pro config set apt_news=false || true
    fi

    info "Servicios NO activados a propósito (cambian el kernel o restringen updates):"
    info "  fips / fips-updates / realtime-kernel  →  'sudo pro enable <svc>' solo si lo necesitas."
    echo
    $SUDO pro status || true
}

# ── Docker (opcional) ──────────────────────────────────────────────────────────
install_docker() {
    [ "$WITH_DOCKER" = "1" ] || return 0
    if command -v docker >/dev/null 2>&1; then
        warn "Docker ya está instalado."
        return 0
    fi
    log "Instalando Docker Engine (repo oficial)..."
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO tee /etc/apt/keyrings/docker.asc >/dev/null
    $SUDO chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
    $SUDO apt-get update -y
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    $SUDO usermod -aG docker "$USER" || true
    if [ "$IS_WSL" = "1" ]; then
        warn "WSL2: Docker necesita systemd. Comprueba que /etc/wsl.conf tiene [boot] systemd=true y reinicia con 'wsl --shutdown'."
    fi
}

# ── Resumen ────────────────────────────────────────────────────────────────────
summary() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════╗"
    echo "║         ¡Setup completado!           ║"
    echo "╚══════════════════════════════════════╝${NC}"
    echo
    info "Versiones instaladas:"
    command -v python3 &>/dev/null && echo "  Python:  $(python3 --version)"
    command -v node    &>/dev/null && echo "  Node:    $(node --version)"
    command -v nvim    &>/dev/null && echo "  Neovim:  $(nvim --version | head -1)"
    command -v git     &>/dev/null && echo "  Git:     $(git --version)"
    command -v go      &>/dev/null && echo "  Go:      $(go version)"
    [ -x "$HOME/.cargo/bin/rustc" ] && echo "  Rust:    $("$HOME/.cargo/bin/rustc" --version)"
    command -v docker  &>/dev/null && echo "  Docker:  $(docker --version)"
    command -v pro     &>/dev/null && echo "  Pro:     $(pro version)"
    echo
    warn "Cierra sesión y vuelve a entrar (o reinicia) para aplicar zsh, grupo docker y PATH."
}

main() {
    preflight
    update_packages
    install_essentials
    install_editors
    install_languages
    install_shell
    install_nvim_config
    configure_git
    setup_ssh
    setup_ubuntu_pro
    install_docker
    summary
}

main
