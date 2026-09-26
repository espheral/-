#!/usr/bin/env bash
# Safe Debian development setup for Android:
#   --target proot  Debian via proot-distro on Termux (runs as root inside proot)
#   --target avf    Android native "Terminal" app (AVF VM, user droid + sudo)
# The target is auto-detected when possible. Default mode is --dry-run.

set -Eeuo pipefail

MODE=dry-run
TARGET=auto
UPGRADE_SYSTEM=0
REPLACE_DOTFILES=0
SET_SHELL=0
CONFIGURE_GIT=0
GENERATE_SSH_KEY=0
REUSE_TERMUX_KEY=0
WITH_NODESOURCE=0
WITH_CLAUDE_CODE=0
SUDO=()
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERMUX_HOME=/data/data/com.termux/files/home

usage() {
    cat <<'EOF'
Usage: ./setup-debian.sh [--target proot|avf] [options]

The default is --dry-run: checks and prints the plan. Nothing is installed or
overwritten until --apply is supplied.

  --target proot|avf      force the environment (auto-detected otherwise)
  --dry-run               inspect and print the plan (default)
  --apply                 perform the planned changes
  --upgrade-system        run apt-get upgrade
  --replace-dotfiles      back up and replace ~/.zshrc and Neovim config;
                          installs Oh-My-Zsh and its plugins if missing
  --set-shell             make zsh the login shell
  --configure-git         set a small set of global Git defaults
  --generate-ssh-key      create ~/.ssh/id_ed25519 (interactive passphrase)
  --reuse-termux-ssh-key  proot only: copy the existing Termux key instead
  --with-nodesource       install Node.js LTS from NodeSource instead of Debian
  --with-claude-code      install Claude Code CLI with the official installer
  -h, --help              show this help
EOF
}

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

quote_cmd() { printf '    '; printf '%q ' "$@"; printf '\n'; }
run() { if [[ $MODE == dry-run ]]; then quote_cmd "$@"; else "$@"; fi; }
run_root() { run "${SUDO[@]}" "$@"; }

while (($#)); do
    case "$1" in
        --target) shift; TARGET=${1:-} ;;
        --target=*) TARGET=${1#*=} ;;
        --dry-run) MODE=dry-run ;;
        --apply) MODE=apply ;;
        --upgrade-system) UPGRADE_SYSTEM=1 ;;
        --replace-dotfiles) REPLACE_DOTFILES=1 ;;
        --set-shell) SET_SHELL=1 ;;
        --configure-git) CONFIGURE_GIT=1 ;;
        --generate-ssh-key) GENERATE_SSH_KEY=1 ;;
        --reuse-termux-ssh-key) REUSE_TERMUX_KEY=1 ;;
        --with-nodesource) WITH_NODESOURCE=1 ;;
        --with-claude-code) WITH_CLAUDE_CODE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Argumento desconocido: $1 (usa --help)." ;;
    esac
    shift
done

detect_target() {
    if [[ -d /mnt/shared ]]; then
        echo avf
    elif [[ -d $TERMUX_HOME ]]; then
        echo proot
    else
        echo unknown
    fi
}

preflight() {
    [[ -f /etc/debian_version ]] || die "Esto no es Debian. Ejecútalo dentro de 'proot-distro login debian' o de la app Terminal."
    [[ $TARGET == auto ]] && TARGET=$(detect_target)
    case "$TARGET" in
        proot|avf) ;;
        unknown) die "No se pudo detectar el entorno; indica --target proot o --target avf." ;;
        *) die "--target no válido: $TARGET (proot|avf)." ;;
    esac

    local detected
    detected=$(detect_target)
    if [[ $detected != "$TARGET" ]]; then
        [[ $MODE == apply ]] && die "El entorno detectado ($detected) no coincide con --target $TARGET."
        warn "Entorno detectado: $detected; se simula --target $TARGET."
    fi

    if ((REUSE_TERMUX_KEY)) && [[ $TARGET != proot ]]; then
        die "--reuse-termux-ssh-key solo aplica a --target proot."
    fi
    if ((REUSE_TERMUX_KEY && GENERATE_SSH_KEY)); then
        die "Usa --generate-ssh-key o --reuse-termux-ssh-key, no ambos."
    fi

    if [[ $TARGET == avf ]]; then
        if [[ $MODE == apply && $(id -u) -eq 0 ]]; then
            die "En la app Terminal ejecútalo como 'droid'; pedirá sudo cuando haga falta."
        fi
        if [[ $MODE == apply ]]; then
            command -v sudo >/dev/null 2>&1 || die "Se necesita sudo para --apply."
            sudo -v || die "No se pudo validar sudo."
        fi
        SUDO=(sudo)
    elif [[ $(id -u) -ne 0 ]]; then
        # proot-distro entra como root por defecto; con --user se requiere sudo
        SUDO=(sudo)
    fi

    [[ -r "$REPO_DIR/dotfiles/.zshrc" ]] || die "Falta dotfiles/.zshrc."
    [[ -r "$REPO_DIR/dotfiles/init.vim" ]] || die "Falta dotfiles/init.vim."
    log "Modo=$MODE destino=$TARGET usuario=$(id -un) Debian=$(cat /etc/debian_version)"
}

apt_install() { run_root apt-get install -y --no-install-recommends "$@"; }

update_packages() {
    log "Índices APT"
    run_root apt-get update
    if ((UPGRADE_SYSTEM)); then
        run_root apt-get upgrade -y
    else
        log "apt-get upgrade omitido (usa --upgrade-system para autorizarlo)"
    fi
}

install_packages() {
    log "Paquetes de repositorios Debian"
    apt_install build-essential git curl wget ca-certificates gnupg openssh-client \
        tar zip unzip xz-utils jq tmux tree ripgrep fd-find fzf \
        python3 python3-pip python3-venv pipx neovim vim nano zsh golang-go rustc cargo
    if ((WITH_NODESOURCE)); then
        log "Node.js LTS desde NodeSource (script descargado y ejecutado como fichero, no por tubería)"
        run_downloaded_script https://deb.nodesource.com/setup_lts.x root
        apt_install nodejs
    else
        apt_install nodejs npm
    fi
}

# Download to a temporary file, then execute it; never curl | bash.
run_downloaded_script() {
    local url=$1 as=$2 tmp
    if [[ $MODE == dry-run ]]; then
        printf '    descargar %s -> fichero temporal; ejecutar como %s\n' "$url" "$as"
        return
    fi
    tmp=$(mktemp)
    if ! curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$tmp"; then
        rm -f -- "$tmp"
        die "No se pudo descargar $url"
    fi
    if [[ $as == root ]]; then
        "${SUDO[@]}" bash "$tmp" || { rm -f -- "$tmp"; die "Falló $url"; }
    else
        bash "$tmp" "${@:3}" || { rm -f -- "$tmp"; die "Falló $url"; }
    fi
    rm -f -- "$tmp"
}

install_claude_code() {
    if (( ! WITH_CLAUDE_CODE )); then
        log "Claude Code omitido (usa --with-claude-code)"
        return
    fi
    if command -v claude >/dev/null 2>&1; then
        log "Claude Code ya instalado; no se toca"
        return
    fi
    log "Claude Code CLI (instalador oficial, usuario actual)"
    run_downloaded_script https://claude.ai/install.sh user
}

backup_path() {
    local src=$1 backup_dir=$2
    [[ -e "$src" || -L "$src" ]] || return 0
    run mkdir -p "$backup_dir"
    run cp -a -- "$src" "$backup_dir/"
}

install_dotfiles() {
    if (( ! REPLACE_DOTFILES )); then
        log "Dotfiles omitidos (usa --replace-dotfiles)"
        return
    fi
    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    if [[ ! -d $HOME/.oh-my-zsh ]]; then
        log "Oh-My-Zsh (sin cambiar shell ni .zshrc)"
        run_downloaded_script https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
            user --unattended --keep-zshrc
    fi
    local plugin
    for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
        [[ -d $zsh_custom/plugins/$plugin ]] && continue
        run git clone --depth 1 "https://github.com/zsh-users/$plugin" "$zsh_custom/plugins/$plugin"
    done

    local backup_dir
    backup_dir="$HOME/.local/state/dev-setup/backups/$(date -u +%Y%m%dT%H%M%SZ)"
    log "Copia previa de dotfiles en $backup_dir"
    backup_path "$HOME/.zshrc" "$backup_dir"
    backup_path "$HOME/.config/nvim/init.vim" "$backup_dir"
    run mkdir -p "$HOME/.config/nvim/undo"
    run install -m 0644 "$REPO_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
    run install -m 0644 "$REPO_DIR/dotfiles/init.vim" "$HOME/.config/nvim/init.vim"
}

set_shell() {
    if (( ! SET_SHELL )); then
        log "Shell de login sin cambios (usa --set-shell)"
        return
    fi
    local zsh_path
    zsh_path=$(command -v zsh || echo /usr/bin/zsh)
    run_root chsh -s "$zsh_path" "$(id -un)"
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
    log "Nombre y email de Git no se fijan aquí: usa git config --global user.name/user.email."
}

setup_ssh() {
    local key="$HOME/.ssh/id_ed25519"
    if (( ! GENERATE_SSH_KEY && ! REUSE_TERMUX_KEY )); then
        log "Clave SSH omitida (usa --generate-ssh-key o --reuse-termux-ssh-key)"
        return
    fi
    if [[ -e $key ]]; then
        log "La clave $key ya existe; no se toca"
        return
    fi
    run install -d -m 0700 "$HOME/.ssh"
    if ((REUSE_TERMUX_KEY)); then
        local src="$TERMUX_HOME/.ssh/id_ed25519"
        [[ $MODE == dry-run || -r $src ]] || die "No existe $src en Termux."
        run install -m 0600 "$src" "$key"
        run install -m 0644 "$src.pub" "$key.pub"
    else
        run ssh-keygen -t ed25519 -C "$(id -un)@android-$TARGET" -f "$key"
        log "Se pedirá una passphrase de forma interactiva; la clave privada nunca se mostrará."
    fi
}

summary() {
    log "Plan completado en modo $MODE (destino $TARGET)"
    if [[ $MODE == dry-run ]]; then
        log "No se ha modificado el sistema. Revisa el plan y usa --apply."
    else
        log "Verifica: git, python3, node, go, rustc, nvim, zsh y, si se pidió, claude."
        [[ $TARGET == avf ]] && log "Intercambio de archivos: Descargas (Android) <-> /mnt/shared."
    fi
}

main() {
    preflight
    update_packages
    install_packages
    install_claude_code
    install_dotfiles
    set_shell
    configure_git
    setup_ssh
    summary
}

main
