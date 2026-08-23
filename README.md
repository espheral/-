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
├── setup.sh                 # Script principal de instalación (se ejecuta en Termux)
├── setup-debian.sh          # Instalación dentro de Debian vía proot-distro (sobre Termux)
├── setup-linux-terminal.sh  # Instalación dentro de la app "Terminal" nativa de Android (AVF)
├── install-termux.sh        # Descarga e instala el APK de Termux vía ADB (se ejecuta en PC/Mac)
└── dotfiles/
    ├── .zshrc                  # Configuración de zsh para Termux nativo
    ├── .zshrc-debian           # Configuración de zsh para Debian vía proot-distro
    ├── .zshrc-linux-terminal   # Configuración de zsh para la app Terminal nativa (AVF)
    └── init.vim                # Configuración de Neovim optimizada para móvil (se usa en los tres)
```

## Dos formas de tener Debian en el móvil

Hay dos caminos distintos para tener un Debian real en Android, y **no están
relacionados entre sí** — usa la sección que corresponda a lo que tienes instalado:

| | proot-distro (sobre Termux) | App "Terminal" nativa (AVF) |
|---|---|---|
| Qué es | Debian en un chroot dentro de Termux | VM Debian real de Google (crosvm + pKVM) |
| Requiere Termux | Sí | No — es una app aparte de Android |
| Cómo se activa | `pkg install proot-distro` en Termux | Ajustes → Opciones de desarrollador → *Linux development environment* |
| Usuario | `root` | `droid` (con `sudo`) |
| Almacenamiento compartido | `/sdcard`, y el `home` de Termux | Solo la carpeta *Descargas*, vía `/mnt/shared` |
| Script de este repo | `setup-debian.sh` | `setup-linux-terminal.sh` |

Si tu prompt se ve como `droid@debian:~$` y llegaste ahí abriendo la app
**Terminal** de Android (no Termux), estás en el segundo caso.

## Entorno Debian vía proot-distro (sobre Termux)

Termux usa su propio entorno Android (no es Debian ni ninguna distro estándar),
lo que a veces causa problemas con herramientas que esperan un Linux glibc
normal — por ejemplo, **Claude Code CLI**. Para eso, `setup.sh` puede instalar
un Debian real dentro de Termux usando [proot-distro](https://github.com/termux/proot-distro).

### Instalación

Al ejecutar `./setup.sh` se te preguntará si quieres instalarlo. También puedes
hacerlo manualmente:

```bash
pkg install -y proot-distro
proot-distro install debian
```

### Uso

```bash
proot-distro login debian    # o el alias: debian
cd /data/data/com.termux/files/home/termux-setup   # tu clon de este repo, visible desde Debian
bash setup-debian.sh
```

`setup-debian.sh` instala (vía `apt`) zsh + Oh-My-Zsh, Neovim, Python, Node.js
(NodeSource), Go, Rust, configura Git/SSH (reutiliza tu clave de Termux si ya
existe) y **Claude Code CLI**. Al terminar, dentro de tu terminal Debian puedes
ejecutar:

```bash
claude
```

> **Nota:** `/sdcard` y el `home` de Termux (`/data/data/com.termux/files/home`)
> son accesibles desde dentro de Debian, así que no necesitas re-clonar el
> repositorio ni duplicar tu clave SSH.

## Entorno Debian vía app "Terminal" nativa (AVF)

Desde Android 16, los Pixel compatibles traen una app **Terminal** que arranca
una VM Debian real usando el [Android Virtualization Framework](https://source.android.com/docs/core/virtualization)
(crosvm + pKVM) — no tiene relación con Termux. Se activa en:

```
Ajustes → Sistema → Opciones de desarrollador → Linux development environment
```

Luego abre la app **Terminal** desde el cajón de apps. Aparecerás como
`droid@debian` con `sudo` disponible.

### Instalación

La VM tiene su propia red y `git`, así que puedes clonar el repo directamente
dentro del Terminal, sin pasar por `/mnt/shared`:

```bash
sudo apt update -y && sudo apt install -y git
git clone https://github.com/espheral/- ~/termux-setup
cd ~/termux-setup
chmod +x setup-linux-terminal.sh
./setup-linux-terminal.sh
```

`setup-linux-terminal.sh` instala zsh + Oh-My-Zsh, Neovim, Python, Node.js
(NodeSource), Go, Rust, configura Git/SSH (clave nueva, propia de esta VM) y
**Claude Code CLI**. Al terminar:

```bash
claude
```

> **Nota:** el único puente de archivos con Android es la carpeta *Descargas*,
> montada dentro de la VM en `/mnt/shared` (alias `shared`). No hay acceso al
> resto del almacenamiento del teléfono, ni a Termux si también lo usas.

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

### Termux

| Problema | Solución |
|----------|----------|
| `pkg update` falla | Cambia mirror: `termux-change-repo` |
| Permisos de almacenamiento denegados | Ejecuta: `termux-setup-storage` |
| `command not found` después de instalar | Reinicia Termux por completo (cierra y abre) |
| Neovim/vim no tiene colores | Agrega `export TERM=xterm-256color` a `.zshrc` |
| Node.js/npm muy lento | Es normal en móvil; Debian vía proot-distro puede ser más rápido |
| SSH falla con "permission denied" | Verifica que `~/.ssh/id_ed25519` tenga permisos `600`: `chmod 600 ~/.ssh/id_ed25519*` |

### Linux Terminal (AVF)

| Problema | Solución |
|----------|----------|
| No aparece la app Terminal | Abre Ajustes → Opciones de desarrollador, activa *Linux development environment*, reinicia |
| `apt` falla con "Hash Sum mismatch" | Ejecuta: `sudo apt update -y && sudo apt clean` |
| No hay acceso a archivos de Android | Solo funciona `/mnt/shared` (Descargas). Copia archivos ahí con: `cp archivo /mnt/shared/` |
| "Permission denied" en home | Ejecuta: `sudo chown -R droid:droid ~` |
| Memoria insuficiente (12GB mínimo) | Cierra apps. Linux Terminal usa hasta 4GB, deja espacio libre. |
| Claude Code no funciona en git | Verifica SSH keys: `ssh-keygen -t ed25519 -C "linux-terminal"` y agrégala a GitHub |

### Ambos entornos

| Problema | Solución |
|----------|----------|
| `git clone` via SSH falla | Verifica: (1) clave SSH agregada a GitHub, (2) `ssh-keyscan github.com` en `/etc/ssh/ssh_known_hosts`, (3) permisos SSH: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/*` |
| Python: "ModuleNotFoundError" | Usa venv: `python3 -m venv .venv && source .venv/bin/activate` |
| Node: "out of memory" | Reduce tamaño del proyecto o usa `--max-old-space-size=256` en npm |
| El teclado virtual tapa el código | Usa una app de teclado con teclas de prog: **Hacker's Keyboard** o **Unexpected Keyboard** |

## Plantillas de proyecto rápido

Crea proyectos con estructura y `.gitignore` prehechos:

```bash
mkpython mi-app      # Crea estructura Python con venv
mknode mi-app        # Crea estructura Node.js con package.json
mkrust mi-app        # Crea proyecto Rust con cargo
```

Cada plantilla:
- Inicializa git
- Agrega `.gitignore` apropiado
- Crea README.md con instrucciones básicas
- (Python) crea `main.py` con ejemplo
- (Node) ejecuta `npm init -y`
- (Rust) usa `cargo new`

## Sincronizar dotfiles entre Termux y Linux Terminal

Si usas ambos entornos en el mismo Pixel:

```bash
./sync-dotfiles.sh push   # Envía tus dotfiles actuales
./sync-dotfiles.sh pull   # Trae dotfiles del otro entorno
./sync-dotfiles.sh status # Ve qué hay en cada lado
```

Archivos sincronizados: `.zshrc`, `.gitconfig`, `.config/nvim/init.vim`

(Nota: Linux Terminal solo puede acceder a archivos en `/mnt/shared` — Descargas de Android)

## Tips para programar en móvil

- **Pantalla dividida:** Usa el modo multipantalla de Android para tener el navegador y Termux a la vez.
- **Teclado externo:** Un teclado Bluetooth mejora muchísimo la experiencia.
- **Sesiones múltiples (Termux):** Desliza desde el borde izquierdo para abrir nuevas sesiones.
- **Servidor local:** Usa `python3 -m http.server 8080` para previsualizar proyectos web desde el móvil.
- **Archivos entre entornos:** Usa `/mnt/shared` (Linux Terminal) o `/sdcard` (Termux) para pasar datos.
