# Entorno de Desarrollo en Android con Termux

Configura un entorno de programación completo en tu móvil Android usando [Termux](https://termux.dev).

## Requisitos previos

1. Instala **Termux** desde [F-Droid](https://f-droid.org/packages/com.termux/) (recomendado) o Google Play.
2. Instala **Termux:API** desde el mismo origen que Termux.
3. Android 7+ con al menos 2 GB de RAM libre.

> **Importante:** Usa siempre la misma fuente (F-Droid o Play Store) para Termux y sus complementos. Mezclarlos causa errores.

## Instalación rápida

```bash
# 1. Clona el repositorio
pkg install -y git
git clone https://github.com/espheral/- ~/termux-setup
cd ~/termux-setup

# 2. Da permisos de ejecución y ejecuta
chmod +x setup.sh
./setup.sh
```

El script instala y configura automáticamente:

| Categoría | Herramientas |
|-----------|-------------|
| Shell | zsh, Oh-My-Zsh, autosuggestions, syntax-highlighting |
| Editores | Neovim, Vim, Nano |
| Lenguajes | Python 3, Node.js, Go, Rust, C/C++ |
| Git | git + configuración global + clave SSH |
| Utilidades | curl, wget, openssh, tar, zip, termux-api |

## Estructura del repositorio

```
.
├── setup.sh          # Script principal de instalación
└── dotfiles/
    ├── .zshrc        # Configuración de zsh con aliases y funciones
    └── init.vim      # Configuración de Neovim optimizada para móvil
```

## Uso post-instalación

### Comandos útiles

```bash
# Crear un proyecto nuevo con git inicializado
mkproject mi-app

# Activar entorno virtual Python
venv            # crea .venv y lo activa
activate        # activa .venv ya existente

# Ir al almacenamiento del teléfono
storage         # cd /sdcard

# Backup de dotfiles a /sdcard
backup_dotfiles
```

### Aliases de Git

```bash
gs   # git status
ga   # git add
gc   # git commit
gp   # git push
gl   # git log --oneline --graph
gd   # git diff
gco  # git checkout
gb   # git branch
```

### Atajos en Neovim

| Atajo | Acción |
|-------|--------|
| `Space + w` | Guardar |
| `Space + q` | Salir |
| `Space + e` | Explorador de archivos |
| `Space + h` | Limpiar búsqueda |
| `Ctrl + h/j/k/l` | Navegar entre paneles |
| `Space + a` | Seleccionar todo |

## Agregar clave SSH a GitHub/GitLab

Después de ejecutar el setup, tu clave pública se muestra en pantalla. También puedes verla con:

```bash
cat ~/.ssh/id_ed25519.pub
```

Cópiala y agrégala en:
- **GitHub:** Settings → SSH and GPG keys → New SSH key
- **GitLab:** Preferences → SSH Keys

## Solución de problemas

### `pkg update` falla
```bash
termux-change-repo   # cambia el mirror
```

### Permisos de almacenamiento denegados
```bash
termux-setup-storage
```

### Neovim no muestra colores
Agrega esto a tu `.zshrc`:
```bash
export TERM=xterm-256color
```

### El teclado virtual tapa el código
Usa una app de teclado con teclas de programación como **Hacker's Keyboard** o **Unexpected Keyboard**.

## Tips para programar en móvil

- **Pantalla dividida:** Usa el modo multipantalla de Android para tener el navegador y Termux a la vez.
- **Teclado externo:** Un teclado Bluetooth mejora muchísimo la experiencia.
- **Sesiones múltiples:** Desliza desde el borde izquierdo en Termux para abrir nuevas sesiones.
- **Servidor local:** Usa `python3 -m http.server 8080` para previsualizar proyectos web desde el móvil.
