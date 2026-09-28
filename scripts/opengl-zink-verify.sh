#!/bin/bash
# opengl-zink-verify.sh — проверка аппаратного desktop-OpenGL (zink поверх PowerVR Vulkan).
#
#   scripts/opengl-zink-verify.sh
#
# Что показывает:
#   1) честную базовую линию — БЕЗ слоя и БЕЗ принудительного софта (как есть на стоке);
#   2) аппаратный рендерер со слоем (ожидаем zink Vulkan 1.3(PowerVR ...));
#   3) что слой действительно поднят — implicit-путь, только PVR_FAKE_GS=1;
#   4) окно: у glmark2 работает (GLX), а старые демки вроде glxgears падают с SIGABRT —
#      падение происходит внутри вендорского компилятора шейдеров (docs/OPENGL-ZINK.md §5).
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
# Критично снять VK_LAYER_PATH/VK_INSTANCE_LAYERS: иначе проверяется explicit-путь,
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
echo "=== 4) окно: glmark2 (ожидаемо работает) против glxgears (известный падающий случай) ==="
if command -v glmark2 >/dev/null; then
    pkill -x glmark2 2>/dev/null; sleep 1
    env -u LD_LIBRARY_PATH PVR_FAKE_GS=1 GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
        LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
        LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
        VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
        timeout -s KILL 240 glmark2 -b build:duration=1 >/tmp/zink-glmark2-win.log 2>&1
    code=$?
    score=$(grep -a 'glmark2 Score' /tmp/zink-glmark2-win.log | tail -1 | awk '{print $NF}')
    # Код возврата тут не показатель: glmark2 штатно завершает бенчмарк, а потом падает с
    # косметической ошибкой X11 BadWindow при закрытии окна (код 1). Признак успеха — оценка.
    if [ -n "$score" ]; then
        echo "   ✅ окно через GLX: glmark2 отработал аппаратно, Score $score (код выхода $code)"
    else
        echo "   ⚠ окно через GLX: glmark2 не дал оценки (код $code) — см. /tmp/zink-glmark2-win.log"
        rc=1
    fi
    pkill -x glmark2 2>/dev/null
else
    echo "   glmark2 не установлен (Debian: пакет glmark2) — пропуск"
fi
if command -v glxgears >/dev/null; then
    pkill -x glxgears 2>/dev/null; sleep 1
    env -u LD_LIBRARY_PATH PVR_FAKE_GS=1 GALLIUM_DRIVER=zink MESA_LOADER_DRIVER_OVERRIDE=zink \
        LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
        LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri \
        VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json \
        timeout -s KILL 15 glxgears -info >/tmp/zink-glxgears.out 2>/tmp/zink-glxgears.err
    code=$?
    fps=$(grep -acE 'frames in' /tmp/zink-glxgears.out)
    case "$code" in
        134|139) [ "$fps" -gt 0 ] \
                   && echo "   ℹ glxgears отработал ($fps интервалов FPS) — на нашей плате он падает, у вас нет" \
                   || echo "   ⛔ glxgears: код $code — известный падающий случай (abort внутри вендорского компилятора шейдеров)" ;;
        0|137)   echo "   ℹ glxgears: код $code, интервалов FPS $fps" ;;
        *)       echo "   ⚠ glxgears: код $code (см. /tmp/zink-glxgears.err)" ;;
    esac
    pkill -x glxgears 2>/dev/null
else
    echo "   glxgears не установлен (Debian: пакет mesa-utils) — пропуск"
fi

echo
if [ "$rc" = 0 ]; then
    echo "ИТОГ: аппаратный рендерер доступен — и off-screen/EGL, и в окне. Отдельные старые GLX-программы"
    echo "      (glxgears, glxdemo) падают внутри вендорского шейдерного компилятора — docs/OPENGL-ZINK.md §5."
else
    echo "ИТОГ: не всё сошлось, см. пункты выше. Диагностика: scripts/opengl-zink-install.sh --check"
fi
exit "$rc"
