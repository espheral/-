export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

# robbyrussell no requiere fuentes Powerline — funciona en cualquier terminal Android

plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    python
    node
    colored-man-pages
    command-not-found
)

source "$ZSH/oh-my-zsh.sh"

# ── PATH ───────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

# ── Editor ─────────────────────────────────────────────────────────────────────
export EDITOR=nvim
export VISUAL=nvim
export TERM=xterm-256color

# ── Aliases generales ──────────────────────────────────────────────────────────
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -I'

# ── Aliases git ────────────────────────────────────────────────────────────────
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# ── Aliases editor ─────────────────────────────────────────────────────────────
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# ── Python ─────────────────────────────────────────────────────────────────────
alias py='python3'
alias pip='pip3'

venv() {
    python3 -m venv .venv
    source .venv/bin/activate
    echo "Entorno virtual activado. Usa 'deactivate' para salir."
}

activate() {
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    elif [ -d "venv" ]; then
        source venv/bin/activate
    else
        echo "No se encontró entorno virtual (.venv o venv)."
        return 1
    fi
}

# ── Node ───────────────────────────────────────────────────────────────────────
alias ni='npm install'
alias nr='npm run'
alias nd='npm run dev'
alias nb='npm run build'

# ── Específico por plataforma ─────────────────────────────────────────────────
# Orden relevante: AVF y proot-distro también son Debian; Termux nativo no tiene
# /etc/debian_version (su /etc vive en $PREFIX/etc).
alias home='cd ~'

if [ -f /etc/debian_version ] && [ -d /mnt/shared ]; then
    # App "Terminal" nativa de Android (AVF, usuario droid)
    DEV_PLATFORM=avf
    alias shared='cd /mnt/shared'   # carpeta Descargas de Android
    alias up='sudo apt update && sudo apt upgrade -y'
    alias pkg-list='apt list --installed 2>/dev/null'
elif [ -f /etc/debian_version ] && [ -d /data/data/com.termux/files/home ]; then
    # Debian vía proot-distro sobre Termux
    DEV_PLATFORM=proot
    alias storage='cd /sdcard'
    alias termux='cd /data/data/com.termux/files/home'
    alias up='apt update && apt upgrade -y'
    alias pkg-list='apt list --installed 2>/dev/null'
elif [ -n "$TERMUX_VERSION" ] || [ -d /data/data/com.termux ]; then
    # Termux (Android)
    DEV_PLATFORM=termux
    alias pkg-list='pkg list-installed'
    alias storage='cd /sdcard'
    alias up='pkg update && pkg upgrade -y'
    command -v proot-distro >/dev/null 2>&1 && alias debian='proot-distro login debian'
elif command -v apt-get >/dev/null 2>&1; then
    # Ubuntu / Debian
    DEV_PLATFORM=apt
    alias up='sudo apt update && sudo apt upgrade -y'
    alias pkg-list='apt list --installed 2>/dev/null'
    command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'
    command -v batcat >/dev/null 2>&1 && alias bat='batcat'
    if command -v pro >/dev/null 2>&1; then
        # Ubuntu Pro
        alias pro-status='pro status'
        alias pro-sec='pro security-status'
        alias pro-fix='sudo pro fix'          # pro-fix CVE-2024-XXXX
    fi
    grep -qi microsoft /proc/version 2>/dev/null && alias winhome='cd /mnt/c/Users'
else
    DEV_PLATFORM=other
fi
export DEV_PLATFORM

# ── Función: crear proyecto rápido ─────────────────────────────────────────────
mkproject() {
    if [ -z "$1" ]; then
        echo "Uso: mkproject <nombre>"
        return 1
    fi
    if [ -e "$1" ]; then
        echo "Error: '$1' ya existe."
        return 1
    fi
    mkdir -p "$1" && cd "$1" && git init
    echo "# $1" > README.md
    echo "Proyecto '$1' creado."
}

# ── Plantillas de proyecto ─────────────────────────────────────────────────────
mkpython() {
    [ -n "$1" ] || { echo "Uso: mkpython <nombre>"; return 1; }
    [ ! -e "$1" ] || { echo "Error: '$1' ya existe"; return 1; }
    mkdir -p "$1" && cd "$1"
    git init
    cat > .gitignore <<EOF
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/
dist/
build/
.pytest_cache/
.mypy_cache/
EOF
    cat > README.md <<EOF
# $1

Python project.

## Setup

\`\`\`bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
\`\`\`

## Run

\`\`\`bash
python3 main.py
\`\`\`
EOF
    : > requirements.txt
    printf '#!/usr/bin/env python3\n\nif __name__ == "__main__":\n    print("Hello from %s")\n' "$1" > main.py
    git add .
    echo "✓ Proyecto Python '$1' creado"
}

mknode() {
    [ -n "$1" ] || { echo "Uso: mknode <nombre>"; return 1; }
    [ ! -e "$1" ] || { echo "Error: '$1' ya existe"; return 1; }
    mkdir -p "$1" && cd "$1"
    git init
    npm init -y >/dev/null 2>&1
    cat > .gitignore <<EOF
node_modules/
dist/
build/
*.log
.env
.DS_Store
EOF
    cat > README.md <<EOF
# $1

Node.js project.

## Setup

\`\`\`bash
npm install
\`\`\`

## Dev

\`\`\`bash
npm run dev
\`\`\`

## Build

\`\`\`bash
npm run build
\`\`\`
EOF
    git add .
    echo "✓ Proyecto Node '$1' creado"
}

mkrust() {
    [ -n "$1" ] || { echo "Uso: mkrust <nombre>"; return 1; }
    [ ! -e "$1" ] || { echo "Error: '$1' ya existe"; return 1; }
    if ! command -v cargo &>/dev/null; then
        echo "Error: Rust/cargo no instalado"
        return 1
    fi
    cargo new "$1" --name "$(echo "$1" | tr - _)"
    cd "$1"
    echo "✓ Proyecto Rust '$1' creado"
}

# ── Función: backup dotfiles ────────────────────────────────────────────────────
backup_dotfiles() {
    local dest stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    case "$DEV_PLATFORM" in
        avf)          dest="/mnt/shared/dotfiles-backup-$stamp" ;;   # visible en Descargas
        termux|proot) dest="/sdcard/dotfiles-backup-$stamp" ;;
        *)            dest="$HOME/dotfiles-backup-$stamp" ;;
    esac
    mkdir -p "$dest" || return 1
    cp ~/.zshrc "$dest/" 2>/dev/null
    cp ~/.config/nvim/init.vim "$dest/" 2>/dev/null
    cp ~/.gitconfig "$dest/" 2>/dev/null
    echo "Backup guardado en $dest"
}

# ── Servidor HTTP rápido ───────────────────────────────────────────────────────
serve() {
    local port="${1:-8080}"
    echo "Servidor en http://localhost:$port (Ctrl+C para detener)"
    # --bind 127.0.0.1 evita exponer el filesystem a otras apps/dispositivos en la red local
    python3 -m http.server "$port" --bind 127.0.0.1
}

# ── Historial ─────────────────────────────────────────────────────────────────
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE   # comandos con espacio inicial no se guardan (útil para tokens)
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
