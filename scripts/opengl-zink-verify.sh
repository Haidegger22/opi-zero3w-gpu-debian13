#!/bin/bash
# opengl-zink-verify.sh — проверка аппаратного desktop-OpenGL (zink поверх PowerVR Vulkan).
#
#   scripts/opengl-zink-verify.sh
#
# Показывает три вещи:
#   1) как рендерит Mesa БЕЗ слоя (ожидаемо llvmpipe — это норма стока);
#   2) как рендерит СО слоем (ожидаем zink Vulkan 1.3(PowerVR ...));
#   3) что слой действительно загружен лоадером Vulkan.
set -u
export DISPLAY="${DISPLAY:-:0}"
HERE=$(cd "$(dirname "$0")" && pwd)
rc=0

renderer() { glxinfo -B 2>/dev/null | grep -aE 'OpenGL renderer string|OpenGL version string'; }

echo "=== 1) без слоя (базовая линия) ==="
env -u LD_LIBRARY_PATH -u PVR_FAKE_GS -u VK_INSTANCE_LAYERS -u VK_LAYER_PATH \
    LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
    glxinfo -B 2>/dev/null | grep -aE 'OpenGL renderer string|OpenGL version string' | sed 's/^/   /'
echo "   (llvmpipe здесь — ожидаемо: аппаратного GL-драйвера у Mesa для этого GPU нет)"

echo
echo "=== 2) со слоем (zink) ==="
# shellcheck disable=SC1090
. "$HERE/opengl-zink-env.sh" 2>/dev/null
out=$(renderer)
if [ -z "$out" ]; then
    echo "   glxinfo не дал результата (нет X-дисплея?)" | sed 's/^/   /'
    rc=1
else
    printf '%s\n' "$out" | sed 's/^/   /'
    if printf '%s' "$out" | grep -q 'zink Vulkan.*PowerVR'; then
        echo "   ✅ аппаратный desktop-OpenGL работает (zink → PowerVR Vulkan)"
    else
        echo "   ⚠ рендерер не zink/PowerVR — слой не загрузился или Mesa собрана не та"
        rc=1
    fi
fi

echo
echo "=== 3) загружен ли слой лоадером Vulkan ==="
if command -v vulkaninfo >/dev/null; then
    if VK_LOADER_DEBUG=layer PVR_FAKE_GS=1 vulkaninfo --summary 2>&1 | grep -qi pvr_strip; then
        echo "   ✅ лоадер поднял VK_LAYER_PVR_strip"
    else
        echo "   ⚠ в отладке лоадера нет pvr_strip — слой не подключён (проверь манифест и коллизию имён)"
        rc=1
    fi
else
    echo "   vulkaninfo не установлен (apt install vulkan-tools) — пропуск"
fi

echo
if [ "$rc" = 0 ]; then
    echo "ИТОГ: аппаратный desktop-OpenGL доступен (off-screen/EGL; GLX-окно невозможно — нет визуалов)."
else
    echo "ИТОГ: не всё сошлось, см. пункты выше. Диагностика: scripts/opengl-zink-install.sh --check"
fi
exit "$rc"
