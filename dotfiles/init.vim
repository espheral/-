" ── Opciones básicas ──────────────────────────────────────────────────────────
set nocompatible
syntax on
filetype plugin indent on

set number relativenumber
set cursorline
set wrap
set linebreak
set scrolloff=8
set sidescrolloff=8
set signcolumn=yes

" ── Indentación ───────────────────────────────────────────────────────────────
set tabstop=4
set shiftwidth=4
set expandtab
set smartindent
set autoindent

" ── Búsqueda ──────────────────────────────────────────────────────────────────
set incsearch
set hlsearch
set ignorecase
set smartcase

" ── Comportamiento ─────────────────────────────────────────────────────────────
set hidden              " cambia de buffer sin obligar a guardar
set confirm             " pregunta en vez de fallar al salir con cambios sin guardar
set splitbelow          " los splits horizontales se abren abajo
set splitright          " los verticales, a la derecha
set wildmenu            " menú visual de autocompletado en la línea de comandos
set wildmode=longest:full,full
set autoread            " recarga el archivo si cambió fuera de vim

" ── Rendimiento táctil (Android) ──────────────────────────────────────────────
set ttimeoutlen=50
set timeoutlen=1000
set updatetime=300
set mouse=a
set lazyredraw          " no redibuja durante macros: más fluido en CPU móvil
set synmaxcol=300       " no resalta sintaxis en líneas larguísimas (rendimiento)
" Portapapeles del sistema (requiere termux-api: termux-clipboard-get/set)
set clipboard=unnamedplus

" ── Archivos ──────────────────────────────────────────────────────────────────
set nobackup
set nowritebackup
set noswapfile
set undofile
set undodir=~/.config/nvim/undo
set undolevels=1000
" Crea el directorio de undo si no existe (si no, el historial no persiste)
if !isdirectory($HOME . '/.config/nvim/undo')
    call mkdir($HOME . '/.config/nvim/undo', 'p')
endif

" ── Codificación ──────────────────────────────────────────────────────────────
set encoding=utf-8
set fileencoding=utf-8

" ── Apariencia ────────────────────────────────────────────────────────────────
set termguicolors
set background=dark
set laststatus=2
set showmode
set showcmd
set ruler

" ── Atajos de teclado ─────────────────────────────────────────────────────────
let mapleader = " "

" Guardar y salir
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :x<CR>

" Limpiar búsqueda
nnoremap <leader>h :nohlsearch<CR>

" Navegación entre ventanas
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k

" Mover líneas (útil en móvil)
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Seleccionar todo
nnoremap <leader>a ggVG

" Explorador de archivos integrado
nnoremap <leader>e :Lexplore<CR>

" ── Autocomandos ──────────────────────────────────────────────────────────────
augroup termux_settings
    autocmd!
    " Eliminar espacios al final al guardar
    autocmd BufWritePre * :%s/\s\+$//e
    " Recordar posición del cursor
    autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
augroup END

" ── netrw (explorador de archivos) ────────────────────────────────────────────
let g:netrw_banner    = 0
let g:netrw_liststyle = 3
let g:netrw_winsize   = 25
