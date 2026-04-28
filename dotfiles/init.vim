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

" ── Rendimiento táctil (Android) ──────────────────────────────────────────────
set ttimeoutlen=50
set timeoutlen=1000
set mouse=a
set clipboard=unnamed

" ── Archivos ──────────────────────────────────────────────────────────────────
set nobackup
set nowritebackup
set noswapfile
set undofile
set undodir=~/.config/nvim/undo

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
