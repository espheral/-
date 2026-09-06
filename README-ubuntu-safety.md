# Ubuntu: ejecución segura y verificación

`setup-ubuntu.sh` funciona en modo **dry-run por defecto**. Sin `--apply` solo
comprueba el host, valida los archivos del repositorio y muestra el plan.

```bash
./setup-ubuntu.sh
./setup-ubuntu.sh --dry-run --skip-pro
./setup-ubuntu.sh --dry-run --with-docker --replace-dotfiles
```

Las acciones que requieren autorización independiente no se realizan por defecto:

- `--upgrade-system`: actualización completa de paquetes.
- `--replace-dotfiles`: copia previa y sustitución de `.zshrc` e `init.vim`.
- `--configure-git`: cambios en la configuración Git global.
- `--generate-ssh-key`: nueva clave Ed25519 con passphrase interactiva.
- `--with-docker`: repositorio oficial, paquetes y pertenencia al grupo `docker`.

Ubuntu Pro se omite con `--skip-pro`. Para un attach no interactivo se usa
`UBUNTU_PRO_TOKEN`; el token por argumento se rechaza para no dejarlo en el
historial o en la lista de procesos.

Antes de aplicar, conserva la salida del dry-run y comprueba el hostname:

```bash
hostname
./setup-ubuntu.sh --dry-run --skip-pro
```

Primera ejecución mínima recomendada en un host real:

```bash
./setup-ubuntu.sh --apply --skip-pro
```

Después verifica `git`, `python3`, `node`, `go`, `rustc`, `nvim` y `zsh`. Pro,
Docker, dotfiles, Git global, SSH y `apt-get upgrade` se prueban en recorridos
separados para que un fallo tenga causa y reversión identificables.

Prueba inocua del dry-run:

```bash
bash tests/test-setup-ubuntu-dry-run.sh
```
