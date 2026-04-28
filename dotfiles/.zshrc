export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="agnoster"

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
alias venv='python3 -m venv .venv && source .venv/bin/activate'
alias activate='source .venv/bin/activate'

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

# ── Historial ─────────────────────────────────────────────────────────────────
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
