#!/bin/bash
# opengl-zink-install.sh — поставить (или снять) слой VK_LAYER_PVR_strip для аппаратного
# desktop-OpenGL на Zero 3W: zink (GL поверх Vulkan) + подделка geometryShader для
# вендорского драйвера PowerVR.
#
#   scripts/opengl-zink-install.sh              # клонировать/обновить, собрать, установить, проверить
#   scripts/opengl-zink-install.sh --check      # только проверить предпосылки и текущее состояние
#   scripts/opengl-zink-install.sh --uninstall  # снять слой
#
# Ставится только в домашний каталог: $XDG_DATA_HOME/vulkan/implicit_layer.d/
# Систему не затрагивает; откат — --uninstall или удаление двух файлов вручную.
set -u

SRC="${PVR_FEX_SRC:-$HOME/pvr-work/a733-powervr-fex}"
SRC_URL="${PVR_FEX_URL:-https://github.com/ayiejosh/a733-powervr-fex.git}"
SRC_BRANCH="${PVR_FEX_BRANCH:-trixie}"
LAYER_DIR="$SRC/gpu/vk-feature-strip"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/vulkan/implicit_layer.d"
MESA_VER=$(dpkg-query -W -f='${Version}' libgl1-mesa-dri 2>/dev/null || echo '?')

info() { printf '   %s\n' "$*"; }
die()  { printf '!! %s\n' "$*" >&2; exit 1; }

check_prereqs() {
    echo "=== предпосылки ==="
    command -v gcc >/dev/null || die "нет gcc (apt install build-essential)"
    info "gcc: $(gcc -dumpversion)"
    info "Mesa (libgl1-mesa-dri): $MESA_VER"

    # Mesa >= 26 несовместима: zink 26+ требует VK_EXT_robustness2.nullDescriptor,
    # которого у блоба нет; PVR_FAKE_R2=1 проходит проверку и падает в libVK_IMG.so.
    case "$MESA_VER" in
        2[6-9].*|[3-9][0-9].*) printf '   ⚠ ВНИМАНИЕ: Mesa %s — ждите падений zink. Рабочая версия 25.0.7.\n' "$MESA_VER" ;;
    esac

    if command -v vulkaninfo >/dev/null; then
        if vulkaninfo --summary 2>/dev/null | grep -qi powervr; then
            info "Vulkan: PowerVR найден ($(vulkaninfo --summary 2>/dev/null | grep -ai 'driverName' | head -1 | cut -d= -f2- | xargs))"
        else
            info "⚠ Vulkan: PowerVR не найден — сначала основной рецепт (README), потом этот слой"
        fi
    else
        info "⚠ vulkaninfo не установлен (apt install vulkan-tools) — пропускаю проверку Vulkan"
    fi

    echo "=== установленный слой ==="
    ls -la "$DEST"/VkLayer_PVR_strip.json "$DEST"/libVkLayer_PVR_strip.so 2>/dev/null | sed 's/^/   /' \
        || info "слой не установлен"

    # Коллизия имён: два манифеста с одним именем → лоадер выберет один и молча проигнорирует
    # переменные второго, слой будет «как будто ничего не делает».
    echo "=== чужие манифесты с тем же именем ==="
    local found=0 f
    for f in /usr/local/share/vulkan/implicit_layer.d/*.json /usr/share/vulkan/implicit_layer.d/*.json \
             /etc/vulkan/implicit_layer.d/*.json "$DEST"/*.json; do
        [ -f "$f" ] || continue
        grep -q 'VK_LAYER_PVR_strip' "$f" 2>/dev/null || continue
        # генерация старого слоя (PVR_STRIP_ENABLE) — это и есть конфликт
        if grep -q 'PVR_STRIP_ENABLE' "$f" 2>/dev/null; then
            info "КОНФЛИКТ (старая реализация): $f"; found=1
        else
            info "наш манифест: $f"
        fi
    done
    [ "$found" = 0 ] || info "→ убери старый манифест, иначе слой не заработает"
}

case "${1:-}" in
    --uninstall)
        if [ -x "$LAYER_DIR/install.sh" ]; then
            "$LAYER_DIR/install.sh" --uninstall
        else
            rm -f "$DEST/VkLayer_PVR_strip.json" "$DEST/libVkLayer_PVR_strip.so"
            info "удалены манифест и .so из $DEST"
        fi
        exit 0 ;;
    --check)
        check_prereqs
        exit 0 ;;
    "" ) ;;
    * ) die "неизвестный ключ: $1 (--check | --uninstall)" ;;
esac

check_prereqs

echo
echo "=== исходник слоя ==="
if [ -d "$SRC/.git" ]; then
    git -C "$SRC" fetch -q origin "$SRC_BRANCH" && git -C "$SRC" checkout -q "$SRC_BRANCH" \
        && git -C "$SRC" merge -q --ff-only "origin/$SRC_BRANCH" 2>/dev/null || true
    info "обновлён: $SRC ($(git -C "$SRC" log --oneline -1))"
else
    mkdir -p "$(dirname "$SRC")"
    git clone -q -b "$SRC_BRANCH" "$SRC_URL" "$SRC" || die "не удалось клонировать $SRC_URL"
    info "склонирован: $SRC ($(git -C "$SRC" log --oneline -1))"
fi
[ -f "$LAYER_DIR/install.sh" ] || die "нет $LAYER_DIR/install.sh — проверь ветку/путь"

echo
echo "=== сборка и установка ==="
( cd "$LAYER_DIR" && ./install.sh ) || die "install.sh слоя завершился с ошибкой"

echo
echo "=== проверка ==="
"$(dirname "$0")/opengl-zink-verify.sh" || info "проверка не прошла — смотри вывод выше"
echo
info "откат: $0 --uninstall   или   PVR_STRIP_DISABLE=1 <app> (на один процесс)"
