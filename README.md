# Entorno de Desarrollo en Android con Termux

Configura un entorno de programación completo en tu móvil Android usando [Termux](https://termux.dev).

## Instalar Termux

### Opción A — GitHub (última versión, recomendado para Pixel)

Los Pixel usan arquitectura **arm64-v8a**. Descarga el APK directamente desde las releases oficiales:

1. En tu Pixel, abre este enlace en el navegador:
   `https://github.com/termux/termux-app/releases/latest`
2. Descarga `termux-app_vX.X.X+github-debug_arm64-v8a.apk`
3. Abre el APK descargado — Android te pedirá habilitar instalación desde fuentes desconocidas
4. Activa el permiso y confirma la instalación

O con el script incluido en este repo (desde un PC/Mac con ADB):

```bash
bash install-termux.sh
```

> **Nota:** Las builds de GitHub están firmadas por el equipo de Termux pero son builds de desarrollo (`github-debug`). Son estables y actualizadas.

### Opción B — F-Droid

Instala F-Droid primero desde [f-droid.org](https://f-droid.org) y busca **Termux** dentro de la app.

### Opción C — Google Play (no recomendado)

La versión de Play Store no se actualiza desde 2020 y tiene bugs conocidos.

---

> **Importante:** Usa siempre la **misma fuente** para Termux y sus complementos (ej. Termux:API). Mezclar GitHub con Play Store causa errores de firma.

## Requisitos previos

- Android 7+ (Pixel 2 o superior funciona perfectamente)
- Al menos 1 GB de almacenamiento libre
- Termux y Termux:API de la misma fuente

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
├── setup.sh           # Script principal de instalación (se ejecuta en Termux)
├── install-termux.sh  # Descarga e instala el APK de Termux vía ADB (se ejecuta en PC/Mac)
└── dotfiles/
    ├── .zshrc         # Configuración de zsh con aliases y funciones
    └── init.vim       # Configuración de Neovim optimizada para móvil
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
