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

# ── Termux específico ──────────────────────────────────────────────────────────
alias pkg-list='pkg list-installed'
alias storage='cd /sdcard'
alias home='cd ~'

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

# ── Función: backup dotfiles ────────────────────────────────────────────────────
backup_dotfiles() {
    local dest="/sdcard/termux-backup-$(date +%Y%m%d)"
    mkdir -p "$dest"
    cp ~/.zshrc "$dest/" 2>/dev/null
    cp ~/.config/nvim/init.vim "$dest/" 2>/dev/null
    cp ~/.gitconfig "$dest/" 2>/dev/null
    echo "Backup guardado en $dest"
}

# ── Servidor HTTP rápido ───────────────────────────────────────────────────────
serve() {
    local port="${1:-8080}"
    echo "Servidor en http://localhost:$port (Ctrl+C para detener)"
    python3 -m http.server "$port"
}

# ── Historial ─────────────────────────────────────────────────────────────────
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
