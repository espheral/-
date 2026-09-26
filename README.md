# Entorno de Desarrollo: Ubuntu + Termux

Scripts para montar un entorno de programación reproducible en:

| Plataforma | Script | Notas |
|------------|--------|-------|
| **Ubuntu** (escritorio, servidor o WSL2) | `setup-ubuntu.sh` | Incluye adjuntar **Ubuntu Pro** (plan personal gratuito) |
| **Android** (Pixel u otro) | `setup.sh` | Se ejecuta dentro de [Termux](https://termux.dev) |

Ambos comparten los mismos dotfiles (`dotfiles/.zshrc`, `dotfiles/init.vim`), que detectan la plataforma en tiempo de carga.

---

## Ubuntu (escritorio / servidor / WSL2)

### Instalación

```bash
sudo apt install -y git
git clone https://github.com/espheral/- ~/dev-setup
cd ~/dev-setup
chmod +x setup-ubuntu.sh

# Inspección segura: es el modo predeterminado y no modifica el sistema
./setup-ubuntu.sh
./setup-ubuntu.sh --dry-run --skip-pro
./setup-ubuntu.sh --dry-run --with-docker --replace-dotfiles

# Aplicación mínima tras revisar el plan
./setup-ubuntu.sh --apply --skip-pro

# Las operaciones de mayor alcance requieren opciones expresas:
# --upgrade-system, --replace-dotfiles, --configure-git,
# --generate-ssh-key y --with-docker
```

Para un attach no interactivo puede usarse `UBUNTU_PRO_TOKEN`; el script rechaza tokens por argumento para que no queden en el historial o la lista de procesos. Consulta [la guía de ejecución segura](README-ubuntu-safety.md).

El script instala:

| Categoría | Herramientas |
|-----------|-------------|
| Base | build-essential, git, curl, wget, gnupg, jq, htop, tmux, tree, ripgrep, fd, fzf, bat |
| Shell | zsh, Oh-My-Zsh, autosuggestions, syntax-highlighting |
| Editores | Neovim, Vim, Nano |
| Lenguajes | Python 3 (+ venv, pipx), Node.js/npm, Go y Rust/Cargo desde los repositorios de Ubuntu, clang/cmake |
| Git | configuración global y clave SSH solo con opciones expresas |
| Ubuntu Pro | cliente `pro`, attach, esm-infra, esm-apps, livepatch y usg; se omite con `--skip-pro` |
| Opcional | Docker Engine + compose plugin (`--with-docker`) |

### Ubuntu Pro: qué es y qué activa el script

Ubuntu Pro es **gratuito para uso personal en hasta 5 máquinas** (cuenta de Ubuntu One). No incluye soporte telefónico/ticket; todo lo demás sí.
Solo funciona en versiones **LTS** (20.04, 22.04, 24.04).

| Servicio | ¿Lo activa el script? | Qué aporta |
|----------|:---------------------:|------------|
| `esm-infra` | Sí | Parches de seguridad para `main` hasta 10 años (12 con Legacy) |
| `esm-apps` | Sí | Parches de seguridad para `universe` (~23.000 paquetes extra) |
| `livepatch` | Sí, salvo WSL/contenedor | Parches de kernel sin reiniciar. Requiere kernel de Canonical + snapd |
| `usg` | Sí | Herramienta `usg` para auditar/aplicar CIS y DISA-STIG. **Solo instala la herramienta**, no endurece nada |
| `fips`, `fips-updates` | No | Kernel y libs certificadas FIPS 140. Sustituye el kernel; solo si lo exiges por cumplimiento |
| `realtime-kernel` | No | Kernel PREEMPT_RT. Sustituye el kernel; solo para cargas de tiempo real |
| `landscape` | No | Cliente de gestión de flota. Landscape SaaS está incluido en Pro, pero requiere configuración propia |
| `anbox-cloud`, `ros` | No | Casos de uso específicos |

Además desactiva los avisos comerciales de apt (`pro config set apt_news=false`) salvo que uses `--keep-apt-news`.

### Verificación

```bash
pro status                      # attached: yes, servicios enabled/disabled
pro security-status             # cuántos paquetes cubre esm-infra / esm-apps
pro security-status --esm-apps  # detalle de universe
sudo pro fix CVE-2024-XXXX      # aplicar el parche de un CVE concreto
canonical-livepatch status      # solo si livepatch está activo
sudo usg audit cis_level1_workstation   # auditoría CIS (no modifica nada)
```

Alias disponibles tras el setup: `pro-status`, `pro-sec`, `pro-fix`, `up` (update+upgrade), `winhome` (solo WSL).

### Notas para WSL2

- `pro attach` y ESM funcionan igual que en un Ubuntu nativo. **Livepatch no aplica**: el kernel lo pone Microsoft, no Canonical. El script lo detecta y lo omite.
- Cada instancia WSL cuenta como **una máquina** de las 5 del plan gratuito. Para liberar una: `sudo pro detach` antes de destruirla, o desde el dashboard web.
- Docker en WSL2 requiere systemd: en `/etc/wsl.conf` añade la sección `[boot]` con `systemd=true` y luego ejecuta `wsl --shutdown` desde PowerShell.

### Gestión de máquinas adjuntas

```bash
sudo pro detach                 # libera esta máquina del plan
sudo pro disable livepatch      # desactivar un servicio concreto
sudo pro refresh                # refrescar contrato/config tras cambios en el dashboard
```

Las máquinas adjuntas se ven y se eliminan en https://ubuntu.com/pro/dashboard.

---

## Android con Termux

### Instalar Termux

#### Opción A — GitHub (última versión, recomendado para Pixel)

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

#### Opción B — F-Droid

Instala F-Droid primero desde [f-droid.org](https://f-droid.org) y busca **Termux** dentro de la app.

#### Opción C — Google Play (no recomendado)

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
├── setup-ubuntu.sh          # Ubuntu (escritorio/servidor/WSL2) + Ubuntu Pro; dry-run por defecto
├── setup.sh                 # Instalación en Termux (Android)
├── setup-debian.sh          # Debian en Android: proot-distro o app Terminal (AVF); dry-run por defecto
├── setup-linux-terminal.sh  # Atajo de setup-debian.sh --target avf
├── sync-dotfiles.sh         # Sincroniza dotfiles entre Termux, proot y AVF vía Descargas
├── install-termux.sh        # Descarga e instala el APK de Termux vía ADB (se ejecuta en PC/Mac)
├── tests/                   # Pruebas de no mutación de los dry-run (CI)
└── dotfiles/
    ├── .zshrc               # zsh único; detecta Termux, proot, AVF y Ubuntu/Debian
    └── init.vim             # Configuración de Neovim
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
bash setup-debian.sh                                # dry-run: solo muestra el plan
bash setup-debian.sh --apply --replace-dotfiles --set-shell --with-claude-code
```

Sin opciones, `setup-debian.sh` instala solo paquetes de Debian (`apt`): Neovim,
Python + pipx, Node.js, Go, Rust, zsh. Cada cambio persistente requiere su
opción (ver `--help`): `--replace-dotfiles` (con copia previa; instala
Oh-My-Zsh), `--set-shell`, `--configure-git`, `--generate-ssh-key` (con
passphrase) o `--reuse-termux-ssh-key`, `--with-nodesource`,
`--with-claude-code` y `--upgrade-system`. Los instaladores remotos se descargan
a un fichero temporal antes de ejecutarse (nunca `curl | bash`). Al terminar:

```bash
claude
```

> **Nota:** `/sdcard` y el `home` de Termux (`/data/data/com.termux/files/home`)
> son accesibles desde dentro de Debian, así que no necesitas re-clonar el
> repositorio. Para reutilizar la clave SSH de Termux, pásalo explícitamente
> con `--reuse-termux-ssh-key`.

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
bash setup-linux-terminal.sh         # dry-run
bash setup-linux-terminal.sh --apply --replace-dotfiles --set-shell \
    --generate-ssh-key --with-claude-code
```

`setup-linux-terminal.sh` equivale a `setup-debian.sh --target avf` (mismas
opciones). Debe ejecutarse como `droid`; con `--apply` rechaza root. Al terminar:

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

# Backup de dotfiles (/sdcard en Termux/proot, /mnt/shared en AVF, ~ en el resto)
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
| Claude Code no funciona en git | Crea clave con `bash setup-linux-terminal.sh --apply --generate-ssh-key` y agrégala a GitHub |

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
bash sync-dotfiles.sh status # Compara local y carpeta compartida
bash sync-dotfiles.sh push   # Envía tus dotfiles actuales
bash sync-dotfiles.sh pull   # Trae dotfiles (copia previa de los locales que difieran)
```

Archivos sincronizados: `.zshrc`, `.gitconfig`, `.config/nvim/init.vim`. Nunca
claves SSH. Carpeta común: Descargas de Android (`/sdcard/Download/.dotfiles-sync`
en Termux/proot = `/mnt/shared/.dotfiles-sync` en AVF). Es legible por otras apps
con permiso de almacenamiento.

## Tips para programar en móvil

- **Pantalla dividida:** Usa el modo multipantalla de Android para tener el navegador y Termux a la vez.
- **Teclado externo:** Un teclado Bluetooth mejora muchísimo la experiencia.
- **Sesiones múltiples (Termux):** Desliza desde el borde izquierdo para abrir nuevas sesiones.
- **Servidor local:** Usa `python3 -m http.server 8080` para previsualizar proyectos web desde el móvil.
- **Archivos entre entornos:** Usa `/mnt/shared` (Linux Terminal) o `/sdcard` (Termux) para pasar datos.
