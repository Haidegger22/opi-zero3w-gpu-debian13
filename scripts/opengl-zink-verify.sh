#!/bin/bash
# opengl-zink-verify.sh — проверка аппаратного desktop-OpenGL (zink поверх PowerVR Vulkan).
#
#   scripts/opengl-zink-verify.sh
#
# Что показывает:
#   1) честную базовую линию — БЕЗ слоя и БЕЗ принудительного софта (как есть на стоке);
#   2) аппаратный рендерер со слоем (ожидаем zink Vulkan 1.3(PowerVR ...));
#   3) что слой действительно поднят лоадером (implicit-путь, только PVR_FAKE_GS=1);
#   4) работает ли ОКНО — на этой плате НЕ работает: glxgears падает с SIGABRT,
#      софтверный вариант при этом рисует ~168 FPS (это и есть доказательство, что дело в GL, а не в X11).
set -u
export DISPLAY="${DISPLAY:-:0}"
HERE=$(cd "$(dirname "$0")" && pwd)
rc=0

echo "=== 1) базовая линия: без слоя и без принудительного софта ==="
env -u PVR_FAKE_GS -u VK_LAYER_PATH -u VK_INSTANCE_LAYERS -u GALLIUM_DRIVER \
    -u MESA_LOADER_DRIVER_OVERRIDE -u LIBGL_ALWAYS_SOFTWARE -u LD_LIBRARY_PATH \
    glxinfo -B 2>&1 | grep -aE 'failed to create dri3|Vendor:|Device:|Accelerated:|renderer string|version string' | sed 's/^/   /'

echo
echo "=== 2) со слоем (полное окружение) ==="
# shellcheck disable=SC1090
. "$HERE/opengl-zink-env.sh" 2>/dev/null
out=$(glxinfo -B 2>/dev/null | grep -aE 'OpenGL renderer string|OpenGL version string')
if [ -z "$out" ]; then
    echo "   glxinfo не дал результата (нет X-дисплея?)"
    rc=1
else
    printf '%s\n' "$out" | sed 's/^/   /'
    if printf '%s' "$out" | grep -q 'zink Vulkan.*PowerVR'; then
        echo "   ✅ аппаратный рендерер включён (zink → PowerVR Vulkan), GL 2.1"
    else
        echo "   ⚠ рендерер не zink/PowerVR — слой не поднялся или Mesa собрана не та"
        rc=1
    fi
fi

echo
echo "=== 3) implicit-путь: достаточно ли одной PVR_FAKE_GS=1 ==="
# Kритично снять VK_LAYER_PATH/VK_INSTANCE_LAYERS: иначе проверяется explicit-путь,
# а не включение implicit-манифеста по переменной.
imp=$(env -u LD_LIBRARY_PATH -u VK_LAYER_PATH -u VK_INSTANCE_LAYERS \
      PVR_FAKE_GS=1 GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
      LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
      VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
      glxinfo -B 2>/dev/null | grep -a 'OpenGL renderer string')
echo "   $(printf '%s' "$imp" | cut -c1-120)"
if printf '%s' "$imp" | grep -q 'zink Vulkan.*PowerVR'; then
    echo "   ✅ при implicit-установке хватает одной переменной PVR_FAKE_GS=1"
else
    echo "   ℹ одной переменной не хватило — нужен explicit-вариант (VK_LAYER_PATH + VK_INSTANCE_LAYERS)"
fi
if command -v vulkaninfo >/dev/null; then
    if VK_LOADER_DEBUG=layer PVR_FAKE_GS=1 vulkaninfo --summary 2>&1 | grep -qi pvr_strip; then
        echo "   ✅ лоадер видит манифест VK_LAYER_PVR_strip"
    else
        echo "   ⚠ в отладке лоадера нет pvr_strip — проверь манифест и коллизию имён"
        rc=1
    fi
fi

echo
echo "=== 4) окно (ожидаемо НЕ работает) ==="
if command -v glxgears >/dev/null; then
    pkill -x glxgears 2>/dev/null; sleep 1
    env -u LD_LIBRARY_PATH PVR_FAKE_GS=1 GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
        LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
        LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
        VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
        VK_LAYER_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/vulkan/implicit_layer.d" \
        VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip \
        timeout -s KILL 12 glxgears -info >/tmp/zink-glxgears.out 2>/tmp/zink-glxgears.err
    code=$?
    fps=$(grep -acE 'frames in' /tmp/zink-glxgears.out)
    case "$code" in
        134) echo "   ⛔ окно со слоем: SIGABRT — аппаратный GL в окне не работает (нет DRI3/kmsro)" ;;
        139) echo "   ⛔ окно со слоем: SIGSEGV — аппаратный GL в окне не работает" ;;
        0|137) [ "$fps" -gt 0 ] && echo "   ✅ окно со слоем отработало ($fps интервалов FPS) — на нашей плате это не воспроизводится" \
                              || echo "   ⚠ окно закрыто по таймауту без FPS" ;;
        *)  echo "   ⚠ код возврата $code (см. /tmp/zink-glxgears.err)" ;;
    esac
    pkill -x glxgears 2>/dev/null
else
    echo "   glxgears не установлен (apt install mesa-utils) — пропуск"
fi

echo
if [ "$rc" = 0 ]; then
    echo "ИТОГ: аппаратный рендерер доступен (off-screen/EGL). Окно через GLX не работает — это стена, а не настройка."
else
    echo "ИТОГ: не всё сошлось, см. пункты выше. Диагностика: scripts/opengl-zink-install.sh --check"
fi
exit "$rc"
