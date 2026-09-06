#!/usr/bin/env bash
# Safe Ubuntu development environment setup for 20.04/22.04/24.04 and WSL2.

set -Eeuo pipefail

MODE=dry-run
WITH_DOCKER=0
SKIP_PRO=0
KEEP_APT_NEWS=0
UPGRADE_SYSTEM=0
REPLACE_DOTFILES=0
CONFIGURE_GIT=0
GENERATE_SSH_KEY=0
IS_WSL=0
IS_CONTAINER=0
SUDO=()
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage: ./setup-ubuntu.sh [options]

The default is --dry-run: it performs checks and prints the planned changes.
Nothing is installed or overwritten until --apply is supplied.

  --dry-run             inspect and print the plan (default)
  --apply               perform the planned changes
  --upgrade-system      run apt-get upgrade (never enabled by default)
  --replace-dotfiles    replace ~/.zshrc and Neovim config after backing them up
  --configure-git       set a small set of global Git defaults
  --generate-ssh-key    create ~/.ssh/id_ed25519 if no key exists
  --skip-pro            do not install, attach or configure Ubuntu Pro
  --with-docker         install Docker Engine from Docker's official repository
  --keep-apt-news       preserve the current Ubuntu Pro apt_news setting
  -h, --help            show this help

For non-interactive Pro attach, set UBUNTU_PRO_TOKEN in the environment. Never
put the token on the command line. Without a token, --apply uses magic attach
only when stdin is a TTY.
EOF
}

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

quote_cmd() {
    printf '    '
    printf '%q ' "$@"
    printf '\n'
}

run() {
    if [[ "$MODE" == dry-run ]]; then
        quote_cmd "$@"
    else
        "$@"
    fi
}

run_root() {
    run "${SUDO[@]}" "$@"
}

while (($#)); do
    case "$1" in
        --dry-run) MODE=dry-run ;;
        --apply) MODE=apply ;;
        --upgrade-system) UPGRADE_SYSTEM=1 ;;
        --replace-dotfiles) REPLACE_DOTFILES=1 ;;
        --configure-git) CONFIGURE_GIT=1 ;;
        --generate-ssh-key) GENERATE_SSH_KEY=1 ;;
        --skip-pro) SKIP_PRO=1 ;;
        --with-docker) WITH_DOCKER=1 ;;
        --keep-apt-news) KEEP_APT_NEWS=1 ;;
        -h|--help) usage; exit 0 ;;
        --token|--token=*) die "No pases tokens por argv; usa UBUNTU_PRO_TOKEN." ;;
        *) die "Argumento desconocido: $1 (usa --help)." ;;
    esac
    shift
done

preflight() {
    [[ -r /etc/os-release ]] || die "No se encontró /etc/os-release."
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ ${ID:-} == ubuntu ]] || die "Solo se admite Ubuntu (detectado: ${ID:-desconocido})."
    case "${VERSION_ID:-}" in
        20.04|22.04|24.04) ;;
        *) die "Versión no admitida: ${VERSION_ID:-desconocida}; se requiere Ubuntu LTS 20.04, 22.04 o 24.04." ;;
    esac
    UBUNTU_VERSION=$VERSION_ID
    UBUNTU_CODENAME=$VERSION_CODENAME

    if [[ $MODE == apply && $(id -u) -eq 0 ]]; then
        die "No ejecutes el script completo como root. Úsalo como usuario normal; pedirá sudo solo cuando sea necesario."
    fi

    grep -Eqi '(microsoft|wsl)' /proc/version 2>/dev/null && IS_WSL=1
    if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -cq; then
        IS_CONTAINER=1
    fi

    if [[ $MODE == apply ]]; then
        command -v sudo >/dev/null 2>&1 || die "Se necesita sudo para --apply."
        SUDO=(sudo)
        sudo -v || die "No se pudo validar sudo."
    fi

    log "Modo=$MODE Ubuntu=$UBUNTU_VERSION codename=$UBUNTU_CODENAME WSL=$IS_WSL contenedor=$IS_CONTAINER"
    [[ -r "$REPO_DIR/dotfiles/.zshrc" ]] || die "Falta dotfiles/.zshrc."
    [[ -r "$REPO_DIR/dotfiles/init.vim" ]] || die "Falta dotfiles/init.vim."
}

apt_install() {
    run_root apt-get install -y --no-install-recommends "$@"
}

update_packages() {
    log "Índices APT"
    run_root apt-get update
    if ((UPGRADE_SYSTEM)); then
        log "Actualización completa solicitada explícitamente"
        run_root apt-get upgrade -y
    else
        log "apt-get upgrade omitido (usa --upgrade-system para autorizarlo)"
    fi
}

install_packages() {
    log "Paquetes de repositorios Ubuntu"
    apt_install build-essential git curl wget ca-certificates gnupg lsb-release \
        openssh-client tar zip unzip xz-utils jq htop tmux tree ripgrep fd-find \
        fzf bat software-properties-common python3 python3-pip python3-venv pipx \
        neovim vim nano zsh nodejs npm golang-go rustc cargo clang make cmake pkg-config
}

backup_path() {
    local src=$1 backup_dir=$2
    [[ -e "$src" || -L "$src" ]] || return 0
    run mkdir -p "$backup_dir"
    run cp -a -- "$src" "$backup_dir/"
}

install_dotfiles() {
    if (( ! REPLACE_DOTFILES )); then
        log "Dotfiles omitidos (usa --replace-dotfiles para autorizar copia y sustitución)"
        return
    fi
    local stamp backup_dir
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    backup_dir="$HOME/.local/state/dev-setup/backups/$stamp"
    log "Copia previa de dotfiles en $backup_dir"
    backup_path "$HOME/.zshrc" "$backup_dir"
    backup_path "$HOME/.config/nvim/init.vim" "$backup_dir"
    run mkdir -p "$HOME/.config/nvim/undo"
    run install -m 0644 "$REPO_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
    run install -m 0644 "$REPO_DIR/dotfiles/init.vim" "$HOME/.config/nvim/init.vim"
}

configure_git() {
    if (( ! CONFIGURE_GIT )); then
        log "Git global omitido (usa --configure-git)"
        return
    fi
    run git config --global init.defaultBranch main
    run git config --global core.editor nvim
    run git config --global pull.rebase false
    run git config --global color.ui auto
}

setup_ssh() {
    if (( ! GENERATE_SSH_KEY )); then
        log "Generación de clave SSH omitida (usa --generate-ssh-key)"
        return
    fi
    local key="$HOME/.ssh/id_ed25519"
    if [[ -e "$key" ]]; then
        log "La clave $key ya existe; no se toca"
        return
    fi
    run install -d -m 0700 "$HOME/.ssh"
    run ssh-keygen -t ed25519 -C "$(id -un)@$(hostname)" -f "$key"
    log "Se pedirá una passphrase de forma interactiva; la clave privada nunca se mostrará."
}

pro_attached() {
    run_root pro status --format json >/dev/null
}

setup_ubuntu_pro() {
    if ((SKIP_PRO)); then
        log "Ubuntu Pro omitido"
        return
    fi
    log "Ubuntu Pro"
    apt_install ubuntu-pro-client
    if [[ $MODE == dry-run ]]; then
        if [[ -n ${UBUNTU_PRO_TOKEN:-} ]]; then
            log "Se usaría UBUNTU_PRO_TOKEN (valor oculto)"
        else
            log "Se usaría magic attach en una terminal interactiva"
        fi
        quote_cmd "${SUDO[@]}" pro attach --no-auto-enable '<token-oculto-o-magic-attach>'
        quote_cmd "${SUDO[@]}" pro enable esm-infra --assume-yes
        quote_cmd "${SUDO[@]}" pro enable esm-apps --assume-yes
        ((IS_WSL || IS_CONTAINER)) || quote_cmd "${SUDO[@]}" pro enable livepatch --assume-yes
        quote_cmd "${SUDO[@]}" pro enable usg --assume-yes
        ((KEEP_APT_NEWS)) || quote_cmd "${SUDO[@]}" pro config set apt_news=false
        return
    fi

    if ! pro_attached; then
        if [[ -n ${UBUNTU_PRO_TOKEN:-} ]]; then
            run_root pro attach --no-auto-enable "$UBUNTU_PRO_TOKEN"
            unset UBUNTU_PRO_TOKEN
        elif [[ -t 0 ]]; then
            run_root pro attach --no-auto-enable
        else
            die "Ubuntu Pro no está adjunto y no hay TTY/token de entorno; usa --skip-pro o magic attach."
        fi
    fi
    run_root pro enable esm-infra --assume-yes
    run_root pro enable esm-apps --assume-yes
    if ((IS_WSL || IS_CONTAINER)); then
        log "Livepatch omitido en WSL/contenedor"
    else
        run_root pro enable livepatch --assume-yes
    fi
    run_root pro enable usg --assume-yes
    ((KEEP_APT_NEWS)) || run_root pro config set apt_news=false
}

install_docker() {
    ((WITH_DOCKER)) || { log "Docker omitido (usa --with-docker)"; return; }
    log "Docker Engine desde el repositorio oficial"
    if [[ $MODE == dry-run ]]; then
        quote_cmd "${SUDO[@]}" install -m 0755 -d /etc/apt/keyrings
        printf '    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -> /etc/apt/keyrings/docker.gpg\n'
        printf '    crear /etc/apt/sources.list.d/docker.list para %s\n' "$UBUNTU_CODENAME"
        quote_cmd "${SUDO[@]}" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        quote_cmd "${SUDO[@]}" usermod -aG docker "$(id -un)"
        return
    fi
    run_root install -m 0755 -d /etc/apt/keyrings
    local tmp_key
    tmp_key=$(mktemp)
    if ! curl --proto '=https' --tlsv1.2 -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$tmp_key"; then
        rm -f -- "$tmp_key"
        die "No se pudo descargar la clave de Docker."
    fi
    if ! run_root gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg "$tmp_key"; then
        rm -f -- "$tmp_key"
        die "No se pudo instalar la clave de Docker."
    fi
    rm -f -- "$tmp_key"
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
        "$(dpkg --print-architecture)" "$UBUNTU_CODENAME" | run_root tee /etc/apt/sources.list.d/docker.list >/dev/null
    run_root apt-get update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    run_root usermod -aG docker "$(id -un)"
    ((IS_WSL)) && warn "WSL2: verifica systemd antes de intentar iniciar Docker."
}

summary() {
    log "Plan completado en modo $MODE"
    if [[ $MODE == dry-run ]]; then
        log "No se ha modificado el sistema. Revisa el plan y usa --apply solo en el host correcto."
    else
        log "Verifica versiones, dotfiles, Git, Pro y Docker según las opciones autorizadas."
    fi
}

main() {
    preflight
    update_packages
    install_packages
    install_dotfiles
    configure_git
    setup_ssh
    setup_ubuntu_pro
    install_docker
    summary
}

main
