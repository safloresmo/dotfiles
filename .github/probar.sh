#!/usr/bin/env bash
# Prueba el instalador en un contenedor de cualquier distro, como root y con un HOME vacío.
# La corre GitHub en cada push; en local:
#   docker run --rm -v ~/dotfiles:/dot:ro fedora bash /dot/.github/probar.sh
set -euo pipefail

if command -v pacman > /dev/null; then pacman -Syu --noconfirm --needed stow git diffutils procps-ng which
elif command -v apt-get > /dev/null; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -yqq stow git procps
elif command -v dnf > /dev/null; then dnf install -yq stow git diffutils findutils procps-ng which
elif command -v zypper > /dev/null; then zypper -nq install stow git diffutils findutils procps which
fi > /dev/null

# una copia, para no ensuciar el repo con el _ci que crea el instalador
copia="$(mktemp -d)"
cp -a "$(dirname "$(readlink -f "$0")")/.." "$copia/dot"
cd "$copia/dot"
bash -n install.sh bootstrap.sh

export HOME="$copia/home" DOTFILES_EQUIPO=ci TERM=dumb
mkdir -p "$HOME"
./install.sh base fastfetch animacion < /dev/null

for f in .config/fish/user.fish .local/bin/navi-intro; do
    [[ -L "$HOME/$f" ]] || { echo "✖ falta el enlace ~/$f" >&2; exit 1; }
done
problemas="$(./install.sh estado base fastfetch animacion | grep -E ', (falta|sustituido|copia distinta|sistema falta)' || true)"
if [[ -n "$problemas" ]]; then
    echo "✖ estado no quedó limpio:" >&2
    echo "$problemas" >&2
    exit 1
fi
echo "✔ $(. /etc/os-release && echo "$PRETTY_NAME"): instala y enlaza bien"
