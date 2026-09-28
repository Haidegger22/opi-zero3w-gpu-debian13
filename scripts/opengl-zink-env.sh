#!/bin/sh
# opengl-zink-env.sh — окружение для аппаратного desktop-OpenGL (zink поверх PowerVR Vulkan).
#
# Использование:
#     . scripts/opengl-zink-env.sh
#     DISPLAY=:0 glxinfo -B | grep -E 'renderer|version'
#     PVR_STRIP_DISABLE=1 <app>          # выключить слой на один процесс
#
# Требуется установленный слой VK_LAYER_PVR_strip (scripts/opengl-zink-install.sh).
# Проверено на Zero 3W 28.09.2026 (Debian 13 trixie, Mesa 25.0.7, DDK 24.2.6603887).
#
# Почему такой набор переменных:
#   PVR_FAKE_GS=1                  — включает слой (он подделывает geometryShader для zink);
#   GALLIUM_DRIVER/MESA_LOADER_..  — заставляем Mesa взять zink, а не llvmpipe;
#   LD_LIBRARY_PATH на системную   — вендорский стек в /usr/local перебивает системную Mesa
#     Mesa по ldconfig: без этого zink соберётся против вендорских библиотек;
#   VK_ICD_FILENAMES               — берём именно вендорский ICD PowerVR;
#   VK_LAYER_PATH + VK_INSTANCE_LAYERS — явное подключение слоя (нужно только если слой
#     установлен как explicit; при implicit достаточно PVR_FAKE_GS=1).

PVR_FAKE_GS=1
GALLIUM_DRIVER=zink
MESA_LOADER_DRIVER_OVERRIDE=zink
LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu
LIBGL_DRIVERS_PATH=/usr/lib/aarch64-linux-gnu/dri
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/img_icd.json
VK_LAYER_PATH=${XDG_DATA_HOME:-$HOME/.local/share}/vulkan/implicit_layer.d
VK_INSTANCE_LAYERS=VK_LAYER_PVR_strip

export PVR_FAKE_GS GALLIUM_DRIVER MESA_LOADER_DRIVER_OVERRIDE LD_LIBRARY_PATH
export LIBGL_DRIVERS_PATH VK_ICD_FILENAMES VK_LAYER_PATH VK_INSTANCE_LAYERS

[ -n "${DISPLAY:-}" ] || { DISPLAY=:0; export DISPLAY; }

echo "opengl-zink: окружение включено (PVR_FAKE_GS=1, зинк zink, ICD PowerVR)" >&2
