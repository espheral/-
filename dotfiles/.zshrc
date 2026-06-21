export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

# robbyrussell no requiere fuentes Powerline — funciona en cualquier terminal Android

# ── Rendimiento de arranque ─────────────────────────────────────────────────────
# El auto-update de Oh-My-Zsh hace red en cada inicio: lo desactivamos para que
# la shell abra al instante (actualiza manualmente con `omz update`).
zstyle ':omz:update' mode disabled
DISABLE_AUTO_UPDATE="true"
DISABLE_MAGIC_FUNCTIONS="true"   # pegar texto largo es mucho más rápido
DISABLE_UNTRACKED_FILES_DIRTY="true"  # `git status` del prompt no escanea repos enormes

plugins=(
    git
    python
    node
    colored-man-pages
    command-not-found
    zsh-autosuggestions
    zsh-syntax-highlighting
)
# Nota: zsh-syntax-highlighting DEBE ser el último plugin de la lista.

# Carga defensiva: si Oh-My-Zsh aún no está instalado, la shell sigue funcionando
[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# ── PATH ───────────────────────────────────────────────────────────────────────
# `typeset -U` evita entradas duplicadas al re-cargar el .zshrc
typeset -U path PATH
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
alias update='pkg update && pkg upgrade'
alias cb='termux-clipboard-set'    # uso: echo "texto" | cb
alias cbp='termux-clipboard-get'   # pega el portapapeles del sistema

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

# ── Servidor HTTP rápido ───────────────────────────────────────────────────────
serve() {
    local port="${1:-8080}"
    echo "Servidor en http://localhost:$port (Ctrl+C para detener)"
    python3 -m http.server "$port"
}

# ── Historial ─────────────────────────────────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS          # no guarda comandos repetidos consecutivos
setopt HIST_IGNORE_ALL_DUPS      # elimina duplicados antiguos
setopt HIST_IGNORE_SPACE         # comandos que empiezan con espacio no se guardan
setopt HIST_REDUCE_BLANKS        # limpia espacios sobrantes
setopt HIST_VERIFY               # al expandir !! muestra antes de ejecutar
setopt SHARE_HISTORY             # historial compartido entre sesiones

# ── Navegación ──────────────────────────────────────────────────────────────────
setopt AUTO_CD                   # escribir un directorio equivale a `cd` a él
setopt AUTO_PUSHD                # cada cd guarda el anterior en la pila
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS      # permite # comentarios en la línea de comandos

# ── Autosuggestions ─────────────────────────────────────────────────────────────
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20   # no sugiere en líneas muy largas (rendimiento)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
