#!/usr/bin/env bash
# Pone estos dotfiles en ~. Cada carpeta del repo es una aplicación: su contenido
# es un espejo de ~ y se enlaza con GNU Stow. Lo que empieza por _ no se enlaza:
#   _copias/ y _copias.txt   lo que se copia porque no puede ser un enlace
#   _repos.txt               proyectos con repo propio que la app necesita
#   _sistema/                archivos de fuera de ~ (se instalan con sudo)
# _<equipo>/apps.txt dice qué apps lleva cada equipo; junto a él van
# paquetes-motivos.txt y las listas de paquetes de pacman.
#
#   ./install.sh [apps]           enlaza y copia; lo que estorba va a ~/.dotfiles-respaldo-<fecha>
#   ./install.sh adoptar [apps]   en un equipo ya configurado: se queda con lo que hay en ~
#   ./install.sh estado [apps]    qué falta, qué enlace fue sustituido y qué copia difiere
#   ./install.sh recoger [apps]   trae al repo las copias y los archivos que sustituyeron a su enlace
#
# Sin decir apps se usan las de _<equipo>/apps.txt.
set -euo pipefail

repo="$(dirname "$(readlink -f "$0")")"
equipo="$repo/_$(uname -n)"
respaldo="$HOME/.dotfiles-respaldo-$(date +%F-%H%M%S)"

apps_de_este_equipo() {
    [[ -f "$equipo/apps.txt" ]] || { echo "falta $equipo/apps.txt" >&2; exit 1; }
    grep -Ev '^[[:space:]]*(#|$)' "$equipo/apps.txt" | awk '{print $1}'
}

enlazables() { # app -> rutas que van enlazadas, relativas a ~
    (cd "$repo/$1" && find . -mindepth 1 -path './_*' -prune -o \( -type f -o -type l \) -print) |
        sed 's|^\./||' | grep -v '^\.stow-local-ignore$' | sort
}

copias() { # app -> rutas de su _copias.txt
    [[ -f "$repo/$1/_copias.txt" ]] || return 0
    grep -Ev '^[[:space:]]*(#|$)' "$repo/$1/_copias.txt" || true
}

enlazado() { [[ "$(readlink -f "$HOME/$2")" == "$(readlink -f "$repo/$1/$2")" ]]; }

apartar() { # ruta relativa a ~ -> al respaldo
    mkdir -p "$respaldo/$(dirname "$1")"
    mv "$HOME/$1" "$respaldo/$1"
    echo "apartado: ~/$1"
}

enlazar() { # app, "adoptar" para que gane lo que hay en ~
    local app="$1" ruta opciones=(--no-folding)
    [[ "$2" == adoptar ]] && opciones+=(--adopt)
    while read -r ruta; do
        enlazado "$app" "$ruta" && continue
        [[ -e "$HOME/$ruta" || -L "$HOME/$ruta" ]] || continue
        # con --adopt, stow se lleva al repo los archivos normales y los enlaza uno a uno
        [[ "$2" == adoptar && -f "$HOME/$ruta" && ! -L "$HOME/$ruta" ]] && continue
        apartar "$ruta"
    done < <(enlazables "$app")
    stow --dir="$repo" --target="$HOME" "${opciones[@]}" --stow "$app"
}

copiar() { # app: del repo a ~; si pisa algo distinto, lo de antes va al respaldo
    local ruta padre
    while read -r ruta; do
        ruta="${ruta%/}"
        padre="$(dirname "$ruta")"
        if [[ -e "$HOME/$ruta" ]] && ! diff -rq "$repo/$1/_copias/$ruta" "$HOME/$ruta" > /dev/null 2>&1; then
            mkdir -p "$respaldo/$padre"
            cp -a "$HOME/$ruta" "$respaldo/$padre/"
            echo "respaldado: ~/$ruta"
        fi
        mkdir -p "$HOME/$padre"
        cp -a "$repo/$1/_copias/$ruta" "$HOME/$padre/"
    done < <(copias "$1")
}

recoger_copias() { # app: de ~ al repo, sustituyendo lo guardado
    local ruta
    while read -r ruta; do
        ruta="${ruta%/}"
        [[ -n "$ruta" ]] || continue
        if [[ ! -e "$HOME/$ruta" && ! -L "$HOME/$ruta" ]]; then
            echo "no existe, se omite: ~/$ruta" >&2
            continue
        fi
        rm -rf "$repo/$1/_copias/$ruta"
        mkdir -p "$repo/$1/_copias/$(dirname "$ruta")"
        cp -a "$HOME/$ruta" "$repo/$1/_copias/$(dirname "$ruta")/"
    done < <(copias "$1")
}

repos() { # app, "clonar" o "avisar": líneas "ruta url" de _repos.txt
    [[ -f "$repo/$1/_repos.txt" ]] || return 0
    local ruta url
    while read -r ruta url; do
        [[ -z "$ruta" || "$ruta" == \#* || -d "$HOME/$ruta" ]] && continue
        if [[ "$2" == clonar ]]; then
            git clone "$url" "$HOME/$ruta" || echo "no se pudo clonar $url" >&2
        else
            echo "falta el repo: ~/$ruta ($url)"
        fi
    done < "$repo/$1/_repos.txt"
}

# Archivos de fuera de ~: solo se dice cuáles difieren y cómo instalarlos.
sistema() { # app
    [[ -d "$repo/$1/_sistema" ]] || return 0
    local archivo destino
    while IFS= read -r archivo; do
        destino="/${archivo#"$repo/$1/_sistema/"}"
        cmp -s "$archivo" "$destino" 2> /dev/null && continue
        echo "$1, sistema falta o difiere: sudo install -Dm$(stat -c %a "$archivo") -o root -g root '$archivo' '$destino'"
    done < <(find "$repo/$1/_sistema" -type f | sort)
}

instalar() { # "" o "adoptar"; usa $elegidos
    command -v stow > /dev/null || { echo "falta GNU Stow (paquete stow)" >&2; exit 1; }
    mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share"
    local app
    for app in "${elegidos[@]}"; do
        enlazar "$app" "$1"
        if [[ "$1" == adoptar ]]; then recoger_copias "$app"; else copiar "$app"; fi
        repos "$app" clonar
        sistema "$app"
    done
    if command -v systemctl > /dev/null; then systemctl --user daemon-reload 2> /dev/null || true; fi
    [[ -d "$respaldo" ]] && echo "lo apartado quedó en $respaldo"
    return 0
}

sin_motivo() { # lo instalado a mano que ni venía con el sistema ni tiene motivo anotado
    local base="$equipo/paquetes-base.txt" motivos="$equipo/paquetes-motivos.txt" nombre
    [[ -f "$base" ]] && command -v pacman > /dev/null || return 0
    while read -r nombre; do
        echo "instalado sin motivo: $nombre"
    done < <(pacman -Qqe | grep -Fvxf "$base" |
        grep -Fvxf <(grep -Ev '^[[:space:]]*(#|$)' "$motivos" 2> /dev/null | awk '{print $1}') || true)
}

estado() {
    local app ruta
    for app in "${elegidos[@]}"; do
        while read -r ruta; do
            enlazado "$app" "$ruta" && continue
            if [[ -e "$HOME/$ruta" || -L "$HOME/$ruta" ]]; then
                echo "$app, sustituido: ~/$ruta"
            else
                echo "$app, falta: ~/$ruta"
            fi
        done < <(enlazables "$app")
        while read -r ruta; do
            diff -rq "$repo/$app/_copias/${ruta%/}" "$HOME/${ruta%/}" > /dev/null 2>&1 ||
                echo "$app, copia distinta: ~/$ruta"
        done < <(copias "$app")
        repos "$app" avisar
        sistema "$app"
    done
    sin_motivo
    return 0
}

recoger() {
    command -v stow > /dev/null || { echo "falta GNU Stow (paquete stow)" >&2; exit 1; }
    local app
    for app in "${elegidos[@]}"; do
        enlazar "$app" adoptar
        recoger_copias "$app"
    done
    if [[ -d "$equipo" ]] && command -v pacman > /dev/null; then
        pacman -Qqen > "$equipo/paquetes-repos.txt"
        pacman -Qqem > "$equipo/paquetes-aur.txt"
    fi
    git -C "$repo" status --short 2> /dev/null || true
}

orden=instalar
case "${1:-}" in
    adoptar | estado | recoger) orden="$1"; shift ;;
    -h | --help | ayuda) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
if (( $# > 0 )); then elegidos=("$@"); else mapfile -t elegidos < <(apps_de_este_equipo); fi
for app in "${elegidos[@]}"; do
    [[ "$app" != _* && -d "$repo/$app" ]] || { echo "no hay app '$app' en $repo" >&2; exit 1; }
done

case "$orden" in
    instalar) instalar "" ;;
    adoptar) instalar adoptar ;;
    estado) estado ;;
    recoger) recoger ;;
esac
