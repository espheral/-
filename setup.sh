#!/data/data/com.termux/files/usr/bin/bash
# Termux Android Dev Environment Setup
#
# Uso:
#   ./setup.sh                 Instalación completa (interactiva)
#   ./setup.sh --yes           Completa, sin preguntas
#   ./setup.sh shell nvim      Solo las fases indicadas
#   ./setup.sh --help          Ayuda completa

# -e desactivado a propósito: un fallo puntual (p. ej. un paquete temporalmente
# no disponible) NO debe abortar todo el setup. Cada fase se aísla y reporta.
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[*]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Estado global para el resumen final
FAILED_STEPS=()
FAILED_PKGS=()

# Opciones (configurables por flags o variables de entorno)
NONINTERACTIVE=0
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

ALL_PHASES=(storage update essentials editors languages shell nvim git ssh)

# ── Utilidades ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Termux Dev Setup

Uso: ./setup.sh [opciones] [fases...]

Sin argumentos ejecuta la instalación completa de forma interactiva.

Opciones:
  -y, --yes            Modo no interactivo (no pregunta nombre/email de Git)
      --name <nombre>  Nombre para Git (implica modo no interactivo)
      --email <email>  Email para Git (implica modo no interactivo)
  -h, --help           Muestra esta ayuda

Fases disponibles (puedes pasar una o varias en cualquier orden):
  storage update essentials editors languages shell nvim git ssh

Ejemplos:
  ./setup.sh                                # todo, interactivo
  ./setup.sh --yes                          # todo, sin preguntas
  ./setup.sh shell nvim                     # solo zsh y neovim
  ./setup.sh --name "Ana" --email a@x.com   # configura Git sin preguntar
EOF
}

need_termux() {
    command -v pkg >/dev/null 2>&1 || \
        err "No se encontró 'pkg'. Este script es para Termux. En un PC usa install-termux.sh."
}

# Ejecuta una fase, captura su fallo y continúa con el resto.
run_step() {
    local name="$1"; shift
    info "▶ ${name}"
    if "$@"; then
        return 0
    fi
    warn "El paso '${name}' terminó con errores. Continuando con el resto..."
    FAILED_STEPS+=("$name")
    return 0
}

# Instala paquetes de forma resiliente: si el lote falla, reintenta uno por uno
# para no perder los que sí están disponibles.
pkg_install() {
    log "Instalando: $*"
    if pkg install -y "$@" 2>/dev/null; then
        return 0
    fi
    warn "Instalación en lote falló; reintentando individualmente..."
    local p
    for p in "$@"; do
        if pkg install -y "$p" >/dev/null 2>&1; then
            log "  ✓ $p"
        else
            warn "  ✗ $p"
            FAILED_PKGS+=("$p")
        fi
    done
}

# Copia un archivo creando backup con timestamp si ya existía y era distinto.
install_file() {
    local src="$1" dst="$2"
    [ -f "$src" ] || { warn "No se encontró $src (omitido)"; return 0; }
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
        local bak="${dst}.bak.$(date +%Y%m%d%H%M%S)"
        cp -f "$dst" "$bak"
        info "Backup del archivo previo: $bak"
    fi
    cp -f "$src" "$dst"
}

# Clona un repo de forma superficial (rápido y ligero, ideal en datos móviles).
shallow_clone() {
    local url="$1" dest="$2"
    [ -d "$dest" ] && return 0
    git clone --depth 1 --single-branch "$url" "$dest" \
        || warn "No se pudo clonar $(basename "$dest")"
}

# ── Permisos de almacenamiento ─────────────────────────────────────────────────
setup_storage() {
    log "Configurando acceso al almacenamiento..."
    termux-setup-storage 2>/dev/null || warn "Otorga permiso de almacenamiento manualmente si se solicita."
}

# ── Actualizar repositorios ────────────────────────────────────────────────────
update_packages() {
    log "Actualizando índices y paquetes..."
    pkg update -y && pkg upgrade -y
}

# ── Herramientas esenciales ────────────────────────────────────────────────────
install_essentials() {
    log "Instalando herramientas esenciales..."
    pkg_install \
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
    pkg_install neovim vim nano
}

# ── Lenguajes de programación ──────────────────────────────────────────────────
install_languages() {
    log "Instalando lenguajes de programación..."
    pkg_install \
        python \
        python-pip \
        nodejs-lts \
        rust \
        golang \
        clang \
        make \
        cmake

    # Herramientas de Python (resiliente: no aborta si una falla)
    if command -v python >/dev/null 2>&1; then
        log "Instalando herramientas de Python..."
        python -m pip install --upgrade pip >/dev/null 2>&1 || warn "No se pudo actualizar pip"
        python -m pip install --upgrade black isort pytest httpx rich typer \
            || warn "Algunas librerías de Python no se instalaron"
    fi
}

# ── Shell mejorada (zsh + Oh-My-Zsh) ──────────────────────────────────────────
install_shell() {
    log "Instalando zsh..."
    pkg_install zsh

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "Instalando Oh-My-Zsh..."
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
            || warn "Falló la instalación de Oh-My-Zsh (revisa tu conexión)"
    else
        warn "Oh-My-Zsh ya está instalado."
    fi

    # Plugins útiles (clones superficiales: rápidos y ligeros)
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    shallow_clone https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    shallow_clone https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

    # Aplicar configuración .zshrc (con backup del anterior)
    install_file "$SCRIPT_DIR/dotfiles/.zshrc" "$HOME/.zshrc"

    if command -v zsh >/dev/null 2>&1; then
        chsh -s zsh 2>/dev/null || warn "Cambia el shell manualmente con: chsh -s zsh"
    fi
}

# ── Neovim config básica ───────────────────────────────────────────────────────
install_nvim_config() {
    log "Configurando Neovim..."
    install_file "$SCRIPT_DIR/dotfiles/init.vim" "$HOME/.config/nvim/init.vim"
    mkdir -p "$HOME/.config/nvim/undo"
}

# ── Git global config ──────────────────────────────────────────────────────────
configure_git() {
    log "Configurando Git..."
    local name="$GIT_NAME" email="$GIT_EMAIL"

    if [ "$NONINTERACTIVE" -eq 0 ]; then
        [ -z "$name" ]  && { read -rp "Nombre para Git (Enter para omitir): " name  || true; }
        [ -z "$email" ] && { read -rp "Email para Git (Enter para omitir): " email || true; }
    fi

    [ -n "$name" ]  && git config --global user.name  "$name"
    [ -n "$email" ] && git config --global user.email "$email"

    git config --global init.defaultBranch main
    git config --global core.editor nvim
    git config --global pull.rebase false
    git config --global color.ui auto
    return 0
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
    echo      "║         ¡Setup completado!           ║"
    echo -e   "╚══════════════════════════════════════╝${NC}"
    echo ""

    if [ ${#FAILED_STEPS[@]} -gt 0 ]; then
        warn "Pasos con errores: ${FAILED_STEPS[*]}"
    fi
    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        warn "Paquetes no instalados: ${FAILED_PKGS[*]}"
        info "Reintenta con: pkg install ${FAILED_PKGS[*]}"
    fi

    info "Versiones instaladas:"
    command -v python3 &>/dev/null && echo "  Python:  $(python3 --version)"
    command -v node    &>/dev/null && echo "  Node:    $(node --version)"
    command -v nvim    &>/dev/null && echo "  Neovim:  $(nvim --version | head -1)"
    command -v git     &>/dev/null && echo "  Git:     $(git --version)"
    command -v go      &>/dev/null && echo "  Go:      $(go version)"
    command -v rustc   &>/dev/null && echo "  Rust:    $(rustc --version)"
    echo ""
    info "Aplica los cambios sin reiniciar con:  exec zsh"
    warn "O reinicia Termux para que todo tome efecto."
}

# ── Dispatcher de fases ─────────────────────────────────────────────────────────
run_phase() {
    case "$1" in
        storage)    run_step "Almacenamiento" setup_storage ;;
        update)     run_step "Actualización"   update_packages ;;
        essentials) run_step "Esenciales"      install_essentials ;;
        editors)    run_step "Editores"        install_editors ;;
        languages)  run_step "Lenguajes"       install_languages ;;
        shell)      run_step "Shell (zsh)"     install_shell ;;
        nvim)       run_step "Neovim"          install_nvim_config ;;
        git)        run_step "Git"             configure_git ;;
        ssh)        run_step "SSH"             setup_ssh ;;
        *)          warn "Fase desconocida: '$1' (usa --help para ver las válidas)" ;;
    esac
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    local phases=()

    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes)  NONINTERACTIVE=1 ;;
            --name)    GIT_NAME="${2:-}";  NONINTERACTIVE=1; shift ;;
            --email)   GIT_EMAIL="${2:-}"; NONINTERACTIVE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -*)        warn "Opción desconocida: $1 (ver --help)" ;;
            *)         phases+=("$1") ;;
        esac
        shift
    done

    [ ${#phases[@]} -eq 0 ] && phases=("${ALL_PHASES[@]}")

    need_termux

    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════╗"
    echo "║   Termux Dev Setup para Android      ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
    info "Fases a ejecutar: ${phases[*]}"
    echo ""

    local phase
    for phase in "${phases[@]}"; do
        run_phase "$phase"
    done

    summary
}

main "$@"
