# dotfiles

[![instalador](https://github.com/safloresmo/dotfiles/actions/workflows/instalador.yml/badge.svg)](https://github.com/safloresmo/dotfiles/actions/workflows/instalador.yml)

Mi configuración de Linux, una carpeta por aplicación. Un instalador con casillas
deja elegir qué poner, enseña cómo se ve cada cosa antes de instalarla y puede
mantener el equipo al día solo.

## Instalar

Copia esta línea en tu terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/safloresmo/dotfiles/main/bootstrap.sh | bash
```

Pone git si falta, baja el repo en `~/dotfiles` y abre el instalador. Si ya lo
tenías, lo pone al día.

Para instalar unas apps directamente, sin las pantallas de elegir, añádelas al final:

```sh
curl -fsSL https://raw.githubusercontent.com/safloresmo/dotfiles/main/bootstrap.sh | bash -s -- base fastfetch animacion
```

Sin `curl`, a mano:

```sh
git clone https://github.com/safloresmo/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

## Qué trae

| App | Qué es |
|---|---|
| `base` | Fish, Git y lo básico de la terminal |
| `fastfetch` | Fastfetch con el estilo Wired y su emblema |
| `animacion` | Animación Navi al encender, al apagar y cada vez que se recarga la shell |
| `zen` | X y YouTube como apps de Zen, en su propia ventana |
| `1password` | Integración con el navegador y arranque con la sesión |
| `equicord` | Tema para Discord (Equicord); activarlo con `equilotl -install` |
| `cider` | Maku Clips: videoclips de YouTube en Cider |
| `steam` | Millennium con Material Theme |
| `vscode` | Ajustes y tema de VS Code |
| `claude-code` | Claude Code |
| `claude-desktop` | Claude de escritorio |
| `codex` | Codex de OpenAI |
| `chatgpt` | ChatGPT de escritorio |
| `opencode` | OpenCode |
| `gemini` | Gemini CLI |
| `grok` | Grok CLI (se instala desde su web) |
| `cursor` | Cursor |
| `reglas-ia` | Mis reglas para esas herramientas (solo sale con acceso a su repo privado) |
| `ryoku` | Escritorio Ryoku: Hub, barra, plugins y su paleta en las demás apps (solo sale si tienes Ryoku) |

Al final, el instalador pregunta si quieres la **actualización automática**: el
equipo baja de GitHub los cambios cada hora y los aplica.

## El instalador

```sh
./install.sh            # elige apps la primera vez; luego instala las de este equipo
./install.sh elegir     # vuelve a elegir
./install.sh base zen   # instala esas apps
./install.sh estado     # dice qué falta o qué cambió, sin tocar nada
./install.sh ayuda      # todas las órdenes
```

En la lista de apps: `espacio` marca o quita, `v` enseña cómo se ve la app,
`i` cambia entre instalar el programa o solo su configuración, `p` carga la
lista de otro equipo y `Enter` sigue.

Lo que ya tengas en tu carpeta personal no se pierde: va a `~/.dotfiles-respaldo-<fecha>`.

## Dónde funciona

Probado en Arch, Fedora, Ubuntu, Debian y openSUSE, en cada cambio. Los
programas se instalan con el gestor de tu distro (pacman, apt, dnf o zypper),
AUR o Flatpak; lo que no se encuentre se lista al final con su enlace de descarga.

- Sin systemd no hay actualización automática.
- En distros inmutables (Silverblue, Bazzite) y NixOS se enlaza la configuración,
  pero no los archivos de sistema ni la animación de arranque.
