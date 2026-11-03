#!/usr/bin/env bash
# Pone estos dotfiles en ~. Cada carpeta del repo es una aplicación: su contenido
# es un espejo de ~ y se enlaza con GNU Stow. Lo que empieza por _ no se enlaza:
#   _copias/ y _copias.txt   lo que se copia porque no puede ser un enlace
#   _repos.txt               proyectos con repo propio que la app necesita
#   _enlaces.txt             enlaces dentro de ~ ("ruta destino"), p. ej. hacia un repo clonado
#   _sistema/                archivos de fuera de ~ (se instalan con sudo); también en _<equipo>/
#   _descripcion             una línea que se ve al elegir apps
#   _requiere                lo que la app necesita: comando, flatpak:<id> o /ruta, y su paquete
#   _solo-si                 la app solo se ofrece si esto existe (comando o /ruta), p. ej. ryoku
#   _vista                   lo que enseña la tecla v al elegir apps (se corre desde su carpeta)
# _<equipo>/apps.txt dice qué apps lleva cada equipo; junto a él van
# paquetes-motivos.txt, las listas de paquetes de pacman y las apps que solo
# sirven en ese equipo (una carpeta con _descripcion). _logo/ es el banner.
#
#   ./install.sh [apps]           enlaza, copia e instala _sistema; lo que estorba va a ~/.dotfiles-respaldo-<fecha>
#   ./install.sh elegir           marca en una lista las apps de este equipo y las instala
#   ./install.sh adoptar [apps]   en un equipo ya configurado: se queda con lo que hay en ~
#   ./install.sh estado [apps]    qué falta, qué enlace fue sustituido y qué copia difiere
#   ./install.sh recoger [apps]   trae al repo las copias y los archivos que sustituyeron a su enlace
#   ./install.sh quitar apps      deshace sus enlaces y las saca de _<equipo>/apps.txt
#   ./install.sh actualizar       sin preguntar ni sudo, tras un git pull (lo usa la app sincronizar)
#
# Sin decir apps se usan las de _<equipo>/apps.txt; si el equipo no tiene, se eligen.
set -euo pipefail

repo="$(dirname "$(readlink -f "$0")")"
nombre_equipo="${DOTFILES_EQUIPO:-$(uname -n)}"
equipo="$repo/_$nombre_equipo"
respaldo="$HOME/.dotfiles-respaldo-$(date +%F-%H%M%S)"

ruta_app() { # nombre -> carpeta relativa al repo; las de este equipo ganan
    if [[ "$1" != _* && -f "$equipo/$1/_descripcion" ]]; then
        echo "_$nombre_equipo/$1"
    else
        echo "$1"
    fi
}

apps_de_este_equipo() {
    [[ -f "$equipo/apps.txt" ]] || return 0
    local app
    while read -r app; do ruta_app "$app"; done < <(grep -Ev '^[[:space:]]*(#|$)' "$equipo/apps.txt" | awk '{print $1}')
}

categorias=(Terminal Seguridad Navegador Comunicación Música Juegos Desarrollo Escritorio)

categoria_de() { # app -> su categoría; las de la carpeta del equipo van juntas
    if [[ "$1" == _* ]]; then
        echo "Este equipo"
    else
        head -n1 "$repo/$1/_categoria" 2> /dev/null || echo "Otras"
    fi
}

apps_del_repo() { # por categoría y nombre; base primero y las del equipo al final
    local dir orden c i
    {
        for dir in "$repo"/*/ "$equipo"/*/; do
            [[ -d "$dir" ]] || continue
            dir="${dir%/}"
            if [[ "$dir" == "$equipo"/* ]]; then
                [[ -f "$dir/_descripcion" ]] || continue
                dir="_$nombre_equipo/$(basename "$dir")"
            else
                dir="$(basename "$dir")"
                # sincronizar no es una app: se ofrece como paso, «actualización automática»
                [[ "$dir" == _* || "$dir" == rices || "$dir" == sincronizar ]] && continue
                # una app de un sistema concreto (ryoku) solo sale donde ese sistema está
                [[ -f "$repo/$dir/_solo-si" ]] && ! hay "$(head -n1 "$repo/$dir/_solo-si")" && continue
            fi
            c="$(categoria_de "$dir")" orden=50
            for i in "${!categorias[@]}"; do [[ "${categorias[i]}" == "$c" ]] && orden=$(( i + 10 )); done
            [[ "$c" == "Este equipo" ]] && orden=99
            [[ "$dir" == base ]] && orden=0
            printf '%02d\t%s\t%s\n' "$orden" "$c" "$dir"
        done
    } | sort -t$'\t' -k1,1 -k2,2 -k3,3 | cut -f3
}

# --- pantalla -----------------------------------------------------------------

tono=("" "" "" "") negrita="" tenue="" fin=""
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    mapfile -t _rgb < <(grep -Ev '^[[:space:]]*(#|$)' "$repo/_logo/colores" 2> /dev/null || true)
    for i in 0 1 2 3; do tono[i]=$'\e[38;2;'"${_rgb[i]:-255;255;255}"'m'; done
    negrita=$'\e[1m' tenue=$'\e[2m' fin=$'\e[0m'
fi

banner() {
    [[ -t 1 ]] || return 0
    local linea logo="$repo/_logo/navi-color.txt"
    if [[ -z "$fin" ]]; then
        logo="$repo/_logo/navi.txt"
    elif (( $(tput cols 2> /dev/null || echo 80) < 50 )); then
        logo="$repo/_logo/navi-compacto.txt"
    fi
    [[ -f "$logo" ]] || return 0
    local ancho=0 sangria pie="dotfiles · $nombre_equipo"
    while IFS= read -r linea; do
        linea="${linea//\$[1-4]/}"
        (( ${#linea} > ancho )) && ancho=${#linea}
    done < "$logo"
    sangria="$(margen "$ancho")"
    echo
    while IFS= read -r linea; do
        [[ "$logo" == *compacto* ]] && linea="${tono[3]}$linea"
        linea="${linea//\$1/${tono[0]}}" linea="${linea//\$2/${tono[1]}}"
        linea="${linea//\$3/${tono[2]}}" linea="${linea//\$4/${tono[3]}}"
        printf '%s%s%s\n' "$sangria" "$linea" "$fin"
        [[ -n "$fin" ]] && sleep 0.025
    done < "$logo"
    printf '%s%s%s%s\n\n' "$(margen ${#pie})" "$tenue" "$pie" "$fin"
}

raya() { # carácter, cuántos
    local s
    printf -v s '%*s' "$2" ""
    printf '%s' "${s// /$1}"
}

progreso() { # hechos, total, texto: una barra que se rehace en la misma línea
    [[ -t 1 ]] || return 0
    local llenas=$(( $1 * 24 / $2 ))
    printf '\r\e[K%s%s%s%s%s%s %s/%s  %s%s' "$(margen 44)" "${tono[3]}" "$(raya ━ "$llenas")" \
        "$tenue" "$(raya ─ $(( 24 - llenas )))" "$fin" "$1" "$2" "$tenue$3" "$fin"
}

paso_n=0 paso_total=0
paso() { # título de un paso de la instalación, numerado si se sabe cuántos hay
    paso_n=$(( paso_n + 1 ))
    local n=""
    (( paso_total )) && n="$paso_n/$paso_total  "
    printf '\n  %s%s━━ %s%s%s\n' "${tono[2]}" "$negrita" "$n" "$1" "$fin"
}
listo() { printf '  %s✔%s %s\n' "${tono[3]}" "$fin" "$1"; }
fallo() { printf '  %s✖ %s%s\n' "${tono[1]}" "$1" "$fin" >&2; }

columnas() { tput cols 2> /dev/null || echo 80; }

margen() { # ancho visible -> espacios para centrarlo en la terminal
    local m=$(( ($(columnas) - $1) / 2 ))
    (( m > 0 )) || m=0
    printf '%*s' "$m" ""
}

bloque() { # líneas centradas como un bloque alineado a la izquierda
    local l ancho=0 sangria
    for l in "$@"; do (( ${#l} > ancho )) && ancho=${#l}; done
    sangria="$(margen "$ancho")"
    for l in "$@"; do printf '%s%s\n' "$sangria" "$l"; done
}

titulo() { printf '%s%s%s%s%s\n' "$(margen ${#1})" "${tono[2]}" "$negrita" "$1" "$fin"; }
aviso() { printf '%s%s%s%s\n' "$(margen ${#1})" "${tono[1]}" "$1" "$fin" >&2; }

preguntar() { # texto, s|n por defecto -> verdadero si contesta que sí
    local respuesta opciones="[s/N]"
    [[ "$2" == s ]] && opciones="[S/n]"
    read -rp "$(margen $(( ${#1} + ${#opciones} + 2 )))${tono[2]}$1${fin} $opciones " respuesta || respuesta=""
    respuesta="${respuesta,,}"
    [[ -n "$respuesta" ]] || respuesta="$2"
    [[ "$respuesta" == s* || "$respuesta" == y* ]]
}

# --- paquetes -----------------------------------------------------------------

gestor() {
    local g
    for g in pacman apt-get dnf zypper; do
        command -v "$g" > /dev/null && { echo "$g"; return 0; }
    done
    return 0
}

en_repos() { # paquete: está en los repositorios oficiales del sistema
    case "$(gestor)" in
        pacman) pacman -Si "$1" ;;
        apt-get) apt-cache show "$1" ;;
        dnf) dnf info "$1" ;;
        zypper) zypper --quiet info "$1" | grep -q '^Name' ;;
        *) false ;;
    esac > /dev/null 2>&1
}

poner_paquetes() { # paquetes: sin actualizar el resto del sistema
    local root=()
    [[ "$(id -u)" -eq 0 ]] || root=(sudo)
    case "$(gestor)" in
        pacman) "${root[@]}" pacman -S --needed "$@" ;;
        apt-get) "${root[@]}" apt-get install "$@" ;;
        dnf) "${root[@]}" dnf install "$@" ;;
        zypper) "${root[@]}" zypper install "$@" ;;
    esac
}

con_systemd() { [[ -d /run/systemd/system ]]; }

sistema_fijo() { # distros donde /usr no se puede escribir: Silverblue, Bazzite, NixOS…
    [[ -e /run/ostree-booted || -e /etc/NIXOS ]]
}

anotar_motivo() { # paquete, motivo
    mkdir -p "$equipo"
    echo "$1 $(date +%F) $2" >> "$equipo/paquetes-motivos.txt"
}

hay() { # una comprobación de _requiere
    case "$1" in
        flatpak:*) flatpak info "${1#flatpak:}" > /dev/null 2>&1 ;;
        /*) [[ -e "$1" ]] ;;
        *) command -v "$1" > /dev/null ;;
    esac
}

faltan() { # app -> "comprobación [paquete]" de lo que no está
    [[ -f "$repo/$1/_requiere" ]] || return 0
    local que paquete
    while read -r que paquete; do
        [[ -z "$que" || "$que" == \#* ]] && continue
        hay "$que" || echo "$que${paquete:+ $paquete}"
    done < "$repo/$1/_requiere"
}

requisitos_instalador() {
    local falta=() p
    for p in stow git; do command -v "$p" > /dev/null || falta+=("$p"); done
    (( ${#falta[@]} )) || return 0
    aviso "Faltan programas que necesita el instalador:"
    local lineas=()
    command -v stow > /dev/null || lineas+=("stow   enlaza los archivos en tu carpeta personal")
    command -v git > /dev/null || lineas+=("git    clona los repos de algunas apps")
    bloque "${lineas[@]}"
    if [[ -z "$(gestor)" ]]; then
        aviso "Instálalos y vuelve a ejecutar el instalador."
        exit 1
    fi
    preguntar "¿Instalarlos con $(gestor)?" s || exit 1
    poner_paquetes "${falta[@]}"
    for p in "${falta[@]}"; do anotar_motivo "$p" "lo necesita install.sh"; done
}

# --- elegir apps --------------------------------------------------------------

ayudante_aur() {
    local h
    for h in paru yay; do
        command -v "$h" > /dev/null && { echo "$h"; return 0; }
    done
    return 0
}

id_gestor() { case "$(gestor)" in apt-get) echo apt ;; *) gestor ;; esac; }

resolver() { # fuentes de una línea de _requiere -> repo:, aur:, flatpak: o mano:<web>
    local g t general="" propio="" aur="" fp="" web=""
    g="$(id_gestor)"
    for t in "$@"; do
        case "$t" in
            pacman:* | apt:* | dnf:* | zypper:*) [[ "${t%%:*}" == "$g" ]] && propio="${t#*:}" ;;
            aur:*) aur="${t#aur:}" ;;
            flatpak:*) fp="${t#flatpak:}" ;;
            web:*) web="${t#web:}" ;;
            *) [[ -n "$general" ]] || general="$t" ;;
        esac
    done
    propio="${propio:-$general}"
    if [[ -n "$propio" ]] && en_repos "$propio"; then
        echo "repo:$propio"
    elif [[ "$g" == pacman && -n "$(ayudante_aur)" && -n "${aur:-$general}" ]] &&
        "$(ayudante_aur)" -Si --aur "${aur:-$general}" > /dev/null 2>&1; then
        echo "aur:${aur:-$general}"
    elif [[ -n "$fp" ]]; then
        echo "flatpak:$fp"
    else
        echo "mano:$web"
    fi
}

nombre_origen() {
    case "$1" in
        repo) id_gestor ;;
        aur) echo "AUR" ;;
        *) echo "$1" ;;
    esac
}

analizar() { # por cada app de $lista: desc, inst ("origen:paquete" …), mano, webs y app_marca
    local i que fuentes r nombre
    desc=() inst=() mano=() webs=() app_marca=()
    for i in "${!lista[@]}"; do
        progreso "$i" "${#lista[@]}" "${lista[i]##*/}"
        desc[i]="$(head -n1 "$repo/${lista[i]}/_descripcion" 2> /dev/null || true)"
        inst[i]="" mano[i]="" webs[i]=""
        while read -r que fuentes; do
            # shellcheck disable=SC2086
            r="$(resolver $fuentes)"
            nombre="${que#flatpak:}" nombre="${nombre##*/}"
            if [[ "$r" == mano:* ]]; then
                mano[i]+="${mano[i]:+, }$nombre"
                r="${r#mano:}"
                webs[i]+="$nombre${r:+ → $r}"$'\n'
            else
                inst[i]+="${inst[i]:+ }$r"
            fi
        done < <(faltan "${lista[i]}")
        if [[ -n "${inst[i]}" ]]; then app_marca[i]=1; else app_marca[i]=0; fi
    done
    progreso "${#lista[@]}" "${#lista[@]}" "listo"
    [[ -t 1 ]] && printf '\r\e[K'
    return 0
}

extra_de() { # fila -> $extra_plano y $extra_txt: qué pasa con la aplicación
    local t origenes=""
    if [[ -n "${mano[$1]}" && ( -z "${inst[$1]}" || app_marca[$1] -eq 0 ) ]]; then
        extra_plano="instálala a mano: ${mano[$1]}" extra_txt="${tono[1]}$extra_plano$fin"
    elif [[ -z "${inst[$1]}" ]]; then
        extra_plano="ya instalada" extra_txt="$tenue$extra_plano$fin"
    elif (( app_marca[$1] )); then
        for t in ${inst[$1]}; do
            t="$(nombre_origen "${t%%:*}")"
            [[ ", $origenes, " == *", $t, "* ]] || origenes+="${origenes:+, }$t"
        done
        extra_plano="+ instalar la app ($origenes)" extra_txt="${tono[3]}$extra_plano$fin"
        if [[ -n "${mano[$1]}" ]]; then
            extra_plano+=" · a mano: ${mano[$1]}"
            extra_txt+="${tono[1]} · a mano: ${mano[$1]}$fin"
        fi
    else
        extra_plano="solo la configuración" extra_txt="$tenue$extra_plano$fin"
    fi
}

otros_equipos() { # equipos con apps.txt, menos este
    local f
    for f in "$repo"/_*/apps.txt; do
        [[ -f "$f" && "$f" != "$equipo/apps.txt" ]] && basename "$(dirname "$f")" | cut -c2-
    done
    return 0
}

partir_ayuda() { # "a · b · c" -> líneas que caben en la terminal
    local trozo linea="" max=$(( $(columnas) - 4 ))
    local -a trozos
    IFS=$'\x1f' read -ra trozos <<< "${1// · /$'\x1f'}"
    for trozo in "${trozos[@]}"; do
        if [[ -n "$linea" ]] && (( ${#linea} + 3 + ${#trozo} > max )); then
            echo "$linea"
            linea="$trozo"
        else
            linea+="${linea:+ · }$trozo"
        fi
    done
    echo "$linea"
}

casillas() { # título, ayuda, "app" para la columna de la app; usa lista, desc y marca
    local cabecera="$1" ayuda="$2" modo="${3:-}"
    local n=${#lista[@]} pos=0 arriba=0 alto tecla resto i caja cursor nombre texto relleno
    local ancho ancho_desc ancho_extra limite sangria grupos=0 anterior lineas cuantas
    local resumen detalle primera=1 perfil="" perfil_i=-1 apps_perfil l
    local -a cats=() marco=() otros=() ayudas=()
    if [[ "$modo" == app ]]; then
        for i in "${!lista[@]}"; do
            cats[i]="$(categoria_de "${lista[i]}")"
            [[ "${cats[i]}" == "${cats[i-1]:-}" && $i -gt 0 ]] || grupos=$(( grupos + 1 ))
        done
        mapfile -t otros < <(otros_equipos)
        (( ${#otros[@]} )) && ayuda="${ayuda/ · Enter/ · p como otro equipo · Enter}"
        compgen -G "$repo/*/_vista" > /dev/null && ayuda="${ayuda/ · Enter/ · v ver cómo se ve · Enter}"
    fi
    tput smcup 2> /dev/null || true
    tput civis 2> /dev/null || true
    trap 'tput cnorm 2> /dev/null; tput rmcup 2> /dev/null; exit 130' INT TERM
    while true; do
        mapfile -t ayudas < <(partir_ayuda "$ayuda")
        ancho_desc=0 ancho_extra=0
        for i in "${!lista[@]}"; do
            (( ${#desc[i]} > ancho_desc )) && ancho_desc=${#desc[i]}
            if [[ "$modo" == app ]]; then
                extra_de "$i"
                (( ${#extra_plano} + 2 > ancho_extra )) && ancho_extra=$(( ${#extra_plano} + 2 ))
            fi
        done
        limite=$(( $(columnas) - 20 - ancho_extra ))
        (( limite < 10 )) && limite=10
        (( ancho_desc > limite )) && ancho_desc=$limite
        ancho=$(( 2 + 2 + 11 + 1 + ancho_desc + ancho_extra ))
        lineas=$(tput lines 2> /dev/null || echo 24)
        alto=$(( lineas - 8 - ${#ayudas[@]} - grupos ))
        (( alto < 3 )) && alto=3
        (( pos < arriba )) && arriba=$pos
        (( pos >= arriba + alto )) && arriba=$(( pos - alto + 1 ))
        sangria="$(margen "$ancho")"

        # se arma la pantalla entera y se pinta de una vez: sin parpadeo
        marco=()
        for (( i = (lineas - (n < alto ? n : alto) - grupos - 7 - ${#ayudas[@]}) / 2; i > 0; i-- )); do marco+=(""); done
        marco+=("$(margen ${#cabecera})${tono[2]}$negrita$cabecera$fin")
        for l in "${ayudas[@]}"; do marco+=("$(margen ${#l})$tenue$l$fin"); done
        marco+=("")
        if (( arriba > 0 )); then marco+=("$sangria  $tenue▲ hay más$fin"); else marco+=(""); fi
        anterior=""
        for (( i = arriba; i < n && i < arriba + alto; i++ )); do
            if [[ "$modo" == app && "${cats[i]}" != "$anterior" ]]; then
                marco+=("$sangria  ${tono[1]}── ${cats[i]} $(raya ─ $(( ancho - ${#cats[i]} - 6 )))$fin")
                anterior="${cats[i]}"
            fi
            cursor="  " nombre="${lista[i]##*/}"
            if (( i == pos )); then
                cursor="${tono[3]}▌$fin "
                printf -v nombre '%s%-11s%s' "$negrita" "$nombre" "$fin"
            else
                printf -v nombre '%-11s' "$nombre"
            fi
            if (( marca[i] )); then caja="${tono[3]}●$fin"; else caja="$tenue○$fin"; fi
            texto="${desc[i]}"
            (( ${#texto} > ancho_desc )) && texto="${texto:0:ancho_desc-1}…"
            relleno=$(( ancho_desc - ${#texto} ))
            (( marca[i] )) || texto="$tenue$texto$fin"
            extra_txt=""
            if [[ "$modo" == app ]]; then
                extra_de "$i"
                (( marca[i] )) || extra_txt="$tenue$extra_plano$fin"
            fi
            marco+=("$(printf '%s%s%s %s %s%*s%s' "$sangria" "$cursor" "$caja" "$nombre" "$texto" "$relleno" "" "${extra_txt:+  $extra_txt}")")
        done
        if (( arriba + alto < n )); then marco+=("$sangria  $tenue▼ hay más$fin"); else marco+=(""); fi
        cuantas=0
        for i in "${!lista[@]}"; do (( marca[i] )) && cuantas=$(( cuantas + 1 )); done
        resumen="$cuantas de $n elegidas${perfil:+ · como $perfil}"
        marco+=("" "$(margen ${#resumen})${tono[3]}$resumen$fin")
        # la descripción entera de la fila elegida, si en la lista no cabe
        detalle=""
        (( ${#desc[pos]} > ancho_desc )) && detalle="${desc[pos]}"
        (( ${#detalle} > $(columnas) - 4 )) && detalle="${detalle:0:$(columnas)-5}…"
        marco+=("$(margen ${#detalle})$tenue$detalle$fin")
        if [[ "$modo" == app && -f "$repo/${lista[pos]}/_vista" ]]; then
            marco+=("$(margen 26)${tono[1]}◆ pulsa v para verla antes$fin")
        else
            marco+=("")
        fi

        printf '\e[H'
        for l in "${marco[@]}"; do
            printf '%s\e[K\n' "$l"
            (( primera )) && sleep 0.008
        done
        printf '\e[J'
        primera=0

        IFS= read -rsn1 tecla || tecla=q
        if [[ "$tecla" == $'\e' ]]; then
            IFS= read -rsn2 -t 0.05 resto || resto=""
            tecla="$tecla$resto"
        fi
        case "$tecla" in
            $'\e[A' | k) (( pos > 0 )) && pos=$(( pos - 1 )) ;;
            $'\e[B' | j) (( pos < n - 1 )) && pos=$(( pos + 1 )) ;;
            $'\e[H' | g) pos=0 ;;
            $'\e[F' | G) pos=$(( n - 1 )) ;;
            " ") marca[pos]=$(( ! marca[pos] )) ;;
            i) [[ "$modo" == app && -n "${inst[pos]}" ]] && app_marca[pos]=$(( ! app_marca[pos] )) ;;
            a) for i in "${!lista[@]}"; do marca[i]=1; done ;;
            n) for i in "${!lista[@]}"; do marca[i]=0; done ;;
            p)
                (( ${#otros[@]} )) || continue
                perfil_i=$(( (perfil_i + 1) % ${#otros[@]} )) perfil="${otros[perfil_i]}"
                apps_perfil=" $(grep -Ev '^[[:space:]]*(#|$)' "$repo/_$perfil/apps.txt" | awk '{print $1}' | tr '\n' ' ') "
                for i in "${!lista[@]}"; do
                    [[ "$apps_perfil" == *" ${lista[i]##*/} "* ]] && marca[i]=1 || marca[i]=0
                done ;;
            v)
                [[ "$modo" == app && -f "$repo/${lista[pos]}/_vista" ]] || continue
                # vista previa a pantalla completa; cualquier tecla vuelve a la lista
                printf '\e[2J\e[H\n'
                (cd "$repo/${lista[pos]}" && bash _vista) || true
                printf '\n\n%s%sCualquier tecla para volver%s' "$(margen 27)" "$tenue" "$fin"
                IFS= read -rsn1 tecla || true
                printf '\e[2J' ;;
            "") break ;;
            q | $'\e') pos=-1; break ;;
        esac
    done
    tput cnorm 2> /dev/null || true
    tput rmcup 2> /dev/null || true
    trap - INT TERM
    (( pos >= 0 ))
}

repos_pendientes() { # apps -> nombre de cada repo de _repos.txt que falta en ~
    local app ruta url
    for app in "$@"; do
        [[ -f "$repo/$app/_repos.txt" ]] || continue
        while read -r ruta url; do
            [[ -z "$ruta" || "$ruta" == \#* || -d "$HOME/$ruta" ]] && continue
            basename "$ruta"
        done < "$repo/$app/_repos.txt"
    done
}

sistema_pendiente() { # apps o _equipo -> cuántos archivos de _sistema faltan o difieren
    local nombre dir archivo cuenta=0
    for nombre in "$@"; do
        dir="$repo/$nombre/_sistema"
        [[ -d "$dir" ]] || continue
        while IFS= read -r archivo; do
            cmp -s "$archivo" "/${archivo#"$dir/"}" 2> /dev/null || cuenta=$(( cuenta + 1 ))
        done < <(find "$dir" -type f)
    done
    echo "$cuenta"
}

paquetes_guardados() { # repos|aur -> paquetes de las listas del equipo que aquí faltan
    local guardada="$equipo/paquetes-$1.txt"
    [[ -f "$guardada" && "$(gestor)" == pacman ]] || return 0
    if [[ "$1" == repos ]]; then
        # solo los que existen en los repositorios de este sistema
        comm -12 <(comm -23 <(sort -u "$guardada") <(pacman -Qq | sort -u)) <(pacman -Slq | sort -u)
    else
        comm -23 <(sort -u "$guardada") <(pacman -Qq | sort -u)
    fi
}

identidad_git() { # crea ~/.config/git/usuario la primera vez
    local archivo="$HOME/.config/git/usuario" nombre="" correo="" sitio
    [[ -f "$archivo" ]] && return 0
    if [[ ! -t 0 ]]; then
        aviso "Pon tu nombre y correo de Git en $archivo"
        return 0
    fi
    titulo "Git necesita tu nombre y correo para los commits"
    read -rp "$(margen 40)Nombre: " nombre || true
    read -rp "$(margen 40)Correo: " correo || true
    if [[ -z "$nombre" || -z "$correo" ]]; then
        aviso "Sin nombre o correo; ponlos luego en $archivo"
        return 0
    fi
    mkdir -p "$(dirname "$archivo")"
    {
        printf '[user]\n\tname = %s\n\temail = %s\n' "$nombre" "$correo"
        if command -v gh > /dev/null; then
            for sitio in https://github.com https://gist.github.com; do
                printf '[credential "%s"]\n\thelper =\n\thelper = !%s auth git-credential\n' "$sitio" "$(command -v gh)"
            done
        fi
    } > "$archivo"
    titulo "Guardado en ${archivo/#$HOME/\~}"
}

poner_de() { # origen, paquetes: instala sin actualizar el resto del sistema
    local de="$1"
    shift
    case "$de" in
        repo) poner_paquetes "$@" ;;
        aur) "$(ayudante_aur)" -S --needed "$@" ;;
        flatpak)
            flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
            flatpak install --user flathub "$@" ;;
    esac
}

elegir() { # dos pantallas: qué apps y qué hacer; deja $elegidos y $hacer_* listos
    local i t o paquete actuales pendientes cuenta
    local -A por_origen=() motivo=()
    mapfile -t lista < <(apps_del_repo)
    titulo "Comprobando qué hay instalado…"
    analizar
    actuales=" $(apps_de_este_equipo | tr '\n' ' ') "
    marca=()
    for i in "${!lista[@]}"; do
        if [[ -f "$equipo/apps.txt" ]]; then
            [[ "$actuales" == *" ${lista[i]} "* ]] && marca[i]=1 || marca[i]=0
        else
            [[ -z "${inst[i]}${mano[i]}" ]] && marca[i]=1 || marca[i]=0
        fi
    done
    casillas "Elige qué instalar" \
        "↑↓ moverse · espacio elegir · i app o solo config · a todas · n ninguna · Enter seguir · q salir" app ||
        { echo "No se cambió nada."; exit 0; }
    elegidos=()
    for i in "${!lista[@]}"; do
        (( marca[i] )) || continue
        elegidos+=("${lista[i]}")
        (( app_marca[i] )) || continue
        for t in ${inst[i]}; do
            o="${t%%:*}" paquete="${t#*:}"
            [[ " ${por_origen[$o]:-} " == *" $paquete "* ]] || por_origen[$o]+="${por_origen[$o]:+ }$paquete"
            motivo[$paquete]="lo necesita la app ${lista[i]##*/}"
        done
    done
    if (( ${#elegidos[@]} == 0 )); then
        echo "No elegiste ninguna app; no se cambió nada."
        exit 0
    fi
    a_mano=""
    for i in "${!lista[@]}"; do (( marca[i] )) && a_mano+="${webs[i]}"; done
    if [[ -n "${por_origen[flatpak]:-}" ]] && ! command -v flatpak > /dev/null; then
        if en_repos flatpak; then
            por_origen[repo]+="${por_origen[repo]:+ }flatpak"
            motivo[flatpak]="lo necesitan ${por_origen[flatpak]}"
        else
            a_mano+="flatpak → https://flatpak.org/setup/"$'\n'
            unset 'por_origen[flatpak]'
        fi
    fi
    mkdir -p "$equipo"
    { echo "# una app por línea"; printf '%s\n' "${elegidos[@]##*/}"; } > "$equipo/apps.txt"

    # segunda pantalla: cada paso se puede quitar
    lista=() desc=() marca=() pasos=()
    for o in repo aur flatpak; do
        [[ -n "${por_origen[$o]:-}" ]] || continue
        lista+=("$(nombre_origen "$o")") pasos+=("paquetes:$o")
        if [[ "$o" == aur ]]; then
            desc+=("instalar con $(ayudante_aur): ${por_origen[$o]}")
        else
            desc+=("instalar: ${por_origen[$o]}")
        fi
    done
    lista+=("config") pasos+=(config) desc+=("enlazar y copiar la configuración de: ${elegidos[*]##*/}")
    pendientes="$(repos_pendientes "${elegidos[@]}" | paste -sd' ' -)"
    if [[ -n "$pendientes" ]]; then
        lista+=("repos") pasos+=(repos) desc+=("clonar: $pendientes")
    fi
    cuenta="$(sistema_pendiente "${elegidos[@]}" "$(basename "$equipo")")"
    if (( cuenta > 0 )) && ! sistema_fijo; then
        lista+=("sistema") pasos+=(sistema) desc+=("$cuenta archivos fuera de tu carpeta, con sudo")
    fi
    if [[ " ${elegidos[*]} " == *" animacion "* ]] && ! sistema_fijo; then
        lista+=("arranque") pasos+=(arranque) desc+=("poner la animación Navi al encender y al apagar, con sudo")
    fi
    for i in "${!lista[@]}"; do marca[i]=1; done
    # reinstalar lo que este equipo tenía: solo se ofrece, viene sin marcar
    guardados_repo=() guardados_aur=()
    mapfile -t guardados_repo < <(paquetes_guardados repos)
    [[ -n "$(ayudante_aur)" ]] && mapfile -t guardados_aur < <(paquetes_guardados aur)
    if (( ${#guardados_repo[@]} )); then
        lista+=("restaurar") pasos+=("restaurar:repo") marca+=(0)
        desc+=("reinstalar lo que tenía $nombre_equipo: ${#guardados_repo[@]} de $(gestor)")
    fi
    if (( ${#guardados_aur[@]} )); then
        lista+=("rest. AUR") pasos+=("restaurar:aur") marca+=(0)
        desc+=("reinstalar lo que tenía $nombre_equipo: ${#guardados_aur[@]} de AUR")
    fi
    if con_systemd; then
        lista+=("actualizar") pasos+=(sincronizar)
        desc+=("actualización automática: bajar los cambios de GitHub cada hora")
        if [[ "$actuales" == *" sincronizar "* ]]; then marca+=(1); else marca+=(0); fi
    fi
    casillas "Esto es lo que se va a hacer" \
        "↑↓ moverse · espacio quitar o poner · Enter empezar · q salir sin instalar" ||
        { titulo "No se instaló nada; tu elección quedó en _$nombre_equipo/apps.txt"; exit 0; }
    titulo "Guardado en _$nombre_equipo/apps.txt: ${elegidos[*]##*/}"

    hacer_config=0 hacer_repos=0 hacer_sistema=0 hacer_arranque=0
    # config y repos se hacen en un mismo paso
    local marcados=" " auto=0
    for i in "${!pasos[@]}"; do
        [[ "${pasos[i]}" != sincronizar ]] && (( marca[i] )) && marcados+="${pasos[i]} " paso_total=$(( paso_total + 1 ))
    done
    [[ "$marcados" == *" config "* && "$marcados" == *" repos "* ]] && paso_total=$(( paso_total - 1 ))
    for i in "${!pasos[@]}"; do
        (( marca[i] )) || continue
        case "${pasos[i]}" in
            paquetes:*)
                o="${pasos[i]#paquetes:}"
                paso "Instalando con $(nombre_origen "$o"): ${por_origen[$o]}"
                # shellcheck disable=SC2086
                if poner_de "$o" ${por_origen[$o]}; then
                    for paquete in ${por_origen[$o]}; do anotar_motivo "$paquete" "${motivo[$paquete]}"; done
                    listo "instalado"
                else
                    fallo "No se pudo instalar todo con $(nombre_origen "$o"); sigo con lo demás."
                fi ;;
            restaurar:repo)
                paso "Reinstalando lo que tenía $nombre_equipo"
                poner_paquetes "${guardados_repo[@]}" && listo "reinstalado" || fallo "No se pudo reinstalar todo; sigo." ;;
            restaurar:aur)
                paso "Reinstalando lo que tenía $nombre_equipo de AUR"
                "$(ayudante_aur)" -S --needed "${guardados_aur[@]}" && listo "reinstalado" ||
                    fallo "No se pudo reinstalar todo de AUR; sigo." ;;
            config) hacer_config=1 ;;
            repos) hacer_repos=1 ;;
            sistema) hacer_sistema=1 ;;
            arranque) hacer_arranque=1 ;;
            sincronizar)
                auto=1 elegidos+=(sincronizar)
                echo sincronizar >> "$equipo/apps.txt" ;;
        esac
    done
    (( auto )) || apagar_sincronizar
    return 0
}

apagar_sincronizar() { # quita el timer si estaba puesto
    local wants="$HOME/.config/systemd/user/timers.target.wants/dotfiles-sincronizar.timer"
    [[ -L "$wants" || -L "$HOME/.local/bin/dotfiles-sincronizar" ]] || return 0
    if command -v systemctl > /dev/null; then systemctl --user stop dotfiles-sincronizar.timer 2> /dev/null || true; fi
    rm -f "$wants"
    stow --dir="$repo" --target="$HOME" --no-folding --delete sincronizar
    listo "actualización automática apagada"
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
    stow --dir="$repo/$(dirname "$app")" --target="$HOME" "${opciones[@]}" --stow "$(basename "$app")"
}

copiar() { # app: del repo a ~; si pisa algo distinto, lo de antes va al respaldo
    local ruta padre
    while read -r ruta; do
        ruta="${ruta%/}"
        padre="$(dirname "$ruta")"
        # al actualizar, una copia que no cambió en el repo se queda como el programa la dejó
        if [[ -n "${DOTFILES_DESDE:-}" && -e "$HOME/$ruta" ]] &&
            git -C "$repo" diff --quiet "$DOTFILES_DESDE" HEAD -- "$1/_copias/$ruta"; then
            continue
        fi
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

enlaces() { # app, "poner" o "avisar": líneas "ruta destino" de _enlaces.txt, ambas relativas a ~
    [[ -f "$repo/$1/_enlaces.txt" ]] || return 0
    local ruta destino
    while read -r ruta destino; do
        [[ -z "$ruta" || "$ruta" == \#* ]] && continue
        [[ "$(readlink -f "$HOME/$ruta")" == "$(readlink -f "$HOME/$destino")" ]] && continue
        if [[ "$2" == avisar ]]; then
            echo "$1, falta el enlace: ~/$ruta -> ~/$destino"
        elif [[ ! -e "$HOME/$destino" ]]; then
            echo "no existe ~/$destino; no se enlaza ~/$ruta" >&2
        else
            [[ -e "$HOME/$ruta" || -L "$HOME/$ruta" ]] && apartar "$ruta"
            mkdir -p "$(dirname "$HOME/$ruta")"
            ln -s "$HOME/$destino" "$HOME/$ruta"
        fi
    done < "$repo/$1/_enlaces.txt"
}

# Archivos de fuera de ~. estado los lista; instalar los copia con sudo.
sistema() { # app: informa, no toca nada
    [[ -d "$repo/$1/_sistema" ]] || return 0
    local archivo destino
    while IFS= read -r archivo; do
        destino="/${archivo#"$repo/$1/_sistema/"}"
        cmp -s "$archivo" "$destino" 2> /dev/null && continue
        echo "$1, sistema falta o difiere: sudo install -Dm$(stat -c %a "$archivo") -o root -g root '$archivo' '$destino'"
    done < <(find "$repo/$1/_sistema" -type f | sort)
}

poner_sistema() { # app o _equipo: instala lo que difiere
    local nombre="$1" dir archivo destino modo tmp
    dir="$repo/$nombre/_sistema"
    [[ -d "$dir" ]] || return 0
    tmp=$(mktemp)
    {
        echo 'set -euo pipefail'
        while IFS= read -r archivo; do
            destino="/${archivo#"$dir/"}"
            if cmp -s "$archivo" "$destino" 2> /dev/null; then
                continue
            fi
            modo=$(stat -c %a "$archivo")
            printf 'install -Dm%s -o root -g root %q %q\n' "$modo" "$archivo" "$destino"
            printf 'echo %q\n' "sistema: $destino"
        done < <(find "$dir" -type f | sort)
    } >"$tmp"
    if ! grep -q '^install ' "$tmp"; then
        rm -f "$tmp"
        return 0
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        bash "$tmp"
    else
        sudo bash "$tmp" || aviso "No se pusieron los archivos de sistema de ${nombre##*/}; ./install.sh estado dice cuáles."
    fi
    rm -f "$tmp"
}

# La animación de arranque es de la app animacion. Si ya está puesta, no pide sudo.
aplicar_splash() {
    local apply="$repo/animacion/_sistema/usr/local/sbin/navi-splash-apply"
    local src="$repo/animacion/_sistema/usr/share/plymouth/themes/navi"
    local theme=/usr/share/plymouth/themes/navi stamp=/var/lib/navi/splash.stamp
    local cur fp
    [[ -f "$apply" && -d "$src" ]] || return 0
    if [[ -f "$theme/navi.script" && -f "$stamp" ]] && diff -rq "$src" "$theme" > /dev/null 2>&1; then
        cur=$(plymouth-set-default-theme 2> /dev/null || true)
        fp=$(find "$theme" -type f -exec sha256sum {} + | sort | sha256sum | cut -d' ' -f1)
        [[ "$cur" == navi && "$(cat "$stamp")" == "$fp" ]] && return 0
    fi
    if ! command -v plymouth-set-default-theme > /dev/null; then
        aviso "Para la animación de arranque hace falta Plymouth (paquete plymouth)."
        return 0
    fi
    local root=()
    [[ "$(id -u)" -eq 0 ]] || root=(sudo)
    echo "arranque: animación Navi"
    "${root[@]}" "$apply" || aviso "No se aplicó la animación de arranque."
}

instalar() { # "" o "adoptar"; usa $elegidos
    requisitos_instalador
    mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share"
    local app t
    local -a de_sistema=("${elegidos[@]}")
    # con apps sueltas solo se toca lo de esas apps, no lo del equipo
    (( apps_sueltas )) || de_sistema+=("$(basename "$equipo")")
    (( hacer_sistema )) && (( $(sistema_pendiente "${de_sistema[@]}") == 0 )) && hacer_sistema=0
    [[ " ${elegidos[*]} " == *" animacion "* ]] || hacer_arranque=0
    if sistema_fijo && (( hacer_sistema || hacer_arranque )); then
        aviso "Este sistema no deja escribir en /usr: me salto los archivos de sistema y la animación de arranque."
        hacer_sistema=0 hacer_arranque=0
    fi
    (( paso_total )) || paso_total=$(( (hacer_config || hacer_repos) + hacer_sistema + hacer_arranque ))
    if (( hacer_config || hacer_repos )); then
        paso "Configuración"
        for app in "${elegidos[@]}"; do
            if (( hacer_config )); then
                enlazar "$app" "$1"
                if [[ "$1" == adoptar ]]; then recoger_copias "$app"; else copiar "$app"; fi
            fi
            (( hacer_repos )) && repos "$app" clonar
            (( hacer_config )) && enlaces "$app" poner
            listo "${app##*/}"
        done
    fi
    if (( hacer_sistema )); then
        paso "Archivos de sistema (pide sudo)"
        for app in "${de_sistema[@]}"; do poner_sistema "$app"; done
    fi
    if (( hacer_arranque )); then
        paso "Animación de arranque"
        aplicar_splash
    fi
    if (( hacer_config )) && [[ " ${elegidos[*]} " == *" base "* ]]; then identidad_git; fi
    # recarga las unidades y arranca las que activan las apps elegidas en su _enlaces.txt
    if command -v systemctl > /dev/null && systemctl --user daemon-reload 2> /dev/null; then
        for app in "${elegidos[@]}"; do
            [[ -f "$repo/$app/_enlaces.txt" ]] || continue
            while read -r t _; do
                [[ "$t" == *.target.wants/* ]] && { systemctl --user start "${t##*/}" 2> /dev/null || true; }
            done < "$repo/$app/_enlaces.txt"
        done
    fi

    echo
    titulo "✔ Listo"
    [[ -d "$respaldo" ]] && bloque "Lo que estorbaba quedó en $respaldo"
    if [[ " ${elegidos[*]} " == *" animacion "* ]] && ! con_systemd; then
        bloque "Sin systemd, la animación al recargar la shell no arranca sola:" \
            "añade navi-intro-vigia a lo que tu escritorio lanza al iniciar sesión."
    fi
    if [[ " ${elegidos[*]} " == *" sincronizar "* && "$orden" != actualizar ]]; then
        bloque "Este equipo baja solo los cambios de GitHub cada hora." "Para bajarlos ya: dotfiles-sincronizar"
    fi
    if [[ -n "${a_mano:-}" ]]; then
        echo
        titulo "Falta instalar a mano:"
        mapfile -t _lineas < <(printf '%s' "$a_mano" | sort -u)
        bloque "${_lineas[@]}"
    fi
    return 0
}

motivos() { # nombres de paquetes-motivos.txt
    grep -Ev '^[[:space:]]*(#|$)' "$equipo/paquetes-motivos.txt" 2> /dev/null | awk '{print $1}' || true
}

sin_motivo() { # lo instalado a mano sin motivo anotado, y los motivos de algo que ya no está
    local base="$equipo/paquetes-base.txt" nombre instalado flatpaks=""
    command -v pacman > /dev/null || return 0
    command -v flatpak > /dev/null && flatpaks="$(flatpak list --app --columns=application)"
    instalado="$( { pacman -Qq 2> /dev/null; echo "$flatpaks"; } | sort -u)"
    # sin paquetes-base.txt no se sabe qué vino con el sistema: solo se miran los flatpaks
    while read -r nombre; do
        echo "instalado sin motivo: $nombre"
    done < <( { [[ -f "$base" ]] && pacman -Qqe 2> /dev/null | grep -Fvxf "$base"; echo "$flatpaks"; } |
        grep -v '^$' | grep -Fvxf <(motivos) || true)
    while read -r nombre; do
        echo "motivo de algo que no está instalado: $nombre"
    done < <(motivos | grep -Fvxf <(echo "$instalado") || true)
}

enlaces_rotos() { # enlaces de ~ que apuntan al repo a un archivo que ya no existe
    local enlace
    while IFS= read -r enlace; do
        [[ "$(readlink -m "$enlace")" == "$repo"/* ]] && echo "enlace roto: ~/${enlace#"$HOME/"}"
    done < <(find "$HOME" -xdev -xtype l -lname "*$(basename "$repo")/*" 2> /dev/null)
    return 0
}

quitar() { # deshace los enlaces de las apps; copias, repos y _sistema se quedan
    local app
    for app in "${elegidos[@]}"; do
        stow --dir="$repo/$(dirname "$app")" --target="$HOME" --no-folding --delete "$(basename "$app")"
        if [[ -f "$equipo/apps.txt" ]]; then
            awk -v a="${app##*/}" '$1 != a' "$equipo/apps.txt" > "$equipo/apps.txt.nuevo"
            mv "$equipo/apps.txt.nuevo" "$equipo/apps.txt"
        fi
        echo "quitada: ${app##*/} (sus copias en ~ se quedan)"
    done
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
        enlaces "$app" avisar
        sistema "$app"
    done
    sistema "$(basename "$equipo")"
    sin_motivo
    enlaces_rotos
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
hacer_config=1 hacer_repos=1 hacer_sistema=1 hacer_arranque=1
case "${1:-}" in
    adoptar | estado | recoger | elegir | quitar) orden="$1"; shift ;;
    actualizar) orden="$1" hacer_sistema=0 hacer_arranque=0; shift ;;
    -h | --help | ayuda) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
apps_sueltas=$(( $# > 0 ))
if [[ "$orden" == quitar ]] && (( ! apps_sueltas )); then
    echo "di qué apps quitar: ./install.sh quitar <apps>" >&2
    exit 1
fi
[[ "$orden" == estado || "$orden" == actualizar ]] || banner
if [[ "$orden" == elegir ]] || { [[ "$orden" == instalar && $# -eq 0 && ! -f "$equipo/apps.txt" ]]; }; then
    if [[ ! -t 0 ]]; then
        aviso "Elegir apps necesita una terminal; o pásalas: ./install.sh base zen"
        exit 1
    fi
    requisitos_instalador
    if [[ "$orden" == instalar ]]; then
        titulo "Este equipo ($nombre_equipo) todavía no tiene lista de apps."
        preguntar "¿Quieres elegir qué aplicaciones instalar?" s || exit 0
    fi
    elegir
    orden=instalar
    set --
fi
if (( $# > 0 )); then
    elegidos=()
    for app in "$@"; do elegidos+=("$(ruta_app "$app")"); done
else
    mapfile -t elegidos < <(apps_de_este_equipo)
fi
if (( ${#elegidos[@]} == 0 )); then
    aviso "_$nombre_equipo/apps.txt no existe o está vacío: ejecuta ./install.sh elegir"
    exit 1
fi
for app in "${elegidos[@]}"; do
    [[ ( "$app" != _* || "$app" == "_$nombre_equipo/"* ) && -d "$repo/$app" ]] ||
        { echo "no hay app '${app##*/}' en $repo ni en _$nombre_equipo" >&2; exit 1; }
done

case "$orden" in
    instalar | actualizar) instalar "" ;;
    adoptar) instalar adoptar ;;
    estado) estado ;;
    recoger) recoger ;;
    quitar) quitar ;;
esac
