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

# Opción 1: magic attach (interactivo, sin token; te dará un código para https://ubuntu.com/pro/attach)
./setup-ubuntu.sh

# Opción 2: con token (no interactivo). Token en https://ubuntu.com/pro/dashboard
./setup-ubuntu.sh --token C1xxxxxxxxxxxxxxxxxxxxxx

# Opciones adicionales
./setup-ubuntu.sh --with-docker      # Docker Engine desde el repo oficial
./setup-ubuntu.sh --skip-pro         # no tocar Ubuntu Pro
./setup-ubuntu.sh --keep-apt-news    # no desactivar los avisos comerciales de apt
```

Variables de entorno equivalentes: `UBUNTU_PRO_TOKEN`, `WITH_DOCKER=1`, `SKIP_PRO=1`.

El script instala:

| Categoría | Herramientas |
|-----------|-------------|
| Base | build-essential, git, curl, wget, gnupg, jq, htop, tmux, tree, ripgrep, fd, fzf, bat |
| Shell | zsh, Oh-My-Zsh, autosuggestions, syntax-highlighting |
| Editores | Neovim, Vim, Nano |
| Lenguajes | Python 3 (+ venv, pipx), Node.js 22 LTS (NodeSource), Go (apt), Rust (rustup), clang/cmake |
| Git | configuración global + clave SSH Ed25519 |
| Ubuntu Pro | cliente `pro`, attach, esm-infra, esm-apps, livepatch, usg |
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
├── setup-ubuntu.sh    # Instalación en Ubuntu (escritorio/servidor/WSL2) + Ubuntu Pro
├── setup.sh           # Instalación en Termux (Android)
├── install-termux.sh  # Descarga e instala el APK de Termux vía ADB (se ejecuta en PC/Mac)
└── dotfiles/
    ├── .zshrc         # Configuración de zsh compartida; detecta Termux vs Ubuntu
    └── init.vim       # Configuración de Neovim
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

# Backup de dotfiles (a /sdcard en Termux, a ~/dotfiles-backup-* en Ubuntu)
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
