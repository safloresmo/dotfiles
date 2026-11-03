#!/usr/bin/env bash
# Instala estos dotfiles en un equipo nuevo, con una línea en cualquier shell:
#   curl -fsSL https://raw.githubusercontent.com/safloresmo/dotfiles/main/bootstrap.sh | bash
# Pone git si falta, clona el repo en ~/dotfiles (o lo pone al día) y abre el instalador.
# DOTFILES_URL y DOTFILES_DIR cambian de dónde y a dónde se clona.
set -euo pipefail

principal() {
    local url="${DOTFILES_URL:-https://github.com/safloresmo/dotfiles.git}"
    local destino="${DOTFILES_DIR:-$HOME/dotfiles}" root=()
    # con curl | bash la entrada es el propio guion: las preguntas se leen de la terminal
    if { : < /dev/tty; } 2> /dev/null; then exec < /dev/tty; fi
    [[ "$(id -u)" -eq 0 ]] || root=(sudo)

    if ! command -v git > /dev/null; then
        echo "Instalo git para bajar los dotfiles."
        if command -v pacman > /dev/null; then "${root[@]}" pacman -S --needed git
        elif command -v apt-get > /dev/null; then "${root[@]}" apt-get install git
        elif command -v dnf > /dev/null; then "${root[@]}" dnf install git
        elif command -v zypper > /dev/null; then "${root[@]}" zypper install git
        else
            echo "Instala git y vuelve a correr esta línea." >&2
            exit 1
        fi
    fi

    if [[ -d "$destino/.git" ]]; then
        git -C "$destino" pull --ff-only
    else
        git clone "$url" "$destino"
    fi
    exec "$destino/install.sh" "$@"
}

# todo va en una función para que bash lea el guion entero antes de empezar
principal "$@"
